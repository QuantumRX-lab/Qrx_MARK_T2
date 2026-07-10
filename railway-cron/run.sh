#!/bin/sh
# Fires QuantumRx's daily fan-out endpoint every run, and the weekly
# fan-out endpoint too when it lands on a Monday (UTC) — same logic as
# the GitHub Actions backup workflow (.github/workflows/refresh.yml),
# just driven by Railway's cron scheduler instead, since GitHub's
# scheduler has proven unreliable (delayed hours, or dropped entirely).
#
# Requires CRON_SECRET set as a Railway service variable — never hardcode
# it in this script, it's committed to the repo.
set -eu

BASE="${BASE_URL:-https://forge.quantumrx.eu}"

if [ -z "${CRON_SECRET:-}" ]; then
  echo "ERROR: CRON_SECRET is not set." >&2
  exit 1
fi

trigger() {
  ep="$1"
  echo "== $ep =="
  code=$(curl -sS -o /tmp/body -w '%{http_code}' -X POST "$BASE/api/$ep" \
    -H "x-cron-secret: $CRON_SECRET" \
    -H "Authorization: Bearer $CRON_SECRET" \
    --max-time 180 || echo "000")
  body=$(tr -d '\n' < /tmp/body | head -c 300)
  echo "[$code] $body"
  if [ "$code" != "200" ]; then
    return 1
  fi
}

fail=0
trigger cron-daily || fail=1

# date -u +%u -> 1=Monday ... 7=Sunday
if [ "$(date -u +%u)" = "1" ]; then
  echo "Monday (UTC) — also running weekly refresh."
  trigger cron-weekly || fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "One or more refresh endpoints failed." >&2
  exit 1
fi

echo "All refreshes succeeded."
