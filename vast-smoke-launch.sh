#!/bin/bash
# Launch moneywaters/comfyui-ltx:latest WITHOUT ~48GB models (node/UI smoke only).
# Still prefers decent inet_down so the Docker image (~8GB) pulls quickly.
#
# Usage:
#   bash vast-smoke-launch.sh              # search + create
#   bash vast-smoke-launch.sh <OFFER_ID>   # create specific offer
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
IMAGE="${IMAGE:-moneywaters/comfyui-ltx:latest}"
DISK="${DISK:-40}"
LABEL="${LABEL:-comfyui-ltx-smoke}"
MIN_DL="${MIN_DL:-300}"      # enough for a fast image pull
MAX_DPH="${MAX_DPH:-0.15}"
MIN_GPU_RAM="${MIN_GPU_RAM:-10}"

search_offer() {
  vastai search offers \
    "gpu_ram>=${MIN_GPU_RAM} reliability>=0.95 rentable=true verified=true direct_port_count>=1 dph_total<=${MAX_DPH} inet_down>=${MIN_DL}" \
    -o 'inet_down-' --limit 30 --raw \
  | python3 "$ROOT/select-vast-offer.py" \
      --mode smoke \
      --min-dl "$MIN_DL" \
      --max-dph "$MAX_DPH" \
      --min-gpu-ram "$MIN_GPU_RAM"
}

OFFER_ID="${1:-}"
if [ -z "$OFFER_ID" ]; then
  echo "Searching smoke offers (min download ${MIN_DL} Mbps for image pull)..."
  OFFER_ID=$(search_offer)
fi

echo "Creating instance from offer $OFFER_ID ..."

# Vast --ssh overrides ENTRYPOINT, so re-run start.sh with SKIP_MODEL_DOWNLOAD.
ONSTART='mkdir -p /var/run/sshd /workspace/output /workspace/input; /usr/sbin/sshd || true; export SKIP_MODEL_DOWNLOAD=1 BACKGROUND_MODELS=0; exec /opt/start.sh'

vastai create instance "$OFFER_ID" \
  --image "$IMAGE" \
  --ssh --direct \
  --disk "$DISK" \
  --label "$LABEL" \
  --env '-p 22:22 -p 8188:8188 -e SKIP_MODEL_DOWNLOAD=1 -e BACKGROUND_MODELS=0' \
  --onstart-cmd "$ONSTART" \
  --raw

echo
echo "Next:"
echo "  vastai show instances --raw"
echo "  # wait until actual_status=running, then SSH and:"
echo "  bash /opt/smoke-test.sh"
echo "  # Destroy: vastai destroy instance <ID> -y"
