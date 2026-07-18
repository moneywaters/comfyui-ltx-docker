#!/bin/bash
# Launch moneywaters/comfyui-ltx:latest for REAL use (models download ~48GB).
#
# Offer selection prioritizes inet_down (download Mbps) because model pull
# time dominates first boot. Prefer 1000+ Mbps hosts; avoid <500 Mbps.
#
# Usage:
#   bash vast-full-launch.sh                 # auto-pick fastest DL offer
#   bash vast-full-launch.sh <OFFER_ID>      # use a specific offer
#   MIN_DL=2000 MAX_DPH=0.25 bash vast-full-launch.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
IMAGE="${IMAGE:-moneywaters/comfyui-ltx:latest}"
DISK="${DISK:-100}"          # models ~48GB + image + headroom
LABEL="${LABEL:-comfyui-ltx-full}"
MIN_DL="${MIN_DL:-1000}"     # Mbps — raise for faster first boot
MAX_DPH="${MAX_DPH:-0.25}"   # $/hr ceiling
MIN_GPU_RAM="${MIN_GPU_RAM:-12}"

search_offer() {
  # Sort by inet_down desc at the API, then re-rank with our scorer.
  vastai search offers \
    "gpu_ram>=${MIN_GPU_RAM} reliability>=0.95 rentable=true verified=true direct_port_count>=1 dph_total<=${MAX_DPH} inet_down>=${MIN_DL}" \
    -o 'inet_down-' --limit 40 --raw \
  | python3 "$ROOT/select-vast-offer.py" \
      --mode full \
      --min-dl "$MIN_DL" \
      --max-dph "$MAX_DPH" \
      --min-gpu-ram "$MIN_GPU_RAM"
}

OFFER_ID="${1:-}"
if [ -z "$OFFER_ID" ]; then
  echo "Searching offers (min download ${MIN_DL} Mbps, max \$${MAX_DPH}/hr)..."
  OFFER_ID=$(search_offer)
fi

echo "Creating FULL instance from offer $OFFER_ID (models will download in background)..."

# Vast --ssh overrides ENTRYPOINT — re-exec image start.sh.
# BACKGROUND_MODELS=1 (default): UI up first, ~48GB models download in parallel.
ONSTART='mkdir -p /var/run/sshd /workspace/output /workspace/input; /usr/sbin/sshd || true; export SKIP_MODEL_DOWNLOAD=0 BACKGROUND_MODELS=1; exec /opt/start.sh'

vastai create instance "$OFFER_ID" \
  --image "$IMAGE" \
  --ssh --direct \
  --disk "$DISK" \
  --label "$LABEL" \
  --env '-p 22:22 -p 8188:8188 -e SKIP_MODEL_DOWNLOAD=0 -e BACKGROUND_MODELS=1' \
  --onstart-cmd "$ONSTART" \
  --raw

echo
echo "Next:"
echo "  vastai show instance <ID> --raw   # wait until actual_status=running + ports"
echo "  # UI is usable ASAP; models continue in /var/log/model-download.log"
echo "  # status: cat /tmp/models-status   # downloading | ready | failed"
echo "  # When ready=ready, open mapped 8188 and load LTX-fixed.json"
echo "  # Destroy when done: vastai destroy instance <ID> -y"
