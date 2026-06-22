// middleware.js — Q-Sentinel threat enforcement
// Vercel Edge Middleware (no Next.js dependency)
// Runs on every API request before it reaches any endpoint.

const KV_URL = process.env.UPSTASH_REDIS_REST_URL;
const KV_TOKEN = process.env.UPSTASH_REDIS_REST_TOKEN;

async function getIpThreatAction(ip) {
  if (!KV_URL || !KV_TOKEN) return null;
  try {
    const res = await fetch(
      `${KV_URL}/get/threat_action:${encodeURIComponent(ip)}`,
      {
        headers: { Authorization: `Bearer ${KV_TOKEN}` },
        signal: AbortSignal.timeout(800),
      }
    );
    if (!res.ok) return null;
    const data = await res.json();
    if (!data.result) return null;
    const parsed = JSON.parse(data.result);
    return parsed.action || null;
  } catch {
    return null;
  }
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function warningResponse(ip) {
  const safeIp = escapeHtml(ip);
  const ts = new Date().toISOString();
  const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="robots" content="noindex"><title>Access Monitored</title><style>*{margin:0;padding:0;box-sizing:border-box}html,body{height:100%;background:#0a0a0c;color:#e0e0e0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}.wrap{min-height:100%;display:flex;align-items:center;justify-content:center;padding:40px 20px}.inner{max-width:520px;width:100%;text-align:center}.badge{margin-bottom:28px}.card{border:1px solid rgba(255,95,109,.25);background:rgba(255,95,109,.04);border-radius:14px;padding:44px 40px}.icon{font-size:30px;color:#ff5f6d;margin-bottom:18px}h1{color:#ff5f6d;font-size:12px;letter-spacing:.22em;text-transform:uppercase;margin-bottom:26px;font-weight:600}p{font-size:14px;line-height:1.75;color:rgba(255,255,255,.55);margin-bottom:16px}.divider{border-top:1px solid rgba(255,255,255,.07);margin-top:22px;padding-top:20px}.ref{font-size:11px;color:rgba(255,255,255,.22);font-family:monospace}.footer{margin-top:24px;font-size:10px;color:rgba(255,255,255,.16)}</style></head><body><div class="wrap"><div class="inner"><div class="badge"><svg width="48" height="48" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M12 2L4 6v6c0 5.5 3.8 10.7 8 12 4.2-1.3 8-6.5 8-12V6L12 2z" fill="#1e3a8a" stroke="#38bdf8" stroke-width="1"/><path d="M9 12l2 2 4-4" stroke="#ffffff" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg></div><div class="card"><div class="icon">&#9888;</div><h1>Access Monitored</h1><p>Unusual activity has been detected from your connection.</p><p>This endpoint is monitored and protected. All request metadata is logged.</p><p>If you believe this is an error, normal access will resume automatically.</p><div class="divider"><div class="ref">ref: ${safeIp} &middot; ${ts}</div></div></div><div class="footer">QuantumRx &middot; monitored by Q-Sentinel</div></div></div></body></html>`;

  return new Response(html, {
    status: 403,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'private, no-store',
      'X-Robots-Tag': 'noindex',
    },
  });
}

function honeypotResponse(path) {
  if (path.includes('chat') || path.includes('gemini')) {
    return new Response(
      JSON.stringify({ content: [{ type: 'text', text: 'I can help you with that. What would you like to know?' }] }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  }
  if (path.includes('generate')) {
    return new Response(
      JSON.stringify({ success: false, error: 'Rate limit exceeded. Try again later.' }),
      { status: 429, headers: { 'Content-Type': 'application/json' } }
    );
  }
  if (path.includes('validate-key')) {
    return new Response(
      JSON.stringify({ valid: false, error: 'Invalid or expired key.' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  }
  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

export default async function middleware(request) {
  const url = new URL(request.url);
  const path = url.pathname;

  // Only enforce on API routes
  if (!path.startsWith('/api/')) {
    return;
  }

  // Get IP
  const ip =
    request.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ||
    request.headers.get('x-real-ip') ||
    'unknown';

  const action = await getIpThreatAction(ip);

  if (action === 'block') return warningResponse(ip);
  if (action === 'honeypot') return honeypotResponse(path);

  // Clean — pass through
  return;
}

export const config = {
  matcher: '/api/(.*)',
};
