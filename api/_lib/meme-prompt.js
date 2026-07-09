// api/_lib/meme-prompt.js
// Single source of truth for The Daily Meme's theme pool and the Gemini
// prompt used to generate each day's meme (caption + image brief).
//
// Text is never baked into the generated image — image models render text
// unreliably (garbled letters, duplicated lines). Instead the model writes
// a classic top/bottom meme caption as plain strings, and the-meme.html
// overlays that caption on the image with CSS (Impact font, white fill,
// black stroke), the same way every other meme format works.

export const THEME_POOL = [
  'AI coding assistants that are weirdly confident about broken code',
  'Prompt engineering as a job title',
  'Hallucinating a function that was never real',
  'Context windows running out mid-task',
  'Rate limits hitting at the worst possible moment',
  '"It works on my machine" but the machine is an AI model',
  'AGI hype cycles vs what actually shipped',
  'Chatbots refusing a completely reasonable request',
  'A model update quietly breaking every prompt that used to work',
  'Reviewing a pull request written entirely by an AI',
  'Explaining to your boss what the AI actually did overnight',
  'Token limits and the death of a good sentence',
  'The gap between an AI demo and an AI in production',
  'Naming your variables when the AI already named them worse',
  'AI agents that finish the roadmap before your coffee is cold',
  'Debugging a bug the AI introduced while fixing another bug'
];

// Appended to every imagePrompt server-side, not left to the model to
// remember. Deliberately forbids rendered text — the top/bottom caption
// is composited afterward by the page, and text baked into the image by
// the model tends to come out garbled or duplicated.
export const IMAGE_PROMPT_SUFFIX = ' Square image, 1:1 aspect ratio. Photorealistic or clean digital-illustration ' +
  'meme photography style, expressive, high detail, dramatic lighting appropriate to the scene. ' +
  'Do not render any text, letters, captions, or words anywhere in the image — the frame must be completely free of typography.';

// issueNumber is passed in rather than left for the model to track — the
// server owns the authoritative sequential counter (kv.incr), the model
// only needs to know what number to print in its response.
export function buildMemeSystemPrompt(issueNumber) {
  return `You are the writer for "The Daily Meme", a daily AI-humor meme published by QuantumRx Syndicate. One meme, published once a day, always about AI, developers, or working with AI tools.

THEME POOL — pick exactly one theme for today's meme. Vary your pick across days rather than repeating the same one:
${THEME_POOL.map((t) => `- ${t}`).join('\n')}

RULES:
- The joke must be about AI, coding, or working with AI tools — not general workplace humor.
- Write it as a classic top-text/bottom-text meme: "topText" sets up the scene, "bottomText" delivers the punchline. Either can be empty if the joke only needs one line, but never leave both empty.
- Keep each line short and punchy — under 12 words, ALL CAPS is not required (the page renders the styling).
- "imagePrompt" must be a complete, self-contained Gemini image prompt describing a photorealistic or illustrated scene that sets up the joke visually — the kind of reaction-image or scenario photo a meme would be built on. Do not mention text, captions, or words in it.
- "altText" is a one-sentence plain-language description of the image for accessibility.
- "title" is a short punchy title for today's meme (used as the page headline, not shown on the image itself).

Return ONLY valid JSON, no markdown fences, no commentary before or after, in exactly this shape:
{
  "issueNumber": ${issueNumber},
  "title": "string",
  "topText": "string",
  "bottomText": "string",
  "imagePrompt": "complete self-contained Gemini image prompt for the scene",
  "altText": "string"
}`;
}
