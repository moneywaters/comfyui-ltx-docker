# SimplePod + MiniMax H3 Deployment — 2026-08-08

## Working image
- **Docker Hub**: `moneywaters/comfyui-ltx:simplepod` (8.9GB) — also `:latest`
- **Base**: cloreai/jupyter → ComfyUI 0.31.0, PyTorch 2.11.0+cu128, MiniMax H3 native nodes
- **Models** (downloaded at first boot via `HF_TOKEN`): ~42GB
  - `minimax_h3_fl2va_pruned_int8_convrot.safetensors` (diffusion, 20.9GB)
  - `qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors` (text encoder, 15.7GB)
  - `minimax_h3_video_vae_fp16.safetensors` + `minimax_h3_audio_vae_fp32.safetensors`

## SimplePod setup
- **API**: `https://api.simplepod.ai`, auth header `X-AUTH-TOKEN`
- **Private template**: id `28256` "comfyui-minimax-h3"
  - image `moneywaters/comfyui-ltx:simplepod`, port `8188`, no startScript (image CMD runs `/opt/start.sh`), SSH on
- **Instance login**: ComfyUI web UI is gated by `/simplepod-login` — use the instance `hashId` (e.g. `rri_xxxx`) as the password
- **SSH**: key `~/.ssh/simplepod` registered as "mac" on the account

## Verified on RTX 3090 (24GB)
- Full H3 T2V generation worked: 832×480, 124 frames, h264+aac, ~4 min

## Verified on 170HX (64GB, CUDA 13.3)
- **IMPORTANT — use 2x+ 170HX offer (22GB+ RAM), NOT 1x (10GB RAM)**
  - 1x 170HX has only 10GB host RAM → OOM (kernel kills ComfyUI during model load)
  - 2x 170HX (22GB RAM) at $0.4/h works: asan.png I2V, 768×1344, 124 frames, ~2.5 min
- CLIP text encoder loads on **GPU** (64GB VRAM), not CPU — else host RAM OOMs
- `--lowvram` auto-disabled when VRAM ≥ 32GB (start.sh auto-detects)

## Generation API (no UI)
```python
# upload image: POST /upload/image (multipart, field "image")
# submit: POST /prompt with class_types:
#   UNETLoader (fl2va_int8), CLIPLoader (type=minimax), VAELoader x2 (video+audio),
#   MiniMaxH3ImageToVideo (first_frame optional), RandomNoise, KSamplerSelect,
#   BasicScheduler (simple, 12 steps), BasicGuider, SamplerCustomAdvanced,
#   VAEDecode, VAEDecodeAudio, CreateVideo, SaveVideo
# poll: GET /history/{prompt_id}
# download: GET /view?filename=X&type=output
```

## Deploy (170HX, when ready to spend)
```bash
# 1x is too little RAM. Use 2x+ (22GB+ RAM):
POST /instances
{ "gpuCount": 2,
  "instanceMarket": "/instances/market/831",   # 2x170HX $0.4/h, 22GB RAM
  "instanceTemplate": "/instances/templates/28256",
  "envVariables": [{ "name": "HF_TOKEN", "value": "hf_..." },
                   { "name": "SKIP_MODEL_DOWNLOAD", "value": "0" },
                   { "name": "BACKGROUND_MODELS", "value": "1" }] }
```
- 10x170HX rig = market 886/857/875, $2.0/h, 114GB RAM (plenty)
- Always `PUT /instances/{id}` with `{"isAutoRenewOn": false}` right after renting
- Kill stuck pods with `DELETE /instances/{id}`

## Budget notes
- Practice cost: ~$0.28 total across all test instances (3090 + 170HX)
- Balance check: `GET /instances/summary` → `rentalAvailability.balanceRental`
