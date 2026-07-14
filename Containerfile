FROM nvidia/cuda:12.4.0-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 python3.11-venv python3.11-dev python3-pip \
    git wget ffmpeg libsndfile1 libglib2.0-0 libsm6 libxext6 libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

RUN python3.11 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124

RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI && \
    cd /opt/ComfyUI && pip install -r requirements.txt

RUN git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git /opt/ComfyUI/custom_nodes/ComfyUI-Manager

COPY nodes.sh /opt/nodes.sh
RUN bash /opt/nodes.sh

RUN cd /opt/ComfyUI && for req in custom_nodes/*/requirements.txt; do [ -f "$req" ] && pip install -r "$req" || true; done

RUN pip install piexif rotary-embedding-torch numexpr imageio-ffmpeg pykalman \
    "kornia==0.7.3" spandrel spandrel_extra_arches pandas segment-anything webcolors

RUN mkdir -p /opt/ComfyUI/models/{diffusion_models,latent_upscale_models,text_encoders,vae,loras} && \
    wget -nv --retry-connrefused --timeout=60 --tries=5 -P /opt/ComfyUI/models/diffusion_models \
    "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/diffusion_models/ltx-2.3-22b-distilled-1.1_transformer_only_fp8_scaled.safetensors" && \
    wget -nv --retry-connrefused --timeout=60 --tries=5 -P /opt/ComfyUI/models/vae \
    "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_video_vae_bf16.safetensors" && \
    wget -nv --retry-connrefused --timeout=60 --tries=5 -P /opt/ComfyUI/models/vae \
    "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_audio_vae_bf16.safetensors" && \
    wget -nv --retry-connrefused --timeout=60 --tries=5 -P /opt/ComfyUI/models/text_encoders \
    "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/text_encoders/ltx-2.3_text_projection_bf16.safetensors" && \
    wget -nv --retry-connrefused --timeout=60 --tries=5 -P /opt/ComfyUI/models/text_encoders \
    "https://huggingface.co/DreamFast/gemma-3-12b-it-heretic-v2/resolve/main/comfyui/gemma-3-12b-it-heretic-v2_fp8_e4m3fn.safetensors" && \
    wget -nv --retry-connrefused --timeout=60 --tries=5 -P /opt/ComfyUI/models/latent_upscale_models \
    "https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors" && \
    wget -nv --retry-connrefused --timeout=60 --tries=5 -P /opt/ComfyUI/models/diffusion_models \
    "https://huggingface.co/Kijai/MelBandRoFormer_comfy/resolve/main/MelBandRoformer_fp16.safetensors" && \
    wget -nv --retry-connrefused --timeout=60 --tries=5 -P /opt/ComfyUI/models/loras \
    "https://huggingface.co/TenStrip/LTX2.3_Distilled_Lora_1.1_Experiments/resolve/main/ltx-2.3-22b-distilled-lora-1.1_fro90_ceil72_condsafe.safetensors" && \
    wget -nv --retry-connrefused --timeout=60 --tries=5 -P /opt/ComfyUI/models/loras \
    "https://huggingface.co/Comfy-Org/ltx-2.3/resolve/main/split_files/loras/ltx-2.3-id-lora-celebvhq-3k.safetensors" && \
    wget -nv --retry-connrefused --timeout=60 --tries=5 -P /opt/ComfyUI/models/loras \
    "https://huggingface.co/Lightricks/LTX-2-19b-IC-LoRA-Detailer/resolve/main/ltx-2-19b-ic-lora-detailer.safetensors" && \
    wget -nv --retry-connrefused --timeout=60 --tries=5 -P /opt/ComfyUI/models/loras \
    "https://huggingface.co/Lightricks/LTX-2.3-22b-IC-LoRA-Union-Control/resolve/main/ltx-2.3-22b-ic-lora-union-control-ref0.5.safetensors"

RUN echo '#!/bin/bash' > /opt/start.sh && \
    echo 'cd /opt/ComfyUI && mkdir -p /workspace/output /workspace/input && python3 main.py --listen 0.0.0.0 --port 8188' >> /opt/start.sh && \
    chmod +x /opt/start.sh

EXPOSE 8188
WORKDIR /opt/ComfyUI
ENTRYPOINT ["/opt/start.sh"]
