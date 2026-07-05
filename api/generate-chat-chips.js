// api/generate-chat-chips.js
//
// Runs once a day, piggybacked on the same cron trigger as the existing
// refresh scripts (no new schedule). Generates 8 headline-style chat
// chips FROM today's actual retrieved stories, so every chip is
// structurally guaranteed to be answerable from real, live data, not
// from Gemini's frozen training memory.
//
// Each chip is pre-tagged with:
//   - groundedStories: the specific stories it's based on
//   - responseFormat: which of the five reply shapes fits it
//     (comparative/speculative/synthesis/single_story/weekly_recap)
// Both are decided HERE, by the same model that phrases the question,
// with full context. This removes the regex-guessing classifyQuestion()
// has to do in chat.js for these chips entirely — that guessing only
// exists as a fallback for free-typed questions now, not for chips.
//
// Write pattern matches the archive: a dated, permanent record, plus a
// `latest` pointer that ONLY gets overwritten on success. If today's
// run fails or hasn't happened yet, `latest` still holds yesterday's
// chips — no separate fallback logic needed anywhere else.

import { kv } from "@vercel/kv";
import { logRequest, blockThreat } from "./_lib/sentinel.js";

const CRON_SECRET = process.env.CRON_SECRET;
const GEMINI_API_KEY = process.env.GEMINI_API_KEY_Chat;

// Pull a representative sample across verticals for breadth, not just
// the single 'hot' feed — a comparative chip about chips needs semis
// data, a nuclear-energy chip needs the energy feed, etc.
const SAMPLE_VERTICALS = {
  hot: 'qrx_feed_hot',
  aimoves: 'qrx_feed_aimoves',
  energy: 'qrx_feed_energy',
  space: 'qrx_feed_space',
  semis: 'qrx_feed_semis',
  policy: 'qrx_feed_policy',
  robotics: 'qrx_feed_robotics',
};

function todayUTC() {
  return new Date().toISOString().slice(0, 10);
}

async function gatherTodaysStories() {
  const pool = [];
  await Promise.all(
    Object.entries(SAMPLE_VERTICALS).map(async ([vertical, kvKey]) => {
      try {
        const cached = await kv.get(kvKey);
        if (cached?.items && Array.isArray(cached.items)) {
          cached.items.slice(0, 4).forEach(item => {
            pool.push({ vertical, ...item });
          });
        }
      } catch {
        // one vertical missing shouldn't kill the whole generation run
      }
    })
  );
  return pool;
}

function buildGenerationPrompt(stories) {
  const storyList = stories
    .map((s, i) =>
      `[${i}] VERTICAL: ${s.vertical}\nTITLE: ${s.title}\nWHAT IS IT: ${s.what_is_it || s.summary || ''}\nWHY IT MATTERS: ${s.why_it_matters || ''}\nSOURCE: ${s.source || ''}\nURL: ${s.url || s.link || ''}`
    )
    .join('\n\n');

  return `You are generating chat widget chips for QuantumRx, an AI infrastructure publication. Below is a set of today's real, live stories across several verticals.

TODAY'S STORIES:

${storyList}

Generate exactly 8 headline-style questions, in the QuantumRx voice: punchy, specific, sound like a headline rather than a generic FAQ. Examples of the right tone: "Biggest obstacle to Musk getting to Mars", "Who's quietly losing the chip war", "What's the real reason everyone's building nuclear again".

CRITICAL RULES:
- Every question must be answerable using ONLY the stories listed above. Do not generate a question about a topic that isn't actually covered in the story list, even if it would make a good headline.
- Each question must reference which story index numbers ground it (1 to 3 stories per question).
- Each question must be tagged with exactly one response format: comparative (who's winning/losing/ahead), speculative (what could go wrong / what happens if / biggest obstacle or risk), synthesis (connecting multiple stories, what's getting outsized attention), single_story (about one specific story in depth), or weekly_recap (a broad overview question).
- Prefer variety: do not generate 8 questions all in the same format or all about the same vertical.
- This must parse as valid JSON. Do not use straight double quotes ("") inside any question or label text — rephrase to avoid quoting a name or term, or use single quotes instead. Do not include literal newlines inside a string value.

Return ONLY a JSON array, no other text, no markdown code fences, in exactly this shape:

[
  {
    "question": "the full question, as it would be sent to an analyst",
    "label": "a shorter version for a button, under 40 characters",
    "responseFormat": "comparative",
    "groundedStoryIndices": [0, 3]
  }
]`;
}

