// api/meme.js
// GET /api/meme                — today's meme (falls back to latest)
// GET /api/meme?date=YYYY-MM-DD — a specific meme (falls back to latest if not found)
// GET /api/meme?archive=true    — last 30 published dates, most recent first
//
// Public, read-only, same isBlocked()/logRequest() pattern as cartoon.js
// and the other feed endpoints.

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
  await logRequest(req, "meme");
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

  // Short edge TTL, same reasoning as cartoon.js: meme-refresh.js can run
  // at any moment (cron or manual trigger) with no cache-purge step, so a
  // long s-maxage would leave real visitors stuck on a stale response.
  res.setHeader("Cache-Control", "public, s-maxage=60, stale-while-revalidate=300");

  try {
    if (req.query?.archive === "true") {
      const index = (await kv.get("meme:index")) || [];
      const archive = index.slice(-30).reverse();
      return res.status(200).json({ archive });
    }

    const requestedDate = typeof req.query?.date === "string" ? req.query.date : null;
    const latestDate = await kv.get("meme:latest");

    let meme = null;
    if (requestedDate) {
      meme = await kv.get(`meme:${requestedDate}`);
    }
    if (!meme && latestDate) {
      meme = await kv.get(`meme:${latestDate}`);
    }

    if (!meme) {
      return res.status(200).json({ date: null, issueNumber: null, title: null, topText: null, bottomText: null, imageUrl: null });
    }

    return res.status(200).json(meme);
  } catch (err) {
    console.error("[meme] error:", err);
    return res.status(500).json({ error: "Failed to load meme" });
  }
}
