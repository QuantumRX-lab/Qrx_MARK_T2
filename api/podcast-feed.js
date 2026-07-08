// api/podcast-feed.js
// Returns the cached "Top 50 Tech" podcast list from KV (qrx_podcasts).
// Public, read-only GET — same pattern as draw-feed.js / news-feed.js:
// no auth, no cost per call, nothing confidential. isBlocked() still
// refuses genuinely flagged IPs; an Origin mismatch is logged (via
// logRequest) but NOT auto-blocked.
//
// ALLOWED_ORIGINS includes the Vercel domains (forge/tools) because this
// endpoint is called from podcasts.html served there, unlike the Ghost
// feeds which are called from quantumrx.eu.
import { kv } from "@vercel/kv";
import { logRequest } from "./_lib/sentinel.js";

const ALLOWED_ORIGINS = [
  "https://forge.quantumrx.eu",
  "https://tools.quantumrx.eu",
  "https://quantumrx.eu",
  "https://www.quantumrx.eu",
];

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
    return JSON.parse(data.result).action === "block";
  } catch { return false; }
}

export default async function handler(req, res) {
  const ip = getIP(req);
  await logRequest(req, "podcast-feed");
  if (await isBlocked(ip)) return res.status(403).json({ error: "Access monitored" });

  const origin = req.headers.origin || "";
  // Origin mismatch is logged above via logRequest, not blocked — public read
  // data. Only set CORS headers for a known-good origin.
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
  }
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  if (req.method === "OPTIONS") return res.status(200).end();
  res.setHeader("Cache-Control", "no-cache");

  try {
    const data = await kv.get("qrx_podcasts");
    if (!data) return res.status(200).json({ items: [], updated: null, empty: true });
    return res.status(200).json(data);
  } catch {
    return res.status(500).json({ error: "Podcast feed temporarily unavailable" });
  }
}
