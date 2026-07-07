// api/cartoon.js
// GET /api/cartoon                — today's strip (falls back to latest)
// GET /api/cartoon?date=YYYY-MM-DD — a specific strip (falls back to latest if not found)
// GET /api/cartoon?archive=true    — last 30 published dates, most recent first
//
// Public, read-only, same isBlocked()/logRequest() pattern as the other
// feed endpoints (mainstream-feed.js, news-feed.js, etc).

import { kv } from "@vercel/kv";
import { logRequest } from "./_lib/sentinel.js";

const ALLOWED_ORIGINS = ["https://quantumrx.eu", "https://www.quantumrx.eu"];

function getIP(req) {
  return (req.headers["x-forwarded-for"] || "").split(",")[0].trim()
    || req.socket?.remoteAddress || "unknown";
}

async function isBlocked(ip) {
  const kvUrl = process.env.UPSTASH_REDIS_REST_URL;
  const kvToken = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!kvUrl || !kvToken) return false;
  try {
    const res = await fetch(
      `${kvUrl}/get/threat_action:${ip}`,
      { headers: { Authorization: `Bearer ${kvToken}` }, signal: AbortSignal.timeout(800) }
    );
    if (!res.ok) return false;
    const data = await res.json();
    if (!data.result) return false;
    const parsed = JSON.parse(data.result);
    return parsed.action === "block";
  } catch { return false; }
}

export default async function handler(req, res) {
  const ip = getIP(req);
  await logRequest(req, "cartoon");
  if (await isBlocked(ip)) {
    return res.status(403).json({ error: "Access monitored" });
  }

  const origin = req.headers.origin || "";
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
  }
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  if (req.method === "OPTIONS") return res.status(200).end();

  // Short edge TTL deliberately, not the hour-long window this started
  // with: cartoon-refresh.js can run at any moment (cron or manual
  // trigger) and there's no cache-purge step, so a long s-maxage means
  // real visitors can be stuck seeing a stale/empty response for up to
  // that whole window after a refresh. 60s self-heals fast while still
  // absorbing normal traffic between requests.
  res.setHeader("Cache-Control", "public, s-maxage=60, stale-while-revalidate=300");

  try {
    if (req.query?.archive === "true") {
      const index = (await kv.get("cartoon:index")) || [];
      const archive = index.slice(-30).reverse();
      return res.status(200).json({ archive });
    }

    const requestedDate = typeof req.query?.date === "string" ? req.query.date : null;
    const latestDate = await kv.get("cartoon:latest");

    let cartoon = null;
    if (requestedDate) {
      cartoon = await kv.get(`cartoon:${requestedDate}`);
    }
    // Falls back to latest whenever no date was requested, or the
    // requested date doesn't exist in KV — same fallback behaviour the
    // spec calls for, and consistent with every other feed endpoint's
    // "never show a broken page" posture.
    if (!cartoon && latestDate) {
      cartoon = await kv.get(`cartoon:${latestDate}`);
    }

    if (!cartoon) {
      return res.status(200).json({ date: null, issueNumber: null, title: null, panels: [] });
    }

    return res.status(200).json(cartoon);
  } catch (err) {
    console.error("[cartoon] error:", err);
    return res.status(500).json({ error: "Failed to load cartoon" });
  }
}
