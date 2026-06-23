// /api/generate-lotm
//
// Lord of the Memes Forge generation endpoint.
// 1. Activates the licence key with Lemon Squeezy (the ONLY consuming check —
//    see /api/validate-key for why activation is deferred to generate-time)
// 2. Rolls a weighted rarity tier server-side (cannot be manipulated by the client)
// 3. Builds the prompt: locked formula + character archetype + flavor + mood + palette
// 4. Calls the Gemini image model to generate the card
// 5. Stores the result to Vercel Blob
// 6. Atomically increments the Vercel KV issue counter (lotm_counter)
// 7. Returns the public image URL, issue number, and rarity tier to the frontend
//
// Env vars required (set in Vercel project settings):
//   GEMINI_API_KEY_Forge      - Google AI Studio / Gemini API key
//   BLOB_READ_WRITE_TOKEN     - Vercel Blob (auto-set if Blob store is linked)
//   KV_REST_API_URL           - Vercel KV REST URL (auto-set if KV store is linked)
//   KV_REST_API_TOKEN         - Vercel KV REST token (auto-set if KV store is linked)
//
// Expected request body: { character, flavor, mood, palette, licenceKey }
// Expected response: { imageUrl, issue, name, rarity } or { error }

import { put } from '@vercel/blob';
import { kv } from '@vercel/kv';
import { logRequest } from './request-logger.js';

const CHARACTERS = {
  FROG: {
    name: 'The Frog',
    title: 'The Frog, the Smug Sage',
    detail: 'a chunky green cartoon frog with huge bulging eyes, a wide flat downturned mouth in a classic smug-sad deadpan stare, thick bold black outlines, flat saturated colors, exaggerated meme-comic proportions',
    border: 'ornate gold-filigree border with carved lily-pad and reed motifs, inset emerald gemstones catching light',
  },
  SHIBA: {
    name: 'The Shiba',
    title: 'The Shiba, the Joyful Herald',
    detail: 'a chubby tan and white Shiba Inu with an enormous goofy open-mouthed grin, tongue flopping out, tiny excited squinting eyes, thick bold black outlines, flat saturated colors, exaggerated meme-comic proportions',
    border: 'ornate gold-filigree border with carved paw-print and sunburst motifs, inset citrine gemstones catching light',
  },
  APE: {
    name: 'The Ape',
    title: 'The Ape, the Jungle Lord',
    detail: 'a hulking muscular cartoon gorilla with a flat unimpressed deadpan stare, jaw set, thick bold black outlines, flat saturated colors, exaggerated oversized meme-comic proportions',
    border: 'ornate gold-filigree border with carved jungle-vine and gold-leaf motifs, inset emerald gemstones',
  },
  WOJAK: {
    name: 'The Wojak',
    title: 'The Wojak, the Sorrowful',
    detail: 'a minimalist bald line-art human head, blank thousand-yard-stare eyes with a faint glowing rim of light, a single flat downturned mouth line, pale flesh tone, ultra-thin meme sketch outlines on plain background, deliberately crude unfinished feel',
    border: 'dark forged-iron border with sharp polished rivets catching light and worn leather corner trim',
  },
  CHAD: {
    name: 'The Chad',
    title: 'The Chad, the Unshaken',
    detail: 'a square-jawed minimalist line-art human head with a comically oversized jaw, tiny dot eyes, an extremely wide confident smug grin showing teeth, thick bold meme sketch outlines, exaggerated chiseled proportions',
    border: 'ornate gold-filigree border with carved laurel-wreath motifs catching dramatic light, inset citrine gemstones',
  },
  CAT: {
    name: 'The Cat',
    title: 'The Cat, the Aloof Oracle',
    detail: 'a sleek grey cartoon cat with half-closed unimpressed smug eyes and a flat tight-lipped smirk, thick bold black outlines, flat saturated colors, exaggerated meme-comic proportions',
    border: 'ornate gold-filigree border with carved crescent-moon and yarn-spiral motifs, inset amethyst gemstones',
  },
  ROBOT: {
    name: 'The Unit',
    title: 'The Unit, the Unbroken',
    detail: 'a blocky rounded cartoon robot with two huge glowing circular circuit eyes and a flat slot mouth, thick bold black outlines, flat saturated metallic colors, exaggerated chunky meme-comic proportions',
    border: 'ornate gold-filigree border fused with sleek chrome circuit-pattern inlay, inset sapphire gemstones',
  },
  ASTRONAUT: {
    name: 'The Astronaut',
    title: 'The Astronaut, the Far-Wanderer',
    detail: 'a chunky cartoon astronaut in an oversized rounded white spacesuit, a huge reflective dark visor hiding the face, thick bold black outlines, flat saturated colors, exaggerated bobblehead meme-comic proportions',
    border: 'ornate gold-filigree border with carved star-field and comet-trail motifs, inset sapphire gemstones',
  },
  TROLL: {
    name: 'The Troll',
    title: 'The Troll, the Mischief-Born',
    detail: 'a crude rage-comic troll face with a huge jagged gap-toothed grin stretching ear to ear, tiny beady eyes, deliberately ugly scribbly meme-comic line art, flat off-white fill, classic forum rage-face energy',
    border: 'ornate gold-filigree border with carved jagged-flame and scribble-rune motifs, inset garnet gemstones',
  },
  CLOWN: {
    name: 'The Clown',
    title: 'The Clown, the Honkmaster',
    detail: 'a cartoon clown with a huge red ball nose, wild frizzy colorful hair, an oversized painted grin stretching across the whole face, thick bold black outlines, flat saturated colors, exaggerated meme-comic proportions',
    border: 'ornate gold-filigree border with carved carnival-striped and jester-bell motifs, inset ruby gemstones',
  },
};

