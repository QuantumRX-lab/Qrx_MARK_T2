// api/comments-bots.js
// Simulated regular readers for testing live comments + moderation while the
// site is in Ghost private mode (owner decision 2026-09-19, D-INFRA-012).
// Comments are stored with sim:true as an INTERNAL marker only (digest
// separation, bulk cleanup) — they are not labelled on the page. If the site
// ever goes public again, disable this job or reinstate disclosure first.
//
// A fixed cast of regulars with stable usernames, interests and voices come
// back each day to stories that suit them, sometimes replying to each other.
// Two stress-test accounts post deliberately bad comments now and then so the
// moderation filter has something to catch; those land in the held queue
// exactly as a real bad comment would.
// Runs in cron-daily PHASE2. Admin: comments-admin (view=held / recent).

import { randomUUID } from "node:crypto";
import { kv } from "@vercel/kv";
import { logRequest, blockThreat } from "./_lib/sentinel.js";
import { storyKey, moderate, loadThread } from "./comments.js";

const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent";
const STORIES_PER_RUN = 8;
const MAX_COMMENTS_PER_RUN = 16;

export const REGULARS = [
  { id: "tomas_builds", name: "tomas_builds", interests: ["Robotics", "Chips & Quantum", "AI"],
    voice: "Hardware tinkerer in Rotterdam, builds robots in his garage. Short, practical sentences. Asks how things actually get built and what they cost. Occasionally mentions his own projects in passing." },
  { id: "quietquant", name: "quietquant", interests: ["Markets", "AI", "Chips & Quantum"],
    voice: "Ex-trader, now does independent research. Dry, sceptical of valuations and hype cycles, thinks in terms of margins and who pays. Never uses exclamation marks." },
  { id: "dr_elin", name: "Elin M.", interests: ["AI", "Chips & Quantum", "Science"],
    voice: "Postdoc in applied physics. Careful and precise, separates what is demonstrated from what is claimed. Warm but will politely correct a sloppy take." },
  { id: "gridwatcher", name: "gridwatcher", interests: ["Energy & Climate", "Policy", "Markets"],
    voice: "Grid engineer at a UK distribution network operator. Pragmatic, a bit weary. Always comes back to connection queues, transmission capacity and planning timelines." },
  { id: "orbit_nerd", name: "orbit_nerd", interests: ["Space", "Robotics", "Science"],
    voice: "Space enthusiast, watches every launch. Writes casually, mostly lowercase, genuinely excited, the occasional 'honestly' or 'ngl'. Knows launch vehicles well." },
  { id: "policy_kat", name: "Kat R.", interests: ["Policy", "AI", "Social"],
    voice: "Works in EU tech policy in Brussels. Measured, pays attention to regulation, enforcement and who writes the rules. Occasionally wry." },
  { id: "mira_dev", name: "mira.dev", interests: ["AI", "Social", "Connectivity"],
    voice: "Backend developer who uses AI coding tools daily. Cynical humour, impatient with marketing speak, but will say when something is genuinely useful." },
];

// Deliberately bad accounts for exercising the filter. Their comments are
// expected to be HELD by moderation; if one ever gets through, that's a
// moderation gap worth seeing.
const STRESS = [
  { id: "cheap_gpu_deals", name: "cheap_gpu_deals", kind: "spam",
    brief: "An obvious spam comment advertising discounted GPUs or a crypto giveaway, with a made-up link such as example-deals.biz. Nothing to do with the story." },
  { id: "rant_mode", name: "rant_mode", kind: "abuse",
    brief: "A hostile, insulting comment attacking the other commenters as idiots. Rude but NOT hateful toward any protected group, no slurs, no threats." },
];

