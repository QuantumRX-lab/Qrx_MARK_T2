// api/leaderboard.js
// GET /api/leaderboard?limit=20
// Reads the top N entries from the game:leaderboard sorted set (member =
// ip, score = totalPoints, written by game.js/finalize-player.js) and
// resolves each ip to its current display handle before returning —
// the raw ip is never included in the response.

import { kv } from '@vercel/kv';

export default async function handler(req, res) {
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const limit = Math.min(parseInt(req.query?.limit, 10) || 20, 100);

  try {
    const raw = await kv.zrange('game:leaderboard', 0, limit - 1, { rev: true, withScores: true });
    // @vercel/kv returns a flat array [member, score, member, score, ...]
    const ranked = [];
    for (let i = 0; i < raw.length; i += 2) {
      ranked.push({ ip: raw[i], score: Number(raw[i + 1]) });
    }

    const records = await Promise.all(
      ranked.map((r) => kv.get(`game:player:${r.ip}`).catch(() => null))
    );

    const entries = ranked.map((r, i) => ({
      handle: records[i]?.handle || 'Unknown Agent',
      score: r.score
    }));

    return res.status(200).json({ entries });
  } catch (err) {
    console.error('leaderboard fetch error:', err);
    return res.status(500).json({ error: 'Failed to load leaderboard', entries: [] });
  }
}
