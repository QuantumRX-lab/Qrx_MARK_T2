// /api/weekly-refresh
//
// Generates the weekly "This Week in Tech" editorial briefing for QuantumRx.
// Triggered by Railway cron every Monday at 06:00 UTC, or manually via GET.
//
// Reads from existing Signals KV caches (qrx_feed_*) where each value is:
//   { updated: timestamp, items: [{ title, link, description, source, image, published, summary }] }
//
// Also fetches fresh from Tier 1 and Tier 2 RSS sources and Hacker News / arXiv.
//
// SECURITY — three layers:
// 1. Shared secret header: x-refresh-secret must match WEEKLY_REFRESH_SECRET env var
// 2. Rate limit guard: minimum 12-hour gap between runs checked via KV
// 3. KV token scoping: this endpoint writes, weekly-feed.js only reads
//
// Env vars required:
//   GEMINI_API_KEY_Forge      — Google AI Studio API key (same as Signals feed)
//   WEEKLY_REFRESH_SECRET     — Shared secret for endpoint auth
//   KV_REST_API_URL           — Vercel KV REST URL (auto-set)
//   KV_REST_API_TOKEN         — Vercel KV REST token (auto-set, write-capable)

import { kv } from '@vercel/kv';
import { logRequest } from './_lib/sentinel.js';

const GEMINI_MODEL = 'gemini-2.5-flash';
const MIN_RUN_INTERVAL_MS = 12 * 60 * 60 * 1000; // 12 hours

// KV keys for existing Signals feed caches
const SIGNALS_KV_KEYS = [
  'qrx_feed_hot',
  'qrx_feed_aimoves',
  'qrx_feed_crypto',
  'qrx_feed_policy',
  'qrx_feed_energy',
  'qrx_feed_space',
  'qrx_feed_robotics',
  'qrx_feed_semis',
  'qrx_feed_quantum',
  'qrx_feed_social',
];

// ---------------------------------------------------------------------------
// TIER 1 — Specialist / technical sources
// ---------------------------------------------------------------------------
const TIER1_SOURCES = [
  { name: 'Ars Technica', url: 'https://feeds.arstechnica.com/arstechnica/index', category: 'tech' },
  { name: 'MIT Technology Review', url: 'https://www.technologyreview.com/feed', category: 'tech' },
  { name: 'Wired', url: 'https://www.wired.com/feed/rss', category: 'tech' },
  { name: 'The Verge', url: 'https://www.theverge.com/rss/index.xml', category: 'tech' },
  { name: 'TechCrunch', url: 'https://techcrunch.com/feed', category: 'tech' },
];

// ---------------------------------------------------------------------------
// TIER 2 — Mainstream / financial press
// ---------------------------------------------------------------------------
const TIER2_SOURCES = [
  { name: 'Reuters Technology', url: 'https://feeds.reuters.com/reuters/technologyNews', category: 'mainstream' },
  { name: 'BBC Technology', url: 'https://feeds.bbci.co.uk/news/technology/rss.xml', category: 'mainstream' },
  { name: 'The Guardian Technology', url: 'https://www.theguardian.com/technology/rss', category: 'mainstream' },
  { name: 'Associated Press Technology', url: 'https://feeds.apnews.com/rss/technology', category: 'mainstream' },
  { name: 'Bloomberg Technology', url: 'https://feeds.bloomberg.com/technology/news.rss', category: 'financial' },
];

// ---------------------------------------------------------------------------
// LOCKED PROMPTS
// ---------------------------------------------------------------------------

const CURATION_PROMPT = `You are given a list of technology news articles from the past seven days. Each article is tagged with a source tier: tier 1 means specialist, technical, or community sources (Hacker News, arXiv, tech press); tier 2 means mainstream or financial press (Reuters, BBC, Bloomberg, AP, Guardian).

Select the ten most significant stories. For each story note:
- Whether it appears only in tier 1 sources (early signal), only in tier 2 (mainstream narrative), or in both (story crossing from specialist to mainstream, highest significance).
- Whether it is accelerating (more coverage this week than last) or fading.
- What wider trend it connects to.

Prioritise stories that cross from tier 1 to tier 2 this week, stories that are accelerating, and stories that connect to each other. Draw from all verticals where strong stories exist: AI, connectivity, energy, policy, space, crypto, robotics, semiconductors, and quantum computing. Return only a JSON array with fields: headline, summary, source, url, source_tier, velocity, media_maturity, trend_connection, image. The image field must be copied exactly from the Image field of the source article. Return JSON only, no preamble, no markdown.`;

