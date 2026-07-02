import { kv } from "@vercel/kv";
import { logRequest, blockThreat, getSentinelAction } from "./_lib/sentinel.js";

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

const ALLOWED_ORIGINS = ["https://quantumrx.eu", "https://www.quantumrx.eu"];

export default async function handler(req, res) {
  await logRequest(req, "news-feed");

  // Sentinel block check
  const action = await getSentinelAction(req).catch(() => null);
  if (action === "block") {
    return res.status(403).json({ error: "Access monitored" });
  }

  const origin = req.headers.origin || "";
  const referer = req.headers.referer || "";

  // Allow requests with no origin (direct server-side calls, Railway cron)
  // Block requests with an origin that isn't quantumrx.eu
  if (origin && !ALLOWED_ORIGINS.includes(origin)) {
    await blockThreat(req, "news-feed", "disallowed-origin:" + origin);
    return res.status(403).json({ error: "Forbidden" });
  }

  // Set CORS header for browser requests from allowed origins
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
