#!/bin/bash
# Clore autossh_entrypoint may run this. SSH is already provided by Clore or
# by base-image supervisord — only start ComfyUI.
set +e
export DISABLE_SSHD=1
exec /opt/start.sh
