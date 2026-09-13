// reset-password/index.ts — Reset password for a user by ID
// Body: { user_id, password }
//
// Requires the caller's own JWT in the Authorization header, and that the
// caller is an admin in the same company as the target user. Before this the
// function had no auth check at all: anyone who knew the URL and a user_id
// could set that user's password.

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;

    const { user_id, password } = await req.json();
    if (!user_id || !password) {
      return json({ error: 'user_id and password required' }, 400);
    }
    if ((password as string).length < 8) {
      return json({ error: 'Passordet må være minst 8 tegn' }, 400);
    }

    // ── Who is asking? ────────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization') ?? '';
    const token = authHeader.replace(/^Bearer\s+/i, '');
    if (!token) return json({ error: 'Ikke innlogget' }, 401);

    const meRes = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: { apikey: anonKey, Authorization: `Bearer ${token}` },
    });
    if (!meRes.ok) return json({ error: 'Ugyldig sesjon' }, 401);
    const me = await meRes.json();
    const callerId = me?.id as string | undefined;
    if (!callerId) return json({ error: 'Ugyldig sesjon' }, 401);

    const svcHeaders = {
      'Content-Type': 'application/json',
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
    };

    // ── Is the caller an admin in the target user's company? ──────────────
    const targetRes = await fetch(
      `${supabaseUrl}/rest/v1/company_members?select=company_id&user_id=eq.${user_id}`,
      { headers: svcHeaders },
    );
    const targetRows = targetRes.ok ? await targetRes.json() : [];
    const targetCompanies = (targetRows ?? []).map(
      (r: { company_id: string }) => r.company_id,
    );
    if (targetCompanies.length === 0) {
      return json({ error: 'Fant ikke brukeren' }, 404);
    }

    const callerRes = await fetch(
      `${supabaseUrl}/rest/v1/company_members?select=company_id,role&user_id=eq.${callerId}&role=in.(admin,management)`,
      { headers: svcHeaders },
    );
    const callerRows = callerRes.ok ? await callerRes.json() : [];
    const callerAdminCompanies = (callerRows ?? []).map(
      (r: { company_id: string }) => r.company_id,
    );
    const allowed = targetCompanies.some((c: string) =>
      callerAdminCompanies.includes(c),
    );
    if (!allowed) {
      return json({ error: 'Kun administrator kan sette passord' }, 403);
    }

    // ── Set the password ──────────────────────────────────────────────────
    const res = await fetch(`${supabaseUrl}/auth/v1/admin/users/${user_id}`, {
      method: 'PUT',
      headers: svcHeaders,
      body: JSON.stringify({ password }),
    });

    if (!res.ok) return json({ error: await res.text() }, 400);

    return json({ ok: true, user_id });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});
