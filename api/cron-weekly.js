// /api/cron-weekly.js
// Fan-out trigger for the WEEKLY refresh bucket (This Week in Tech + Top 50
// podcasts). One external cron POSTs here once a week (Monday) with the
// x-cron-secret header. Companion to cron-daily.js — see that file for why this
// exists (GitHub Actions' scheduler is unreliable). The two weekly refreshes are
// independent, so they run in parallel.

export const config = { maxDuration: 300 };

const WEEKLY = ['weekly-refresh', 'podcast-refresh'];

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

  const results = await Promise.all(WEEKLY.map((ep) => trigger(base, ep, expected)));
  const ok = results.every((r) => r.ok);
  return res.status(ok ? 200 : 502).json({ task: 'weekly', ok, elapsedMs: Date.now() - startedAt, results });
}
