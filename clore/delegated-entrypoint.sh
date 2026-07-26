#!/bin/bash
# Match cloreai/jupyter:ubuntu24.04-v2 contract exactly.
# Clore may set DELEGATED_ENTRYPOINT to a URL; otherwise idle.

ONSTART_DEF_FILE=/etc/onstart.sh

# Remove ONSTART_DEF_FILE if it exists and is 0 bytes
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
    "$ONSTART_DEF_FILE" || {
        echo "Failed to execute $ONSTART_DEF_FILE"
    }
else
    echo "DELEGATED_ENTRYPOINT is not set. Skipping download."
fi

while true; do
    sleep 60
done
