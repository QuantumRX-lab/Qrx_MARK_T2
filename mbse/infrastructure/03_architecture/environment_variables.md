# Environment Variable Inventory

Verified live 2026-07-20 via `vercel env ls`, VPS `config/.env` inspection
(names only — values never printed), and known Railway/Ghost configuration.
**This is ground truth, not the code's wishlist** — every "code expects it but
it's absent" gap below was independently confirmed by listing what's actually
configured on each platform, not just grepping source.

## Vercel — `forge.quantumrx.eu` (project `project-yu3fn`)

17 variables actually configured, confirmed via `vercel env ls`:

| Variable | Used by | Status |
|---|---|---|
| `CRON_SECRET` | `cron-daily.js`, `cron-weekly.js`, every `*-refresh.js` | ✅ set, working (verified daily since 2026-07-13) |
| `WEEKLY_REFRESH_SECRET` | referenced in `CRON.txt` docs, not confirmed used in current `weekly-refresh.js` | ⚠️ present but redundant with `CRON_SECRET` — worth confirming still needed |
| `UPSTASH_REDIS_REST_URL` / `UPSTASH_REDIS_REST_TOKEN` | all `*-feed.js`/`*-refresh.js`, `_lib/sentinel.js`, `middleware.js` | ✅ set, working |
| `KV_URL` / `KV_REST_API_URL` / `KV_REST_API_TOKEN` / `KV_REST_API_READ_ONLY_TOKEN` / `KV_REDIS_URL` | Vercel's native KV integration (auto-provisioned alongside Upstash vars above) | ✅ set — likely legacy/duplicate of the `UPSTASH_*` pair; both point at the same store |
| `BLOB_STORE_ID` / `BLOB_WEBHOOK_PUBLIC_KEY` | Vercel's native Blob integration (`@vercel/blob`) | ✅ set — `BLOB_READ_WRITE_TOKEN` is not listed separately, consistent with the newer Vercel Blob integration injecting it at runtime without a visible top-level var |
| `GEMINI_API_KEY` | fallback/shared key, some older endpoints | ✅ set |
| `GEMINI_API_KEY_Chat` | `api/chat.js` — the "QRx Signal Analyst" widget | ✅ set |
| `GEMINI_API_KEY_Forge` | `api/cartoon-refresh.js`, `api/meme-refresh.js` | ✅ set |
| `GEMINI_API_KEY_Game` | `api/game.js` — Break the Sentinel | ✅ set |
| `GEMINI_API_KEY_Kernel` | Kernel Generator tool | ✅ set |
| `ANTHROPIC_API_KEY` | — | ⚠️ **set but referenced by zero lines in `api/*.js`** — confirmed via `grep -rn ANTHROPIC_API_KEY api/*.js` returning nothing. Every page's "Claude writes the script" copy (the-strip.html, chat widget branding) is marketing language; the actual *deployed* generation is 100% Gemini on this stack. **Owner-confirmed 2026-07-20: intentional** — used occasionally for manual/ad hoc work outside the committed codebase, not dead config. |

### Resolved: `api/ls-webhook.js` deleted (2026-07-20)

Originally flagged here as "5 required env vars confirmed missing"
(`GHOST_ADMIN_API_KEY`, `GHOST_API_URL`, `LS_WEBHOOK_SECRET`,
`LS_VARIANT_RSI_SINGLE`, `LS_VARIANT_RSI_BUNDLE`) with the practical effect
that real Lemon Squeezy purchases weren't creating/labelling Ghost members.

**Owner confirmed the file was an unused stub, never wired into production
purchase flows** — actual purchase delivery (licence keys for Pepe Legends,
Lord of the Memes, RSI reports) runs through Lemon Squeezy's own native
fulfillment, not through this file. Deleted rather than fixed (`D-INFRA-008`);
no other file referenced it. See `RISK-INFRA-004` (now closed) and
`06_decisions/decision_log.yaml`.

## Railway (`railway-cron/`)

| Variable | Required by | Status |
|---|---|---|
| `CRON_SECRET` | `run.sh` | ✅ set — same secret value as Vercel's, confirmed working since 2026-07-13 |
| `BASE_URL` | `run.sh` (optional, defaults to `https://forge.quantumrx.eu`) | not set, using default — fine |

