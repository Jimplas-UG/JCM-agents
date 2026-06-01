# Read local Cursor billing hints and update backend/infra/subscriptions.json
# Usage: powershell -NoProfile -File scripts\sync-cursor-subscription-expiry.ps1
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Out = Join-Path $Root "backend\infra\subscriptions.json"
$Db = Join-Path $env:APPDATA "Cursor\User\globalStorage\state.vscdb"

if (-not (Test-Path $Db)) {
    Write-Error "Cursor state DB not found: $Db"
}

$py = @'
import json, sqlite3, sys
from datetime import date, datetime, timezone
from pathlib import Path

db = Path(r"%DB%")
out = Path(r"%OUT%")

conn = sqlite3.connect(db)
auth = {}
for key, value in conn.execute("SELECT key, value FROM ItemTable WHERE key LIKE 'cursorAuth/%'"):
    text = value.decode("utf-8", errors="replace") if isinstance(value, bytes) else str(value)
    auth[key.split("/", 1)[1]] = text

row = conn.execute(
    "SELECT value FROM ItemTable WHERE key = ?",
    ("src.vs.platform.reactivestorage.browser.reactiveStorageServiceImpl.persistentStorage.applicationUser",),
).fetchone()
app_user = json.loads(row[0]) if row else {}

onboarding = auth.get("onboardingDate", "")[:10]
plan = auth.get("stripeMembershipType") or app_user.get("membershipType") or "unknown"
sub_status = auth.get("stripeSubscriptionStatus") or app_user.get("subscriptionStatus") or "unknown"

def add_month(d):
    m, y = d.month + 1, d.year
    if m > 12:
        m, y = 1, y + 1
    day = min(d.day, 28 if m == 2 else 30 if m in (4, 6, 9, 11) else 31)
    return date(y, m, day)

expires = None
source = "manual"
notes = ""
if onboarding:
    anchor = date.fromisoformat(onboarding)
    today = date.today()
    nxt = anchor
    while nxt <= today:
        nxt = add_month(nxt)
    expires = nxt.isoformat()
    source = "estimated_monthly_from_signup"
    notes = f"Next monthly renewal estimated from Cursor signup {onboarding}. Confirm at cursor.com/settings."

payload = {"updated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"), "subscriptions": []}
if out.exists():
    payload = json.loads(out.read_text(encoding="utf-8"))

subs = {s.get("id"): s for s in payload.get("subscriptions", [])}
cursor = subs.get("cursor", {"id": "cursor", "label": "Cursor Pro", "renew_url": "https://cursor.com/settings"})
if expires:
    cursor["expires_on"] = expires
cursor["plan"] = plan
cursor["billing_status"] = sub_status
if "status" in cursor:
    del cursor["status"]
cursor["source"] = source
if notes:
    cursor["notes"] = notes
subs["cursor"] = cursor
if "cloudzy" not in subs:
    subs["cloudzy"] = {
        "id": "cloudzy",
        "label": "Cloudzy VPS",
        "expires_on": "2026-06-23",
        "renew_url": "https://cloudzy.com",
        "source": "manual",
    }
payload["subscriptions"] = list(subs.values())
payload["updated_at"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"cursor_expires_on": expires, "plan": plan, "status": sub_status, "file": str(out)}, indent=2))
'@ -replace '%DB%', ($Db -replace '\\', '\\\\') -replace '%OUT%', ($Out -replace '\\', '\\\\')

$tmp = Join-Path $env:TEMP "sync-cursor-sub.py"
Set-Content -Path $tmp -Value $py -Encoding UTF8
python $tmp
Remove-Item $tmp -Force -ErrorAction SilentlyContinue
