// tripletex-proxy/index.ts
// Supabase Edge Function — Proxy for Tripletex API.
//
// Handles session token creation/caching and forwards requests
// to the Tripletex API with Basic Auth.
//
// Input body: { company_id, method, path, body? }
// Always returns HTTP 200 with { ok, data?, error?, details? }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Production API base
const API_BASE = 'https://tripletex.no/v2';

// In-memory session token cache: companyId -> { token, expiresAt }
const sessionCache = new Map<string, { token: string; expiresAt: number }>();

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  try {
    const sb = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Verify caller is authenticated
    const authHeader = req.headers.get('authorization') ?? '';
    const token = authHeader.replace('Bearer ', '');
    const { data: { user }, error: authErr } = await sb.auth.getUser(token);
    if (authErr || !user) {
      return ok({ error: 'Ikke innlogget', details: authErr?.message });
    }

    const body = await req.json();
    const { company_id, method, path, body: reqBody } = body;

    if (!company_id || !method || !path) {
      return ok({ error: 'Mangler company_id, method eller path' });
    }

    // Verify user is admin/management of this company
    const { data: membership } = await sb
      .from('company_members')
      .select('role')
      .eq('company_id', company_id)
      .eq('user_id', user.id)
      .maybeSingle();

    if (!membership || !['admin', 'management'].includes(membership.role)) {
      return ok({ error: 'Krever admin-tilgang' });
    }

    // Get Tripletex tokens from company
    const { data: company } = await sb
      .from('companies')
      .select('tripletex_consumer_token, tripletex_employee_token')
      .eq('id', company_id)
      .single();

    if (!company?.tripletex_consumer_token || !company?.tripletex_employee_token) {
      return ok({ error: 'Tripletex-tokens er ikke konfigurert' });
    }

    const consumerToken = company.tripletex_consumer_token as string;
    const employeeToken = company.tripletex_employee_token as string;

    // Forward request to Tripletex (with automatic retry on 401)
    const url = `${API_BASE}${path}`;
    console.log(`Tripletex → ${method.toUpperCase()} ${url}`);

    let tripletexRes: Response | null = null;

    for (let attempt = 0; attempt < 2; attempt++) {
      let sessionToken: string;
      try {
        sessionToken = await getSessionToken(company_id, consumerToken, employeeToken);
      } catch (err) {
        return ok({
          error: 'Kunne ikke opprette Tripletex-sesjon',
          details: String(err),
        });
      }

      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Authorization': `Basic ${btoa(`0:${sessionToken}`)}`,
      };

      const fetchOptions: RequestInit = {
        method: method.toUpperCase(),
        headers,
      };

      if (reqBody && !['GET', 'DELETE'].includes(method.toUpperCase())) {
        fetchOptions.body = JSON.stringify(reqBody);
      }

      tripletexRes = await fetch(url, fetchOptions);

      if (tripletexRes.status === 401 && attempt === 0) {
        console.log('Got 401 — clearing cached session and retrying with new token...');
        sessionCache.delete(company_id);
        // Consume the body before retrying
        await tripletexRes.text();
        continue;
      }

      break;
    }

    if (!tripletexRes!.ok) {
      const errText = await tripletexRes!.text();
      console.error(`Tripletex ${tripletexRes!.status}:`, errText.slice(0, 500));

      if (tripletexRes!.status === 401) {
        sessionCache.delete(company_id);
      }

      let errData: unknown;
      try { errData = JSON.parse(errText); } catch { errData = errText; }

      return ok({
        error: `Tripletex svarte med ${tripletexRes!.status}`,
        tripletexStatus: tripletexRes!.status,
        details: errData,
      });
    }

    // Check if response is binary (PDF, image, etc.)
    const contentType = tripletexRes!.headers.get('content-type') ?? '';
    if (!contentType.includes('json')) {
      const bytes = new Uint8Array(await tripletexRes!.arrayBuffer());
      // Convert to base64
      let binary = '';
      for (let i = 0; i < bytes.length; i++) {
        binary += String.fromCharCode(bytes[i]);
      }
      const base64 = btoa(binary);
      const fileName = tripletexRes.headers.get('content-disposition')
        ?.match(/filename="?([^";\s]+)"?/)?.[1] ?? 'document';

      return ok({
        ok: true,
        data: { _binary: true, base64, mimeType: contentType, fileName },
      });
    }

    // JSON response
    const resText = await tripletexRes!.text();
    let resData: unknown;
    try { resData = JSON.parse(resText); } catch { resData = resText; }

    return ok({ ok: true, data: resData });

  } catch (err) {
    console.error('tripletex-proxy error:', err);
    return ok({ error: String(err) });
  }
});


// ── Helpers ────────────────────────────────────────────────

/** Always return HTTP 200 so Flutter can read the body. */
function ok(data: Record<string, unknown>) {
  return new Response(JSON.stringify(data), {
    status: 200,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

/**
 * Get a valid Tripletex session token, creating one if needed.
 * Session tokens are cached in memory and expire at midnight.
 */
async function getSessionToken(
  companyId: string,
  consumerToken: string,
  employeeToken: string,
): Promise<string> {
  const cached = sessionCache.get(companyId);
  if (cached && cached.expiresAt > Date.now()) {
    return cached.token;
  }

  // Create new session token
  const expDate = getTomorrowDate();
  const url = `${API_BASE}/token/session/:create?consumerToken=${encodeURIComponent(consumerToken)}&employeeToken=${encodeURIComponent(employeeToken)}&expirationDate=${expDate}`;

  console.log(`Creating Tripletex session (exp=${expDate}, consumer=${consumerToken.slice(0,8)}..., employee=${employeeToken.slice(0,8)}...)...`);
  const res = await fetch(url, { method: 'PUT' });
  const resText = await res.text();
  console.log(`Session creation response: ${res.status} ${resText.slice(0, 300)}`);

  if (!res.ok) {
    console.error('Session creation failed:', res.status, resText.slice(0, 300));
    throw new Error(`Sesjon feilet (${res.status}): ${resText.slice(0, 200)}`);
  }

  let data: { value?: { token?: string } };
  try {
    data = JSON.parse(resText);
  } catch {
    throw new Error(`Ugyldig JSON fra Tripletex: ${resText.slice(0, 100)}`);
  }

  const sessionToken = data.value?.token;
  if (!sessionToken) {
    throw new Error(`Ingen token i respons: ${JSON.stringify(data).slice(0, 200)}`);
  }

  console.log('Session token created OK');

  // Cache until midnight (conservative: expire 1 hour before)
  const now = new Date();
  const midnight = new Date(now);
  midnight.setDate(midnight.getDate() + 1);
  midnight.setHours(0, 0, 0, 0);
  const expiresAt = midnight.getTime() - 3600_000;

  sessionCache.set(companyId, { token: sessionToken, expiresAt });
  return sessionToken;
}

/** Returns tomorrow's date as YYYY-MM-DD for session expiration. */
function getTomorrowDate(): string {
  const d = new Date();
  d.setDate(d.getDate() + 1);
  return d.toISOString().slice(0, 10);
}
