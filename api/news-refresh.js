// /api/news-refresh.js
// QuantumRx Signals — daily refresh engine v5
// Tabs: What's Hot, AI Moves, Crypto, Policy, Energy, Space, Robotics, Semis, Quantum, Social, Search
// Watch: 4 videos, one per vertical group, diversified

import { kv } from "@vercel/kv";
import { logRequest, blockThreat } from "./_lib/sentinel.js";

// ---------------------------------------------------------------------------
// SOURCE LISTS
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

const CRYPTO_FEEDS = [
  { name: "The Block", url: "https://www.theblock.co/rss/all" },
  { name: "Blockworks", url: "https://blockworks.co/feed" },
  { name: "Protos", url: "https://protos.com/feed/" },
  { name: "Decrypt", url: "https://decrypt.co/feed" },
  { name: "Ethereum Foundation", url: "https://blog.ethereum.org/feed.xml" },
];

const POLICY_FEEDS = [
  { name: "Politico Tech", url: "https://www.politico.com/rss/technology.xml" },
  { name: "The Register Policy", url: "https://www.theregister.com/policy/headlines.atom" },
  { name: "EFF", url: "https://www.eff.org/rss/updates.xml" },
  { name: "NIST", url: "https://www.nist.gov/news-events/news/rss.xml" },
  { name: "EU Commission Digital", url: "https://digital-strategy.ec.europa.eu/en/rss.xml" },
];

const ENERGY_FEEDS = [
  { name: "Canary Media", url: "https://www.canarymedia.com/feed" },
  { name: "Energy Monitor", url: "https://www.energymonitor.ai/feed/" },
  { name: "Electrek", url: "https://electrek.co/feed/" },
  { name: "Power Magazine", url: "https://www.powermag.com/feed/" },
  { name: "IEA", url: "https://www.iea.org/news/rss" },
];

const SPACE_FEEDS = [
  { name: "NASA", url: "https://www.nasa.gov/rss/dyn/breaking_news.rss" },
  { name: "SpaceNews", url: "https://spacenews.com/feed/" },
  { name: "NASASpaceflight", url: "https://www.nasaspaceflight.com/feed/" },
  { name: "Space.com", url: "https://www.space.com/feeds/all" },
  { name: "Payload Space", url: "https://payloadspace.com/feed/" },
  { name: "Spaceflight Now", url: "https://spaceflightnow.com/feed/" },
  { name: "ESA News", url: "https://www.esa.int/rssfeed.xml" },
  { name: "Parabolic Arc", url: "https://www.parabolicarc.com/feed/" },
  { name: "Ars Technica Space", url: "https://feeds.arstechnica.com/arstechnica/space" },
  { name: "The Orbital Index", url: "https://orbitalindex.substack.com/feed" },
];

const ROBOTICS_FEEDS = [
  { name: "The Robot Report", url: "https://www.therobotreport.com/feed/" },
  { name: "IEEE Spectrum Robotics", url: "https://spectrum.ieee.org/feeds/topic/robotics.rss" },
  { name: "TechCrunch Robotics", url: "https://techcrunch.com/category/robotics/feed/" },
  { name: "Robotics Business Review", url: "https://www.roboticsbusinessreview.com/feed/" },
  { name: "MIT News Robotics", url: "https://news.mit.edu/rss/topic/robots" },
];

const SEMIS_FEEDS = [
  { name: "SemiAnalysis", url: "https://semianalysis.com/feed" },
  { name: "EE Times", url: "https://www.eetimes.com/feed/" },
  { name: "Tom's Hardware", url: "https://www.tomshardware.com/feeds/all" },
  { name: "AnySilicon", url: "https://anysilicon.com/feed/" },
  { name: "Semiconductor Engineering", url: "https://semiengineering.com/feed/" },
];

