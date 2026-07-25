FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime

ENV PYTHONUNBUFFERED=1
ENV COMFYUI_PATH=/opt/ComfyUI
ENV BACKGROUND_MODELS=1
ENV SKIP_MODEL_DOWNLOAD=0
# fp8 embedding fix (sitecustomize + explicit import path)
# Keep /opt/conda/bin — overriding PATH without it breaks pip/python from the base image.
ENV PATH=/opt/ffmpeg/bin:/opt/conda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Clore-compatible SSH stack: supervisor + init.sh (same pattern as cloreai/jupyter)
RUN apt-get update && apt-get install -y --no-install-recommends \
        git wget curl xz-utils libsndfile1 \
        libgl1-mesa-glx libglib2.0-0 libsm6 libxext6 libxrender1 libgomp1 libx11-6 \
        ffmpeg \
        openssh-server supervisor \
        gcc g++ build-essential \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /var/run/sshd /run/sshd /root/.ssh /var/log/supervisor /etc/supervisor/conf.d \
    && chmod 700 /root/.ssh \
    && ssh-keygen -A \
    && sed -i 's/#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
    && echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config \
    && echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config \
    && touch /etc/supervisor/SSH_INIT_SET

# NVENC FFmpeg (av1_nvenc + h264_nvenc + hevc_nvenc). Host NVIDIA driver provides libnvidia-encode.
# AV1 *encode* needs Ada (RTX 40xx)+; Ampere (30xx) uses h264_nvenc. start.sh picks format by compute_cap.
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

RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI \
    && cd /opt/ComfyUI \
    && /opt/conda/bin/pip install --no-cache-dir -r requirements.txt

COPY nodes.sh /opt/nodes.sh
RUN bash /opt/nodes.sh
# fp8 embedding fix runs as ComfyUI prestartup (must NOT import torch via sitecustomize)
COPY fp8_fix_node /opt/ComfyUI/custom_nodes/00_fp8_embed_fix

RUN cd /opt/ComfyUI && for req in custom_nodes/*/requirements.txt; do \
        [ -f "$req" ] && /opt/conda/bin/pip install --no-cache-dir -r "$req" || true; \
    done

RUN /opt/conda/bin/pip install --no-cache-dir piexif rotary-embedding-torch numexpr imageio-ffmpeg pykalman \
        "kornia==0.7.3" spandrel spandrel_extra_arches pandas segment-anything webcolors \
    && /opt/conda/bin/pip install --no-cache-dir sqlalchemy opencv-python-headless scikit-image matplotlib

RUN mkdir -p /opt/comfyui-fixes \
        /opt/ComfyUI/models/diffusion_models \
        /opt/ComfyUI/models/latent_upscale_models \
        /opt/ComfyUI/models/text_encoders \
        /opt/ComfyUI/models/vae \
        /opt/ComfyUI/models/loras \
        /opt/ComfyUI/user/default/workflows \
        /workspace/output \
        /workspace/input

COPY fp8_embed_fix.py /opt/comfyui-fixes/fp8_embed_fix.py
COPY start.sh /opt/start.sh
COPY onstart.sh /root/onstart.sh
COPY download-models.sh /opt/download-models.sh
COPY smoke-test.sh /opt/smoke-test.sh
COPY clore/supervisor/init.sh /etc/supervisor/init.sh
COPY clore/supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY clore/delegated-entrypoint.sh /etc/delegated-entrypoint.sh
RUN chmod +x /opt/start.sh /root/onstart.sh /opt/download-models.sh /opt/smoke-test.sh \
        /etc/supervisor/init.sh /etc/delegated-entrypoint.sh \
    && touch /etc/supervisor/SSH_INIT_SET

COPY workflow/LTX-fixed.json /opt/ComfyUI/user/default/workflows/LTX-fixed.json

# PID1 = clore init: starts sshd FIRST, then ComfyUI in background.
# Model downloads never block SSH. Clore injects SSH_KEY / SSH_PASSWORD.
EXPOSE 22 8188
WORKDIR /opt/ComfyUI
# No ENTRYPOINT (matches cloreai/jupyter). CMD is the only boot path.
CMD ["/etc/supervisor/init.sh"]
