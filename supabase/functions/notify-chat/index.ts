// notify-chat/index.ts
// Sends push + in-app notification for chat messages.
//
// Payloads:
//   { type: 'direct', receiver_id, sender_name, message, mentioned_user_ids? }
//   { type: 'group', group_id, sender_id, sender_name, message, mentioned_user_ids? }
//   { type: 'gig', gig_id, company_id, sender_id, sender_name, message, mentioned_user_ids? }

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

// ─── Send push to a list of user IDs ─────────────────────────────────────────

async function sendPushBatch(
  supabase: any,
  userIds: string[],
  title: string,
  body: string,
  _excludeFcmForUserId?: string,
  notificationType: string = 'general',
  gigId?: string,
  extraFields?: Record<string, string>,
): Promise<{ notifications: number; push: number }> {
  if (userIds.length === 0) return { notifications: 0, push: 0 };

  console.log(`[sendPushBatch] userIds=${JSON.stringify(userIds)} type=${notificationType}`);

  // 1. Insert in-app notifications
  const baseRows = userIds.map(uid => ({
    user_id: uid,
    title,
    body,
    read: false,
    type: notificationType,
    ...(gigId ? { gig_id: gigId } : {}),
    ...(extraFields?.peer_id ? { peer_id: extraFields.peer_id } : {}),
    ...(extraFields?.group_id ? { group_id: extraFields.group_id } : {}),
    ...(extraFields?.group_name ? { group_name: extraFields.group_name } : {}),
  }));

  let { error: insertError } = await supabase
    .from('notifications')
    .insert(baseRows);

  // Fallback: if insert fails (e.g. new columns not yet migrated), retry without extra fields
  if (insertError) {
    console.error('Insert notifications error (retrying without extra fields):', insertError.message);
    const fallbackRows = userIds.map(uid => ({
      user_id: uid,
      title,
      body,
      read: false,
      type: notificationType,
      ...(gigId ? { gig_id: gigId } : {}),
    }));
    const { error: fallbackError } = await supabase
      .from('notifications')
      .insert(fallbackRows);
    if (fallbackError) console.error('Fallback insert also failed:', fallbackError.message);
  }

  // 2. Fetch FCM tokens for recipients
  const { data: profiles } = await supabase
    .from('profiles')
    .select('id, fcm_token')
    .in('id', userIds)
    .not('fcm_token', 'is', null);

  const allTokens = (profiles ?? []).filter((p: any) => p.fcm_token);
  console.log(`[sendPushBatch] FCM profiles found: ${allTokens.length} (of ${userIds.length} recipients)`);

  // Deduplicate by FCM token — same device should only get 1 push
  const seenTokens = new Set<string>();
  const tokens = allTokens.filter((p: any) => {
    if (seenTokens.has(p.fcm_token)) return false;
    seenTokens.add(p.fcm_token);
    return true;
  });

  console.log(`[sendPushBatch] Unique tokens to send: ${tokens.length}`);
  if (tokens.length === 0) return { notifications: userIds.length, push: 0 };

  // 3. Firebase access token
  const sa = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT')!);
  const accessToken = await getAccessToken(sa);

  // 4. Send FCM push
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
                ...(gigId ? { gig_id: gigId } : {}),
                ...(extraFields ?? {}),
                ...(_excludeFcmForUserId ? { sender_id: _excludeFcmForUserId } : {}),
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
      if (fcmRes.ok) sent++;
      else console.error('FCM error for', profile.id, await fcmRes.json());
    } catch (e) {
      console.error('FCM send error:', e);
    }
  }

  return { notifications: userIds.length, push: sent };
}