const QUANTUM_FEEDS = [
  { name: "Quantum Computing Report", url: "https://quantumcomputingreport.com/feed/" },
  { name: "The Quantum Insider", url: "https://thequantuminsider.com/feed/" },
  { name: "arXiv Quantum", url: "https://export.arxiv.org/rss/quant-ph" },
  { name: "IBM Research Quantum", url: "https://research.ibm.com/blog/rss" },
  { name: "Q2B Insider", url: "https://q2b.qcware.com/feed/" },
];

const SOCIAL_FEEDS = [
  { name: "Lobsters", url: "https://lobste.rs/rss" },
  { name: "Tildes", url: "https://tildes.net/~tech.rss" },
  { name: "IndieHackers", url: "https://www.indiehackers.com/feed.xml" },
  { name: "Changelog", url: "https://changelog.com/feed" },
  { name: "Hacker News Show", url: "https://news.ycombinator.com/showrss" },
  { name: "Dev.to", url: "https://dev.to/feed" },
  { name: "Product Hunt", url: "https://www.producthunt.com/feed" },
];

// VIDEO FEEDS — grouped by vertical, biased toward short-form channels
// One video selected per group, 4 total Watch cards
const VIDEO_GROUPS = [
  {
    vertical: "ai",
    feeds: [
      { name: "Fireship", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCsBjURrPoezykLs9EqgamOA" },
      { name: "Two Minute Papers", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCbfYPyITQ-7l4upoX8nvctg" },
      { name: "AI Explained", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCNJ1Ymd5yFuUPtn21xtRbbw" },
      { name: "Yannic Kilcher", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCZHmQk67mSJgfCCTn7xBfew" },
      { name: "Andrej Karpathy", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCXUPKJO5MZQMU11rgDXghSA" },
    ],
  },
  {
    vertical: "robotics",
    feeds: [
      { name: "Boston Dynamics", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC7vVhkEfw4nOGp8TyDk7RcQ" },
      { name: "Simone Giertz", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC3KEoMzNz8eYnwBC34RaKCQ" },
    ],
  },
  {
    vertical: "semis",
    feeds: [
      { name: "Asianometry", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC6gxBBmEOFPE3MpYs9aBstQ" },
      { name: "Branch Education", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCZFipeZtQM5CKUjx6grh54g" },
    ],
  },
  {
    vertical: "quantum",
    feeds: [
      { name: "IBM Technology", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCKWaEZ-_VweaEx1j62do_vQ" },
      { name: "Quanta Magazine", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCTpmmkp1E4nmZqWPS-Sd5eA" },
    ],
  },
  {
    vertical: "space",
    feeds: [
      { name: "Scott Manley", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCxzC4EngIsMrPmbm6Nxvb-A" },
      { name: "Real Engineering", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCR1IuLEqb6UEA_zQ81kwXfg" },
    ],
  },
];

// ---------------------------------------------------------------------------
// KEYWORD GATES
// ---------------------------------------------------------------------------
const SIGNAL_TERMS = [
  "ai", "artificial intelligence", "llm", "model", "inference", "agent", "agentic",
  "foundation model", "edge", "compute", "gpu", "chip", "semiconductor", "silicon",
  "data center", "datacenter", "cloud", "satellite", "satcom", "connectivity",
  "5g", "6g", "network", "quantum", "robot", "autonomous", "neural", "training",
  "open source", "open-source", "nvidia", "openai", "anthropic", "google", "mistral",
];

const CRYPTO_TERMS = [
  "protocol", "layer 2", "l2", "validator", "consensus", "zk", "rollup",
  "defi", "smart contract", "on-chain", "blockchain infrastructure", "ethereum",
  "staking", "proof of stake", "evm", "web3 infrastructure", "cross-chain",
  "sequencer", "bridge", "liquidity", "dao", "merkle",
];

const POLICY_TERMS = [
  "regulation", "legislation", "ai act", "executive order", "fcc", "spectrum",
  "data protection", "gdpr", "antitrust", "policy", "governance", "compliance",
  "copyright", "privacy", "digital markets", "ofcom", "ftc", "doj",
  "european commission", "parliament", "congress", "senate", "cybersecurity",
  "national security", "export control",
];

const ENERGY_TERMS = [
  "grid", "power", "nuclear", "data center energy", "renewable", "electricity",
  "gigawatt", "energy infrastructure", "hydrogen", "battery storage", "transmission",
  "solar", "wind", "capacity", "megawatt", "generation", "ferc", "utility",
  "energy consumption", "cooling", "ppa", "carbon", "emissions",
];

const ROBOTICS_TERMS = [
  "robot", "robotics", "autonomous", "humanoid", "bipedal", "manipulation",
  "actuator", "end effector", "ros", "perception", "lidar", "embodied",
  "warehouse automation", "boston dynamics", "figure", "1x", "agility",
  "physical ai", "dexterous", "locomotion", "exoskeleton", "drone",
  "uav", "mobile robot", "arm", "gripper", "servo",
];

const SEMIS_TERMS = [
  "semiconductor", "chip", "wafer", "fab", "foundry", "tsmc", "samsung foundry",
  "intel foundry", "nvidia", "amd", "arm", "risc-v", "node", "nm", "nanometer",
  "lithography", "asml", "euv", "packaging", "hbm", "memory", "nand", "dram",
  "silicon", "soc", "gpu", "npu", "accelerator", "export control", "chips act",
  "supply chain", "yield", "tape out", "process node",
];

const QUANTUM_TERMS = [
  "quantum", "qubit", "quantum computing", "quantum error correction",
  "quantum advantage", "quantum supremacy", "superposition", "entanglement",
  "decoherence", "quantum hardware", "photonic", "trapped ion", "superconducting",
  "quantum algorithm", "ibm quantum", "google quantum", "ionq", "rigetti",
  "quantum network", "quantum communication", "qkd", "quantum memory",
  "quantum sensor", "quantum annealing",
];

const SOCIAL_TERMS = [
  "ai", "tech", "software", "startup", "product", "developer", "code", "programming",
  "machine learning", "model", "data", "cloud", "api", "open source", "github",
  "launch", "funding", "research", "algorithm", "infrastructure", "security",
  "privacy", "tool", "framework", "show hn", "ask hn", "built", "released",
];

// ---------------------------------------------------------------------------
// SECURITY
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
  } catch { return false; }
}

function sanitiseImageUrl(url) {
  if (!url) return "";
  try {
    const u = new URL(url);
    return u.protocol === "https:" || u.protocol === "http:" ? url : "";
  } catch { return ""; }
}

function stripHtml(text) {
  return (text || "").replace(/<[^>]+>/g, "").replace(/&[a-z]+;/gi, " ").trim();
}

// ---------------------------------------------------------------------------
// RSS PARSING
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
    const ua = feed.reddit
      ? "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      : "QuantumRx-Signals/1.0 (+https://quantumrx.eu)";
    const res = await fetch(feed.url, {
      headers: { "User-Agent": ua },
      signal: AbortSignal.timeout(12000),
    });
    if (!res.ok) return [];
    const xml = await res.text();
    return parseFeed(xml, feed.name);
  } catch { return []; }
}

async function fetchAll(feeds) {
  const results = await Promise.allSettled(feeds.map(fetchFeed));
  return results.flatMap((r) => (r.status === "fulfilled" ? r.value : []));
}

// ---------------------------------------------------------------------------
// ENRICH
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
  } catch { return {}; }
}

async function enrichItems(items) {
  const needsEnrich = items.filter((it) => !it.image || it.description.length < 30);
  if (!needsEnrich.length) return items;
  const batch = needsEnrich.slice(0, 20);
  const results = await Promise.allSettled(batch.map((it) => fetchOgData(it.link)));
  results.forEach((r, i) => {
    if (r.status !== "fulfilled" || !r.value) return;
    const og = r.value;
    const item = batch[i];
    if (!item.image && og.image) item.image = og.image;
    if (item.description.length < 30 && og.description) item.description = og.description;
  });
  return items;
}

function termMatch(item, terms) {
  const hay = `${item.title} ${item.description}`.toLowerCase();
  return terms.some((t) => hay.includes(t));
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

const VOICE = `You are the editor of QuantumRx Signals, a publication covering AI infrastructure, edge compute, connectivity, satellite systems, energy infrastructure, crypto infrastructure, technology policy, space systems, robotics, semiconductors, quantum computing, and what the tech community is talking about. Your readers are technical: engineers, founders, and operators. Write summaries that are direct and concrete. No hype, no filler, no adjectives like "revolutionary" or "groundbreaking". State what happened and why it matters to someone building in this space. Two sentences maximum. IMPORTANT: If the excerpt is missing, says "Comments", or is unhelpful, you MUST still write a proper two-sentence summary based on the headline alone. Never return "Comments" or a single word as a summary.`;

const CATEGORY_PROMPTS = {
  hot: `Select the \${N} stories most likely to still matter in six months. Prioritise structural shifts in AI infrastructure, compute, and connectivity over daily news-cycle noise.`,
  aimoves: `Select only stories about AI model releases, AI company funding, acquisitions, or founder and lab activity. Choose up to \${N}.`,
  crypto: `Select only stories about blockchain and crypto infrastructure — protocols, layer 2 networks, validators, consensus mechanisms, zk proofs, DeFi rails, and on-chain systems. Exclude price speculation, market moves, and coin trading. Choose up to \${N}.`,
  policy: `Select only stories about technology regulation, legislation, and governance — AI regulation, data protection, spectrum policy, antitrust, export controls, and government technology policy in the US, EU, and UK. Choose up to \${N}.`,
  energy: `Select only stories about energy infrastructure relevant to technology — data center power consumption, grid capacity, nuclear power for compute, renewable energy projects at scale, battery storage, and electricity infrastructure. Choose up to \${N}.`,
  space: `Select the \${N} strongest stories about space systems, orbital infrastructure, satellite communications, launch vehicles, and commercial space. Prioritise commercial, connectivity, and engineering angles over general interest pieces.`,
  robotics: `Select only stories about robotics and autonomous systems — humanoid robots, industrial automation, warehouse robotics, drone systems, physical AI, and robotic hardware. Exclude pure software AI stories unless they directly concern robotic systems. Choose up to \${N}.`,
  semis: `Select only stories about semiconductors and chip infrastructure — chip design, fabrication, foundry capacity, packaging, memory, GPU and NPU architecture, export controls on chips, and the compute supply chain. Choose up to \${N}.`,
  quantum: `Select only stories about quantum computing and quantum technology — qubit advances, error correction, quantum hardware, quantum algorithms, quantum networking, and commercial quantum developments. Choose up to \${N}.`,
  social: `Select the \${N} stories that the tech community is most actively engaging with right now — tools people are genuinely building with, projects gaining real traction, debates engineers care about, and launches worth paying attention to. IMPORTANT: You MUST include at least one story from Lobsters, at least one from Hacker News Show, and at least one from Dev.to or IndieHackers. Avoid political drama. Choose stories with genuine signal for builders and founders.`,
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
    if (junk.includes(s.toLowerCase()) || s.length < 10) s = it.title;
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
    const picks = JSON.parse(extractJSON(text));
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

async function summariseVideos(items, apiKey) {
  if (!items.length) return [];
  const prompt = `${VOICE}

For each video below, write a single sentence describing what it covers, for a technical reader deciding whether to watch. Return ONLY a JSON array: [{"index": <n>, "summary": "<one sentence>"}]

VIDEOS:
${buildList(items)}`;
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
    const picks = JSON.parse(extractJSON(text));
    if (!picks.length) throw new Error("empty");
    const byIndex = Object.fromEntries(picks.map((p) => [p.index, p.summary]));
    return items.map((it, i) => ({ ...it, summary: byIndex[i] || "" }));
  } catch {
    return items.map((it) => ({ ...it, summary: "" }));
  }
}

function videoThumb(item) {
  if (item.image && (item.image.includes("ytimg.com") || item.image.includes(".jpg") || item.image.includes(".png"))) {
    return item.image;
  }
  const id = item.link && (
    item.link.match(/[?&]v=([\w-]+)/)?.[1] ||
    item.link.match(/youtu\.be\/([\w-]+)/)?.[1]
  );
  return id ? `https://i.ytimg.com/vi/${id}/hqdefault.jpg` : (item.image || "");
}

// Pick one video per vertical group, 4 total
// Each group fetches all its feeds, picks the most recent item
async function pickDiverseVideos(n) {
  const selected = [];
  for (const group of VIDEO_GROUPS) {
    if (selected.length >= n) break;
    const raw = await fetchAll(group.feeds);
    const items = freshSort(dedupe(raw));
    if (items.length > 0) {
      selected.push({ ...items[0], vertical: group.vertical });
    }
  }
  return selected;
}

function diversifySocial(selected, pool, n) {
  const groups = {
    lobsters: pool.filter(it => it.source.toLowerCase().includes('lobsters')),
    indiehackers: pool.filter(it => it.source.toLowerCase().includes('indiehackers')),
    hn: pool.filter(it => it.source.toLowerCase().includes('hacker news')),
    devto: pool.filter(it => it.source.toLowerCase().includes('dev.to')),
  };
  const result = [...selected];
  const resultLinks = new Set(result.map(it => it.link));
  Object.values(groups).forEach(function(items) {
    if (!items.length) return;
    const hasGroup = items.some(gi => resultLinks.has(gi.link));
    if (!hasGroup) {
      const candidate = items.find(it => !resultLinks.has(it.link));
      if (candidate) {
        candidate.summary = candidate.summary || candidate.description?.slice(0, 180) || candidate.title;
        result.push(candidate);
        resultLinks.add(candidate.link);
      }
    }
  });
  return result.slice(0, n + 4);
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

  // 1. Fetch all pools in parallel
  const [rawText, rawCrypto, rawPolicy, rawEnergy, rawSpace, rawRobotics, rawSemis, rawQuantum, rawSocial] = await Promise.all([
    fetchAll(TEXT_FEEDS),
    fetchAll(CRYPTO_FEEDS),
    fetchAll(POLICY_FEEDS),
    fetchAll(ENERGY_FEEDS),
    fetchAll(SPACE_FEEDS),
    fetchAll(ROBOTICS_FEEDS),
    fetchAll(SEMIS_FEEDS),
    fetchAll(QUANTUM_FEEDS),
    fetchAll(SOCIAL_FEEDS),
  ]);

  // 2. Filter and dedupe
  const textPool     = freshSort(dedupe(rawText.filter((it) => termMatch(it, SIGNAL_TERMS)))).slice(0, 60);
  const cryptoPool   = freshSort(dedupe(rawCrypto.filter((it) => termMatch(it, CRYPTO_TERMS)))).slice(0, 40);
  const policyPool   = freshSort(dedupe(rawPolicy.filter((it) => termMatch(it, POLICY_TERMS)))).slice(0, 40);
  const energyPool   = freshSort(dedupe(rawEnergy.filter((it) => termMatch(it, ENERGY_TERMS)))).slice(0, 40);
  const spacePool    = freshSort(dedupe(rawSpace)).slice(0, 40);
  const roboticsPool = freshSort(dedupe(rawRobotics.filter((it) => termMatch(it, ROBOTICS_TERMS)))).slice(0, 40);
  const semisPool    = freshSort(dedupe(rawSemis.filter((it) => termMatch(it, SEMIS_TERMS)))).slice(0, 40);
  const quantumPool  = freshSort(dedupe(rawQuantum.filter((it) => termMatch(it, QUANTUM_TERMS)))).slice(0, 40);
  const socialPool   = freshSort(dedupe(rawSocial.filter((it) => termMatch(it, SOCIAL_TERMS)))).slice(0, 50);

  // 3. Enrich missing images/descriptions
  await Promise.all([
    enrichItems(textPool),
    enrichItems(cryptoPool),
    enrichItems(policyPool),
    enrichItems(energyPool),
    enrichItems(spacePool),
    enrichItems(roboticsPool),
    enrichItems(semisPool),
    enrichItems(quantumPool),
    enrichItems(socialPool),
  ]);

  // 4. Gemini passes
  const [hot, aimoves] = await Promise.all([
    geminiSelect(textPool, CATEGORY_PROMPTS.hot, 8, apiKey),
    geminiSelect(textPool, CATEGORY_PROMPTS.aimoves, 8, apiKey),
  ]);
  const [crypto, policy, energy] = await Promise.all([
    geminiSelect(cryptoPool, CATEGORY_PROMPTS.crypto, 8, apiKey),
    geminiSelect(policyPool, CATEGORY_PROMPTS.policy, 8, apiKey),
    geminiSelect(energyPool, CATEGORY_PROMPTS.energy, 8, apiKey),
  ]);
  const [space, robotics, semis, quantum] = await Promise.all([
    geminiSelect(spacePool, CATEGORY_PROMPTS.space, 10, apiKey),
    geminiSelect(roboticsPool, CATEGORY_PROMPTS.robotics, 8, apiKey),
    geminiSelect(semisPool, CATEGORY_PROMPTS.semis, 8, apiKey),
    geminiSelect(quantumPool, CATEGORY_PROMPTS.quantum, 8, apiKey),
  ]);
  const [socialRaw] = await Promise.all([
    geminiSelect(socialPool, CATEGORY_PROMPTS.social, 8, apiKey),
  ]);
  const social = diversifySocial(socialRaw, socialPool, 8);

  // 5. Videos — one per vertical group, 4 total
  const rawVideos = await pickDiverseVideos(4);
  const summarisedVideos = await summariseVideos(rawVideos, apiKey);
  const videos = summarisedVideos.map((v) => ({ ...v, image: videoThumb(v) }));

  // 6. Clean summaries
  [hot, aimoves, crypto, policy, energy, space, robotics, semis, quantum, social].forEach(cleanSummaries);

  // 7. Write cache
  const stamp = (arr) => ({ updated: startedAt, items: arr });
  const TTL = 60 * 60 * 25;
  await Promise.all([
    kv.set("qrx_feed_hot",      stamp(hot),      { ex: TTL }),
    kv.set("qrx_feed_aimoves",  stamp(aimoves),  { ex: TTL }),
    kv.set("qrx_feed_crypto",   stamp(crypto),   { ex: TTL }),
    kv.set("qrx_feed_policy",   stamp(policy),   { ex: TTL }),
    kv.set("qrx_feed_energy",   stamp(energy),   { ex: TTL }),
    kv.set("qrx_feed_space",    stamp(space),    { ex: TTL }),
    kv.set("qrx_feed_robotics", stamp(robotics), { ex: TTL }),
    kv.set("qrx_feed_semis",    stamp(semis),    { ex: TTL }),
    kv.set("qrx_feed_quantum",  stamp(quantum),  { ex: TTL }),
    kv.set("qrx_feed_social",   stamp(social),   { ex: TTL }),
    kv.set("qrx_feed_video",    stamp(videos),   { ex: TTL }),
  ]);

  return res.status(200).json({
    ok: true,
    elapsedMs: Date.now() - startedAt,
    counts: {
      textPool: textPool.length,
      cryptoPool: cryptoPool.length,
      policyPool: policyPool.length,
      energyPool: energyPool.length,
      spacePool: spacePool.length,
      roboticsPool: roboticsPool.length,
      semisPool: semisPool.length,
      quantumPool: quantumPool.length,
      socialPool: socialPool.length,
      hot: hot.length,
      aimoves: aimoves.length,
      crypto: crypto.length,
      policy: policy.length,
      energy: energy.length,
      space: space.length,
      robotics: robotics.length,
      semis: semis.length,
      quantum: quantum.length,
      social: social.length,
      video: videos.length,
    },
  });
}
