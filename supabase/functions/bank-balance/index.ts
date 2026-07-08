// bank-balance/index.ts
// Fetches current bank balance from Enable Banking for a company account.
// POST { company_id }
// Returns { balance, currency, updated_at, account_name }

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
    const { company_id } = await req.json();
    if (!company_id) throw new Error('company_id required');

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Get stored bank account
    const { data: accounts, error } = await supabase
      .from('company_bank_accounts')
      .select('*')
      .eq('company_id', company_id)
      .order('created_at')
      .limit(5);

    if (error) throw error;
    if (!accounts || accounts.length === 0) {
      return new Response(
        JSON.stringify({ error: 'no_account', message: 'Ingen bankkonto tilkoblet' }),
        { status: 404, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      );
    }

    const token = await getAccessToken();
    const results = [];

    for (const account of accounts) {
      const uid = account.account_external_id;
      let balance = account.balance;
      let updatedAt = account.balance_updated_at;

      try {
        const balRes = await fetch(`${API_BASE}/accounts/${uid}/balances`, {
          headers: { Authorization: `Bearer ${token}` },
        });

        if (balRes.ok) {
          const balData = await balRes.json();
          const balances = balData.balances || [];
          const preferred = balances.find((b: any) =>
            b.balance_type === 'expected' || b.balance_type === 'closingBooked'
          ) || balances[0];

          if (preferred?.balance_amount?.amount) {
            balance = parseFloat(preferred.balance_amount.amount);
            updatedAt = new Date().toISOString();

            // Cache in DB
            await supabase
              .from('company_bank_accounts')
              .update({ balance, balance_updated_at: updatedAt })
              .eq('id', account.id);
          }
        }
      } catch (e) {
        console.error(`Balance fetch error for ${uid}:`, e);
        // Fall back to cached balance
      }

      results.push({
        id: account.id,
        account_name: account.account_name,
        bank_name: account.bank_name,
        iban: account.iban,
        balance,
        currency: account.currency,
        updated_at: updatedAt,
      });
    }

    return new Response(
      JSON.stringify({ accounts: results }),
      { headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('bank-balance error:', err);
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    );
  }
});
