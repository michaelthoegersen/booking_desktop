// notify-company/index.ts
// Sends push notification + in-app notification to ALL members of a company.
// Used when admin creates a new gig, etc.
//
// Payload:
//   { company_id, title, body, exclude_user_id?, gig_id?, role_filter? }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const FCM_PROJECT_ID = 'tourflow-60890';

// ─── JWT / OAuth2 helpers ────────────────────────────────────────────────────

function base64url(data: Uint8Array | string): string {
  let b64: string;
  if (typeof data === 'string') {
    b64 = btoa(data);
  } else {
    let s = '';
    data.forEach(byte => (s += String.fromCharCode(byte)));
    b64 = btoa(s);
  }
  return b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

async function importPkcs8Key(pem: string): Promise<CryptoKey> {
  const pemBody = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '');
  const binary = atob(pemBody);
  const buf = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) buf[i] = binary.charCodeAt(i);
  return crypto.subtle.importKey(
    'pkcs8', buf,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false, ['sign'],
  );
}

async function getAccessToken(sa: { client_email: string; private_key: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = base64url(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now, exp: now + 3600,
  }));
  const signingInput = `${header}.${payload}`;
  const key = await importPkcs8Key(sa.private_key);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(signingInput));
  const jwt = `${signingInput}.${base64url(new Uint8Array(sig))}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`OAuth2 failed: ${await res.text()}`);
  return (await res.json()).access_token as string;
}

// ─── MAIN ────────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  try {
    const { company_id, title, body = '', exclude_user_id, gig_id, role_filter, type: notifType = 'gig' } = await req.json();

    if (!company_id || !title) {
      return new Response(
        JSON.stringify({ error: 'company_id and title are required' }),
        { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      );
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // 1. Get company members (optionally filtered by role)
    let query = supabase
      .from('company_members')
      .select('user_id, role')
      .eq('company_id', company_id);

    if (role_filter) {
      query = query.eq('role', role_filter);
    }

    const { data: members, error: membersError } = await query;

    if (membersError) {
      console.error('Error fetching members:', membersError);
      return new Response(
        JSON.stringify({ error: 'Failed to fetch company members' }),
        { status: 500, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      );
    }

    // Filter out the sender
    const userIds = (members ?? [])
      .map(m => m.user_id)
      .filter(uid => uid !== exclude_user_id);

    if (userIds.length === 0) {
      return new Response(
        JSON.stringify({ ok: true, sent: 0, reason: 'no_recipients' }),
        { headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      );
    }

    // 2. Insert in-app notifications for all recipients
    const notificationRows = userIds.map(uid => ({
      user_id: uid,
      title,
      body,
      read: false,
      type: notifType,
      ...(gig_id ? { gig_id } : {}),
    }));

    const { error: insertError } = await supabase
      .from('notifications')
      .insert(notificationRows);

    if (insertError) {
      console.error('Insert notifications error:', insertError);
    }

    // 3. Fetch FCM tokens for all recipients
    const { data: profiles } = await supabase
      .from('profiles')
      .select('id, fcm_token')
      .in('id', userIds)
      .not('fcm_token', 'is', null);

    const allTokens = (profiles ?? []).filter(p => p.fcm_token);

    // Deduplicate by FCM token — same device should only get 1 push
    // (handles duplicate profiles with same token)
    const seenTokens = new Set<string>();
    const tokens = allTokens.filter(p => {
      if (seenTokens.has(p.fcm_token)) return false;
      seenTokens.add(p.fcm_token);
      return true;
    });

    if (tokens.length === 0) {
      return new Response(
        JSON.stringify({ ok: true, notifications: userIds.length, push: 0, reason: 'no_fcm_tokens' }),
        { headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      );
    }

    // 4. Get Firebase access token
    const sa = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT')!);
    const accessToken = await getAccessToken(sa);

    // 5. Send FCM push to each unique token
    let sent = 0;
    for (const profile of tokens) {
      try {
        const fcmRes = await fetch(
          `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`,
          {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${accessToken}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              message: {
                token: profile.fcm_token,
                notification: { title, body },
                data: {
                  ...(gig_id ? { gig_id } : {}),
                  type: 'gig',
                },
                apns: {
                  payload: { aps: { sound: 'default', badge: 1, 'content-available': 1 } },
                },
                android: {
                  priority: 'high',
                  notification: { sound: 'default' },
                },
              },
            }),
          },
        );

        if (fcmRes.ok) {
          sent++;
        } else {
          const err = await fcmRes.json();
          console.error('FCM error for', profile.id, err);
        }
      } catch (e) {
        console.error('FCM send error:', e);
      }
    }

    return new Response(
      JSON.stringify({ ok: true, notifications: userIds.length, push: sent }),
      { headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('notify-company error:', err);
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    );
  }
});
