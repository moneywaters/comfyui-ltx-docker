#!/bin/bash
set -euo pipefail
echo "=== Downloading models ==="
/opt/download-models.sh
echo "=== Starting ComfyUI ==="
cd /opt/ComfyUI
exec python3 main.py --listen 0.0.0.0 --port 8188 --output-directory /workspace/output --input-directory /workspace/input
