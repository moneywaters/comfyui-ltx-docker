#!/bin/bash
set -euo pipefail

# SSH setup
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -A
fi

mkdir -p /root/.ssh
chmod 700 /root/.ssh

if [ -n "${AUTHORIZED_KEYS:-}" ]; then
    echo "$AUTHORIZED_KEYS" >> /root/.ssh/authorized_keys
fi

chmod 600 /root/.ssh/authorized_keys

/usr/sbin/sshd
echo "=== SSH daemon started ==="

echo "=== Downloading models ==="
/opt/download-models.sh
echo "=== Starting ComfyUI ==="
cd /opt/ComfyUI
exec /opt/conda/bin/python3 main.py --listen 0.0.0.0 --port 8188 --output-directory /workspace/output --input-directory /workspace/input
