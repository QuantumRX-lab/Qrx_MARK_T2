// api/mainstream-refresh.js
// QuantumRx Mainstream — daily refresh engine
// Sources: BBC Tech, Reuters, Guardian Tech, Wired, The Verge, Ars Technica, MIT Tech Review, The Register
// Selects best 2 stories per outlet (16 total), generates 4-bullet summary per story
// Writes to KV as qrx_mainstream with 25h TTL

import { kv } from "@vercel/kv";
import { logRequest, blockThreat } from "./_lib/sentinel.js";

const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent";

const FEEDS = [
  { url: "http://feeds.bbci.co.uk/news/technology/rss.xml",          source: "BBC Technology",      dot: "dot-bbc" },
  { url: "https://feeds.reuters.com/reuters/technologyNews",          source: "Reuters",             dot: "dot-reuters" },
  { url: "https://www.theguardian.com/uk/technology/rss",            source: "The Guardian",        dot: "dot-guardian" },
  { url: "https://www.wired.com/feed/rss",                           source: "Wired",               dot: "dot-wired" },
  { url: "https://www.theverge.com/rss/index.xml",                   source: "The Verge",           dot: "dot-verge" },
  { url: "https://feeds.arstechnica.com/arstechnica/technology-lab", source: "Ars Technica",        dot: "dot-ars" },
  { url: "https://www.technologyreview.com/feed/",                   source: "MIT Technology Review",dot: "dot-mit" },
  { url: "https://www.theregister.com/headlines.atom",               source: "The Register",        dot: "dot-register" },
];

const UA = "QuantumRx-Mainstream/1.0 (+https://quantumrx.eu)";
const TTL = 60 * 60 * 25;

function isSafeUrl(url) {
  try {
    const u = new URL(url);
    if (u.protocol !== "https:" && u.protocol !== "http:") return false;
    const host = u.hostname;
    if (host === "localhost" || host === "0.0.0.0") return false;
    if (host.startsWith("127.") || host.startsWith("10.") || host.startsWith("192.168.")) return false;
    if (host.startsWith("172.") && parseInt(host.split(".")[1]) >= 16 && parseInt(host.split(".")[1]) <= 31) return false;
    if (host === "169.254.169.254") return false;
    if (host.endsWith(".internal") || host.endsWith(".local")) return false;
    return true;
  } catch { return false; }
}

function sanitiseImageUrl(url) {
  if (!url) return "";
  try {
    const u = new URL(url);
    return u.protocol === "https:" || u.protocol === "http:" ? url : "";
  } catch { return ""; }
}

function decode(s = "") {
  return s
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(parseInt(n, 10)))
    .replace(/&#x([0-9a-fA-F]+);/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/<[^>]+>/g, "").trim();
}

function pickTag(block, tag) {
  const m = block.match(new RegExp("<" + tag + "[^>]*>([\\s\\S]*?)<\\/" + tag + ">", "i"));
  return m ? m[1] : "";
}

function pickAttr(block, tag, attr) {
  const m = block.match(new RegExp("<" + tag + "[^>]*\\b" + attr + "=[\"']([^\"']+)[\"']", "i"));
  return m ? m[1] : "";
}

function findImage(block) {
  return (
    pickAttr(block, "media:thumbnail", "url") ||
    pickAttr(block, "media:content", "url") ||
    pickAttr(block, "enclosure", "url") ||
    (block.match(/<img[^>]+src=["']([^"']+)["']/i) || [])[1] ||
    ""
  );
}

