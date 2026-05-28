# Marketing Agent — Operations Guide

Agent #9 in the JCM platform. **Supervisory only** — generates draft content for human approval. Never publishes automatically unless `MARKETING_AUTO_APPROVE=true` (not recommended).

## Responsibilities

- Weekly content batch (LinkedIn, X, Instagram)
- Trend signal scanning (AI finance, African fintech, macro, Uganda fixed income)
- Brand kit API (channels, pillars, compliance)
- Human review queue (`draft` → `approved` → `published`)

## API endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/marketing/brand` | Brand kit summary |
| GET | `/marketing/stats` | Queue counts + brand |
| GET | `/marketing/queue?status=draft` | Content queue |
| GET | `/marketing/trends` | Trend signals |
| POST | `/marketing/generate` | Generate pillar post or full batch |
| POST | `/marketing/cycle` | Run full agent cycle |
| POST | `/marketing/queue/{id}/approve` | Approve for publishing |
| POST | `/marketing/queue/{id}/reject` | Reject draft |

## Run cycle manually

```bash
curl -X POST http://localhost:8000/marketing/cycle
```

## Scheduler

Runs every **24 hours** via `agents-worker` (`marketing_agent`).

## Compliance

- Forbidden phrases enforced in `brand_kit.validate_content()`
- All posts include educational disclaimer templates
- No guaranteed returns, no signal selling

## Source docs

- `docs/BRAND_INTELLIGENCE.md`
- `docs/CONTENT_CALENDAR_4WEEKS.md`
- `docs/SOCIAL_POST_BANK.md`
