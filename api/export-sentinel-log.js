// api/export-sentinel-log.js
// POST /api/export-sentinel-log?day=YYYY-MM-DD  (defaults to yesterday, UTC)
//
// Vercel endpoint (same hosting + auth pattern as mainstream-refresh.js /
// news-refresh.js), not a standalone Railway script — this project's
// convention is Vercel + Upstash KV throughout, so the daily export lives
// here too, triggered the same way the other refresh crons are.
//
// Pulls the previous day's logged Break the Sentinel wins from KV and
// returns three views in the response:
//   - entries: everything logged that day
//   - novel: entries the regex classifier couldn't tag (low-priority
//     curiosity bucket, not necessarily worth individual review)
//   - sentinelCandidates: entries from level >= 13 (Sentinel-Lite/Vault) —
//     the actionable list, since these mirror real Sentinel detection
//     logic and are the only wins worth a human considering for
//     promotion into production checkPromptInjection() patterns.
// No filesystem writes — Vercel functions don't have a durable
// filesystem, and the JSON response is what the reviewer actually reads.

import { kv } from '@vercel/kv';
import { blockThreat } from './_lib/sentinel.js';

function yesterdayUTC() {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().slice(0, 10);
}

function summarizeByTag(entries) {
  const counts = {};
  for (const e of entries) {
    counts[e.tag] = (counts[e.tag] || 0) + 1;
  }
  return counts;
}

export default async function handler(req, res) {
  const provided = req.headers['x-cron-secret'];
  const expected = process.env.CRON_SECRET;
  if (!expected || provided !== expected) {
    await blockThreat(req, 'export-sentinel-log', 'missing-or-invalid-cron-secret');
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const day = req.query?.day || yesterdayUTC();
  const listKey = `sentinel-log-day:${day}`;
  const candidateKey = `game:sentinel-candidates:${day}`;

  try {
    const [rawEntries, rawCandidates] = await Promise.all([
      kv.lrange(listKey, 0, -1),
      kv.lrange(candidateKey, 0, -1)
    ]);

    const parse = (list) => list.map((s) => {
      try {
        return typeof s === 'string' ? JSON.parse(s) : s;
      } catch {
        return null;
      }
    }).filter(Boolean);

    const entries = parse(rawEntries || []);
    const sentinelCandidates = parse(rawCandidates || []);
    const novel = entries.filter((e) => e.tag === 'novel');

    return res.status(200).json({
      day,
      totalEntries: entries.length,
      novelCount: novel.length,
      sentinelCandidateCount: sentinelCandidates.length,
      tagBreakdown: summarizeByTag(entries),
      entries,
      novel,
      sentinelCandidates
    });
  } catch (err) {
    console.error('[export-sentinel-log] error:', err);
    return res.status(500).json({ error: 'Export failed' });
  }
}