async function fetchOgImage(url) {
  if (!isSafeUrl(url)) return "";
  try {
    const res = await fetch(url, {
      headers: { "User-Agent": UA },
      signal: AbortSignal.timeout(5000),
      redirect: "follow",
    });
    if (!res.ok) return "";
    const html = await res.text();
    const ogImg =
      (html.match(/<meta[^>]*property=["']og:image["'][^>]*content=["']([^"']+)["']/i) || [])[1] ||
      (html.match(/<meta[^>]*content=["']([^"']+)["'][^>]*property=["']og:image["']/i) || [])[1] ||
      "";
    return sanitiseImageUrl(ogImg.replace(/&amp;/g, "&"));
  } catch { return ""; }
}

// ── XML parser ────────────────────────────────────────────────────────────────
function parseXML(xml, source, dot) {
  const items = [];
  const entries = [...xml.matchAll(/<(?:item|entry)[^>]*>([\s\S]*?)<\/(?:item|entry)>/gi)];
  for (const entry of entries.slice(0, 15)) {
    const block = entry[1];
    const title = decode(pickTag(block, "title"));
    const link = decode(pickTag(block, "link")) || pickAttr(block, "link", "href");
    const description = decode(pickTag(block, "description") || pickTag(block, "summary") || pickTag(block, "content"));
    const pubDate = decode(pickTag(block, "pubDate") || pickTag(block, "published") || pickTag(block, "updated"));
    if (!title || title.length < 10) continue;
    items.push({
      title: title.slice(0, 200),
      description: description.slice(0, 400),
      url: link.trim(),
      source,
      dot,
      published: pubDate ? new Date(pubDate).getTime() : Date.now(),
      image: sanitiseImageUrl(findImage(block)),
    });
  }
  return items;
}

function extractJSON(text) {
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) return fence[1].trim();
  const bracket = text.match(/(\[[\s\S]*\])/);
  if (bracket) return bracket[1].trim();
  return text.trim();
}

// ── Fetch one RSS feed ────────────────────────────────────────────────────────
async function fetchFeed(feed) {
  try {
    const res = await fetch(feed.url, {
      headers: { "User-Agent": UA },
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) return [];
    const xml = await res.text();
    return parseXML(xml, feed.source, feed.dot);
  } catch {
    return [];
  }
}

// ── Gemini: select best 2 stories from one outlet's pool ─────────────────────
async function geminiSelectOutlet(items, source, apiKey) {
  if (!items.length) return [];

  // Take up to 8 most recent from this outlet for Gemini to pick from
  const pool = items.slice(0, 8);
  const list = pool
    .map((it, i) => `[${i}] TITLE: ${it.title}\nEXCERPT: ${it.description.slice(0, 200)}`)
    .join("\n\n");

  const prompt = `You are the editor of QuantumRx. From these ${source} stories, select the 2 most significant for a technically literate audience. Prioritise genuine news impact, policy implications, infrastructure shifts, and major company moves. Avoid opinion pieces, listicles, consumer how-to content, promo codes, discount offers, coupon articles, affiliate marketing content, and anything that is not genuine tech news.

For each selected story return exactly 4 bullet points covering:
1. What happened (the concrete fact)
2. The scale or context (numbers, geography, or timeline)
3. Why it matters for the tech industry
4. What to watch next (one specific, checkable signal)

Each bullet should be one tight sentence. No hype, no filler.

Return ONLY a JSON array, no markdown, no preamble:
[{"index": <number>, "bullets": ["...", "...", "...", "..."]}]

STORIES:
${list}`;

  try {
    const res = await fetch(`${GEMINI_URL}?key=${apiKey}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.3,
          maxOutputTokens: 1500,
          thinkingConfig: { thinkingBudget: 0 },
        },
      }),
      signal: AbortSignal.timeout(20000),
    });
    const data = await res.json();
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text || "[]";
    const picks = JSON.parse(extractJSON(text));

    return picks
      .filter((p) => pool[p.index] && Array.isArray(p.bullets) && p.bullets.length)
      .map((p) => ({
        ...pool[p.index],
        bullets: p.bullets.slice(0, 4),
      }))
      .slice(0, 2);
  } catch {
    return pool.slice(0, 2).map((it) => ({
      ...it,
      bullets: [it.description.slice(0, 120) || it.title],
    }));
  }
}

// ── Handler ───────────────────────────────────────────────────────────────────
export default async function handler(req, res) {
  await logRequest(req, "mainstream-refresh");

  const provided = req.headers["x-cron-secret"];
  const expected = process.env.CRON_SECRET;
  if (!expected || provided !== expected) {
    await blockThreat(req, "mainstream-refresh", "missing-or-invalid-cron-secret");
    return res.status(401).json({ error: "Unauthorized" });
  }

  const apiKey = process.env.GEMINI_API_KEY_Forge;
  if (!apiKey) return res.status(500).json({ error: "Missing Gemini API key" });

  const startedAt = new Date().toISOString();
  const t0 = Date.now();

  // 1. Fetch all feeds in parallel
  const feedResults = await Promise.all(FEEDS.map(fetchFeed));
  const allItems = feedResults.flat();

  // 2. Deduplicate by URL
  const seen = new Set();
  const dedupedItems = allItems.filter((it) => {
    if (!it.url || seen.has(it.url)) return false;
    seen.add(it.url);
    return true;
  });

  // 3. Sort by recency
  const sorted = [...dedupedItems].sort((a, b) => b.published - a.published);

  // 3b. Enrich missing images via OG fetch
  // Also re-fetch for known hotlink-blocking domains (Guardian, Reuters etc)
  const hotlinkBlocked = ['theguardian.com', 'reuters.com', 'bbc.co.uk', 'bbc.com'];
  const needsImg = sorted.filter((it) => {
    if (!it.image) return true;
    try { return hotlinkBlocked.some((d) => new URL(it.image).hostname.includes(d)); } catch { return false; }
  }).slice(0, 25);
  if (needsImg.length) {
    const imgResults = await Promise.allSettled(needsImg.map((it) => fetchOgImage(it.url)));
    imgResults.forEach((r, i) => {
      if (r.status === "fulfilled" && r.value) needsImg[i].image = r.value;
    });
  }

  // 4. Per-outlet Gemini selection — 2 best stories per outlet
  // Group items by source first
  const bySource = {};
  FEEDS.forEach(function(feed) { bySource[feed.source] = []; });
  sorted.forEach(function(it) {
    if (bySource[it.source]) bySource[it.source].push(it);
  });

  // Run all 8 outlets in parallel
  const outletResults = await Promise.all(
    FEEDS.map((feed) => geminiSelectOutlet(bySource[feed.source] || [], feed.source, apiKey))
  );

  // Flatten — 2 stories per outlet = 16 total, ordered by outlet then recency
  const stories = outletResults.flat();

  // 5. Write to KV
  await kv.set("qrx_mainstream", {
    updated: startedAt,
    items: stories,
  }, { ex: TTL });

  const elapsed = Date.now() - t0;

  return res.status(200).json({
    ok: true,
    elapsedMs: elapsed,
    counts: {
      fetched: allItems.length,
      deduped: dedupedItems.length,
      selected: stories.length,
      perOutlet: 2,
    },
  });
}
