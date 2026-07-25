#!/bin/bash
# Clore.ai delegated entrypoint (same contract as cloreai/jupyter).
# Optional DELEGATED_ENTRYPOINT URL or local /etc/onstart.sh / /root/onstart.sh.

ONSTART_DEF_FILE=/etc/onstart.sh

if [ -f "$ONSTART_DEF_FILE" ] && [ ! -s "$ONSTART_DEF_FILE" ]; then
    rm -f "$ONSTART_DEF_FILE"
fi

download_entrypoint() {
    while true; do
        if wget -O "$ONSTART_DEF_FILE" "$DELEGATED_ENTRYPOINT"; then
            if [ -s "$ONSTART_DEF_FILE" ]; then
                chmod +x "$ONSTART_DEF_FILE"
                return 0
            else
                rm -f "$ONSTART_DEF_FILE"
            fi
        fi
        sleep 60
    done
}

if [ -n "${DELEGATED_ENTRYPOINT:-}" ]; then
    if [ -f "$ONSTART_DEF_FILE" ]; then
        chmod +x "$ONSTART_DEF_FILE"
    else
        download_entrypoint
    fi
    echo "Running $ONSTART_DEF_FILE"
    "$ONSTART_DEF_FILE" || echo "Failed to execute $ONSTART_DEF_FILE"
elif [ -x /root/onstart.sh ] && [ "${RUN_ROOT_ONSTART:-0}" = "1" ]; then
    # Only when explicitly requested — comfyui already runs via supervisord.
    /root/onstart.sh || true
else
    echo "DELEGATED_ENTRYPOINT is not set. Skipping download."
fi

while true; do
    sleep 60
done
