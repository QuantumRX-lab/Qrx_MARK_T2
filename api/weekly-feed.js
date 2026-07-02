// api/weekly-feed.js
// Returns cached weekly briefing from KV

import { kv } from "@vercel/kv";
import { logRequest, blockThreat, getSentinelAction } from "./_lib/sentinel.js";

const ALLOWED_ORIGINS = ["https://quantumrx.eu", "https://www.quantumrx.eu"];

export default async function handler(req, res) {
  await logRequest(req, "weekly-feed");

  // Sentinel block check
  const action = await getSentinelAction(req).catch(() => null);
  if (action === "block") {
    return res.status(403).json({ error: "Access monitored" });
  }

  const origin = req.headers.origin || "";

  if (origin && !ALLOWED_ORIGINS.includes(origin)) {
    await blockThreat(req, "weekly-feed", "disallowed-origin:" + origin);
    return res.status(403).json({ error: "Forbidden" });
  }

  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
  }
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  if (req.method === "OPTIONS") return res.status(200).end();
  res.setHeader("Cache-Control", "no-cache");

  try {
    const current = await kv.get("weekly_briefing_current");
    const previous = await kv.get("weekly_briefing_previous").catch(() => null);
    return res.status(200).json({ current: current || null, previous: previous || null });
  } catch {
    return res.status(500).json({ error: "Weekly feed temporarily unavailable" });
  }
}
