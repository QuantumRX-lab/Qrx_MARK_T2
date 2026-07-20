# Need Statement — QuantumRx Infrastructure

## Statement

QuantumRx operates two customer-facing brands (`quantumrx.eu` — AI/tech signal
media and tool "forges"; `quantumrx.co.uk` — the RSI Earth-observation report
product) across four hosting platforms (Ghost Pro, Vercel, Railway, a Hetzner
VPS) with no dedicated infrastructure/DevOps role. The infrastructure needs to
run **unattended and correctly** — daily content and cron jobs firing on
schedule, secrets available where needed and nowhere else, payment webhooks
actually working — because there is no one watching it continuously; problems
surface only when someone thinks to check, or a customer complains.

## Why this tree exists

Prior to 2026-07-20, infrastructure knowledge existed only as tribal knowledge
across a long chat session and one narrative doc (`STACK-OVERVIEW.md`) — real,
but not verifiable, not testable, and with no mechanism to catch drift (e.g.
an env var quietly missing, a cron trigger silently duplicating). This tree
converts that knowledge into requirements with an actual verification method,
plus a script (`crawler.py`) that can re-check reality against the model on
demand.

## Scope

In scope: hosting/deployment topology, environment variable inventory across
all four platforms, cron/automation reliability, the Q-Sentinel security
layer, GA4 analytics wiring, and the Lemon Squeezy payment webhook.

Out of scope: the RSI product pipeline itself (that's `Medha/MBSE/tools/RSI/`
— a separate, product-level MBSE tree with its own requirements, tests, and
619+ passing pytest suite). This tree only covers the infrastructure RSI runs
*on*, not RSI's own business logic.

## Origin

Built 2026-07-20 following a full manual stack audit conducted across the
prior week of sessions (page-by-page HTTP checks, live VPS SSH inspection,
`vercel env ls`, GitHub Actions run history, Ghost Admin API queries, Sentinel
KV inspection). Every fact in this tree traces to something actually observed
live, not assumed — see `06_decisions/decision_log.yaml` for how specific
findings were confirmed.
