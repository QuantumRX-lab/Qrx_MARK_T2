// api/comments-bots.js
// QuantumRx's AI analyst personas — openly labelled bots that seed discussion
// on the day's top stories. Runs in cron-daily PHASE2 (after the refreshes).
//
// Disclosure is the design constraint: every comment is stored with
// bot:true + persona and the drawer renders an "AI analyst" badge. These
// never pose as members (D-INFRA-011) — a reader must always be able to tell
// a persona from a person.
//
// Per run: up to MAX_PER_RUN stories (hot picks first, then one per category
// round-robin), at most ONE bot comment per story ever (nx key, 7d), personas
// rotated by day so threads don't look templated. Comments are grounded only
// in the story's own article_summary/background, go through the same Gemini
// moderation as member comments, and anything held is simply dropped.
// Remove any of them with comments-admin {action:"delete"}.

import { createHash, randomUUID } from "node:crypto";
import { kv } from "@vercel/kv";
import { logRequest, blockThreat } from "./_lib/sentinel.js";
import { storyKey, moderate } from "./comments.js";

const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent";
const MAX_PER_RUN = 12;

export const PERSONAS = [
  { id: "skeptic", name: "The Skeptic",
    brief: "You probe hype. You ask what is unproven, missing, or conveniently left out of the story, and what evidence would change your mind. Dry, fair, never sneering." },
  { id: "operator", name: "The Operator",
    brief: "You think like someone who has to build, buy, or deploy this. You care about cost, timelines, integration pain, supply and who actually signs the cheque. Practical and concrete." },
  { id: "historian", name: "The Historian",
    brief: "You place the story in a longer pattern: where a similar move has been seen before in technology or industry, how it played out, and what that suggests here. Only cite precedents you are confident are real." },
];

// Personas stay out of stories about human suffering: an AI adding "takes"
// on outbreaks, war or deaths reads as glib however carefully it's written.
// Whole categories are skipped, plus a keyword screen for anything sensitive
// that lands in an otherwise-fine category (owner decision 2026-09-19).
const SKIP_CATEGORIES = new Set(["Conflict", "World"]);
const SENSITIVE = /\b(kill(ed|s|ing)?|dead|deaths?|dies|died|casualt|massacre|murder|shooting|bomb(ing|ed)?|air ?strikes?|missile|war\b|invasion|genocide|terror|hostage|outbreak|ebola|epidemic|pandemic|famine|earthquake|flood(s|ing)?|wildfire|hurricane|cyclone|tsunami|crash(ed)?\b|victims?|suicide|abuse|assault|rape|refugee|funeral|mourning)/i;
export function isSensitive(it) {
  if (SKIP_CATEGORIES.has(it.category) || SKIP_CATEGORIES.has(it.subcategory)) return true;
  return SENSITIVE.test(`${it.title} ${it.article_summary || ""} ${it.what_is_it || ""}`);
}

function pickStories(items) {
  const usable = items.filter((it) => it.link && (it.article_summary || it.what_is_it) && !isSensitive(it));
  const picked = [], seen = new Set();
  const take = (it) => { if (it && !seen.has(it.link) && picked.length < MAX_PER_RUN) { seen.add(it.link); picked.push(it); } };
  usable.filter((it) => it.hot).forEach(take);
  const byCat = {};
  usable.filter((it) => !it.hot && it.category).forEach((it) => { (byCat[it.category] = byCat[it.category] || []).push(it); });
  const cats = Object.keys(byCat);
  for (let round = 0; picked.length < MAX_PER_RUN && round < 3; round++) cats.forEach((c) => take(byCat[c][round]));
  return picked;
}

function extractJSON(text) {
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) return fence[1].trim();
  const bracket = text.match(/(\[[\s\S]*\])/);
  return bracket ? bracket[1].trim() : text.trim();
}

