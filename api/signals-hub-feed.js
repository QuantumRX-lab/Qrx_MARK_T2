// api/signals-hub-feed.js
// One read for the consolidated Signals hub: merges every Signals category,
// The Draw (world + finance) and Mainstream into a single ordered list with a
// unified category taxonomy, plus the Watch videos for weaving into the
// stream. Replaces the 13 separate per-category/per-page reads the old
// pages made (13 serverless invocations + 13 Sentinel log writes per view).
//
// Ordering: curated "What's Hot" picks first (they are cross-vertical picks
// that mostly do NOT appear in any category bucket — verified 7/8 unique on
// 2026-09-18), then everything else newest-first. Dedupe is by link.
//
// Taxonomy (tab <- source labels):
//   AI               <- Signals aimoves; Mainstream "AI"
//   Chips & Quantum  <- semis, quantum; "Semiconductors", "Quantum"
//   Robotics         <- robotics; "Robotics"
//   Space            <- space; "Space"
//   Connectivity     <- "Connectivity" (Mainstream only; rare)
//   Energy & Climate <- energy; "Energy", "Climate"
//   Policy           <- policy; Mainstream "Policy" (tech policy)
//   World            <- Draw "World", and Draw-main "Policy" (geopolitics —
//                       20/44 of Draw's headlines get that label and would
//                       swamp the tech-policy tab)
//   Conflict         <- Draw "Conflict"
//   Markets          <- crypto; "Business", "Crypto"
//   Social           <- social
//   Science          <- Draw "Science"
// The source's own finer label is kept as `subcategory` for the card tag.

import { kv } from "@vercel/kv";
import { logRequest } from "./_lib/sentinel.js";

const ALLOWED_ORIGINS = ["https://quantumrx.eu", "https://www.quantumrx.eu"];

const SIGNALS = {
  aimoves: "AI", semis: "Chips & Quantum", quantum: "Chips & Quantum", robotics: "Robotics",
  space: "Space", energy: "Energy & Climate", policy: "Policy", crypto: "Markets", social: "Social",
};
const SIGNALS_SUB = {
  aimoves: "AI", semis: "Semiconductors", quantum: "Quantum", robotics: "Robotics", space: "Space",
  energy: "Energy", policy: "Policy", crypto: "Crypto", social: "Social",
};
const LABELS = {
  AI: "AI", Connectivity: "Connectivity", Semiconductors: "Chips & Quantum", Quantum: "Chips & Quantum",
  Robotics: "Robotics", Space: "Space", Energy: "Energy & Climate", Climate: "Energy & Climate",
  Policy: "Policy", Business: "Markets", Crypto: "Markets", World: "World", Conflict: "Conflict",
  Science: "Science",
};

function getIP(req) {
  return (req.headers["x-forwarded-for"] || "").split(",")[0].trim() || req.socket?.remoteAddress || "unknown";
}
async function isBlocked(ip) {
  const kvUrl = process.env.UPSTASH_REDIS_REST_URL, kvToken = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!kvUrl || !kvToken) return false;
  try {
    const res = await fetch(`${kvUrl}/get/threat_action:${ip}`, { headers: { Authorization: `Bearer ${kvToken}` }, signal: AbortSignal.timeout(800) });
    if (!res.ok) return false;
    const data = await res.json();
    return data.result ? JSON.parse(data.result).action === "block" : false;
  } catch { return false; }
}

function shape(it, category, subcategory, feed) {
  return {
    title: it.title || "",
    link: it.link || it.url || "",
    description: it.description || "",
    summary: it.summary || "",
    what_is_it: it.what_is_it || "",
    why_it_matters: it.why_it_matters || "",
    what_next: it.what_next || it.what_to_watch || "",
    hot_take: it.hot_take || "",
    image: it.image || "",
    source: it.source || it.outlets || "",
    published: typeof it.published === "number" ? it.published : (Date.parse(it.published) || 0),
    category, subcategory, feed,
    hot: false, hotRank: null,
  };
}

export default async function handler(req, res) {
  const ip = getIP(req);
  await logRequest(req, "signals-hub-feed");
  if (await isBlocked(ip)) return res.status(403).json({ error: "Access monitored" });
  const origin = req.headers.origin || "";
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
  }
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  if (req.method === "OPTIONS") return res.status(200).end();
  // Feeds refresh once daily at 06:00 UTC; five minutes of edge caching
  // collapses a burst of page views into a single KV read.
  res.setHeader("Cache-Control", "public, s-maxage=300, stale-while-revalidate=600");

  try {
    const sigKeys = Object.keys(SIGNALS);
    const keys = [
      ...sigKeys.map((c) => `qrx_feed_${c}`),
      "qrx_feed_hot", "qrx_feed_video", "qrx_draw_main", "qrx_draw_finance", "qrx_mainstream",
    ];
    const vals = await Promise.all(keys.map((k) => kv.get(k).catch(() => null)));
    const byKey = Object.fromEntries(keys.map((k, i) => [k, vals[i]]));

    const seen = new Map();
    const items = [];
    const add = (it, category, subcategory, feed) => {
      const s = shape(it, category, subcategory, feed);
      if (!s.link || !s.title) return null;
      if (seen.has(s.link)) return seen.get(s.link);
      seen.set(s.link, s);
      items.push(s);
      return s;
    };

    sigKeys.forEach((c) => ((byKey[`qrx_feed_${c}`]?.items) || []).forEach((it) => add(it, SIGNALS[c], SIGNALS_SUB[c], "signals")));
    ((byKey.qrx_mainstream?.items) || []).forEach((it) => add(it, LABELS[it.category] || "AI", it.category || "Tech", "mainstream"));
    ((byKey.qrx_draw_main?.items) || []).forEach((it) => {
      const cat = it.category === "Policy" ? "World" : (LABELS[it.category] || "World");
      add(it, cat, it.category || "World", "draw");
    });
    ((byKey.qrx_draw_finance?.items) || []).forEach((it) => add(it, LABELS[it.category] || "Markets", it.category || "Business", "draw"));
    ((byKey.qrx_feed_hot?.items) || []).forEach((it, i) => {
      const s = add(it, null, "Top story", "signals");
      if (s) { s.hot = true; s.hotRank = i; }
    });

    items.sort((a, b) => {
      if (a.hot !== b.hot) return a.hot ? -1 : 1;
      if (a.hot && b.hot) return a.hotRank - b.hotRank;
      return b.published - a.published;
    });

    const counts = {};
    items.forEach((it) => { if (it.category) counts[it.category] = (counts[it.category] || 0) + 1; });

    const videos = ((byKey.qrx_feed_video?.items) || []).map((v) => ({
      title: v.title || "", link: v.link || v.url || "", image: v.image || "", source: v.source || "",
      summary: v.summary || "", vertical: v.vertical || "",
    })).filter((v) => v.link && v.title);

    const stamps = [byKey.qrx_feed_hot?.updated, byKey.qrx_draw_main?.updated, byKey.qrx_mainstream?.updated]
      .map((u) => (typeof u === "number" ? u : Date.parse(u) || 0));
    return res.status(200).json({ updated: Math.max(0, ...stamps) || null, total: items.length, counts, items, videos });
  } catch {
    return res.status(500).json({ error: "Feed temporarily unavailable" });
  }
}
