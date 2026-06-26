// /api/_lib/sentinel.js
// Q-Sentinel integration for the Signals endpoints.
// Mirrors the existing request-logger.js -> Upstash KV -> Sentinel monitor pipeline.
// Writes into the sentinel:news:* namespace so the live monitor picks it up
// with no extra configuration.

import { kv } from "@vercel/kv";

function clientIp(req) {
  const fwd = req.headers["x-forwarded-for"];
  return (Array.isArray(fwd) ? fwd[0] : fwd || "").split(",")[0].trim() || "unknown";
}

// Standard request log. Fires on every protected-endpoint hit.
export async function logRequest(req, endpoint) {
  try {
    const ip = clientIp(req);
    const ts = Date.now();
    const entry = {
      ts,
      ip,
      endpoint,
      ua: req.headers["user-agent"] || "",
      method: req.method,
      category: req.query?.category || null,
    };
    // Append to a capped rolling log for the monitor dashboard.
    await kv.lpush("sentinel:news:log", JSON.stringify(entry));
    await kv.ltrim("sentinel:news:log", 0, 999);

    // Refresh-endpoint rate rule: cron runs once daily. More than twice in an
    // hour from any source is suspicious. Track a 1h sliding counter.
    if (endpoint === "news-refresh") {
      const bucket = `sentinel:news:refreshrate:${Math.floor(ts / 3600000)}`;
      const count = await kv.incr(bucket);
      await kv.expire(bucket, 3600);
      if (count > 2) {
        await raiseAlert(req, endpoint, "refresh-rate-exceeded", { count });
      }
    }
  } catch {
    // Logging must never break the request path.
  }
}

// Threat event: unauthorised access attempt on a protected endpoint.
export async function blockThreat(req, endpoint, reason) {
  await raiseAlert(req, endpoint, reason, { blocked: true });
}

async function raiseAlert(req, endpoint, reason, meta = {}) {
  try {
    const alert = {
      ts: Date.now(),
      level: "high",
      endpoint,
      reason,
      ip: clientIp(req),
      ua: req.headers["user-agent"] || "",
      ...meta,
    };
    await kv.lpush("sentinel:news:alerts", JSON.stringify(alert));
    await kv.ltrim("sentinel:news:alerts", 0, 199);
    await kv.incr("sentinel:news:alertcount");
  } catch {
    /* swallow */
  }
}
