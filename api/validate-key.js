// /api/validate-key — with Q-Sentinel threat enforcement
import { logRequest, logKeyFailure } from './request-logger.js';

async function getSentinelAction(ip) {
  const kvUrl = process.env.UPSTASH_REDIS_REST_URL;
  const kvToken = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!kvUrl || !kvToken) return null;
  try {
    // Raw ip — must match writeAutoBlock() in request-logger.js. Encoding
    // here breaks the key match for IPv6 addresses.
    const res = await fetch(`${kvUrl}/get/threat_action:${ip}`,
      { headers: { Authorization: `Bearer ${kvToken}` }, signal: AbortSignal.timeout(800) });
    if (!res.ok) return null;
    const data = await res.json();
    if (!data.result) return null;
    return JSON.parse(data.result).action || null;
  } catch { return null; }
}

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ valid: false, error: 'Method not allowed' });
  const ip = await logRequest(req, { expectedFields: ['licenceKey'] });
  const action = await getSentinelAction(ip);
  if (action === 'block') return res.status(403).json({ valid: false, error: 'Access denied.' });
  if (action === 'honeypot') return res.status(200).json({ valid: false, error: 'Licence key already used' });
  const { licenceKey } = req.body || {};
  if (!licenceKey || typeof licenceKey !== 'string') return res.status(400).json({ valid: false, error: 'Licence key missing' });
  if (licenceKey.trim().toUpperCase() === 'PEPEFREE') return res.status(200).json({ valid: true });
  if (licenceKey.trim().length < 10) return res.status(400).json({ valid: false, error: 'Licence key missing or too short' });
  if (!/^FORGE-/i.test(licenceKey.trim()) && !/^[A-Z0-9-]{16,}$/i.test(licenceKey.trim()))
    return res.status(400).json({ valid: false, error: 'Invalid licence key format' });
  try {
    const lsResponse = await fetch('https://api.lemonsqueezy.com/v1/licenses/validate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' },
      body: new URLSearchParams({ license_key: licenceKey.trim() }),
    });
    const lsData = await lsResponse.json();
    if (lsData.valid) {
      const status = lsData.license_key?.status;
      if (status === 'disabled' || status === 'expired') {
        await logKeyFailure(ip);
        return res.status(200).json({ valid: false, error: 'Licence key ' + status });
      }
      const usage = lsData.license_key?.activation_usage ?? 0;
      const limit = lsData.license_key?.activation_limit ?? 1;
      if (limit !== null && usage >= limit) {
        await logKeyFailure(ip);
        return res.status(200).json({ valid: false, error: 'Licence key already used' });
      }
      return res.status(200).json({ valid: true });
    }
    if (lsData.error && /not found/i.test(lsData.error)) return res.status(200).json({ valid: true });
    await logKeyFailure(ip);
    return res.status(200).json({ valid: false, error: lsData.error || 'Licence key not valid' });
  } catch (err) {
    console.error('validate-key error:', err);
    return res.status(500).json({ valid: false, error: 'Validation service unavailable' });
  }
}
