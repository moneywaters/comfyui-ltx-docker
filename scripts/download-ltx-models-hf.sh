#!/bin/bash
# Manual LTX model pull (Hugging Face URLs from download-models.sh).
# Usage on pod:
#   bash /opt/download-ltx-models-hf.sh
#   # or: nohup bash /opt/download-ltx-models-hf.sh >/var/log/hf-models.log 2>&1 &
set -uo pipefail

M="${COMFYUI_MODELS:-/opt/ComfyUI/models}"
LOG="${HF_MODELS_LOG:-/var/log/hf-models.log}"
STATUS="${HF_MODELS_STATUS:-/tmp/models-status}"
mkdir -p "$M"/{diffusion_models,latent_upscale_models,text_encoders,vae,loras}
mkdir -p "$(dirname "$LOG")"

# Prefer aria2c (multi-connection), else wget, else curl
dl_one() {
    local dest="$1" url="$2"
    if command -v aria2c >/dev/null 2>&1; then
        aria2c -x 8 -s 8 -k 1M -c --file-allocation=none \
            --summary-interval=10 -o "$(basename "$dest")" -d "$(dirname "$dest")" \
            "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -c --show-progress --progress=dot:giga -O "$dest.partial" "$url" \
            && mv -f "$dest.partial" "$dest"
    else
        curl -L --retry 5 --retry-delay 2 -C - -o "$dest.partial" "$url" \
            && mv -f "$dest.partial" "$dest"
    fi
}

download() {
    local subdir="$1" name="$2" url="$3"
    local path="$M/$subdir/$name"
    if [ -f "$path" ]; then
        local size
        size=$(stat -c%s "$path" 2>/dev/null || stat -f%z "$path" 2>/dev/null || echo 0)
        if [ "${size:-0}" -gt 1000000 ]; then
            echo "OK exists: $subdir/$name (${size} bytes)"
            return 0
        fi
        echo "WARN incomplete ($size), re-download: $subdir/$name"
        rm -f "$path" "$path.partial"
    fi
    echo "=== DOWNLOADING $subdir/$name ==="
    echo "URL: $url"
    if dl_one "$path" "$url"; then
        local size
        size=$(stat -c%s "$path" 2>/dev/null || stat -f%z "$path" 2>/dev/null || echo 0)
        echo "OK: $subdir/$name (${size} bytes)"
        return 0
    fi
    rm -f "$path.partial"
    echo "FAIL: $subdir/$name"
    return 1
}

echo "=== LTX HF model download start $(date -u) ===" | tee -a "$LOG"
echo "downloading" > "$STATUS"
FAILED=0

# Hugging Face links (same set as /opt/download-models.sh)
download diffusion_models \
  "ltx-2.3-22b-distilled-1.1_transformer_only_fp8_scaled.safetensors" \
  "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/diffusion_models/ltx-2.3-22b-distilled-1.1_transformer_only_fp8_scaled.safetensors" \
  || FAILED=$((FAILED+1))

download vae \
  "LTX23_video_vae_bf16.safetensors" \
  "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_video_vae_bf16.safetensors" \
  || FAILED=$((FAILED+1))

download vae \
  "LTX23_audio_vae_bf16.safetensors" \
  "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_audio_vae_bf16.safetensors" \
  || FAILED=$((FAILED+1))

download text_encoders \
  "ltx-2.3_text_projection_bf16.safetensors" \
  "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/text_encoders/ltx-2.3_text_projection_bf16.safetensors" \
  || FAILED=$((FAILED+1))

download text_encoders \
  "gemma-3-12b-it-heretic-v2_fp8_e4m3fn.safetensors" \
  "https://huggingface.co/DreamFast/gemma-3-12b-it-heretic-v2/resolve/main/comfyui/gemma-3-12b-it-heretic-v2_fp8_e4m3fn.safetensors" \
  || FAILED=$((FAILED+1))

download latent_upscale_models \
  "ltx-2.3-spatial-upscaler-x2-1.1.safetensors" \
  "https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors" \
  || FAILED=$((FAILED+1))

download diffusion_models \
  "MelBandRoformer_fp16.safetensors" \
  "https://huggingface.co/Kijai/MelBandRoFormer_comfy/resolve/main/MelBandRoformer_fp16.safetensors" \
  || FAILED=$((FAILED+1))

download loras \
  "ltx-2.3-22b-distilled-lora-1.1_fro90_ceil72_condsafe.safetensors" \
  "https://huggingface.co/TenStrip/LTX2.3_Distilled_Lora_1.1_Experiments/resolve/main/ltx-2.3-22b-distilled-lora-1.1_fro90_ceil72_condsafe.safetensors" \
  || FAILED=$((FAILED+1))

download loras \
  "ltx-2.3-id-lora-celebvhq-3k.safetensors" \
  "https://huggingface.co/Comfy-Org/ltx-2.3/resolve/main/split_files/loras/ltx-2.3-id-lora-celebvhq-3k.safetensors" \
  || FAILED=$((FAILED+1))

download loras \
  "ltx-2-19b-ic-lora-detailer.safetensors" \
  "https://huggingface.co/Lightricks/LTX-2-19b-IC-LoRA-Detailer/resolve/main/ltx-2-19b-ic-lora-detailer.safetensors" \
  || FAILED=$((FAILED+1))

download loras \
  "ltx-2.3-22b-ic-lora-union-control-ref0.5.safetensors" \
  "https://huggingface.co/Lightricks/LTX-2.3-22b-IC-LoRA-Union-Control/resolve/main/ltx-2.3-22b-ic-lora-union-control-ref0.5.safetensors" \
  || FAILED=$((FAILED+1))

# Workflow filename compatibility symlinks
cd "$M/diffusion_models"
[ -f ltx-2.3-22b-distilled-1.1_transformer_only_fp8_scaled.safetensors ] && \
    ln -sf ltx-2.3-22b-distilled-1.1_transformer_only_fp8_scaled.safetensors ltx-2.3-22b-dev.safetensors || true
cd "$M/text_encoders"
[ -f gemma-3-12b-it-heretic-v2_fp8_e4m3fn.safetensors ] && \
    ln -sf gemma-3-12b-it-heretic-v2_fp8_e4m3fn.safetensors comfy_gemma_3_12B_it.safetensors || true

echo "=== Summary $(date -u) ==="
du -sh "$M"/* 2>/dev/null || true
find "$M" -name "*.safetensors" -type f -exec ls -lh {} \; 2>/dev/null

if [ "$FAILED" -gt 0 ]; then
    echo "failed" > "$STATUS"
    echo "=== DONE with $FAILED failure(s) ==="
    exit 1
fi
echo "ready" > "$STATUS"
echo "=== Models ready ==="
exit 0
