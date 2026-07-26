#!/bin/bash
# Idempotent preflight for Clore SSH contract.
# Official init.sh expects openssh + supervisor + SSH_INIT_SET marker.
# Safe to run at image build time; re-run at container start is optional.
set -euo pipefail

echo "[ensure-clore-ssh] checking Clore SSH prerequisites..."

# Packages that mon_container / reverse SSH need
if ! command -v /usr/sbin/sshd >/dev/null 2>&1; then
    echo "[ensure-clore-ssh] ERROR: /usr/sbin/sshd missing (install openssh-server)" >&2
    exit 1
fi
if ! command -v /usr/bin/supervisord >/dev/null 2>&1; then
    echo "[ensure-clore-ssh] ERROR: supervisord missing" >&2
    exit 1
fi
if [ ! -x /etc/supervisor/init.sh ]; then
    echo "[ensure-clore-ssh] ERROR: /etc/supervisor/init.sh missing or not executable" >&2
    exit 1
fi

mkdir -p /run/sshd /var/run/sshd /root/.ssh /var/log/supervisor /etc/supervisor/conf.d
chmod 700 /root/.ssh

# First-boot host-key regen marker used by official init.sh
if [ ! -f /etc/supervisor/SSH_INIT_SET ] && [ ! -f /etc/ssh/ssh_host_rsa_key ] && [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
    touch /etc/supervisor/SSH_INIT_SET
fi

# Container-friendly sshd defaults (init.sh also appends PermitRootLogin)
if [ -f /etc/ssh/sshd_config ]; then
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || true
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
    sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config || true
    grep -q '^PermitRootLogin yes' /etc/ssh/sshd_config || echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
    grep -q '^PasswordAuthentication yes' /etc/ssh/sshd_config || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
fi

# Host keys for images that ship without regenerating on first start
if [ ! -f /etc/ssh/ssh_host_rsa_key ] && [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
    ssh-keygen -A
fi

# Validate sshd config
/usr/sbin/sshd -t

echo "[ensure-clore-ssh] OK — CMD must be: bash -c /etc/supervisor/init.sh"
