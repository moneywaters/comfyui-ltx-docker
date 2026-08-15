#!/bin/bash
# runtime-extras.sh — installs UI-selected extras at pod boot (non-blocking, idempotent).
# Consumed env vars (set by the SimplePod UI as flags):
#   EXTRA_HF_MODELS   comma-separated HuggingFace repo ids
#   CIVITAI_LORAS     name1|url1;;name2|url2   (downloaded into models/loras)
#   CUSTOM_NODES      comma-separated git URLs (cloned into custom_nodes)
# Never aborts the whole script on one failure; safe to re-run.
set -uo pipefail

M=/opt/ComfyUI/models
PYBIN="${COMFY_PYTHON:-/opt/comfyui-venv/bin/python3}"

log() { echo "[runtime-extras] $*"; }

# --- Extra HuggingFace models ---
if [ -n "${EXTRA_HF_MODELS:-}" ]; then
    log "EXTRA_HF_MODELS=$EXTRA_HF_MODELS"
    if command -v huggingface-cli >/dev/null 2>&1; then
        IFS=',' read -ra REPOS <<< "$EXTRA_HF_MODELS"
        for repo in "${REPOS[@]}"; do
            repo=$(echo "$repo" | xargs)
            [ -z "$repo" ] && continue
            log "Downloading HF repo: $repo"
            HF_TOKEN="${HF_TOKEN:-}" huggingface-cli download "$repo" \
                --local-dir "$M/hf_extra/$(basename "$repo")" 2>&1 | tail -5 || \
                log "WARN: failed to download $repo"
        done
    else
        log "WARN: huggingface-cli not installed — skipping EXTRA_HF_MODELS"
    fi
fi

# --- CivitAI LoRAs ---
if [ -n "${CIVITAI_LORAS:-}" ]; then
    log "CIVITAI_LORAS present"
    mkdir -p "$M/loras"
    IFS=';;' read -ra PAIRS <<< "$CIVITAI_LORAS"
    for pair in "${PAIRS[@]}"; do
        [ -z "$pair" ] && continue
        name="${pair%%|*}"
        url="${pair#*|}"
        name=$(echo "$name" | tr -c 'A-Za-z0-9._-' '_')
        [ -z "$url" ] || [ "$url" = "$pair" ] && continue
        dest="$M/loras/$name.safetensors"
        if [ -f "$dest" ]; then
            log "LoRA exists: $name"
            continue
        fi
        log "Downloading LoRA: $name <- $url"
        if wget -q --show-progress -O "$dest.partial" "$url"; then
            mv -f "$dest.partial" "$dest"
            log "LoRA OK: $name"
        else
            rm -f "$dest.partial"
            log "WARN: failed LoRA $name"
        fi
    done
fi

# --- Custom nodes ---
if [ -n "${CUSTOM_NODES:-}" ]; then
    log "CUSTOM_NODES=$CUSTOM_NODES"
    mkdir -p /opt/ComfyUI/custom_nodes
    IFS=',' read -ra URLS <<< "$CUSTOM_NODES"
    for url in "${URLS[@]}"; do
        url=$(echo "$url" | xargs)
        [ -z "$url" ] && continue
        dir=$(basename "$url" .git)
        if [ -d "/opt/ComfyUI/custom_nodes/$dir/.git" ]; then
            log "Node exists: $dir"
            continue
        fi
        log "Cloning node: $dir <- $url"
        git clone --depth 1 "$url" "/opt/ComfyUI/custom_nodes/$dir" 2>&1 | tail -2 || \
            log "WARN: failed to clone $url"
    done
fi

log "runtime-extras done"