async function writeComments(jobs, apiKey) {
  const list = jobs.map((j, i) =>
    `[${i}] PERSONA: ${j.persona.name}\nTITLE: ${j.story.title}\nSTORY: ${(j.story.article_summary || [j.story.what_is_it, j.story.why_it_matters].join(" ")).slice(0, 900)}\nBACKGROUND: ${(j.story.background || "").slice(0, 500)}`
  ).join("\n\n");
  const personas = PERSONAS.map((p) => `${p.name}: ${p.brief}`).join("\n");
  const prompt = `You write short reader-style comments for QuantumRx, a technology intelligence site. Each comment is posted under a clearly labelled AI analyst persona.

PERSONAS
${personas}

For each story below, write ONE comment in the voice of the persona named for that story.
Rules:
- 2 to 4 sentences, conversational, no greeting, no sign-off, no hashtags, no emoji.
- Ground every claim in the STORY and BACKGROUND text given. Do not add facts, figures, names or dates that are not there. Never expand an acronym unless the expansion appears in the text.
- Offer a genuine angle, not a recap of the story.
- End with a real question that invites other readers to reply.
- Do not mention being an AI; the label is shown separately.
- Banned phrases: game changer, it remains to be seen, only time will tell, delve, landscape.

Return ONLY a JSON array: [{"index": <number>, "comment": "..."}]

STORIES
${list}`;
  const res = await fetch(`${GEMINI_URL}?key=${apiKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { temperature: 0.8, maxOutputTokens: 4000, thinkingConfig: { thinkingBudget: 0 } },
    }),
    signal: AbortSignal.timeout(40000),
  });
  const data = await res.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text || "[]";
  return JSON.parse(extractJSON(text));
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

  try {
    const feedRes = await fetch(`https://${req.headers.host}/api/signals-hub-feed?bots=${t0}`, { signal: AbortSignal.timeout(20000) });
    const feed = await feedRes.json();
    const candidates = pickStories(feed.items || []);

    // Claim each story first (nx) so a re-run the same week never double-posts.
    const dayOffset = Math.floor(t0 / 86400000);
    const jobs = [];
    for (const story of candidates) {
      const claim = `botcomment:${createHash("sha256").update(story.link).digest("hex")}`;
      const ok = await kv.set(claim, "1", { nx: true, ex: 7 * 24 * 60 * 60 });
      if (ok) jobs.push({ story, claim, persona: PERSONAS[(jobs.length + dayOffset) % PERSONAS.length] });
    }
    if (!jobs.length) return res.status(200).json({ ok: true, posted: 0, note: "all candidate stories already have a bot comment" });

    const drafts = await writeComments(jobs, apiKey);
    let posted = 0, dropped = 0;
    for (const d of drafts) {
      const job = jobs[d.index];
      const text = String(d.comment || "").trim().slice(0, 1200);
      if (!job || text.length < 40) { dropped++; continue; }
      const verdict = await moderate(text);
      if (verdict.verdict === "hold") { dropped++; continue; }
      const comment = {
        id: randomUUID(), storyId: job.story.link, memberId: `bot:${job.persona.id}`,
        name: job.persona.name, bot: true, persona: job.persona.id, text,
        createdAt: Date.now(), status: "approved",
        moderation: { checked: verdict.checked, reason: verdict.reason, at: Date.now() },
      };
      await kv.set(`comment:${comment.id}`, JSON.stringify(comment));
      await kv.rpush(storyKey(job.story.link), comment.id);
      await kv.lpush("comments:recent", comment.id);
      await kv.ltrim("comments:recent", 0, 999);
      posted++;
      job.done = true;
    }
    // Release claims for stories that ended up with nothing, so tomorrow can retry.
    await Promise.all(jobs.filter((j) => !j.done).map((j) => kv.del(j.claim).catch(() => {})));

    return res.status(200).json({ ok: true, elapsedMs: Date.now() - t0, candidates: candidates.length, attempted: jobs.length, posted, dropped });
  } catch (err) {
    return res.status(500).json({ error: "bot run failed", detail: String(err?.message || err).slice(0, 200) });
  }
}
