// api/draw-refresh.js
// The Draw — daily world news briefing
// 10 outlets x 3 stories for Main Headlines
// 10 outlets x 3 stories for Financial News
// Writes to KV as qrx_draw_main and qrx_draw_finance with 25h TTL

import { kv } from "@vercel/kv";
import { logRequest, blockThreat } from "./_lib/sentinel.js";

const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent";
const UA = "QuantumRx-TheDraw/1.0 (+https://quantumrx.eu)";
const TTL = 60 * 60 * 25;

const MAIN_FEEDS = [
  { url: "http://feeds.bbci.co.uk/news/rss.xml",                          source: "BBC News",               dot: "#cc0000" },
  { url: "https://feeds.reuters.com/reuters/topNews",                      source: "Reuters",                dot: "#ff6600" },
  { url: "https://www.theguardian.com/world/rss",                         source: "The Guardian",           dot: "#005689" },
  { url: "https://rss.ap.org/apf-topnews",                                source: "AP News",                dot: "#333333" },
  { url: "https://www.aljazeera.com/xml/rss/all.xml",                     source: "Al Jazeera",             dot: "#c8a000" },
  { url: "https://rss.dw.com/rdf/rss-en-all",                             source: "Deutsche Welle",         dot: "#005f9e" },
  { url: "https://www.scmp.com/rss/91/feed",                              source: "South China Morning Post",dot: "#d32f2f" },
  { url: "https://timesofindia.indiatimes.com/rssfeeds/296589292.cms",    source: "Times of India",         dot: "#e57c00" },
  { url: "https://www.france24.com/en/rss",                               source: "France 24",              dot: "#003f87" },
  { url: "https://allafrica.com/tools/headlines/rdf/latest/headlines.rdf",source: "AllAfrica",              dot: "#2e7d32" },
  { url: "https://feeds.npr.org/1001/rss.xml",                             source: "NPR News",               dot: "#005288" },
  { url: "https://api.axios.com/feed/",                                    source: "Axios",                  dot: "#ff6d00" },
  { url: "http://rss.cnn.com/rss/edition.rss",                            source: "CNN",                    dot: "#cc0000" },
  { url: "https://feeds.nbcnews.com/nbcnews/public/news",                 source: "NBC News",               dot: "#0b3a8e" },
  { url: "https://www.dailymail.co.uk/articles.rss",                      source: "Daily Mail",             dot: "#004db3" },
  { url: "https://abcnews.go.com/abcnews/topstories",                     source: "ABC News",               dot: "#004db3" },
  { url: "https://www.cbsnews.com/latest/rss/main",                       source: "CBS News",               dot: "#304ffe" },
  { url: "https://moxie.foxnews.com/google-publisher/latest.xml",         source: "Fox News",               dot: "#003366" },
];

const FINANCE_FEEDS = [
  { url: "https://feeds.reuters.com/reuters/businessNews",                 source: "Reuters Business",       dot: "#ff6600" },
  { url: "https://www.ft.com/rss/home",                                   source: "Financial Times",        dot: "#f7c430" },
  { url: "https://www.cnbc.com/id/100003114/device/rss/rss.html",         source: "CNBC",                   dot: "#005594" },
  { url: "https://feeds.marketwatch.com/marketwatch/topstories/",         source: "MarketWatch",            dot: "#0274b5" },
  { url: "https://www.forbes.com/real-time/feed2/",                       source: "Forbes",                 dot: "#990000" },
  { url: "https://www.economist.com/latest/rss.xml",                      source: "The Economist",          dot: "#e3120b" },
  { url: "https://www.wsj.com/xml/rss/3_7085.xml",                        source: "Wall Street Journal",    dot: "#004276" },
  { url: "https://seekingalpha.com/market_currents.xml",                  source: "Seeking Alpha",          dot: "#1a8754" },
  { url: "https://www.investopedia.com/feedbuilder/feed/getfeed/?feedName=investopedia-term-of-the-day", source: "Investopedia", dot: "#00529b" },
  { url: "https://feeds.bloomberg.com/markets/news.rss",                  source: "Bloomberg",              dot: "#1a1a1a" },
  { url: "https://www.businessinsider.com/rss",                           source: "Business Insider",        dot: "#1a1a1a" },
  { url: "https://fortune.com/feed/",                                     source: "Fortune",                 dot: "#d4a017" },
];

// ── Helpers ───────────────────────────────────────────────────────────────────
function isSafeUrl(url) {
  try {
    const u = new URL(url);
    if (!["https:", "http:"].includes(u.protocol)) return false;
    const h = u.hostname;
    if (["localhost", "0.0.0.0"].includes(h)) return false;
    if (h.startsWith("127.") || h.startsWith("192.168.") || h === "169.254.169.254") return false;
    return true;
  } catch { return false; }
}

function sanitiseUrl(url) {
  if (!url) return "";
  try { const u = new URL(url); return ["https:", "http:"].includes(u.protocol) ? url : ""; } catch { return ""; }
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
  return pickAttr(block, "media:thumbnail", "url")
    || pickAttr(block, "media:content", "url")
    || pickAttr(block, "enclosure", "url")
    || (block.match(/<img[^>]+src=["']([^"']+)["']/i) || [])[1]
    || "";
}

function extractJSON(text) {
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) return fence[1].trim();
  const bracket = text.match(/(\[[\s\S]*\])/);
  if (bracket) return bracket[1].trim();
  return text.trim();
}

