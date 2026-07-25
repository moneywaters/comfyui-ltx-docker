#!/bin/bash
# Clore autossh_entrypoint may invoke this. Prefer full init (SSH + ComfyUI).
# If SSH already up, start.sh with DISABLE_SSHD only starts ComfyUI.
set +e
if ! pgrep -x sshd >/dev/null 2>&1; then
    exec /etc/supervisor/init.sh
fi
export DISABLE_SSHD=1
exec /opt/start.sh
