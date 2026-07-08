// create-tenant-company/index.ts
// Creates a new TENANT company (owner_company_id = NULL) and optionally
// adds a first admin user (either the calling platform admin or a brand
// new auth user).
//
// Only the platform owner (hardcoded to michael@nttas.com) may call this.
//
// Body:
//   name           (string, required)
//   org_nr         (string, optional)
//   address        (string, optional)
//   postal_code    (string, optional)
//   city           (string, optional)
//   country        (string, optional)
//   app_mode       ('css' | 'management', default 'css')
//   first_admin    ({ mode: 'self' } | { mode: 'new', name, email, phone? })
//
// Deploy with:
//   supabase functions deploy create-tenant-company --no-verify-jwt \
//     --project-ref fqefvgqlrntwgschkugf

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

const TEMP_PASSWORD = 'TourFlow2026';

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405, headers: CORS_HEADERS });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json(401, { error: 'Unauthorized' });
    const accessToken = authHeader.replace(/^Bearer\s+/i, '');

    // --- Resolve caller via /auth/v1/user ---
    const meRes = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: { apikey: serviceKey, Authorization: `Bearer ${accessToken}` },
    });
    if (!meRes.ok) return json(401, { error: 'Invalid session token' });
    const me = await meRes.json() as { id: string; email?: string };
    const callerId = me.id;
    const callerEmail = (me.email ?? '').toLowerCase();

    // --- Verify caller is the platform owner (hardcoded identity) ---
    if (callerEmail !== 'michael@nttas.com') {
      return json(403, { error: 'Forbidden: platform owner only' });
    }

    // --- Parse body ---
    const body = await req.json() as {
      name: string;
      org_nr?: string | null;
      address?: string | null;
      postal_code?: string | null;
      city?: string | null;
      country?: string | null;
      app_mode?: 'css' | 'management';
      first_admin?:
        | { mode: 'self' }
        | { mode: 'new'; name: string; email: string; phone?: string }
        | { mode: 'none' };
    };

    if (!body.name || !body.name.trim()) {
      return json(400, { error: 'name is required' });
    }

    const appMode: 'css' | 'management' = body.app_mode === 'management' ? 'management' : 'css';

    // --- 1. Create company (tenant — owner_company_id stays NULL) ---
    const companyPayload: Record<string, unknown> = {
      name: body.name.trim(),
      org_nr: body.org_nr?.trim() || null,
      address: body.address?.trim() || null,
      postal_code: body.postal_code?.trim() || null,
      city: body.city?.trim() || null,
      country: body.country?.trim() || null,
    };

    const companyRes = await fetch(`${supabaseUrl}/rest/v1/companies`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        Prefer: 'return=representation',
      },
      body: JSON.stringify(companyPayload),
    });
    if (!companyRes.ok) {
      const err = await companyRes.text();
      return json(500, { error: `Failed to insert company: ${err}` });
    }
    const companyRows = await companyRes.json() as Array<{ id: string }>;
    const companyId = companyRows[0].id;

    // --- 2. First admin handling ---
    const firstAdmin = body.first_admin ?? { mode: 'self' as const };

    async function addMembership(userId: string, role: string) {
      const r = await fetch(`${supabaseUrl}/rest/v1/company_members`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
          Prefer: 'resolution=merge-duplicates',
        },
        body: JSON.stringify({
          user_id: userId,
          company_id: companyId,
          role,
          app_mode: appMode,
        }),
      });
      if (!r.ok) {
        const err = await r.text();
        throw new Error(`company_members insert failed: ${err}`);
      }
    }

    let createdUser: { id: string; email: string; temp_password?: string } | null = null;

    if (firstAdmin.mode === 'self') {
      await addMembership(callerId, 'admin');
    } else if (firstAdmin.mode === 'new') {
      if (!firstAdmin.email || !firstAdmin.name) {
        return json(400, { error: 'first_admin.email and first_admin.name required' });
      }

      // Create auth user
      const createRes = await fetch(`${supabaseUrl}/auth/v1/admin/users`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
        },
        body: JSON.stringify({
          email: firstAdmin.email,
          password: TEMP_PASSWORD,
          email_confirm: true,
          user_metadata: { name: firstAdmin.name },
        }),
      });
      if (!createRes.ok) {
        const err = await createRes.text();
        return json(400, { error: `Failed to create auth user: ${err}` });
      }
      const newAuthUser = await createRes.json() as { id: string };
      const newUserId = newAuthUser.id;

      // Force password hash
      await fetch(`${supabaseUrl}/auth/v1/admin/users/${newUserId}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
        },
        body: JSON.stringify({ password: TEMP_PASSWORD }),
      });

      // Upsert profile
      await fetch(`${supabaseUrl}/rest/v1/profiles`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
          Prefer: 'resolution=merge-duplicates',
        },
        body: JSON.stringify({
          id: newUserId,
          name: firstAdmin.name,
          email: firstAdmin.email,
          phone: firstAdmin.phone ?? null,
          role: 'admin',
          company_id: companyId,
        }),
      });

      await addMembership(newUserId, 'admin');

      createdUser = {
        id: newUserId,
        email: firstAdmin.email,
        temp_password: TEMP_PASSWORD,
      };
    }
    // mode === 'none': just create the company, no membership

    return json(200, {
      ok: true,
      company_id: companyId,
      created_user: createdUser,
    });
  } catch (err) {
    console.error('create-tenant-company error:', err);
    return json(500, { error: String(err) });
  }
});
