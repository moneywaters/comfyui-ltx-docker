#!/bin/bash
# Clore autossh_entrypoint path: Clore may run this after/instead of image CMD.
# Start ComfyUI only (SSH is Clore-managed or already via supervisord).
set -euo pipefail
export DISABLE_SSHD=1
exec /opt/start.sh
