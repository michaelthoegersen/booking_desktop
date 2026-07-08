// bank-callback-company/index.ts
// Handles the BankID redirect after PSD2 consent.
// GET ?code=...&state=companyId__uuid
// Exchanges the code for an Enable Banking session, stores accounts, fetches initial balance.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

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
  if (req.method !== 'GET') {
    return new Response('Method not allowed', { status: 405 });
  }

  try {
    const url = new URL(req.url);
    const code = url.searchParams.get('code');
    const state = url.searchParams.get('state') || '';

    if (!code) {
      return new Response(html('Feil', 'Ingen autorisasjonskode mottatt.'), {
        status: 400,
        headers: { 'Content-Type': 'text/html; charset=utf-8' },
      });
    }

    // Extract company_id from state
    const companyId = state.split('__')[0];
    if (!companyId) {
      return new Response(html('Feil', 'Ugyldig state-parameter.'), {
        status: 400,
        headers: { 'Content-Type': 'text/html; charset=utf-8' },
      });
    }

    const token = await getAccessToken();
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Exchange code for session
    const sessionRes = await fetch(`${API_BASE}/sessions`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ code }),
    });

    const raw = await sessionRes.text();
    if (!sessionRes.ok) {
      return new Response(html('Feil', `Banktilkobling feilet: ${raw}`), {
        status: 500,
        headers: { 'Content-Type': 'text/html; charset=utf-8' },
      });
    }

    const session = JSON.parse(raw);
    const sessionId = session.session_id;
    let accountCount = 0;

    // Store each account
    for (const account of session.accounts || []) {
      const uid = account.uid || account.account_id?.iban || crypto.randomUUID();
      const iban = account.account_id?.iban || null;
      const details = account.details || '';
      const name = details || (iban ? `Konto ${iban.slice(-4)}` : 'DNB Bedriftskonto');

      // Fetch balance for this account
      let balance: number | null = null;
      try {
        const balRes = await fetch(`${API_BASE}/accounts/${uid}/balances`, {
          headers: { Authorization: `Bearer ${token}` },
        });
        if (balRes.ok) {
          const balData = await balRes.json();
          const balances = balData.balances || [];
          // Prefer "expected" or "closingBooked" balance
          const preferred = balances.find((b: any) =>
            b.balance_type === 'expected' || b.balance_type === 'closingBooked'
          ) || balances[0];
          if (preferred?.balance_amount?.amount) {
            balance = parseFloat(preferred.balance_amount.amount);
          }
        }
      } catch (e) {
        console.error('Balance fetch error:', e);
      }

      await supabase
        .from('company_bank_accounts')
        .upsert({
          company_id: companyId,
          session_id: sessionId,
          account_external_id: uid,
          bank_name: session.aspsp?.name || 'DNB',
          account_name: name,
          iban,
          currency: account.currency || 'NOK',
          balance,
          balance_updated_at: balance != null ? new Date().toISOString() : null,
          session_valid_until: session.access?.valid_until || null,
          updated_at: new Date().toISOString(),
        }, {
          onConflict: 'company_id,account_external_id',
        });

      accountCount++;
    }

    return new Response(
      html('Tilkoblet!', `${accountCount} konto(er) fra DNB er nå koblet til. Du kan lukke dette vinduet.`),
      { headers: { 'Content-Type': 'text/html; charset=utf-8' } },
    );
  } catch (err) {
    console.error('bank-callback-company error:', err);
    return new Response(
      html('Feil', `Noe gikk galt: ${String(err)}`),
      { status: 500, headers: { 'Content-Type': 'text/html; charset=utf-8' } },
    );
  }
});

function html(title: string, message: string): string {
  return `<!DOCTYPE html>
<html lang="no">
<head><meta charset="utf-8"><title>${title}</title>
<style>
  body { font-family: -apple-system, system-ui, sans-serif; display: flex;
         justify-content: center; align-items: center; min-height: 100vh;
         margin: 0; background: #111; color: #fff; }
  .card { text-align: center; padding: 40px; background: #222;
          border-radius: 16px; max-width: 400px; }
  h1 { margin: 0 0 12px; }
  p { color: #aaa; line-height: 1.5; }
</style>
</head>
<body><div class="card"><h1>${title}</h1><p>${message}</p></div></body>
</html>`;
}