const FLAVORS = {
  BULL_MARKET: { label: 'Bull Market', detail: 'surrounded by green upward arrows and bull horns motif, triumphant pose' },
  BEAR_MARKET: { label: 'Bear Market', detail: 'surrounded by red downward arrows, weary defiant pose' },
  TO_THE_MOON: { label: 'To The Moon', detail: 'riding or standing beside a cartoon rocket blasting toward a crescent moon' },
  DIAMOND_HANDS: { label: 'Diamond Hands', detail: 'holding up a glowing diamond-shaped gem with both hands, resolute pose' },
  PAPER_HANDS: { label: 'Paper Hands', detail: 'comically crumpling under a pile of falling paper, exaggerated panic' },
  AI_UPRISING: { label: 'AI Uprising', detail: 'surrounded by glowing holographic circuit patterns and floating data fragments' },
  SPACE_MISSION: { label: 'Space Mission', detail: 'standing on a cratered alien surface with a distant ringed planet in the sky' },
  MARKET_CRASH: { label: 'Market Crash', detail: 'standing amid cartoon shattered glass and falling red chart lines' },
  HODL: { label: 'HODL', detail: 'gripping a glowing anchor chained to the ground, immovable stance' },
  SHORT_SQUEEZE: { label: 'Short Squeeze', detail: 'flexing triumphantly as cartoon enemies are squeezed and flattened in the background' },
};

const MOOD_MODIFIERS = {
  FIERCE: 'eyes burning with fierce intensity, piercing gaze, rigid tense posture, clenched fists',
  MYSTIC: 'eyes glowing with a mysterious mystical light, enigmatic aura, faint swirling energy around the figure',
  PLAYFUL: 'eyes glinting with mischief, relaxed loose posture, lighthearted energy',
  WISE: 'calm steady gaze, composed dignified posture, serene unhurried presence',
  DARK: 'eyes shadowed and brooding, ominous atmosphere, dramatic low lighting',
  ETHEREAL: 'eyes softly glowing, dreamlike translucent aura, otherworldly weightless presence',
};

