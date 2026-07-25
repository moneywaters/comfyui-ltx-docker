#!/bin/bash
# Clore.ai autossh_entrypoint mode: Clore S6 manages SSH and runs this script.
# Hand off to /opt/start.sh with DISABLE_SSHD=1 so we don't fight Clore's sshd.
# Without Clore autossh, the image ENTRYPOINT is /opt/start.sh (self-managed SSH).
set -euo pipefail

echo "[onstart] Clore/onstart handoff -> /opt/start.sh (DISABLE_SSHD=1)"
export DISABLE_SSHD="${DISABLE_SSHD:-1}"
exec /opt/start.sh
