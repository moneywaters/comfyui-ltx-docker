#!/bin/bash
set -euo pipefail

log() { echo "[start] $*"; }

# Prefer our NVENC-enabled ffmpeg if installed
if [ -x /opt/ffmpeg/bin/ffmpeg ]; then
    export PATH="/opt/ffmpeg/bin:$PATH"
fi

# --- SSH (self-contained for Clore/Vast/RunPod; skip if platform already runs sshd) ---
mkdir -p /var/run/sshd /root/.ssh
chmod 700 /root/.ssh

if [ ! -f /etc/ssh/ssh_host_rsa_key ] && [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
    ssh-keygen -A 2>/dev/null || true
fi

# Accept keys from common platform env vars
for _keyvar in AUTHORIZED_KEYS SSH_PUBLIC_KEY PUBLIC_KEY SSH_KEY; do
    eval "_kval=\${${_keyvar}:-}"
    if [ -n "${_kval}" ]; then
        echo "${_kval}" >> /root/.ssh/authorized_keys
    fi
done
# Clore/Vast sometimes drop keys into these files
for _kf in /root/.ssh/authorized_keys /ssh/authorized_keys /etc/ssh/authorized_keys; do
    if [ -f "$_kf" ] && [ "$_kf" != /root/.ssh/authorized_keys ]; then
        cat "$_kf" >> /root/.ssh/authorized_keys || true
    fi
done
if [ -f /root/.ssh/authorized_keys ]; then
    sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi

# Optional root password (Clore ssh_password / Vast)
if [ -n "${SSH_PASSWORD:-}" ]; then
    echo "root:${SSH_PASSWORD}" | chpasswd 2>/dev/null || true
    log "Root password set from SSH_PASSWORD"
elif [ -n "${PASSWORD:-}" ]; then
    echo "root:${PASSWORD}" | chpasswd 2>/dev/null || true
    log "Root password set from PASSWORD"
fi

if [ "${DISABLE_SSHD:-0}" != "1" ] && command -v /usr/sbin/sshd >/dev/null 2>&1; then
    if ! pgrep -x sshd >/dev/null 2>&1; then
        /usr/sbin/sshd -D -e >/var/log/sshd.log 2>&1 &
        sleep 0.5
        if pgrep -x sshd >/dev/null 2>&1; then
            log "SSH daemon started (self-managed)"
        else
            # foreground-style retry without -D background
            /usr/sbin/sshd || true
            log "SSH daemon start attempted (see /var/log/sshd.log)"
        fi
    else
        log "SSH daemon already running (platform-managed)"
    fi
fi

mkdir -p /workspace/output /workspace/input /opt/ComfyUI/user/default/workflows

# --- Model download strategy ---
# Env knobs:
#   SKIP_MODEL_DOWNLOAD=1     — never download (smoke tests)
#   WAIT_FOR_MODELS=1         — block until downloads finish
#   BACKGROUND_MODELS=0       — same as WAIT_FOR_MODELS=1
SKIP_MODEL_DOWNLOAD="${SKIP_MODEL_DOWNLOAD:-0}"
WAIT_FOR_MODELS="${WAIT_FOR_MODELS:-0}"
BACKGROUND_MODELS="${BACKGROUND_MODELS:-1}"

if [ "$WAIT_FOR_MODELS" = "1" ]; then
    BACKGROUND_MODELS=0
fi

if [ "$SKIP_MODEL_DOWNLOAD" = "1" ]; then
    log "SKIP_MODEL_DOWNLOAD=1 — skipping model downloads"
    echo "skipped" > /tmp/models-status
elif [ ! -x /opt/download-models.sh ]; then
    log "WARN: /opt/download-models.sh missing — skipping downloads"
    echo "missing" > /tmp/models-status
elif [ "$BACKGROUND_MODELS" = "0" ]; then
    log "Downloading models (blocking)..."
    echo "downloading" > /tmp/models-status
    /opt/download-models.sh && echo "ready" > /tmp/models-status || echo "failed" > /tmp/models-status
else
    log "Downloading models in background (ComfyUI will start now)..."
    echo "downloading" > /tmp/models-status
    # nohup+disown so the shell never blocks on the download job (Vast onstart
    # scripts have been observed to sit in do_wait on a plain & subshell).
    nohup bash -c '
        if /opt/download-models.sh; then
            echo ready > /tmp/models-status
            echo "[start] Background model download finished"
        else
            echo failed > /tmp/models-status
            echo "[start] Background model download finished with errors"
        fi
    ' >/var/log/model-download.log 2>&1 &
    echo $! > /tmp/models-download.pid
    disown $! 2>/dev/null || true
fi

if [ "${INSTALL_EXTRA_DEPS:-0}" = "1" ]; then
    /opt/conda/bin/pip install -q sqlalchemy opencv-python-headless scikit-image matplotlib || true
fi

# --- VHS encoder: AV1 NVENC on Ada+ (compute >= 8.9), else H.264 NVENC ---
# av1_nvenc is compiled into /opt/ffmpeg; Ampere (30xx) cannot encode AV1 in hardware.
WF_JSON="/opt/ComfyUI/user/default/workflows/LTX-fixed.json"
if [ -f "$WF_JSON" ] && command -v nvidia-smi >/dev/null 2>&1; then
    CAP=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ' || echo "0.0")
    # compare major.minor as float via awk
    USE_AV1=$(awk -v c="$CAP" 'BEGIN { print (c+0 >= 8.9) ? "1" : "0" }')
    if [ "$USE_AV1" = "1" ]; then
        VHS_FMT="video/nvenc_av1-mp4"
    else
        VHS_FMT="video/nvenc_h264-mp4"
    fi
    # Allow override
    /opt/conda/bin/python3 - "$WF_JSON" "$VHS_FMT" <<'PY' || true
import json, sys
path, fmt = sys.argv[1], sys.argv[2]
with open(path) as f:
    wf = json.load(f)
nchg = 0
for n in wf.get("nodes") or []:
    if n.get("type") != "VHS_VideoCombine":
        continue
    wv = n.get("widgets_values")
    if isinstance(wv, dict) and n.get("id") == 301:
        if wv.get("format") != fmt:
            wv["format"] = fmt
            nchg += 1
    elif isinstance(wv, dict) and "nvenc" in str(wv.get("format", "")):
        # secondary combines: keep software h264 if not 301
        pass
with open(path, "w") as f:
    json.dump(wf, f, indent=2)
    f.write("\n")
print(f"[start] VHS format for node 301 -> {fmt} (changes={nchg})", flush=True)
PY
    # Probe whether NVENC actually encodes (driver API may be too old for this ffmpeg)
    if echo "$VHS_FMT" | grep -q nvenc; then
        ENC=$(echo "$VHS_FMT" | sed -n "s|video/nvenc_\(.*\)-mp4|\1_nvenc|p")
        if ! ffmpeg -hide_banner -loglevel error -f lavfi -i color=c=black:s=64x64:d=0.04               -c:v "${ENC:-h264_nvenc}" -f null - 2>/dev/null; then
            log "NVENC encode probe failed for ${ENC} — falling back to software h264"
            VHS_FMT="video/h264-mp4"
        fi
    fi
    VHS_FMT="${COMFYUI_VHS_FORMAT:-$VHS_FMT}"
    log "GPU compute_cap=${CAP}; VHS format=${VHS_FMT}"
fi

# Log encoder availability
if command -v ffmpeg >/dev/null 2>&1; then
    log "ffmpeg: $(command -v ffmpeg)"
    ffmpeg -hide_banner -encoders 2>/dev/null | grep -E 'av1_nvenc|h264_nvenc|hevc_nvenc' || log "WARN: no nvenc encoders visible (needs NVIDIA driver at runtime)"
fi

# --- VRAM / allocator knobs ---
# NOTE: do NOT set expandable_segments by default — with this image's torch 2.5.1
# it can crash CUDA init:
#   Allocator backend parsed at runtime != allocator backend parsed at load time
if [ -n "${PYTORCH_CUDA_ALLOC_CONF:-}" ]; then
    export PYTORCH_CUDA_ALLOC_CONF
    log "PYTORCH_CUDA_ALLOC_CONF=$PYTORCH_CUDA_ALLOC_CONF"
fi
# fp8 fix is applied via custom_nodes/00_fp8_embed_fix/prestartup_script.py
# (must not import torch before ComfyUI CUDA init)

# ComfyUI CLI flags (override with COMFYUI_EXTRA_ARGS)


# --lowvram: stream weights to GPU layer-by-layer (critical for 22B + long video)
# --disable-smart-memory: avoid holding peak reserved memory
LOWVRAM_FLAG="--lowvram"
if [ "${COMFYUI_NO_LOWVRAM:-0}" = "1" ]; then
    LOWVRAM_FLAG=""
fi
EXTRA_ARGS="${COMFYUI_EXTRA_ARGS:-}"

log "Starting ComfyUI on 0.0.0.0:8188 (lowvram=${LOWVRAM_FLAG:-off})"
cd /opt/ComfyUI

# shellcheck disable=SC2086
exec /opt/conda/bin/python3 main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    --enable-cors-header \
    --disable-auto-launch \
    --disable-smart-memory \
    $LOWVRAM_FLAG \
    $EXTRA_ARGS \
    --output-directory /workspace/output \
    --input-directory /workspace/input
