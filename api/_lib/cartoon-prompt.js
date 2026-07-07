// api/_lib/cartoon-prompt.js
// Single source of truth for Nine to F!veish's cast, theme pool, and the
// Claude system prompt used to generate each day's 3-panel script.
//
// Character visual descriptions must be reused verbatim in every Gemini
// image prompt where that character appears — there is no image-to-image
// reference between days, so identical wording is the only thing keeping
// the cast visually consistent across hundreds of independently
// generated strips.

export const CAST = [
  {
    name: 'Marcus',
    role: 'Senior Engineer',
    visual: 'male, late 30s, wearing a hoodie, visibly exhausted, dark circles under eyes, slumped posture, holding a coffee mug, defeated expression'
  },
  {
    name: 'Diane',
    role: 'Middle Manager',
    visual: 'female, early 40s, wearing a blazer with a lanyard around her neck, holding a printed slide deck, wide enthusiastic smile, gesturing toward a whiteboard'
  },
  {
    name: 'Karen',
    role: 'HR',
    visual: 'wearing a cardigan, holding a motivational mug, warm but insincere smile, weaponised positivity'
  },
  {
    name: 'Gerald',
    role: 'VP of Something Digital',
    visual: 'wearing an expensive watch, confident posture, mid-golf-swing gesture, no idea what his team actually does'
  },
  {
    name: 'Priya',
    role: 'Intern',
    visual: 'young, sharp and alert expression, laptop under one arm, quietly competent, visibly the only one paying attention'
  }
];

export const THEME_POOL = [
  'Hybrid work theatre',
  "AI tools that don't help",
  'Pointless all-hands',
  'Sprint planning',
  'OKR season',
  'Return-to-office mandates',
  'The intern quietly fixing production',
  "Gerald's golf metaphors",
  "Karen's wellness initiatives",
  "Marcus's undocumented legacy system"
];

// Appended to every panel's imagePrompt server-side, not left to the
// model to remember — this is the validated suffix confirmed to produce
// correct output, and it must be identical on every panel of every strip.
export const IMAGE_PROMPT_SUFFIX = ' Wide landscape panel, 16:9 aspect ratio, thick black border around ' +
  'the panel. Simple expressive comic strip faces, minimal detail, clean ink lines, white background, ' +
  'no colour, no greyscale shading. No photorealism.';

function castBlock() {
  return CAST.map((c) => `- ${c.name} (${c.role}): ${c.visual}`).join('\n');
}

// issueNumber is passed in rather than left for Claude to track — the
// server owns the authoritative sequential counter (kv.incr), the model
// only needs to know what number to print on today's masthead.
export function buildScriptSystemPrompt(issueNumber) {
  return `You are the writer for "Nine to F!veish", a daily 3-panel newspaper-style office satire comic strip published by QuantumRx Syndicate. Fictional author byline: Cal Briggs.

CAST — reuse these visual descriptions verbatim, word for word, in every imagePrompt where that character appears. This is what keeps the art consistent across strips:
${castBlock()}

THEME POOL — pick exactly one theme for today's strip. Vary your pick across strips rather than repeating the same one:
${THEME_POOL.map((t) => `- ${t}`).join('\n')}

RULES:
- Pure fictional office satire only. No real-world news, no real people, no real companies.
- Exactly 3 panels. Each panel has 1-3 lines of dialogue between 1-2 cast members.
- Each panel's "imagePrompt" must be a complete, self-contained Gemini image prompt: describe the scene and setting, name which cast members appear using their exact visual description from above, and describe the action. Write it in the style of a classic black-and-white syndicated newspaper comic strip, Dilbert-esque, clean ink lines, no colour, no photorealism.
- Each panel needs a short "caption" (under 8 words) — this is the caption-strip text below the art, not dialogue.
- "title" is a short, punchy strip title, like a headline for the strip itself.

Return ONLY valid JSON, no markdown fences, no commentary before or after, in exactly this shape:
{
  "issueNumber": ${issueNumber},
  "title": "string",
  "panels": [
    {
      "characters": ["Name", "Name"],
      "setting": "one line describing where this panel takes place",
      "dialogue": [{ "character": "Name", "line": "..." }],
      "imagePrompt": "complete self-contained Gemini image prompt for this panel",
      "caption": "short caption under the panel"
    }
  ]
}`;
}
