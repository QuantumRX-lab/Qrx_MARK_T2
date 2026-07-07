// api/chat-chips.js
//
// Public GET endpoint serving the current daily chat chips. Always
// reads the single `latest` key — the fallback to yesterday's chips
// is automatic and requires no logic here, since generate-chat-chips.js
// only overwrites `latest` on confirmed success.

import { kv } from "@vercel/kv";
import { logRequest } from "./_lib/sentinel.js";

// Widget also runs on the Vercel-hosted tool pages now, each a distinct origin.
const ALLOWED_ORIGINS = ['https://www.quantumrx.eu', 'https://quantumrx.eu', 'https://forge.quantumrx.eu', 'https://tools.quantumrx.eu'];

// Absolute last resort — only used if `latest` has literally never been
// written even once (e.g. brand new deploy, before the first successful
// morning run). Not a daily fallback, a bootstrap fallback.
// These carry no server-side grounding record (there's nothing in KV to
// look them up against), so chat.js's getChipById() will find nothing for
// a "bootstrap_*" id and fall back to normal free-text classification —
// which is fine, since their question text already matches the
// weekly_recap pattern in classifyQuestion() on its own.
const BOOTSTRAP_CHIPS = [
  { id: "bootstrap_0", question: "What should I watch this week?", label: "What should I watch?", vertical: null },
  { id: "bootstrap_1", question: "What's crossing mainstream this week?", label: "Crossing mainstream?", vertical: null },
];

async function isBlocked(ip) {
  const kvUrl = process.env.UPSTASH_REDIS_REST_URL;
  const kvToken = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!kvUrl || !kvToken) return false;
  try {
    // Raw ip — must match writeAutoBlock() in request-logger.js. Encoding
    // here breaks the key match for IPv6 addresses.
    const res = await fetch(`${kvUrl}/get/threat_action:${ip}`,
      { headers: { Authorization: `Bearer ${kvToken}` }, signal: AbortSignal.timeout(800) });
    if (!res.ok) return false;
    const data = await res.json();
    if (!data.result) return false;
    return JSON.parse(data.result).action === "block";
  } catch { return false; }
}

function getIP(req) {
  return (req.headers["x-forwarded-for"] || "").split(",")[0].trim()
    || req.socket?.remoteAddress || "unknown";
}

// Only the fields a chip button actually needs to render and to ask its
// question — never the grounding data or response format. Those are looked
// up server-side by chat.js from the chip's id, so there's nothing here for
// a client to tamper with and hand back as "authoritative" grounding.
// `vertical` is safe to expose: it's a single category label, not story
// content, and the widget uses it to sort chips by page relevance.
function publicShape(chip) {
  const vertical = (chip.groundedStories && chip.groundedStories[0] && chip.groundedStories[0].vertical) || null;
  return { id: chip.id, question: chip.question, label: chip.label, vertical };
}

export default async function handler(req, res) {
  const ip = getIP(req);
  await logRequest(req, "chat-chips");

  const origin = req.headers.origin;
  if (ALLOWED_ORIGINS.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
  }
  res.setHeader('Access-Control-Allow-Methods', 'GET');

  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }

  if (await isBlocked(ip)) {
    res.status(403).json({ error: "Access monitored" });
    return;
  }

  try {
    const record = await kv.get('daily_chat_chips:latest');

    if (!record || !record.chips || !record.chips.length) {
      res.setHeader('Cache-Control', 'no-store');
      res.status(200).json({ date: null, chips: BOOTSTRAP_CHIPS, bootstrap: true });
      return;
    }

    // Short cache — this can change once a day, but a stale minute is
    // harmless and this keeps repeat widget loads off KV.
    res.setHeader('Cache-Control', 'public, max-age=300');
    res.status(200).json({ date: record.date, chips: record.chips.map(publicShape), bootstrap: false });
  } catch (err) {
    console.error('chat-chips error:', err);
    res.setHeader('Cache-Control', 'no-store');
    res.status(200).json({ date: null, chips: BOOTSTRAP_CHIPS, bootstrap: true });
  }
}
