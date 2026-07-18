#!/bin/bash
# Downloads LTX workflow models into /opt/ComfyUI/models.
# Safe to re-run (skips existing files). Never aborts the whole script on one failure.
set -uo pipefail

if [ "${SKIP_MODEL_DOWNLOAD:-0}" = "1" ]; then
    echo "=== SKIP_MODEL_DOWNLOAD=1 — not downloading models ==="
    exit 0
fi

M=/opt/ComfyUI/models
mkdir -p "$M"/{diffusion_models,latent_upscale_models,text_encoders,vae,loras}

if ! command -v wget >/dev/null 2>&1; then
    echo "ERROR: wget not found — install wget in the image (Containerfile apt packages)"
    exit 1
fi

FAILED=0
download() {
    local subdir="$1" name="$2" url="$3"
    if [ -f "$M/$subdir/$name" ]; then
        local size
        size=$(stat -c%s "$M/$subdir/$name" 2>/dev/null || stat -f%z "$M/$subdir/$name" 2>/dev/null || echo 0)
        if [ "${size:-0}" -gt 1000000 ]; then
            echo "OK exists: $subdir/$name (${size} bytes)"
            return 0
        fi
        echo "WARN incomplete ($size bytes), re-downloading: $subdir/$name"
        rm -f "$M/$subdir/$name"
    fi
    echo "Downloading: $subdir/$name"
    if wget -q --show-progress --progress=dot:giga -O "$M/$subdir/$name.partial" "$url"; then
        mv -f "$M/$subdir/$name.partial" "$M/$subdir/$name"
        echo "OK: $subdir/$name"
    else
        rm -f "$M/$subdir/$name.partial"
        echo "WARN: failed to download $name"
        FAILED=$((FAILED + 1))
    fi
}

download diffusion_models  "ltx-2.3-22b-distilled-1.1_transformer_only_fp8_scaled.safetensors" "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/diffusion_models/ltx-2.3-22b-distilled-1.1_transformer_only_fp8_scaled.safetensors"
download vae               "LTX23_video_vae_bf16.safetensors" "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_video_vae_bf16.safetensors"
download vae               "LTX23_audio_vae_bf16.safetensors" "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_audio_vae_bf16.safetensors"
download text_encoders     "ltx-2.3_text_projection_bf16.safetensors" "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/text_encoders/ltx-2.3_text_projection_bf16.safetensors"
download text_encoders     "gemma-3-12b-it-heretic-v2_fp8_e4m3fn.safetensors" "https://huggingface.co/DreamFast/gemma-3-12b-it-heretic-v2/resolve/main/comfyui/gemma-3-12b-it-heretic-v2_fp8_e4m3fn.safetensors"
download latent_upscale_models "ltx-2.3-spatial-upscaler-x2-1.1.safetensors" "https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors"
download diffusion_models  "MelBandRoformer_fp16.safetensors" "https://huggingface.co/Kijai/MelBandRoFormer_comfy/resolve/main/MelBandRoformer_fp16.safetensors"
download loras             "ltx-2.3-22b-distilled-lora-1.1_fro90_ceil72_condsafe.safetensors" "https://huggingface.co/TenStrip/LTX2.3_Distilled_Lora_1.1_Experiments/resolve/main/ltx-2.3-22b-distilled-lora-1.1_fro90_ceil72_condsafe.safetensors"
download loras             "ltx-2.3-id-lora-celebvhq-3k.safetensors" "https://huggingface.co/Comfy-Org/ltx-2.3/resolve/main/split_files/loras/ltx-2.3-id-lora-celebvhq-3k.safetensors"
download loras             "ltx-2-19b-ic-lora-detailer.safetensors" "https://huggingface.co/Lightricks/LTX-2-19b-IC-LoRA-Detailer/resolve/main/ltx-2-19b-ic-lora-detailer.safetensors"
download loras             "ltx-2.3-22b-ic-lora-union-control-ref0.5.safetensors" "https://huggingface.co/Lightricks/LTX-2.3-22b-IC-LoRA-Union-Control/resolve/main/ltx-2.3-22b-ic-lora-union-control-ref0.5.safetensors"

# Symlinks for workflow filename compatibility
cd "$M/diffusion_models"
[ -f ltx-2.3-22b-distilled-1.1_transformer_only_fp8_scaled.safetensors ] && \
    ln -sf ltx-2.3-22b-distilled-1.1_transformer_only_fp8_scaled.safetensors ltx-2.3-22b-dev.safetensors || true
cd "$M/text_encoders"
[ -f gemma-3-12b-it-heretic-v2_fp8_e4m3fn.safetensors ] && \
    ln -sf gemma-3-12b-it-heretic-v2_fp8_e4m3fn.safetensors comfy_gemma_3_12B_it.safetensors || true

if [ "$FAILED" -gt 0 ]; then
    echo "=== Models finished with $FAILED failure(s) ==="
    exit 1
fi
echo "=== Models ready ==="
exit 0
