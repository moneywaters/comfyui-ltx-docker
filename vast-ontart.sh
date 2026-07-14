#!/bin/bash
set -euo pipefail

INSTANCE_ID="${VAST_CONTAINERLABEL:-unknown}"
API_HOST="https://console.vast.ai"
LOG="/workspace/build.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== Build Start: $(date) ==="
echo "Instance: $INSTANCE_ID"

echo "Setting up Docker..."
until docker info >/dev/null 2>&1; do sleep 5; done

echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin docker.io

echo "Writing Dockerfile..."
cat > /workspace/Dockerfile << 'DOCKERFILE'
FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    git wget ffmpeg libsndfile1 libglib2.0-0 libsm6 libxext6 libxrender-dev libgomp1 \
    gcc g++ build-essential && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI && \
    cd /opt/ComfyUI && pip install -r requirements.txt

RUN git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git /opt/ComfyUI/custom_nodes/ComfyUI-Manager && \
    cd /opt/ComfyUI/custom_nodes && \
    git clone --depth 1 https://github.com/rgthree/rgthree-comfy.git rgthree-comfy && \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Impact-Pack.git ComfyUI-Impact-Pack && \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Inspire-Pack.git ComfyUI-Inspire-Pack && \
    git clone --depth 1 https://github.com/chflame163/ComfyUI_LayerStyle.git ComfyUI_LayerStyle && \
    git clone --depth 1 https://github.com/yolain/ComfyUI-Easy-Use.git ComfyUI-Easy-Use && \
    git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git ComfyUI-VideoHelperSuite && \
    git clone --depth 1 https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git ComfyUI-Custom-Scripts && \
    git clone --depth 1 https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git ComfyUI-Frame-Interpolation && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-MelBandRoFormer.git comfyui-melbandroformer && \
    git clone --depth 1 https://github.com/Fannovel16/comfyui_controlnet_aux.git comfyui_controlnet_aux && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-KJNodes.git ComfyUI-KJNodes && \
    git clone --depth 1 https://github.com/FizzleDorf/ComfyUI_FizzNodes.git ComfyUI-FizzNodes && \
    git clone --depth 1 https://github.com/WASasquatch/was-node-suite-comfyui.git WAS-Node-Suite-ComfyUI && \
    git clone --depth 1 https://github.com/Lightricks/ComfyUI-LTXVideo.git ComfyUI-LTXVideo && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-LivePortraitKJ.git ComfyUI-LivePortraitKJ && \
    git clone --depth 1 https://github.com/Azornes/Comfyui-Resolution-Master.git Comfyui-Resolution-Master && \
    git clone --depth 1 https://github.com/BetaDoggo/comfyui-rtx-simple.git comfyui-rtx-simple && \
    git clone --depth 1 https://github.com/chrisgoringe/cg-use-everywhere.git cg-use-everywhere && \
    git clone --depth 1 https://github.com/malkuthro/ComfyUI-Koolook.git ComfyUI-Koolook && \
    git clone --depth 1 https://github.com/artokun/comfyui-mcp-panel.git comfyui-mcp-panel

RUN cd /opt/ComfyUI && \
    for req in custom_nodes/*/requirements.txt; do \
        [ -f "$req" ] && pip install -r "$req" || true; \
    done

RUN pip install piexif rotary-embedding-torch numexpr imageio-ffmpeg pykalman \
    "kornia==0.7.3" spandrel spandrel_extra_arches \
    pandas segment-anything webcolors

RUN mkdir -p /opt/ComfyUI/models/{diffusion_models,latent_upscale_models,text_encoders,vae,loras}

RUN wget -q --show-progress -P /opt/ComfyUI/models/diffusion_models \
    "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/diffusion_models/ltx-2.3-22b-distilled-1.1_transformer_only_fp8_scaled.safetensors"

RUN wget -q --show-progress -P /opt/ComfyUI/models/vae \
    "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_video_vae_bf16.safetensors"

RUN wget -q --show-progress -P /opt/ComfyUI/models/vae \
    "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_audio_vae_bf16.safetensors"

RUN wget -q --show-progress -P /opt/ComfyUI/models/text_encoders \
    "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/text_encoders/ltx-2.3_text_projection_bf16.safetensors"

RUN wget -q --show-progress -P /opt/ComfyUI/models/text_encoders \
    "https://huggingface.co/DreamFast/gemma-3-12b-it-heretic-v2/resolve/main/comfyui/gemma-3-12b-it-heretic-v2_fp8_e4m3fn.safetensors"

RUN wget -q --show-progress -P /opt/ComfyUI/models/latent_upscale_models \
    "https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors"

RUN wget -q --show-progress -P /opt/ComfyUI/models/diffusion_models \
    "https://huggingface.co/Kijai/MelBandRoFormer_comfy/resolve/main/MelBandRoformer_fp16.safetensors"

RUN wget -q --show-progress -P /opt/ComfyUI/models/loras \
    "https://huggingface.co/TenStrip/LTX2.3_Distilled_Lora_1.1_Experiments/resolve/main/ltx-2.3-22b-distilled-lora-1.1_fro90_ceil72_condsafe.safetensors"

RUN wget -q --show-progress -P /opt/ComfyUI/models/loras \
    "https://huggingface.co/Comfy-Org/ltx-2.3/resolve/main/split_files/loras/ltx-2.3-id-lora-celebvhq-3k.safetensors"

RUN wget -q --show-progress -P /opt/ComfyUI/models/loras \
    "https://huggingface.co/Lightricks/LTX-2-19b-IC-LoRA-Detailer/resolve/main/ltx-2-19b-ic-lora-detailer.safetensors"

RUN wget -q --show-progress -P /opt/ComfyUI/models/loras \
    "https://huggingface.co/Lightricks/LTX-2.3-22b-IC-LoRA-Union-Control/resolve/main/ltx-2.3-22b-ic-lora-union-control-ref0.5.safetensors"

RUN echo '#!/bin/bash' > /opt/start.sh && echo 'cd /opt/ComfyUI' >> /opt/start.sh && \
    echo 'mkdir -p /workspace/output /workspace/input' >> /opt/start.sh && \
    echo 'python3 main.py --listen 0.0.0.0 --port 8188' >> /opt/start.sh && chmod +x /opt/start.sh

EXPOSE 8188
WORKDIR /opt/ComfyUI
ENTRYPOINT ["/opt/start.sh"]
DOCKERFILE

echo "=== Building ==="
ST=$(date +%s)
docker build -t docker.io/moneywaters/comfyui-ltx:latest /workspace
ET=$(date +%s)
echo "Build done in $(( (ET-ST)/60 )) min"

echo "=== Pushing ==="
docker push docker.io/moneywaters/comfyui-ltx:latest
echo "Push done!"

echo "=== ALL DONE: $(date) ==="
echo "Image: docker.io/moneywaters/comfyui-ltx:latest"

# Self-destruct — runs even if this script's SSH session dies
echo "Destroying instance in 10s..."
sleep 10
curl -sf -X DELETE "${API_HOST}/api/v0/instances/${INSTANCE_ID}/" \
  -H "Authorization: Bearer ${API_KEY}" \
  || echo "WARN: auto-destroy failed — run 'vastai destroy instance ${INSTANCE_ID} -y'"
halt -p 2>/dev/null || true