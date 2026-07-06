// api/register-player.js
// POST /api/register-player
// Body: { handle: string }
//
// Registers (or re-rolls) the display handle for the requesting IP.
// Identity is server-derived from IP, not from anything the client sends
// as an id — the handle is purely cosmetic flavor text layered on top.
// Re-registering (rerolling the name) always updates the handle, but
// never touches totalPoints/levelsCleared already accumulated for this ip.

import { kv } from '@vercel/kv';

function getIP(req) {
  return (req.headers['x-forwarded-for'] || '').split(',')[0].trim()
    || req.socket?.remoteAddress || 'unknown';
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { handle } = req.body || {};
  if (!handle || typeof handle !== 'string') {
    return res.status(400).json({ error: 'handle is required' });
  }

  const safeHandle = handle.slice(0, 60);
  const ip = getIP(req);
  const playerKey = `game:player:${ip}`;

  try {
    const existing = await kv.get(playerKey);
    const record = existing || { levelsCleared: [], totalPoints: 0 };
    record.handle = safeHandle;
    await kv.set(playerKey, record);

    // NX — only takes effect the very first time this ip appears on the
    // leaderboard, so a reroll never resets an already-earned score back
    // to 0. Member is the ip (never exposed to clients); leaderboard.js
    // resolves it to the current handle at read time.
    await kv.zadd('game:leaderboard', { nx: true }, { score: 0, member: ip });

    return res.status(200).json({ ok: true, handle: safeHandle });
  } catch (err) {
    console.error('register-player error:', err);
    return res.status(500).json({ error: 'Failed to register player' });
  }
}
