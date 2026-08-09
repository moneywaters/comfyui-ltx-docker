#!/bin/bash
set -euo pipefail
cd /opt/ComfyUI/custom_nodes

git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git ComfyUI-Manager

for pair in \
  "https://github.com/rgthree/rgthree-comfy.git rgthree-comfy" \
  "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git ComfyUI-Impact-Pack" \
  "https://github.com/ltdrdata/ComfyUI-Inspire-Pack.git ComfyUI-Inspire-Pack" \
  "https://github.com/chflame163/ComfyUI_LayerStyle.git ComfyUI_LayerStyle" \
  "https://github.com/yolain/ComfyUI-Easy-Use.git ComfyUI-Easy-Use" \
  "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git ComfyUI-VideoHelperSuite" \
  "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git ComfyUI-Custom-Scripts" \
  "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git ComfyUI-Frame-Interpolation" \
  "https://github.com/kijai/ComfyUI-MelBandRoFormer.git comfyui-melbandroformer" \
  "https://github.com/Fannovel16/comfyui_controlnet_aux.git comfyui_controlnet_aux" \
  "https://github.com/kijai/ComfyUI-KJNodes.git ComfyUI-KJNodes" \
  "https://github.com/FizzleDorf/ComfyUI_FizzNodes.git ComfyUI-FizzNodes" \
  "https://github.com/WASasquatch/was-node-suite-comfyui.git WAS-Node-Suite-ComfyUI" \
  "https://github.com/Lightricks/ComfyUI-LTXVideo.git ComfyUI-LTXVideo" \
  "https://github.com/kijai/ComfyUI-LivePortraitKJ.git ComfyUI-LivePortraitKJ" \
  "https://github.com/Azornes/Comfyui-Resolution-Master.git Comfyui-Resolution-Master" \
  "https://github.com/BetaDoggo/comfyui-rtx-simple.git comfyui-rtx-simple" \
  "https://github.com/chrisgoringe/cg-use-everywhere.git cg-use-everywhere" \
  "https://github.com/malkuthro/ComfyUI-Koolook.git ComfyUI-Koolook" \
  "https://github.com/artokun/comfyui-mcp-panel.git comfyui-mcp-panel" \
  "https://github.com/dseditor/ComfyUI-ListHelper.git ComfyUI-ListHelper" \
  "https://github.com/WhatDreamsCost/WhatDreamsCost-ComfyUI.git WhatDreamsCost-ComfyUI" \
  "https://github.com/pixaroma/ComfyUI-Pixaroma.git ComfyUI-Pixaroma"; do
  url=$(echo "$pair" | awk '{print $1}')
  dir=$(echo "$pair" | awk '{print $2}')
  echo "Cloning $dir ..."
  git clone --depth 1 "$url" "$dir"
done

echo "=== Custom nodes cloned ==="
ls -1
