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
  ].join('
