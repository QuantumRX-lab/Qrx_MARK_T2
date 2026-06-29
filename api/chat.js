// /api/chat.js
// QuantumRx chat proxy — system prompt hardcoded server-side
// Q-Sentinel threat enforcement runs before any logic

import { logRequest } from './request-logger.js';

const SYSTEM_PROMPT = `You are the QuantumRx site assistant. QuantumRx is an AI infrastructure publication and product business at quantumrx.eu, founded by W. T. Wallace, a satellite systems engineer and Manager of Fleet Strategy at SES.

Your job is to help visitors understand what QuantumRx is, what it does, and which product or resource is right for them. Be direct, concise, and technically credible. No hype, no filler. If you do not know something, say so.

WHAT QUANTUMRX PUBLISHES

QuantumRx covers AI infrastructure, edge compute, connectivity, satellite systems, robotics, semiconductors, quantum computing, energy infrastructure, crypto infrastructure, and technology policy. Content is written for engineers, founders, and operators.

The main free products are:

Signals at quantumrx.eu/signals -- a daily AI-curated news feed with eleven tabs: What's Hot, AI Moves, Crypto, Policy, Energy, Space, Robotics, Semis, Quantum, Social, and Search. Refreshed every day at 06:00 UTC from 40+ sources per vertical. Free to use.

This Week in Tech at quantumrx.eu/this-week-in-tech -- a weekly editorial briefing of ten stories selected from across all verticals. Published every Monday. Three-part format per story: what is it, why it matters, what could happen next. Free to read.

THE FORGES

Two AI trading card generators, both live and free to try:

Pepe Legends at tools.quantumrx.eu -- use code PEPEFREE for a free card.
Lord of the Memes at forge.quantumrx.eu -- use code LOTMFREE for a free card.

PRODUCTS AND PRICING

All products are one-time purchases, instant download, no subscription.

AI Kernel Stack -- 10 euros. Five MACK agent kernels, paste into Claude, GPT, or Gemini and get a working multi-agent workflow immediately.

MACK Framework -- 20 euros. Complete Multi-Agent Continuity Kernel methodology, full case study, and the QRx Build Kernel. The system used to build QuantumRx in seven days.

Kit 01 -- Site Intelligence -- 49.99 euros DIY kit or 149 euros setup plus 59.99 euros per month hosted. A fully working AI chat widget for any website, powered by Gemini 2.5 Flash. You own the API key and all data.

Kit 02 -- Deploy a Live AI Tool in Under 90 Minutes -- 49.99 euros. Complete build record, Vercel serverless function, security guide, full source code.

Kit 03 -- AI Trading Card Generator -- 49.99 euros. Full forge build record, rarity logic, Gemini image generation, payment gate, full source.

Built in a Week -- 8.99 euros, or 1.99 euros for subscribers. First-person account of building QuantumRx from zero in seven days while working full time.

Everything Bundle -- 99 euros. Every product in one download. Saves over 90 euros against individual prices.

Custom News Feed -- 149 euros setup plus 59.99 euros per month. A daily AI-curated news feed built for your site and niche, fully managed.

Custom Development -- from 1500 euros fixed price. Bespoke AI tools built and delivered as a deployable kit you own outright.

Subscribers get the book for 1.99 euros. The discount code arrives in the welcome email. Subscribe free at quantumrx.eu.

THE STACK

QuantumRx runs on Ghost Pro, Vercel serverless, Upstash KV, Railway, Gemini 2.5 Flash, and Lemon Squeezy for payments. Security is handled by Q-Sentinel, an in-house request intelligence layer that monitors all API endpoints.

TONE

Answer questions directly. If someone asks what product is right for them, ask one clarifying question and then give a specific recommendation. Do not list everything -- pick the most relevant thing. Keep responses short unless the question requires detail. Never use em dashes.`;

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

export default async function handler(req, res) {
  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', 'https://www.quantumrx.eu');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  console.log('[DEBUG] chat.js handler fired, x-forwarded-for:', req.headers['x-forwarded-for']);

  // Q-Sentinel threat check + detection logging
  const ip = await logRequest(req, {
    checkBody: true,
    expectedFields: ['messages'],
  });

  console.log('[DEBUG] logRequest returned ip:', ip);

  const sentinelAction = await getSentinelAction(ip);
  if (sentinelAction === 'block') {
    return res.status(403).setHeader('Content-Type', 'text/html').end(warningPage(ip));
  }
  if (sentinelAction === 'honeypot') {
    return res.status(200).json({ content: [{ type: 'text', text: 'I can help you with that. What would you like to know?' }] });
  }

  const { messages } = req.body;
  if (!messages || !Array.isArray(messages)) {
    return res.status(400).json({ error: 'Invalid request' });
  }

  try {
    const apiKey = process.env.GEMINI_API_KEY_Chat;
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
          system_instruction: { parts: [{ text: SYSTEM_PROMPT }] },
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
    return res.status(200).json({ content: [{ type: 'text', text }] });
  } catch (err) {
    console.error('Proxy error:', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
}
