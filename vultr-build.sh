#!/bin/bash
# Run on Vultr 216.128.159.11 via web console or SSH
# Builds ComfyUI LTX image and pushes to Docker Hub
set -euo pipefail

echo "=== Build Start $(date) ==="

apt-get update -qq
apt-get install -y -qq buildah > /dev/null 2>&1

echo 'dckr_pat_5EKXhQwYGBv0LIHhKgxVEQnG7do' | buildah login -u moneywaters --password-stdin docker.io

c=$(buildah from pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime)

buildah run $c -- apt-get update -qq
buildah run $c -- apt-get install -y --no-install-recommends git wget ffmpeg libsndfile1 libglib2.0-0 libsm6 libxext6 libxrender-dev libgomp1 gcc g++ build-essential
buildah run $c -- apt-get clean

buildah run $c -- git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI
buildah run $c -- pip install -r /opt/ComfyUI/requirements.txt

buildah run $c -- git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git /opt/ComfyUI/custom_nodes/ComfyUI-Manager

for repo in \
  "https://github.com/rgthree/rgthree-comfy.git:rgthree-comfy" \
  "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git:ComfyUI-Impact-Pack" \
  "https://github.com/ltdrdata/ComfyUI-Inspire-Pack.git:ComfyUI-Inspire-Pack" \
  "https://github.com/chflame163/ComfyUI_LayerStyle.git:ComfyUI_LayerStyle" \
  "https://github.com/yolain/ComfyUI-Easy-Use.git:ComfyUI-Easy-Use" \
  "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git:ComfyUI-VideoHelperSuite" \
  "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git:ComfyUI-Custom-Scripts" \
  "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git:ComfyUI-Frame-Interpolation" \
  "https://github.com/kijai/ComfyUI-MelBandRoFormer.git:comfyui-melbandroformer" \
  "https://github.com/Fannovel16/comfyui_controlnet_aux.git:comfyui_controlnet_aux" \
  "https://github.com/kijai/ComfyUI-KJNodes.git:ComfyUI-KJNodes" \
  "https://github.com/FizzleDorf/ComfyUI_FizzNodes.git:ComfyUI-FizzNodes" \
  "https://github.com/WASasquatch/was-node-suite-comfyui.git:WAS-Node-Suite-ComfyUI" \
  "https://github.com/Lightricks/ComfyUI-LTXVideo.git:ComfyUI-LTXVideo" \
  "https://github.com/kijai/ComfyUI-LivePortraitKJ.git:ComfyUI-LivePortraitKJ" \
  "https://github.com/Azornes/Comfyui-Resolution-Master.git:Comfyui-Resolution-Master" \
  "https://github.com/BetaDoggo/comfyui-rtx-simple.git:comfyui-rtx-simple" \
  "https://github.com/chrisgoringe/cg-use-everywhere.git:cg-use-everywhere" \
  "https://github.com/malkuthro/ComfyUI-Koolook.git:ComfyUI-Koolook" \
  "https://github.com/artokun/comfyui-mcp-panel.git:comfyui-mcp-panel"; do
  url="${repo%%:*}"
  dir="${repo##*:}"
  buildah run $c -- git clone --depth 1 "$url" "/opt/ComfyUI/custom_nodes/$dir"
done

echo "=== Per-node requirements ==="
buildah run $c -- bash -c 'for req in /opt/ComfyUI/custom_nodes/*/requirements.txt; do [ -f "$req" ] && pip install -r "$req" || true; done'

echo "=== Extra pip deps ==="
buildah run $c -- pip install piexif rotary-embedding-torch numexpr imageio-ffmpeg pykalman "kornia==0.7.3" spandrel spandrel_extra_arches pandas segment-anything webcolors

buildah run $c -- mkdir -p /opt/ComfyUI/models/{diffusion_models,latent_upscale_models,text_encoders,vae,loras}

echo "=== Downloading models ==="
buildah run $c -- wget -q --show-progress -P /opt/ComfyUI/models/diffusion_models "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/diffusion_models/ltx-2.3-22b-distilled-1.1_transformer_only_fp8_scaled.safetensors"

buildah run $c -- wget -q --show-progress -P /opt/ComfyUI/models/vae "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_video_vae_bf16.safetensors"

buildah run $c -- wget -q --show-progress -P /opt/ComfyUI/models/vae "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_audio_vae_bf16.safetensors"

buildah run $c -- wget -q --show-progress -P /opt/ComfyUI/models/text_encoders "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/text_encoders/ltx-2.3_text_projection_bf16.safetensors"

buildah run $c -- wget -q --show-progress -P /opt/ComfyUI/models/text_encoders "https://huggingface.co/DreamFast/gemma-3-12b-it-heretic-v2/resolve/main/comfyui/gemma-3-12b-it-heretic-v2_fp8_e4m3fn.safetensors"

buildah run $c -- wget -q --show-progress -P /opt/ComfyUI/models/latent_upscale_models "https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors"

buildah run $c -- wget -q --show-progress -P /opt/ComfyUI/models/diffusion_models "https://huggingface.co/Kijai/MelBandRoFormer_comfy/resolve/main/MelBandRoformer_fp16.safetensors"

buildah run $c -- wget -q --show-progress -P /opt/ComfyUI/models/loras "https://huggingface.co/TenStrip/LTX2.3_Distilled_Lora_1.1_Experiments/resolve/main/ltx-2.3-22b-distilled-lora-1.1_fro90_ceil72_condsafe.safetensors"

buildah run $c -- wget -q --show-progress -P /opt/ComfyUI/models/loras "https://huggingface.co/Comfy-Org/ltx-2.3/resolve/main/split_files/loras/ltx-2.3-id-lora-celebvhq-3k.safetensors"

buildah run $c -- wget -q --show-progress -P /opt/ComfyUI/models/loras "https://huggingface.co/Lightricks/LTX-2-19b-IC-LoRA-Detailer/resolve/main/ltx-2-19b-ic-lora-detailer.safetensors"

buildah run $c -- wget -q --show-progress -P /opt/ComfyUI/models/loras "https://huggingface.co/Lightricks/LTX-2.3-22b-IC-LoRA-Union-Control/resolve/main/ltx-2.3-22b-ic-lora-union-control-ref0.5.safetensors"

echo "=== Start script ==="
buildah run $c -- bash -c 'echo "#!/bin/bash" > /opt/start.sh && echo "cd /opt/ComfyUI" >> /opt/start.sh && echo "mkdir -p /workspace/output /workspace/input" >> /opt/start.sh && echo "python3 main.py --listen 0.0.0.0 --port 8188" >> /opt/start.sh && chmod +x /opt/start.sh'

buildah config --entrypoint '["/opt/start.sh"]' $c
buildah config --port 8188 $c
buildah config --workingdir /opt/ComfyUI $c

echo "=== Commit & Push $(date) ==="
buildah commit $c docker.io/moneywaters/comfyui-ltx:latest
buildah push docker.io/moneywaters/comfyui-ltx:latest

echo "=== DONE: docker.io/moneywaters/comfyui-ltx:latest $(date) ==="
echo "Deploy: vastai create instance <OFFER> --image moneywaters/comfyui-ltx:latest --disk 100 --env '-p 8188:8188'"
