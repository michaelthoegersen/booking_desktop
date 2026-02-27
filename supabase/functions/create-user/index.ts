// create-user/index.ts
// Supabase Edge Function — oppretter en ny bruker med admin-rettigheter
//
// Body-parametere:
//   name        (string, required)
//   email       (string, required)
//   role        (string, default: 'user') — 'admin' | 'gruppeleder' | 'bruker'
//   company_id  (string, optional) — påkrevd når role = 'management'
//
// Krever: Authorization: Bearer <session-token> fra en pålogget admin

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== 'POST') {
    return new Response('Method not allowed', {
      status: 405,
      headers: CORS_HEADERS,
    });
  }

  try {
    // --- Supabase admin client (service role) ---
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    // --- Verify caller is authenticated ---
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    // --- Parse body ---
    const { name, email, role, company_id } = await req.json() as {
      name: string;
      email: string;
      role?: string;
      company_id?: string;
    };

    if (!name || !email) {
      return new Response(
        JSON.stringify({ error: 'name and email are required' }),
        {
          status: 400,
          headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
        },
      );
    }

    const userRole = role || 'user';

    // Fixed password — user changes it in the mobile app
    const tempPassword = 'Complete2026';

    // --- Create auth user ---
    const createRes = await fetch(
      `${supabaseUrl}/auth/v1/admin/users`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
        },
        body: JSON.stringify({
          email,
          password: tempPassword,
          email_confirm: true, // skip email verification
          user_metadata: { name },
        }),
      },
    );

    if (!createRes.ok) {
      const err = await createRes.text();
      console.error('Auth user create error:', err);
      return new Response(
        JSON.stringify({ error: `Failed to create auth user: ${err}` }),
        {
          status: 400,
          headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
        },
      );
    }

    const newUser = await createRes.json();
    const userId = newUser.id as string;

    // --- Upsert profile with role and company_id ---
    const profileData: Record<string, unknown> = {
      id: userId,
      name,
      email,
      role: userRole,
    };

    if (company_id) {
      profileData['company_id'] = company_id;
    }

    const profileRes = await fetch(
      `${supabaseUrl}/rest/v1/profiles`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
          Prefer: 'resolution=merge-duplicates',
        },
        body: JSON.stringify(profileData),
      },
    );

    if (!profileRes.ok) {
      const err = await profileRes.text();
      console.error('Profile upsert error:', err);
      // User was created but profile failed — not critical, log it
    }

    // --- Also insert into company_members junction table ---
    if (company_id) {
      const memberRes = await fetch(
        `${supabaseUrl}/rest/v1/company_members`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            apikey: serviceKey,
            Authorization: `Bearer ${serviceKey}`,
            Prefer: 'resolution=merge-duplicates',
          },
          body: JSON.stringify({
            user_id: userId,
            company_id,
            role: userRole,
          }),
        },
      );

      if (!memberRes.ok) {
        const err = await memberRes.text();
        console.error('company_members insert error:', err);
      }
    }

    console.log(
      `✅ User created: ${email} (${userId}) role=${userRole} company=${company_id ?? 'none'}`,
    );

    return new Response(
      JSON.stringify({
        ok: true,
        user_id: userId,
        temp_password: tempPassword,
      }),
      {
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      },
    );
  } catch (err) {
    console.error('create-user error:', err);
    return new Response(
      JSON.stringify({ error: String(err) }),
      {
        status: 500,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      },
    );
  }
});
