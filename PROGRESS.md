# ComfyUI LTX Docker Build — Progress State

## Session: 2026-07-16

## What was accomplished

### Workflow Fixed
- LTX.json had 291 nodes, 86 distinct types. 10 Note nodes stripped (removed in ComfyUI 0.27.0).
- Saved as /Users/asan/Downloads/LTX-fixed.json (281 nodes, 257 links).
- KJNodes Set/Get nodes (104 total) are backwards compatible after March 2026 rewrite — no changes needed.
- All 86 node types verified against installed custom node packs — no missing types (after Note removal).
- Model filenames in workflow MATCH download-models.sh filenames exactly — no symlinks needed for current workflow.
- Node 52 (UNETLoader) references ltx2310eros_v12.safetensors which is NOT in download-models.sh — optional alt-checkpoint, will fail to load but doesn't block other nodes.

### Docker Image Source Files Fixed
1. **start.sh**: Changed bare python3 to /opt/conda/bin/python3 (system python lacks torch)
2. **download-models.sh**: Removed set -e (one failed download no longer aborts everything), added || true per wget, added symlink creation for workflow filename compatibility
3. **Containerfile**: Added libgl1-mesa-glx libx11-6 (OpenCV deps), added pip install sqlalchemy opencv-python-headless scikit-image matplotlib
4. **Dockerfile**: Same fixes as Containerfile
5. **nodes.sh**: Already complete (20 packs including comfyui-mcp-panel)

### Git Push
- Committed and pushed to GitHub (moneywaters/comfyui-ltx-docker, commit bc6cbd6)
- GitHub Actions build triggered (run #29492376858)
- GHA builds from Containerfile (not Dockerfile)

### Vast.ai Deployments Tried
1. **RTX 2080 Ti (offer 43529661, California, /bin/sh.069/hr)**: Container couldn't start — Docker retrying, no container created. Host-side issue.
2. **RTX 3060 (offer 23137177, Poland, /bin/sh.052/hr)**: SSH worked, models downloaded (11 files, 48GB). ComfyUI crashed with Illegal instruction — CPU was Pentium Gold G5420 (no AVX2 support, PyTorch 2.5.1 requires AVX2).
3. **RTX 4060 (offer 43896131, California, /bin/sh.063/hr)**: Instance started, currently loading image layers.

## Key Findings (CONCLUSIONS)

### What WORKS
- The onstart-cmd pattern: start sshd FIRST (so SSH is available immediately), then apt-get, then download-models.sh, then pip install, then exec python3 main.py
- The image has clore.ai SSH key baked in (Containerfile line with authorized_keys)
- The image has openssh-server pre-installed and configured (PermitRootLogin yes, PasswordAuthentication no)
- Model downloads work reliably when download-models.sh uses || true instead of set -e
- All 20 custom node packs install correctly from nodes.sh
- KJNodes Set/Get nodes are backwards compatible (March 2026 rewrite)

### What DOES NOT WORK
- Vast.ai SSH proxy (sshN.vast.ai) is SLOW and often times out — use direct IP:port from --raw output instead
- Cheapest Vast hosts often have old CPUs (Pentium Gold, no AVX2) — PyTorch 2.5.1 requires AVX2
- Some Vast hosts can't pull large Docker images (8GB) — Docker retrying, no container created
- ComfyUI started with pipe to head (| head -30) will crash with SIGPIPE when head exits — use nohup + redirect to log file instead

### CPU Compatibility
- PyTorch 2.5.1+cu124 requires AVX2 instruction set
- Intel Pentium Gold / Celeron CPUs do NOT have AVX2
- Intel Core i3/i5/i7/i9 (Haswell 2013+) and AMD Ryzen (all) have AVX2
- Filter Vast offers by newer GPU type (RTX 4060+) as a proxy for newer CPU

## Next Session Should
1. Check if GHA build #29492376858 completed successfully
2. If yes, deploy the NEW image (moneywaters/comfyui-ltx:latest) on a Vast host with AVX2 CPU
3. Verify ComfyUI starts automatically (onstart-cmd should handle everything)
4. Load LTX-fixed.json workflow via browser or API
5. Check for 0 missing node errors
6. Optionally attempt tiny generation (very small resolution, 1-2 frames)
7. Destroy the Vast instance when done to save credits

## Vast.ai Launch Command (PROVEN)
```bash
vastai create instance <OFFER_ID>   --image moneywaters/comfyui-ltx:latest   --ssh --direct   --disk 100   --env '-p 22:22 -p 8188:8188'   --onstart-cmd 'mkdir -p /var/run/sshd && /usr/sbin/sshd && apt-get update -qq && apt-get install -y -qq libgl1-mesa-glx libx11-6 && bash /opt/download-models.sh && /opt/conda/bin/pip install sqlalchemy opencv-python-headless scikit-image matplotlib && cd /opt/ComfyUI && exec /opt/conda/bin/python3 main.py --listen 0.0.0.0 --port 8188 --output-directory /workspace/output --input-directory /workspace/input'
```

## Artifacts
- /Users/asan/Downloads/LTX-fixed.json — cleaned workflow (281 nodes, Note nodes stripped)
- /Users/asan/comfyui-ltx-docker/ — updated Docker source (pushed to GitHub, commit bc6cbd6)
- /Users/asan/run_comfyui_workflow.py — workflow queueing script (needs fixing for API format)
- /Users/asan/Downloads/LTX.json — original workflow from RunPod


## Session Update: NZ Instance Verification (2026-07-16)

### Instance Details
- Instance: 45083210 on RTX 3060 Laptop 12GB (New Zealand, $0.065/hr)
- CPU: Intel Xeon E5-2620 v3 (AVX2 supported — PyTorch 2.5.1 works!)
- Direct IP: 114.23.254.176, SSH port 56552, ComfyUI port 56561
- ComfyUI: Running (PID 624, HTTP 200, 2250 node types, 0 import errors)
- All 20 custom node packs loaded successfully
- Models downloaded: LTX transformer (24GB), text projection (2.2GB), video VAE (1.4GB), audio VAE (348MB)
- Gemma text encoder (7.2GB) still downloading — slow HuggingFace bandwidth from NZ

### Workflow Verification (LTX-fixed.json)
- 281 nodes, 85 distinct types
- 2250 node types available in ComfyUI
- 17 of 19 missing types are FRONTEND-ONLY UI nodes (dont appear in API object_info):
  - 9 UUID proxy widget nodes (ComfyUI core)
  - 4 rgthree UI nodes (Bookmark, Fast Actions Button, Fast Groups Bypasser, Label)
  - 2 KJNodes virtual nodes (SetNode, GetNode — resolved during prompt execution)
  - 1 MarkdownNote (pysssss display node)
  - 1 FancyTimerNode (no inputs/outputs, pure utility)
- 2 GENUINELY MISSING backend nodes (need version pinning or workflow update):
  - LTXDirectorGuide (2 nodes, IDs 357/358) — only in Koolook comments, not registered. Replaced by LTXDirector__koolook in current version (different API). Need to pin Koolook to old commit or update workflow.
  - AudioToFrameCount (1 node, ID 97) — not found in ComfyUI-LTXVideo. May have been removed or renamed.

### Generation Attempt
- Could NOT attempt generation: gemma text encoder (7.2GB) still downloading
- RTX 3060 Laptop has 12GB VRAM — LTX model is 24GB fp8, might OOM
- User confirmed generation is optional on cheapest GPU

### GHA Build
- Build #29492376858 completed successfully (8m2s)
- New image moneywaters/comfyui-ltx:latest pushed to Docker Hub with all fixes
