#!/bin/bash
# Clore-compatible PID1 bootstrap.
# SSH must come up FIRST and stay up regardless of ComfyUI / model downloads.
# Mirrors cloreai/jupyter contract: env SSH_KEY + SSH_PASSWORD.
set +e
exec > >(tee -a /var/log/clore-init.log) 2>&1
echo "[clore-init] start $(date -u)"

mkdir -p /run/sshd /var/run/sshd /root/.ssh /var/log /var/log/supervisor
chmod 700 /root/.ssh

# Container-friendly sshd
if [ -f /etc/ssh/sshd_config ]; then
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#\?UsePAM.*/UsePAM no/' /etc/ssh/sshd_config
    grep -q '^PermitRootLogin yes' /etc/ssh/sshd_config || echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
    grep -q '^PasswordAuthentication yes' /etc/ssh/sshd_config || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
    grep -q '^PubkeyAuthentication yes' /etc/ssh/sshd_config || echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config
    grep -q '^UsePAM no' /etc/ssh/sshd_config || echo 'UsePAM no' >> /etc/ssh/sshd_config
fi

# Host keys (regenerate once if marker present, else ensure they exist)
if [ -f /etc/supervisor/SSH_INIT_SET ]; then
    rm -f /etc/ssh/ssh_host_* 2>/dev/null
    ssh-keygen -A
    rm -f /etc/supervisor/SSH_INIT_SET
else
    [ -f /etc/ssh/ssh_host_rsa_key ] || [ -f /etc/ssh/ssh_host_ed25519_key ] || ssh-keygen -A
fi

# Clore injects these env vars (same names as official jupyter image)
if [ -n "${SSH_PASSWORD:-}" ]; then
    echo "root:${SSH_PASSWORD}" | chpasswd
    echo "[clore-init] root password set from SSH_PASSWORD"
fi
if [ -n "${SSH_KEY:-}" ]; then
    printf '%s\n' "${SSH_KEY}" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    echo "[clore-init] authorized_keys written from SSH_KEY"
fi
# Fallback env names
if [ -n "${AUTHORIZED_KEYS:-}" ] && [ ! -s /root/.ssh/authorized_keys ]; then
    printf '%s\n' "${AUTHORIZED_KEYS}" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi

# ---------- SSH FIRST (must not wait on models/comfy) ----------
if pgrep -x sshd >/dev/null 2>&1; then
    echo "[clore-init] sshd already running"
else
    /usr/sbin/sshd
    sleep 0.3
    if pgrep -x sshd >/dev/null 2>&1; then
        echo "[clore-init] sshd STARTED (independent of ComfyUI)"
    else
        echo "[clore-init] WARN: sshd failed first try, retry -D background"
        /usr/sbin/sshd -D -e >> /var/log/sshd.log 2>&1 &
        sleep 0.5
        pgrep -a sshd || echo "[clore-init] ERROR: sshd still not running"
    fi
fi

# ---------- ComfyUI + model downloads in background ----------
# Never block SSH. Failures here must not kill the container.
if [ -x /opt/start.sh ]; then
    (
        export DISABLE_SSHD=1
        # start.sh uses set -e; isolate so it cannot tear down PID1
        /opt/start.sh
    ) >> /var/log/comfyui.log 2>&1 &
    echo "[clore-init] ComfyUI launched in background pid=$!"
else
    echo "[clore-init] WARN: /opt/start.sh missing"
fi

echo "[clore-init] entering keep-alive (SSH should already work)"
# Keep container alive forever — sshd is daemonized
while true; do
    # restart sshd if it died
    if ! pgrep -x sshd >/dev/null 2>&1; then
        echo "[clore-init] sshd died, restarting"
        /usr/sbin/sshd || true
    fi
    sleep 30
done