## Hetzner VPS (`/opt/mip/config/.env`, quantumrx.co.uk backend)

Verified by listing which keys are non-empty (values never read/transmitted):

| Variable | Set? | Purpose |
|---|---|---|
| `ANTHROPIC_API_KEY` | ✅ set | Real Claude usage — `pipeline/synthesis.py` narrative generation (unlike the Vercel side, Claude genuinely runs here) |
| `GEMINI_API_KEY` | ✅ set | Second AI vendor for synthesis, no-LLM-fallback pattern |
| `COPERNICUS_URL` / `COPERNICUS_KEY` | ✅ set | ERA5 wind reanalysis download auth |
| `COPERNICUS_USER` / `COPERNICUS_PASSWORD` | ❌ empty | Unused — auth is via URL+KEY, not user/password |
| `LS_API_KEY` | ✅ set | Lemon Squeezy (report purchases) |
| `EMAIL_API_KEY` | ✅ set | `pipeline/resend_email_client.py` |
| `BLOB_STORE_ACCESS_KEY` / `BLOB_STORE_SECRET_KEY` / `BLOB_STORE_BUCKET` / `BLOB_STORE_URL` | ✅ set | `pipeline/blob_client.py` — signed download links |
| `BLOB_STORE_TOKEN` | ❌ empty | Superseded by the access/secret key pair above — likely dead var, not a gap |
| `HETZNER_API_TOKEN` | ❌ empty | Compute burst (CPX41 on-demand) — not yet needed at current load |
| `RUNPOD_API_KEY` | ❌ empty | GPU burst (RTX 4090 on-demand) — not yet needed |
| `DATALASTIC_API_KEY` | ❌ empty | MIP-specific (vessel intelligence) — MIP is paused, expected empty |
| `ADMIN_TOKEN` | ❌ empty | Admin dashboard auth — `web/admin` not yet built (see RSI dashboard, phase 4/5 items) |
| `TEST_LICENCE_KEY` | ✅ set | Test-mode licence bypass for pipeline testing |

## Ghost (both `quantumrx.eu` and `quantumrx.co.uk`'s membership backend)

Ghost itself has no "environment variables" in the traditional sense from the
outside — it's a hosted CMS (`quantumrx.ghost.io`). The two things that behave
like secrets:

- **Admin API key** (`6a38e...:fdb206...` format, `id:secret`) — used by
  external scripts (this session's Python push scripts) to authenticate as a
  Custom Integration. **Not stored as a Vercel env var** — no current code
  needs it there now that `api/ls-webhook.js` is deleted — currently only
  exists in `CRON.txt` in plaintext in this repo's working directory.
  Verified `CRON.txt` is correctly listed in `.gitignore` and is **not**
  tracked by git (`git ls-files` confirms it was never committed) — so this
  is a local-machine-only exposure, not a leaked-to-GitHub one. Also checked
  `git log --all --full-history -- CRON.txt`: zero commits, ever — confirmed
  it was never in git history, even before `.gitignore` picked it up. Still
  worth moving into a real secrets manager rather than a loose text file
  long-term — see `RISK-INFRA-005`.
- **Site-wide Code Injection** (Settings → Code Injection → Site Header) —
  the homepage hero/nav framework. **Not API-editable** — confirmed via a
  `403 NoPermissionError` when attempting a PUT to
  `/ghost/api/admin/settings/` for `codeinjection_head`. Must be pasted
  manually by a human with Ghost Admin UI access.

## GA4 (not env vars, but adjacent — hardcoded measurement IDs)

| Property | ID | Where it lives |
|---|---|---|
| `.eu` brand | `G-YPMBJ71VTF` | Hardcoded inline in every `forge.quantumrx.eu` page's `<head>` and Ghost's site-wide header injection |
| `.co.uk` brand | `G-8C097TY3ZJ` | Hardcoded inline in `/var/www/medha/index.html` and `order.html` on the VPS |

Deliberately separate accounts (confirmed with the owner 2026-07-16), not a
misconfiguration.
