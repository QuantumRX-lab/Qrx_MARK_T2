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

async function writeBlock(ip, endpoint) {
  const kvUrl = process.env.UPSTASH_REDIS_REST_URL;
  const kvToken = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!kvUrl || !kvToken) return;
  const ttl = 60 * 60 * 24 * 30;
  const now = new Date().toISOString();
  try {
    // Write auto-block
    const blockVal = JSON.stringify({ action: "block", autoBlocked: true, blockedAt: now, reason: endpoint });
    await fetch(`${kvUrl}/set/threat_action:${encodeURIComponent(ip)}?EX=${ttl}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${kvToken}` },
      body: blockVal,
    });
    // Write Sentinel flag so monitor.js fires terminal alert
    const flagVal = JSON.stringify({ ip, severity: "HIGH", pattern: "bad_origin", detail: endpoint, detectedAt: now });
    await fetch(`${kvUrl}/set/threat:flag:${encodeURIComponent(ip)}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${kvToken}` },
      body: flagVal,
    });
    console.log(`[SENTINEL] AUTO-BLOCK + FLAG — ${ip} — ${endpoint}`);
  } catch (err) {
    console.error(`[SENTINEL] writeBlock failed — ${ip} —`, err.message);
  }
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

  // Block requests from unknown origins, allow no-origin (server calls, cron)
  if (origin && !ALLOWED_ORIGINS.includes(origin)) {
    await writeBlock(ip, "news-feed:bad-origin");
    return res.status(403).json({ error: "Forbidden" });
  }

  if (origin) {
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
