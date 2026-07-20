# Hosting Topology

## .eu brand — quantumrx.eu / forge.quantumrx.eu

```
                        ┌─────────────────────┐
                        │   Ghost Pro          │
  visitor ────────────▶ │  quantumrx.ghost.io  │
                        │  (quantumrx.eu)      │
                        └──────────┬───────────┘
                                   │ fetch() from page JS
                                   ▼
                        ┌─────────────────────┐
                        │  Vercel              │
  visitor ────────────▶ │  forge.quantumrx.eu  │◀──── Railway cron
                        │  (static + /api/*)   │       (06:17 UTC daily,
                        └──────┬───────┬───────┘        + Mondays: weekly)
                               │       │
                    ┌──────────┘       └──────────┐
                    ▼                              ▼
          ┌──────────────────┐          ┌──────────────────┐
          │  Upstash Redis    │          │  Vercel Blob      │
          │  (feed cache,     │          │  (comic panels,   │
          │   Sentinel KV)    │          │   meme images)    │
          └───────────────────┘          └────────────────────┘

  GitHub Actions (.github/workflows/refresh.yml) — manual-only backup
  since 2026-07-13, schedule removed after it raced Railway on Mondays.
```

**Key point**: Ghost pages are *not* server-rendered with the feed data —
they're static HTML/CSS/JS cards (kept locally in `ghost-current/`) that
`fetch()` the Vercel `/api/*` endpoints client-side at page load. Ghost and
Vercel are only connected through the browser, not server-to-server. (An
`api/ls-webhook.js` once existed to call Ghost's Admin API directly on
purchase — confirmed an unused stub, deleted 2026-07-20. No live
server-to-server link between Ghost and Vercel currently exists.)

## .co.uk brand — quantumrx.co.uk (RSI / Medha)

```
                        ┌───────────────────────────────────┐
                        │  Hetzner CX22 VPS — 91.99.127.39   │
  visitor ────────────▶ │  nginx (static + /api/ proxy)      │
                        │                                    │
                        │  ┌──────────────┐  ┌─────────────┐│
                        │  │ mip-api       │  │ mip-worker   ││
                        │  │ (gunicorn,    │  │ (async job   ││
                        │  │  submit.py,   │◀─│  processor)  ││
                        │  │  status.py)   │  │              ││
                        │  └──────────────┘  └──────┬───────┘│
                        │                            │        │
                        │  /opt/mip/data/  (8.2GB     │        │
                        │  real geospatial datasets)  ▼        │
                        │                     /opt/mip/pipeline/│
                        └───────────────────────────────────┘
                                   │
                       ┌───────────┼───────────┬─────────────┐
                       ▼           ▼            ▼             ▼
                 Copernicus   Lemon Squeezy  Resend      Blob storage
                 (ERA5 wind)  (payments)     (email)     (signed PDF links)
```

**Key point**: this is a single self-contained VPS — no CDN, no serverless
functions, no separate database service (SQLite on local disk). The entire
`.co.uk` product runs on one box. Static marketing pages (`index.html`,
`order.html`, `status.html`) are also served directly by the same nginx
instance, not a separate frontend host.

## Where the two brands touch

1. **`quantumrx.eu/signals/`** carries a permanent pinned promotional tile for
   `quantumrx.co.uk` (Space tab) — one-directional, no live data pulled from
   `.co.uk`.
2. Both brands' Ghost members live in the **same Ghost instance**
   (`quantumrx.ghost.io`) — the one shared piece of infrastructure besides
   the promotional tile above. (A shared payment webhook, `api/ls-webhook.js`,
   was planned to write purchase labels there for both brands but was
   confirmed an unused stub and deleted 2026-07-20 — see `RISK-INFRA-004`.
   Both brands' purchases are actually fulfilled directly by Lemon Squeezy's
   own native licence-key delivery, independent of Ghost.)
3. Otherwise: **fully independent.** Separate GA4 properties, separate Ghost
   membership tiers, separate hosting stacks, separate git repos
   (`QuantumRX-lab/Qrx_MARK_T2` vs `QuantumRX-lab/Medha`).
