const rateLimit = new Map();

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, x-internal-key');
  if (req.method === 'OPTIONS') return res.status(200).end();

  // Auth check — reject anything not coming from your own frontend
  const internalKey = process.env.INTERNAL_API_KEY;
  if (!internalKey || req.headers['x-internal-key'] !== internalKey) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  // Rate limiting — 5 requests per IP per hour
  const ip = req.headers['x-forwarded-for'] || req.socket?.remoteAddress || 'unknown';
  const now = Date.now();
  const windowMs = 60 * 60 * 1000;
  const maxRequests = 5;
  if (!rateLimit.has(ip)) {
    rateLimit.set(ip, []);
  }
  const requests = rateLimit.get(ip).filter(t => now - t < windowMs);
  requests.push(now);
  rateLimit.set(ip, requests);
  if (requests.length > maxRequests) {
    return res.status(429).json({ error: 'Too many requests. Please try again later.' });
  }

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) return res.status(500).json({ error: 'API key not configured' });

  let prompt;
  try {
    const body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
    prompt = body?.prompt;
  } catch {
    return res.status(400).json({ error: 'Invalid request body' });
  }

  if (!prompt) return res.status(400).json({ error: 'No prompt provided' });

  if (prompt.length > 50000) {
    return res.status(400).json({ error: 'Input too large. Please reduce your chat history.' });
  }

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
