// bank-connect-company/index.ts
// Starts PSD2 consent flow via Enable Banking for a company bank account.
// Returns the BankID redirect URL.
//
// POST { company_id, institution_id }  (institution_id e.g. "DNB_NO_DNBANOKK")

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const API_BASE = 'https://api.enablebanking.com';

function base64url(data: Uint8Array): string {
  return btoa(String.fromCharCode(...data))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function base64urlEncode(str: string): string {
  return base64url(new TextEncoder().encode(str));
}

async function getAccessToken(): Promise<string> {
  const applicationId = Deno.env.get('ENABLEBANKING_APP_ID')!;
  const privateKeyPem = Deno.env.get('ENABLEBANKING_PRIVATE_KEY')!;

  const pemContent = privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/[\s\n\r]/g, '');
  const binaryKey = Uint8Array.from(atob(pemContent), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8', binaryKey,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false, ['sign'],
  );

  const now = Math.floor(Date.now() / 1000);
  const header = base64urlEncode(JSON.stringify({ alg: 'RS256', typ: 'JWT', kid: applicationId }));
  const payload = base64urlEncode(JSON.stringify({
    iss: 'enablebanking.com',
    aud: 'api.enablebanking.com',
    iat: now, exp: now + 600,
    sub: applicationId,
  }));

  const data = new TextEncoder().encode(`${header}.${payload}`);
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, data);

  return `${header}.${payload}.${base64url(new Uint8Array(signature))}`;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  try {
    const { company_id, institution_id } = await req.json();
    if (!company_id) throw new Error('company_id required');

    const token = await getAccessToken();
    const callbackUrl =
      `${Deno.env.get('SUPABASE_URL')}/functions/v1/bank-callback-company`;

    // State encodes the company_id so the callback knows which company
    const state = `${company_id}__${crypto.randomUUID()}`;

    const res = await fetch(`${API_BASE}/auth`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        access: {
          valid_until: new Date(Date.now() + 90 * 24 * 60 * 60 * 1000).toISOString(),
        },
        aspsp: {
          name: institution_id || 'DNB',
          country: 'NO',
        },
        state,
        redirect_url: callbackUrl,
        psu_type: 'business',
      }),
    });

    const raw = await res.text();
    if (!res.ok) {
      return new Response(
        JSON.stringify({ error: `Enable Banking error (${res.status})`, detail: raw }),
        { status: res.status, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      );
    }

    const auth = JSON.parse(raw);

    return new Response(
      JSON.stringify({ link: auth.url }),
      { headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    );
  }
});
