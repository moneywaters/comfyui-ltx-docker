# ComfyUI LTX Docker Build — Progress State

## Session: 2026-07-18 (logo hang + first-boot reliability)

### Root causes of "stuck on ComfyUI logo"

1. **Models blocked UI start** — `start.sh` ran `/opt/download-models.sh` (~48GB) *before* launching ComfyUI. Hitting the URL during/after downloads still looked "stuck" because the server never came up until wget finished (or users hit a half-ready host).
2. **Missing custom nodes for LTX-fixed.json**
   - `AudioToFrameCount` → pack `dseditor/ComfyUI-ListHelper` (cnr_id `listhelper`) — was never installed
   - `LTXDirectorGuide` → pack `WhatDreamsCost/WhatDreamsCost-ComfyUI` — Koolook only ships namespaced `LTXDirector__koolook` and deliberately does *not* register bare `LTXDirectorGuide`
3. **Containerfile missing runtime tools** — no `wget`/`ffmpeg`/`curl` in the slim Containerfile, so downloads and video nodes could fail silently depending on base image contents.
4. **Vast `--ssh` overrides ENTRYPOINT** — still true; onstart-cmd must re-exec `/opt/start.sh`.

### Fixes shipped this session

| File | Change |
|------|--------|
| `start.sh` | Start ComfyUI immediately; download models in **background** by default. `SKIP_MODEL_DOWNLOAD=1`, `WAIT_FOR_MODELS=1`, CORS + no auto-launch |
| `download-models.sh` | Partial-file safety, size checks, skip-if-present, non-fatal per-file failures |
| `nodes.sh` | + `ComfyUI-ListHelper`, + `WhatDreamsCost-ComfyUI` (22 packs total) |
| `Containerfile` | wget/curl/ffmpeg/libsndfile + full GL/X libs; bake smoke-test; env defaults |
| `Dockerfile` | Kept in sync with Containerfile |
| `smoke-test.sh` | Fast verify: custom_nodes dirs + HTTP 200 + system_stats + required object_info types |
| `vast-smoke-launch.sh` | One-shot Vast launch with `SKIP_MODEL_DOWNLOAD=1` (no 48GB wait) |

### How to test WITHOUT 48GB downloads

```bash
# After image rebuild is on Docker Hub:
bash vast-smoke-launch.sh

# Once instance is running:
vastai execute <ID> 'bash /opt/smoke-test.sh'
# Expect: AudioToFrameCount + LTXDirectorGuide present, HTTP 200
```

Or manually:

```bash
vastai create instance <OFFER_ID> \
  --image moneywaters/comfyui-ltx:latest \
  --ssh --direct --disk 40 \
  --env '-p 22:22 -p 8188:8188 -e SKIP_MODEL_DOWNLOAD=1' \
  --onstart-cmd 'mkdir -p /var/run/sshd && /usr/sbin/sshd || true; export SKIP_MODEL_DOWNLOAD=1; exec /opt/start.sh'
```

### Full production launch (with models, background download → UI up first)

```bash
vastai create instance <OFFER_ID> \
  --image moneywaters/comfyui-ltx:latest \
  --ssh --direct --disk 100 \
  --env '-p 22:22 -p 8188:8188' \
  --onstart-cmd 'mkdir -p /var/run/sshd && /usr/sbin/sshd || true; exec /opt/start.sh'
```

ComfyUI should answer on :8188 within ~1–3 min of container start while models continue in `/var/log/model-download.log`. Status file: `/tmp/models-status` (`downloading`|`ready`|`failed`|`skipped`).

### Verification (2026-07-18) — PASSED without 48GB models

- GHA run `29634454609` for commit `d5f5b37` → success (~8 min)
- Vast instance `45223170` (Poland RTX 3060, Ryzen 5600X, `$0.061/hr`) with `SKIP_MODEL_DOWNLOAD=1`
- `bash /opt/smoke-test.sh` → **ALL CHECKS PASSED**
  - 2289 registered node types, 101 LTX backend types
  - `AudioToFrameCount`, `LTXDirectorGuide`, `LTXDirector__koolook`, `VHS_VideoCombine` present
  - `models-status=skipped`
  - ComfyUI 0.28.0, PyTorch 2.5.1+cu124, frontend package 1.45.21 (matches required)
  - HTTP `/` 200, WebSocket `/ws` connected
  - Workflow library includes `LTX-fixed.json`
- Instance destroyed after smoke test to save credit

UI URL during test: `http://91.150.160.38:10962/` (direct mapped port)

### CPU / host warnings (still apply)

- PyTorch 2.5.1 needs **AVX2** — avoid Pentium Gold / Celeron hosts
- Prefer RTX 3060+ / 4060+ as a CPU-age proxy
- Vast SSH proxy is slow — use direct IP:port from `--raw`

---

## Prior session: 2026-07-16

### What was accomplished
- LTX.json cleaned → LTX-fixed.json (Note nodes stripped)
- GHA builds Containerfile → moneywaters/comfyui-ltx:latest
- NZ RTX 3060 Laptop instance verified 2250 node types, 0 import errors (before ListHelper/WhatDreamsCost fixes)
- Missing types documented: LTXDirectorGuide, AudioToFrameCount (now fixed)

### Artifacts
- `/Users/asan/comfyui-ltx-docker/` — source of truth
- `workflow/LTX-fixed.json` — baked into image at `/opt/ComfyUI/user/default/workflows/LTX-fixed.json`
