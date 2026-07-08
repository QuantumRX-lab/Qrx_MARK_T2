// api/podcast-refresh.js
// Podcasts — "Top 50 Tech" weekly directory.
// Pulls the LATEST episode from each of 50 hand-curated tech-podcast RSS
// feeds and writes a single ranked list to KV as `qrx_podcasts`.
//
// Same shape/mechanics as draw-refresh.js (RSS -> KV -> public feed
// endpoint -> client-side page), but the content unit is a SHOW (with its
// most recent episode) rather than a news story, and there is no Gemini
// step — the curated order IS the ranking, so nothing needs summarising.
//
// Auth: accepts BOTH `x-cron-secret: <CRON_SECRET>` (manual / external
// trigger, matching every other *-refresh.js) AND Vercel's native cron
// header `Authorization: Bearer <CRON_SECRET>`. middleware.js does not
// translate between them, and Vercel Cron only ever sends the Bearer form,
// so accepting both is what actually lets the weekly cron authenticate.
// (Same dual-secret reasoning as weekly-refresh.js from the audit.)
//
// Feed list validated live before commit; dead URLs are skipped gracefully
// at runtime (fetchFeed returns null), so a show dropping offline just
// shrinks the list rather than breaking the page.

import { kv } from "@vercel/kv";
import { logRequest, blockThreat } from "./_lib/sentinel.js";

const UA = "QuantumRx-Podcasts/1.0 (+https://quantumrx.eu)";
const TTL = 60 * 60 * 24 * 8; // 8 days — deliberately outlives the weekly cron

