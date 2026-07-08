// gig-cancelled/index.ts
// Database webhook handler — sends push notifications when a gig is
// cancelled (status update) or deleted (without prior cancellation).
//
// Called by Supabase database webhook on gigs table (UPDATE + DELETE).
// Payload format: { type: 'UPDATE'|'DELETE', record, old_record }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const FCM_PROJECT_ID = 'tourflow-60890';

// ─── JWT / OAuth2 helpers (same as notify-company) ──────────────────────────

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
    const payload = await req.json();
    const { type, record, old_record } = payload;

    console.log(`[gig-cancelled] type=${type}`);

    // Determine the gig data and whether we should notify
    let gig: any;
    let shouldNotify = false;

    if (type === 'UPDATE') {
      // Only notify when status changes TO cancelled
      const oldStatus = old_record?.status;
      const newStatus = record?.status;
      if (newStatus === 'cancelled' && oldStatus !== 'cancelled') {
        gig = record;
        shouldNotify = true;
        console.log(`[gig-cancelled] Status changed to cancelled: ${gig.id}`);
      }
    } else if (type === 'DELETE') {
      // Only notify if the deleted gig was NOT already cancelled
      gig = old_record;
      if (gig && gig.status !== 'cancelled') {
        shouldNotify = true;
        console.log(`[gig-cancelled] Deleted without prior cancel: ${gig.id}`);
      } else {
        console.log(`[gig-cancelled] Deleted but was already cancelled — skipping`);
      }
    }

    if (!shouldNotify || !gig) {
      return new Response(JSON.stringify({ ok: true, skipped: true }), {
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    const companyId = gig.company_id;
    if (!companyId) {
      return new Response(JSON.stringify({ ok: true, skipped: true, reason: 'no_company_id' }), {
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    // Build notification message
    const venue = gig.venue_name || '';
    const city = gig.city || '';
    const firma = gig.customer_firma || '';
    let dateLabel = '';
    if (gig.date_from) {
      const d = new Date(gig.date_from);
      dateLabel = `${d.getDate()}.${d.getMonth() + 1}.${d.getFullYear()}`;
    }

    const parts: string[] = [];
    if (dateLabel) parts.push(dateLabel);
    if (venue) parts.push(venue);
    else if (city) parts.push(city);
    let body = parts.join(' — ');
    if (firma) body += ` (${firma})`;

    const title = 'Gig avlyst';

    // Get all company members
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: members } = await supabase
      .from('company_members')
      .select('user_id')
      .eq('company_id', companyId);

    const userIds = (members ?? []).map((m: any) => m.user_id);
    if (userIds.length === 0) {
      return new Response(JSON.stringify({ ok: true, sent: 0 }), {
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    // Insert in-app notifications
    const notifRows = userIds.map((uid: string) => ({
      user_id: uid,
      title,
      body,
      read: false,
      type: 'gig_cancelled',
      gig_id: gig.id,
    }));

    const { error: insertErr } = await supabase
      .from('notifications')
      .insert(notifRows);
    if (insertErr) console.error('Insert notifications error:', insertErr.message);

    // Send FCM push
    const { data: profiles } = await supabase
      .from('profiles')
      .select('id, fcm_token')
      .in('id', userIds)
      .not('fcm_token', 'is', null);

    const seenTokens = new Set<string>();
    const tokens = (profiles ?? []).filter((p: any) => {
      if (!p.fcm_token || seenTokens.has(p.fcm_token)) return false;
      seenTokens.add(p.fcm_token);
      return true;
    });

    let sent = 0;
    if (tokens.length > 0) {
      const sa = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT')!);
      const accessToken = await getAccessToken(sa);

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
                  data: { gig_id: gig.id, type: 'gig_cancelled' },
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
          if (fcmRes.ok) sent++;
          else console.error('FCM error:', await fcmRes.json());
        } catch (e) {
          console.error('FCM send error:', e);
        }
      }
    }

    console.log(`[gig-cancelled] Notified ${userIds.length} users, ${sent} push sent`);

    return new Response(
      JSON.stringify({ ok: true, notifications: userIds.length, push: sent }),
      { headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('gig-cancelled error:', err);
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    );
  }
});
