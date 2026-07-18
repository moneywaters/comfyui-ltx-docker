# Legacy/alternate Dockerfile. GitHub Actions builds Containerfile.
# Keep this in sync with Containerfile for local docker builds.
FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV COMFYUI_PATH=/opt/ComfyUI
ENV BACKGROUND_MODELS=1
ENV SKIP_MODEL_DOWNLOAD=0
ENV PYTHONPATH=/opt/comfyui-fixes
ENV PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
ENV PATH=/opt/ffmpeg/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
    git wget curl xz-utils openssh-server ffmpeg libsndfile1 \
    libglib2.0-0 libsm6 libxext6 libxrender1 libgomp1 libgl1-mesa-glx libx11-6 \
    gcc g++ build-essential \
    && mkdir -p /var/run/sshd \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/ffmpeg/bin \
    && cd /tmp \
    && wget -q -O ffmpeg.tar.xz \
        "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz" \
    && tar -xJf ffmpeg.tar.xz \
    && FFDIR=$(find /tmp -maxdepth 1 -type d -name 'ffmpeg-*-linux64-gpl' | head -1) \
    && cp -a "$FFDIR"/bin/ffmpeg "$FFDIR"/bin/ffprobe /opt/ffmpeg/bin/ \
    && ln -sf /opt/ffmpeg/bin/ffmpeg /usr/local/bin/ffmpeg \
    && ln -sf /opt/ffmpeg/bin/ffprobe /usr/local/bin/ffprobe \
    && rm -rf /tmp/ffmpeg*

RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI && \
    cd /opt/ComfyUI && pip install --no-cache-dir -r requirements.txt

COPY nodes.sh /opt/nodes.sh
RUN bash /opt/nodes.sh

RUN cd /opt/ComfyUI && \
    for req in custom_nodes/*/requirements.txt; do \
        [ -f "$req" ] && pip install --no-cache-dir -r "$req" || true; \
    done

RUN pip install --no-cache-dir piexif rotary-embedding-torch numexpr imageio-ffmpeg pykalman \
    "kornia==0.7.3" spandrel spandrel_extra_arches \
    pandas segment-anything webcolors
RUN pip install --no-cache-dir sqlalchemy opencv-python-headless scikit-image matplotlib

RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh && \
    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAt/TE7gxwxhsaAvnYg/uZcZpa1ovhC0YOnCdjkJurZO clore.ai' > /root/.ssh/authorized_keys && \
    chmod 600 /root/.ssh/authorized_keys

RUN mkdir -p \
    /opt/ComfyUI/models/diffusion_models \
    /opt/ComfyUI/models/latent_upscale_models \
    /opt/ComfyUI/models/text_encoders \
    /opt/ComfyUI/models/vae \
    /opt/ComfyUI/models/loras \
    /opt/ComfyUI/user/default/workflows \
    /workspace/output \
    /workspace/input

RUN mkdir -p /opt/comfyui-fixes
COPY fp8_embed_fix.py sitecustomize.py /opt/comfyui-fixes/
RUN SITE=$(python3 -c 'import site; print(site.getsitepackages()[0])') \
    && cp /opt/comfyui-fixes/sitecustomize.py "$SITE/sitecustomize.py" \
    && cp /opt/comfyui-fixes/fp8_embed_fix.py "$SITE/fp8_embed_fix.py"
COPY start.sh /opt/start.sh
COPY download-models.sh /opt/download-models.sh
COPY smoke-test.sh /opt/smoke-test.sh
RUN chmod +x /opt/start.sh /opt/download-models.sh /opt/smoke-test.sh

COPY workflow/LTX-fixed.json /opt/ComfyUI/user/default/workflows/LTX-fixed.json

EXPOSE 8188 22
WORKDIR /opt/ComfyUI
ENTRYPOINT ["/opt/start.sh"]
