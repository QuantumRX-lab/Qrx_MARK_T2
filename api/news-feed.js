// api/news-feed.js
// v2 CHANGE: dropped the auto-block on Origin mismatch. This is a public,
// read-only GET serving already-public Signals data, and it's the endpoint
// the chat widget itself calls on every vertical tap — meaning real visitor
// browsers hit this constantly with whatever Origin their session happens
// to carry. A 30-day auto-block on mismatch (shared via threat_action:<ip>
// with chat.js and weekly-feed.js) is too severe here: one edge-case Origin
// locks a real visitor out of the chat widget too, not just this endpoint.
// isBlocked() is kept — genuinely flagged IPs are still refused. Origin
// mismatches are logged via logRequest for visibility, not auto-blocked.
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
const KEYS = {
  hot:      "qrx_feed_hot",
  aimoves:  "qrx_feed_aimoves",
  crypto:   "qrx_feed_crypto",
  policy:   "qrx_feed_policy",
  energy:   "qrx_feed_energy",
  space:    "qrx_feed_space",
  robotics: "qrx_feed_robotics",
  semis:    "qrx_feed_semis",
  quantum:  "qrx_feed_quantum",
  social:   "qrx_feed_social",
  video:    "qrx_feed_video",
};
export default async function handler(req, res) {
  const ip = getIP(req);
  await logRequest(req, "news-feed");
  // Block already-blocked IPs
  if (await isBlocked(ip)) {
    return res.status(403).json({ error: "Access monitored" });
  }
  const origin = req.headers.origin || "";
  // Origin mismatch is logged above via logRequest, not blocked — this is
  // public read data, no cost per call, and the widget itself is the main
  // caller of this endpoint. Only set CORS headers for a known-good origin.
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
  }
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  if (req.method === "OPTIONS") return res.status(200).end();
  res.setHeader("Cache-Control", "no-cache");
  const tab = (req.query.tab || req.query.category || "hot").toLowerCase();
  const key = KEYS[tab];
  if (!key) return res.status(400).json({ error: "Unknown category" });
  try {
    const data = await kv.get(key);
    if (!data) return res.status(200).json({ updated: null, items: [], empty: true });
    return res.status(200).json(data);
  } catch {
    return res.status(500).json({ error: "Feed temporarily unavailable" });
  }
}
