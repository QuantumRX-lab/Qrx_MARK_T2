# Infrastructure Changelog

Dated log of infrastructure-level changes (not product/content changes —
those belong to their own history). Newest first.

## 2026-07-20
- Built this MBSE tree (`mbse/infrastructure/`) and `crawler.py` following a full audit of both stacks.
- Confirmed `CRON.txt` has zero git history (RISK-INFRA-005).
- `api/ls-webhook.js` deleted — owner confirmed it was an unused stub, never wired into production (D-INFRA-008, closes RISK-INFRA-004).
- `ANTHROPIC_API_KEY` on Vercel confirmed intentional occasional/manual use, not dead config (closes RISK-INFRA-006).

## 2026-07-17
- VPS: nav CTA renamed "Order a Report" → "RSI Tool" (`index.html`, backed up first).
- VPS: "QuantumRx membership" button pointed at paid tier deep link, then reverted to a placeholder alert same day after confirming Stripe isn't connected (D-INFRA-005, D-INFRA-006).
- VPS: security hardening pass, commit `6ae14f1` — closed port 8081, fail2ban mitigation, migration runbook scoped.

## 2026-07-16
- Confirmed GA4 tags consistent across all `.eu`/forge pages (`G-YPMBJ71VTF`), separate deliberate property on `.co.uk` (`G-8C097TY3ZJ`).
- Confirmed Ghost's site-wide Code Injection is not Admin-API-writable (403), established manual-paste workflow (D-INFRA-004).
- Cleared a stale Sentinel false-positive block from this session's own curl testing.

## 2026-07-13
- Railway cron (`railway-cron/`) built and made the primary automation trigger (D-INFRA-001).
- GitHub Actions `schedule:` trigger removed after it raced Railway on a Monday and produced a false-failure alert (D-INFRA-002).

## 2026-07-11
- First Sentinel false-positive (bot_ua on own curl traffic) identified and cleared (D-INFRA-003).
