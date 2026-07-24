#!/bin/bash
# This runs via Clore.ai's S6 overlay alongside its managed SSH server.
# Do NOT include SSH setup here — the Clore entrypoint handles it.
set -euo pipefail

log() { echo "[onstart] $*"; }

# Prefer our NVENC-enabled ffmpeg if installed
if [ -x /opt/ffmpeg/bin/ffmpeg ]; then
    export PATH="/opt/ffmpeg/bin:$PATH"
fi

mkdir -p /workspace/output /workspace/input /opt/ComfyUI/user/default/workflows

# --- Model download strategy ---
SKIP_MODEL_DOWNLOAD="${SKIP_MODEL_DOWNLOAD:-0}"
WAIT_FOR_MODELS="${WAIT_FOR_MODELS:-0}"
BACKGROUND_MODELS="${BACKGROUND_MODELS:-1}"

if [ "$WAIT_FOR_MODELS" = "1" ]; then
    BACKGROUND_MODELS=0
fi

if [ "$SKIP_MODEL_DOWNLOAD" = "1" ]; then
    log "SKIP_MODEL_DOWNLOAD=1 — skipping model downloads"
    echo "skipped" > /tmp/models-status
elif [ ! -x /opt/download-models.sh ]; then
    log "WARN: /opt/download-models.sh missing — skipping downloads"
    echo "missing" > /tmp/models-status
elif [ "$BACKGROUND_MODELS" = "0" ]; then
    log "Downloading models (blocking)..."
    echo "downloading" > /tmp/models-status
    /opt/download-models.sh && echo "ready" > /tmp/models-status || echo "failed" > /tmp/models-status
else
    log "Downloading models in background (ComfyUI will start now)..."
    echo "downloading" > /tmp/models-status
    nohup bash -c '
        if /opt/download-models.sh; then
            echo ready > /tmp/models-status
            echo "[onstart] Background model download finished"
        else
            echo failed > /tmp/models-status
            echo "[onstart] Background model download finished with errors"
        fi
    ' >/var/log/model-download.log 2>&1 &
    echo $! > /tmp/models-download.pid
    disown $! 2>/dev/null || true
fi

if [ "${INSTALL_EXTRA_DEPS:-0}" = "1" ]; then
    /opt/conda/bin/pip install -q sqlalchemy opencv-python-headless scikit-image matplotlib || true
fi

# --- VHS encoder: AV1 NVENC on Ada+ (compute >= 8.9), else H.264 NVENC ---
WF_JSON="/opt/ComfyUI/user/default/workflows/LTX-fixed.json"
if [ -f "$WF_JSON" ] && command -v nvidia-smi >/dev/null 2>&1; then
    CAP=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ' || echo "0.0")
    USE_AV1=$(awk -v c="$CAP" 'BEGIN { print (c+0 >= 8.9) ? "1" : "0" }')
    if [ "$USE_AV1" = "1" ]; then
        VHS_FMT="video/nvenc_av1-mp4"
    else
        VHS_FMT="video/nvenc_h264-mp4"
    fi
    /opt/conda/bin/python3 - "$WF_JSON" "$VHS_FMT" <<'PY' || true
import json, sys
path, fmt = sys.argv[1], sys.argv[2]
with open(path) as f:
    wf = json.load(f)
nchg = 0
for n in wf.get("nodes") or []:
    if n.get("type") != "VHS_VideoCombine":
        continue
    wv = n.get("widgets_values")
    if isinstance(wv, dict) and n.get("id") == 301:
        if wv.get("format") != fmt:
            wv["format"] = fmt
            nchg += 1
    elif isinstance(wv, dict) and "nvenc" in str(wv.get("format", "")):
        pass
with open(path, "w") as f:
    json.dump(wf, f, indent=2)
    f.write("\n")
print(f"[onstart] VHS format for node 301 -> {fmt} (changes={nchg})", flush=True)
PY
    if echo "$VHS_FMT" | grep -q nvenc; then
        ENC=$(echo "$VHS_FMT" | sed -n "s|video/nvenc_\(.*\)-mp4|\1_nvenc|p")
        if ! ffmpeg -hide_banner -loglevel error -f lavfi -i color=c=black:s=64x64:d=0.04 \
            -c:v "${ENC:-h264_nvenc}" -f null - 2>/dev/null; then
            log "NVENC encode probe failed for ${ENC} — falling back to software h264"
            VHS_FMT="video/h264-mp4"
        fi
    fi
    VHS_FMT="${COMFYUI_VHS_FORMAT:-$VHS_FMT}"
    log "GPU compute_cap=${CAP}; VHS format=${VHS_FMT}"
fi

if command -v ffmpeg >/dev/null 2>&1; then
    log "ffmpeg: $(command -v ffmpeg)"
    ffmpeg -hide_banner -encoders 2>/dev/null | grep -E 'av1_nvenc|h264_nvenc|hevc_nvenc' || log "WARN: no nvenc encoders visible (needs NVIDIA driver at runtime)"
fi

# --- VRAM / allocator knobs ---
if [ -n "${PYTORCH_CUDA_ALLOC_CONF:-}" ]; then
    export PYTORCH_CUDA_ALLOC_CONF
    log "PYTORCH_CUDA_ALLOC_CONF=$PYTORCH_CUDA_ALLOC_CONF"
fi

LOWVRAM_FLAG="--lowvram"
if [ "${COMFYUI_NO_LOWVRAM:-0}" = "1" ]; then
    LOWVRAM_FLAG=""
fi
EXTRA_ARGS="${COMFYUI_EXTRA_ARGS:-}"

log "Starting ComfyUI on 0.0.0.0:8188 (lowvram=${LOWVRAM_FLAG:-off})"
cd /opt/ComfyUI

# shellcheck disable=SC2086
exec /opt/conda/bin/python3 main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    --enable-cors-header \
    --disable-auto-launch \
    --disable-smart-memory \
    $LOWVRAM_FLAG \
    $EXTRA_ARGS \
    --output-directory /workspace/output \
    --input-directory /workspace/input
