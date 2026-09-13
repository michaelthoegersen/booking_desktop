// request-password-reset/index.ts
// A member who cannot log in asks for a new password from the login screen.
// Creates a request row and notifies the company's admins.
//
// Body: { email }
//
// Always answers { ok: true }, whether or not the address exists. Telling an
// anonymous caller which addresses are registered would turn this into a way
// to enumerate members.

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

const ok = () =>
  new Response(JSON.stringify({ ok: true }), {
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    const { email } = await req.json();
    const clean = (email ?? '').toString().trim();
    if (!clean) return ok();

    const headers = {
      'Content-Type': 'application/json',
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
    };

    // Look up the member. ilike so a capitalised address still matches.
    const profileRes = await fetch(
      `${supabaseUrl}/rest/v1/profiles?select=id,name,email,company_id&email=ilike.${encodeURIComponent(clean)}&limit=1`,
      { headers },
    );
    const profiles = profileRes.ok ? await profileRes.json() : [];
    if (!Array.isArray(profiles) || profiles.length === 0) {
      console.log('No profile for reset request:', clean);
      return ok();
    }
    const profile = profiles[0];

    // Don't stack duplicates — one open request per member is enough.
    const existingRes = await fetch(
      `${supabaseUrl}/rest/v1/password_reset_requests?select=id&user_id=eq.${profile.id}&status=eq.pending&limit=1`,
      { headers },
    );
    const existing = existingRes.ok ? await existingRes.json() : [];
    if (Array.isArray(existing) && existing.length > 0) {
      console.log('Reset request already pending for', clean);
      return ok();
    }

    const insertRes = await fetch(
      `${supabaseUrl}/rest/v1/password_reset_requests`,
      {
        method: 'POST',
        headers,
        body: JSON.stringify({
          email: profile.email ?? clean,
          user_id: profile.id,
          company_id: profile.company_id,
          status: 'pending',
        }),
      },
    );
    if (!insertRes.ok) {
      console.error('Insert reset request failed:', await insertRes.text());
      return ok();
    }

    // Tell the admins. Reuses notify-company, which handles both push and the
    // in-app notification.
    if (profile.company_id) {
      try {
        const adminsRes = await fetch(
          `${supabaseUrl}/rest/v1/company_members?select=user_id&company_id=eq.${profile.company_id}&role=in.(admin,management)`,
          { headers },
        );
        const admins = adminsRes.ok ? await adminsRes.json() : [];
        const ids = (admins ?? []).map((a: { user_id: string }) => a.user_id);
        if (ids.length > 0) {
          await fetch(`${supabaseUrl}/functions/v1/notify-company`, {
            method: 'POST',
            headers,
            body: JSON.stringify({
              company_id: profile.company_id,
              title: 'Ber om nytt passord',
              body: `${profile.name ?? profile.email ?? clean} kommer ikke inn`,
              user_ids: ids,
              type: 'general',
            }),
          });
        }
      } catch (e) {
        console.error('Notify admins failed:', e);
      }
    }

    return ok();
  } catch (err) {
    console.error('request-password-reset error:', err);
    // Still ok() — the caller must not learn anything from a failure either.
    return ok();
  }
});
