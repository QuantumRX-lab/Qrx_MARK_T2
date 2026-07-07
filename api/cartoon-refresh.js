// api/cartoon-refresh.js
// POST /api/cartoon-refresh — daily cron, 07:00 UTC
//
// Nine to F!veish pipeline: Claude writes today's 3-panel script, Gemini
// generates one image per panel, results are written to KV. No Ghost
// Admin API involved — the Ghost/Vercel page for this strip is a static
// shell that fetches fresh data client-side from api/cartoon.js on every
// load, same pattern as every other feed page in this project. That
// means there is nothing here to "patch" server-side; the page is
// already fresh the moment KV is updated.
//
// Model choices deliberately differ from the original spec, which named
// models that don't exist / aren't confirmed working in this project:
//   - Script generation: claude-sonnet-5 (spec said claude-sonnet-4-6,
//     not a real model id).
//   - Image generation: gemini-3.1-flash-image with responseModalities
//     ['IMAGE','TEXT'] (spec suggested imagen-3.0-generate-001 or
//     gemini-2.0-flash-preview-image-generation — neither matches the
//     confirmed-working pattern already used by generate.js /
//     generate-lotm.js / generate-result-image.js in this exact repo).
//
// Failure handling: the whole pipeline is wrapped in try/catch. On any
// failure, the error is logged to cartoon:error:YYYY-MM-DD and the
// function exits without touching cartoon:latest or cartoon:index —
// yesterday's strip stays live, nothing breaks.

import { kv } from '@vercel/kv';
import { put } from '@vercel/blob';
import { logRequest, blockThreat } from './_lib/sentinel.js';
import { buildScriptSystemPrompt, IMAGE_PROMPT_SUFFIX } from './_lib/cartoon-prompt.js';

const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY;
// Matches the existing convention for content-refresh pipelines in this
// repo (mainstream-refresh.js, news-refresh.js, draw-refresh.js,
// weekly-refresh.js all use this same key) rather than the spec's
// generic GEMINI_API_KEY, which isn't an env var this project actually
// has configured.
const GEMINI_API_KEY = process.env.GEMINI_API_KEY_Forge;

const ARCHIVE_RETENTION = 90; // kv.index keeps this many dates; api/cartoon.js's ?archive=true slices to the last 30 of these

function extractJSON(text) {
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) return fence[1].trim();
  const brace = text.match(/(\{[\s\S]*\})/);
  if (brace) return brace[1].trim();
  return text.trim();
}

async function generateScript(issueNumber) {
  if (!ANTHROPIC_API_KEY) throw new Error('Missing ANTHROPIC_API_KEY');

  const systemPrompt = buildScriptSystemPrompt(issueNumber);
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01'
    },
    body: JSON.stringify({
      model: 'claude-sonnet-5',
      max_tokens: 2048,
      system: systemPrompt,
      messages: [{ role: 'user', content: "Write today's strip." }]
    }),
    signal: AbortSignal.timeout(30000)
  });

  const data = await res.json();
  if (!res.ok) {
    throw new Error(`Claude API error: ${res.status} ${JSON.stringify(data).slice(0, 500)}`);
  }

  const text = data?.content?.[0]?.text || '';
  const json = extractJSON(text);
  let script;
  try {
    script = JSON.parse(json);
  } catch {
    throw new Error(`Claude returned invalid JSON: ${text.slice(0, 500)}`);
  }

  if (!script.title || !Array.isArray(script.panels) || script.panels.length !== 3) {
    throw new Error('Claude script missing title or does not have exactly 3 panels');
  }
  return script;
}

async function generatePanelImage(imagePrompt) {
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
  const filename = `nine-to-fiveish/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.png`;
  const blob = await put(filename, buffer, { access: 'public', contentType: 'image/png' });
  return blob.url;
}

export default async function handler(req, res) {
  await logRequest(req, 'cartoon-refresh');

  const provided = req.headers['x-cron-secret'];
  const expected = process.env.CRON_SECRET;
  if (!expected || provided !== expected) {
    await blockThreat(req, 'cartoon-refresh', 'missing-or-invalid-cron-secret');
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const today = new Date().toISOString().slice(0, 10);

  try {
    // Server owns the authoritative sequential counter — Claude is only
    // told what number to print, never trusted to track it itself.
    const issueNumber = await kv.incr('cartoon:counter');

    const script = await generateScript(issueNumber);

    const panels = await Promise.all(
      script.panels.map(async (panel) => ({
        caption: panel.caption || '',
        imageUrl: await generatePanelImage(panel.imagePrompt)
      }))
    );

    const cartoon = {
      date: today,
      issueNumber,
      title: script.title,
      panels
    };

    await kv.set(`cartoon:${today}`, cartoon);
    await kv.set('cartoon:latest', today);

    let index = (await kv.get('cartoon:index')) || [];
    index = index.filter((d) => d !== today);
    index.push(today);
    if (index.length > ARCHIVE_RETENTION) {
      index = index.slice(index.length - ARCHIVE_RETENTION);
    }
    await kv.set('cartoon:index', index);

    return res.status(200).json({ ok: true, date: today, issueNumber, title: script.title });
  } catch (err) {
    console.error('[cartoon-refresh] pipeline failed:', err);
    await kv.set(`cartoon:error:${today}`, String(err?.message || err)).catch(() => {});
    // Deliberately do NOT touch cartoon:latest / cartoon:index here —
    // yesterday's strip stays live, the page never shows a broken state.
    return res.status(500).json({ error: 'Cartoon generation failed', logged: true });
  }
}
