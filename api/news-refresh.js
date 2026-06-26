// /api/news-refresh.js
// QuantumRx Signals — daily refresh engine.
// Fetches open RSS feeds, filters to the QRx editorial lens, summarises via Gemini
// in six editorial passes, and writes six cache keys to Vercel KV.
// Protected by a shared cron secret and logged through Q-Sentinel.

import { kv } from "@vercel/kv";
import { logRequest, blockThreat } from "./_lib/sentinel.js";

// ---------------------------------------------------------------------------
// SOURCE LISTS  (all open / non-paywalled)
// ---------------------------------------------------------------------------
const TEXT_FEEDS = [
  { name: "Ars Technica", url: "https://feeds.arstechnica.com/arstechnica/technology-lab" },
  { name: "The Register", url: "https://www.theregister.com/headlines.atom" },
  { name: "VentureBeat AI", url: "https://venturebeat.com/category/ai/feed/" },
  { name: "TechCrunch AI", url: "https://techcrunch.com/category/artificial-intelligence/feed/" },
  { name: "SiliconANGLE", url: "https://siliconangle.com/feed/" },
  { name: "The Next Platform", url: "https://www.nextplatform.com/feed/" },
  { name: "Hacker News", url: "https://news.ycombinator.com/rss" },
  { name: "IEEE Spectrum", url: "https://spectrum.ieee.org/feeds/feed.rss" },
  { name: "The Gradient", url: "https://thegradient.pub/rss/" },
  { name: "Import AI", url: "https://importai.substack.com/feed" },
];

const SPACE_FEEDS = [
  { name: "NASA", url: "https://www.nasa.gov/rss/dyn/breaking_news.rss" },
  { name: "SpaceNews", url: "https://spacenews.com/feed/" },
  { name: "NASASpaceflight", url: "https://www.nasaspaceflight.com/feed/" },
  { name: "The Planetary Society", url: "https://www.planetary.org/feed/articles.rss" },
  { name: "Space.com", url: "https://www.space.com/feeds/all" },
];

