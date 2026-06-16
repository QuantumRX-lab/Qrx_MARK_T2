// /api/validate-key
//
// Validates a Lemon Squeezy licence key for the QRx NFT Forge.
// Uses LS's own licence-key validation API rather than a custom store,
// since LS already tracks activation count/limit per key.
//
// Env vars required (set in Vercel project settings):
//   LEMONSQUEEZY_API_KEY  - LS API key (used for "activate" call, optional if just validating)
//
// Expected request body: { licenceKey: string }
// Expected response: { valid: true } or { valid: false, error: string }

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ valid: false, error: 'Method not allowed' });
  }

  const { licenceKey } = req.body || {};

  if (!licenceKey || typeof licenceKey !== 'string' || licenceKey.trim().length < 10) {
    return res.status(400).json({ valid: false, error: 'Licence key missing or too short' });
  }

  // Reject obviously-fake keys early (e.g. demo-era "any 16 digits" bypass attempts)
  if (!/^FORGE-/i.test(licenceKey.trim()) && !/^[A-Z0-9-]{16,}$/i.test(licenceKey.trim())) {
    return res.status(400).json({ valid: false, error: 'Invalid licence key format' });
  }

  try {
    // Lemon Squeezy /activate is used here instead of /validate, because /validate
    // can return "license_key not found" for keys that have never been activated yet
    // (confirmed empirically against a real never-activated key on 2026-06-16).
    // /activate both confirms the key exists and registers the activation in one call.
    // Docs: https://docs.lemonsqueezy.com/help/licensing/license-api
    const lsResponse = await fetch('https://api.lemonsqueezy.com/v1/licenses/activate', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        Accept: 'application/json',
      },
      body: new URLSearchParams({
        license_key: licenceKey.trim(),
        instance_name: 'qrx-forge-validation',
      }),
    });

    const lsData = await lsResponse.json();

    if (!lsResponse.ok || !lsData.activated) {
      return res.status(200).json({ valid: false, error: lsData.error || 'Licence key not valid' });
    }

    // LS reports activation_usage / activation_limit on the license_key object.
    const meta = lsData.license_key || {};
    const status = meta.status; // 'inactive' | 'active' | 'expired' | 'disabled'

    if (status === 'disabled' || status === 'expired') {
      return res.status(200).json({ valid: false, error: 'Licence key ' + status });
    }

    return res.status(200).json({ valid: true });

  } catch (err) {
    console.error('validate-key error:', err);
    return res.status(500).json({ valid: false, error: 'Validation service unavailable' });
  }
}
