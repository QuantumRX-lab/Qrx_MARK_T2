// api/weekly-feed.js
// v2 CHANGE: dropped the auto-block on Origin mismatch for this endpoint.
// This is a public, read-only GET serving already-public briefing data —
// no cost per call, nothing confidential to protect. A 30-day auto-block
// on Origin mismatch is too severe a penalty for what is often just a
// legitimate non-browser client (API testing tools, direct URL access,
// local dev) rather than actual abuse. CORS header behavior is unchanged;
// only the writeBlock-on-mismatch behavior is removed. Origin mismatches
// are still logged (visible via logRequest) for visibility without a
// punitive lockout. isBlocked() is kept — genuine flagged IPs (from other
// endpoints, or manually) are still refused here.
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
      // Raw ip — must match writeAutoBlock() in request-logger.js. Encoding
      // here breaks the key match for IPv6 addresses.
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
  await logRequest(req, "weekly-feed");
  if (await isBlocked(ip)) {
    return res.status(403).json({ error: "Access monitored" });
  }
  const origin = req.headers.origin || "";
  if (origin && !ALLOWED_ORIGINS.includes(origin)) {
    // Mismatch noted via logRequest above — no block, no 403. This is a
    // public read endpoint; an unexpected Origin isn't treated as a threat
    // here. Fall through and serve the request normally, just without
    // setting CORS headers for that origin below.
  } else if (origin) {
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
  }
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  if (req.method === "OPTIONS") return res.status(200).end();
  res.setHeader("Cache-Control", "no-cache");
  try {
    const stories = await kv.get("weekly_briefing_current");
    const meta = await kv.get("weekly_briefing_updated").catch(() => null);
    if (!stories || !stories.length) {
      return res.status(200).json({ current: null, previous: [] });
    }
    // Wrap into the shape the This Week page expects:
    // data.current = { stories, weekLabel, updatedAt, storyCount }
    const current = {
      stories,
      weekLabel: meta?.weekLabel || null,
      updatedAt: meta?.updatedAt || null,
      storyCount: stories.length,
    };
    // Previous editions — every archived week still inside its own TTL
    // (weekly-refresh.js archives the outgoing edition under
    // weekly_briefing_archive_<weekLabel> each time it runs, with a
    // 21-day expiry). This naturally accumulates a rolling history —
    // one archive key gets added per refresh, older ones drop off on
    // their own once they expire — so `previous` is always the full
    // list of everything currently retained, not just the last one.
    let previous = [];
    try {
      const archiveKeys = await kv.keys("weekly_briefing_archive_*");
      const editions = await Promise.all(archiveKeys.map((k) => kv.get(k).catch(() => null)));
      previous = editions
        .filter(Boolean)
        .sort((a, b) => new Date(b.updatedAt || 0) - new Date(a.updatedAt || 0));
    } catch {
      previous = [];
    }
    return res.status(200).json({ current, previous });
  } catch {
    return res.status(500).json({ error: "Weekly feed temporarily unavailable" });
  }
}
