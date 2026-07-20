# Infrastructure — MBSE Tree

Model-based systems engineering tree for **cross-cutting QuantumRx infrastructure**:
hosting, secrets/environment variables, automation (cron), security (Q-Sentinel),
analytics (GA4), and payments (Lemon Squeezy) — across both brands:

- **quantumrx.eu / forge.quantumrx.eu** — Ghost + Vercel + Upstash KV + Railway
- **quantumrx.co.uk** — Hetzner VPS (nginx + systemd), the RSI product's own home

This is deliberately **not** a product requirements tree like `RSI` or `MIP` in the
Medha MBSE registry (`C:\Medha\MBSE\tools\`) — it documents the infrastructure both
brands run on, not a sellable product. Same methodology (INCOSE-style requirement
IDs, verification-by-test-case, decision log, risk register), scoped differently.

## Structure

| Folder | Contents |
|---|---|
| `00_need/` | Why this infra exists, what it's for |
| `01_stakeholders/` | Who depends on it, what they need from it |
| `02_requirements/` | `requirements.yaml` — L1 stakeholder + L2 system requirements |
| `03_architecture/` | Hosting topology, environment variable inventory, interfaces |
| `04_verification/` | `test_cases.yaml` — how each requirement is checked |
| `05_risks/` | `risk_register.yaml` — open/closed infra risks, including real findings from the 2026-07-20 audit |
| `06_decisions/` | `decision_log.yaml` — infra decisions with rationale (Railway migration, GitHub Actions disable, etc.) |
| `07_change/` | `CHANGELOG.md` — dated infra change history |
| `08_status/` | `dashboard.yaml` — machine-written by `crawler.py`, human-readable status snapshot |

## Keeping it current

Run `crawler.py` from this directory (or anywhere — it uses absolute checks) to
re-verify live status and rewrite `08_status/dashboard.yaml`:

```
python crawler.py
```

It checks page availability, feed freshness, cron trigger health (GitHub Actions
+ Railway inference), VPS service status and disk, and outstanding Sentinel
blocks — the same checks done manually in every "stack status check" this
session, now scripted. It requires SSH access to the VPS (`root@91.99.127.39`)
and a GitHub PAT / Upstash token — see `crawler.py`'s own header for what it
expects to find and where.
