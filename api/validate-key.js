// /api/validate-key
//
// Tentatively checks a Lemon Squeezy licence key for the QRx NFT Forge,
// WITHOUT consuming its activation. The real, consuming check happens in
// /api/generate at the moment of actual card generation — see that file
// for why activation is deferred to generate-time.
//
// This endpoint exists purely to give the frontend fast feedback (green
// border) while typing, so users aren't stuck guessing whether a key
// looks right before they even select theme/mood/palette.
//
// Uses LS's /validate endpoint, which does NOT consume activation. Known
// quirk: /validate returns "license_key not found" for keys that have
// never been activated yet (confirmed empirically 2026-06-16), even
// though the key is genuinely valid and unused. We treat that specific
// case as a tentative pass rather than a rejection, since rejecting it
// would block every legitimate first-time buyer. Genuinely malformed,
// disabled, or expired keys are still caught correctly below.
//
// Expected request body: { licenceKey: string }
// Expected response: { valid: true } or { valid: false, error: string }

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ valid: false, error: 'Method not allowed' });
  }

  const { licenceKey } = req.body || {};

  if (!licenceKey || typeof licenceKey !== 'string') {
    return res.status(400).json({ valid: false, error: 'Licence key missing' });
  }

  // FREE CODE short-circuit — see /api/generate for the actual capped
  // enforcement (KV-counted, 100 redemptions, key forge_free_used). This
  // check is tentative only, same as the LS path below: it tells the
  // frontend the code is recognized, but doesn't guarantee a slot is
  // still free. If the cap has been hit, /api/generate will still
  // correctly reject at the point of actual generation.
  if (licenceKey.trim().toUpperCase() === 'PEPEFREE') {
    return res.status(200).json({ valid: true });
  }

  if (licenceKey.trim().length < 10) {
    return res.status(400).json({ valid: false, error: 'Licence key missing or too short' });
  }

  // Reject obviously-fake keys early (e.g. demo-era "any 16 digits" bypass attempts)
  if (!/^FORGE-/i.test(licenceKey.trim()) && !/^[A-Z0-9-]{16,}$/i.test(licenceKey.trim())) {
    return res.status(400).json({ valid: false, error: 'Invalid licence key format' });
  }

  try {
    // Non-consuming check. Docs: https://docs.lemonsqueezy.com/api/license-api/validate-license-key
    const lsResponse = await fetch('https://api.lemonsqueezy.com/v1/licenses/validate', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        Accept: 'application/json',
      },
      body: new URLSearchParams({ license_key: licenceKey.trim() }),
    });

    const lsData = await lsResponse.json();

    if (lsData.valid) {
      const status = lsData.license_key?.status;
      if (status === 'disabled' || status === 'expired') {
        return res.status(200).json({ valid: false, error: 'Licence key ' + status });
      }
      const usage = lsData.license_key?.activation_usage ?? 0;
      const limit = lsData.license_key?.activation_limit ?? 1;
      if (limit !== null && usage >= limit) {
        return res.status(200).json({ valid: false, error: 'Licence key already used' });
      }
      return res.status(200).json({ valid: true });
    }

    // Known LS quirk: a never-activated key reports "not found" here even
    // though it's genuinely valid. Treat this specific error as a tentative
    // pass — the real activation check happens in /api/generate.
    if (lsData.error && /not found/i.test(lsData.error)) {
      return res.status(200).json({ valid: true });
    }

    // Any other rejection (malformed, wrong store, etc.) is a real failure.
    return res.status(200).json({ valid: false, error: lsData.error || 'Licence key not valid' });

  } catch (err) {
    console.error('validate-key error:', err);
    return res.status(500).json({ valid: false, error: 'Validation service unavailable' });
  }
}
