FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime

ENV PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends git openssh-server libgl1-mesa-glx libx11-6 && \
    mkdir /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config && \
    rm -rf /var/lib/apt/lists/*

RUN git config --global http.postBuffer 524288000 && git config --global http.lowSpeedLimit 0 && git config --global http.lowSpeedTime 999999

RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI && \
    cd /opt/ComfyUI && pip install --no-cache-dir -r requirements.txt

COPY nodes.sh /opt/nodes.sh
RUN bash /opt/nodes.sh

RUN cd /opt/ComfyUI && for req in custom_nodes/*/requirements.txt; do [ -f "$req" ] && pip install --no-cache-dir -r "$req" || true; done

RUN pip install --no-cache-dir piexif rotary-embedding-torch numexpr imageio-ffmpeg pykalman \
    "kornia==0.7.3" spandrel spandrel_extra_arches pandas segment-anything webcolors
RUN pip install --no-cache-dir sqlalchemy opencv-python-headless scikit-image matplotlib

RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh && \
    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAt/TE7gxwxhsaAvnYg/uZcZpa1ovhC0YOnCdjkJurZO clore.ai' > /root/.ssh/authorized_keys && \
    chmod 600 /root/.ssh/authorized_keys

RUN mkdir -p /opt/ComfyUI/models/{diffusion_models,latent_upscale_models,text_encoders,vae,loras}

COPY start.sh /opt/start.sh
COPY download-models.sh /opt/download-models.sh
RUN chmod +x /opt/start.sh /opt/download-models.sh

EXPOSE 8188 22
WORKDIR /opt/ComfyUI
ENTRYPOINT ["/opt/start.sh"]
