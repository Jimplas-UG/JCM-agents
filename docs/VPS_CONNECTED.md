# VPS Connection — Confirmed

| Item | Value |
|------|--------|
| Host | `jcm-vps` (104.194.140.203) |
| OS | Windows Server 2022 |
| SSH user | Administrator |
| Project path | `C:\Users\Administrator\Documents\JCM agents\JCM-agents` |
| Runtime | Windows native (`start-platform.ps1`) — Docker Compose not active |
| BSv3.2 | Running (observer mode) |

## Cursor Remote SSH

1. `Ctrl+Shift+P` → **Remote-SSH: Connect to Host** → `jcm-vps`
2. **Open Folder:** `C:\Users\Administrator\Documents\JCM agents\JCM-agents`

## Platform status (verified via SSH)

- API: **healthy** (9 agents registered including marketing)
- Dashboard overview: BSv3.2 running, 20 active alerts, 10 marketing drafts
- MT5 bridge: not connected (check Bilshenz services on :8765)

## Live endpoints

| Service | URL |
|---------|-----|
| API health | http://104.194.140.203:8000/health |
| API docs | http://104.194.140.203:8000/docs |
| Dashboard | http://104.194.140.203:3000 |

## SSH from PC

```powershell
ssh jcm-vps
cd "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
```