const PALETTE_MODIFIERS = {
  WARM: 'warm color palette, oranges and reds',
  COOL: 'cool color palette, blues and teals',
  NEON: 'vibrant neon color palette, electric saturated colors',
  PASTEL: 'soft pastel color palette, muted gentle tones',
  MONO: 'single dominant color hue throughout, high contrast, not black-and-white or greyscale',
  NATURAL: 'natural earthy color palette, organic tones',
};

const RARITY_TIERS = [
  { label: 'COMMON', weight: 60, glow: 'plain matte card finish, no special glow, natural daylight', powerMin: 40, powerMax: 59 },
  { label: 'RARE', weight: 25, glow: 'polished silver foil shimmer across the border catching crisp cold light', powerMin: 60, powerMax: 74 },
  { label: 'EPIC', weight: 12, glow: 'vivid holographic foil glow blazing across the entire border, intense saturated light spilling from the gemstone insets', powerMin: 75, powerMax: 89 },
  { label: 'LEGENDARY', weight: 3, glow: 'intense radiant golden holographic glow erupting from the entire card, dramatic blazing light and faint floating ember particles drifting from the border', powerMin: 90, powerMax: 99 },
];

function rollRarity() {
  const total = RARITY_TIERS.reduce((sum, t) => sum + t.weight, 0);
  let roll = Math.random() * total;
  for (const tier of RARITY_TIERS) {
    if (roll < tier.weight) return tier;
    roll -= tier.weight;
  }
  return RARITY_TIERS[0];
}

function rollPowerRating(tier) {
  return Math.floor(Math.random() * (tier.powerMax - tier.powerMin + 1)) + tier.powerMin;
}

function buildPrompt({ character, flavor, mood, palette, issue, rarity, powerRating }) {
  const char = CHARACTERS[character];
  const flav = FLAVORS[flavor];
  const moodMod = MOOD_MODIFIERS[mood] || '';
  const paletteMod = PALETTE_MODIFIERS[palette] || '';

  return [
    `${char.detail}.`,
    `Bold internet meme illustration style throughout, not realistic, not painterly — thick clean outlines and flat color fills like a classic viral meme character.`,
    `Mood layer (does not change the character's face or mouth, only adds atmosphere and posture): ${flav.detail}, ${moodMod}, ${paletteMod}. The character's core facial expression and mood described above must remain fully visible and dominant no matter what flavor props, symbols, or background elements are added — if the flavor and mood pull in different emotional directions, the character's expression wins; flavor elements are set-dressing around the character, never a replacement for it.`,
    `STRICT TRADING CARD LAYOUT: full bleed vertical trading card, character art fills the entire frame edge to edge, ${char.border} as a single thin decorative frame around the outer edge only — one continuous border, not a nested double border with separate inner and outer panels. The border has ornate gold or metallic trim detailing running along its full length, with small decorative flourish emblems in each of the four corners and a small circular crest or medallion icon centered at the very top of the border, above the title banner. Rarity finish: ${rarity.glow}. Exactly ONE title banner bar, placed at the very top of the card only, reading "${char.title.toUpperCase()}" in bold meme-style lettering — this title must appear this one time only and nowhere else on the card (no repeated title inside the art area, no second banner). Directly beneath the title banner, a smaller subtitle banner reading "${rarity.label}" in bold meme-style lettering. Small series number "#${issue}/9999" in the bottom corner. In the opposite bottom corner, a small stat box reading "PWR ${powerRating}" in bold meme-style lettering, styled to match the series number tag. Along the very bottom edge of the border, a thin glowing circuit-line or wire trace detail runs horizontally, with "QRX FORGE" worked into it in small glowing tech-style lettering as if etched into the circuit trace itself — subtle, decorative, like a manufacturer's mark inlaid into the card border, not competing with the subtitle banner or power stat. This must look like a real trading card, not a poster or illustration without card elements. Lord of the Memes brand.`,
    `Render this as a flat, front-facing digital scan or print mockup of the card graphic only — perfectly flat, no perspective, no tilt, no shadow, no surface beneath it. Do NOT include a hand, fingers, person, or any human body part holding, presenting, or framing the card. Do NOT render this as a photograph of a physical object — no studio lighting, no depth of field, no table or background surface, no reflections beyond the rarity foil finish itself. The entire image is the flat card graphic and nothing else.`,
    `Do not include any real-world national flags, real brand logos, real company names, or real identifiable people anywhere in the image; all symbols and emblems should be original fictional designs only.`,
  ].join(' ');
}

