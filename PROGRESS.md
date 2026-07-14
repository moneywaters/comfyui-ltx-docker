# ComfyUI LTX Docker Build — Progress State

## Session: 2026-07-14

## What we're doing
Building a self-contained Docker image on Vast.ai (GTX 1080 Ti, $0.068/hr) that has:
- ComfyUI v0.27.0
- 20 custom nodes (all verified URLs from nodes.txt)
- 11 models (~25GB) — base LTX model, VAEs, text encoders, LoRAs
- All pip deps (kornia==0.7.3, piexif, segment-anything, etc.)
- Fixed workflow (LTXDirector → LTXDirector__koolook)

## Current Vast instance
- **Instance ID**: 44743370
- **Offer**: 41660413 (GTX 1080 Ti, 82GB disk, $0.068/hr, South Korea)
- **Status**: Building — onstart script running
- **Auto-destruct**: Yes — destroys itself after push

## How to monitor
```bash
# Check instance status
vastai show instance 44743370 --raw | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('actual_status'))"

# Check logs
vastai logs 44743370 --tail 50

# Check if image pushed
curl -s "https://hub.docker.com/v2/repositories/moneywaters/comfyui-ltx/tags/latest/" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('last_updated','not yet'))"
```

## What we learned (conclusions)
- **Docker Desktop on macOS can't build this image** — networking proxy breaks apt-get, qemu x86 emulation is unreliable for pip installs with compiled dependencies
- **Podman on macOS has same issue** — slow qemu emulation, broken apt networking
- **Building on native x86 Linux (Vast.ai) is the only reliable path**
- **Disk space**: host needs 50GB free for the 25GB model + build layers
- **stringzilla build failure** — ComfyUI depends on stringzilla which needs gcc/g++ build-essential. Added to Dockerfile.
- **Base image**: pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime is better than nvidia/cuda — PyTorch/Git pre-installed, less apt dependencies

## Verified custom node repo URLs (corrected from nodes.txt)
- comfyui-melbandroformer → kijai/ComfyUI-MelBandRoFormer (not sucial)
- ComfyUI-LivePortrait → kijai/ComfyUI-LivePortraitKJ (not silkyland)  
- Comfyui-Resolution-Master → Azornes/Comfyui-Resolution-Master (not UmeAi-AI)
- comfyui-rtx-simple → BetaDoggo/comfyui-rtx-simple (not Skim42)
- BlenderAI-node → NOT INSTALLED (not in workflow, repos deleted)

## Next session
1. Check if `moneywaters/comfyui-ltx:latest` exists on Docker Hub
2. If yes — deploy a fresh Vast.ai instance with that image 
3. If no — check instance 44743370 status, logs, and troubleshoot

## Deploy command for final image
```bash
vastai create instance <OFFER_ID> \
  --image docker.io/moneywaters/comfyui-ltx:latest \
  --disk 100 \
  --ssh --direct \
  --env '-p 8188:8188' \
  --label comfyui-ltx
```
