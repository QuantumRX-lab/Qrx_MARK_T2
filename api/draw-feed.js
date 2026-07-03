// api/draw-feed.js
// Returns cached Draw stories from KV
// ?tab=main or ?tab=finance

import { kv } from "@vercel/kv";
import { logRequest } from "./_lib/sentinel.js";

const ALLOWED_ORIGINS = ["https://quantumrx.eu", "https://www.quantumrx.eu"];

function getIP(req) {
  return (req.headers["x-forwarded-for"] || "").split(",")[0].trim() || req.socket?.remoteAddress || "unknown";
}

async function isBlocked(ip) {
  const kvUrl = process.env.UPSTASH_REDIS_REST_URL;
  const kvToken = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!kvUrl || !kvToken) return false;
  try {
    const res = await fetch(`${kvUrl}/get/threat_action:${encodeURIComponent(ip)}`,
      { headers: { Authorization: `Bearer ${kvToken}` }, signal: AbortSignal.timeout(800) });
    if (!res.ok) return false;
    const data = await res.json();
    if (!data.result) return false;
    return JSON.parse(data.result).action === "block";
  } catch { return false; }
}

async function writeBlock(ip, endpoint) {
  const kvUrl = process.env.UPSTASH_REDIS_REST_URL;
  const kvToken = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!kvUrl || !kvToken) return;
  const now = new Date().toISOString();
  try {
    await fetch(`${kvUrl}/set/threat_action:${encodeURIComponent(ip)}?EX=${60*60*24*30}`, {
      method: "POST", headers: { Authorization: `Bearer ${kvToken}` },
      body: JSON.stringify({ action: "block", autoBlocked: true, blockedAt: now, reason: endpoint }),
    });
    await fetch(`${kvUrl}/set/threat:flag:${encodeURIComponent(ip)}`, {
      method: "POST", headers: { Authorization: `Bearer ${kvToken}` },
      body: JSON.stringify({ ip, severity: "HIGH", pattern: "bad_origin", detail: endpoint, detectedAt: now }),
    });
  } catch {}
}

export default async function handler(req, res) {
  const ip = getIP(req);
  await logRequest(req, "draw-feed");

  if (await isBlocked(ip)) return res.status(403).json({ error: "Access monitored" });

  const origin = req.headers.origin || "";
  if (origin && !ALLOWED_ORIGINS.includes(origin)) {
    await writeBlock(ip, "draw-feed:bad-origin");
    return res.status(403).json({ error: "Forbidden" });
  }

  if (origin) { res.setHeader("Access-Control-Allow-Origin", origin); res.setHeader("Vary", "Origin"); }
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  if (req.method === "OPTIONS") return res.status(200).end();
  res.setHeader("Cache-Control", "no-cache");

  const tab = (req.query.tab || "main").toLowerCase();
  const key = tab === "finance" ? "qrx_draw_finance" : "qrx_draw_main";

  try {
    const data = await kv.get(key);
    if (!data) return res.status(200).json({ items: [], updated: null });
    return res.status(200).json(data);
  } catch {
    return res.status(500).json({ error: "Feed temporarily unavailable" });
  }
}
