// request-logger.js
// Threat detection layer for Qrx_MARK_T2
// Writes threat:flag:<ip> to Upstash KV — picked up by Q-Sentinel monitor within 30s
// AUTO-BLOCK: HIGH severity detections now automatically write threat_action:block
//
// FIX (2026-06-23): keys are NO LONGER encodeURIComponent'd. Upstash stored the
// %3A-encoded form, which the Sentinel monitor's `threat:flag:*` (literal colon)
// KEYS query could never match. All KV paths now use raw colons, matching the
// monitor and the manual REPL tests. All writes now check res.ok and log the
// real HTTP status so failures are never silent again.

const KV_URL = process.env.UPSTASH_REDIS_REST_URL;
const KV_TOKEN = process.env.UPSTASH_REDIS_REST_TOKEN;

// ─── KV helpers ──────────────────────────────────────────────────────────────
// Keys go in the path with RAW colons. Do NOT encodeURIComponent.

async function kvGet(key) {
  const res = await fetch(`${KV_URL}/get/${key}`, {
    headers: { Authorization: `Bearer ${KV_TOKEN}` },
  });
  if (!res.ok) {
    console.error(`[SENTINEL-LOGGER] kvGet failed ${res.status} for ${key}`);
    return null;
  }
  const data = await res.json();
  return data.result;
}

async function kvIncr(key) {
  const res = await fetch(`${KV_URL}/incr/${key}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${KV_TOKEN}` },
  });
  if (!res.ok) {
    console.error(`[SENTINEL-LOGGER] kvIncr failed ${res.status} for ${key}`);
    return 0;
  }
  const data = await res.json();
  return data.result;
}

async function kvExpire(key, ttlSeconds) {
  const res = await fetch(`${KV_URL}/expire/${key}/${ttlSeconds}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${KV_TOKEN}` },
  });
  if (!res.ok) {
    console.error(`[SENTINEL-LOGGER] kvExpire failed ${res.status} for ${key}`);
  }
}

async function kvSet(key, value) {
  const body = String(value);
  const res = await fetch(`${KV_URL}/set/${key}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${KV_TOKEN}` },
    body,
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    console.error(`[SENTINEL-LOGGER] kvSet FAILED ${res.status} for ${key} — ${text}`);
    return false;
  }
  return true;
}

// ─── Auto-block writer ────────────────────────────────────────────────────────

async function writeAutoBlock(ip) {
  const key = `threat_action:${ip}`;
  const value = JSON.stringify({ action: 'block', autoBlocked: true, blockedAt: new Date().toISOString() });
  const ok = await kvSet(key, value);
  if (ok) {
    console.log(`[SENTINEL-LOGGER] AUTO-BLOCK WRITTEN — ${ip}`);
  } else {
    console.error(`[SENTINEL-LOGGER] AUTO-BLOCK FAILED — ${ip}`);
  }
}

// ─── Threat flag writer ───────────────────────────────────────────────────────

async function writeFlag(ip, severity, pattern, detail = '') {
  const key = `threat:flag:${ip}`;

  const existing = await kvGet(key);
  let shouldWriteFlag = true;
  if (existing) {
    try {
      const parsed = JSON.parse(existing);
      const levels = { LOW: 1, MEDIUM: 2, HIGH: 3 };
      if (levels[parsed.severity] >= levels[severity]) shouldWriteFlag = false;
    } catch { /* corrupt value — overwrite it */ }
  }

  if (shouldWriteFlag) {
    const flag = {
      ip,
      severity,
      pattern,
      detail,
      detectedAt: new Date().toISOString(),
    };

    const ok = await kvSet(key, JSON.stringify(flag));
    if (ok) {
      console.log(`[SENTINEL-LOGGER] FLAG WRITTEN — ${severity} | ${ip} | ${pattern} | ${detail}`);
    } else {
      console.error(`[SENTINEL-LOGGER] FLAG WRITE FAILED — ${severity} | ${ip} | ${pattern}`);
    }
  } else {
    console.log(`[SENTINEL-LOGGER] FLAG SKIPPED (existing flag same or higher severity) — ${severity} | ${ip} | ${pattern}`);
  }

  // AUTO-BLOCK: fires on every HIGH severity detection, independent of whether
  // the flag record itself needed (re)writing. This was the actual bug — the
  // dedup check above used to gate the auto-block call too, meaning a repeat
  // HIGH severity hit on an IP that already had a HIGH flag never re-triggered
  // the block, even if the block itself had since been manually cleared.
  if (severity === 'HIGH') {
    await writeAutoBlock(ip);
  }
}

// ─── Detection rules ──────────────────────────────────────────────────────────

const INJECTION_PATTERNS = [
  /ignore\s+(all\s+|the\s+)?(previous|above|prior|all|earlier)\s+(instructions?|prompts?|rules?)/i,
  /ignore\s+(previous|above|prior|all|earlier)/i,
  /disregard\s+(all\s+|any\s+|the\s+)?(previous|above|prior)/i,
  /system\s*prompt/i,
  /reveal\s+(your\s+)?(instructions?|prompts?|system|context)/i,
  /jailbreak/i,
  /act\s+as\s+(if\s+you\s+are\s+|a\s+)?(?:dan|evil|unrestricted|unfiltered)/i,
  /\[INST\]|\[\/INST\]|<\|system\|>|<\|user\|>/i,
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

async function checkUserAgent(ip, req) {
  const ua = req.headers['user-agent'] || '';

  if (!ua) {
    await writeFlag(ip, 'HIGH', 'missing_ua', 'No User-Agent header');
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

async function checkKeyFailure(ip) {
  const key = `keyfail:${ip}`;
  const count = await kvIncr(key);
  if (count === 1) await kvExpire(key, 3600);
  if (count >= 3) {
    await writeFlag(ip, 'MEDIUM', 'repeated_key_failure', `${count} failures in 1h`);
  }
}

async function checkRequestVolume(ip) {
  const key = `reqcount:${ip}`;
  const count = await kvIncr(key);
  if (count === 1) await kvExpire(key, 60);

  if (count > 10) {
    const excessKey = `reqexcess:${ip}`;
    const excess = await kvIncr(excessKey);
    if (excess === 1) await kvExpire(excessKey, 60);
    if (excess >= 5) {
      await writeFlag(ip, 'LOW', 'high_request_volume', `${count} requests in 60s`);
    }
  }
}

async function checkMalformedRequest(ip, body, expectedFields) {
  if (!body || typeof body !== 'object') {
    const malformKey = `malform:${ip}`;
    const count = await kvIncr(malformKey);
    if (count === 1) await kvExpire(malformKey, 300);
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
    console.error('[SENTINEL-LOGGER] Error in threat detection:', err.message);
  }

  return ip;
}

export async function logKeyFailure(ip) {
  if (!KV_URL || !KV_TOKEN) return;
  try {
    await checkKeyFailure(ip);
  } catch (err) {
    console.error('[SENTINEL-LOGGER] Error in key failure tracking:', err.message);
  }
}
