// /api/generate
//
// Core QRx NFT Forge generation endpoint.
// 1. Checks Q-Sentinel threat_action for the requesting IP, blocks if flagged
// 2. Validates the licence key is still good (re-checks LS, defence in depth)
// 3. Builds the prompt: locked formula + theme + mood + palette + gender + random scene
// 4. Calls Nano Banana 2 (Gemini 2.5/2.0 Flash Image) to generate the card
// 5. Stores the result to Vercel Blob
// 6. Atomically increments the Vercel KV issue counter (forge_counter)
// 7. Returns the public image URL + issue number to the frontend
//
// FIX (2026-06-30): free-code per-IP guard was a separate get-then-set, vulnerable
// to a race condition where concurrent requests from the same IP could all pass
// the check before any of them finished writing the lock. Replaced with an atomic
// kv.set(..., { nx: true }) so only one request can ever claim the IP slot.
//
// Also added Sentinel threat_action check at the top of the handler — IPs already
// blocked by Q-Sentinel (e.g. for prompt injection on /api/chat) are now blocked
// here too, rather than only on the chat endpoint.
//
// Env vars required (set in Vercel project settings):
//   GEMINI_API_KEY_Forge       - Google AI Studio / Gemini API key, dedicated to the NFT forge image generation
//   BLOB_READ_WRITE_TOKEN     - Vercel Blob read/write token (auto-set if Blob store is linked)
//   KV_REST_API_URL           - Vercel KV REST URL (auto-set if KV store is linked)
//   KV_REST_API_TOKEN         - Vercel KV REST token (auto-set if KV store is linked)
//   LEMONSQUEEZY_API_KEY      - optional, only needed if re-validating against LS here too
//
// Expected request body: { theme, mood, palette, gender, licenceKey }
// Expected response: { imageUrl, issue, name } or { error }

import { put } from '@vercel/blob';
import { kv } from '@vercel/kv';
import { logRequest } from './request-logger.js';

const SCENES = {
  MECHA: ['raining neon city', 'volcanic crater battlefield', 'shattered moon orbit', 'arctic ice plains', 'jungle ruins', 'burning skyscrapers', 'desert canyon', 'space station debris', 'interdimensional rift', 'coral reef abyss'],
  PORTRAIT: ['holographic gallery', 'neon mirror room', 'cosmic void', 'crystal palace', 'misty mountaintop', 'underwater cathedral', 'burning library', 'frozen throne room', 'shadow dimension', 'golden sanctum'],
  STEAMPUNK: ['clockwork factory', 'airship graveyard', 'Victorian rooftop', 'underground coal mine', 'brass cathedral', 'fog harbour', 'mechanical desert', 'copper canyon', "inventor's workshop", 'steam-powered city'],
  FANTASY: ['enchanted forest', 'dragon mountain', 'cursed swamp', 'crystal cavern', 'sky fortress', 'shadow realm', 'frozen tundra temple', 'sunken library', 'volcanic shrine', 'ancient battlefield'],
  'SCI-FI': ['deep space nebula', 'alien planet surface', 'orbital station', 'quantum laboratory', 'crashed starship', 'binary star system', 'terraformed Mars', 'wormhole gateway', 'cyberpunk megacity', 'dark matter void'],
  PSYCHIC: ['neon Tokyo alley', 'collapsing skyscraper', 'psychic storm arena', 'fractured cityscape', 'underground bunker', 'rooftop in monsoon', 'burning dojo', 'flooded subway', 'ghost market', 'electric slums'],
  COMMANDER: ['space carrier bridge', 'asteroid field', 'moon base siege', 'supernova explosion', 'planetary ring battle', 'black hole approach', 'star destroyer graveyard', 'comet trail', 'nebula storm', 'galactic core'],
  SORCERER: ['skull throne chamber', 'cursed catacombs', 'dark cathedral', 'shadow forest', 'bone arena', 'volcanic temple', 'haunted library', 'demon portal', 'eclipse ceremony', 'abyssal gateway'],
  CAPTAIN: ['thunderstorm over ocean', 'airship fleet battle', 'volcanic island', 'arctic iceberg', 'lightning-struck lighthouse', 'enemy fleet engagement', 'fog-bound harbour', 'hurricane eye', 'cliff-side fortress', 'burning port'],
  LUNAR: ['moon landing site', 'lunar crater', 'Earth rise', 'dark side of moon', 'lunar base', 'meteor storm', 'moonquake', 'ancient lunar ruins', 'rocket launch pad', 'lunar eclipse'],
};

