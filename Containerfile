FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime

ENV PYTHONUNBUFFERED=1
ENV COMFYUI_PATH=/opt/ComfyUI
ENV BACKGROUND_MODELS=1
ENV SKIP_MODEL_DOWNLOAD=0
# fp8 embedding fix (sitecustomize + explicit import path)
ENV PYTHONPATH=/opt/comfyui-fixes
ENV PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
# Keep /opt/conda/bin — overriding PATH without it breaks pip/python from the base image.
ENV PATH=/opt/ffmpeg/bin:/opt/conda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
        git wget curl xz-utils openssh-server libsndfile1 \
        libgl1-mesa-glx libglib2.0-0 libsm6 libxext6 libxrender1 libgomp1 libx11-6 \
        ffmpeg \
        gcc g++ build-essential \
    && mkdir -p /var/run/sshd \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config \
    && rm -rf /var/lib/apt/lists/*

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

RUN cd /opt/ComfyUI && for req in custom_nodes/*/requirements.txt; do \
        [ -f "$req" ] && /opt/conda/bin/pip install --no-cache-dir -r "$req" || true; \
    done

RUN /opt/conda/bin/pip install --no-cache-dir piexif rotary-embedding-torch numexpr imageio-ffmpeg pykalman \
        "kornia==0.7.3" spandrel spandrel_extra_arches pandas segment-anything webcolors \
    && /opt/conda/bin/pip install --no-cache-dir sqlalchemy opencv-python-headless scikit-image matplotlib

RUN mkdir -p /opt/comfyui-fixes /root/.ssh \
        /opt/ComfyUI/models/diffusion_models \
        /opt/ComfyUI/models/latent_upscale_models \
        /opt/ComfyUI/models/text_encoders \
        /opt/ComfyUI/models/vae \
        /opt/ComfyUI/models/loras \
        /opt/ComfyUI/user/default/workflows \
        /workspace/output \
        /workspace/input \
    && chmod 700 /root/.ssh \
    && echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAt/TE7gxwxhsaAvnYg/uZcZpa1ovhC0YOnCdjkJurZO clore.ai' > /root/.ssh/authorized_keys \
    && chmod 600 /root/.ssh/authorized_keys

COPY fp8_embed_fix.py sitecustomize.py /opt/comfyui-fixes/
# Install into site-packages. Clear PYTHONPATH for the path query so a
# provisional sitecustomize on /opt/comfyui-fixes cannot pollute stdout.
RUN SITE=$(PYTHONPATH= /opt/conda/bin/python3 -c 'import site; print(site.getsitepackages()[0])') \
    && echo "site-packages=$SITE" \
    && cp /opt/comfyui-fixes/sitecustomize.py "$SITE/sitecustomize.py" \
    && cp /opt/comfyui-fixes/fp8_embed_fix.py "$SITE/fp8_embed_fix.py" \
    && test -f "$SITE/sitecustomize.py" && test -f "$SITE/fp8_embed_fix.py" \
    && echo "fp8 fix installed into $SITE"
COPY start.sh /opt/start.sh
COPY download-models.sh /opt/download-models.sh
COPY smoke-test.sh /opt/smoke-test.sh
RUN chmod +x /opt/start.sh /opt/download-models.sh /opt/smoke-test.sh

COPY workflow/LTX-fixed.json /opt/ComfyUI/user/default/workflows/LTX-fixed.json

EXPOSE 8188 22
WORKDIR /opt/ComfyUI
ENTRYPOINT ["/opt/start.sh"]