// Curated top-50 tech podcasts. Order = rank. `cat` drives the page's
// category tabs; `dot` is the source-badge colour (same idea as The Draw).
const FEEDS = [
  { url: "https://feeds.twit.tv/twit.xml",                                 show: "This Week in Tech",              cat: "general",  dot: "#e8412a" },
  { url: "https://feeds.twit.tv/tnw.xml",                                  show: "Tech News Weekly",               cat: "general",  dot: "#e67e22" },
  { url: "https://feeds.megaphone.fm/vergecast",                          show: "The Vergecast",                  cat: "general",  dot: "#5200ff" },
  { url: "https://feeds.simplecast.com/l2i9YnTd",                          show: "Hard Fork",                      cat: "general",  dot: "#111827" },
  { url: "https://feeds.megaphone.fm/pivot",                              show: "Pivot",                          cat: "business", dot: "#dc2626" },
  { url: "https://lexfridman.com/feed/podcast/",                          show: "Lex Fridman Podcast",            cat: "ai",       dot: "#6d28d9" },
  { url: "https://api.substack.com/feed/podcast/69345.rss",               show: "Dwarkesh Podcast",               cat: "ai",       dot: "#ef4444" },
  { url: "https://api.substack.com/feed/podcast/1084089.rss",             show: "Latent Space",                   cat: "ai",       dot: "#10b981" },
  { url: "https://changelog.com/practicalai/feed",                        show: "Practical AI",                   cat: "ai",       dot: "#7c3aed" },
  { url: "https://feeds.twit.tv/twig.xml",                                 show: "Intelligent Machines",           cat: "ai",       dot: "#16a085" },
  { url: "https://changelog.com/podcast/feed",                            show: "The Changelog",                  cat: "dev",      dot: "#60a5fa" },
  { url: "https://changelog.com/friends/feed",                            show: "Changelog & Friends",            cat: "dev",      dot: "#38bdf8" },
  { url: "https://feed.syntax.fm/rss",                                    show: "Syntax",                         cat: "dev",      dot: "#f43f5e" },
  { url: "https://changelog.com/jsparty/feed",                            show: "JS Party",                       cat: "dev",      dot: "#d4a017" },
  { url: "https://changelog.com/gotime/feed",                             show: "Go Time",                        cat: "dev",      dot: "#00add8" },
  { url: "https://talkpython.fm/episodes/rss",                            show: "Talk Python To Me",              cat: "dev",      dot: "#306998" },
  { url: "https://pythonbytes.fm/episodes/rss",                           show: "Python Bytes",                   cat: "dev",      dot: "#f0a500" },
  { url: "https://softwareengineeringdaily.com/feed/podcast/",            show: "Software Engineering Daily",     cat: "dev",      dot: "#34495e" },
  { url: "https://feeds.simplecast.com/XA_851k3",                          show: "The Stack Overflow Podcast",     cat: "dev",      dot: "#f48024" },
  { url: "https://atp.fm/rss",                                            show: "Accidental Tech Podcast",        cat: "apple",    dot: "#1abc9c" },
  { url: "https://hanselminutes.com/subscribe",                          show: "Hanselminutes",                  cat: "dev",      dot: "#d64541" },
  { url: "https://pwop.com/feed.aspx?show=dotnetrocks",                    show: ".NET Rocks!",                    cat: "dev",      dot: "#512bd4" },
  { url: "https://shoptalkshow.com/feed/podcast/",                        show: "ShopTalk",                       cat: "dev",      dot: "#e84393" },
  { url: "https://changelog.com/shipit/feed",                             show: "Ship It!",                       cat: "dev",      dot: "#0ea5e9" },
  { url: "https://feeds.transistor.fm/screaming-in-the-cloud",             show: "Screaming in the Cloud",         cat: "business", dot: "#ff9900" },
  { url: "https://kubernetespodcast.com/feeds/audio.xml",                 show: "Kubernetes Podcast from Google", cat: "dev",      dot: "#326ce5" },
  { url: "https://feeds.megaphone.fm/darknetdiaries",                     show: "Darknet Diaries",                cat: "security", dot: "#444444" },
  { url: "https://risky.biz/feeds/risky-business/",                       show: "Risky Business",                 cat: "security", dot: "#b91c1c" },
  { url: "https://malicious.life/feed/podcast/",                          show: "Malicious Life",                 cat: "security", dot: "#8a3a2a" },
  { url: "https://www.smashingsecurity.com/rss",                          show: "Smashing Security",              cat: "security", dot: "#16a34a" },
  { url: "https://feeds.megaphone.fm/cyberwire-daily-podcast",            show: "CyberWire Daily",                cat: "security", dot: "#0f766e" },
  { url: "https://isc.sans.edu/dailypodcast.xml",                        show: "SANS Stormcast",                 cat: "security", dot: "#1e3a8a" },
  { url: "https://feeds.twit.tv/sn.xml",                                   show: "Security Now",                   cat: "security", dot: "#cc0000" },
  { url: "https://feeds.transistor.fm/acquired",                          show: "Acquired",                       cat: "business", dot: "#0d9488" },
  { url: "https://api.substack.com/feed/podcast/10845.rss",              show: "Lenny's Podcast",                cat: "business", dot: "#f59e0b" },
  { url: "https://thetwentyminutevc.libsyn.com/rss",                      show: "The Twenty Minute VC",           cat: "business", dot: "#2563eb" },
  { url: "https://www.marketplace.org/feed/podcast/marketplace-tech/",    show: "Marketplace Tech",               cat: "business", dot: "#00a06b" },
  { url: "https://feeds.twit.tv/twiet.xml",                                show: "This Week in Enterprise Tech",   cat: "business", dot: "#2c3e50" },
  { url: "https://feeds.twit.tv/mbw.xml",                                  show: "MacBreak Weekly",                cat: "apple",    dot: "#8e44ad" },
  { url: "https://www.relay.fm/connected/feed",                           show: "Connected",                      cat: "apple",    dot: "#ec4899" },
  { url: "https://www.relay.fm/upgrade/feed",                             show: "Upgrade",                        cat: "apple",    dot: "#e11d48" },
  { url: "https://feeds.twit.tv/hom.xml",                                  show: "Hands-On Apple",                 cat: "apple",    dot: "#555555" },
  { url: "https://feeds.twit.tv/ww.xml",                                   show: "Windows Weekly",                 cat: "general",  dot: "#0078d4" },
  { url: "https://feeds.twit.tv/aaa.xml",                                  show: "All About Android",              cat: "general",  dot: "#3ddc84" },
  { url: "https://feeds.fireside.fm/linuxunplugged/rss",                   show: "LINUX Unplugged",                cat: "linux",    dot: "#e95420" },
  { url: "https://feeds.fireside.fm/selfhosted/rss",                       show: "Self-Hosted",                    cat: "linux",    dot: "#0891b2" },
  { url: "https://latenightlinux.com/feed/mp3",                           show: "Late Night Linux",               cat: "linux",    dot: "#1f2937" },
  { url: "https://feeds.fireside.fm/linuxactionnews/rss",                  show: "Linux Action News",              cat: "linux",    dot: "#d97706" },
  { url: "https://feeds.twit.tv/uls.xml",                                  show: "Untitled Linux Show",            cat: "linux",    dot: "#f39c12" },
  { url: "https://feeds.twit.tv/floss.xml",                                show: "FLOSS Weekly",                   cat: "linux",    dot: "#27ae60" },
];

