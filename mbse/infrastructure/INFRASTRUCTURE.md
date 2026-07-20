# QuantumRx Infrastructure — Critical Reference

**Last verified live: 2026-07-20.** This is the "read this first" doc for
anyone (human or AI agent) about to touch QuantumRx infrastructure. It's the
narrative front door to the full MBSE tree in this folder — see `README.md`
for the tree structure, or jump straight to a section below.

---

## The two-brand split

QuantumRx runs **two separate brands on entirely separate infrastructure**:

| | `.eu` — AI/tech signal media | `.co.uk` — RSI (Earth observation reports) |
|---|---|---|
| Hosting | Ghost Pro + Vercel | Single Hetzner VPS |
| Repo | `QuantumRX-lab/Qrx_MARK_T2` (this one) | `QuantumRX-lab/Medha` |
| GA4 property | `G-YPMBJ71VTF` | `G-8C097TY3ZJ` (deliberately separate) |
| Payments | Lemon Squeezy, one-time | Lemon Squeezy (reports) + unconnected Stripe (membership) |

They share exactly two things: the Ghost instance (`quantumrx.ghost.io`, both
brands' Ghost members live in the same database, distinguished by labels) and
`api/ls-webhook.js` (the payment webhook both brands' Lemon Squeezy purchases
land on). Full topology diagrams: `03_architecture/hosting_topology.md`.

---

## How to check if everything's actually working

```
cd mbse/infrastructure
python crawler.py
```

Needs `GITHUB_TOKEN` (repo Actions read), `UPSTASH_KV_URL`/`UPSTASH_KV_TOKEN`
(Sentinel block visibility), and SSH access to `root@91.99.127.39` (VPS
checks) as environment variables — never hardcode these into the script or
commit them. Any missing credential just skips that section rather than
failing the whole run. Writes `08_status/dashboard.yaml` and prints a report.

---

## Critical facts

### 1. Automation: Railway is primary, GitHub Actions is dead weight on purpose
Daily content (comic, meme, news/draw/mainstream feeds) refreshes via a
Railway cron job (`railway-cron/`) hitting `/api/cron-daily` at 06:17 UTC,
plus `/api/cron-weekly` on Mondays. **GitHub Actions' own scheduler is
deliberately disabled** (`.github/workflows/refresh.yml` has no `schedule:`
block since 2026-07-13) — it used to race Railway and produce false-failure
alerts. It still exists as a manual (`workflow_dispatch`) backup.

### 2. `api/ls-webhook.js` deleted — was an unused stub, not a live feature
Originally flagged as "broken" (5 missing Vercel env vars). **Owner confirmed
2026-07-20 it had never actually been wired into production purchase
flows** — real purchase fulfillment (Pepe Legends, Lord of the Memes, RSI
reports) runs entirely through Lemon Squeezy's own native licence-key
delivery, independent of Ghost. Deleted rather than fixed (`D-INFRA-008`); no
other file referenced it. If a real purchase → Ghost-member flow is wanted
later, design it fresh against actual current needs. See `RISK-INFRA-004`.

### 3. `ANTHROPIC_API_KEY` on Vercel is intentional, not dead
Despite marketing copy ("Claude writes the script") on several pages, **every
*deployed* AI generation feature on `forge.quantumrx.eu` runs on Gemini** — 4
separate per-feature keys (`GEMINI_API_KEY_Chat/Forge/Game/Kernel`). An
`ANTHROPIC_API_KEY` is configured on Vercel but referenced by zero lines of
committed code — **owner-confirmed intentional**: used occasionally for
manual/ad hoc work outside the deployed codebase, not dead config. Claude
*is* genuinely deployed on the `.co.uk` side — the RSI pipeline's
`pipeline/synthesis.py` on the VPS has a real, working `ANTHROPIC_API_KEY`.

### 4. Two Ghost write paths, only one is API-accessible
Ghost page HTML cards (`/signals/`, `/the-draw/`) **are** writable via the
Admin API — this session pushed several updates that way, always via a
timestamped-fresh `updated_at` check to avoid conflicts. Ghost's **site-wide
Code Injection** (the homepage hero framework) is **not** — the Admin API
returns `403 NoPermissionError` regardless of integration permissions. Prep
the diff in `ghost-current/site-header-injection.html` and hand it to a human
to paste into Ghost Admin → Settings → Code Injection manually.

### 5. `.co.uk` membership tier is priced but not purchasable
Ghost has a real paid "QuantumRx" tier (£5/mo, £50/yr, slug
`default-product`) but **Stripe isn't connected** to this Ghost instance. The
membership button on `quantumrx.co.uk` currently shows a placeholder alert
rather than a checkout flow that would fail partway through. Recommendation
on file (`D-INFRA-005`): connect Stripe rather than building custom Lemon
Squeezy subscription-sync logic from scratch — the existing LS webhook only
ever handled one-time purchases, there's no subscription lifecycle code to
extend.

### 6. Secrets hygiene
`CRON.txt` in this repo's working directory holds live secrets in plaintext
(CRON_SECRET, Ghost Admin key, GitHub PAT, Vercel token) — confirmed
`.gitignore`'d and confirmed **zero commits, ever**, via full git history
search. Not a leak, but not a real secrets manager either. `railway-cron/`
and `crawler.py` (this tree) both deliberately read credentials from
environment variables only — follow that pattern for anything new.

### 7. Q-Sentinel blocks don't expire
The shared threat-detection layer (`api/_lib/sentinel.js`) writes blocks to
Upstash KV with no TTL. False positives (this session's own `curl` testing
without a browser User-Agent got auto-blocked twice) need manual `DEL` via
the Upstash REST API — there's no self-expiry. 4 long-standing blocks from
`prompt_injection` pattern matches (real Break the Sentinel game attempts)
have sat since 2026-06-29 — expected, not a bug.

---

## Where things actually are

| What | Where |
|---|---|
| Full env var inventory (all 4 platforms) | `03_architecture/environment_variables.md` |
| Hosting topology diagrams | `03_architecture/hosting_topology.md` |
| Interface contracts (cron triggers, webhooks, Sentinel) | `03_architecture/interfaces.md` |
| Requirements (what the infra is supposed to do) | `02_requirements/requirements.yaml` |
| Test cases (how each requirement was actually checked) | `04_verification/test_cases.yaml` |
| Open risks | `05_risks/risk_register.yaml` |
| Why past infra decisions were made | `06_decisions/decision_log.yaml` |
| Dated change history | `07_change/CHANGELOG.md` |
| Live status snapshot (crawler-written) | `08_status/dashboard.yaml` |
| Internal consistency validator — run after any manual edit | `validate.py` |
| Lighter narrative companion (no requirement IDs, easier first read) | `../../STACK-OVERVIEW.md` |
| RSI's own product-level MBSE tree (pipeline, not infra) | `C:\Medha\MBSE\tools\RSI\` |
