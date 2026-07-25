# Build LTX/ComfyUI ON TOP of the official Clore Jupyter image so we inherit
# the working SSH stack (supervisor init + SSH_KEY/SSH_PASSWORD + sshd).
# Experiments: cloreai/jupyter reaches mon_container=2 + SSH; custom bases often stay mon=0.
FROM cloreai/jupyter:ubuntu24.04-v2

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV COMFYUI_PATH=/opt/ComfyUI
ENV BACKGROUND_MODELS=1
ENV SKIP_MODEL_DOWNLOAD=0
ENV COMFY_PYTHON=/opt/comfyui-venv/bin/python3
# Keep CUDA/NVIDIA paths from base; prepend ffmpeg + venv
ENV PATH=/opt/ffmpeg/bin:/opt/comfyui-venv/bin:/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
        git wget curl xz-utils libsndfile1 \
        libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 libgomp1 \
        ffmpeg gcc g++ build-essential python3-venv python3-dev \
    && rm -rf /var/lib/apt/lists/*

# NVENC-capable ffmpeg (host driver provides libnvidia-encode)
RUN mkdir -p /opt/ffmpeg/bin \
    && cd /tmp \
    && wget -q -O ffmpeg.tar.xz \
        "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz" \
    && tar -xJf ffmpeg.tar.xz \
    && FFDIR=$(find /tmp -maxdepth 1 -type d -name 'ffmpeg-*-linux64-gpl' | head -1) \
    && cp -a "$FFDIR"/bin/ffmpeg "$FFDIR"/bin/ffprobe /opt/ffmpeg/bin/ \
    && ln -sf /opt/ffmpeg/bin/ffmpeg /usr/local/bin/ffmpeg \
    && ln -sf /opt/ffmpeg/bin/ffprobe /usr/local/bin/ffprobe \
    && rm -rf /tmp/ffmpeg* \
    && /opt/ffmpeg/bin/ffmpeg -hide_banner -encoders 2>&1 | grep -E 'av1_nvenc|h264_nvenc' \
    && echo "NVENC ffmpeg installed OK"

RUN git config --global http.postBuffer 524288000 \
    && git config --global http.lowSpeedLimit 0 \
    && git config --global http.lowSpeedTime 999999

# Isolated venv so we don't break system Jupyter on the Clore base
# cu121 wheels work on modern host drivers (Clore GPU hosts typically 535+)
RUN python3 -m venv /opt/comfyui-venv \
    && /opt/comfyui-venv/bin/pip install -U --no-cache-dir pip wheel setuptools \
    && /opt/comfyui-venv/bin/pip install --no-cache-dir \
        torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI \
    && cd /opt/ComfyUI \
    && /opt/comfyui-venv/bin/pip install --no-cache-dir -r requirements.txt

COPY nodes.sh /opt/nodes.sh
RUN bash /opt/nodes.sh

COPY fp8_fix_node /opt/ComfyUI/custom_nodes/00_fp8_embed_fix

RUN cd /opt/ComfyUI && for req in custom_nodes/*/requirements.txt; do \
        [ -f "$req" ] && /opt/comfyui-venv/bin/pip install --no-cache-dir -r "$req" || true; \
    done

RUN /opt/comfyui-venv/bin/pip install --no-cache-dir \
        piexif rotary-embedding-torch numexpr imageio-ffmpeg pykalman \
        "kornia==0.7.3" spandrel spandrel_extra_arches pandas segment-anything webcolors \
        sqlalchemy opencv-python-headless scikit-image matplotlib

RUN mkdir -p /opt/comfyui-fixes \
        /opt/ComfyUI/models/diffusion_models \
        /opt/ComfyUI/models/latent_upscale_models \
        /opt/ComfyUI/models/text_encoders \
        /opt/ComfyUI/models/vae \
        /opt/ComfyUI/models/loras \
        /opt/ComfyUI/user/default/workflows \
        /workspace/output \
        /workspace/input \
        /var/log/supervisor

COPY fp8_embed_fix.py /opt/comfyui-fixes/fp8_embed_fix.py
COPY start.sh /opt/start.sh
COPY onstart.sh /root/onstart.sh
COPY download-models.sh /opt/download-models.sh
COPY smoke-test.sh /opt/smoke-test.sh
# Only replace supervisord programs (sshd + comfyui). Keep official /etc/supervisor/init.sh.
COPY clore/supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
# Ensure delegated entrypoint exists (present on official image; re-copy our copy for safety)
COPY clore/delegated-entrypoint.sh /etc/delegated-entrypoint.sh
RUN chmod +x /opt/start.sh /root/onstart.sh /opt/download-models.sh /opt/smoke-test.sh \
        /etc/delegated-entrypoint.sh \
    && test -x /etc/supervisor/init.sh

COPY workflow/LTX-fixed.json /opt/ComfyUI/user/default/workflows/LTX-fixed.json

# Inherit CMD from cloreai/jupyter: bash -c /etc/supervisor/init.sh
# That init applies SSH_KEY/SSH_PASSWORD then starts supervisord (sshd + comfyui).
EXPOSE 22 8188
WORKDIR /opt/ComfyUI
