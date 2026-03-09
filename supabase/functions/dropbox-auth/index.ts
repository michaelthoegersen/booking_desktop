// dropbox-auth/index.ts
// Supabase Edge Function — Dropbox OAuth2 token exchange, status, disconnect.
//
// Required secrets:
//   DROPBOX_APP_KEY
//   DROPBOX_APP_SECRET
//   SUPABASE_URL              — auto-injected
//   SUPABASE_SERVICE_ROLE_KEY — auto-injected

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  try {
    // Service-role client for DB operations
    const sb = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Verify caller is authenticated
    const authHeader = req.headers.get('authorization') ?? '';
    const token = authHeader.replace('Bearer ', '');
    const { data: { user }, error: authErr } = await sb.auth.getUser(token);
    if (authErr || !user) {
      return jsonResponse({ error: 'Unauthorized' }, 401);
    }

    const body = await req.json();
    const { action, company_id } = body;

    if (!company_id) {
      return jsonResponse({ error: 'Missing company_id' }, 400);
    }

    // Verify user is admin of this company
    const { data: membership } = await sb
      .from('company_members')
      .select('role')
      .eq('company_id', company_id)
      .eq('user_id', user.id)
      .maybeSingle();

    if (!membership || !['admin', 'management'].includes(membership.role)) {
      return jsonResponse({ error: 'Admin access required' }, 403);
    }

    // ── EXCHANGE ──────────────────────────────────────────────
    if (action === 'exchange') {
      const { code, code_verifier, redirect_uri } = body;
      if (!code || !code_verifier || !redirect_uri) {
        return jsonResponse({ error: 'Missing code, code_verifier, or redirect_uri' }, 400);
      }

      const appKey = Deno.env.get('DROPBOX_APP_KEY')!;
      const appSecret = Deno.env.get('DROPBOX_APP_SECRET')!;

      // Exchange authorization code for tokens
      const tokenRes = await fetch('https://api.dropboxapi.com/oauth2/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          code,
          grant_type: 'authorization_code',
          code_verifier,
          client_id: appKey,
          client_secret: appSecret,
          redirect_uri,
        }),
      });

      if (!tokenRes.ok) {
        const err = await tokenRes.text();
        console.error('Dropbox token exchange failed:', err);
        return jsonResponse({ error: 'Token exchange failed' }, 502);
      }

      const tokenData = await tokenRes.json();
      const accessToken = tokenData.access_token as string;
      const refreshToken = tokenData.refresh_token as string;
      const expiresIn = tokenData.expires_in as number; // seconds

      const expiresAt = new Date(Date.now() + expiresIn * 1000).toISOString();

      // Get account display name
      let accountName = '';
      try {
        const acctRes = await fetch('https://api.dropboxapi.com/2/users/get_current_account', {
          method: 'POST',
          headers: { Authorization: `Bearer ${accessToken}` },
        });
        if (acctRes.ok) {
          const acct = await acctRes.json();
          accountName = acct.name?.display_name ?? '';
        }
      } catch (_) { /* ignore */ }

      // Upsert token row
      const { error: upsertErr } = await sb
        .from('dropbox_tokens')
        .upsert({
          company_id,
          access_token: accessToken,
          refresh_token: refreshToken,
          expires_at: expiresAt,
          account_display_name: accountName,
          updated_at: new Date().toISOString(),
        }, { onConflict: 'company_id' });

      if (upsertErr) {
        console.error('Upsert error:', upsertErr);
        return jsonResponse({ error: 'Failed to save tokens' }, 500);
      }

      return jsonResponse({ connected: true, account_name: accountName });
    }

    // ── STATUS ────────────────────────────────────────────────
    if (action === 'status') {
      const { data: token } = await sb
        .from('dropbox_tokens')
        .select('account_display_name')
        .eq('company_id', company_id)
        .maybeSingle();

      return jsonResponse({
        connected: !!token,
        account_name: token?.account_display_name ?? null,
      });
    }

    // ── DISCONNECT ────────────────────────────────────────────
    if (action === 'disconnect') {
      // Revoke Dropbox token
      const { data: token } = await sb
        .from('dropbox_tokens')
        .select('access_token, refresh_token, expires_at')
        .eq('company_id', company_id)
        .maybeSingle();

      if (token) {
        const validToken = await getValidAccessToken(sb, company_id, token);
        try {
          await fetch('https://api.dropboxapi.com/2/auth/token/revoke', {
            method: 'POST',
            headers: { Authorization: `Bearer ${validToken}` },
          });
        } catch (_) { /* best effort */ }
      }

      // Delete tokens + shared folders
      await sb.from('dropbox_shared_folders').delete().eq('company_id', company_id);
      await sb.from('dropbox_tokens').delete().eq('company_id', company_id);

      return jsonResponse({ connected: false });
    }

    return jsonResponse({ error: `Unknown action: ${action}` }, 400);

  } catch (err) {
    console.error('dropbox-auth error:', err);
    return jsonResponse({ error: String(err) }, 500);
  }
});


// ── Helpers ────────────────────────────────────────────────

function jsonResponse(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

/** Refresh the Dropbox access token if expired (or about to expire). */
async function getValidAccessToken(
  sb: ReturnType<typeof createClient>,
  companyId: string,
  token: { access_token: string; refresh_token: string; expires_at: string },
): Promise<string> {
  const expiresAt = new Date(token.expires_at).getTime();
  const now = Date.now();
  const fiveMin = 5 * 60 * 1000;

  if (expiresAt - now > fiveMin) {
    return token.access_token;
  }

  // Refresh
  const appKey = Deno.env.get('DROPBOX_APP_KEY')!;
  const appSecret = Deno.env.get('DROPBOX_APP_SECRET')!;

  const res = await fetch('https://api.dropboxapi.com/oauth2/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: token.refresh_token,
      client_id: appKey,
      client_secret: appSecret,
    }),
  });

  if (!res.ok) {
    throw new Error(`Token refresh failed: ${await res.text()}`);
  }

  const data = await res.json();
  const newAccessToken = data.access_token as string;
  const newExpiresAt = new Date(Date.now() + (data.expires_in as number) * 1000).toISOString();

  await sb
    .from('dropbox_tokens')
    .update({
      access_token: newAccessToken,
      expires_at: newExpiresAt,
      updated_at: new Date().toISOString(),
    })
    .eq('company_id', companyId);

  return newAccessToken;
}
