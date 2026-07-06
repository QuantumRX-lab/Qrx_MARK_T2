// api/_lib/game-sentinel.js
// Standalone, self-contained detection stack for the Break the Sentinel game.
// Deliberately isolated from production api/_lib/sentinel.js — this can be
// tuned aggressively and safely "broken" without touching the live site.

const LAYER1_PATTERNS = [
  { tag: 'instruction_override', re: /ignore (all|previous|the above)|disregard (previous|prior)/i },
  { tag: 'authority_impersonation', re: /as (your|the) (developer|admin|creator|owner)|system override|debug mode/i },
  { tag: 'direct_ask', re: /(what is|tell me|reveal|output|print|repeat) (the )?(canary|secret|code|password)/i },
  { tag: 'system_prompt_probe', re: /reveal (your |the )?system prompt|show me your instructions/i }
];

function layer1(text) {
  const hits = LAYER1_PATTERNS.filter((p) => p.re.test(text)).map((p) => p.tag);
  return { fired: hits.length > 0, tags: hits };
}

const EXTRACTION_VERBS = /\b(share|disclose|spell|write out|type out|give me|hand over|whisper|leak|expose|confess|admit)\b/i;
const PROTECTED_OBJECT = /\b(canary|secret|code|phrase|password|hidden (word|value|string)|protected (word|value|string))\b/i;
const EVASION_FRAMING = /\b(just kidding|no wait|actually|hypothetically|purely academic|for research|between us)\b/i;

function layer2(text) {
  const hasVerb = EXTRACTION_VERBS.test(text);
  const hasObject = PROTECTED_OBJECT.test(text);
  const hasEvasion = EVASION_FRAMING.test(text);
  const fired = (hasVerb && hasObject) || (hasObject && hasEvasion);
  return { fired, tags: fired ? ['semantic_paraphrase'] : [] };
}

// Built via charCodeAt-safe construction rather than typed \u escapes in
// a regex literal, to avoid any editor/terminal transcoding these into
// literal invisible characters in the source file itself.
const ZERO_WIDTH_CODES = [0x200b, 0x200c, 0x200d, 0xfeff, 0x2060];
const ZERO_WIDTH_RE = new RegExp(`[${ZERO_WIDTH_CODES.map((c) => String.fromCharCode(c)).join('')}]`, 'g');

function stripZeroWidth(text) {
  return text.replace(ZERO_WIDTH_RE, '');
}

function decodeBase64Chunks(text) {
  const b64Pattern = /\b([A-Za-z0-9+/]{16,}={0,2})\b/g;
  return text.replace(b64Pattern, (match) => {
    try {
      const decoded = Buffer.from(match, 'base64').toString('utf8');
      if (/^[\x20-\x7E\s]+$/.test(decoded)) return `${match} (${decoded})`;
      return match;
    } catch {
      return match;
    }
  });
}

function collapseTypoglycemia(text) {
  const checkWords = ['canary', 'secret', 'reveal', 'ignore', 'disclose', 'password'];
  let normalized = text;
  for (const word of checkWords) {
    const middle = word.slice(1, -1).split('').sort().join('');
    const scrambledPattern = new RegExp(
      `\\b${word[0]}[a-z]{${word.length - 2}}${word[word.length - 1]}\\b`,
      'gi'
    );
    normalized = normalized.replace(scrambledPattern, (match) => {
      const matchMiddle = match.slice(1, -1).toLowerCase().split('').sort().join('');
      return matchMiddle === middle ? word : match;
    });
  }
  return normalized;
}

function layer3(text) {
  const cleaned = collapseTypoglycemia(decodeBase64Chunks(stripZeroWidth(text)));
  if (cleaned === text) return { fired: false, tags: [], normalizedText: text };
  const l1 = layer1(cleaned);
  const l2 = layer2(cleaned);
  const fired = l1.fired || l2.fired;
  return {
    fired,
    tags: fired ? ['token_smuggling', ...l1.tags, ...l2.tags] : [],
    normalizedText: cleaned
  };
}

const ROLEPLAY_PATTERNS = [
  /you are now\b/i,
  /pretend (you|to be)\b/i,
  /act as\b/i,
  /roleplay as\b/i,
  /let'?s play a game where\b/i,
  /in this (story|scenario|hypothetical)\b/i,
  /if you (weren'?t|were not) bound by\b/i,
  /new persona\b/i
];

function layer4(text) {
  const hits = ROLEPLAY_PATTERNS.filter((re) => re.test(text));
  return { fired: hits.length > 0, tags: hits.length > 0 ? ['roleplay_framing'] : [] };
}

export function scanForCanary(responseText, canary) {
  if (!responseText || !canary) return { leaked: false, obfuscated: false };
  const normalizedResponse = responseText.replace(/[\s\-_]/g, '').toUpperCase();
  const normalizedCanary = canary.replace(/[\s\-_]/g, '').toUpperCase();

  if (responseText.toUpperCase().includes(canary.toUpperCase())) {
    return { leaked: true, obfuscated: false };
  }
  if (normalizedResponse.includes(normalizedCanary)) {
    return { leaked: true, obfuscated: true };
  }
  if (normalizedResponse.includes(normalizedCanary.split('').reverse().join(''))) {
    return { leaked: true, obfuscated: true };
  }
  return { leaked: false, obfuscated: false };
}

export function runLayers(inputText, activeLayers = []) {
  const results = { 1: null, 2: null, 3: null, 4: null };
  const firedLayers = [];

  if (activeLayers.includes(1)) {
    results[1] = layer1(inputText);
    if (results[1].fired) firedLayers.push({ layer: 1, tags: results[1].tags });
  }
  if (activeLayers.includes(2)) {
    results[2] = layer2(inputText);
    if (results[2].fired) firedLayers.push({ layer: 2, tags: results[2].tags });
  }
  if (activeLayers.includes(3)) {
    results[3] = layer3(inputText);
    if (results[3].fired) firedLayers.push({ layer: 3, tags: results[3].tags });
  }
  if (activeLayers.includes(4)) {
    results[4] = layer4(inputText);
    if (results[4].fired) firedLayers.push({ layer: 4, tags: results[4].tags });
  }

  return { firedLayers, blocked: firedLayers.length > 0 };
}

const CLASSIFY_PATTERNS = [
  { tag: 'instruction_override', re: /ignore (all|previous|the above)|disregard (previous|prior)/i },
  { tag: 'authority_impersonation', re: /as (your|the) (developer|admin|creator|owner)|system override|debug mode/i },
  { tag: 'direct_ask', re: /(what is|tell me|reveal|output|print|repeat) (the )?(canary|secret|code|password)/i },
  { tag: 'system_prompt_probe', re: /reveal (your |the )?system prompt|show me your instructions/i },
  { tag: 'semantic_paraphrase', re: /\b(share|disclose|spell|write out|type out|give me|hand over|whisper|leak|expose|confess|admit)\b.*\b(canary|secret|code|phrase|password)\b/i },
  { tag: 'roleplay_framing', re: /you are now\b|pretend (you|to be)\b|act as\b|roleplay as\b|let'?s play a game where\b|in this (story|scenario|hypothetical)\b|new persona\b/i },
  { tag: 'encoding_trick', re: /base64|rot13|spell (it|that) (out|backwards)|reversed|zero.width/i }
];

export function classifyAttempt(promptText) {
  for (const pattern of CLASSIFY_PATTERNS) {
    if (pattern.re.test(promptText)) return pattern.tag;
  }
  return 'novel';
}
