# VPS Setup — Work With Cursor From Your PC (No Cursor on VPS)

Running Cursor **on** the VPS uses 2–4 GB+ RAM. The recommended setup:

```
Your PC (Cursor IDE)  ──SSH──►  VPS (Docker only: API, DB, dashboard)
```

You edit code locally or via **Remote SSH**; the VPS only runs containers.

---

## Step 1 — SSH key (one-time, on your Windows PC)

```powershell
ssh-keygen -t ed25519 -C "jcm-vps" -f "$env:USERPROFILE\.ssh\jcm_vps"
```

Copy the public key to the VPS:

```powershell
type $env:USERPROFILE\.ssh\jcm_vps.pub | ssh YOUR_USER@YOUR_VPS_IP "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

---

## Step 2 — Cursor Remote SSH (on your PC)

1. Install extension: **Remote - SSH** (Microsoft)
2. `Ctrl+Shift+P` → **Remote-SSH: Open SSH Configuration File**
3. Add:

```
Host jcm-vps
    HostName YOUR_VPS_IP
    User YOUR_USER
    IdentityFile C:\Users\YOUR_NAME\.ssh\jcm_vps
```

4. `Ctrl+Shift+P` → **Remote-SSH: Connect to Host** → `jcm-vps`
5. **File → Open Folder** → `/opt/jcm` (or your clone path)

Once connected, the AI agent runs commands **on the VPS** through your local Cursor.

---

## Step 3 — Prepare VPS (minimal RAM footprint)

SSH in (or use Remote SSH terminal):

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y git docker.io docker-compose-plugin curl

sudo usermod -aG docker $USER
# Log out and back in for docker group

sudo mkdir -p /opt/jcm
sudo chown $USER:$USER /opt/jcm
cd /opt/jcm

git clone https://github.com/Jimplas-UG/JCM-agents.git .
cp .env.example .env
nano .env   # set passwords, API URLs, EVENT_WEBHOOK_SECRET
```

---

## Step 4 — Deploy (one command)

```bash
chmod +x scripts/vps-deploy.sh
./scripts/vps-deploy.sh
```

Or manually:

```bash
docker compose pull
docker compose up -d --build

# If DB already existed before marketing tables:
docker exec -i jcm-postgres psql -U jcm_admin -d jcm_bsv32 < backend/db/migrations/002_marketing.sql
```

---

## Step 5 — Firewall (open only what you need)

| Port | Service |
|------|---------|
| 22 | SSH |
| 8000 | API (or reverse proxy only) |
| 3000 | Dashboard (or reverse proxy only) |
| 9090 | Prometheus (optional, internal) |

Do **not** expose 5432 (Postgres) or 6379 (Redis) publicly.

---

## RAM guide (typical)

| Service | Approx RAM |
|---------|------------|
| PostgreSQL | 200–400 MB |
| Redis | 50–100 MB |
| API + worker | 300–600 MB |
| Frontend | 150–300 MB |
| **Total Docker** | **~1–1.5 GB** |
| Cursor on VPS | **+2–4 GB** ❌ avoid |

---

## What to send your developer / AI assistant

Share **only** (never post passwords in chat):

- VPS IP address  
- SSH username  
- Confirm key is on `authorized_keys`  
- Path to project (e.g. `/opt/jcm`)  

Optional: create a limited deploy user:

```bash
sudo adduser jcmdeploy
sudo usermod -aG docker jcmdeploy
```

---

## Daily workflow

1. Open Cursor on **your PC** → Connect to `jcm-vps` via Remote SSH  
2. Pull latest: `git pull`  
3. Deploy: `./scripts/vps-deploy.sh`  
4. Logs: `docker compose logs -f api`  
5. Dashboard: `http://YOUR_VPS_IP:3000`

---

## Troubleshooting

```bash
docker compose ps
docker compose logs api --tail 100
curl http://localhost:8000/health
free -h
```

If OOM (out of memory): stop unused services, add swap:

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```
