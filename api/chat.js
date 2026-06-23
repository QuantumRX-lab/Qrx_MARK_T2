// Q-Sentinel threat enforcement — runs before any logic
import { logRequest } from './request-logger.js';

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

  // Debug — confirm handler is running updated code
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

  const { system, messages } = req.body;
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
          system_instruction: { parts: [{ text: system }] },
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
