FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV COMFYUI_PATH=/opt/ComfyUI

RUN apt-get update && apt-get install -y --no-install-recommends \
    git wget ffmpeg libsndfile1 libglib2.0-0 libsm6 libxext6 libxrender-dev libgomp1 \
    gcc g++ build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI && \
    cd /opt/ComfyUI && pip install -r requirements.txt

RUN git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git /opt/ComfyUI/custom_nodes/ComfyUI-Manager

RUN cd /opt/ComfyUI/custom_nodes && \
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

RUN mkdir -p /opt/ComfyUI/models && cp -r /mnt/models/* /opt/ComfyUI/models/

COPY workflow/workflow.json /opt/ComfyUI/user/default/workflows/ltx_director.json

COPY start.sh /opt/start.sh
RUN chmod +x /opt/start.sh

EXPOSE 8188
WORKDIR /opt/ComfyUI
ENTRYPOINT ["/opt/start.sh"]
