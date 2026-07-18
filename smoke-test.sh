#!/bin/bash
# Fast verification WITHOUT downloading ~48GB of models.
# Usage (inside container or via SSH):
#   bash /opt/smoke-test.sh
#   bash /opt/smoke-test.sh http://127.0.0.1:8188
set -euo pipefail

BASE="${1:-http://127.0.0.1:8188}"
FAIL=0

ok()   { echo "  PASS  $*"; }
bad()  { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }
info() { echo "  info  $*"; }

echo "=== ComfyUI LTX smoke test against $BASE ==="

# 1. Custom node packs on disk
echo "-- custom_nodes on disk --"
REQUIRED_DIRS=(
  ComfyUI-Manager
  ComfyUI-LTXVideo
  ComfyUI-KJNodes
  ComfyUI-Koolook
  ComfyUI-ListHelper
  WhatDreamsCost-ComfyUI
  ComfyUI-VideoHelperSuite
  comfyui-mcp-panel
  rgthree-comfy
)
for d in "${REQUIRED_DIRS[@]}"; do
  if [ -d "/opt/ComfyUI/custom_nodes/$d" ]; then
    ok "dir $d"
  else
    bad "missing dir $d"
  fi
done

# 2. HTTP readiness (retries — first boot can take a while loading nodes)
echo "-- HTTP readiness --"
READY=0
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 "$BASE/" 2>/dev/null || echo 000)
  if [ "$code" = "200" ]; then
    READY=1
    ok "GET / -> 200 (attempt $i)"
    break
  fi
  sleep 5
done
if [ "$READY" != "1" ]; then
  bad "ComfyUI never returned HTTP 200 at $BASE/ (last=$code)"
  echo "=== RESULT: FAIL ($FAIL) — server not up ==="
  exit 2
fi

# 3. system_stats
echo "-- /system_stats --"
if curl -sf --max-time 30 "$BASE/system_stats" > /tmp/system_stats.json; then
  ok "system_stats reachable"
  python3 - <<'PY' || bad "system_stats parse"
import json
d=json.load(open("/tmp/system_stats.json"))
sysinfo=d.get("system", d)
print("  info  comfy:", sysinfo.get("comfyui_version") or sysinfo.get("comfyui"))
print("  info  pytorch:", sysinfo.get("pytorch_version") or sysinfo.get("pytorch"))
devs=d.get("devices") or []
for dev in devs:
    print("  info  device:", dev.get("name"), "vram_free=", dev.get("vram_free"), "vram_total=", dev.get("vram_total"))
PY
else
  bad "system_stats unreachable"
fi

# 4. Critical node types for LTX-fixed.json
echo "-- required node types in /object_info --"
# object_info can be huge; stream-filter with python
if curl -sf --max-time 180 "$BASE/object_info" > /tmp/object_info.json; then
  ok "object_info downloaded ($(wc -c </tmp/object_info.json) bytes)"
  python3 - <<'PY' || true
import json, sys
hard = [
    "AudioToFrameCount",       # ComfyUI-ListHelper
    "LTXDirectorGuide",        # WhatDreamsCost-ComfyUI
    "VHS_VideoCombine",        # VideoHelperSuite
]
soft = [
    "LTXDirector__koolook",    # ComfyUI-Koolook (nice-to-have; workflow also has bare LTXDirectorGuide)
    "SetNode",                 # KJNodes virtual
    "GetNode",
]
info = json.load(open("/tmp/object_info.json"))
types = set(info.keys())
print(f"  info  total registered types: {len(types)}")
missing = []
for n in hard:
    if n in types:
        print(f"  PASS  node type present: {n}")
    else:
        print(f"  FAIL  node type MISSING: {n}")
        missing.append(n)
for n in soft:
    if n in types:
        print(f"  PASS  node type present: {n}")
    else:
        print(f"  info  optional/virtual node not in object_info: {n}")
# At least some LTXVideo backend nodes must load
ltx_backend = [t for t in types if t.startswith("LTXV") or t.startswith("LTX")]
if ltx_backend:
    print(f"  PASS  LTX backend types loaded ({len(ltx_backend)})")
else:
    print("  FAIL  no LTX* backend node types found")
    missing.append("LTX*")

# LTX family soft check
ltx = sorted(t for t in types if "LTX" in t or "ltx" in t)
print(f"  info  LTX-related types ({len(ltx)}): {', '.join(ltx[:25])}{'...' if len(ltx)>25 else ''}")
open("/tmp/smoke_missing.txt","w").write("\n".join(missing))
sys.exit(1 if missing else 0)
PY
  if [ -s /tmp/smoke_missing.txt ]; then
    FAIL=$((FAIL + $(wc -l </tmp/smoke_missing.txt)))
  fi
else
  bad "object_info unreachable or timed out"
fi

# 5. Import error scan via /object_info is enough; also check Manager if present
echo "-- models status file --"
if [ -f /tmp/models-status ]; then
  info "models-status=$(cat /tmp/models-status)"
else
  info "no /tmp/models-status (entrypoint may have been overridden)"
fi

echo "-- ffmpeg / NVENC --"
if command -v ffmpeg >/dev/null 2>&1; then
  info "ffmpeg=$(command -v ffmpeg)"
  if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q av1_nvenc; then
    ok "av1_nvenc encoder present in ffmpeg build"
  else
    bad "av1_nvenc missing from ffmpeg (image build should ship BtbN NVENC ffmpeg)"
  fi
  if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q h264_nvenc; then
    ok "h264_nvenc encoder present"
  else
    info "h264_nvenc not listed (may still work once driver libs mount)"
  fi
else
  bad "ffmpeg not on PATH"
fi

echo "-- lowvram / fp8 fix --"
if [ -f /opt/comfyui-fixes/fp8_embed_fix.py ]; then
  ok "fp8_embed_fix.py present"
else
  bad "fp8_embed_fix.py missing"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "=== RESULT: ALL CHECKS PASSED ==="
  exit 0
else
  echo "=== RESULT: $FAIL FAILURE(S) ==="
  exit 1
fi