async function callGemini(prompt) {
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${GEMINI_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
        // Raised from 2048 — 8 chip objects with grounding indices left
        // little headroom, and hitting the cap mid-string produces
        // exactly the "Unterminated string in JSON" failure this was
        // seen throwing.
        generationConfig: { maxOutputTokens: 4096, temperature: 0.8 },
      }),
    }
  );
  const data = await response.json();
  if (!response.ok) throw new Error('Gemini generation failed: ' + JSON.stringify(data));
  return data.candidates?.[0]?.content?.parts?.[0]?.text || '';
}

// If the model's output was truncated (hit the token cap mid-string) or a
// later object got malformed (e.g. an unescaped quote inside a question),
// JSON.parse fails on the whole array even though earlier chips in it were
// fine. Recover by cutting back to the last complete top-level object and
// closing the array there, rather than discarding a good batch over one bad
// tail entry. Returns null if nothing recoverable is found.
function tryRepairTruncatedArray(text) {
  const lastBrace = text.lastIndexOf('}');
  if (lastBrace === -1) return null;
  const truncated = text.slice(0, lastBrace + 1) + ']';
  try {
    return JSON.parse(truncated);
  } catch {
    return null;
  }
}

function parseGeneratedChips(rawText, stories) {
  // Strip markdown code fences if the model added them despite instructions
  const cleaned = rawText.replace(/```json\s*|```\s*/g, '').trim();

  let parsed;
  try {
    parsed = JSON.parse(cleaned);
  } catch (err) {
    parsed = tryRepairTruncatedArray(cleaned);
    if (!parsed) throw err; // genuinely unrecoverable — let the caller's catch handle it
  }

  if (!Array.isArray(parsed) || !parsed.length) {
    throw new Error('Generated chips were not a valid non-empty array');
  }

  return parsed
    .filter(c => c.question && c.label && c.responseFormat && Array.isArray(c.groundedStoryIndices))
    .map(c => ({
      question: c.question,
      label: c.label,
      responseFormat: c.responseFormat,
      groundedStories: c.groundedStoryIndices
        .map(i => stories[i])
        .filter(Boolean)
        .map(s => ({
          title: s.title,
          url: s.url || s.link,
          source: s.source,
          vertical: s.vertical,
          what_is_it: s.what_is_it || s.summary || '',
          why_it_matters: s.why_it_matters || '',
          what_next: s.what_next || s.what_to_watch || '',
          hot_take: s.hot_take || null,
        })),
    }))
    .filter(c => c.groundedStories.length > 0); // drop any chip whose story indices didn't resolve
}

export default async function handler(req, res) {
  await logRequest(req, "generate-chat-chips");

  const cronSecret = req.headers['x-cron-secret'];
  if (!CRON_SECRET || cronSecret !== CRON_SECRET) {
    await blockThreat(req, "generate-chat-chips", "missing-or-invalid-cron-secret");
    return res.status(403).json({ error: 'Forbidden' });
  }

  try {
    const stories = await gatherTodaysStories();
    if (!stories.length) {
      return res.status(200).json({ written: false, reason: 'no-stories-available' });
    }

    const prompt = buildGenerationPrompt(stories);
    const rawText = await callGemini(prompt);
    const chips = parseGeneratedChips(rawText, stories);

    if (chips.length < 4) {
      // Too few valid chips survived parsing/filtering to be worth
      // replacing yesterday's set — fail loud, leave `latest` untouched.
      return res.status(200).json({ written: false, reason: 'too-few-valid-chips', count: chips.length });
    }

    const date = todayUTC();

    // Stable id per chip, assigned to the FINAL (post-filter) array position —
    // this is what lets chat.js resolve a chip's real grounding server-side
    // from just an id, rather than trusting a client-supplied grounding blob.
    // See getChipById() in chat.js.
    const chipsWithIds = chips.map((c, i) => ({ id: `${date}_${i}`, ...c }));

    const record = { date, generatedAt: new Date().toISOString(), chips: chipsWithIds };

    // Dated permanent record, for history/audit — never overwritten.
    await kv.set(`daily_chat_chips:${date}`, record);

    // `latest` — the ONLY key the read endpoint actually serves. Only
    // written here, on confirmed success, which is what gives yesterday's
    // chips their automatic fallback: if this line never runs today,
    // `latest` simply still holds whatever it held before.
    await kv.set('daily_chat_chips:latest', record);

    return res.status(200).json({ written: true, date, chipCount: chips.length });
  } catch (err) {
    console.error('generate-chat-chips error:', err);
    // Failure here means `latest` is untouched, yesterday's chips keep
    // serving. That's the point — this is a soft failure, not an outage.
    return res.status(500).json({ written: false, error: String(err) });
  }
}
