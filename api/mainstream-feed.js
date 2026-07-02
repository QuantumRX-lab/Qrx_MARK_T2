// api/mainstream-feed.js
// Returns cached mainstream stories from KV

import { kv } from "@vercel/kv";
import { logRequest } from "./_lib/sentinel.js";

export default async function handler(req, res) {
  await logRequest(req, "mainstream-feed");

  res.setHeader("Access-Control-Allow-Origin", "*");
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
