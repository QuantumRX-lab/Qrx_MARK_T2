// /api/cron-daily.js
// Fan-out trigger for the DAILY refresh bucket.
//
// One reliable external cron (e.g. cron-job.org) POSTs here once a day with the
// x-cron-secret header, and this endpoint runs all five daily refreshes for us.
// It exists because GitHub Actions' scheduled runs proved unreliable (delayed
// hours, or dropped entirely) — see the 2026-07-09 miss. Keep the GitHub
// workflow as a manual/secondary backup; make this the primary trigger.
//
// Ordering matters: the three feed refreshes + the cartoon run in parallel
// first, THEN generate-chat-chips, because the chips are built from the feed
// data that news/draw/mainstream write to KV. Cartoon has no feed dependency
// so it rides along in phase 1.

export const config = { maxDuration: 300 };

const PHASE1 = ['news-refresh', 'draw-refresh', 'mainstream-refresh', 'cartoon-refresh'];
const PHASE2 = ['generate-chat-chips'];

function baseUrl(req) {
  const proto = (req.headers['x-forwarded-proto'] || 'https').split(',')[0].trim();
  const host = req.headers['x-forwarded-host'] || req.headers.host || 'forge.quantumrx.eu';
  return `${proto}://${host}`;
}

async function trigger(base, ep, secret) {
  const startedAt = Date.now();
  try {
    const r = await fetch(`${base}/api/${ep}`, {
      method: 'POST',
      headers: { 'x-cron-secret': secret, Authorization: `Bearer ${secret}` },
      signal: AbortSignal.timeout(180000),
    });
    const body = (await r.text().catch(() => '')).replace(/\s+/g, ' ').slice(0, 180);
    return { ep, status: r.status, ok: r.ok, ms: Date.now() - startedAt, body };
  } catch (err) {
    return { ep, status: 0, ok: false, ms: Date.now() - startedAt, body: String((err && err.message) || err).slice(0, 180) };
  }
}

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const provided = req.headers['x-cron-secret'] || (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  const expected = process.env.CRON_SECRET;
  if (!expected || provided !== expected) return res.status(401).json({ error: 'Unauthorized' });

  const base = baseUrl(req);
  const startedAt = Date.now();

  const phase1 = await Promise.all(PHASE1.map((ep) => trigger(base, ep, expected)));
  const phase2 = await Promise.all(PHASE2.map((ep) => trigger(base, ep, expected)));

  const results = [...phase1, ...phase2];
  const ok = results.every((r) => r.ok);
  // Non-2xx on any failure so the external cron flags it (and can alert).
  return res.status(ok ? 200 : 502).json({ task: 'daily', ok, elapsedMs: Date.now() - startedAt, results });
}
