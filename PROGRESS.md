# ComfyUI LTX Docker Build — Progress State

## Clore custom image (preferred path) — 2026-07-26

See **[CLORE.md](./CLORE.md)** for full deploy docs.

**Root cause of `mon_container=0`:** image lost official Clore PID1
(`CMD bash -c /etc/supervisor/init.sh`) and/or openssh, so sshd never ran.

**Fix (this session):**

| Change | Why |
|--------|-----|
| `CMD ["bash","-c","/etc/supervisor/init.sh"]` explicit | Match `cloreai/jupyter`; mon_container + reverse SSH |
| Re-install `openssh-server` + `supervisor` | Survive apt churn |
| conf.d: `sshd` + `comfyui` + `delegated_entrypoint` only | Do not replace official `init.sh` |
| `/opt/ensure-clore-ssh.sh` build check | Fail the image build if SSH contract is broken |
| `EXPOSE 22 8188` | Clore order: `22/tcp` + `8188/http` |

Deploy image: `moneywaters/comfyui-ltx:latest` with ports **22/tcp + 8188/http**,
`SSH_PASSWORD` / `SSH_KEY`, `autossh_entrypoint=true`.

## Fallback: install on a *standard* Clore image

If custom image still fails on a host, order `cloreai/jupyter:ubuntu24.04-v2`
then:

```bash
# On the pod (root):
curl -fsSL https://raw.githubusercontent.com/moneywaters/comfyui-ltx-docker/main/install-on-clore.sh | bash

# Skip ~45GB models for a quick UI smoke test:
SKIP_MODEL_DOWNLOAD=1 curl -fsSL https://raw.githubusercontent.com/moneywaters/comfyui-ltx-docker/main/install-on-clore.sh | bash
```

Order: ports `22/tcp` + `8188/http`, `autossh_entrypoint: true`, your `ssh_key`.


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

### Pod selection: **download speed first** (models ~48GB)

`select-vast-offer.py` ranks offers primarily by `inet_down` (Mbps).

| Link speed | ~50GB model pull (rough) |
|------------|---------------------------|
| 200 Mbps   | ~30+ min                  |
| 1000 Mbps  | ~7 min                    |
| 3000+ Mbps | ~2 min                    |
| 8000 Mbps  | under 1 min               |

**Full launch (models download)** — requires fast DL:
```bash
bash vast-full-launch.sh
# or raise the floor:
MIN_DL=2000 MAX_DPH=0.30 bash vast-full-launch.sh
```
Defaults: `inet_down>=1000`, disk 100GB, `BACKGROUND_MODELS=1` (UI first).

**Smoke (no models)** — still wants decent DL for the ~8GB image pull:
```bash
bash vast-smoke-launch.sh
# Once running (SSH):
bash /opt/smoke-test.sh
```

Manual full create (if you already picked a fast offer id):
```bash
vastai create instance <OFFER_ID> \
  --image moneywaters/comfyui-ltx:latest \
  --ssh --direct --disk 100 \
  --env '-p 22:22 -p 8188:8188' \
  --onstart-cmd 'mkdir -p /var/run/sshd && /usr/sbin/sshd || true; exec /opt/start.sh'
```

ComfyUI answers on :8188 within ~1–3 min while models continue in `/var/log/model-download.log`. Status: `/tmp/models-status` (`downloading`|`ready`|`failed`|`skipped`).

### Image hardening (2026-07-18 later) — NVENC / 15s / fp8 / lowvram

| Change | Detail |
|--------|--------|
| **NVENC ffmpeg** | BtbN `linux64-gpl` build at `/opt/ffmpeg` with `av1_nvenc` + `h264_nvenc` |
| **VHS format** | `start.sh` picks `video/nvenc_av1-mp4` if GPU compute ≥ 8.9 (Ada/40xx+), else `video/nvenc_h264-mp4` (30xx). Override: `COMFYUI_VHS_FORMAT` |
| **15s workflow** | Director 15s / 361f @ 24fps; res 768×768; looping temporal tiles 40/16; primary sampler 6 steps |
| **fp8 path** | `/opt/comfyui-fixes/fp8_embed_fix.py` casts Float8 embedding weights before `index_select` (keeps Gemma on GPU) |
| **lowvram** | `main.py --lowvram --disable-smart-memory` + `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`. Disable lowvram: `COMFYUI_NO_LOWVRAM=1` |

Re-optimize workflow anytime: `python3 optimize_workflow_15s.py --seconds 15 --width 768`

### Full model + generation (2026-07-18) — LTX-fixed.json only


- Instance `45223843` RTX 3090 (Michigan), high `inet_down`, disk 100GB
- Models downloaded to `/tmp/models-status=ready` (13 safetensors, ~45GB+)
- Workflow: **only** bundled `LTX-fixed.json` (UI→API convert + UE/Get-Set patches)
- Inputs: `asan.png` (Director timeline), plus `A.mp4` / `BaseScene (1).png` as named in graph
- **SUCCESS** prompt `10cd3b5b-f698-4009-a6ac-f7a2eb2f21c3` → `LTX2_3_00002-audio.mp4` (~641KB)
- Saved locally: `/Users/asan/Downloads/ltx_full_run_LTX2_3_00002-audio.mp4`

Hardening lessons from the full run (bake into image later):
1. **fp8 Gemma**: DualCLIPLoader `device=cpu` avoids `index_select_cuda` Float8 error on PyTorch 2.5.1
2. **VHS encode**: workflow default `video/nvenc_av1-mp4` fails without `av1_nvenc` — use `video/h264-mp4`
3. **VRAM**: full `LTXVLoopingSampler` HR path OOMs on 24GB; first-stage path works with `--lowvram` + reduced frames; 48GB+ GPU preferred for full graph
4. API conversion must re-apply Use Everywhere CLIP links and EMPTY_LATENT → DirectorGuide

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
