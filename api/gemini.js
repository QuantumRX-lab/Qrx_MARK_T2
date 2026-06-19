const rateLimit = new Map();

function compressPrompt(fmt, input) {
  return `You are an expert AI workflow architect. Analyse this raw AI chat history and compress it into a structured continuity kernel.

Extract and structure ALL of the following sections:

IDENTITY: name, role, expertise, location, handle, timezone
PROJECT: name, domain, platform, goals, audience, key URLs
STATUS: completed milestones, work in progress, blockers
DECISIONS: key choices made with rationale
PIPELINE: upcoming tasks/items with priority and status
COMMUNICATION: tone preferences, style, formatting dislikes, feedback preferences, working rhythm
RELATIONSHIP: how the user likes to work with AI, what they find valuable, what frustrates them, any explicit preferences about AI interaction style
REFERENCES: key URLs, tools, data sources, credentials (non-sensitive)
OPEN THREADS: unresolved questions, pending decisions, known issues
WORKFLOW: tools in use, agent structure, session patterns, methodology

Output format: ${fmt.toUpperCase()}
CRITICAL: Output ONLY the raw ${fmt.toUpperCase()} — absolutely no preamble, no explanation, no markdown code fences, no backticks.
- Mark inferred fields: # inferred
- Mark fields needing verification: # verify
- Include metadata block: generated date, source, format version
- Every field must earn its place
- The communication and relationship sections are as important as the project sections

Chat history:
---
${input}
---`;
}

function buildPrompt(fmt, input) {
  let parsed;
  try { parsed = JSON.parse(input); } catch { return null; }
  const { type, name, project, domain, desc } = parsed;
  if (!desc) return null;
  return `You are an expert AI workflow architect. Generate a comprehensive drop-in continuity kernel for a ${type||'general'} project.

Include ALL of the following sections:

IDENTITY: author name, role, expertise, location
PROJECT: name, domain, platform, goals, audience, key URLs
STATUS: current phase, completed milestones, active work, blockers
PIPELINE: upcoming tasks/features with priority and status
DECISIONS: key choices made and rationale
COMMUNICATION: tone preferences, style, formatting preferences, feedback style, working rhythm
RELATIONSHIP: how the user prefers to work with AI assistants — what they value, what frustrates them, interaction style preferences, level of detail expected
REFERENCES: key URLs, tools, data sources
CONSTRAINTS: known limitations, dependencies, open questions
METADATA: generated date, format version, TODO markers

Output format: ${fmt.toUpperCase()}
CRITICAL: Output ONLY the raw ${fmt.toUpperCase()} — absolutely no preamble, no explanation, no markdown code fences, no backticks.
- Descriptive placeholders: # TODO: add your X here
- Adapt field names naturally for a ${type||'general'} project
- Brief inline comments on each major section
- The communication and relationship sections are mandatory — not optional

Project details:
Author: ${name||'Not specified'}
Project: ${project||'Not specified'}
Type: ${type||'Not specified'}
Domain: ${domain||'Not specified'}
Description: ${desc}`;
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  // Rate limiting — 5 requests per IP per hour
  const ip = req.headers['x-forwarded-for'] || req.socket?.remoteAddress || 'unknown';
  const now = Date.now();
  const windowMs = 60 * 60 * 1000;
  const maxRequests = 5;
  if (!rateLimit.has(ip)) rateLimit.set(ip, []);
  const requests = rateLimit.get(ip).filter(t => now - t < windowMs);
  requests.push(now);
  rateLimit.set(ip, requests);
  if (requests.length > maxRequests) {
    return res.status(429).json({ error: 'Too many requests. Please try again later.' });
  }

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) return res.status(500).json({ error: 'API key not configured' });

  let mode, format, input;
  try {
    const body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
    mode = body?.mode;
    format = body?.format;
    input = body?.input;
  } catch {
    return res.status(400).json({ error: 'Invalid request body' });
  }

  // Validate inputs
  if (!mode || !['compress', 'build'].includes(mode)) {
    return res.status(400).json({ error: 'Invalid mode' });
  }
  if (!format || !['yaml', 'json', 'markdown'].includes(format)) {
    return res.status(400).json({ error: 'Invalid format' });
  }
  if (!input || typeof input !== 'string') {
    return res.status(400).json({ error: 'No input provided' });
  }
  if (input.length > 50000) {
    return res.status(400).json({ error: 'Input too large. Please reduce your chat history.' });
  }

  // Build prompt server-side
  const truncated = input.length > 48000 ? input.slice(0, 48000) + '\n\n[truncated]' : input;
  const prompt = mode === 'compress' ? compressPrompt(format, truncated) : buildPrompt(format, truncated);
  if (!prompt) return res.status(400).json({ error: 'Invalid input data' });

  try {
    const geminiRes = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ role: 'user', parts: [{ text: prompt }] }],
          generationConfig: { maxOutputTokens: 2500, temperature: 0.3 },
        }),
      }
    );
    if (!geminiRes.ok) {
      const errText = await geminiRes.text();
      return res.status(geminiRes.status).json({ error: `Gemini API error: ${geminiRes.status}`, detail: errText });
    }
    const data = await geminiRes.json();
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text || '';
    return res.status(200).json({ text });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}
