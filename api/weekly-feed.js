// /api/weekly-feed
//
// Serves the current weekly briefing and last 3 archived editions
// to the this-week-in-tech Ghost card frontend.
//
// Current briefing is stored as a JSON array of story objects, each with:
//   title, category, velocity, media_maturity, outlets,
//   what_is_it, why_it_matters, what_next
//
// Returns:
//   {
//     current: { stories: [...], updatedAt, weekLabel },
//     archive: [ { weekLabel, stories: [...], updatedAt } ]
//   }

import { kv } from '@vercel/kv';

const CDN_CACHE_SECONDS = 300;
const STALE_REVALIDATE_SECONDS = 60;

export default async function handler(req, res) {
  // CORS — allow quantumrx.eu Ghost pages to fetch from this Vercel endpoint
  res.setHeader('Access-Control-Allow-Origin', 'https://www.quantumrx.eu');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const stories = await kv.get('weekly_briefing_current');
    const meta = await kv.get('weekly_briefing_updated');

    if (!stories || !Array.isArray(stories) || stories.length === 0) {
      res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');
      return res.status(200).json({
        current: null,
        archive: [],
        message: 'Briefing updating, check back shortly',
      });
    }

    const etag = meta?.updatedAt
      ? `"${Buffer.from(meta.updatedAt).toString('base64')}"`
      : null;

    res.setHeader(
      'Cache-Control',
      `public, s-maxage=${CDN_CACHE_SECONDS}, stale-while-revalidate=${STALE_REVALIDATE_SECONDS}`
    );
    if (etag) res.setHeader('ETag', etag);

    if (etag && req.headers['if-none-match'] === etag) {
      return res.status(304).end();
    }

    // Fetch last 3 archived editions
    const archive = [];
    const now = new Date();
    for (let i = 1; i <= 3; i++) {
      const d = new Date(now);
      d.setDate(d.getDate() - i * 7);
      const year = d.getFullYear();
      const start = new Date(year, 0, 1);
      const week = Math.ceil(((d - start) / 86400000 + start.getDay() + 1) / 7);
      const key = `weekly_briefing_archive_${year}-W${String(week).padStart(2, '0')}`;
      try {
        const archived = await kv.get(key);
        if (archived) archive.push(archived);
      } catch { /* archive entry doesn't exist yet */ }
    }

    return res.status(200).json({
      current: {
        stories,
        updatedAt: meta?.updatedAt || null,
        weekLabel: meta?.weekLabel || null,
      },
      archive,
    });

  } catch (err) {
    console.error('weekly-feed error:', err);
    res.setHeader('Cache-Control', 'no-store');
    return res.status(500).json({ error: 'Failed to fetch weekly briefing' });
  }
}