async function getNextIssueNumber() {
  const next = await kv.incr('lotm_counter');
  return String(next).padStart(4, '0');
}

async function callImageModel(prompt) {
  const apiKey = process.env.GEMINI_API_KEY_Forge;
  if (!apiKey) throw new Error('GEMINI_API_KEY_Forge not configured');

  const model = 'gemini-3.1-flash-image';
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: { responseModalities: ['IMAGE', 'TEXT'] },
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

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // Q-Sentinel threat check + detection logging
  const ip = await logRequest(req, {
    checkBody: true,
    expectedFields: ['character', 'flavor', 'mood', 'palette', 'licenceKey'],
  });

  const { character, flavor, mood, palette, licenceKey } = req.body || {};

  if (!character || !flavor || !mood || !palette || !licenceKey) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  const characterKey = character.toUpperCase();
  const flavorKey = flavor.toUpperCase();
  if (!CHARACTERS[characterKey]) return res.status(400).json({ error: 'Unknown character' });
  if (!FLAVORS[flavorKey]) return res.status(400).json({ error: 'Unknown flavor' });

  const FREE_CODE = 'LOTMFREE';
  const FREE_CODE_LIMIT = 100;
  const isFreeCodeAttempt = licenceKey.trim().toUpperCase() === FREE_CODE;

  try {
    if (isFreeCodeAttempt) {
      const forwardedFor = req.headers['x-forwarded-for'] || '';
      const clientIp = forwardedFor.split(',')[0].trim() || 'unknown';
      const ipKey = `lotm_free_ip:${clientIp}`;

      const alreadyRedeemed = await kv.get(ipKey);
      if (alreadyRedeemed) {
        return res.status(403).json({ error: 'Free code already used from this connection. Grab a licence key instead.' });
      }

      const usedCount = await kv.incr('lotm_free_used');
      if (usedCount > FREE_CODE_LIMIT) {
        return res.status(403).json({ error: 'Free codes for this drop have all been claimed. Grab a licence key instead.' });
      }

      await kv.set(ipKey, '1', { ex: 60 * 60 * 24 * 30 });
    } else {
      const lsRes = await fetch('https://api.lemonsqueezy.com/v1/licenses/activate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' },
        body: new URLSearchParams({
          license_key: licenceKey.trim(),
          instance_name: 'lotm-generation-' + Date.now(),
        }),
      });
      const lsData = await lsRes.json();
      if (!lsRes.ok || !lsData.activated) {
        return res.status(403).json({ error: lsData.error || 'Licence key already used or invalid' });
      }
    }

    const [issue, rarity] = await Promise.all([
      getNextIssueNumber(),
      Promise.resolve(rollRarity()),
    ]);
    const powerRating = rollPowerRating(rarity);

    const prompt = buildPrompt({
      character: characterKey,
      flavor: flavorKey,
      mood: mood.toUpperCase(),
      palette: palette.toUpperCase(),
      issue,
      rarity,
      powerRating,
    });

    const { buffer, mimeType } = await callImageModel(prompt);
    const ext = mimeType.includes('png') ? 'png' : 'jpg';
    const filename = `lotm/${issue}-${characterKey.toLowerCase()}-${Date.now()}.${ext}`;

    const blob = await put(filename, buffer, {
      access: 'public',
      contentType: mimeType,
    });

    return res.status(200).json({
      imageUrl: blob.url,
      issue,
      name: CHARACTERS[characterKey].name,
      title: CHARACTERS[characterKey].title,
      flavorLabel: FLAVORS[flavorKey].label,
      rarity: rarity.label,
      powerRating,
    });

  } catch (err) {
    console.error('generate error:', err);
    return res.status(500).json({ error: 'Generation failed, please try again' });
  }
}