// ── Helpers (mirrors draw-refresh.js) ───────────────────────────────────────
function sanitiseUrl(url) {
  if (!url) return "";
  try { const u = new URL(url); return ["https:", "http:"].includes(u.protocol) ? url : ""; } catch { return ""; }
}

function decode(s = "") {
  return s
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&apos;/g, "'")
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

// Show cover art — podcast artwork lives at the channel level (itunes:image
// or <image><url>), so read it from the header (everything before the first
// <item>) rather than from the episode block.
function channelImage(header) {
  const itunes = pickAttr(header, "itunes:image", "href");
  if (itunes) return sanitiseUrl(itunes.replace(/&amp;/g, "&"));
  const imgBlock = pickTag(header, "image");
  if (imgBlock) {
    const u = decode(pickTag(imgBlock, "url"));
    if (u) return sanitiseUrl(u);
  }
  return "";
}

// Parse ONE feed into a single ranked entry = its latest episode + show art.
function parseLatest(xml, feed) {
  const header = xml.split(/<item[\s>]/i)[0];
  const art = channelImage(header);

  const m = xml.match(/<item[^>]*>([\s\S]*?)<\/item>/i)
    || xml.match(/<entry[^>]*>([\s\S]*?)<\/entry>/i);
  if (!m) return null;
  const block = m[1];

  const title = decode(pickTag(block, "title"));
  if (!title) return null;

  // Episode-level artwork if present, otherwise the show's cover art.
  const epImg = sanitiseUrl(pickAttr(block, "itunes:image", "href").replace(/&amp;/g, "&"))
    || sanitiseUrl(pickAttr(block, "media:thumbnail", "url"))
    || "";
  // Force https — the artwork is embedded on an https page, so an http URL
  // (e.g. relay.fm's files.relay.fm) is blocked as mixed content. Upgrading
  // can only help: an http-only host was already unusable when embedded.
  const image = (art || epImg).replace(/^http:\/\//i, "https://");

  const link = sanitiseUrl(decode(pickTag(block, "link")) || pickAttr(block, "link", "href"));
  const audio = sanitiseUrl(pickAttr(block, "enclosure", "url"));
  const pubDate = decode(pickTag(block, "pubDate") || pickTag(block, "published") || pickTag(block, "updated"));
  const description = decode(
    pickTag(block, "description") || pickTag(block, "itunes:summary") ||
    pickTag(block, "content:encoded") || pickTag(block, "summary") || pickTag(block, "content")
  );

  return {
    show: feed.show,
    cat: feed.cat,
    dot: feed.dot,
    title: title.slice(0, 220),
    url: link || audio,        // where "Open episode" goes
    audio,                     // direct media enclosure for "Listen"
    image,
    description: description.slice(0, 600),
    published: pubDate ? (new Date(pubDate).getTime() || Date.now()) : Date.now(),
  };
}

async function fetchFeed(feed) {
  try {
    const res = await fetch(feed.url, {
      headers: { "User-Agent": UA },
      redirect: "follow",
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) return null;
    return parseLatest(await res.text(), feed);
  } catch { return null; }
}

// ── Handler ─────────────────────────────────────────────────────────────────
export default async function handler(req, res) {
  await logRequest(req, "podcast-refresh");

  const expected = process.env.CRON_SECRET;
  const headerSecret = req.headers["x-cron-secret"];
  const bearer = (req.headers["authorization"] || "").replace(/^Bearer\s+/i, "");
  const provided = headerSecret || bearer;
  if (!expected || provided !== expected) {
    await blockThreat(req, "podcast-refresh", "missing-or-invalid-cron-secret");
    return res.status(401).json({ error: "Unauthorized" });
  }

  const startedAt = new Date().toISOString();
  const t0 = Date.now();

  const results = await Promise.all(FEEDS.map(fetchFeed));
  const items = results
    .filter(Boolean)
    .map((it, i) => ({ rank: i + 1, ...it })); // rank follows curated order

  // Re-rank sequentially after dropping any feeds that failed this run, so
  // there are never gaps in the numbering the page renders.
  items.forEach((it, i) => { it.rank = i + 1; });

  await kv.set("qrx_podcasts", { updated: startedAt, items }, { ex: TTL });

  return res.status(200).json({
    ok: true,
    elapsedMs: Date.now() - t0,
    total: FEEDS.length,
    live: items.length,
    dropped: FEEDS.length - items.length,
  });
}
