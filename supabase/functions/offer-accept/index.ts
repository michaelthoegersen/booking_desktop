// offer-accept/index.ts
// API for offer acceptance flow (CSS tilbud).
// GET  ?token=xxx  → returns offer data (PDF url, status, customer info)
// POST ?token=xxx  → records customer acceptance (name + date)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

const SUPABASE_URL = 'https://fqefvgqlrntwgschkugf.supabase.co';

function json(data: any, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json; charset=utf-8' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  const url = new URL(req.url);
  const token = url.searchParams.get('token');

  if (!token) {
    return json({ error: 'Missing token.' }, 400);
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // Look up offer token
  const { data: offerToken, error } = await supabase
    .from('offer_tokens')
    .select('*, offers(id, company, contact, owner_company_id, payload)')
    .eq('token', token)
    .maybeSingle();

  if (error || !offerToken) {
    console.error('Lookup error:', error);
    return json({ error: 'Offer not found.' }, 404);
  }

  const offer = offerToken.offers;

  // ── GET: Return offer data ──
  if (req.method === 'GET') {
    const pdfUrl = offerToken.pdf_path
      ? `${SUPABASE_URL}/storage/v1/object/public/offers-pdf/${offerToken.pdf_path}`
      : null;

    // Get company name for the landing page header
    let companyName = '';
    if (offer?.owner_company_id) {
      const { data: company } = await supabase
        .from('companies')
        .select('name')
        .eq('id', offer.owner_company_id)
        .maybeSingle();
      companyName = company?.name ?? '';
    }

    return json({
      ok: true,
      status: offerToken.status,
      customer_name: offer?.contact ?? '',
      customer_company: offer?.company ?? '',
      company_name: companyName,
      pdf_url: pdfUrl,
      accepted_name: offerToken.accepted_name ?? '',
      accepted_at: offerToken.accepted_at ?? '',
    });
  }

  // ── POST: Accept the offer ──
  if (req.method === 'POST') {
    if (offerToken.status !== 'pending') {
      return json({ error: 'This offer has already been accepted.' }, 400);
    }

    let body: { name?: string } = {};
    try {
      body = await req.json();
    } catch {
      return json({ error: 'Invalid request.' }, 400);
    }

    const acceptedName = body.name?.trim();
    if (!acceptedName) {
      return json({ error: 'Name is required.' }, 400);
    }

    // Update offer token status
    const { error: updateError } = await supabase
      .from('offer_tokens')
      .update({
        status: 'accepted',
        accepted_at: new Date().toISOString(),
        accepted_name: acceptedName,
      })
      .eq('token', token);

    if (updateError) {
      console.error('Accept update error:', updateError);
      return json({ error: 'Could not register acceptance.' }, 500);
    }

    // Send notification to all company members
    if (offer?.owner_company_id) {
      const { data: members } = await supabase
        .from('company_members')
        .select('user_id')
        .eq('company_id', offer.owner_company_id);

      if (members && members.length > 0) {
        const firma = offer.company || 'customer';
        const notifications = members.map((m: any) => ({
          user_id: m.user_id,
          title: 'Offer accepted',
          body: `${acceptedName} (${firma}) has accepted the offer`,
          type: 'offer',
        }));

        await supabase.from('notifications').insert(notifications);
      }
    }

    return json({ ok: true });
  }

  return json({ error: 'Method not allowed' }, 405);
});
