// Q-Sentinel threat enforcement
import { logRequest } from './request-logger.js';
import { kv } from '@vercel/kv';

async function getSentinelAction(ip) {
  const kvUrl = process.env.UPSTASH_REDIS_REST_URL;
  const kvToken = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!kvUrl || !kvToken) return null;
  try {
    const res = await fetch(
      // Raw ip — must match writeAutoBlock() in request-logger.js. Encoding
      // here breaks the key match for IPv6 addresses.
      `${kvUrl}/get/threat_action:${ip}`,
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
  return `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>Access Monitored</title><style>*{margin:0;padding:0;box-sizing:border-box}body{background:#0a0a0c;color:#e0e0e0;font-family:-apple-system,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;padding:40px 20px}.inner{max-width:520px;text-align:center}.card{border:1px solid rgba(255,95,109,.25);background:rgba(255,95,109,.04);border-radius:14px;padding:44px 40px}h1{color:#ff5f6d;font-size:12px;letter-spacing:.22em;text-transform:uppercase;margin-bottom:20px}p{font-size:14px;line-height:1.75;color:rgba(255,255,255,.55);margin-bottom:14px}.ref{margin-top:18px;padding-top:16px;border-top:1px solid rgba(255,255,255,.07);font-size:11px;color:rgba(255,255,255,.22);font-family:monospace}.footer{margin-top:20px;font-size:10px;color:rgba(255,255,255,.16)}</style></head><body><div class="inner"><div class="card"><h1>Access Monitored</h1><p>Unusual activity has been detected from your connection.</p><p>This endpoint is monitored and protected.</p><div class="ref">ref: ${safeIp} &middot; ${new Date().toISOString()}</div></div><div class="footer">QuantumRx &middot; monitored by Q-Sentinel</div></div></body></html>`;
}

// KV-backed per-IP counter — 5 requests/IP/hour. Replaces a previous in-memory
// Map, which reset on every cold start and didn't share state across
// concurrent serverless instances, so it wasn't a real limit in production.
// Fails open (returns 0) if KV is unavailable, matching chat.js's getSessionCount.
async function checkRateLimit(ip) {
  const key = `gemini_rate:${ip}`;
  try {
    const count = await kv.incr(key);
    if (count === 1) await kv.expire(key, 60 * 60);
    return count;
  } catch {
    return 0;
  }
}

function compressPrompt(fmt, input) {
  return `You are an expert AI workflow architect. Analyse this raw AI chat history and compress it into a structured continuity kernel.

Extract and structure ALL of the following sections:

IDENTITY: name, role, expertise, location, handle, timezone
PROJECT: name, domain, platform, goals, audience, key URLs
STATUS: completed milestones, work in progress, blockers
DECISIONS: key choices made with rationale
PIPELINE: upcoming tasks/items with priority and status
COMMUNICATION: tone preferences, style, formatting dislikes, feedback preferences, working rhythm
RELATIONSHIP: how the user likes to work with AI, what they find valuable, what frustrates them, any explicit preferences about AI interaction style
REFERENCES: key URLs, tools, data sources, credentials (non-sensitive)
OPEN THREADS: unresolved questions, pending decisions, known issues
WORKFLOW: tools in use, agent structure, session patterns, methodology

Output format: ${fmt.toUpperCase()}
CRITICAL: Output ONLY the raw ${fmt.toUpperCase()} — absolutely no preamble, no explanation, no markdown code fences, no backticks.
- Mark inferred fields: # inferred
- Mark fields needing verification: # verify
- Include metadata block: generated date, source, format version
- Every field must earn its place
- The communication and relationship sections are as important as the project sections

Chat history:
---
${input}
---`;
}

function buildPrompt(fmt, input) {
  let parsed;
  try { parsed = JSON.parse(input); } catch { return null; }
  const { type, name, project, domain, desc } = parsed;
  if (!desc) return null;
  return `You are an expert AI workflow architect. Generate a comprehensive drop-in continuity kernel for a ${type||'general'} project.

Include ALL of the following sections:

IDENTITY: author name, role, expertise, location
PROJECT: name, domain, platform, goals, audience, key URLs
STATUS: current phase, completed milestones, active work, blockers
PIPELINE: upcoming tasks/features with priority and status
DECISIONS: key choices made and rationale
COMMUNICATION: tone preferences, style, formatting preferences, feedback style, working rhythm
RELATIONSHIP: how the user prefers to work with AI assistants — what they value, what frustrates them, interaction style preferences, level of detail expected
REFERENCES: key URLs, tools, data sources
CONSTRAINTS: known limitations, dependencies, open questions
METADATA: generated date, format version, TODO markers

Output format: ${fmt.toUpperCase()}
CRITICAL: Output ONLY the raw ${fmt.toUpperCase()} — absolutely no preamble, no explanation, no markdown code fences, no backticks.
- Descriptive placeholders: # TODO: add your X here
- Adapt field names naturally for a ${type||'general'} project
- Brief inline comments on each major section
- The communication and relationship sections are mandatory — not optional

Project details:
Author: ${name||'Not specified'}
Project: ${project||'Not specified'}
Type: ${type||'Not specified'}
Domain: ${domain||'Not specified'}
Description: ${desc}`;
}

const ALLOWED_ORIGINS = [
  'https://www.quantumrx.eu',
  'https://quantumrx.eu',
  'https://tools.quantumrx.eu',
];

export default async function handler(req, res) {
  // CORS — restricted to known origins
  const origin = req.headers.origin;
  if (ALLOWED_ORIGINS.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
  }
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  // Q-Sentinel threat check + detection logging
  const ip = await logRequest(req, {
    checkBody: true,
    expectedFields: ['mode', 'format', 'input'],
  });
  const sentinelAction = await getSentinelAction(ip);
  if (sentinelAction === 'block') {
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    return res.status(403).end(warningPage(ip));
  }
  if (sentinelAction === 'honeypot') {
    return res.status(200).json({ text: 'Here is your compressed kernel:\n\nIDENTITY:\n  name: Unknown\n  role: Developer\nPROJECT:\n  name: Project\n  status: active\n' });
  }

  // Rate limiting — 5 requests per IP per hour, KV-backed (see checkRateLimit above)
  const requestCount = await checkRateLimit(ip);
  if (requestCount > 5) {
    return res.status(429).json({ error: 'Too many requests. Please try again later.' });
  }

  // Was process.env.GEMINI_API_KEY — the one endpoint in the repo not
  // following the per-feature key convention every other Gemini-calling
  // endpoint uses (GEMINI_API_KEY_Forge/_Chat/_Game). cartoon-refresh.js
  // even has its own comment confirming the generic GEMINI_API_KEY isn't
  // an env var this project actually provisions, so this was either
  // silently broken (var never set) or drawing against an untracked
  // budget (if left over from earlier scaffolding). Needs a real
  // GEMINI_API_KEY_Kernel value set in Vercel before this works again.
  const apiKey = process.env.GEMINI_API_KEY_Kernel;
  if (!apiKey) return res.status(500).json({ error: 'Missing GEMINI_API_KEY_Kernel' });

  let mode, format, input;
  try {
    const body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
    mode = body?.mode;
    format = body?.format;
    input = body?.input;
  } catch {
    return res.status(400).json({ error: 'Invalid request body' });
  }

  if (!mode || !['compress', 'build'].includes(mode)) return res.status(400).json({ error: 'Invalid mode' });
  if (!format || !['yaml', 'json', 'markdown'].includes(format)) return res.status(400).json({ error: 'Invalid format' });
  if (!input || typeof input !== 'string') return res.status(400).json({ error: 'No input provided' });
  if (input.length > 50000) return res.status(400).json({ error: 'Input too large. Please reduce your chat history.' });

  const truncated = input.length > 48000 ? input.slice(0, 48000) + '\n\n[truncated]' : input;
  const prompt = mode === 'compress' ? compressPrompt(format, truncated) : buildPrompt(format, truncated);
  if (!prompt) return res.status(400).json({ error: 'Invalid input data' });

  try {
    const geminiRes = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ role: 'user', parts: [{ text: prompt }] }],
          generationConfig: { maxOutputTokens: 2500, temperature: 0.3 },
        }),
      }
    );
    if (!geminiRes.ok) {
      const errText = await geminiRes.text();
      return res.status(geminiRes.status).json({ error: `Gemini API error: ${geminiRes.status}`, detail: errText });
    }
    const data = await geminiRes.json();
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text || '';
    return res.status(200).json({ text });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}