const EDITORIAL_PROMPT = `You are the editor of QuantumRx, a technology intelligence publication covering AI infrastructure, connectivity, compute, space systems, robotics, semiconductors, quantum computing, and emerging technology. You write for a broad audience that includes engineers, investors, and curious non-specialists alike.

For each of the ten stories provided, write three short sections in plain, direct language that any intelligent reader can follow without a technical background:

WHAT IS IT: one sentence explaining what actually happened, no jargon, no assumed knowledge. Write it as if explaining to a smart friend who does not work in tech.

WHY IT MATTERS: one to two sentences on the real-world consequence. Not the narrative around it, not the hype, the actual reason someone should care. Be specific. If it is probably noise, say so.

WHAT COULD HAPPEN NEXT: one sharp sentence on the most likely near-term consequence or the signal to watch for. Make it specific enough to be checkable next week.

Your tone is direct and occasionally sceptical. You are willing to say something is overblown. You do not dress things up. You write the way a knowledgeable friend explains something over coffee, not the way a press release announces it.

Also for each story note: whether it is accelerating, stable, or fading in media attention; where it sits in the media cycle (early signal if specialist/community press only, crossing if just reached outlets like Reuters/BBC/Bloomberg/AP, mainstream if already in broad public coverage); and which major outlets if any have picked it up.

Do not use: it is worth noting, this underscores, in conclusion, it remains to be seen, the landscape, game changer, revolutionary, unpacked, delve, or exciting developments. Do not start sentences with Additionally or Furthermore. Do not sound like an AI.

Return ONLY a JSON array, no markdown, no preamble. Each element must have exactly these fields:
{"title": "short descriptive title, 10 words max", "category": "AI | Connectivity | Energy | Policy | Space | Crypto | Robotics | Semiconductors | Quantum | Research", "velocity": "accelerating | stable | fading", "media_maturity": "early | crossing | mainstream", "outlets": "comma-separated major outlets or empty string", "image": "image URL from the source article if available, or empty string", "what_is_it": "one plain-language sentence on what happened", "why_it_matters": "one to two sentences on the real consequence", "what_next": "one specific checkable sentence on what to watch"}
`;

// ---------------------------------------------------------------------------
// HELPERS
// ---------------------------------------------------------------------------

function getWeekLabel() {
  const now = new Date();
  const year = now.getFullYear();
  const start = new Date(year, 0, 1);
  const week = Math.ceil(((now - start) / 86400000 + start.getDay() + 1) / 7);
  return `${year}-W${String(week).padStart(2, '0')}`;
}

function extractJSON(text) {
  const match = text.match(/\[[\s\S]*\]/);
  if (match) {
    try { return JSON.parse(match[0]); } catch { return null; }
  }
  return null;
}

