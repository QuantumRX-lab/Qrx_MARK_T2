// /api/generate
//
// Core QRx NFT Forge generation endpoint.
// 1. Validates the licence key is still good (re-checks LS, defence in depth)
// 2. Builds the prompt: locked formula + theme + mood + palette + gender + random scene
// 3. Calls Nano Banana 2 (Gemini 2.5/2.0 Flash Image) to generate the card
// 4. Stores the result to Vercel Blob
// 5. Atomically increments the Vercel KV issue counter (forge_counter)
// 6. Returns the public image URL + issue number to the frontend
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

// ─────────────────────────────────────────────────────────────
// BACKGROUND SCENES — 10 per theme, picked at random per generation
// ─────────────────────────────────────────────────────────────
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

// Theme-specific costume/prop details, matching the founding-set art direction.
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

  // Locked prompt formula (do not alter structure without re-testing card output quality)
  return [
    `Pepe the frog character with distinctive sad-smug expression, bulging eyes, wide mouth, classic Pepe green skin tone,`,
    `${genderNote}${themeDetail}, set in a ${scene}, ${moodMod}, ${paletteMod},`,
    `full bleed vertical card format, ${themeBorder} integrated into artwork,`,
    `title banner at top, series number bottom right, Series 1 #${issue}/1000, Limited Edition.`,
    `Do not include any real-world national flags, real countries, real brand logos, or real organization insignia anywhere in the image; all patches, badges, and emblems should be original fictional designs only.`,
  ].join(' ');
}

async function getNextIssueNumber() {
  // Public forge issue numbers start at #0100 (0000-0010 reserved for founding set,
  // 0011-0099 reserved/unused). forge_counter is atomically incremented in Vercel KV.
  const next = await kv.incr('forge_counter');
  const actual = next < 100 ? next + 99 : next; // safety floor in case counter wasn't pre-seeded to 99
  return String(actual).padStart(4, '0');
}

async function callNanoBanana(prompt) {
  const apiKey = process.env.GEMINI_API_KEY_Forge;
  if (!apiKey) throw new Error('GEMINI_API_KEY_Forge not configured');

  // Nano Banana 2 image generation model, confirmed directly from Google AI Studio's
  // "Get code" sample on 2026-06-16. Google flags this model as not yet stable /
  // not guaranteed production-ready — acceptable risk for this low-stakes product.
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

  // Image comes back as inline base64 data in the response parts.
  const parts = data?.candidates?.[0]?.content?.parts || [];
  const imagePart = parts.find(p => p.inlineData && p.inlineData.data);

  if (!imagePart) {
    throw new Error('No image returned from Gemini API');
  }

  const mimeType = imagePart.inlineData.mimeType || 'image/png';
  const buffer = Buffer.from(imagePart.inlineData.data, 'base64');
  return { buffer, mimeType };
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { theme, mood, palette, gender, licenceKey } = req.body || {};

  if (!theme || !mood || !palette || !licenceKey) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  const themeKey = theme.toUpperCase();
  if (!SCENES[themeKey]) {
    return res.status(400).json({ error: 'Unknown theme' });
  }

  // ─────────────────────────────────────────────────────────────
  // FREE CODE — a shared, capped giveaway code that bypasses Lemon
  // Squeezy checkout entirely. Anyone can paste PEPEFREE into the
  // licence key field; the first 100 redemptions succeed, the 101st
  // onward are rejected. Cap is enforced atomically via a dedicated
  // KV counter (forge_free_used), separate from the paid-key path and
  // separate from forge_counter (issue numbers). This is NOT a Lemon
  // Squeezy discount code (like FORGE100) — no LS license key is
  // issued or activated for this path, so it must never be treated
  // as a real licence key anywhere else in the app.
  // ─────────────────────────────────────────────────────────────
  const FREE_CODE = 'PEPEFREE';
  const FREE_CODE_LIMIT = 100;
  const isFreeCodeAttempt = licenceKey.trim().toUpperCase() === FREE_CODE;

  try {
    if (isFreeCodeAttempt) {
      // Atomic increment + check. kv.incr is atomic, so concurrent
      // requests can't both slip in under the cap.
      const usedCount = await kv.incr('forge_free_used');
      if (usedCount > FREE_CODE_LIMIT) {
        return res.status(403).json({ error: 'Free codes for this drop have all been claimed. Grab a licence key instead.' });
      }
      // Free code accepted — skip Lemon Squeezy activation entirely.
    } else {
      // This is now the ONLY place the licence key is actually activated/consumed.
      // /api/validate-key (called when the user types the key) is non-consuming and
      // only gives tentative frontend feedback. Calling /activate here both confirms
      // the key is genuinely usable AND enforces the one-time-use limit: if this key
      // was already activated by a prior generation, LS will correctly reject this
      // second /activate attempt once activation_usage reaches activation_limit.
      // Docs: https://docs.lemonsqueezy.com/api/license-api/activate-license-key
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