const VIDEO_FEEDS = [
  { name: "Lex Fridman", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCSHZKyawb77ixDdsGog4iWA" },
  { name: "Two Minute Papers", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCbfYPyITQ-7l4upoX8nvctg" },
  { name: "AI Explained", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCNJ1Ymd5yFuUPtn21xtRbbw" },
  { name: "Google DeepMind", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCP7jMXSY2xbc3KCAE0MHQ-A" },
];

const SIGNAL_TERMS = [
  "ai", "artificial intelligence", "llm", "model", "inference", "agent", "agentic",
  "foundation model", "edge", "compute", "gpu", "chip", "semiconductor", "silicon",
  "data center", "datacenter", "cloud", "satellite", "satcom", "connectivity",
  "5g", "6g", "network", "quantum", "robot", "autonomous", "neural", "training",
  "open source", "open-source", "nvidia", "openai", "anthropic", "google", "mistral",
];

// ---------------------------------------------------------------------------
// RSS / ATOM PARSING
// ---------------------------------------------------------------------------
function decode(s = "") {
  return s
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&#x27;/g, "'")
    .replace(/&nbsp;/g, " ").replace(/<[^>]+>/g, "").trim();
}

function pick(block, tag) {
  const m = block.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`, "i"));
  return m ? m[1] : "";
}

function pickAttr(block, tag, attr) {
  const m = block.match(new RegExp(`<${tag}[^>]*\\b${attr}=["']([^"']+)["']`, "i"));
  return m ? m[1] : "";
}

function findImage(block) {
  return (
    pickAttr(block, "media:thumbnail", "url") ||
    pickAttr(block, "media:content", "url") ||
    pickAttr(block, "enclosure", "url") ||
    (block.match(/<img[^>]+src=["']([^"']+)["']/i)?.[1]) ||
    ""
  );
}

function parseFeed(xml, sourceName) {
  const items = [];
  const blocks = xml.match(/<item[\s\S]*?<\/item>/gi) || xml.match(/<entry[\s\S]*?<\/entry>/gi) || [];
  for (const b of blocks) {
    const title = decode(pick(b, "title"));
    let link = decode(pick(b, "link")) || pickAttr(b, "link", "href");
    const desc = decode(pick(b, "description") || pick(b, "summary") || pick(b, "content"));
    const pub = decode(pick(b, "pubDate") || pick(b, "published") || pick(b, "updated"));
    if (!title || !link) continue;
    items.push({
      title,
      link,
      description: desc.slice(0, 600),
      source: sourceName,
      image: sanitiseImageUrl(findImage(b)),
      published: pub ? new Date(pub).getTime() || Date.now() : Date.now(),
    });
  }
  return items;
}

async function fetchFeed(feed) {
  try {
    const res = await fetch(feed.url, {
      headers: { "User-Agent": "QuantumRx-Signals/1.0 (+https://quantumrx.eu)" },
      signal: AbortSignal.timeout(12000),
    });
    if (!res.ok) return [];
    const xml = await res.text();
    return parseFeed(xml, feed.name);
  } catch {
    return [];
  }
}

async function fetchAll(feeds) {
  const results = await Promise.allSettled(feeds.map(fetchFeed));
  return results.flatMap((r) => (r.status === "fulfilled" ? r.value : []));
}

// ---------------------------------------------------------------------------
// SECURITY — URL validation and output sanitisation
// ---------------------------------------------------------------------------
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
  } catch {
    return false;
  }
}

function sanitiseImageUrl(url) {
  if (!url) return "";
  try {
    const u = new URL(url);
    return u.protocol === "https:" || u.protocol === "http:" ? url : "";
  } catch {
    return "";
  }
}

function stripHtml(text) {
  return (text || "").replace(/<[^>]+>/g, "").replace(/&[a-z]+;/gi, " ").trim();
}

// ---------------------------------------------------------------------------
// ENRICH — fetch og:image and og:description from article pages
// ---------------------------------------------------------------------------
async function fetchOgData(url) {
  if (!isSafeUrl(url)) return {};
  try {
    const res = await fetch(url, {
      headers: { "User-Agent": "QuantumRx-Signals/1.0 (+https://quantumrx.eu)" },
      signal: AbortSignal.timeout(5000),
      redirect: "follow",
    });
    if (!res.ok) return {};
    const html = await res.text();
    const ogImg = html.match(/<meta[^>]*property=["']og:image["'][^>]*content=["']([^"']+)["']/i)?.[1]
      || html.match(/<meta[^>]*content=["']([^"']+)["'][^>]*property=["']og:image["']/i)?.[1]
      || "";
    const ogDesc = html.match(/<meta[^>]*property=["']og:description["'][^>]*content=["']([^"']+)["']/i)?.[1]
      || html.match(/<meta[^>]*content=["']([^"']+)["'][^>]*property=["']og:description["']/i)?.[1]
      || html.match(/<meta[^>]*name=["']description["'][^>]*content=["']([^"']+)["']/i)?.[1]
      || "";
    return {
      image: sanitiseImageUrl(ogImg.replace(/&amp;/g, "&")),
      description: ogDesc.replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&#39;/g, "'").slice(0, 600),
    };
  } catch {
    return {};
  }
}

async function enrichItems(items) {
  const needsEnrich = items.filter(
    (it) => !it.image || it.description.length < 30
  );
  if (!needsEnrich.length) return items;
  const batch = needsEnrich.slice(0, 20);
  const results = await Promise.allSettled(
    batch.map((it) => fetchOgData(it.link))
  );
  results.forEach((r, i) => {
    if (r.status !== "fulfilled" || !r.value) return;
    const og = r.value;
    const item = batch[i];
    if (!item.image && og.image) item.image = og.image;
    if (item.description.length < 30 && og.description) item.description = og.description;
  });
  return items;
}

function signalMatch(item) {
  const hay = `${item.title} ${item.description}`.toLowerCase();
  return SIGNAL_TERMS.some((t) => hay.includes(t));
}

function dedupe(items) {
  const seen = new Set();
  return items.filter((i) => {
    const key = i.link.split("?")[0];
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function freshSort(items) {
  return [...items].sort((a, b) => b.published - a.published);
}

// ---------------------------------------------------------------------------
// GEMINI
// ---------------------------------------------------------------------------
const GEMINI_URL =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent";

const VOICE = `You are the editor of QuantumRx Signals, a publication covering AI infrastructure, edge compute, connectivity, satellite systems, and emerging technology. Your readers are technical: engineers, founders, and operators. Write summaries that are direct and concrete. No hype, no filler, no adjectives like "revolutionary" or "groundbreaking". State what happened and why it matters to someone building in this space. Two sentences maximum. IMPORTANT: If the excerpt is missing, says "Comments", or is unhelpful, you MUST still write a proper two-sentence summary based on the headline alone. Never return "Comments" or a single word as a summary.`;

const CATEGORY_PROMPTS = {
  hot: `Select the ${"${N}"} stories most likely to still matter in six months. Prioritise structural shifts in AI infrastructure, compute, and connectivity over daily news-cycle noise.`,
  all: `Select the ${"${N}"} strongest stories across AI infrastructure, compute, connectivity, and emerging tech. Aim for breadth across topics.`,
  deeptech: `Select only stories about semiconductors, chips, quantum, edge compute, data centers, or physical-layer connectivity. Choose up to ${"${N}"}. If fewer than ${"${N}"} qualify, return fewer.`,
  aimoves: `Select only stories about AI model releases, AI company funding, acquisitions, or founder and lab activity. Choose up to ${"${N}"}.`,
};

function buildList(items) {
  const junk = ["comments", "comment", ""];
  return items
    .map((it, i) => {
      const desc = (it.description || "").trim();
      const isJunk = desc.length < 30 || junk.includes(desc.toLowerCase());
      const excerpt = isJunk
        ? "(No excerpt available — write the summary from the headline only)"
        : desc.slice(0, 280);
      return `[${i}] SOURCE: ${it.source}\nHEADLINE: ${it.title}\nEXCERPT: ${excerpt}`;
    })
    .join("\n\n");
}

function cleanSummaries(items) {
  const junk = ["comments", "comment", ""];
  return items.map((it) => {
    let s = stripHtml(it.summary || "").trim();
    s = s.replace(/https?:\/\/\S+/g, "").trim();
    if (junk.includes(s.toLowerCase()) || s.length < 10) {
      s = it.title;
    }
    it.summary = s;
    return it;
  });
}

function extractJSON(text) {
  const m = text.match(/\[[\s\S]*\]/);
  return m ? m[0] : "[]";
}

async function geminiSelect(items, categoryPrompt, n, apiKey) {
  if (!items.length) return [];
  const prompt = `${VOICE}

From the article list below, ${categoryPrompt.replace(/\$\{N\}/g, n)}

Return ONLY a JSON array, no markdown, no preamble. Each element:
{"index": <number from list>, "summary": "<two-sentence QRx summary>"}

ARTICLE LIST:
${buildList(items)}`;

  try {
    const res = await fetch(`${GEMINI_URL}?key=${apiKey}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.4,
          maxOutputTokens: 1400,
          thinkingConfig: { thinkingBudget: 0 },
        },
      }),
      signal: AbortSignal.timeout(30000),
    });
    const data = await res.json();
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text || "[]";
    const clean = extractJSON(text);
    const picks = JSON.parse(clean);
    if (!picks.length) throw new Error("empty");
    return picks
      .filter((p) => items[p.index])
      .map((p) => ({ ...items[p.index], summary: p.summary }))
      .slice(0, n);
  } catch {
    return items.slice(0, n).map((it) => ({
      ...it,
      summary: it.description && it.description.length > 30 ? it.description.slice(0, 180) : it.title,
    }));
  }
}

