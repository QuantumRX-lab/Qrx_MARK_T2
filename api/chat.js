// /api/chat.js
// QuantumRx chat proxy — system prompt hardcoded server-side
// Injects live weekly briefing context for Signal Analyst widget
// Session-limited to 8 messages per IP per 24h, KV-tracked
// Q-Sentinel threat enforcement runs before any logic

import { kv } from "@vercel/kv";
import { logRequest } from './request-logger.js';

const SESSION_LIMIT = 8;
const SESSION_TTL = 60 * 60 * 24; // 24h

const BASE_SYSTEM_PROMPT = `You are the QuantumRx Signal Analyst, the site assistant for quantumrx.eu. QuantumRx is an AI infrastructure publication and product business founded by W. T. Wallace, a satellite systems engineer and Manager of Fleet Strategy at SES.

Your job is to help visitors understand the week's signals, what QuantumRx covers, and which product or resource is right for them. Be direct, concise, and technically credible. No hype, no filler. If you do not know something, say so.

WHAT QUANTUMRX PUBLISHES

QuantumRx covers AI infrastructure, edge compute, connectivity, satellite systems, robotics, semiconductors, quantum computing, energy infrastructure, crypto infrastructure, and technology policy. Content is written for engineers, founders, and operators.

Signals at quantumrx.eu/signals -- a daily AI-curated news feed with eleven tabs: What's Hot, AI Moves, Crypto, Policy, Energy, Space, Robotics, Semis, Quantum, Social, and Search. Refreshed every day at 06:00 UTC.

This Week in Tech at quantumrx.eu/this-week-in-tech -- a weekly editorial briefing of ten stories selected from across all verticals, published every Monday.

THE FORGES

Pepe Legends at tools.quantumrx.eu -- use code PEPEFREE for a free card.
Lord of the Memes at forge.quantumrx.eu -- use code LOTMFREE for a free card.

PRODUCTS AND PRICING

All products are one-time purchases, instant download, no subscription, except hosted services which are monthly.

AI Kernel Stack -- 10 euros. MACK Framework -- 20 euros. Kit 01 Site Intelligence -- 49.99 euros DIY or 149 euros setup plus 59.99 euros monthly hosted. Kit 02 Deploy a Live AI Tool -- 49.99 euros. Kit 03 AI Trading Card Generator -- 49.99 euros. Built in a Week -- 8.99 euros, or 1.99 euros for subscribers. Everything Bundle -- 99 euros. Custom News Feed -- 149 euros setup plus 59.99 euros monthly. Custom Development -- from 1500 euros.

Subscribers get the book for 1.99 euros. Subscribe free at quantumrx.eu.

RESPONSE FORMAT FOR SIGNAL QUESTIONS

When discussing a specific story or signal, use this three-part structure with these exact labels:

WHAT IS IT: one sentence, plain language, no jargon.
WHY IT MATTERS: one to two sentences on the real consequence, specific, willing to say if something is overblown.
WHAT TO WATCH: one sharp, checkable sentence on the near-term signal to watch.

After the three parts, on its own line, write: READLINK:<category> where category is one of aimoves, energy, space, crypto, policy, hot, robotics, semis, quantum -- matching the story's vertical. This will be converted into a link by the frontend, do not write it as a sentence.

TONE

Never use em dashes. Keep responses tight. Do not list every product when asked for a recommendation, pick the most relevant one and ask one clarifying question if needed.`;

function buildSystemPrompt(briefing) {
  if (!briefing || !briefing.stories || !briefing.stories.length) {
    return BASE_SYSTEM_PROMPT + `\n\nNo current weekly briefing is loaded. If asked about this week's signals, direct the user to quantumrx.eu/signals for live coverage.`;
  }
  const storyList = briefing.stories.map((s, i) =>
    `[${i}] CATEGORY: ${s.category}\nTITLE: ${s.title}\nWHAT IS IT: ${s.what_is_it}\nWHY IT MATTERS: ${s.why_it_matters}\nWHAT NEXT: ${s.what_next}\nVELOCITY: ${s.velocity}\nMATURITY: ${s.media_maturity}\nOUTLETS: ${s.outlets || ''}`
  ).join('\n\n');

  return BASE_SYSTEM_PROMPT + `\n\nCURRENT WEEKLY BRIEFING (${briefing.weekLabel || 'this week'}, ${briefing.stories.length} stories):\n\n${storyList}\n\nWhen asked about "this week", "the briefing", "signals", or any specific story above, use this data. When asked for "full briefing", cover the top 3 stories by velocity and significance, then offer to go deeper on any of them or cover the remaining stories. When asked about a specific vertical (AI, Energy, Space, Crypto, Policy, Robotics, Semiconductors, Quantum), find the matching story above and use it. If no story exists for that vertical this week, say so plainly and suggest checking the live Signals tab.`;
}

async function getSessionCount(ip) {
  const key = `chatsession:${ip}`;
  try {
    const count = await kv.incr(key);
    if (count === 1) await kv.expire(key, SESSION_TTL);
    return count;
  } catch {
    return 0; // fail open if KV unavailable
  }
}

