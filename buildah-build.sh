#!/bin/bash
# ── buildah-build.sh — Runs inside CircleCI machine executor ──────
set -euo pipefail
IMAGE="docker.io/${DOCKER_USER:-moneywaters}/comfyui-ltx:latest"

echo "=== Installing buildah ==="
sudo apt-get update -qq
sudo apt-get install -y -qq buildah
echo 'unqualified-search-registries = ["docker.io"]' | sudo tee /etc/containers/registries.conf.d/docker.conf

echo "=== Login ==="
echo "${DOCKER_PASS:?}" | buildah login -u "${DOCKER_USER:?}" --password-stdin docker.io

echo "=== Pull base ==="
buildah pull docker.io/pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime
CONTAINER=$(buildah from docker.io/pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime)

echo "=== System deps ==="
buildah run "$CONTAINER" -- apt-get update -qq
buildah run "$CONTAINER" -- apt-get install -y --no-install-recommends git wget ffmpeg libsndfile1 libglib2.0-0 libsm6 libxext6 libxrender-dev libgomp1 gcc g++ build-essential -qq
buildah run "$CONTAINER" -- apt-get clean

echo "=== ComfyUI $(date) ==="
buildah run "$CONTAINER" -- git clone --depth 1 --quiet https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI
buildah run "$CONTAINER" -- pip install --progress-bar off -r /opt/ComfyUI/requirements.txt

echo "=== Custom nodes ==="
# Write a small batch script to install ALL nodes at once inside the container
buildah run "$CONTAINER" -- bash /opt/nodes_install.sh 2>/dev/null || {
  # Copy the install script into the container and run it
  buildah copy "$CONTAINER" "$(dirname "$0")/nodes.sh" /opt/nodes_install.sh
  buildah run "$CONTAINER" -- bash /opt/nodes_install.sh
}
echo "Nodes done $(date)"

echo "=== Pip deps ==="
buildah run "$CONTAINER" -- bash -c 'for req in /opt/ComfyUI/custom_nodes/*/requirements.txt; do [ -f "$req" ] && pip install -r "$req" || true; done'
buildah run "$CONTAINER" -- pip install piexif rotary-embedding-torch numexpr imageio-ffmpeg pykalman "kornia==0.7.3" spandrel spandrel_extra_arches pandas segment-anything webcolors

echo "=== Models ==="
buildah run "$CONTAINER" -- mkdir -p /opt/ComfyUI/models/{diffusion_models,latent_upscale_models,text_encoders,vae,loras}
buildah run "$CONTAINER" -- wget -q --show-progress -P /opt/ComfyUI/models/diffusion_models "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/diffusion_models/ltx-2.3-22b-distilled-1.1_transformer_only_fp8_scaled.safetensors"
echo "1/11 $(date)"
buildah run "$CONTAINER" -- wget -q --show-progress -P /opt/ComfyUI/models/vae "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_video_vae_bf16.safetensors"
buildah run "$CONTAINER" -- wget -q --show-progress -P /opt/ComfyUI/models/vae "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_audio_vae_bf16.safetensors"
buildah run "$CONTAINER" -- wget -q --show-progress -P /opt/ComfyUI/models/text_encoders "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/text_encoders/ltx-2.3_text_projection_bf16.safetensors"
buildah run "$CONTAINER" -- wget -q --show-progress -P /opt/ComfyUI/models/text_encoders "https://huggingface.co/DreamFast/gemma-3-12b-it-heretic-v2/resolve/main/comfyui/gemma-3-12b-it-heretic-v2_fp8_e4m3fn.safetensors"
buildah run "$CONTAINER" -- wget -q --show-progress -P /opt/ComfyUI/models/latent_upscale_models "https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors"
buildah run "$CONTAINER" -- wget -q --show-progress -P /opt/ComfyUI/models/diffusion_models "https://huggingface.co/Kijai/MelBandRoFormer_comfy/resolve/main/MelBandRoformer_fp16.safetensors"
buildah run "$CONTAINER" -- wget -q --show-progress -P /opt/ComfyUI/models/loras "https://huggingface.co/TenStrip/LTX2.3_Distilled_Lora_1.1_Experiments/resolve/main/ltx-2.3-22b-distilled-lora-1.1_fro90_ceil72_condsafe.safetensors"
buildah run "$CONTAINER" -- wget -q --show-progress -P /opt/ComfyUI/models/loras "https://huggingface.co/Comfy-Org/ltx-2.3/resolve/main/split_files/loras/ltx-2.3-id-lora-celebvhq-3k.safetensors"
buildah run "$CONTAINER" -- wget -q --show-progress -P /opt/ComfyUI/models/loras "https://huggingface.co/Lightricks/LTX-2-19b-IC-LoRA-Detailer/resolve/main/ltx-2-19b-ic-lora-detailer.safetensors"
buildah run "$CONTAINER" -- wget -q --show-progress -P /opt/ComfyUI/models/loras "https://huggingface.co/Lightricks/LTX-2.3-22b-IC-LoRA-Union-Control/resolve/main/ltx-2.3-22b-ic-lora-union-control-ref0.5.safetensors"
echo "Models done $(date)"

echo "=== Config ==="
buildah run "$CONTAINER" -- bash -c 'echo "#!/bin/bash" > /opt/start.sh && echo "cd /opt/ComfyUI && mkdir -p /workspace/output /workspace/input && python3 main.py --listen 0.0.0.0 --port 8188" >> /opt/start.sh && chmod +x /opt/start.sh'
buildah config --entrypoint '["/opt/start.sh"]' --port 8188 --workingdir /opt/ComfyUI "$CONTAINER"

echo "=== Commit $(date) ==="
buildah commit "$CONTAINER" "$IMAGE"
echo "=== Push $(date) ==="
buildah push "$IMAGE"
echo "=== DONE $(date) — $IMAGE ==="
