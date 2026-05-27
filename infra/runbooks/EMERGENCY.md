# BSv3.2 Emergency Runbooks

## Kill-Switch Recommended Alert

1. **Do NOT** auto-disable BSv3.2 — human decision required
2. Open CEO Dashboard → Risk panel
3. Verify drawdown metrics against account statement
4. If confirmed: pause BSv3.2 via MT5/Desk API (manual)
5. Acknowledge alert in dashboard
6. Review audit trail: `GET /dashboard/audit`

## MT5 Connection Lost

1. Infrastructure agent attempts auto-reconnect via Watchdog API
2. If unresolved after 3 retries: check VPS via SSH
3. Manual: restart MT5 terminal on VPS
4. Verify: `GET /dashboard/infrastructure`
5. Confirm trade events resume: watch WebSocket `/ws`

## API Service Failure

| Service | Remediation Endpoint | Manual Fallback |
|---------|---------------------|-----------------|
| Desk API | `POST {WATCHDOG}/remediate/desk` | Restart desk service |
| Forward Bot | `POST {WATCHDOG}/remediate/forward_bot` | Restart forward-bot |
| Watchdog | Contact infrastructure team | — |
| MT5 Bridge | `POST {MT5}/reconnect` | Restart MT5 |

## Drawdown Breach

1. Portfolio Risk Orchestrator flags `kill_switch_recommended`
2. Review open positions in Desk API
3. Consider manual position reduction (human only)
4. Lot scaling factor published to Redis `jcm:bsv32:lot_scaling` — informational input to BSv3.2 only

## Broker Execution Degradation

1. Check Execution Quality panel
2. If slippage trend worsening: reduce trade frequency manually
3. Review broker spread settings
4. Do not modify BSv3.2 filter logic without quant team approval
