#!/bin/bash
# =============================================================================
# install-on-clore.sh
#
# Install the full moneywaters LTX / ComfyUI stack on a *standard* Clore image
# (e.g. cloreai/jupyter:ubuntu24.04-v2) after SSH is working.
#
# Usage (on the Clore pod):
#   curl -fsSL https://raw.githubusercontent.com/moneywaters/comfyui-ltx-docker/main/install-on-clore.sh | bash
#   # or, from a cloned repo:
#   bash install-on-clore.sh
#
# Env knobs:
#   INSTALL_ROOT=/opt                 # prefix for ComfyUI + venv
#   SKIP_MODEL_DOWNLOAD=0|1           # skip ~45GB model pull
#   BACKGROUND_MODELS=1|0            # download models in background (default 1)
#   START_COMFYUI=1|0                 # start ComfyUI when install finishes (default 1)
#   REPO_URL=https://github.com/moneywaters/comfyui-ltx-docker.git
#   REPO_REF=main
#   COMFYUI_PORT=8188
# =============================================================================
set -uo pipefail

log()  { echo "[install-on-clore] $*"; }
warn() { echo "[install-on-clore] WARN: $*" >&2; }
die()  { echo "[install-on-clore] ERROR: $*" >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive
INSTALL_ROOT="${INSTALL_ROOT:-/opt}"
COMFYUI_PATH="${COMFYUI_PATH:-$INSTALL_ROOT/ComfyUI}"
VENV="${VENV:-$INSTALL_ROOT/comfyui-venv}"
FIXES="${FIXES:-$INSTALL_ROOT/comfyui-fixes}"
WORKSPACE="${WORKSPACE:-/workspace}"
SKIP_MODEL_DOWNLOAD="${SKIP_MODEL_DOWNLOAD:-0}"
BACKGROUND_MODELS="${BACKGROUND_MODELS:-1}"
START_COMFYUI="${START_COMFYUI:-1}"
REPO_URL="${REPO_URL:-https://github.com/moneywaters/comfyui-ltx-docker.git}"
REPO_REF="${REPO_REF:-main}"
COMFYUI_PORT="${COMFYUI_PORT:-8188}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
STAGING="${STAGING:-/tmp/ltx-clore-setup}"

if [ "$(id -u)" -ne 0 ]; then
    die "run as root (Clore containers are root)"
fi

# ---------------------------------------------------------------------------
# 1) System packages
# ---------------------------------------------------------------------------
log "Installing system packages..."
apt-get update -qq
apt-get install -y --no-install-recommends \
    git wget curl xz-utils ca-certificates \
    libsndfile1 libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 libgomp1 \
    ffmpeg gcc g++ build-essential python3-venv python3-dev python3-pip \
    || apt-get install -y --no-install-recommends \
        git wget curl xz-utils ca-certificates \
        libsndfile1 ffmpeg gcc g++ build-essential python3-venv python3-dev python3-pip

# Optional: NVENC ffmpeg (best-effort)
if [ ! -x /opt/ffmpeg/bin/ffmpeg ]; then
    log "Installing NVENC ffmpeg (best-effort)..."
    mkdir -p /opt/ffmpeg/bin
    if wget -q -O /tmp/ffmpeg.tar.xz \
        "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz"; then
        tar -xJf /tmp/ffmpeg.tar.xz -C /tmp
        FFDIR=$(find /tmp -maxdepth 1 -type d -name 'ffmpeg-*-linux64-gpl' | head -1)
        if [ -n "$FFDIR" ]; then
            cp -a "$FFDIR"/bin/ffmpeg "$FFDIR"/bin/ffprobe /opt/ffmpeg/bin/
            ln -sf /opt/ffmpeg/bin/ffmpeg /usr/local/bin/ffmpeg
            ln -sf /opt/ffmpeg/bin/ffprobe /usr/local/bin/ffprobe
            log "NVENC ffmpeg installed"
        fi
        rm -rf /tmp/ffmpeg* 2>/dev/null || true
    else
        warn "could not download NVENC ffmpeg; using distro ffmpeg"
    fi
fi
export PATH="/opt/ffmpeg/bin:${PATH}"

# ---------------------------------------------------------------------------
# 2) Staging: clone repo for nodes list, models script, workflow, fp8 fix
# ---------------------------------------------------------------------------
log "Fetching setup assets from $REPO_URL ($REPO_REF)..."
rm -rf "$STAGING"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/nodes.sh" ] && [ -f "$SCRIPT_DIR/download-models.sh" ]; then
    log "Using local repo copy at $SCRIPT_DIR"
    mkdir -p "$STAGING"
    cp -a "$SCRIPT_DIR/." "$STAGING/"
else
    git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$STAGING" \
        || git clone --depth 1 "$REPO_URL" "$STAGING"
fi

# ---------------------------------------------------------------------------
# 3) Python venv + PyTorch (CUDA 12.1 wheels — works on modern host drivers)
# ---------------------------------------------------------------------------
log "Creating venv at $VENV..."
python3 -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
pip install -U --no-cache-dir pip wheel setuptools
log "Installing PyTorch (cu121)..."
pip install --no-cache-dir torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu121

# ---------------------------------------------------------------------------
# 4) ComfyUI core
# ---------------------------------------------------------------------------
if [ ! -d "$COMFYUI_PATH/.git" ]; then
    log "Cloning ComfyUI -> $COMFYUI_PATH"
    rm -rf "$COMFYUI_PATH"
    git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_PATH"
else
    log "ComfyUI already present; pulling latest (best-effort)"
    git -C "$COMFYUI_PATH" pull --ff-only || true
fi

log "Installing ComfyUI requirements..."
pip install --no-cache-dir -r "$COMFYUI_PATH/requirements.txt"

# ---------------------------------------------------------------------------
# 5) Custom nodes (same pack list as image nodes.sh)
# ---------------------------------------------------------------------------
log "Installing custom nodes..."
mkdir -p "$COMFYUI_PATH/custom_nodes"

clone_node() {
    local url="$1" dir="$2"
    if [ -d "$COMFYUI_PATH/custom_nodes/$dir/.git" ]; then
        echo "  exists: $dir"
        return 0
    fi
    echo "  clone: $dir"
    git clone --depth 1 "$url" "$COMFYUI_PATH/custom_nodes/$dir" || warn "failed $dir"
}

clone_node "https://github.com/ltdrdata/ComfyUI-Manager.git" ComfyUI-Manager
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
  "https://github.com/WhatDreamsCost/WhatDreamsCost-ComfyUI.git WhatDreamsCost-ComfyUI"
do
    url=$(echo "$pair" | awk '{print $1}')
    dir=$(echo "$pair" | awk '{print $2}')
    clone_node "$url" "$dir"
done

# Node requirements
log "Installing custom node requirements..."
for req in "$COMFYUI_PATH"/custom_nodes/*/requirements.txt; do
    [ -f "$req" ] || continue
    pip install --no-cache-dir -r "$req" || warn "pip failed for $req"
done

pip install --no-cache-dir \
    piexif rotary-embedding-torch numexpr imageio-ffmpeg pykalman \
    "kornia==0.7.3" spandrel spandrel_extra_arches pandas segment-anything webcolors \
    sqlalchemy opencv-python-headless scikit-image matplotlib \
    || warn "extra pip packages had failures"

# ---------------------------------------------------------------------------
# 6) fp8 fix + workflow
# ---------------------------------------------------------------------------
log "Installing fp8 fix + workflow..."
mkdir -p "$FIXES" \
    "$COMFYUI_PATH/custom_nodes/00_fp8_embed_fix" \
    "$COMFYUI_PATH/user/default/workflows" \
    "$WORKSPACE/output" "$WORKSPACE/input" \
    "$COMFYUI_PATH/models"/{diffusion_models,latent_upscale_models,text_encoders,vae,loras}

if [ -f "$STAGING/fp8_embed_fix.py" ]; then
    cp -f "$STAGING/fp8_embed_fix.py" "$FIXES/"
fi
if [ -f "$STAGING/fp8_fix_node/prestartup_script.py" ]; then
    cp -f "$STAGING/fp8_fix_node/prestartup_script.py" "$COMFYUI_PATH/custom_nodes/00_fp8_embed_fix/"
    cp -f "$STAGING/fp8_fix_node/__init__.py" "$COMFYUI_PATH/custom_nodes/00_fp8_embed_fix/" 2>/dev/null || \
        echo '# fp8 fix prestartup only' > "$COMFYUI_PATH/custom_nodes/00_fp8_embed_fix/__init__.py"
    # Point prestartup at our FIXES path
    sed -i "s|/opt/comfyui-fixes|$FIXES|g" "$COMFYUI_PATH/custom_nodes/00_fp8_embed_fix/prestartup_script.py" 2>/dev/null || true
fi
if [ -f "$STAGING/workflow/LTX-fixed.json" ]; then
    cp -f "$STAGING/workflow/LTX-fixed.json" "$COMFYUI_PATH/user/default/workflows/"
fi

# ---------------------------------------------------------------------------
# 7) Helper scripts on PATH
# ---------------------------------------------------------------------------
install -m 0755 /dev/stdin /usr/local/bin/download-ltx-models <<'EOS'
#!/bin/bash
# Wrapper: re-exec image download-models.sh with COMFYUI models path
set -uo pipefail
COMFYUI_PATH="${COMFYUI_PATH:-/opt/ComfyUI}"
export M="${COMFYUI_PATH}/models"
SCRIPT="${LTX_STAGING:-/tmp/ltx-clore-setup}/download-models.sh"
if [ ! -f "$SCRIPT" ]; then
    echo "download-models.sh not found at $SCRIPT"
    exit 1
fi
# Patch hardcoded /opt/ComfyUI/models if needed
sed "s|/opt/ComfyUI/models|$M|g" "$SCRIPT" > /tmp/download-models-run.sh
chmod +x /tmp/download-models-run.sh
bash /tmp/download-models-run.sh
EOS

# Rewrite download-models to use COMFYUI_PATH
if [ -f "$STAGING/download-models.sh" ]; then
    sed "s|/opt/ComfyUI|$COMFYUI_PATH|g" "$STAGING/download-models.sh" > /opt/download-models.sh
    chmod +x /opt/download-models.sh
fi

# start-comfyui helper
cat > /usr/local/bin/start-comfyui <<EOF
#!/bin/bash
set -uo pipefail
export PATH="/opt/ffmpeg/bin:${VENV}/bin:\$PATH"
export COMFY_PYTHON="${VENV}/bin/python3"
export COMFYUI_PATH="${COMFYUI_PATH}"
export DISABLE_SSHD=1
export BACKGROUND_MODELS="\${BACKGROUND_MODELS:-1}"
export SKIP_MODEL_DOWNLOAD="\${SKIP_MODEL_DOWNLOAD:-0}"
cd "${COMFYUI_PATH}"
LOWVRAM="--lowvram"
[ "\${COMFYUI_NO_LOWVRAM:-0}" = "1" ] && LOWVRAM=""
exec "${VENV}/bin/python3" main.py \\
  --listen 0.0.0.0 --port ${COMFYUI_PORT} \\
  --enable-cors-header --disable-auto-launch --disable-smart-memory \\
  \$LOWVRAM \${COMFYUI_EXTRA_ARGS:-} \\
  --output-directory ${WORKSPACE}/output \\
  --input-directory ${WORKSPACE}/input
EOF
chmod +x /usr/local/bin/start-comfyui

# Copy start.sh adapted if present
if [ -f "$STAGING/start.sh" ]; then
    sed \
      -e "s|/opt/comfyui-venv|${VENV}|g" \
      -e "s|/opt/ComfyUI|${COMFYUI_PATH}|g" \
      -e "s|/opt/comfyui-fixes|${FIXES}|g" \
      -e "s|/workspace|${WORKSPACE}|g" \
      "$STAGING/start.sh" > /opt/start.sh
    chmod +x /opt/start.sh
fi

# ---------------------------------------------------------------------------
# 8) Models
# ---------------------------------------------------------------------------
export LTX_STAGING="$STAGING"
export COMFYUI_PATH
export SKIP_MODEL_DOWNLOAD
if [ "$SKIP_MODEL_DOWNLOAD" = "1" ]; then
    log "SKIP_MODEL_DOWNLOAD=1 — not pulling models"
    echo "skipped" > /tmp/models-status
elif [ "$BACKGROUND_MODELS" = "1" ]; then
    log "Starting model download in background (~45GB)..."
    echo "downloading" > /tmp/models-status
    nohup bash /opt/download-models.sh > /var/log/model-download.log 2>&1 &
    echo $! > /tmp/models-download.pid
    log "Model PID $(cat /tmp/models-download.pid) — log: /var/log/model-download.log"
else
    log "Downloading models (blocking)..."
    echo "downloading" > /tmp/models-status
    bash /opt/download-models.sh && echo "ready" > /tmp/models-status || echo "failed" > /tmp/models-status
fi

# ---------------------------------------------------------------------------
# 9) Optional: wire into Clore supervisord (if present)
# ---------------------------------------------------------------------------
if [ -d /etc/supervisor/conf.d ] && command -v supervisorctl >/dev/null 2>&1; then
    log "Writing supervisord program for ComfyUI..."
    cat > /etc/supervisor/conf.d/comfyui-ltx.conf <<EOF
[program:comfyui]
command=/usr/local/bin/start-comfyui
autostart=true
autorestart=true
startsecs=5
startretries=30
stdout_logfile=/var/log/supervisor/comfyui.log
stderr_logfile=/var/log/supervisor/comfyui.err
priority=25
EOF
    supervisorctl reread 2>/dev/null || true
    supervisorctl update 2>/dev/null || true
    supervisorctl start comfyui 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 10) Start ComfyUI now
# ---------------------------------------------------------------------------
log "Install complete."
log "  ComfyUI:  $COMFYUI_PATH"
log "  Python:   $VENV/bin/python3"
log "  Start:    start-comfyui"
log "  Models:   /opt/download-models.sh  (status: cat /tmp/models-status)"
log "  Smoke:    after UI is up — curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:${COMFYUI_PORT}/"

if [ "$START_COMFYUI" = "1" ]; then
    if pgrep -f "main.py.*--port ${COMFYUI_PORT}" >/dev/null 2>&1; then
        log "ComfyUI already running"
    else
        log "Starting ComfyUI on 0.0.0.0:${COMFYUI_PORT}..."
        nohup /usr/local/bin/start-comfyui >> /var/log/comfyui.log 2>&1 &
        echo $! > /tmp/comfyui.pid
        log "ComfyUI PID $(cat /tmp/comfyui.pid) — log: /var/log/comfyui.log"
        log "Wait ~1–3 min for node load, then open Clore HTTP port ${COMFYUI_PORT}"
    fi
fi

echo ""
echo "=== Done. On Clore, map HTTP port ${COMFYUI_PORT} and open the http_pub URL. ==="
echo "    SSH is already provided by the standard Clore image / autossh."
