// api/generate-result-image.js
// GET /api/generate-result-image?type=pass|fail
//
// Generates a small AI image for the terminal's pass/fail state — a canary
// on pass, a big red X on fail — then CACHES it permanently in KV + Vercel
// Blob so every subsequent request just serves the cached URL instantly.
// Generation only happens once per type, ever (until manually cleared).
//
// Model + responseModalities match the confirmed-working image-gen call
// already used by generate.js / generate-lotm.js (Pepe Legends / LOTM
// pipeline) — gemini-3.1-flash-image, not the older exp model name.

import { kv } from '@vercel/kv';
import { put } from '@vercel/blob';

// Same dedicated key as game.js — separate from GEMINI_API_KEY_Forge so
// this stays cost-isolated from the paid card-generation pipeline. In
// practice this only ever fires twice, ever (one generation per type,
// then cached permanently), so the isolation matters far less here than
// in game.js, but keeping both game endpoints on the same key avoids
// having a third env var to track for no real benefit.
const GEMINI_API_KEY = process.env.GEMINI_API_KEY_Game;

const PROMPTS = {
  pass: 'A small stylized canary bird icon, glowing gold outline on transparent dark background, minimalist flat vector style, no text, no background clutter, centered, security-badge aesthetic.',
  fail: 'A bold red X mark / access-denied glyph, glowing magenta-red outline on transparent dark background, minimalist flat vector style, no text, centered, security-alert aesthetic.'
};

async function generateAndUploadImage(promptText) {
  const model = 'gemini-3.1-flash-image';
  const genRes = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ role: 'user', parts: [{ text: promptText }] }],
        generationConfig: { responseModalities: ['IMAGE', 'TEXT'] }
      })
    }
  );
  const genData = await genRes.json();
  const base64 = genData?.candidates?.[0]?.content?.parts?.find((p) => p.inlineData)?.inlineData?.data;

  if (!base64) {
    throw new Error('No image data returned from generation call');
  }

  const imageBuffer = Buffer.from(base64, 'base64');
  const blob = await put(`sentinel-game/${Date.now()}.png`, imageBuffer, {
    access: 'public',
    contentType: 'image/png'
  });
  return blob.url;
}

export default async function handler(req, res) {
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  if (!GEMINI_API_KEY) {
    return res.status(500).json({ error: 'Missing GEMINI_API_KEY_Game' });
  }

  const type = req.query?.type;
  if (type !== 'pass' && type !== 'fail') {
    return res.status(400).json({ error: 'type must be "pass" or "fail"' });
  }

  const cacheKey = `game-image:${type}`;
  const lockKey = `game-image-lock:${type}`;

  try {
    const cached = await kv.get(cacheKey);
    if (cached) {
      return res.status(200).json({ url: cached, cached: true });
    }

    // Atomic claim — same pattern as the free-code claim in generate.js.
    // Without this, every request that arrives while the cache is still
    // empty (only possible before the very first successful generation
    // for this type, but real on a fresh deploy or right after a cache
    // clear) independently sees cached=null and triggers its own paid
    // Gemini call + Blob upload, instead of exactly one.
    const claimed = await kv.set(lockKey, '1', { ex: 30, nx: true });
    if (!claimed) {
      // Someone else is already generating this — poll briefly for their
      // result rather than generating a redundant copy ourselves.
      for (let i = 0; i < 8; i++) {
        await new Promise((r) => setTimeout(r, 500));
        const nowCached = await kv.get(cacheKey);
        if (nowCached) return res.status(200).json({ url: nowCached, cached: true });
      }
      return res.status(503).json({ error: 'Image generation in progress, try again shortly' });
    }

    const url = await generateAndUploadImage(PROMPTS[type]);
    await kv.set(cacheKey, url);

    return res.status(200).json({ url, cached: false });
  } catch (err) {
    console.error('generate-result-image error:', err);
    return res.status(500).json({ error: 'Image generation failed' });
  }
}
