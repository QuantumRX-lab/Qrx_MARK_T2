// request-logger.js
// Threat detection layer for Qrx_MARK_T2
// Writes threat:flag:<ip> to Upstash KV — picked up by Q-Sentinel monitor within 30s
// All counters use KV with TTL so cold starts don't reset detection windows

const KV_URL = process.env.UPSTASH_REDIS_REST_URL;
const KV_TOKEN = process.env.UPSTASH_REDIS_REST_TOKEN;

// ─── KV helpers ──────────────────────────────────────────────────────────────

async function kvGet(key) {
  const res = await fetch(`${KV_URL}/get/${encodeURIComponent(key)}`, {
    headers: { Authorization: `Bearer ${KV_TOKEN}` },
  });
  const data = await res.json();
  return data.result; // null if not found
}

async function kvIncr(key) {
  const res = await fetch(`${KV_URL}/incr/${encodeURIComponent(key)}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${KV_TOKEN}` },
  });
  const data = await res.json();
  return data.result; // new count
}

async function kvExpire(key, ttlSeconds) {
  await fetch(`${KV_URL}/expire/${encodeURIComponent(key)}/${ttlSeconds}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${KV_TOKEN}` },
  });
}

async function kvSet(key, value) {
  await fetch(`${KV_URL}/set/${encodeURIComponent(key)}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${KV_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(value),
  });
}

// ─── Threat flag writer ───────────────────────────────────────────────────────

async function writeFlag(ip, severity, pattern, detail = '') {
  const key = `threat:flag:${ip}`;

  // Don't downgrade an existing flag
  const existing = await kvGet(key);
  if (existing) {
    const parsed = JSON.parse(existing);
    const levels = { LOW: 1, MEDIUM: 2, HIGH: 3 };
    if (levels[parsed.severity] >= levels[severity]) return; // already flagged at equal or higher level
  }

  const flag = {
    ip,
    severity,
    pattern,
    detail,
    detectedAt: new Date().toISOString(),
  };

  await kvSet(key, JSON.stringify(flag));
  // No TTL on threat flags — operator clears manually via Sentinel (clear action)
  console.log(`[SENTINEL-LOGGER] FLAG WRITTEN — ${severity} | ${ip} | ${pattern} | ${detail}`);
}

// ─── Detection rules ──────────────────────────────────────────────────────────

// HIGH: prompt injection keywords in request body
// Single occurrence is enough — unambiguous malicious intent
const INJECTION_PATTERNS = [
  /ignore\s+(previous|above|prior|all)\s+(instructions?|prompts?|rules?)/i,
  /system\s*prompt/i,
  /reveal\s+(your\s+)?(instructions?|prompts?|system|context)/i,
  /jailbreak/i,
  /act\s+as\s+(if\s+you\s+are\s+|a\s+)?(?:dan|evil|unrestricted|unfiltered)/i,
  /\[INST\]|\[\/INST\]|<\|system\|>|<\|user\|>/i, // model-specific injection tokens
  /do\s+not\s+follow\s+(your\s+)?(rules?|guidelines?|training)/i,
  /pretend\s+(you\s+are|to\s+be)\s+.{0,40}(no\s+restrictions?|unfiltered)/i,
];

async function checkPromptInjection(ip, body) {
  if (!body) return;
  const text = typeof body === 'string' ? body : JSON.stringify(body);
  for (const pattern of INJECTION_PATTERNS) {
    if (pattern.test(text)) {
      await writeFlag(ip, 'HIGH', 'prompt_injection', pattern.source.slice(0, 80));
      return;
    }
  }
}

// HIGH: missing User-Agent or known bot/script UA
async function checkUserAgent(ip, req) {
  const ua = req.headers['user-agent'] || '';

  if (!ua) {
    await writeFlag(ip, 'HIGH', name, 'No User-Agent header');
    return;
  }

  const BOT_UAS = [
    /^python-requests/i,
    /^curl\//i,
    /^wget\//i,
    /^Go-http-client/i,
    /^node-fetch/i,
    /^axios\//i,
    /^libcurl/i,
    /^java\//i,
    /^ruby/i,
    /^scrapy/i,
    /postmanruntime/i,
    /^httpx/i,
  ];

  for (const pattern of BOT_UAS) {
    if (pattern.test(ua)) {
      await writeFlag(ip, 'HIGH', 'bot_ua', ua.slice(0, 80));
      return;
    }
  }
}

// MEDIUM: repeated key failures — flag at 3 within 1 hour
async function checkKeyFailure(ip) {
  const key = `keyfail:${ip}`;
  const count = await kvIncr(key);

  // Set TTL on first increment only
  if (count === 1) {
    await kvExpire(key, 3600); // 1 hour window
  }

  if (count >= 3) {
    await writeFlag(ip, 'MEDIUM', 'repeated_key_failure', `${count} failures in 1h`);
  }
}

// LOW: high request volume — flag at >10 in 60s
async function checkRequestVolume(ip) {
  const key = `reqcount:${ip}`;
  const count = await kvIncr(key);

  // Set TTL on first increment only — 60s window, auto-cleans
  if (count === 1) {
    await kvExpire(key, 60);
  }

  if (count > 10) {
    // Flag after 5 excess hits to avoid false positives from brief bursts
    const excessKey = `reqexcess:${ip}`;
    const excess = await kvIncr(excessKey);
    if (excess === 1) await kvExpire(excessKey, 60);

    if (excess >= 5) {
      await writeFlag(ip, 'LOW', 'high_request_volume', `${count} requests in 60s`);
    }
  }
}

// LOW: malformed request structure
async function checkMalformedRequest(ip, body, expectedFields) {
  if (!body || typeof body !== 'object') {
    const malformKey = `malform:${ip}`;
    const count = await kvIncr(malformKey);
    if (count === 1) await kvExpire(malformKey, 300); // 5 min window
    if (count >= 5) {
      await writeFlag(ip, 'LOW', 'malformed_request', 'Non-object body repeated');
    }
    return;
  }

  if (expectedFields && expectedFields.length > 0) {
    const missing = expectedFields.filter(f => !(f in body));
    if (missing.length > 0) {
      const malformKey = `malform:${ip}`;
      const count = await kvIncr(malformKey);
      if (count === 1) await kvExpire(malformKey, 300);
      if (count >= 5) {
        await writeFlag(ip, 'LOW', 'malformed_request', `Missing fields: ${missing.join(', ')}`);
      }
    }
  }
}

// ─── Main exports ─────────────────────────────────────────────────────────────

/**
 * logRequest — call at the top of every API endpoint
 *
 * @param {object} req              — Vercel request object
 * @param {object} [options]
 * @param {boolean} [options.checkBody]       — true to scan body for injection patterns
 * @param {string[]} [options.expectedFields] — field names expected in req.body for malform check
 * @returns {string} ip — parsed client IP, pass to getSentinelAction and logKeyFailure
 */
export async function logRequest(req, options = {}) {
  const ip =
    (req.headers['x-forwarded-for'] || '').split(',')[0].trim() ||
    req.socket?.remoteAddress ||
    'unknown';

  if (!KV_URL || !KV_TOKEN) {
    console.warn('[SENTINEL-LOGGER] KV env vars not set — detection disabled');
    return ip;
  }

  try {
    const checks = [
      checkUserAgent(ip, req),
      checkRequestVolume(ip),
    ];

    if (options.checkBody && req.body) {
      checks.push(checkPromptInjection(ip, req.body));
    }

    if (options.expectedFields) {
      checks.push(checkMalformedRequest(ip, req.body, options.expectedFields));
    }

    await Promise.all(checks);
  } catch (err) {
    // Never let the logger crash the endpoint
    console.error('[SENTINEL-LOGGER] Error in threat detection:', err.message);
  }

  return ip;
}

/**
 * logKeyFailure — call after a failed key validation
 * Separate from logRequest so the endpoint controls when failure is confirmed
 *
 * @param {string} ip — from the return value of logRequest()
 */
export async function logKeyFailure(ip) {
  if (!KV_URL || !KV_TOKEN) return;
  try {
    await checkKeyFailure(ip);
  } catch (err) {
    console.error('[SENTINEL-LOGGER] Error in key failure tracking:', err.message);
  }
}