async function getWeeklyBriefing() {
  try {
    const stories = await kv.get('weekly_briefing_current');
    const meta = await kv.get('weekly_briefing_updated');
    if (!stories || !Array.isArray(stories) || !stories.length) return null;
    return {
      stories,
      weekLabel: meta?.weekLabel || null,
      updatedAt: meta?.updatedAt || null,
    };
  } catch {
    return null;
  }
}

async function getSentinelAction(ip) {
  const kvUrl = process.env.UPSTASH_REDIS_REST_URL;
  const kvToken = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!kvUrl || !kvToken) return null;
  try {
    const res = await fetch(
      `${kvUrl}/get/threat_action:${encodeURIComponent(ip)}`,
      { headers: { Authorization: `Bearer ${kvToken}` }, signal: AbortSignal.timeout(800) }
    );
    if (!res.ok) return null;
    const data = await res.json();
    if (!data.result) return null;
    const parsed = JSON.parse(data.result);
    return parsed.action || null;
  } catch { return null; }
}

function escapeHtml(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

function warningPage(ip) {
  const safeIp = escapeHtml(ip);
  return `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>Access Monitored</title><style>*{margin:0;padding:0;box-sizing:border-box}body{background:#0a0a0c;color:#e0e0e0;font-family:-apple-system,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;padding:40px 20px}.inner{max-width:520px;text-align:center}.badge{margin-bottom:28px}.card{border:1px solid rgba(255,95,109,.25);background:rgba(255,95,109,.04);border-radius:14px;padding:44px 40px}h1{color:#ff5f6d;font-size:12px;letter-spacing:.22em;text-transform:uppercase;margin-bottom:20px}p{font-size:14px;line-height:1.75;color:rgba(255,255,255,.55);margin-bottom:14px}.ref{margin-top:18px;padding-top:16px;border-top:1px solid rgba(255,255,255,.07);font-size:11px;color:rgba(255,255,255,.22);font-family:monospace}.footer{margin-top:20px;font-size:10px;color:rgba(255,255,255,.16)}</style></head><body><div class="inner"><div class="badge"><svg width="48" height="48" viewBox="0 0 24 24" fill="none"><path d="M12 2L4 6v6c0 5.5 3.8 10.7 8 12 4.2-1.3 8-6.5 8-12V6L12 2z" fill="#1e3a8a" stroke="#38bdf8" stroke-width="1"/><path d="M9 12l2 2 4-4" stroke="#fff" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg></div><div class="card"><h1>Access Monitored</h1><p>Unusual activity has been detected from your connection.</p><p>This endpoint is monitored and protected. All request metadata is logged.</p><p>If you believe this is an error, normal access will resume automatically.</p><div class="ref">ref: ${safeIp} &middot; ${new Date().toISOString()}</div></div><div class="footer">QuantumRx &middot; monitored by Q-Sentinel</div></div></body></html>`;
}

const LIMIT_REACHED_TEXT = `You've reached the free limit of 8 questions for this session.

For unlimited access to the Signal Analyst, full weekly briefings, and daily Signals coverage, subscribe free at quantumrx.eu. Your session resets in 24 hours either way.`;

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', 'https://www.quantumrx.eu');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const ip = await logRequest(req, {
    checkBody: true,
    expectedFields: ['messages'],
  });

  const sentinelAction = await getSentinelAction(ip);
  if (sentinelAction === 'block') {
    return res.status(403).setHeader('Content-Type', 'text/html').end(warningPage(ip));
  }
  if (sentinelAction === 'honeypot') {
    return res.status(200).json({ content: [{ type: 'text', text: 'I can help you with that. What would you like to know?' }] });
  }

  // Session limit check
  const sessionCount = await getSessionCount(ip);
  if (sessionCount > SESSION_LIMIT) {
    return res.status(200).json({ content: [{ type: 'text', text: LIMIT_REACHED_TEXT }], limitReached: true });
  }

  const { messages } = req.body;
  if (!messages || !Array.isArray(messages)) {
    return res.status(400).json({ error: 'Invalid request' });
  }

  try {
    const apiKey = process.env.GEMINI_API_KEY_Chat;
    const briefing = await getWeeklyBriefing();
    const systemPrompt = buildSystemPrompt(briefing);

    const contents = messages.map(m => ({
      role: m.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: m.content }]
    }));

    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          system_instruction: { parts: [{ text: systemPrompt }] },
          contents,
          generationConfig: { maxOutputTokens: 512, temperature: 0.7 }
        })
      }
    );
    const data = await response.json();
    if (!response.ok) {
      console.error('Gemini error:', data);
      return res.status(500).json({ error: 'Gemini API error' });
    }
    const text = data.candidates?.[0]?.content?.parts?.[0]?.text || 'No response generated.';
    return res.status(200).json({
      content: [{ type: 'text', text }],
      sessionCount,
      sessionLimit: SESSION_LIMIT,
      weekLabel: briefing?.weekLabel || null,
      storyCount: briefing?.stories?.length || 0,
    });
  } catch (err) {
    console.error('Proxy error:', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
}
