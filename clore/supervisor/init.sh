#!/bin/bash
# Clore.ai-compatible SSH bootstrap (mirrors cloreai/jupyter:ubuntu24.04-v2).
# Clore injects SSH_PASSWORD and SSH_KEY as env vars at container start.
set -euo pipefail

cd /etc/supervisor/ || true

SSH_PASSWORD_SET=/etc/supervisor/SSH_PASSWORD_SET
SSH_INIT_SET=/etc/supervisor/SSH_INIT_SET
SSH_KEY_FILE=/root/.ssh/authorized_keys

mkdir -p /root/.ssh /run/sshd /var/run/sshd
chmod 700 /root/.ssh

if [ -n "${SSH_PASSWORD:-}" ]; then
    if [ ! -f "$SSH_PASSWORD_SET" ]; then
        echo "root:${SSH_PASSWORD}" | chpasswd
        touch "$SSH_PASSWORD_SET"
        if ! grep -q '^PermitRootLogin yes' /etc/ssh/sshd_config 2>/dev/null; then
            echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
        fi
    fi
    export SSH_PASSWORD=""
fi

if [ -n "${SSH_KEY:-}" ]; then
    if [ ! -f "$SSH_KEY_FILE" ] || [ ! -s "$SSH_KEY_FILE" ]; then
        echo "${SSH_KEY}" > "$SSH_KEY_FILE"
    else
        # append if not already present
        if ! grep -qF "${SSH_KEY}" "$SSH_KEY_FILE" 2>/dev/null; then
            echo "${SSH_KEY}" >> "$SSH_KEY_FILE"
        fi
    fi
    chmod 600 "$SSH_KEY_FILE"
    export SSH_KEY=""
fi

if [ -f "$SSH_INIT_SET" ]; then
    rm -f /etc/ssh/ssh_host_ecdsa_key /etc/ssh/ssh_host_ecdsa_key.pub \
          /etc/ssh/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key.pub \
          /etc/ssh/ssh_host_rsa_key /etc/ssh/ssh_host_rsa_key.pub
    ssh-keygen -A
    mkdir -p /run/sshd /var/run/sshd
    rm -f "$SSH_INIT_SET"
fi

# Prefer conf.d layout used by Clore official images
if [ -f /etc/supervisor/conf.d/supervisord.conf ]; then
    exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
fi
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
