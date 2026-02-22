// send-graph-email/index.ts
// Supabase Edge Function — sends email via Microsoft Graph API
//
// Required secrets (set via Supabase CLI):
//   GRAPH_CLIENT_SECRET  — Azure AD application client secret
//
// Tenant ID, Client ID and sender are hardcoded below (not sensitive).

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const TENANT_ID   = 'abb1c1c4-8653-4a56-91d6-039b8ccbea2d';
const CLIENT_ID   = 'c9a7931d-973f-4278-90d6-f825250d4b49';
const SENDER      = 'michael@nttas.com';

async function getAccessToken(clientSecret: string): Promise<string> {
  const res = await fetch(
    `https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'client_credentials',
        client_id: CLIENT_ID,
        client_secret: clientSecret,
        scope: 'https://graph.microsoft.com/.default',
      }),
    },
  );

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Token error ${res.status}: ${text}`);
  }

  const json = await res.json();
  return json.access_token as string;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405, headers: CORS_HEADERS });
  }

  try {
    const { to, subject, body } = await req.json() as {
      to: string;
      subject: string;
      body: string;
    };

    if (!to || !subject || !body) {
      return new Response(
        JSON.stringify({ error: 'to, subject and body are required' }),
        { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      );
    }

    const clientSecret = Deno.env.get('GRAPH_CLIENT_SECRET');
    if (!clientSecret) {
      throw new Error('GRAPH_CLIENT_SECRET secret is not set');
    }

    const token = await getAccessToken(clientSecret);

    const sendRes = await fetch(
      `https://graph.microsoft.com/v1.0/users/${SENDER}/sendMail`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            subject,
            body: { contentType: 'Text', content: body },
            toRecipients: [{ emailAddress: { address: to } }],
          },
        }),
      },
    );

    if (sendRes.status !== 202) {
      const text = await sendRes.text();
      throw new Error(`Graph API error ${sendRes.status}: ${text}`);
    }

    return new Response(
      JSON.stringify({ ok: true }),
      { headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('send-graph-email error:', err);
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    );
  }
});
