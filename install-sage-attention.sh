#!/bin/bash
# Build + install SageAttention from source (needs GPU host CUDA toolkit).
# Required for Blackwell (sm120, 170HX) — prebuilt wheels don't bundle sm120 kernels.
# Idempotent: skips if already installed.
set -uo pipefail
PYBIN="${COMFY_PYTHON:-/opt/comfyui-venv/bin/python3}"

if [ "${INSTALL_SAGE_ATTENTION:-0}" != "1" ]; then
    echo "[sageattn] INSTALL_SAGE_ATTENTION != 1 — skipping"
    exit 0
fi

if "$PYBIN" -c "import sageattention" 2>/dev/null; then
    echo "[sageattn] already installed — skipping"
    exit 0
fi

echo "[sageattn] Building SageAttention from source (this takes several minutes)..."
mkdir -p /opt/sageattn
cd /opt/sageattn
if [ ! -d SageAttention ]; then
    git clone --depth 1 --branch abi3_stable https://github.com/woct0rdho/SageAttention.git
    cd SageAttention
else
    cd SageAttention
    git fetch --depth 1 origin abi3_stable && git reset --hard FETCH_HEAD
fi

# Ensure triton (SageAttention dependency)
"$PYBIN" -m pip install -q triton 2>/dev/null || true

echo "[sageattn] Building wheel..."
if "$PYBIN" setup.py bdist_wheel --verbose >/tmp/sageattn-build.log 2>&1; then
    WHL=$(ls -t dist/*.whl 2>/dev/null | head -1)
    if [ -n "$WHL" ]; then
        "$PYBIN" -m pip install -q "$WHL"
        echo "[sageattn] installed: $WHL"
        echo "ready" > /tmp/sageattn-status
    else
        echo "[sageattn] build finished but no wheel found" >&2
        echo "failed" > /tmp/sageattn-status
    fi
else
    echo "[sageattn] BUILD FAILED — see /tmp/sageattn-build.log" >&2
    tail -20 /tmp/sageattn-build.log >&2
    echo "failed" > /tmp/sageattn-status
fi

# Mark done so start.sh can add --use-sage-attention
if "$PYBIN" -c "import sageattention" 2>/dev/null; then
    touch /opt/sageattn/INSTALLED
fi
