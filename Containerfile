FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime

ENV PYTHONUNBUFFERED=1
ENV PATH="/opt/venv/bin:$PATH"

RUN python3 -m venv /opt/venv

RUN pip install git+https://github.com/comfyanonymous/ComfyUI.git@master

RUN mkdir -p /opt/ComfyUI/custom_nodes && cd /opt/ComfyUI/custom_nodes && \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git ComfyUI-Manager

COPY nodes.sh /opt/nodes.sh
RUN bash /opt/nodes.sh

RUN cd /opt/ComfyUI && for req in custom_nodes/*/requirements.txt; do [ -f "$req" ] && pip install -r "$req" || true; done

RUN pip install piexif rotary-embedding-torch numexpr imageio-ffmpeg pykalman \
    "kornia==0.7.3" spandrel spandrel_extra_arches pandas segment-anything webcolors \
    wget

RUN mkdir -p /opt/ComfyUI/models/{diffusion_models,latent_upscale_models,text_encoders,vae,loras}

COPY download-models.sh /opt/download-models.sh
RUN chmod +x /opt/download-models.sh

COPY start.sh /opt/start.sh
RUN chmod +x /opt/start.sh

EXPOSE 8188
WORKDIR /opt/ComfyUI
ENTRYPOINT ["/opt/start.sh"]
