// send-push/index.ts
// Unified push notification function — handles BOTH:
//   1. CSS mode:      { job_id }           → looks up drivers from samletdata
//   2. Complete mode:  { user_id, title, body, draft_id? } → sends to specific user

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

// ─── Send FCM push to a single token ─────────────────────────────────────────

async function sendFcm(
  accessToken: string,
  fcmToken: string,
  title: string,
  body: string,
  data?: Record<string, string>,
): Promise<any> {
  const res = await fetch(
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
          ...(data && Object.keys(data).length > 0 ? { data } : {}),
          apns: {
            payload: {
              aps: { sound: 'default', badge: 1, 'content-available': 1 },
            },
          },
          android: {
            priority: 'high',
            notification: { sound: 'default' },
          },
        },
      }),
    },
  );
  return { ok: res.ok, result: await res.json() };
}

// ─── MAIN ────────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405, headers: CORS_HEADERS });
  }

  try {
    const payload = await req.json();
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const sa = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT')!);

    // =====================================================================
    // MODE 1: CSS — { job_id } → notify assigned drivers from samletdata
    // =====================================================================
    if (payload.job_id) {
      const { job_id } = payload;

      const { data: job, error: jobError } = await supabase
        .from('samletdata')
        .select('sjafor, d_drive')
        .eq('id', job_id)
        .single();

      if (jobError || !job) {
        return new Response(
          JSON.stringify({ error: 'Job not found' }),
          { status: 404, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
        );
      }

      const drivers = [job.sjafor, job.d_drive].filter(Boolean);
      if (drivers.length === 0) {
        return new Response(
          JSON.stringify({ message: 'No drivers assigned' }),
          { status: 200, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
        );
      }

      const { data: profiles } = await supabase
        .from('profiles')
        .select('id, name, fcm_token')
        .in('name', drivers);

      if (!profiles || profiles.length === 0) {
        return new Response(
          JSON.stringify({ message: 'No profiles found' }),
          { status: 200, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
        );
      }

      // Insert in-app notification for each driver
      const notificationRows = profiles.map(p => ({
        user_id: p.id,
        title: 'Ny jobb tildelt 🚍',
        body: 'Du har fått en ny jobb i TourFlow',
        read: false,
        type: 'tour',
        draft_id: job_id,
      }));

      const { error: insertError } = await supabase
        .from('notifications')
        .insert(notificationRows);

      if (insertError) {
        console.error('Insert CSS notifications error:', insertError);
      }

      // Send FCM push to drivers with tokens
      const withTokens = profiles.filter(p => p.fcm_token);
      if (withTokens.length === 0) {
        return new Response(
          JSON.stringify({ ok: true, notifications: profiles.length, push: 0, reason: 'no_fcm_tokens' }),
          { headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
        );
      }

      const accessToken = await getAccessToken(sa);
      const results: any[] = [];

      for (const profile of withTokens) {
        const fcmResult = await sendFcm(
          accessToken,
          profile.fcm_token,
          'Ny jobb tildelt 🚍',
          'Du har fått en ny jobb i TourFlow',
          { draft_id: job_id, type: 'tour' },
        );
        results.push({ name: profile.name, response: fcmResult.result });
      }

      return new Response(
        JSON.stringify({ ok: true, notifications: profiles.length, push: results.length, results }),
        { headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      );
    }

    // =====================================================================
    // MODE 2: Complete — { user_id, title, body?, draft_id? }
    // =====================================================================
    const { user_id, title, body = '', draft_id, gig_id, type } = payload;

    if (!user_id || !title) {
      return new Response(
        JSON.stringify({ error: 'user_id and title are required (or provide job_id for CSS mode)' }),
        { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      );
    }

    // 1. Insert in-app notification (bell)
    const { error: insertError } = await supabase
      .from('notifications')
      .insert({
        user_id, title, body, read: false,
        draft_id: draft_id ?? null,
        ...(gig_id ? { gig_id } : {}),
        ...(type ? { type } : {}),
      });

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

    // 3. Send FCM push
    const accessToken = await getAccessToken(sa);
    const fcmData: Record<string, string> = {};
    if (gig_id) fcmData.gig_id = gig_id;
    if (type) fcmData.type = type;
    if (draft_id) fcmData.draft_id = draft_id;
    const fcmResult = await sendFcm(accessToken, fcmToken, title, body, fcmData);

    if (!fcmResult.ok) {
      console.error('FCM error:', fcmResult.result);
    } else {
      console.log('FCM push sent:', fcmResult.result);
    }

    return new Response(
      JSON.stringify({ ok: true, push: fcmResult.ok, fcm: fcmResult.result }),
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
