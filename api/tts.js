// api/tts.js
// QuantumRx Signal Analyst — Text-to-Speech endpoint
// Uses Gemini 3.1 Flash TTS Preview via REST API
// Returns a WAV audio file from the story card text
// Voice: Kore (clear, authoritative, suits news delivery)

import { logRequest, getSentinelAction } from './_lib/sentinel.js';

const GEMINI_TTS_URL = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-tts-preview:generateContent';

// Build a WAV file header around raw PCM data
// Gemini TTS returns 16-bit PCM at 24kHz mono
function buildWav(pcmBase64) {
  const pcm = Buffer.from(pcmBase64, 'base64');
  const numChannels = 1;
  const sampleRate = 24000;
  const bitsPerSample = 16;
  const byteRate = sampleRate * numChannels * (bitsPerSample / 8);
  const blockAlign = numChannels * (bitsPerSample / 8);
  const dataSize = pcm.length;
  const headerSize = 44;

  const buf = Buffer.alloc(headerSize + dataSize);

  // RIFF chunk
  buf.write('RIFF', 0);
  buf.writeUInt32LE(headerSize - 8 + dataSize, 4);
  buf.write('WAVE', 8);

  // fmt chunk
  buf.write('fmt ', 12);
  buf.writeUInt32LE(16, 16);           // chunk size
  buf.writeUInt16LE(1, 20);            // PCM format
  buf.writeUInt16LE(numChannels, 22);
  buf.writeUInt32LE(sampleRate, 24);
  buf.writeUInt32LE(byteRate, 28);
  buf.writeUInt16LE(blockAlign, 32);
  buf.writeUInt16LE(bitsPerSample, 34);

  // data chunk
  buf.write('data', 36);
  buf.writeUInt32LE(dataSize, 40);
  pcm.copy(buf, 44);

  return buf;
}

export default async function handler(req, res) {
  // CORS — allow both www and non-www
  const origin = req.headers.origin || '';
  const allowed = ['https://quantumrx.eu', 'https://www.quantumrx.eu'];
  if (allowed.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
  }
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  await logRequest(req, 'tts');

  const action = await getSentinelAction(req);
  if (action === 'block') {
    return res.status(403).json({ error: 'Access monitored' });
  }

  const apiKey = process.env.GEMINI_API_KEY_Forge;
  if (!apiKey) return res.status(500).json({ error: 'TTS not configured' });

  const { text } = req.body || {};
  if (!text || typeof text !== 'string' || text.trim().length < 10) {
    return res.status(400).json({ error: 'Invalid text' });
  }

  // Limit text length — a full story card is ~600 chars max
  const safeText = text.slice(0, 1200).trim();

  try {
    const geminiRes = await fetch(`${GEMINI_TTS_URL}?key=${apiKey}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ parts: [{ text: safeText }] }],
        generationConfig: {
          responseModalities: ['AUDIO'],
          speechConfig: {
            voiceConfig: {
              prebuiltVoiceConfig: {
                voiceName: 'Kore',
              },
            },
          },
        },
      }),
      signal: AbortSignal.timeout(30000),
    });

    if (!geminiRes.ok) {
      const err = await geminiRes.text().catch(() => '');
      console.error('[TTS] Gemini error:', geminiRes.status, err);
      return res.status(502).json({ error: 'TTS generation failed' });
    }

    const data = await geminiRes.json();
    const pcmBase64 = data?.candidates?.[0]?.content?.parts?.[0]?.inlineData?.data;

    if (!pcmBase64) {
      console.error('[TTS] No audio data in response');
      return res.status(502).json({ error: 'No audio returned' });
    }

    const wav = buildWav(pcmBase64);

    res.setHeader('Content-Type', 'audio/wav');
    res.setHeader('Content-Length', wav.length);
    res.setHeader('Cache-Control', 'no-store');
    return res.status(200).end(wav);

  } catch (err) {
    console.error('[TTS] Error:', err);
    return res.status(500).json({ error: 'TTS request failed' });
  }
}
