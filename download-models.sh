#!/bin/bash
# Downloads MiniMax H3 (ComfyUI native) models into /opt/ComfyUI/models.
# Safe to re-run (skips existing files). Never aborts the whole script on one failure.
# Requires HF_TOKEN for the Comfy-Org/MiniMax-H3 gated repo.
set -uo pipefail

if [ "${SKIP_MODEL_DOWNLOAD:-0}" = "1" ]; then
    echo "=== SKIP_MODEL_DOWNLOAD=1 — not downloading models ==="
    exit 0
fi

if [ -z "${HF_TOKEN:-}" ]; then
    echo "ERROR: HF_TOKEN not set — required to download MiniMax H3 from Comfy-Org/MiniMax-H3"
    exit 1
fi

M=/opt/ComfyUI/models
mkdir -p "$M"/{diffusion_models,text_encoders,vae} "$M"/diffusion_models/h3

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
    if wget --header "Authorization: Bearer ${HF_TOKEN}" -q --show-progress --progress=dot:giga \
            -O "$M/$subdir/$name.partial" "$url"; then
        mv -f "$M/$subdir/$name.partial" "$M/$subdir/$name"
        echo "OK: $subdir/$name"
    else
        rm -f "$M/$subdir/$name.partial"
        echo "WARN: failed to download $name"
        FAILED=$((FAILED + 1))
    fi
}

# --- MiniMax H3 model set selector ---
# MODEL_SET=quality (default): non-pruned INT8 diffusion (34GB) + INT8 text encoder (27GB)
#   = best quality, needs 64GB+ VRAM (170HX). Goes in h3/ subfolder.
# MODEL_SET=pruned: pruned INT8 diffusion (21GB) + NVFP4 text encoder (16GB)
#   = fits 24GB VRAM (4090/3090), ~42GB disk total.
MODEL_SET="${MODEL_SET:-quality}"
mkdir -p "$M"/diffusion_models/h3

if [ "$MODEL_SET" = "pruned" ]; then
    echo "=== MODEL_SET=pruned (24GB VRAM set) ==="
    download diffusion_models "minimax_h3_fl2va_pruned_int8_convrot.safetensors" "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors"
    download text_encoders "qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors" "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"
else
    echo "=== MODEL_SET=quality (64GB VRAM set) ==="
    download diffusion_models/h3 "minimax_h3_fl2va_int8_convrot.safetensors" "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_fl2va_int8_convrot.safetensors"
    download text_encoders "qwen3vl_32b_minimax_h3_int8_convrot.safetensors" "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/text_encoders/qwen3vl_32b_minimax_h3_int8_convrot.safetensors"
fi
download vae           "minimax_h3_video_vae_fp16.safetensors" "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_video_vae_fp16.safetensors"
download vae           "minimax_h3_audio_vae_fp32.safetensors" "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_audio_vae_fp32.safetensors"

if [ "$FAILED" -gt 0 ]; then
    echo "=== Models finished with $FAILED failure(s) ==="
    exit 1
fi
echo "=== MiniMax H3 models ready ==="
exit 0
