# Interface Control — Infrastructure

Lightweight ICDs for the cross-platform interfaces that matter for reliability.
(Product-level ICDs for RSI's own pipeline live in `Medha/MBSE/tools/RSI/03_architecture/interfaces/`.)

## ICD-INFRA-001 — Railway → Vercel cron trigger

- **Caller**: Railway scheduled service (`railway-cron/run.sh`)
- **Callee**: `POST https://forge.quantumrx.eu/api/cron-daily` (always), plus
  `POST /api/cron-weekly` when the run date is a Monday (UTC)
- **Auth**: `x-cron-secret` header + `Authorization: Bearer` — both set to
  `CRON_SECRET`, must match on both Railway and Vercel
- **Schedule**: `17 6 * * *` (06:17 UTC daily) — deliberately off the top of
  the hour
- **Failure mode**: non-2xx response from either fan-out call causes
  `cron-daily.js`/`cron-weekly.js` to return 502; Railway's own run just
  fails, no automatic retry — next real attempt is the following day's
  scheduled run
- **Verified**: RSI-INFRA-TC-001

## ICD-INFRA-002 — GitHub Actions → Vercel cron trigger (backup, manual only)

- Same target endpoints as ICD-INFRA-001, same secret
- **Trigger**: `workflow_dispatch` only since 2026-07-13 — no `schedule:`
  block. Must be run by hand from the Actions tab.
- Exists purely as a manual fallback if Railway is down

## ICD-INFRA-003 — [RETIRED] Vercel `api/ls-webhook.js` → Ghost Admin API

- **Caller**: Lemon Squeezy (`order_created` webhook event) → Vercel
- **Callee**: `POST {GHOST_API_URL}/ghost/api/admin/members/`
- **Auth**: Ghost Admin API key (`id:secret` format) → short-lived JWT
  (5 min expiry, HS256, generated per request)
- **Retired 2026-07-20**: `api/ls-webhook.js` confirmed an unused stub, never
  wired into production, and deleted (`D-INFRA-008`). This ICD is kept here
  for historical record only — no live interface currently exists between
  Lemon Squeezy and Ghost. Purchase fulfillment (licence keys) runs entirely
  through Lemon Squeezy's own native delivery, independent of Ghost. See
  `RISK-INFRA-004`.

## ICD-INFRA-004 — External scripts → Ghost Admin API (page HTML cards only)

- Used this session to push updates to Ghost page HTML cards (`/signals/`,
  `/the-draw/`) — `PUT /ghost/api/admin/pages/{id}/?formats=lexical`
- **Does not work** for site-wide Code Injection
  (`PUT /ghost/api/admin/settings/` with key `codeinjection_head`) — returns
  `403 NoPermissionError` regardless of integration permissions. That setting
  is Admin-UI-only, confirmed by direct API test 2026-07-16.

## ICD-INFRA-005 — Q-Sentinel block list (shared KV namespace)

- **Writers**: `api/request-logger.js` (auto-block on threat detection),
  manual `DEL` via Upstash REST API (operator clearing false positives)
- **Readers**: every public-facing Vercel API endpoint's `isBlocked()` check
  (`_lib/sentinel.js` pattern), `api/game.js` (Break the Sentinel)
- **Key shape**: `threat_action:<ip>` (block/allow decision),
  `threat:flag:<ip>` (severity + pattern + detail, informational)
- **No TTL observed** — blocks persist until manually cleared; a stale
  false-positive block (e.g. this session's own `curl` testing traffic
  without a browser User-Agent) will sit indefinitely otherwise
