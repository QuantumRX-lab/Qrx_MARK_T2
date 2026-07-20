# Stakeholders

| Stakeholder | Interest | Key needs |
|---|---|---|
| **Owner/operator** (W. T. Wallace) | Both brands run reliably with minimal manual intervention | Cron jobs fire on schedule; no false-failure noise; secrets don't leak; payment flow actually works |
| **Site visitors** (`.eu`) | Fresh daily content (comic, meme, news feeds) | Pages load (200s), content updates daily, no stale caches |
| **Report buyers** (`.co.uk`) | Order a report, receive a working licence key | Lemon Squeezy's own native fulfillment delivers the licence key; `api/ls-webhook.js` (an incomplete Ghost-CRM-labelling side path, unused stub) was deleted 2026-07-20 — see `RISK-INFRA-004` |
| **Break the Sentinel players** | A working, fair prompt-injection challenge | Q-Sentinel correctly distinguishes real game attempts from false positives |
| **AI agents (Claude Code sessions)** | Enough infra context to work without re-discovering everything from scratch each session | This MBSE tree + `STACK-OVERVIEW.md` + `crawler.py` output |
| **Google Analytics / Ghost / Lemon Squeezy / Vercel / Railway** (external platforms) | Correctly configured integration | Valid API keys, correctly scoped webhooks, matching measurement IDs |
