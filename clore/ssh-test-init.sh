#!/bin/bash
# Minimal PID1: start sshd using Clore SSH_KEY / SSH_PASSWORD, stay alive.
set +e
exec > >(tee -a /var/log/ssh-test-init.log) 2>&1
echo "[ssh-test] start $(date -u)"

mkdir -p /run/sshd /var/run/sshd /root/.ssh
chmod 700 /root/.ssh
ssh-keygen -A 2>/dev/null || true

if [ -n "${SSH_PASSWORD:-}" ]; then
    echo "root:${SSH_PASSWORD}" | chpasswd
    echo "[ssh-test] password set"
fi
if [ -n "${SSH_KEY:-}" ]; then
    printf '%s\n' "${SSH_KEY}" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    echo "[ssh-test] SSH_KEY installed"
fi

if ! pgrep -x sshd >/dev/null 2>&1; then
    /usr/sbin/sshd
    sleep 0.3
fi
pgrep -a sshd || /usr/sbin/sshd -D -e >> /var/log/sshd.log 2>&1 &
echo "[ssh-test] sshd up; waiting forever"

while true; do
    pgrep -x sshd >/dev/null 2>&1 || /usr/sbin/sshd
    sleep 30
done
