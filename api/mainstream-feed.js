// api/mainstream-feed.js
// v2 CHANGE: dropped the auto-block on Origin mismatch. Same reasoning as
// news-feed.js and weekly-feed.js — public, read-only GET, no cost per call,
// nothing confidential to protect. A 30-day auto-block shared via
// threat_action:<ip> with chat.js and every other feed endpoint is too
// severe a penalty for a mismatched-but-legitimate Origin. isBlocked() is
// kept for genuinely flagged IPs. Origin mismatches are logged via
// logRequest for visibility, not auto-blocked.
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
      `${kvUrl}/get/threat_action:${encodeURIComponent(ip)}`,
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
  await logRequest(req, "mainstream-feed");
  if (await isBlocked(ip)) {
    return res.status(403).json({ error: "Access monitored" });
  }
  const origin = req.headers.origin || "";
  // Origin mismatch logged above via logRequest, not blocked — public read
  // data, no cost per call. Only set CORS headers for a known-good origin.
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
  }
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  if (req.method === "OPTIONS") return res.status(200).end();
  try {
    const data = await kv.get("qrx_mainstream");
    if (!data) return res.status(200).json({ items: [], updated: null });
    return res.status(200).json(data);
  } catch (err) {
    console.error("[mainstream-feed] KV error:", err);
    return res.status(500).json({ error: "Failed to load mainstream feed" });
  }
}