async function summariseVideos(items, n, apiKey) {
  const top = freshSort(items).slice(0, n);
  if (!top.length) return [];
  const prompt = `${VOICE}

For each video below, write a single sentence describing what it covers, for a technical reader deciding whether to watch. Return ONLY a JSON array: [{"index": <n>, "summary": "<one sentence>"}]

VIDEOS:
${buildList(top)}`;
  try {
    const res = await fetch(`${GEMINI_URL}?key=${apiKey}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.4,
          maxOutputTokens: 800,
          thinkingConfig: { thinkingBudget: 0 },
        },
      }),
      signal: AbortSignal.timeout(30000),
    });
    const data = await res.json();
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text || "[]";
    const clean = extractJSON(text);
    const picks = JSON.parse(clean);
    if (!picks.length) throw new Error("empty");
    const byIndex = Object.fromEntries(picks.map((p) => [p.index, p.summary]));
    return top.map((it, i) => ({ ...it, summary: byIndex[i] || "" }));
  } catch {
    return top.map((it) => ({ ...it, summary: "" }));
  }
}

function videoThumb(item) {
  if (item.image && (item.image.includes('ytimg.com') || item.image.includes('.jpg') || item.image.includes('.png'))) {
    return item.image;
  }
  const id = item.link && (
    item.link.match(/[?&]v=([\w-]+)/)?.[1] ||
    item.link.match(/youtu\.be\/([\w-]+)/)?.[1]
  );
  return id ? `https://i.ytimg.com/vi/${id}/hqdefault.jpg` : (item.image || '');
}

// ---------------------------------------------------------------------------
// HANDLER
// ---------------------------------------------------------------------------
export default async function handler(req, res) {
  const provided = req.headers["x-cron-secret"];
  const expected = process.env.CRON_SECRET;

  await logRequest(req, "news-refresh");

  if (!expected || provided !== expected) {
    await blockThreat(req, "news-refresh", "missing-or-invalid-cron-secret");
    return res.status(401).json({ error: "Unauthorized" });
  }

  const apiKey = process.env.GEMINI_API_KEY_Forge;
  if (!apiKey) return res.status(500).json({ error: "Missing GEMINI_API_KEY_Forge" });

  const startedAt = Date.now();

  // 1. Fetch + filter
  const rawText = await fetchAll(TEXT_FEEDS);
  const textPool = freshSort(dedupe(rawText.filter(signalMatch))).slice(0, 60);

  const rawSpace = await fetchAll(SPACE_FEEDS);
  const spacePool = freshSort(dedupe(rawSpace)).slice(0, 30);

  const rawVideo = await fetchAll(VIDEO_FEEDS);
  const videoPool = dedupe(rawVideo);

  // 2. Enrich missing images/descriptions
  await Promise.all([enrichItems(textPool), enrichItems(spacePool)]);

  // 3. Editorial passes
  const [hot, all, deeptech, aimoves] = await Promise.all([
    geminiSelect(textPool, CATEGORY_PROMPTS.hot, 8, apiKey),
    geminiSelect(textPool, CATEGORY_PROMPTS.all, 12, apiKey),
    geminiSelect(textPool, CATEGORY_PROMPTS.deeptech, 8, apiKey),
    geminiSelect(textPool, CATEGORY_PROMPTS.aimoves, 8, apiKey),
  ]);
  const space = await geminiSelect(spacePool, CATEGORY_PROMPTS.all, 6, apiKey);
  const videosRaw = await summariseVideos(videoPool, 4, apiKey);
  const videos = videosRaw.map((v) => ({ ...v, image: videoThumb(v) }));

  // 4. Clean junk summaries
  [hot, all, deeptech, aimoves, space].forEach(cleanSummaries);

  // 5. Write cache
  const stamp = (arr) => ({ updated: startedAt, items: arr });
  const TTL = 60 * 60 * 25;
  await Promise.all([
    kv.set("qrx_feed_hot", stamp(hot), { ex: TTL }),
    kv.set("qrx_feed_all", stamp(all), { ex: TTL }),
    kv.set("qrx_feed_deeptech", stamp(deeptech), { ex: TTL }),
    kv.set("qrx_feed_aimoves", stamp(aimoves), { ex: TTL }),
    kv.set("qrx_feed_space", stamp(space), { ex: TTL }),
    kv.set("qrx_feed_video", stamp(videos), { ex: TTL }),
  ]);

  return res.status(200).json({
    ok: true,
    elapsedMs: Date.now() - startedAt,
    counts: {
      textPool: textPool.length,
      hot: hot.length,
      all: all.length,
      deeptech: deeptech.length,
      aimoves: aimoves.length,
      space: space.length,
      video: videos.length,
    },
  });
}
