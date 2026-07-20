# QuantumRx Stack Overview

Last verified: 2026-07-18. Two separate brands, two separate stacks, one company.

> For the full MBSE treatment — requirements, test cases, risk register,
> decision log, environment variable inventory, and a `crawler.py` script
> that re-verifies live status on demand — see
> [`mbse/infrastructure/INFRASTRUCTURE.md`](mbse/infrastructure/INFRASTRUCTURE.md).
> This document is the lighter narrative companion; that tree is the source
> of truth for anything you need to cite a requirement ID or test result for.

---

## quantumrx.eu — AI/Tech signal & tools brand

### Hosting
| Layer | Platform | Notes |
|---|---|---|
| Main site (`quantumrx.eu`) | Ghost Pro (`quantumrx.ghost.io`) | CMS, subscriber/member database, newsletter |
| Tool pages (`forge.quantumrx.eu`) | Vercel | Static HTML + serverless `/api/*` functions |
| Feed/session cache | Upstash Redis (KV) | Feed caches, Q-Sentinel threat data, archives |
| Generated images | Vercel Blob | Comic panels, meme images, forge card art |

### Ghost pages (quantumrx.eu)
Custom HTML cards, not Ghost's default theme rendering:
- `/` — homepage. Site-wide header code injection (Ghost Admin → Settings → Code Injection → Site Header, **not** API-editable) builds a custom "Signal Desk" front page: hero + subscribe form + 6 quick-nav buttons (**AI & Tech**, **Week in Review**, **Top Headlines**, **World & Markets**, **Security Feed**, **Products**), then a live-fetched grid pulling from the forge APIs below.
- `/signals/` — AI/tech news feed, 10 categories (What's Hot, AI Moves, Crypto, Policy, Energy, Space, Robotics, Semis, Quantum, Social) + search. Space tab carries a **pinned promotional tile** for `quantumrx.co.uk` (styled identically to real stories).
- `/the-draw/` — World news + financial markets, two tabs.
- `/this-week-in-tech/` — weekly curated story digest (what/why/what-next format).
- `/mainstream/` — general mainstream-outlet news aggregation.
- `/products/` — product listing.

All Ghost HTML card source is kept locally under `ghost-current/` for reference/editing before manual paste into Ghost Admin (page HTML cards are Admin-API-editable; the site-wide header injection is **not**, must be pasted by hand).

### Vercel pages (forge.quantumrx.eu)
`index.html`, `ai-labs.html`, `the-strip.html` (Nine to F!veish — daily AI comic), `the-meme.html` (The Daily Meme), `break-the-sentinel.html` (prompt-injection game), `nft-forge-tv.html` (Pepe Legends card forge), `lotm-forge-tv.html` (Lord of the Memes card forge), `podcasts.html`, `products.html`, `this-week-in-tech.html`, `exploit-watch.html` (daily CVE/PoC briefing).

Every page carries a floating **QRx Signal Analyst** chat widget (Claude-backed, `api/chat.js`) and a fixed Home button.

### API layer (`api/*.js` on Vercel)
- **Content pipelines** (each a `-feed`/`-refresh` pair): `cartoon`, `meme`, `news`, `draw`, `mainstream`, `weekly`, `podcast`. Refresh endpoints require `x-cron-secret`; feed endpoints are public, rate-limited via Q-Sentinel.
- **Chat**: `chat.js`, `chat-chips.js`, `tts.js` — the "QRx Signal Analyst" widget. Despite branding, actually Gemini-backed (`GEMINI_API_KEY_Chat`), not Claude — confirmed via the 2026-07-20 infra audit (see `mbse/infrastructure/`).
- **Games/forges**: `game.js` (Break the Sentinel), `generate.js` / `generate-lotm.js` / `generate-result-image.js` (card forges).
- **Payments**: purchase fulfillment (Pepe Legends, Lord of the Memes, RSI reports) runs entirely through Lemon Squeezy's own native licence-key delivery. `ls-webhook.js` (intended to also create/label a Ghost member per purchase) was confirmed an unused stub, never wired into production, and deleted 2026-07-20.
- **Sentinel**: `request-logger.js`, `export-sentinel-log.js`, `_lib/sentinel.js` — bot/threat detection, auto-block writes to KV `threat_action:<ip>`.
- **Cron fan-out**: `cron-daily.js` (news/draw/mainstream/cartoon/meme/chat-chips), `cron-weekly.js` (weekly/podcast).

### Automation
- **Primary trigger: Railway cron** (`railway-cron/`, Docker/Alpine + curl). Fires `17 6 * * *` (06:17 UTC) daily → hits `/api/cron-daily`; also hits `/api/cron-weekly` when the run lands on a Monday.
- **Backup: GitHub Actions** (`.github/workflows/refresh.yml`). Schedule trigger **removed 2026-07-13** after it raced Railway's Monday run and produced a false-failure alert (`weekly-refresh` 429 cooldown rejection). Manual `workflow_dispatch` only now.

### Security
**Q-Sentinel** — shared threat-detection layer (`api/_lib/sentinel.js`) powering both defensive auto-blocking (bot UA, prompt-injection patterns) and the Break the Sentinel game itself. Blocks live in Upstash KV, TTL-less (manual clear via `KV_URL/del/threat_action:<ip>`).

A separate standalone vault app, **Q-Sentinel** (confusingly same name, different thing — `C:\Q-Sentinel\q-sentinel`), is an air-gapped local authorization vault for AI agent key management. `npm start` / `npm run watchdog` from that directory. Not related to the web threat-detection layer above.

### Analytics
GA4 property `G-YPMBJ71VTF`, consistent across every `quantumrx.eu` and `forge.quantumrx.eu` page — single tag load, no duplicates, no CSP blocking (forge's CSP explicitly allow-lists `googletagmanager.com`/`google-analytics.com`).

### Payments
Lemon Squeezy — one-time purchases only (card forges, RSI reports). No recurring/subscription product exists on this brand.

---

## quantumrx.co.uk — Medha / RSI (Renewable Site Intelligence)

### Hosting
Single Hetzner CX22 VPS, `91.99.127.39`, Ubuntu, **nginx serving static files directly** from `/var/www/medha/` — no Vercel, no CDN. `index.html` (marketing site), `order.html` (report ordering UI), `status.html` (job polling), `download.html`.

### Backend
Python pipeline at `/opt/mip`, deployed via systemd:
- `mip-api.service` (gunicorn) — `api/submit.py`, `api/status.py`
- `mip-worker.service` — async job processor
- Both sit behind nginx's `/api/` proxy on the same domain.

**Codebase** (as of commit `6ae14f1`, 2026-07-17):
- `pipeline/` — 24 modules (solar, wind, yield, grid, constraints, site_access, cable_route, broadband, risk_scoring, renderer, orchestrator, payment/email clients, …)
- `api/` — 2 modules (submit, status)
- `scripts/` — 13 idempotent data-farming scripts (`fetch_*.py`)
- **7,876 lines production code, 7,235 lines test code** (≈0.92:1 ratio)
- **618 automated pytest tests passing**

### Real-world data (~8.2GB, 11 datasets)
EA Flood Zone 2/3 (813,627 features, 5.5GB), DESNZ REPD (14,289 projects), Northern Powergrid grid connection points (1,471 substations, national ECR), Natural England + Scotland ecological designations (SSSI/SAC/SPA/Ramsar/NNR), Agricultural Land Classification, OS roads & EA watercourses, ONS LAD boundaries + Ofcom broadband/mobile coverage, ERA5 + Global Wind Atlas wind rasters, NASA POWER/PVGIS solar (live API, not stored).

### Architecture highlights
- **Decision-first, not LLM-first**: a deterministic weighted 0–100 risk-scoring engine (`pipeline/risk_scoring.py`) computes the verdict in code. Claude/Gemini write the surrounding narrative only, with a no-LLM template fallback.
- **Rendering**: Jinja2 + WeasyPrint (HTML → PDF), replacing an earlier python-docx + LibreOffice pipeline mid-project after a live feasibility test.
- **Verification culture**: beyond the unit suite, real generated PDFs are routinely re-read page-by-page against live coordinates — this has caught bugs unit tests missed (an "unknown" ALC grade despite real data existing, a solar P90 stat from the wrong endpoint, a wind farm's own name appearing as its "nearest substation").

### MBSE governance
Tracked in `mbse/tools/RSI/` (mirrored locally at `C:\Medha\MBSE`): **173 requirements** (5 L1 stakeholder + 168 L2 system, 84.5% verification coverage), **165 documented test cases**, **5 interface control documents**, **125 logged engineering decisions** with rationale, **7 risks tracked, 0 open**. Full write-up: [Artifact — RSI MBSE Program Overview](https://claude.ai/code/artifact/e848dbca-a89c-4fee-916f-bb769830f778).

### Nav / UI (2026-07-17 changes)
- Top nav CTA renamed **"Order a Report" → "RSI Tool"** (still links to `/order.html`).
- **"QuantumRx membership"** button: was linking to Ghost Portal signup (`#/portal/signup/default-product`); **currently a placeholder** — clicking shows an alert ("Membership options are not available yet") instead, since payment processing for that tier isn't live yet (see Payments below). Every edit to `index.html`/`order.html` on this VPS is preceded by a timestamped backup (`*.bak-YYYYMMDDHHMMSS`) in the same directory — several exist from this week's changes.

### Payments
- **Report purchases**: Lemon Squeezy, one-time, fulfilled directly by Lemon Squeezy's own native licence-key delivery — same as the `.eu` brand's card forges. (`ls-webhook.js`, an incomplete Ghost-member-labelling side path, was confirmed an unused stub and deleted 2026-07-20 — never actually part of the delivery flow.)
- **Membership tier**: Ghost has a paid "QuantumRx" tier configured (£5/mo, £50/yr, slug `default-product`) but **Stripe is not connected** to this Ghost instance (`stripe_connect_account_id` etc. all empty) — so the tier is priced but not actually purchasable. No subscription-sync code exists to bridge Lemon Squeezy → Ghost membership either; that would be new work, not an extension of a proven one-time-purchase pattern.

### Analytics
Separate GA4 property, `G-8C097TY3ZJ` — **deliberately** a distinct monitoring account from the `.eu` property (confirmed, not an oversight).

### Security
Hardening pass 2026-07-17 (commit `6ae14f1`): closed port 8081 (RSI-R012), fail2ban mitigation (RSI-R011), scoped a migration runbook (RSI-R008).

### Repo
`github.com/QuantumRX-lab/Medha` (private) — single source of truth, includes both the pipeline code and the `mbse/` MBSE tree.

---

## Cross-brand notes

- Both brands share the **Lemon Squeezy → Ghost member labelling** pattern for one-time purchases, but each Ghost instance/GA4 property is independent — no shared subscriber base or analytics rollup between `.eu` and `.co.uk`.
- The `.eu` Signals page carries a permanent promotional tile for the `.co.uk` product; there is no reverse link automation (co.uk doesn't pull from `.eu`'s feeds).
- Disk on the RSI VPS is at **68% (25GB/38GB)**, growing with data-farming work — not urgent, worth rechecking periodically. Biggest consumer: `/opt/mip/data` at 8.2GB.
