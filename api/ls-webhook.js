// api/ls-webhook.js
// Lemon Squeezy → Ghost member creation
// 
// What this does:
//   1. Receives POST from Lemon Squeezy on every purchase event
//   2. Verifies the request is genuinely from Lemon Squeezy (HMAC signature)
//   3. Extracts buyer name and email from the payload
//   4. Calls Ghost Admin API to create the member
//   5. Assigns them to the Lifetime tier
//
// Environment variables required in Vercel:
//   LS_WEBHOOK_SECRET   — from Lemon Squeezy dashboard → Webhooks → your webhook → Signing secret
//   GHOST_ADMIN_API_KEY — from Ghost Admin → Settings → Integrations → Add custom integration
//   GHOST_API_URL       — your Ghost URL e.g. https://www.quantumrx.eu
//   GHOST_TIER_ID       — ID of your Lifetime Member tier (see note below on finding this)

import crypto from 'crypto';

export default async function handler(req, res) {

  // ── Only accept POST ────────────────────────────────────────────────────────
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // ── Verify Lemon Squeezy signature ──────────────────────────────────────────
  // LS signs every webhook with HMAC-SHA256 using your webhook secret.
  // If the signature doesn't match, reject immediately — could be spoofed.
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

  // ── Only act on order_created events ────────────────────────────────────────
  // Lemon Squeezy fires multiple event types (refunds, subscriptions, etc).
  // We only want to create Ghost members when a purchase completes.
  const eventName = req.headers['x-event-name'];

  if (eventName !== 'order_created') {
    // Acknowledge other events without acting on them
    return res.status(200).json({ received: true, action: 'ignored', event: eventName });
  }

  // ── Extract buyer details from payload ──────────────────────────────────────
  const data = req.body?.data;
  const attributes = data?.attributes;

  if (!attributes) {
    console.error('No attributes in payload:', JSON.stringify(req.body));
    return res.status(400).json({ error: 'Invalid payload structure' });
  }

  const buyerEmail = attributes.user_email;
  const buyerName  = attributes.user_name || '';

  if (!buyerEmail) {
    console.error('No email in payload');
    return res.status(400).json({ error: 'No email in payload' });
  }

  console.log(`New purchase: ${buyerName} <${buyerEmail}>`);

  // ── Call Ghost Admin API to create member ───────────────────────────────────
  // Ghost Admin API uses JWT authentication.
  // The GHOST_ADMIN_API_KEY format is: {id}:{secret} — split on the colon.
  const ghostApiKey = process.env.GHOST_ADMIN_API_KEY;
  const ghostUrl    = process.env.GHOST_API_URL;      // e.g. https://www.quantumrx.eu
  const tierId      = process.env.GHOST_TIER_ID;      // your Lifetime tier ID

  if (!ghostApiKey || !ghostUrl || !tierId) {
    console.error('Missing Ghost environment variables');
    return res.status(500).json({ error: 'Server configuration error' });
  }

  // Generate Ghost Admin JWT
  const [keyId, keySecret] = ghostApiKey.split(':');
  const token = generateGhostJWT(keyId, keySecret);

  // Create member in Ghost
  const ghostEndpoint = `${ghostUrl}/ghost/api/admin/members/`;

  const memberPayload = {
    members: [{
      email:       buyerEmail,
      name:        buyerName,
      tiers:       [{ id: tierId }],
      labels:      [{ name: 'lemon-squeezy' }, { name: 'lifetime' }],
      note:        `Lifetime member — purchased via Lemon Squeezy. Order ID: ${data.id}`,
      subscribed:  true,
    }]
  };

  let ghostRes;
  try {
    ghostRes = await fetch(ghostEndpoint, {
      method:  'POST',
      headers: {
        'Content-Type':  'application/json',
        'Authorization': `Ghost ${token}`,
      },
      body: JSON.stringify(memberPayload),
    });
  } catch (err) {
    console.error('Ghost API fetch error:', err);
    return res.status(500).json({ error: 'Failed to reach Ghost API' });
  }

  const ghostData = await ghostRes.json();

  // Ghost returns 422 if member already exists — handle gracefully
  if (ghostRes.status === 422) {
    console.log(`Member already exists: ${buyerEmail} — updating tier`);
    
    // Find existing member and update their tier
    const updateResult = await addTierToExistingMember(
      ghostUrl, token, buyerEmail, tierId
    );

    if (updateResult.success) {
      return res.status(200).json({ success: true, action: 'tier_added', email: buyerEmail });
    } else {
      return res.status(500).json({ error: 'Failed to update existing member', detail: updateResult.error });
    }
  }

  if (!ghostRes.ok) {
    console.error('Ghost API error:', ghostRes.status, JSON.stringify(ghostData));
    return res.status(500).json({ error: 'Ghost API error', detail: ghostData });
  }

  console.log(`Member created successfully: ${buyerEmail}`);
  return res.status(200).json({ success: true, action: 'member_created', email: buyerEmail });
}


// ── Ghost JWT generation ─────────────────────────────────────────────────────
// Ghost Admin API requires a short-lived JWT signed with your integration secret.
// This generates one valid for 5 minutes — sufficient for a single API call.
function generateGhostJWT(keyId, keySecret) {
  const now = Math.floor(Date.now() / 1000);

  const header  = { alg: 'HS256', typ: 'JWT', kid: keyId };
  const payload = { iat: now, exp: now + 300, aud: '/admin/' };

  const encode = obj => Buffer.from(JSON.stringify(obj)).toString('base64url');

  const headerB64  = encode(header);
  const payloadB64 = encode(payload);
  const sigInput   = `${headerB64}.${payloadB64}`;

  const secret = Buffer.from(keySecret, 'hex');
  const sig    = crypto.createHmac('sha256', secret).update(sigInput).digest('base64url');

  return `${sigInput}.${sig}`;
}


// ── Add tier to existing Ghost member ────────────────────────────────────────
// If the buyer already has a Ghost account (e.g. free subscriber),
// find them and assign the Lifetime tier without overwriting anything.
async function addTierToExistingMember(ghostUrl, token, email, tierId) {
  try {
    // Find the member by email
    const searchRes = await fetch(
      `${ghostUrl}/ghost/api/admin/members/?filter=email:'${encodeURIComponent(email)}'`,
      { headers: { 'Authorization': `Ghost ${token}` } }
    );
    const searchData = await searchRes.json();
    const member = searchData?.members?.[0];

    if (!member) {
      return { success: false, error: 'Member not found after 422' };
    }

    // Merge existing tiers with new Lifetime tier (avoid duplicates)
    const existingTierIds = (member.tiers || []).map(t => t.id);
    if (existingTierIds.includes(tierId)) {
      console.log(`Member ${email} already has Lifetime tier`);
      return { success: true };
    }

    const updatedTiers = [...(member.tiers || []), { id: tierId }];

    // Update member
    const updateRes = await fetch(
      `${ghostUrl}/ghost/api/admin/members/${member.id}/`,
      {
        method:  'PUT',
        headers: {
          'Content-Type':  'application/json',
          'Authorization': `Ghost ${token}`,
        },
        body: JSON.stringify({
          members: [{
            tiers:  updatedTiers,
            labels: [...(member.labels || []), { name: 'lemon-squeezy' }, { name: 'lifetime' }],
          }]
        }),
      }
    );

    if (!updateRes.ok) {
      const err = await updateRes.json();
      return { success: false, error: err };
    }

    console.log(`Lifetime tier added to existing member: ${email}`);
    return { success: true };

  } catch (err) {
    return { success: false, error: err.message };
  }
}
