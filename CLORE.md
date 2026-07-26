# Deploy moneywaters/comfyui-ltx on Clore.ai

Based on [Clore Docker images](https://docs.clore.ai/for-renters/docker-images),
[How to connect](https://docs.clore.ai/for-renters/how-to-connect),
[Troubleshooting](https://docs.clore.ai/guides/getting-started/clore-troubleshooting),
and [ComfyUI guide](https://docs.clore.ai/guides/image-generation/comfyui).

## Why custom images failed (`mon_container=0`)

Clore health (`mon_container > 0`) and reverse SSH need a **running container PID1**
that starts **sshd on port 22**. Official `cloreai/jupyter:ubuntu24.04-v2` does:

1. `CMD bash -c /etc/supervisor/init.sh`
2. init applies `SSH_PASSWORD` / `SSH_KEY` env vars
3. starts `supervisord` → program `sshd` + app

Our previous builds either:

- dropped `CMD` / `ENTRYPOINT` (container exited immediately), or
- overwrote the Clore entry with `/opt/start.sh` only (no sshd), or
- lost `openssh-server` during package churn.

This image **keeps the official init** and only replaces the jupyter supervisord
program with ComfyUI.

## Order settings (required)

| Field | Value |
|-------|--------|
| **Image** | `moneywaters/comfyui-ltx:latest` (or `:clore`) |
| **Ports** | `22` = **tcp**, `8188` = **http** |
| **SSH password** | ≤32 chars (Clore limit), e.g. `CloreTemp123` |
| **SSH key** | your public key (≤3072 chars) |
| **Currency** | `CLORE-Blockchain` |
| **autossh_entrypoint** | `true` (CLI/API) |

Env vars Clore injects (do not put secrets in the image):

- `SSH_PASSWORD`
- `SSH_KEY`

Optional env for this image:

| Env | Default | Meaning |
|-----|---------|---------|
| `SKIP_MODEL_DOWNLOAD` | `0` | `1` = skip ~45GB LTX models |
| `BACKGROUND_MODELS` | `1` | download models in background |
| `COMFYUI_NO_LOWVRAM` | `0` | `1` = disable `--lowvram` |

## CLI deploy example

```bash
clore deploy <SERVER_ID> \
  --image moneywaters/comfyui-ltx:latest \
  --type on-demand \
  --currency CLORE-Blockchain \
  --ssh-password 'CloreTemp123' \
  --ssh-key "$(cat ~/.ssh/clore_ai.pub)" \
  --port 22:tcp \
  --port 8188:http
```

Python API:

```python
from clore_ai.client import CloreAI
c = CloreAI(api_key="...")
c.create_order(
    server_id=SERVER_ID,
    image="moneywaters/comfyui-ltx:latest",
    type="on-demand",
    currency="CLORE-Blockchain",
    ssh_password="CloreTemp123",
    ssh_key=open("...pub").read().strip(),
    ports={"22": "tcp", "8188": "http"},
    autossh_entrypoint="true",
)
```

## After order is Active

1. Wait until `mon_container >= 1` (usually 1–3 min after pull).
2. SSH (use **mapped** port from My Orders, not 22):

   ```bash
   ssh -i ~/.ssh/clore_ai -p <MAPPED_PORT> root@<pub_cluster_host>
   ```

   If your Mac routes Clore through a VPN/fake-ip (`198.18.x`), bind the LAN NIC:

   ```bash
   ssh -i ~/.ssh/clore_ai -p <PORT> -b 192.168.1.9 \
     -o IdentitiesOnly=yes root@$(dig @8.8.8.8 +short n1.xxx.clorecloud.net | head -1)
   ```

3. ComfyUI UI: `https://<http_pub>/` (Clore Cloudflare). First load can 502 while models download.
4. Workflow: load **LTX-fixed.json** from the workflow library.
5. Model status:

   ```bash
   cat /tmp/models-status          # downloading | ready | failed | skipped
   tail -f /var/log/model-download.log
   tail -f /var/log/supervisor/comfyui.log
   ```

## Smoke test (no 45GB models)

Deploy with env `SKIP_MODEL_DOWNLOAD=1`, then:

```bash
bash /opt/smoke-test.sh
# or
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8188/
```

## What runs inside

```
PID1: bash -c /etc/supervisor/init.sh
  └─ supervisord
       ├─ sshd -D                 # port 22 — required for Clore SSH
       ├─ /opt/start.sh           # ComfyUI :8188, models in background
       └─ /etc/delegated-entrypoint.sh
```

## Fallback: standard image + install script

If the custom image still fails on a host:

```bash
# Order: cloreai/jupyter:ubuntu24.04-v2 , ports 22/tcp + 8188/http
curl -fsSL https://raw.githubusercontent.com/moneywaters/comfyui-ltx-docker/main/install-on-clore.sh | bash
```

## Build & push

```bash
# GHA / Bitbucket pipeline builds Containerfile → moneywaters/comfyui-ltx:latest
docker build -f Containerfile -t moneywaters/comfyui-ltx:latest .
docker push moneywaters/comfyui-ltx:latest
docker tag moneywaters/comfyui-ltx:latest moneywaters/comfyui-ltx:clore
docker push moneywaters/comfyui-ltx:clore
```

Local verify of Clore contract (amd64):

```bash
podman run --rm --platform linux/amd64 --entrypoint bash moneywaters/comfyui-ltx:latest -c '
  test -x /etc/supervisor/init.sh && test -x /usr/sbin/sshd
  grep -q program:sshd /etc/supervisor/conf.d/supervisord.conf
  cat /proc/1/cmdline 2>/dev/null || true
  bash /opt/ensure-clore-ssh.sh
'
```
