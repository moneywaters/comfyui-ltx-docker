#!/bin/bash
# ComfyUI + optional model download.
# SSH is owned by Clore supervisor (cloreai/jupyter base) when DISABLE_SSHD=1.
# Must never block or replace PID1 sshd.
set -uo pipefail

log() { echo "[start] $*"; }

# Prefer NVENC ffmpeg, then venv python
if [ -x /opt/ffmpeg/bin/ffmpeg ]; then
    export PATH="/opt/ffmpeg/bin:$PATH"
fi

resolve_python() {
    if [ -n "${COMFY_PYTHON:-}" ] && [ -x "${COMFY_PYTHON}" ]; then
        echo "${COMFY_PYTHON}"
        return
    fi
    if [ -x /opt/comfyui-venv/bin/python3 ]; then
        echo /opt/comfyui-venv/bin/python3
        return
    fi
    if [ -x /opt/conda/bin/python3 ]; then
        echo /opt/conda/bin/python3
        return
    fi
    command -v python3
}

PYBIN="$(resolve_python)"
log "python=$PYBIN"

# --- Optional self-managed SSH (Vast / non-Clore). On Clore, supervisor already runs sshd. ---
mkdir -p /var/run/sshd /run/sshd /root/.ssh
chmod 700 /root/.ssh

if [ "${DISABLE_SSHD:-1}" != "1" ]; then
    if [ ! -f /etc/ssh/ssh_host_rsa_key ] && [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
        ssh-keygen -A 2>/dev/null || true
    fi
    for _keyvar in SSH_KEY AUTHORIZED_KEYS SSH_PUBLIC_KEY PUBLIC_KEY; do
        eval "_kval=\${${_keyvar}:-}"
        if [ -n "${_kval}" ]; then
            echo "${_kval}" >> /root/.ssh/authorized_keys
        fi
    done
    if [ -f /root/.ssh/authorized_keys ]; then
        sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
    fi
    if [ -n "${SSH_PASSWORD:-}" ]; then
        echo "root:${SSH_PASSWORD}" | chpasswd 2>/dev/null || true
    fi
    if command -v /usr/sbin/sshd >/dev/null 2>&1 && ! pgrep -x sshd >/dev/null 2>&1; then
        /usr/sbin/sshd || true
        log "self-managed sshd started"
    fi
else
    log "DISABLE_SSHD=1 — ComfyUI only (Clore/supervisor owns SSH)"
fi

mkdir -p /workspace/output /workspace/input /opt/ComfyUI/user/default/workflows

# --- Model download (background by default; never blocks SSH) ---
SKIP_MODEL_DOWNLOAD="${SKIP_MODEL_DOWNLOAD:-0}"
WAIT_FOR_MODELS="${WAIT_FOR_MODELS:-0}"
BACKGROUND_MODELS="${BACKGROUND_MODELS:-1}"

if [ "$WAIT_FOR_MODELS" = "1" ]; then
    BACKGROUND_MODELS=0
fi

if [ "$SKIP_MODEL_DOWNLOAD" = "1" ]; then
    log "SKIP_MODEL_DOWNLOAD=1"
    echo "skipped" > /tmp/models-status
elif [ ! -x /opt/download-models.sh ]; then
    log "WARN: download-models.sh missing"
    echo "missing" > /tmp/models-status
elif [ "$BACKGROUND_MODELS" = "0" ]; then
    log "Downloading models (blocking)..."
    echo "downloading" > /tmp/models-status
    /opt/download-models.sh && echo "ready" > /tmp/models-status || echo "failed" > /tmp/models-status
else
    log "Downloading models in background..."
    echo "downloading" > /tmp/models-status
    nohup bash -c '
        if /opt/download-models.sh; then
            echo ready > /tmp/models-status
            echo "[start] model download ready"
        else
            echo failed > /tmp/models-status
            echo "[start] model download failed"
        fi
    ' >/var/log/model-download.log 2>&1 &
    echo $! > /tmp/models-download.pid
    disown $! 2>/dev/null || true
fi

if [ "${INSTALL_EXTRA_DEPS:-0}" = "1" ]; then
    "$PYBIN" -m pip install -q sqlalchemy opencv-python-headless scikit-image matplotlib || true
fi

# --- VHS encoder format by GPU capability ---
WF_JSON="/opt/ComfyUI/user/default/workflows/LTX-fixed.json"
if [ -f "$WF_JSON" ] && command -v nvidia-smi >/dev/null 2>&1; then
    CAP=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ' || echo "0.0")
    USE_AV1=$(awk -v c="$CAP" 'BEGIN { print (c+0 >= 8.9) ? "1" : "0" }')
    if [ "$USE_AV1" = "1" ]; then
        VHS_FMT="video/nvenc_av1-mp4"
    else
        VHS_FMT="video/nvenc_h264-mp4"
    fi
    "$PYBIN" - "$WF_JSON" "$VHS_FMT" <<'PY' || true
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
with open(path, "w") as f:
    json.dump(wf, f, indent=2)
    f.write("\n")
print(f"[start] VHS format node 301 -> {fmt} (changes={nchg})", flush=True)
PY
    if echo "$VHS_FMT" | grep -q nvenc; then
        ENC=$(echo "$VHS_FMT" | sed -n "s|video/nvenc_\(.*\)-mp4|\1_nvenc|p")
        if ! ffmpeg -hide_banner -loglevel error -f lavfi -i color=c=black:s=64x64:d=0.04 \
            -c:v "${ENC:-h264_nvenc}" -f null - 2>/dev/null; then
            log "NVENC probe failed — software h264"
            VHS_FMT="video/h264-mp4"
        fi
    fi
    VHS_FMT="${COMFYUI_VHS_FORMAT:-$VHS_FMT}"
    log "compute_cap=${CAP}; VHS=${VHS_FMT}"
fi

if [ -n "${PYTORCH_CUDA_ALLOC_CONF:-}" ]; then
    export PYTORCH_CUDA_ALLOC_CONF
fi

LOWVRAM_FLAG="--lowvram"
if [ "${COMFYUI_NO_LOWVRAM:-0}" = "1" ]; then
    LOWVRAM_FLAG=""
fi
EXTRA_ARGS="${COMFYUI_EXTRA_ARGS:-}"

log "Starting ComfyUI on 0.0.0.0:8188 (lowvram=${LOWVRAM_FLAG:-off})"
cd /opt/ComfyUI

# Guard: if something already bound 8188 (e.g. supervisor started us and SimplePod
# also ran this script), don't start a second server.
if command -v python3 >/dev/null 2>&1 && python3 -c "import socket,sys; s=socket.socket(); sys.exit(0 if s.connect_ex(('127.0.0.1',8188))==0 else 1)" 2>/dev/null; then
    log "Port 8188 already in use — skipping duplicate start (assuming supervisor owns it)."
    exec sleep infinity
fi

# shellcheck disable=SC2086
exec "$PYBIN" main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    --enable-cors-header \
    --disable-auto-launch \
    --disable-smart-memory \
    $LOWVRAM_FLAG \
    $EXTRA_ARGS \
    --output-directory /workspace/output \
    --input-directory /workspace/input
