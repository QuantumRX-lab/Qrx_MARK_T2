// middleware.js — Q-Sentinel threat enforcement
// Runs on every request before it reaches any API endpoint.
// Checks KV for Sentinel threat actions and responds accordingly.

import { NextResponse } from 'next/server';

const KV_URL = process.env.UPSTASH_REDIS_REST_URL;
const KV_TOKEN = process.env.UPSTASH_REDIS_REST_TOKEN;

// Only enforce on API routes — don't block static assets or Ghost content
const PROTECTED_PATHS = [
  '/api/chat',
  '/api/gemini',
  '/api/generate',
  '/api/generate-lotm',
  '/api/validate-key',
  '/api/validate-key-lotm',
  '/api/chat-session',
];

async function getIpThreatAction(ip) {
  if (!KV_URL || !KV_TOKEN) return null;
  try {
    const res = await fetch(
      `${KV_URL}/get/threat_action:${encodeURIComponent(ip)}`,
      {
        headers: { Authorization: `Bearer ${KV_TOKEN}` },
        signal: AbortSignal.timeout(800), // fast — don't slow down clean requests
      }
    );
    if (!res.ok) return null;
    const data = await res.json();
    if (!data.result) return null;
    const parsed = JSON.parse(data.result);
    return parsed.action || null;
  } catch {
    return null; // fail open — never block legitimate traffic on KV error
  }
}

function warningResponse(ip) {
  const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="robots" content="noindex"><title>Access Monitored</title>
<style>*{margin:0;padding:0;box-sizing:border-box}
html,body{height:100%;background:#0a0a0c;color:#e0e0e0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
.wrap{min-height:100%;display:flex;align-items:center;justify-content:center;padding:40px 20px}
.inner{max-width:520px;width:100%;text-align:center}
.badge{margin-bottom:28px}
.card{border:1px solid rgba(255,95,109,.25);background:rgba(255,95,109,.04);border-radius:14px;padding:44px 40px}
.icon{font-size:30px;color:#ff5f6d;margin-bottom:18px}
h1{color:#ff5f6d;font-size:12px;letter-spacing:.22em;text-transform:uppercase;margin-bottom:26px;font-weight:600}
p{font-size:14px;line-height:1.75;color:rgba(255,255,255,.55);margin-bottom:16px}
.divider{border-top:1px solid rgba(255,255,255,.07);margin-top:22px;padding-top:20px}
.ref{font-size:11px;color:rgba(255,255,255,.22);font-family:monospace}
.footer{margin-top:24px;font-size:10px;color:rgba(255,255,255,.16)}</style>
</head><body><div class="wrap"><div class="inner">
<div class="badge"><svg width="48" height="48" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M12 2L4 6v6c0 5.5 3.8 10.7 8 12 4.2-1.3 8-6.5 8-12V6L12 2z" fill="#1e3a8a" stroke="#38bdf8" stroke-width="1"/>
<path d="M9 12l2 2 4-4" stroke="#ffffff" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
</svg></div>
<div class="card"><div class="icon">&#9888;</div>
<h1>Access Monitored</h1>
<p>Unusual activity has been detected from your connection.</p>
<p>This endpoint is monitored and protected. All request metadata is logged.</p>
<p>If you believe this is an error, normal access will resume automatically.</p>
<div class="divider">
<div class="ref">ref: ${ip.replace(/[<>&"']/g, '')} &middot; ${new Date().toISOString()}</div>
</div></div>
<div class="footer">QuantumRx &middot; monitored by Q-Sentinel</div>
</div></div></body></html>`;

  return new NextResponse(html, {
    status: 403,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'private, no-store',
      'X-Robots-Tag': 'noindex',
    },
  });
}

function honeypotResponse(path) {
  // Return realistic-looking but completely fake data
  // Attacker thinks they got real data — we watch them try to use it
  if (path.includes('chat') || path.includes('gemini')) {
    return NextResponse.json({
      content: [{ type: 'text', text: 'I can help you with that. What would you like to know?' }]
    });
  }
  if (path.includes('generate')) {
    return NextResponse.json({ success: false, error: 'Rate limit exceeded. Try again later.' });
  }
  if (path.includes('validate-key')) {
    return NextResponse.json({ valid: false, error: 'Invalid or expired key.' });
  }
  // Generic fake success
  return NextResponse.json({ ok: true });
}

export async function middleware(request) {
  const path = request.nextUrl.pathname;

  // Only enforce on protected API paths
  const isProtected = PROTECTED_PATHS.some(p => path.startsWith(p));
  if (!isProtected) return NextResponse.next();

  // Get IP
  const ip =
    request.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ||
    request.headers.get('x-real-ip') ||
    'unknown';

  // Check Sentinel's decision for this IP
  const action = await getIpThreatAction(ip);

  if (action === 'block') {
    return warningResponse(ip);
  }

  if (action === 'honeypot') {
    return honeypotResponse(path);
  }

  // Clean — let through
  return NextResponse.next();
}

export const config = {
  matcher: ['/api/:path*'],
};