const THEME_DETAILS = {
  MECHA: 'wearing mecha armor with glowing thrusters, cyberpunk mechanical suit',
  PORTRAIT: 'close-up holographic portrait style, rainbow holographic sheen',
  STEAMPUNK: 'wearing brass and copper steampunk armor, holding a lantern',
  FANTASY: 'wielding a runic sword and enchanted shield, mystical warrior armor',
  'SCI-FI': 'cybernetic eye implant, holographic wrist display, sci-fi bodysuit',
  PSYCHIC: 'crackling lightning aura, torn streetwear jacket, glowing eyes',
  COMMANDER: 'wearing a starfighter pilot helmet, seated in a cockpit',
  SORCERER: 'dark sorcerer robes, holding an ancient grimoire, purple flame aura',
  CAPTAIN: 'wearing a top hat and brass goggles, airship captain coat',
  LUNAR: 'wearing a fictional astronaut spacesuit with an original mission emblem, lunar surface reflection in visor',
};

const THEME_BORDERS = {
  MECHA: 'industrial mechanical border with rivets and warning stripes',
  PORTRAIT: 'holographic rainbow foil border',
  STEAMPUNK: 'engraved brass and gear-pattern border',
  FANTASY: 'carved stone and vine border with glowing runes',
  'SCI-FI': 'sleek chrome and circuit-pattern border',
  PSYCHIC: 'neon electric border with lightning cracks',
  COMMANDER: 'military starfighter HUD-style border',
  SORCERER: 'black bone and obsidian border with purple glow',
  CAPTAIN: 'aged brass and rope-trim nautical border',
  LUNAR: 'fictional space-mission style border with star field',
};

const MOOD_MODIFIERS = {
  FIERCE: 'intense fierce expression, aggressive stance',
  MYSTIC: 'mysterious mystical aura, enigmatic expression',
  PLAYFUL: 'playful smug grin, lighthearted pose',
  WISE: 'wise calm expression, composed dignified stance',
  DARK: 'dark brooding expression, ominous shadows',
  ETHEREAL: 'ethereal dreamlike glow, otherworldly presence',
};

const PALETTE_MODIFIERS = {
  WARM: 'warm color palette, oranges and reds',
  COOL: 'cool color palette, blues and teals',
  NEON: 'vibrant neon color palette, electric saturated colors',
  PASTEL: 'soft pastel color palette, muted gentle tones',
  MONO: 'single dominant color hue throughout, high contrast, not black-and-white or greyscale',
  NATURAL: 'natural earthy color palette, organic tones',
};

function buildPrompt({ theme, mood, palette, gender, issue, scene }) {
  const themeDetail = THEME_DETAILS[theme] || '';
  const themeBorder = THEME_BORDERS[theme] || 'ornate card border';
  const moodMod = MOOD_MODIFIERS[mood] || '';
  const paletteMod = PALETTE_MODIFIERS[palette] || '';
  const genderNote = gender === 'FEM' ? 'feminine features, ' : '';

  return [
    `Pepe the frog character with distinctive sad-smug expression, bulging eyes, wide mouth, classic Pepe green skin tone,`,
    `${genderNote}${themeDetail}, set in a ${scene}, ${moodMod}, ${paletteMod},`,
    `full bleed vertical card format, ${themeBorder} integrated into artwork,`,
    `title banner at top, series number bottom right, Series 1 #${issue}/1000, Limited Edition.`,
    `Do not include any real-world national flags, real countries, real brand logos, or real organization insignia anywhere in the image; all patches, badges, and emblems should be original fictional designs only.`,
  ].join(' ');
}

async function getNextIssueNumber() {
  const next = await kv.incr('forge_counter');
  const actual = next < 100 ? next + 99 : next;
  return String(actual).padStart(4, '0');
}

async function callNanoBanana(prompt) {
  const apiKey = process.env.GEMINI_API_KEY_Forge;
  if (!apiKey) throw new Error('GEMINI_API_KEY_Forge not configured');

  const model = 'gemini-3.1-flash-image';
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: {
        responseModalities: ['IMAGE', 'TEXT'],
      },
    }),
  });

  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`Gemini API error ${response.status}: ${errText}`);
  }

  const data = await response.json();
  const parts = data?.candidates?.[0]?.content?.parts || [];
  const imagePart = parts.find(p => p.inlineData && p.inlineData.data);

  if (!imagePart) throw new Error('No image returned from Gemini API');

  const mimeType = imagePart.inlineData.mimeType || 'image/png';
  const buffer = Buffer.from(imagePart.inlineData.data, 'base64');
  return { buffer, mimeType };
}

