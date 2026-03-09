// dropbox-list-folder/index.ts
// Supabase Edge Function — lists folder contents from Dropbox.
// Refreshes access token automatically if expired.
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
    // Service-role client
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
    const { company_id, path } = body;

    if (!company_id || path === undefined) {
      return jsonResponse({ error: 'Missing company_id or path' }, 400);
    }

    // Verify user is member of this company
    const { data: membership } = await sb
      .from('company_members')
      .select('role')
      .eq('company_id', company_id)
      .eq('user_id', user.id)
      .maybeSingle();

    if (!membership) {
      return jsonResponse({ error: 'Access denied' }, 403);
    }

    // Get valid access token
    const accessToken = await getValidAccessToken(sb, company_id);

    // Call Dropbox list_folder
    const listRes = await fetch('https://api.dropboxapi.com/2/files/list_folder', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        path: path || '',
        recursive: false,
        include_media_info: false,
        include_deleted: false,
      }),
    });

    if (!listRes.ok) {
      const errText = await listRes.text();
      console.error('Dropbox list_folder error:', errText);
      return jsonResponse({ error: 'Dropbox API error' }, 502);
    }

    const listData = await listRes.json();

    // Map entries to simpler format
    const entries = (listData.entries || []).map((e: Record<string, unknown>) => ({
      name: e.name as string,
      path: e.path_lower as string,
      is_folder: e['.tag'] === 'folder',
      size: e.size as number | undefined ?? 0,
    }));

    // Sort: folders first, then alphabetical
    entries.sort((a: { is_folder: boolean; name: string }, b: { is_folder: boolean; name: string }) => {
      if (a.is_folder !== b.is_folder) return a.is_folder ? -1 : 1;
      return a.name.localeCompare(b.name);
    });

    return jsonResponse({ entries });

  } catch (err) {
    console.error('dropbox-list-folder error:', err);
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

async function getValidAccessToken(
  sb: ReturnType<typeof createClient>,
  companyId: string,
): Promise<string> {
  const { data: token, error } = await sb
    .from('dropbox_tokens')
    .select('access_token, refresh_token, expires_at')
    .eq('company_id', companyId)
    .maybeSingle();

  if (error || !token) {
    throw new Error('Dropbox not connected for this company');
  }

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
