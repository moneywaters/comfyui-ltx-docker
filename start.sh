#!/bin/bash
set -euo pipefail

log() { echo "[start] $*"; }

# --- SSH (needed on Clore/Vast/etc. for remote access) ---
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -A
fi

mkdir -p /root/.ssh
chmod 700 /root/.ssh

if [ -n "${AUTHORIZED_KEYS:-}" ]; then
    echo "$AUTHORIZED_KEYS" >> /root/.ssh/authorized_keys
fi
if [ -f /root/.ssh/authorized_keys ]; then
    chmod 600 /root/.ssh/authorized_keys
fi

if command -v /usr/sbin/sshd >/dev/null 2>&1; then
    # Don't fail boot if sshd is already running (Vast may inject its own).
    /usr/sbin/sshd || true
    log "SSH daemon started (or already running)"
fi

mkdir -p /workspace/output /workspace/input /opt/ComfyUI/user/default/workflows

# --- Model download strategy ---
# Default: download in BACKGROUND so ComfyUI UI is reachable immediately.
# The classic "stuck on logo" experience is usually "ComfyUI never started yet
# because start.sh is still wget'ing ~48GB of weights."
#
# Env knobs:
#   SKIP_MODEL_DOWNLOAD=1     — never download (smoke tests / node verification)
#   WAIT_FOR_MODELS=1         — block until downloads finish (old behavior)
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
    (
        if /opt/download-models.sh; then
            echo "ready" > /tmp/models-status
            log "Background model download finished"
        else
            echo "failed" > /tmp/models-status
            log "Background model download finished with errors"
        fi
    ) >/var/log/model-download.log 2>&1 &
    echo $! > /tmp/models-download.pid
fi

# Optional extra pip deps (hosts with older images / overridden entrypoints)
if [ "${INSTALL_EXTRA_DEPS:-0}" = "1" ]; then
    /opt/conda/bin/pip install -q sqlalchemy opencv-python-headless scikit-image matplotlib || true
fi

log "Starting ComfyUI on 0.0.0.0:8188"
cd /opt/ComfyUI

# --enable-cors-header: remote MCP / browser clients on other origins
# --disable-auto-launch: headless container, no local browser
exec /opt/conda/bin/python3 main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    --enable-cors-header \
    --disable-auto-launch \
    --output-directory /workspace/output \
    --input-directory /workspace/input
