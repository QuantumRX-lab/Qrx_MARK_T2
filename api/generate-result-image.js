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

const GEMINI_API_KEY = process.env.GEMINI_API_KEY_Forge;

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

  const type = req.query?.type;
  if (type !== 'pass' && type !== 'fail') {
    return res.status(400).json({ error: 'type must be "pass" or "fail"' });
  }

  const cacheKey = `game-image:${type}`;

  try {
    const cached = await kv.get(cacheKey);
    if (cached) {
      return res.status(200).json({ url: cached, cached: true });
    }

    const url = await generateAndUploadImage(PROMPTS[type]);
    await kv.set(cacheKey, url);

    return res.status(200).json({ url, cached: false });
  } catch (err) {
    console.error('generate-result-image error:', err);
    return res.status(500).json({ error: 'Image generation failed' });
  }
}