// Same sensitivity screen as before: no simulated chatter under stories about
// human suffering.
const SKIP_CATEGORIES = new Set(["Conflict", "World"]);
const SENSITIVE = /\b(kill(ed|s|ing)?|dead|deaths?|dies|died|casualt|massacre|murder|shooting|bomb(ing|ed)?|air ?strikes?|missile|war\b|invasion|genocide|terror|hostage|outbreak|ebola|epidemic|pandemic|famine|earthquake|flood(s|ing)?|wildfire|hurricane|cyclone|tsunami|crash(ed)?\b|victims?|suicide|abuse|assault|rape|refugee|funeral|mourning)/i;
function isSensitive(it) {
  if (SKIP_CATEGORIES.has(it.category) || SKIP_CATEGORIES.has(it.subcategory)) return true;
  return SENSITIVE.test(`${it.title} ${it.article_summary || ""} ${it.what_is_it || ""}`);
}

// Recent Ghost articles ("Featured Articles" on the homepage). Only posts from
// the last ARTICLE_WINDOW_DAYS; read-only Content API key (GHOST_CONTENT_API_KEY).
// Articles have no tags, so interests are matched by keyword.
const ARTICLE_WINDOW_DAYS = 7;
const CONTENT_URL = (process.env.GHOST_CONTENT_URL || "https://quantumrx.ghost.io").replace(/\/$/, "");
const TOPIC_WORDS = [
  ["Space", /\b(space|spacex|starship|starlink|rocket|launch|orbit|satellite|nasa|esa)\b/i],
  ["Chips & Quantum", /\b(chip|chips|semiconductor|gpu|nvidia|tsmc|quantum|qubit)\b/i],
  ["Robotics", /\b(robot|robots|robotics|humanoid|drone|autonomous)\b/i],
  ["Energy & Climate", /\b(energy|grid|solar|wind|battery|nuclear|climate|power)\b/i],
  ["Markets", /\b(ipo|invest|investor|valuation|market|stock|funding|revenue)\b/i],
  ["Policy", /\b(regulat\w*|policy|law|government|safety|treaty|agree\w*|oversight)\b/i],
  ["AI", /\b(ai|model|models|llm|agent|agents|openai|anthropic|deepmind|lab|labs)\b/i],
];
function guessCategory(text) {
  let best = "AI", bestN = 0;
  for (const [cat, re] of TOPIC_WORDS) {
    const n = (String(text).match(new RegExp(re.source, "gi")) || []).length;
    if (n > bestN) { best = cat; bestN = n; }
  }
  return best;
}
async function fetchRecentArticles() {
  const key = process.env.GHOST_CONTENT_API_KEY;
  if (!key) return [];
  const since = new Date(Date.now() - ARTICLE_WINDOW_DAYS * 864e5).toISOString().slice(0, 19).replace("T", " ");
  const url = `${CONTENT_URL}/ghost/api/content/posts/?key=${key}&limit=10&formats=plaintext` +
    `&fields=title,url,plaintext,custom_excerpt,excerpt,published_at,visibility` +
    `&filter=${encodeURIComponent(`published_at:>'${since}'+visibility:public`)}`;
  try {
    const d = await (await fetch(url, { signal: AbortSignal.timeout(10000) })).json();
    return (d.posts || []).map((p) => ({
      title: p.title, link: p.url, article: true, hot: false,
      article_summary: String(p.plaintext || p.custom_excerpt || p.excerpt || "").replace(/\s+/g, " ").slice(0, 1500),
      category: guessCategory(`${p.title} ${p.plaintext || ""}`), subcategory: "Article",
      published: Date.parse(p.published_at) || Date.now(),
    }));
  } catch { return []; }
}

function shuffle(a) { for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; }

function pickStories(items) {
  const usable = items.filter((it) => it.link && (it.article_summary || it.what_is_it) && !isSensitive(it));
  const hot = usable.filter((it) => it.hot);
  const rest = shuffle(usable.filter((it) => !it.hot));
  return [...hot.slice(0, 3), ...rest].slice(0, STORIES_PER_RUN);
}

function interestedRegulars(story) {
  const fans = REGULARS.filter((r) => r.interests.includes(story.category));
  const pool = fans.length ? fans : REGULARS;
  return shuffle([...pool]).slice(0, 1 + Math.floor(Math.random() * Math.min(3, pool.length)));
}