async function getSentinelAction(ip) {
  const kvUrl = process.env.UPSTASH_REDIS_REST_URL;
  const kvToken = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!kvUrl || !kvToken) return null;
  try {
    const res = await fetch(
      // Raw ip — must match writeAutoBlock() in request-logger.js. Encoding
      // here breaks the key match for IPv6 addresses.
      `${kvUrl}/get/threat_action:${ip}`,
      { headers: { Authorization: `Bearer ${kvToken}` }, signal: AbortSignal.timeout(800) }
    );
    if (!res.ok) return null;
    const data = await res.json();
    if (!data.result) return null;
    let parsed;
    try {
      parsed = JSON.parse(data.result);
    } catch {
      return null;
    }
    // Handle both the clean shape and the double-wrapped shape seen in manual writes
    if (parsed.action) return parsed.action;
    if (parsed.value) {
      try {
        const inner = JSON.parse(parsed.value);
        return inner.action || null;
      } catch {
        return null;
      }
    }
    return null;
  } catch { return null; }
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // Q-Sentinel threat check + detection logging
  const ip = await logRequest(req, {
    checkBody: true,
    expectedFields: ['theme', 'mood', 'palette', 'licenceKey'],
  });

  // Block IPs already flagged by Q-Sentinel, regardless of which endpoint flagged them
  const sentinelAction = await getSentinelAction(ip);
  if (sentinelAction === 'block') {
    return res.status(403).json({ error: 'Access temporarily restricted from this connection.' });
  }
  // No 'honeypot' branch here: middleware.js already intercepts every
  // /api/* request at the edge and answers honeypot-flagged IPs directly
  // with its own canned response (see honeypotResponse() in middleware.js) —
  // this handler is never invoked for those requests, so any per-endpoint
  // honeypot handling here would be unreachable.

  const { theme, mood, palette, gender, licenceKey } = req.body || {};

  if (!theme || !mood || !palette || !licenceKey) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  const themeKey = theme.toUpperCase();
  if (!SCENES[themeKey]) {
    return res.status(400).json({ error: 'Unknown theme' });
  }

  const FREE_CODE = 'PEPEFREE';
  const FREE_CODE_LIMIT = 100;
  const isFreeCodeAttempt = licenceKey.trim().toUpperCase() === FREE_CODE;

  try {
    if (isFreeCodeAttempt) {
      const ipKey = `forge_free_ip:${ip}`;

      // ATOMIC claim — nx: true means "only set if key does not already exist".
      // Returns null if the key was already there, meaning someone else claimed
      // it first. This closes the race condition where concurrent requests from
      // the same IP could all read "not redeemed" before any write landed.
      const claimed = await kv.set(ipKey, '1', { ex: 60 * 60 * 24 * 30, nx: true });
      if (!claimed) {
        return res.status(403).json({ error: 'Free code already used from this connection. Grab a licence key instead.' });
      }

      const usedCount = await kv.incr('forge_free_used');
      if (usedCount > FREE_CODE_LIMIT) {
        return res.status(403).json({ error: 'Free codes for this drop have all been claimed. Grab a licence key instead.' });
      }
    } else {
      const lsRes = await fetch('https://api.lemonsqueezy.com/v1/licenses/activate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' },
        body: new URLSearchParams({
          license_key: licenceKey.trim(),
          instance_name: 'qrx-forge-generation-' + Date.now(),
        }),
      });
      const lsData = await lsRes.json();
      if (!lsRes.ok || !lsData.activated) {
        return res.status(403).json({ error: lsData.error || 'Licence key already used or invalid' });
      }
    }

    const issue = await getNextIssueNumber();
    const scenePool = SCENES[themeKey];
    const scene = scenePool[Math.floor(Math.random() * scenePool.length)];

    const prompt = buildPrompt({
      theme: themeKey,
      mood: mood.toUpperCase(),
      palette: palette.toUpperCase(),
      gender,
      issue,
      scene,
    });

    const { buffer, mimeType } = await callNanoBanana(prompt);
    const ext = mimeType.includes('png') ? 'png' : 'jpg';
    const filename = `forge/${issue}-${themeKey.toLowerCase()}-${Date.now()}.${ext}`;

    const blob = await put(filename, buffer, {
      access: 'public',
      contentType: mimeType,
    });

    const name = `${themeKey.charAt(0) + themeKey.slice(1).toLowerCase()} Pepe`;

    return res.status(200).json({
      imageUrl: blob.url,
      issue,
      name,
      scene,
    });

  } catch (err) {
    console.error('generate error:', err);
    return res.status(500).json({ error: 'Generation failed, please try again' });
  }
}
