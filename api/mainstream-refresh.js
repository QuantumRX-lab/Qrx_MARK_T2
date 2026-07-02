// api/mainstream-refresh.js
// QuantumRx Mainstream — daily refresh engine
// Sources: BBC Tech, Reuters, Guardian Tech, Wired, The Verge, Ars Technica, MIT Tech Review, The Register
// Selects top 8 stories across all sources, generates 4-bullet summary per story
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

// ── XML parser ────────────────────────────────────────────────────────────────
function parseXML(xml, source, dot) {
  const items = [];
  const entries = [...xml.matchAll(/<(?:item|entry)[^>]*>([\s\S]*?)<\/(?:item|entry)>/gi)];
  for (const entry of entries.slice(0, 15)) {
    const block = entry[1];
    const get = (tag) => {
      const m = block.match(new RegExp(`<${tag}[^>]*>(?:<!\\[CDATA\\[)?([\\s\\S]*?)(?:\\]\\]>)?<\\/${tag}>`, "i"));
      return m ? m[1].replace(/<[^>]+>/g, "").trim() : "";
    };
    const link = block.match(/<link[^>]*href="([^"]+)"/i)?.[1] ||
                 block.match(/<link[^>]*>([^<]+)<\/link>/i)?.[1] || "";
    const title = get("title");
    const description = get("description") || get("summary") || get("content");
    const pubDate = get("pubDate") || get("published") || get("updated");
    if (!title || title.length < 10) continue;
    items.push({
      title: title.slice(0, 200),
      description: description.slice(0, 400),
      url: link.trim(),
      source,
      dot,
      published: pubDate ? new Date(pubDate).getTime() : Date.now(),
      image: null,
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

// ── Gemini: select top 8 stories and generate 4-bullet summaries ──────────────
async function geminiSelectAndSummarise(items, apiKey) {
  if (!items.length) return [];

  const list = items
    .slice(0, 40)
    .map((it, i) => `[${i}] SOURCE: ${it.source}\nTITLE: ${it.title}\nEXCERPT: ${it.description.slice(0, 200)}`)
    .join("\n\n");

  const prompt = `You are the editor of QuantumRx, a serious tech intelligence publication. From the stories below, select the 8 most significant for a technically literate audience. Prioritise genuine news impact, policy implications, infrastructure shifts, and major company moves. Avoid opinion pieces, listicles, and consumer how-to content.

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
          maxOutputTokens: 3000,
          thinkingConfig: { thinkingBudget: 0 },
        },
      }),
      signal: AbortSignal.timeout(30000),
    });
    const data = await res.json();
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text || "[]";
    const picks = JSON.parse(extractJSON(text));

    return picks
      .filter((p) => items[p.index] && Array.isArray(p.bullets) && p.bullets.length)
      .map((p) => ({
        ...items[p.index],
        bullets: p.bullets.slice(0, 4),
      }))
      .slice(0, 8);
  } catch {
    return items.slice(0, 8).map((it) => ({
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

  // 4. Gemini select + summarise
  const stories = await geminiSelectAndSummarise(sorted, apiKey);

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
    },
  });
}