function extractJSON(text) {
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) return fence[1].trim();
  const bracket = text.match(/(\[[\s\S]*\])/);
  return bracket ? bracket[1].trim() : text.trim();
}

async function gemini(prompt, apiKey, temperature) {
  const res = await fetch(`${GEMINI_URL}?key=${apiKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { temperature, maxOutputTokens: 6000, thinkingConfig: { thinkingBudget: 0 } },
    }),
    signal: AbortSignal.timeout(45000),
  });
  const data = await res.json();
  return JSON.parse(extractJSON(data?.candidates?.[0]?.content?.parts?.[0]?.text || "[]"));
}

async function writeRegularComments(plan, apiKey) {
  const cast = REGULARS.map((r) => `- ${r.name}: ${r.voice}`).join("\n");
  const blocks = plan.map((p, i) => {
    const existing = p.existing.length
      ? p.existing.slice(-4).map((c) => `    ${c.name}: "${c.text.slice(0, 220)}"`).join("\n")
      : "    (no comments yet)";
    return `[${i}] TITLE: ${p.story.title}
${p.story.article ? "QUANTUMRX ARTICLE (the site's own piece — readers may agree or argue with the author)" : "STORY"}: ${(p.story.article_summary || [p.story.what_is_it, p.story.why_it_matters].join(" ")).slice(0, p.story.article ? 1500 : 800)}
EXISTING COMMENTS:
${existing}
WRITERS (in order): ${p.writers.map((w) => w.name).join(", ")}`;
  }).join("\n\n");

  const prompt = `Write realistic reader comments for a technology news site's comment section, for an internal test of the comment system. The commenters are a fixed group of regular readers:

${cast}

For each story, write one comment per listed writer, in order, each in that person's own voice. Make it read like a real comment section:
- Vary length a lot: some are one short line, some are 3-4 sentences.
- React to the story with an actual opinion; do not summarise it.
- Later writers may respond to earlier comments (address them by name, e.g. "@quietquant fair, but...") and they do not always agree.
- Do not end every comment with a question. No greetings, sign-offs, hashtags or emoji.
- Only reference facts that are in the STORY text. Do not invent figures, names or dates. Never expand an acronym unless the text does.
- Avoid: game changer, it remains to be seen, only time will tell, delve, landscape.

Return ONLY a JSON array: [{"story": <index>, "writer": "<name>", "comment": "..."}]

STORIES
${blocks}`;
  return gemini(prompt, apiKey, 0.9);
}

async function writeStressComment(story, account, apiKey) {
  const prompt = `This is a test fixture for a comment moderation filter. Write ONE comment for the story below as described, so we can confirm the filter catches it.
Description: ${account.brief}
Keep it under 50 words.
Return ONLY a JSON array: [{"comment": "..."}]

STORY TITLE: ${story.title}`;
  const out = await gemini(prompt, apiKey, 0.9);
  return String(out?.[0]?.comment || "").trim();
}

// Replies: regulars return to threads from the last few days and answer a
// specific earlier comment — agreeing, pushing back, or following up after
// "thinking about it more". Stored with replyTo so the drawer can show it.
const REPLY_WINDOW_MS = 4 * 24 * 60 * 60 * 1000;
const REPLY_THREADS_PER_RUN = 6;

async function recentSimThreads(feedByLink) {
  const ids = (await kv.lrange("comments:recent", 0, 499)) || [];
  if (!ids.length) return [];
  const rows = (await kv.mget(...ids.map((id) => `comment:${id}`))).filter(Boolean)
    .map((r) => (typeof r === "string" ? JSON.parse(r) : r));
  const cutoff = Date.now() - REPLY_WINDOW_MS;
  const links = [...new Set(rows.filter((c) => c.sim && c.status === "approved" && c.createdAt >= cutoff && feedByLink[c.storyId]).map((c) => c.storyId))];
  const threads = [];
  for (const link of shuffle(links).slice(0, REPLY_THREADS_PER_RUN * 2)) {
    const thread = (await loadThread(link)).filter((c) => c.sim);
    if (!thread.length) continue;
    const last = thread[thread.length - 1];
    const story = feedByLink[link];
    const fans = REGULARS.filter((r) => r.id !== last.persona && (r.interests.includes(story.category) || Math.random() < 0.25));
    if (!fans.length) continue;
    // Reply to someone else in the thread, usually the most recent comment.
    const others = thread.filter((c) => c.persona !== undefined);
    const target = Math.random() < 0.7 ? last : others[Math.floor(Math.random() * others.length)];
    const replier = shuffle(fans.filter((r) => r.id !== target.persona))[0];
    if (!replier) continue;
    threads.push({ story, thread, target, replier });
    if (threads.length >= REPLY_THREADS_PER_RUN) break;
  }
  return threads;
}

async function writeReplies(threads, apiKey) {
  const cast = REGULARS.map((r) => `- ${r.name}: ${r.voice}`).join("\n");
  const blocks = threads.map((t, i) => `[${i}] STORY: ${t.story.title}
SUMMARY: ${(t.story.article_summary || t.story.what_is_it || "").slice(0, 500)}
THREAD SO FAR:
${t.thread.slice(-6).map((c) => `    ${c.name}: "${c.text.slice(0, 260)}"`).join("\n")}
REPLIER: ${t.replier.name}
REPLYING TO: ${t.target.name} — "${t.target.text.slice(0, 260)}"`).join("\n\n");
  const prompt = `Write replies in a technology news comment section, for an internal test of the comment system. The commenters are a fixed group of regular readers:

${cast}

For each thread, write ONE reply from REPLIER, directly responding to the REPLYING TO comment, in the replier's own voice. Mix it up across threads: some agree and add a point, some push back, some are a short follow-up ("coming back to this —", "fair point, although..."), some are one line. Start by addressing the person (e.g. "@quietquant ...") about half the time. Stay on the story; only use facts from the SUMMARY or the thread. No greetings, sign-offs, hashtags or emoji. Do not repeat what the other person said.

Return ONLY a JSON array: [{"thread": <index>, "reply": "..."}]

THREADS
${blocks}`;
  return gemini(prompt, apiKey, 0.9);
}

async function store(story, name, personaId, text, verdict, createdAt, extra = {}) {
  const comment = {
    id: randomUUID(), storyId: story.link, memberId: `sim:${personaId}`,
    name, bot: true, sim: true, persona: personaId, text,
    createdAt: Math.min(createdAt, Date.now()),
    status: verdict.verdict === "hold" ? "held" : "approved",
    moderation: { checked: verdict.checked, reason: verdict.reason, at: Date.now() },
    ...extra,
  };
  await kv.set(`comment:${comment.id}`, JSON.stringify(comment));
  await kv.rpush(storyKey(story.link), comment.id);
  await kv.lpush("comments:recent", comment.id);
  await kv.ltrim("comments:recent", 0, 999);
  if (comment.status === "held") await kv.lpush("comments:held", comment.id);
  return comment;
}

// Timestamps rise through a thread so "@name" replies never predate the
// comment they answer.
function nextStamp(prev) {
  const base = prev || Date.now() - (60 + Math.floor(Math.random() * 180)) * 60 * 1000;
  return Math.min(Date.now(), base + (4 + Math.floor(Math.random() * 40)) * 60 * 1000);
}

export default async function handler(req, res) {
  await logRequest(req, "comments-bots");
  const expected = process.env.CRON_SECRET;
  if (!expected || req.headers["x-cron-secret"] !== expected) {
    await blockThreat(req, "comments-bots", "missing-or-invalid-cron-secret");
    return res.status(401).json({ error: "Unauthorized" });
  }
  const apiKey = process.env.GEMINI_API_KEY_Forge;
  if (!apiKey) return res.status(500).json({ error: "Missing Gemini API key" });
  const t0 = Date.now();
  // ?mode=replies runs only the reply pass (for extra check-ins during the day).
  const mode = String(req.query?.mode || "all");

  try {
    const feed = await (await fetch(`https://${req.headers.host}/api/signals-hub-feed?sim=${t0}`, { signal: AbortSignal.timeout(20000) })).json();
    const articles = await fetchRecentArticles();
    const feedByLink = Object.fromEntries([...(feed.items || []), ...articles].filter((it) => !isSensitive(it)).map((it) => [it.link, it]));
    let posted = 0, held = 0, replies = 0, stress = null, storiesTouched = 0;

    // 1. Replies to earlier threads first, so today's new comments aren't
    //    immediately answered in the same breath.
    const threads = await recentSimThreads(feedByLink);
    if (threads.length) {
      const drafts = await writeReplies(threads, apiKey);
      for (const d of drafts) {
        const t = threads[d.thread];
        const text = String(d.reply || "").trim().slice(0, 1200);
        if (!t || text.length < 4) continue;
        const verdict = await moderate(text);
        const lastAt = t.thread[t.thread.length - 1].createdAt;
        const c = await store(t.story, t.replier.name, t.replier.id, text, verdict, nextStamp(Math.max(lastAt, Date.now() - 30 * 60 * 1000)),
          { replyTo: { id: t.target.id, name: t.target.name } });
        c.status === "held" ? held++ : replies++;
      }
    }

    if (mode !== "replies") {
      // 2. New comments on today's stories.
      const stories = [...articles.filter((a) => !isSensitive(a)), ...pickStories(feed.items || [])].slice(0, STORIES_PER_RUN + articles.length);
      storiesTouched = stories.length;
      const plan = [];
      for (const story of stories) {
        const existing = (await loadThread(story.link)).filter((c) => c.sim);
        const already = new Set(existing.map((c) => c.persona));
        const base = story.article ? shuffle([...REGULARS]).sort((a, b) => b.interests.includes(story.category) - a.interests.includes(story.category)).slice(0, 2 + Math.floor(Math.random() * 3)) : interestedRegulars(story);
        const writers = base.filter((w) => !already.has(w.id) || Math.random() < 0.3);
        if (writers.length) plan.push({ story, existing, writers, lastAt: existing.length ? existing[existing.length - 1].createdAt : 0 });
      }
      const drafts = plan.length ? await writeRegularComments(plan, apiKey) : [];
      for (const d of drafts) {
        if (posted + held >= MAX_COMMENTS_PER_RUN) break;
        const p = plan[d.story];
        const writer = p && REGULARS.find((r) => r.name === d.writer);
        const text = String(d.comment || "").trim().slice(0, 1200);
        if (!p || !writer || text.length < 8) continue;
        const verdict = await moderate(text);
        p.lastAt = nextStamp(p.lastAt);
        const c = await store(p.story, writer.name, writer.id, text, verdict, p.lastAt);
        c.status === "held" ? held++ : posted++;
      }

      // 3. ~Half of runs, one stress-test account posts something the filter should catch.
      if (stories.length && Math.random() < 0.5) {
        const account = STRESS[Math.floor(Math.random() * STRESS.length)];
        const story = stories[Math.floor(Math.random() * stories.length)];
        const text = (await writeStressComment(story, account, apiKey)).slice(0, 1200);
        if (text) {
          const verdict = await moderate(text);
          const c = await store(story, account.name, account.id, text, verdict, nextStamp(0), { stressTest: account.kind });
          stress = { account: account.name, kind: account.kind, caughtByFilter: c.status === "held", reason: verdict.reason };
        }
      }
    }

    return res.status(200).json({
      ok: true, mode, elapsedMs: Date.now() - t0, stories: storiesTouched, articles: articles.map((a) => a.title),
      replies, regularComments: { approved: posted, heldByFilter: held }, stressTest: stress,
    });
  } catch (err) {
    return res.status(500).json({ error: "sim run failed", detail: String(err?.message || err).slice(0, 200) });
  }
}