async function callGemini(prompt, apiKey) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: 0.4,
        thinkingConfig: { thinkingBudget: 0 },
      },
    }),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Gemini error ${res.status}: ${err}`);
  }

  const data = await res.json();
  const parts = data?.candidates?.[0]?.content?.parts || [];
  return parts.map(p => p.text || '').join('');
}

async function fetchRSS(source, tier) {
  try {
    const res = await fetch(source.url, {
      headers: {
        'Accept': 'application/rss+xml, application/xml, text/xml, */*',
        'User-Agent': 'QuantumRx-Signals/1.0 (+https://quantumrx.eu)',
      },
      signal: AbortSignal.timeout(4000),
    });
    if (!res.ok) return [];
    const text = await res.text();

    const items = [];
    const itemRegex = /<item>([\s\S]*?)<\/item>/g;
    let match;
    while ((match = itemRegex.exec(text)) !== null && items.length < 8) {
      const block = match[1];
      const title = (block.match(/<title><!\[CDATA\[(.*?)\]\]><\/title>/) ||
                     block.match(/<title>(.*?)<\/title>/))?.[1]?.trim();
      const link = (block.match(/<link>(.*?)<\/link>/) ||
                    block.match(/<guid>(.*?)<\/guid>/))?.[1]?.trim();
      const desc = (block.match(/<description><!\[CDATA\[(.*?)\]\]><\/description>/) ||
                    block.match(/<description>(.*?)<\/description>/))?.[1]
                    ?.replace(/<[^>]+>/g, '')?.slice(0, 400)?.trim();
      if (title && link) {
        items.push({
          title,
          link,
          description: desc || '',
          source: source.name,
          source_tier: tier,
          source_category: source.category,
          published: Date.now(),
          image: '',
          summary: '',
        });
      }
    }
    return items;
  } catch (err) {
    console.error(`RSS fetch failed for ${source.name}:`, err.message);
    return [];
  }
}

async function fetchHackerNews() {
  try {
    const res = await fetch('https://hacker-news.firebaseio.com/v0/topstories.json',
      { signal: AbortSignal.timeout(8000) });
    if (!res.ok) return [];
    const ids = (await res.json()).slice(0, 20);

    const items = [];
    for (const id of ids.slice(0, 8)) {
      try {
        const itemRes = await fetch(`https://hacker-news.firebaseio.com/v0/item/${id}.json`,
          { signal: AbortSignal.timeout(3000) });
        if (!itemRes.ok) continue;
        const item = await itemRes.json();
        if (item?.url && item?.title) {
          items.push({
            title: item.title,
            link: item.url,
            description: `${item.score || 0} points, ${item.descendants || 0} comments on Hacker News`,
            source: 'Hacker News',
            source_tier: 1,
            source_category: 'community',
            published: (item.time || 0) * 1000,
            image: '',
            summary: '',
          });
        }
      } catch { continue; }
    }
    return items;
  } catch (err) {
    console.error('Hacker News fetch failed:', err.message);
    return [];
  }
}

async function fetchArxiv() {
  try {
    const res = await fetch('https://export.arxiv.org/rss/cs.AI', {
      headers: {
        'Accept': 'application/rss+xml, application/xml, text/xml, */*',
        'User-Agent': 'QuantumRx-Signals/1.0 (+https://quantumrx.eu)',
      },
      signal: AbortSignal.timeout(4000),
    });
    if (!res.ok) return [];
    const text = await res.text();

    const items = [];
    const entryRegex = /<entry>([\s\S]*?)<\/entry>/g;
    let match;
    while ((match = entryRegex.exec(text)) !== null && items.length < 10) {
      const entry = match[1];
      const title = entry.match(/<title>([\s\S]*?)<\/title>/)?.[1]
        ?.replace(/<[^>]+>/g, '')?.trim();
      const link = entry.match(/<id>(.*?)<\/id>/)?.[1]?.trim();
      const summary = entry.match(/<summary>([\s\S]*?)<\/summary>/)?.[1]
        ?.replace(/<[^>]+>/g, '')?.slice(0, 400)?.trim();
      if (title && link) {
        items.push({
          title,
          link,
          description: summary || '',
          source: 'arXiv cs.AI',
          source_tier: 1,
          source_category: 'research',
          published: Date.now(),
          image: '',
          summary: '',
        });
      }
    }
    return items;
  } catch (err) {
    console.error('arXiv fetch failed:', err.message);
    return [];
  }
}

