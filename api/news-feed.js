import { kv } from "@vercel/kv";
import { logRequest } from "./_lib/sentinel.js";

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
  await logRequest(req, "news-feed");
  const category = (req.query.category || "hot").toLowerCase();
  const key = KEYS[category];
  const origin = req.headers.origin || "";
  const allowed = ["https://quantumrx.eu", "https://www.quantumrx.eu"];
  if (allowed.includes(origin)) {
    res.setHeader("Access-Control-Allow-Origin", origin);
  }
  res.setHeader("Cache-Control", "no-cache");
  if (!key) return res.status(400).json({ error: "Unknown category" });
  try {
    const data = await kv.get(key);
    if (!data) return res.status(200).json({ updated: null, items: [], empty: true });
    return res.status(200).json(data);
  } catch {
    return res.status(500).json({ error: "Feed temporarily unavailable" });
  }
}
