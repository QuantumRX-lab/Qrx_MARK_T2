// api/meme-refresh.js
// POST /api/meme-refresh — daily cron, rides in cron-daily.js's phase 1.
//
// The Daily Meme pipeline: Gemini (text) writes today's caption + image
// brief, then Gemini (image) generates the scene image. The image never
// has text baked in (see meme-prompt.js) — the-meme.html overlays the
// top/bottom caption with CSS, the standard meme format. Results are
// written to KV, same read/refresh split as cartoon.js / cartoon-refresh.js.
//
// Failure handling: the whole pipeline is wrapped in try/catch. On any
// failure, the error is logged to meme:error:YYYY-MM-DD and the function
// exits without touching meme:latest / meme:index — yesterday's meme
// stays live, nothing breaks.

import { kv } from '@vercel/kv';
import { put } from '@vercel/blob';
import { logRequest, blockThreat } from './_lib/sentinel.js';
import { buildMemeSystemPrompt, IMAGE_PROMPT_SUFFIX } from './_lib/meme-prompt.js';

const GEMINI_API_KEY = process.env.GEMINI_API_KEY_Forge;
const GEMINI_TEXT_URL = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

const ARCHIVE_RETENTION = 90; // kv.index keeps this many dates; api/meme.js's ?archive=true slices to the last 30 of these

function extractJSON(text) {
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) return fence[1].trim();
  const brace = text.match(/(\{[\s\S]*\})/);
  if (brace) return brace[1].trim();
  return text.trim();
}

async function generateMemeScript(issueNumber) {
  if (!GEMINI_API_KEY) throw new Error('Missing GEMINI_API_KEY_Forge');

  const prompt = buildMemeSystemPrompt(issueNumber) + "\n\nWrite today's meme now.";

  const res = await fetch(`${GEMINI_TEXT_URL}?key=${GEMINI_API_KEY}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: 0.9,
        maxOutputTokens: 1024,
        thinkingConfig: { thinkingBudget: 0 }
      }
    }),
    signal: AbortSignal.timeout(30000)
  });

  const data = await res.json();
  if (!res.ok) {
    throw new Error(`Gemini API error: ${res.status} ${JSON.stringify(data).slice(0, 500)}`);
  }

  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text || '';
  const json = extractJSON(text);
  let script;
  try {
    script = JSON.parse(json);
  } catch {
    throw new Error(`Gemini returned invalid JSON: ${text.slice(0, 500)}`);
  }

  if (!script.title || !script.imagePrompt || (!script.topText && !script.bottomText)) {
    throw new Error('Script missing title, imagePrompt, or both caption lines');
  }
  return script;
}

async function generateMemeImage(imagePrompt) {
  if (!GEMINI_API_KEY) throw new Error('Missing GEMINI_API_KEY_Forge');

  const fullPrompt = imagePrompt + IMAGE_PROMPT_SUFFIX;
  const model = 'gemini-3.1-flash-image';
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ role: 'user', parts: [{ text: fullPrompt }] }],
        generationConfig: { responseModalities: ['IMAGE', 'TEXT'] }
      }),
      signal: AbortSignal.timeout(30000)
    }
  );

  const data = await res.json();
  const base64 = data?.candidates?.[0]?.content?.parts?.find((p) => p.inlineData)?.inlineData?.data;
  if (!base64) {
    throw new Error(`No image data returned from Gemini: ${JSON.stringify(data).slice(0, 300)}`);
  }

  const buffer = Buffer.from(base64, 'base64');
  const filename = `ai-memes/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.png`;
  const blob = await put(filename, buffer, { access: 'public', contentType: 'image/png' });
  return blob.url;
}

export default async function handler(req, res) {
  await logRequest(req, 'meme-refresh');

  const provided = req.headers['x-cron-secret'];
  const expected = process.env.CRON_SECRET;
  if (!expected || provided !== expected) {
    await blockThreat(req, 'meme-refresh', 'missing-or-invalid-cron-secret');
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const today = new Date().toISOString().slice(0, 10);

  try {
    const issueNumber = await kv.incr('meme:counter');

    const script = await generateMemeScript(issueNumber);
    const imageUrl = await generateMemeImage(script.imagePrompt);

    const meme = {
      date: today,
      issueNumber,
      title: script.title,
      topText: script.topText || '',
      bottomText: script.bottomText || '',
      altText: script.altText || script.title,
      imageUrl
    };

    await kv.set(`meme:${today}`, meme);
    await kv.set('meme:latest', today);

    let index = (await kv.get('meme:index')) || [];
    index = index.filter((d) => d !== today);
    index.push(today);
    if (index.length > ARCHIVE_RETENTION) {
      index = index.slice(index.length - ARCHIVE_RETENTION);
    }
    await kv.set('meme:index', index);

    return res.status(200).json({ ok: true, date: today, issueNumber, title: script.title });
  } catch (err) {
    console.error('[meme-refresh] pipeline failed:', err);
    await kv.set(`meme:error:${today}`, String(err?.message || err)).catch(() => {});
    return res.status(500).json({ error: 'Meme generation failed', logged: true });
  }
}
