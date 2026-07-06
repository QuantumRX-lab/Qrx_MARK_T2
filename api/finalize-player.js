// api/finalize-player.js
// POST /api/finalize-player
// Body: { phrase?: string }
//
// Called when a player hits "Give Up". Reconciles the leaderboard entry
// to the server's own authoritative total for this ip (game:player:<ip>
// .totalPoints, built up server-side by game.js on every real win) and
// stores the last taunt phrase for flavor text next to their entry.
//
// Deliberately does NOT accept a score from the client — game.js already
// tracks the real total via zincrby on every canary break-through, so
// trusting a client-supplied number here would let anyone overwrite the
// leaderboard with an arbitrary score without ever playing.

import { kv } from '@vercel/kv';

function getIP(req) {
  return (req.headers['x-forwarded-for'] || '').split(',')[0].trim()
    || req.socket?.remoteAddress || 'unknown';
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { phrase } = req.body || {};
  const safePhrase = (phrase || '').slice(0, 300);
  const ip = getIP(req);

  try {
    const record = (await kv.get(`game:player:${ip}`)) || { totalPoints: 0 };
    const trueScore = record.totalPoints || 0;

    // Reconciliation write using the server's own recorded total — not
    // client input. zincrby during play should already keep this in sync;
    // this is a safety-net overwrite in case of a missed update, using
    // only data the server itself produced.
    await kv.zadd('game:leaderboard', { score: trueScore, member: ip });
    await kv.set(`game:player-taunt:${ip}`, safePhrase);

    return res.status(200).json({ ok: true, score: trueScore });
  } catch (err) {
    console.error('finalize-player error:', err);
    return res.status(500).json({ error: 'Failed to finalize session' });
  }
}
