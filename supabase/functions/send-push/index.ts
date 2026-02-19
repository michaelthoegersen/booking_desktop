// send-push/index.ts
// Supabase Edge Function — inserts a notification row + sends FCM v1 push
//
// Required secrets (set via Supabase dashboard or CLI):
//   FIREBASE_SERVICE_ACCOUNT  — full service-account JSON (one line, no newlines)
//   SUPABASE_URL              — auto-injected by Supabase
//   SUPABASE_SERVICE_ROLE_KEY — auto-injected by Supabase

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const FCM_PROJECT_ID = 'tourflow-60890';

// ──────────────────────────────────────────────────────────────────────────────
// JWT / OAuth2 helpers (Deno Web Crypto — no external deps)
// ──────────────────────────────────────────────────────────────────────────────

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
    'pkcs8',
    buf,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

async function makeServiceAccountJwt(sa: {
  client_email: string;
  private_key: string;
}): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = base64url(
    JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );

  const signingInput = `${header}.${payload}`;
  const key = await importPkcs8Key(sa.private_key);
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(signingInput),
  );

  return `${signingInput}.${base64url(new Uint8Array(sig))}`;
}

async function getAccessToken(sa: {
  client_email: string;
  private_key: string;
}): Promise<string> {
  const jwt = await makeServiceAccountJwt(sa);

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`OAuth2 token exchange failed: ${text}`);
  }

  const json = await res.json();
  return json.access_token as string;
}

// ──────────────────────────────────────────────────────────────────────────────
// MAIN HANDLER
// ──────────────────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  // CORS pre-flight
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405, headers: CORS_HEADERS });
  }

  try {
    const { user_id, title, body = '', draft_id } = await req.json() as {
      user_id: string;
      title: string;
      body?: string;
      draft_id?: string;
    };

    if (!user_id || !title) {
      return new Response(
        JSON.stringify({ error: 'user_id and title are required' }),
        { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      );
    }

    // ── Supabase admin client ────────────────────────────────────────────────
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // 1. Insert in-app notification (bell)
    const { error: insertError } = await supabase
      .from('notifications')
      .insert({ user_id, title, body, read: false, draft_id: draft_id ?? null });

    if (insertError) {
      console.error('Insert notification error:', insertError);
    }

    // 2. Fetch FCM token
    const { data: profile } = await supabase
      .from('profiles')
      .select('fcm_token')
      .eq('id', user_id)
      .maybeSingle();

    const fcmToken: string | null = profile?.fcm_token ?? null;

    if (!fcmToken) {
      console.log('No FCM token for user', user_id, '— notification saved, push skipped');
      return new Response(
        JSON.stringify({ ok: true, push: false, reason: 'no_fcm_token' }),
        { headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      );
    }

    // 3. Get Firebase OAuth2 access token
    const serviceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
    if (!serviceAccountJson) {
      throw new Error('FIREBASE_SERVICE_ACCOUNT secret is not set');
    }
    const sa = JSON.parse(serviceAccountJson);
    const accessToken = await getAccessToken(sa);

    // 4. Send FCM v1 push
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
            token: fcmToken,
            notification: { title, body },
            // iOS-specific: enable sound and badge
            apns: {
              payload: {
                aps: {
                  sound: 'default',
                  badge: 1,
                  'content-available': 1,
                },
              },
            },
            // Android-specific: high priority
            android: {
              priority: 'high',
              notification: {
                sound: 'default',
              },
            },
          },
        }),
      },
    );

    const fcmResult = await fcmRes.json();

    if (!fcmRes.ok) {
      console.error('FCM error:', fcmResult);
    } else {
      console.log('FCM push sent:', fcmResult);
    }

    return new Response(
      JSON.stringify({ ok: true, push: fcmRes.ok, fcm: fcmResult }),
      { headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('send-push error:', err);
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    );
  }
});