// ── RSS fetch ─────────────────────────────────────────────────────────────────
function parseXML(xml, feed) {
  const items = [];
  const entries = [...xml.matchAll(/<(?:item|entry)[^>]*>([\s\S]*?)<\/(?:item|entry)>/gi)];
  for (const entry of entries.slice(0, 12)) {
    const block = entry[1];
    const title = decode(pickTag(block, "title"));
    const link = decode(pickTag(block, "link")) || pickAttr(block, "link", "href");
    const description = decode(pickTag(block, "description") || pickTag(block, "summary") || pickTag(block, "content"));
    const pubDate = decode(pickTag(block, "pubDate") || pickTag(block, "published") || pickTag(block, "updated"));
    if (!title || title.length < 8) continue;
    items.push({
      title: title.slice(0, 200),
      description: description.slice(0, 400),
      url: link.trim(),
      source: feed.source,
      dot: feed.dot,
      published: pubDate ? new Date(pubDate).getTime() : Date.now(),
      image: sanitiseUrl(findImage(block)),
    });
  }
  return items;
}

async function fetchFeed(feed) {
  try {
    const res = await fetch(feed.url, {
      headers: { "User-Agent": UA },
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) return [];
    return parseXML(await res.text(), feed);
  } catch { return []; }
}

// ── OG image fetch ────────────────────────────────────────────────────────────
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
    return sanitiseUrl(ogImg.replace(/&amp;/g, "&"));
  } catch { return ""; }
}

// ── Gemini selection ──────────────────────────────────────────────────────────
async function geminiSelectOutlet(items, source, tab, apiKey) {
  if (!items.length) return [];
  const pool = items.slice(0, 10);
  const list = pool.map((it, i) =>
    `[${i}] TITLE: ${it.title}\nEXCERPT: ${it.description.slice(0, 200)}`
  ).join("\n\n");

  const isFinance = tab === "finance";
  const criteria = isFinance
    ? "market-moving events, earnings results, central bank decisions, macro-economic trends, significant corporate moves. Avoid opinion, advertorial, or how-to content."
    : "genuine global news impact — policy decisions, conflict, climate, science breakthroughs, major political developments. Avoid opinion pieces, lifestyle, entertainment, and celebrity content.";

  const prompt = `You are a senior editor at a world news briefing. From these ${source} stories select the 3 most significant for a globally informed audience. Prioritise ${criteria}

For each story return exactly 3 bullet points:
1. What happened — the concrete fact in one sentence
2. Why it matters — the global significance in one sentence  
3. What to watch — one specific checkable signal

Return ONLY a JSON array, no markdown:
[{"index": <number>, "bullets": ["...", "...", "..."]}]

STORIES:
${list}`;

  try {
    const res = await fetch(`${GEMINI_URL}?key=${apiKey}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.3, maxOutputTokens: 1200, thinkingConfig: { thinkingBudget: 0 } },
      }),
      signal: AbortSignal.timeout(20000),
    });
    const data = await res.json();
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text || "[]";
    const picks = JSON.parse(extractJSON(text));
    return picks
      .filter(p => pool[p.index] && Array.isArray(p.bullets) && p.bullets.length)
      .map(p => ({ ...pool[p.index], bullets: p.bullets.slice(0, 3) }))
      .slice(0, 3);
  } catch {
    return pool.slice(0, 3).map(it => ({ ...it, bullets: [it.description.slice(0, 120) || it.title] }));
  }
}

// ── Handler ───────────────────────────────────────────────────────────────────
export default async function handler(req, res) {
  await logRequest(req, "draw-refresh");

  const provided = req.headers["x-cron-secret"];
  const expected = process.env.CRON_SECRET;
  if (!expected || provided !== expected) {
    await blockThreat(req, "draw-refresh", "missing-or-invalid-cron-secret");
    return res.status(401).json({ error: "Unauthorized" });
  }

  const apiKey = process.env.GEMINI_API_KEY_Forge;
  if (!apiKey) return res.status(500).json({ error: "Missing API key" });

  const startedAt = new Date().toISOString();
  const t0 = Date.now();

  // Fetch all feeds in parallel
  const [mainResults, financeResults] = await Promise.all([
    Promise.all(MAIN_FEEDS.map(fetchFeed)),
    Promise.all(FINANCE_FEEDS.map(fetchFeed)),
  ]);

  // Enrich OG images for stories missing them
  const enrichImages = async (feedItems) => {
    const hotlinkBlocked = ["theguardian.com", "reuters.com", "bbc.co.uk", "bbc.com", "ft.com", "economist.com"];
    const needsImg = feedItems.filter(it => {
      if (!it.image) return true;
      try { return hotlinkBlocked.some(d => new URL(it.image).hostname.includes(d)); } catch { return false; }
    }).slice(0, 15);
    if (needsImg.length) {
      const results = await Promise.allSettled(needsImg.map(it => fetchOgImage(it.url)));
      results.forEach((r, i) => { if (r.status === "fulfilled" && r.value) needsImg[i].image = r.value; });
    }
    return feedItems;
  };

  // Select 3 stories per outlet for each tab
  const [mainStories, financeStories] = await Promise.all([
    Promise.all(mainResults.map((items, i) =>
      enrichImages(items).then(enriched =>
        geminiSelectOutlet(enriched, MAIN_FEEDS[i].source, "main", apiKey)
      )
    )),
    Promise.all(financeResults.map((items, i) =>
      enrichImages(items).then(enriched =>
        geminiSelectOutlet(enriched, FINANCE_FEEDS[i].source, "finance", apiKey)
      )
    )),
  ]);

  const main = mainStories.flat();
  const finance = financeStories.flat();

  await Promise.all([
    kv.set("qrx_draw_main",    { updated: startedAt, items: main    }, { ex: TTL }),
    kv.set("qrx_draw_finance", { updated: startedAt, items: finance }, { ex: TTL }),
  ]);

  return res.status(200).json({
    ok: true,
    elapsedMs: Date.now() - t0,
    counts: { main: main.length, finance: finance.length },
  });
}