// ─── MAIN ────────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  try {
    const payload = await req.json();
    const { type } = payload;

    if (!type) {
      return new Response(
        JSON.stringify({ error: 'type is required (direct|group|gig)' }),
        { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      );
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Truncate message for push preview
    const preview = (payload.message ?? '').substring(0, 100);

    let recipientIds: string[] = [];

    // ── DIRECT MESSAGE ───────────────────────────────────────────────────────
    if (type === 'direct') {
      const { receiver_id, sender_id, sender_name, mentioned_user_ids } = payload;
      if (!receiver_id || !sender_name) {
        return new Response(
          JSON.stringify({ error: 'receiver_id and sender_name required' }),
          { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
        );
      }
      const mentionSet = new Set<string>(mentioned_user_ids ?? []);
      const mentionedRecipients = [receiver_id].filter((uid: string) => mentionSet.has(uid));
      const normalRecipients = [receiver_id].filter((uid: string) => !mentionSet.has(uid));

      const dmExtra = { chat_type: 'dm', peer_id: sender_id, peer_name: sender_name };

      let totalResult = { notifications: 0, push: 0 };
      if (mentionedRecipients.length > 0) {
        const mentionPreview = `${sender_name} nevnte deg: ${preview}`;
        const r = await sendPushBatch(supabase, mentionedRecipients, sender_name, mentionPreview, sender_id, 'chat_mention', undefined, dmExtra);
        totalResult.notifications += r.notifications;
        totalResult.push += r.push;
      }
      if (normalRecipients.length > 0) {
        const r = await sendPushBatch(supabase, normalRecipients, sender_name, preview, sender_id, 'chat_dm', undefined, dmExtra);
        totalResult.notifications += r.notifications;
        totalResult.push += r.push;
      }
      return new Response(JSON.stringify({ ok: true, ...totalResult }), {
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    // ── GROUP CHAT ───────────────────────────────────────────────────────────
    if (type === 'group') {
      const { group_id, sender_id, sender_name, mentioned_user_ids } = payload;
      if (!group_id || !sender_id || !sender_name) {
        return new Response(
          JSON.stringify({ error: 'group_id, sender_id, sender_name required' }),
          { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
        );
      }

      const { data: members } = await supabase
        .from('group_chat_members')
        .select('user_id')
        .eq('group_chat_id', group_id);

      // Fetch group name for deep-link navigation
      const { data: groupRow } = await supabase
        .from('group_chats')
        .select('name')
        .eq('id', group_id)
        .maybeSingle();
      const groupName = groupRow?.name ?? '';

      recipientIds = (members ?? [])
        .map((m: any) => m.user_id)
        .filter((uid: string) => uid !== sender_id);

      const mentionSet = new Set<string>(mentioned_user_ids ?? []);
      const mentionedRecipients = recipientIds.filter((uid: string) => mentionSet.has(uid));
      const normalRecipients = recipientIds.filter((uid: string) => !mentionSet.has(uid));

      const groupExtra = { chat_type: 'group', group_id, group_name: groupName };

      let totalResult = { notifications: 0, push: 0 };
      if (mentionedRecipients.length > 0) {
        const mentionPreview = `${sender_name} nevnte deg: ${preview}`;
        const r = await sendPushBatch(supabase, mentionedRecipients, sender_name, mentionPreview, sender_id, 'chat_mention', undefined, groupExtra);
        totalResult.notifications += r.notifications;
        totalResult.push += r.push;
      }
      if (normalRecipients.length > 0) {
        const r = await sendPushBatch(supabase, normalRecipients, sender_name, preview, sender_id, 'chat_group', undefined, groupExtra);
        totalResult.notifications += r.notifications;
        totalResult.push += r.push;
      }
      return new Response(JSON.stringify({ ok: true, ...totalResult }), {
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    // ── GIG MESSAGE ──────────────────────────────────────────────────────────
    if (type === 'gig') {
      const { gig_id, company_id, sender_id, sender_name, mentioned_user_ids } = payload;
      if (!company_id || !sender_id || !sender_name) {
        return new Response(
          JSON.stringify({ error: 'company_id, sender_id, sender_name required' }),
          { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
        );
      }

      // Send to all company members (gig chat is visible to all)
      const { data: members } = await supabase
        .from('company_members')
        .select('user_id')
        .eq('company_id', company_id);

      recipientIds = (members ?? [])
        .map((m: any) => m.user_id)
        .filter((uid: string) => uid !== sender_id);

      // Fetch gig name for notification title
      let gigLabel = 'Gig chat';
      if (gig_id) {
        const { data: gig } = await supabase
          .from('gigs')
          .select('venue_name, city, date_from')
          .eq('id', gig_id)
          .maybeSingle();
        if (gig) {
          const parts: string[] = [];
          if (gig.date_from) {
            const d = new Date(gig.date_from);
            parts.push(`${d.getDate()}.${d.getMonth() + 1}`);
          }
          if (gig.venue_name) parts.push(gig.venue_name);
          if (parts.length > 0) {
            gigLabel = parts.join(' · ');
          }
        }
      }

      const title = `${sender_name} · ${gigLabel}`;
      const mentionSet = new Set<string>(mentioned_user_ids ?? []);
      const mentionedRecipients = recipientIds.filter((uid: string) => mentionSet.has(uid));
      const normalRecipients = recipientIds.filter((uid: string) => !mentionSet.has(uid));

      const gigExtra = { chat_type: 'gig' };

      let totalResult = { notifications: 0, push: 0 };
      if (mentionedRecipients.length > 0) {
        const mentionPreview = `${sender_name} nevnte deg: ${preview}`;
        const r = await sendPushBatch(supabase, mentionedRecipients, title, mentionPreview, sender_id, 'chat_mention', gig_id, gigExtra);
        totalResult.notifications += r.notifications;
        totalResult.push += r.push;
      }
      if (normalRecipients.length > 0) {
        const r = await sendPushBatch(supabase, normalRecipients, title, preview, sender_id, 'gig_chat', gig_id, gigExtra);
        totalResult.notifications += r.notifications;
        totalResult.push += r.push;
      }
      return new Response(JSON.stringify({ ok: true, ...totalResult }), {
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    return new Response(
      JSON.stringify({ error: `Unknown type: ${type}` }),
      { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('notify-chat error:', err);
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    );
  }
});
