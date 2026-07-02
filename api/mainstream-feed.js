// api/mainstream-feed.js
// Returns cached mainstream stories from KV

import { kv } from "@vercel/kv";
import { logRequest, blockThreat, getSentinelAction } from "./_lib/sentinel.js";

const ALLOWED_ORIGINS = ["https://quantumrx.eu", "https://www.quantumrx.eu"];

export default async function handler(req, res) {
  await logRequest(req, "mainstream-feed");

  // Sentinel block check
  const action = await getSentinelAction(req).catch(() => null);
  if (action === "block") {
    return res.status(403).json({ error: "Access monitored" });
  }

  const origin = req.headers.origin || "";

  // Block requests with an origin that isn't quantumrx.eu
  if (origin && !ALLOWED_ORIGINS.includes(origin)) {
    await blockThreat(req, "mainstream-feed", "disallowed-origin:" + origin);
    return res.status(403).json({ error: "Forbidden" });
  }

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
