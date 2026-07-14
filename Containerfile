FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime

ENV PYTHONUNBUFFERED=1

RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI && \
    cd /opt/ComfyUI && pip install --no-cache-dir -r requirements.txt

COPY nodes.sh /opt/nodes.sh
RUN bash /opt/nodes.sh

RUN cd /opt/ComfyUI/custom_nodes && git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git ComfyUI-Manager

RUN cd /opt/ComfyUI && for req in custom_nodes/*/requirements.txt; do [ -f "$req" ] && pip install --no-cache-dir -r "$req" || true; done

RUN pip install --no-cache-dir piexif rotary-embedding-torch numexpr imageio-ffmpeg pykalman \
    "kornia==0.7.3" spandrel spandrel_extra_arches pandas segment-anything webcolors

RUN mkdir -p /opt/ComfyUI/models/{diffusion_models,latent_upscale_models,text_encoders,vae,loras}

COPY start.sh /opt/start.sh
COPY download-models.sh /opt/download-models.sh
RUN chmod +x /opt/start.sh /opt/download-models.sh

EXPOSE 8188
WORKDIR /opt/ComfyUI
ENTRYPOINT ["/opt/start.sh"]
