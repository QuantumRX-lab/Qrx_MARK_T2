// api/ls-webhook.js — v2 (label-based, no Stripe/tier required)
// Lemon Squeezy → Ghost member creation
//
// What this does:
//   1. Receives POST from Lemon Squeezy on every purchase event
//   2. Verifies the request is genuinely from Lemon Squeezy (HMAC signature)
//   3. Extracts buyer name and email from the payload
//   4. Calls Ghost Admin API to create the member with a 'lifetime' label
//      (plus an 'rsi-single'/'rsi-bundle' label for RSI report purchases,
//      distinguished by variant_id — see RSI_VARIANT_LABELS below)
//   5. Ghost automatically sends the buyer a magic link email
//
// Environment variables required in Vercel:
//   LS_WEBHOOK_SECRET      — from Lemon Squeezy dashboard → Webhooks → Signing secret
//   GHOST_ADMIN_API_KEY    — from Ghost Admin → Settings → Integrations → Add custom integration
//   GHOST_API_URL          — e.g. https://www.quantumrx.eu
//   LS_VARIANT_RSI_SINGLE  — Lemon Squeezy variant_id for the single-report RSI product
//   LS_VARIANT_RSI_BUNDLE  — Lemon Squeezy variant_id for the 10-report RSI bundle
//   (both RSI variant env vars are placeholders until the products are
//   created in the Lemon Squeezy dashboard -- until then this simply
//   never matches, and every purchase falls through to the pre-existing
//   generic 'lifetime' labelling unchanged)

import crypto from 'crypto';

// RSI-specific label per Lemon Squeezy variant_id, matched against
// attributes.first_order_item.variant_id (previously read but ignored by
// this webhook). Non-RSI variants fall through to the existing generic
// behaviour untouched -- the meme/forge products are not affected.
const RSI_VARIANT_LABELS = {
  [process.env.LS_VARIANT_RSI_SINGLE]: 'rsi-single',
  [process.env.LS_VARIANT_RSI_BUNDLE]: 'rsi-bundle',
};

export default async function handler(req, res) {

  // ── Only accept POST ──────────────────────────────────────────────────────
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // ── Verify Lemon Squeezy signature ────────────────────────────────────────
  const secret    = process.env.LS_WEBHOOK_SECRET;
  const signature = req.headers['x-signature'];

  if (!secret || !signature) {
    console.error('Missing webhook secret or signature header');
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const rawBody = JSON.stringify(req.body);
  const expected = crypto
    .createHmac('sha256', secret)
    .update(rawBody)
    .digest('hex');

  if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) {
    console.error('Signature mismatch — request rejected');
    return res.status(401).json({ error: 'Invalid signature' });
  }

  // ── Only act on order_created events ─────────────────────────────────────
  const eventName = req.headers['x-event-name'];
  if (eventName !== 'order_created') {
    return res.status(200).json({ received: true, action: 'ignored', event: eventName });
  }

  // ── Extract buyer details ─────────────────────────────────────────────────
  const attributes = req.body?.data?.attributes;
  if (!attributes) {
    console.error('No attributes in payload');
    return res.status(400).json({ error: 'Invalid payload structure' });
  }

  const buyerEmail = attributes.user_email;
  const buyerName  = attributes.user_name || '';
  const orderId    = req.body?.data?.id || 'unknown';
  const variantId  = String(attributes.first_order_item?.variant_id ?? '');
  const rsiLabel   = RSI_VARIANT_LABELS[variantId] || null;

  if (!buyerEmail) {
    console.error('No email in payload');
    return res.status(400).json({ error: 'No email in payload' });
  }

  console.log(`New purchase: ${buyerName} <${buyerEmail}> — Order ${orderId}${rsiLabel ? ` — ${rsiLabel}` : ''}`);

  // ── Ghost Admin API setup ─────────────────────────────────────────────────
  const ghostApiKey = process.env.GHOST_ADMIN_API_KEY;
  const ghostUrl    = process.env.GHOST_API_URL;

  if (!ghostApiKey || !ghostUrl) {
    console.error('Missing Ghost environment variables');
    return res.status(500).json({ error: 'Server configuration error' });
  }

  const [keyId, keySecret] = ghostApiKey.split(':');
  const token = generateGhostJWT(keyId, keySecret);

  // ── Try to create new Ghost member ───────────────────────────────────────
  const createRes = await fetch(`${ghostUrl}/ghost/api/admin/members/`, {
    method:  'POST',
    headers: {
      'Content-Type':  'application/json',
      'Authorization': `Ghost ${token}`,
    },
    body: JSON.stringify({
      members: [{
        email:      buyerEmail,
        name:       buyerName,
        labels:     [{ name: 'lifetime' }, { name: 'lemon-squeezy' }, ...(rsiLabel ? [{ name: rsiLabel }] : [])],
        note:       `Lifetime member — Lemon Squeezy order ${orderId}`,
        subscribed: true,
      }]
    }),
  });

  // ── Member already exists — add lifetime label ───────────────────────────
  if (createRes.status === 422) {
    console.log(`Member exists: ${buyerEmail} — adding lifetime label`);
    const result = await addLabelToExistingMember(ghostUrl, token, buyerEmail, rsiLabel);
    if (result.success) {
      return res.status(200).json({ success: true, action: 'label_added', email: buyerEmail });
    }
    return res.status(500).json({ error: 'Failed to update existing member', detail: result.error });
  }

  if (!createRes.ok) {
    const err = await createRes.json();
    console.error('Ghost API error:', createRes.status, JSON.stringify(err));
    return res.status(500).json({ error: 'Ghost API error', detail: err });
  }

  console.log(`Member created: ${buyerEmail}`);
  return res.status(200).json({ success: true, action: 'member_created', email: buyerEmail });
}


// ── Ghost JWT ────────────────────────────────────────────────────────────────
function generateGhostJWT(keyId, keySecret) {
  const now = Math.floor(Date.now() / 1000);
  const encode = obj => Buffer.from(JSON.stringify(obj)).toString('base64url');
  const header  = encode({ alg: 'HS256', typ: 'JWT', kid: keyId });
  const payload = encode({ iat: now, exp: now + 300, aud: '/admin/' });
  const secret  = Buffer.from(keySecret, 'hex');
  const sig     = crypto.createHmac('sha256', secret).update(`${header}.${payload}`).digest('base64url');
  return `${header}.${payload}.${sig}`;
}


// ── Add lifetime label to existing member ────────────────────────────────────
async function addLabelToExistingMember(ghostUrl, token, email, rsiLabel) {
  try {
    // Find member
    const searchRes = await fetch(
      `${ghostUrl}/ghost/api/admin/members/?filter=email:'${encodeURIComponent(email)}'`,
      { headers: { 'Authorization': `Ghost ${token}` } }
    );
    const searchData = await searchRes.json();
    const member = searchData?.members?.[0];
    if (!member) return { success: false, error: 'Member not found' };

    // Merge labels — avoid duplicates
    const existingLabels = (member.labels || []).map(l => l.name);
    const labelsToAdd = ['lifetime', 'lemon-squeezy', ...(rsiLabel ? [rsiLabel] : [])];
    const newLabels = [...new Set([...existingLabels, ...labelsToAdd])]
      .map(name => ({ name }));

    const updateRes = await fetch(
      `${ghostUrl}/ghost/api/admin/members/${member.id}/`,
      {
        method:  'PUT',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Ghost ${token}` },
        body: JSON.stringify({ members: [{ labels: newLabels }] }),
      }
    );

    if (!updateRes.ok) {
      const err = await updateRes.json();
      return { success: false, error: err };
    }

    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
}
