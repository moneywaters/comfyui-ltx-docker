#!/bin/bash
# Launch a cheap Vast.ai instance of moneywaters/comfyui-ltx:latest
# WITHOUT downloading ~48GB models — for node/UI smoke tests only.
#
# Usage:
#   bash vast-smoke-launch.sh              # search + create
#   bash vast-smoke-launch.sh <OFFER_ID>   # create specific offer
set -euo pipefail

IMAGE="${IMAGE:-moneywaters/comfyui-ltx:latest}"
DISK="${DISK:-40}"
LABEL="${LABEL:-comfyui-ltx-smoke}"

# Prefer newer GPUs as a proxy for AVX2 CPUs (PyTorch 2.5 needs AVX2).
search_offer() {
  vastai search offers \
    'gpu_ram>=10 reliability>=0.95 rentable=true verified=true direct_port_count>=1 dph_total<=0.15' \
    -o 'dph_total' --limit 15 --raw \
  | python3 -c '
import json,sys
offers=json.load(sys.stdin)
# Prefer RTX 3060/4060/3070/3080/3090 over ancient cards
prefer=("RTX_4090","RTX_4080","RTX_4070","RTX_4060","RTX_3090","RTX_3080","RTX_3070","RTX_3060","RTX A4000","RTX A5000")
def score(o):
    name=o.get("gpu_name") or ""
    rank=99
    for i,p in enumerate(prefer):
        if p.replace("_"," ") in name or p in name:
            rank=i; break
    return (rank, o.get("dph_total", 99))
offers=sorted(offers, key=score)
if not offers:
    sys.exit("No offers found")
o=offers[0]
print(o["id"])
print("# selected offer %s gpu=%s dph=%s loc=%s cpu=%s" % (
    o.get("id"), o.get("gpu_name"), o.get("dph_total"), o.get("geolocation"), o.get("cpu_name")), file=sys.stderr)
'
}

OFFER_ID="${1:-}"
if [ -z "$OFFER_ID" ]; then
  echo "Searching for a cheap AVX2-friendly offer..."
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
echo "  # wait until actual_status=running, then:"
echo "  vastai execute <ID> 'bash /opt/smoke-test.sh'"
echo "  # or SSH and curl localhost:8188"
