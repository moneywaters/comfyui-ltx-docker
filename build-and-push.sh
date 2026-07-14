#!/bin/bash
# ── ComfyUI LTX Director — Build & Push ─────────────────────────────
# Run this on a Vast.ai instance (or any Linux box with Podman/Docker)
# Everything is self-contained — ComfyUI, 20 custom nodes, pip deps,
# and all 11 models download and get baked into a single image.
# Then pushes to Docker Hub.
set -euo pipefail

DOCKER_USER="moneywaters"
DOCKER_PASS="dckr_pat_5EKXhQwYGBv0LIHhKgxVEQnG7do"
IMAGE="docker.io/${DOCKER_USER}/comfyui-ltx:latest"

echo "=== Logging into Docker Hub ==="
echo "$DOCKER_PASS" | podman login -u "$DOCKER_USER" --password-stdin docker.io

echo "=== Writing Containerfile ==="
cat > /tmp/Containerfile << 'EOF'
FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    git wget ffmpeg libsndfile1 libglib2.0-0 libsm6 libxext6 libxrender-dev libgomp1 \
    gcc g++ build-essential \
    && rm -rf /var/lib/apt/lists/*

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

# Models — each in own RUN so a failure doesn't kill the whole build
RUN echo "Model 1/11: Base model (23GB)..." && \
    wget -q --show-progress -P /opt/ComfyUI/models/diffusion_models \
    "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/diffusion_models/ltx-2.3-22b-distilled-1.1_transformer_only_fp8_scaled.safetensors"

RUN echo "Model 2/11: Video VAE" && \
    wget -q --show-progress -P /opt/ComfyUI/models/vae \
    "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_video_vae_bf16.safetensors"

RUN echo "Model 3/11: Audio VAE" && \
    wget -q --show-progress -P /opt/ComfyUI/models/vae \
    "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_audio_vae_bf16.safetensors"

RUN echo "Model 4/11: Text projection" && \
    wget -q --show-progress -P /opt/ComfyUI/models/text_encoders \
    "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/text_encoders/ltx-2.3_text_projection_bf16.safetensors"

RUN echo "Model 5/11: Gemma text encoder" && \
    wget -q --show-progress -P /opt/ComfyUI/models/text_encoders \
    "https://huggingface.co/DreamFast/gemma-3-12b-it-heretic-v2/resolve/main/comfyui/gemma-3-12b-it-heretic-v2_fp8_e4m3fn.safetensors"

RUN echo "Model 6/11: Upscaler" && \
    wget -q --show-progress -P /opt/ComfyUI/models/latent_upscale_models \
    "https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors"

RUN echo "Model 7/11: Mel-Band RoFormer" && \
    wget -q --show-progress -P /opt/ComfyUI/models/diffusion_models \
    "https://huggingface.co/Kijai/MelBandRoFormer_comfy/resolve/main/MelBandRoformer_fp16.safetensors"

RUN echo "Model 8/11: Distilled LoRA" && \
    wget -q --show-progress -P /opt/ComfyUI/models/loras \
    "https://huggingface.co/TenStrip/LTX2.3_Distilled_Lora_1.1_Experiments/resolve/main/ltx-2.3-22b-distilled-lora-1.1_fro90_ceil72_condsafe.safetensors"

RUN echo "Model 9/11: ID LoRA" && \
    wget -q --show-progress -P /opt/ComfyUI/models/loras \
    "https://huggingface.co/Comfy-Org/ltx-2.3/resolve/main/split_files/loras/ltx-2.3-id-lora-celebvhq-3k.safetensors"

RUN echo "Model 10/11: Detailer LoRA" && \
    wget -q --show-progress -P /opt/ComfyUI/models/loras \
    "https://huggingface.co/Lightricks/LTX-2-19b-IC-LoRA-Detailer/resolve/main/ltx-2-19b-ic-lora-detailer.safetensors"

RUN echo "Model 11/11: Union Control LoRA" && \
    wget -q --show-progress -P /opt/ComfyUI/models/loras \
    "https://huggingface.co/Lightricks/LTX-2.3-22b-IC-LoRA-Union-Control/resolve/main/ltx-2.3-22b-ic-lora-union-control-ref0.5.safetensors"

# Workflow + start script
RUN echo '#!/bin/bash' > /opt/start.sh && \
    echo 'set -e' >> /opt/start.sh && \
    echo 'echo "Starting ComfyUI..."' >> /opt/start.sh && \
    echo 'mkdir -p /workspace/output /workspace/input /workspace/user' >> /opt/start.sh && \
    echo 'cd /opt/ComfyUI' >> /opt/start.sh && \
    echo 'python3 main.py --listen 0.0.0.0 --port 8188 --output-directory /workspace/output --input-directory /workspace/input --user-directory /workspace/user' >> /opt/start.sh && \
    chmod +x /opt/start.sh

EXPOSE 8188
WORKDIR /opt/ComfyUI
ENTRYPOINT ["/opt/start.sh"]
EOF

echo "=== Building image (this will take 30-60 minutes) ==="
podman build -t "$IMAGE" -f /tmp/Containerfile /tmp

echo "=== Build complete! Pushing to Docker Hub ==="
podman push "$IMAGE"

echo ""
echo "=== DONE ==="
echo "Image: $IMAGE"
echo "Deploy on Vast.ai: use image ${DOCKER_USER}/comfyui-ltx:latest, port 8188, GPU >= RTX 4090, disk >= 100GB"