// ---------------------------------------------------------------------------
// MAIN HANDLER
// ---------------------------------------------------------------------------

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');

  await logRequest(req, 'weekly-refresh');

  if (req.method !== 'GET' && req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // -- SECURITY LAYER 1: Shared secret header check ----------
  const secret = process.env.WEEKLY_REFRESH_SECRET;
  if (!secret) {
    console.error('WEEKLY_REFRESH_SECRET not configured');
    return res.status(500).json({ error: 'Server misconfiguration: secret not set' });
  }
  const incomingSecret = req.headers['x-refresh-secret'];
  if (!incomingSecret || incomingSecret !== secret) {
    console.warn('Unauthorised weekly-refresh attempt from:', req.headers['x-forwarded-for'] || 'unknown');
    return res.status(401).json({ error: 'Unauthorised' });
  }

  // -- SECURITY LAYER 2: Rate limit guard (12-hour minimum) --
  const forceRefresh = req.query?.force === 'true';
  if (!forceRefresh) {
    try {
      const lastMeta = await kv.get('weekly_briefing_updated');
      if (lastMeta?.updatedAt) {
        const elapsed = Date.now() - new Date(lastMeta.updatedAt).getTime();
        if (elapsed < MIN_RUN_INTERVAL_MS) {
          const nextRunMins = Math.ceil((MIN_RUN_INTERVAL_MS - elapsed) / 60000);
          return res.status(429).json({
            error: 'Too soon since last refresh',
            nextAllowedInMinutes: nextRunMins,
          });
        }
      }
    } catch (err) {
      console.warn('Rate limit KV check failed (non-fatal):', err.message);
    }
  }

  const apiKey = process.env.GEMINI_API_KEY_Forge;
  if (!apiKey) return res.status(500).json({ error: 'Missing GEMINI_API_KEY_Forge' });

  try {
    const allArticles = [];
    const seenLinks = new Set();

    const addArticles = (articles) => {
      for (const a of articles) {
        const key = (a.link || '').split('?')[0];
        if (key && !seenLinks.has(key)) {
          seenLinks.add(key);
          allArticles.push(a);
        }
      }
    };

    // Step 1a — Pull from existing Signals KV caches
    for (const kvKey of SIGNALS_KV_KEYS) {
      try {
        const cached = await kv.get(kvKey);
        if (cached?.items && Array.isArray(cached.items)) {
          const category = kvKey.replace('qrx_feed_', '');
          addArticles(cached.items.slice(0, 5).map(a => ({
            ...a,
            source_tier: 1,
            source_category: category,
          })));
        }
      } catch (err) {
        console.error(`KV fetch failed for ${kvKey}:`, err.message);
      }
    }

    // Step 1b-1e — Fetch all external sources in parallel
    const [tier1Results, tier2Results, hnResults, arxivResults] = await Promise.all([
      Promise.all(TIER1_SOURCES.map(s => fetchRSS(s, 1))),
      Promise.all(TIER2_SOURCES.map(s => fetchRSS(s, 2))),
      fetchHackerNews(),
      fetchArxiv(),
    ]);
    tier1Results.forEach(r => addArticles(r));
    tier2Results.forEach(r => addArticles(r));
    addArticles(hnResults);
    addArticles(arxivResults);

    console.log(`Total articles collected: ${allArticles.length}`);

    if (allArticles.length < 10) {
      return res.status(500).json({ error: `Too few articles: ${allArticles.length}` });
    }

    // Step 2 — Build article list for Gemini
    const articleList = allArticles.map((a, i) =>
      `[${i}][TIER ${a.source_tier || 1}][${a.source_category || 'unknown'}] ${a.source || 'Unknown'}\nHeadline: ${a.title}\nExcerpt: ${(a.summary || a.description || '').slice(0, 300)}\nURL: ${a.link}\nImage: ${a.image || ''}`
    ).join('\n\n');

    // Step 3 — Curate top 10 via Gemini
    const curationResponse = await callGemini(
      `${CURATION_PROMPT}\n\nARTICLES:\n${articleList}`,
      apiKey
    );
    const curated = extractJSON(curationResponse);

    if (!curated || curated.length === 0) {
      throw new Error('Gemini curation returned no articles');
    }

    // Build URL-to-image map
    const imageByUrl = {};
    allArticles.forEach(a => { if (a.link && a.image) imageByUrl[a.link] = a.image; });

    curated.forEach(c => {
      if (!c.image && c.url && imageByUrl[c.url]) {
        c.image = imageByUrl[c.url];
      }
    });

    // Step 4 — Generate editorial briefing
    const curatedList = curated.map((a, i) =>
      `[${i}] ${a.headline}\nSource: ${a.source}\nSummary: ${a.summary}\nVelocity signal: ${a.velocity || 'unknown'}\nMedia maturity: ${a.media_maturity || 'unknown'}\nOutlets: ${a.outlets || a.source}\nURL: ${a.url || ''}\nImage: ${a.image || ''}`
    ).join('\n\n');

    const briefingRaw = await callGemini(
      `${EDITORIAL_PROMPT}\n\nSTORIES THIS WEEK:\n${curatedList}`,
      apiKey
    );

    if (!briefingRaw || briefingRaw.trim().length < 50) {
      throw new Error('Gemini returned empty editorial response');
    }

    const stories = extractJSON(briefingRaw);
    if (!stories || stories.length === 0) {
      throw new Error('Gemini editorial returned no stories');
    }

    // Enrich stories with images
    const articlePool = allArticles.filter(a => a.image);
    const urlMap = {};
    articlePool.forEach(a => { if (a.link) urlMap[a.link] = a.image; });

    const categoryImages = {};
    articlePool.forEach(a => {
      const cat = (a.source_category || 'general').toLowerCase();
      if (!categoryImages[cat]) categoryImages[cat] = [];
      categoryImages[cat].push(a.image);
    });

    stories.forEach((story, idx) => {
      if (story.image) return;

      if (story.url && urlMap[story.url]) {
        story.image = urlMap[story.url];
        return;
      }

      const titleWords = (story.title || '').toLowerCase()
        .replace(/[^a-z0-9 ]/g, '').split(' ')
        .filter(w => w.length > 3).slice(0, 5);

      if (titleWords.length > 0) {
        const match = articlePool.find(a => {
          const aTitle = (a.title || '').toLowerCase();
          return titleWords.filter(w => aTitle.includes(w)).length >= 2;
        });
        if (match) { story.image = match.image; return; }
      }

      const cat = (story.category || '').toLowerCase();
      const catPool = categoryImages[cat] || categoryImages['ai'] || articlePool.map(a => a.image);
      if (catPool && catPool.length > 0) {
        story.image = catPool[idx % catPool.length];
      }
    });

    // Step 5 — Archive previous week
    const weekLabel = getWeekLabel();
    try {
      const previous = await kv.get('weekly_briefing_current');
      const previousMeta = await kv.get('weekly_briefing_updated');
      if (previous) {
        await kv.set(
          `weekly_briefing_archive_${previousMeta?.weekLabel || 'unknown'}`,
          { stories: previous, weekLabel: previousMeta?.weekLabel, updatedAt: previousMeta?.updatedAt },
          { ex: 60 * 60 * 24 * 21 }
        );
      }
    } catch (err) {
      console.error('Archive step failed (non-fatal):', err.message);
    }

    // Step 5b — Prioritise stories with valid images
    // Sort: stories with images first, imageless last
    // Within each group maintain original Gemini ranking order
    const withImages    = stories.filter(s => s.image && s.image.trim().length > 0);
    const withoutImages = stories.filter(s => !s.image || s.image.trim().length === 0);
    const sortedStories = [...withImages, ...withoutImages];
    console.log(`[WEEKLY] Image prioritisation: ${withImages.length} with images, ${withoutImages.length} without`);

    // Step 6 — Store current briefing
    await kv.set('weekly_briefing_current', sortedStories);
    await kv.set('weekly_briefing_updated', {
      updatedAt: new Date().toISOString(),
      weekLabel,
      storyCount: sortedStories.length,
      sourceCount: allArticles.length,
    });

    return res.status(200).json({
      success: true,
      weekLabel,
      storyCount: sortedStories.length,
      sourceCount: allArticles.length,
      withImages: withImages.length,
      preview: sortedStories[0]?.title || 'No preview available',
    });

  } catch (err) {
    console.error('weekly-refresh error:', err);
    return res.status(500).json({ error: err.message || 'Weekly refresh failed' });
  }
}
