// agreement-accept/index.ts
// API for agreement acceptance flow.
// GET  ?token=xxx  → returns agreement data (PDF url, status, venue, etc.)
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
    return json({ error: 'Mangler token.' }, 400);
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // Look up agreement token
  const { data: agreement, error } = await supabase
    .from('agreement_tokens')
    .select('*, gigs(venue_name, date_from, date_to, customer_name, customer_email)')
    .eq('token', token)
    .maybeSingle();

  if (error || !agreement) {
    return json({ error: 'Avtalen ble ikke funnet.' }, 404);
  }

  const gig = agreement.gigs;

  // ── GET: Return agreement data ──
  if (req.method === 'GET') {
    const pdfUrl = agreement.pdf_path
      ? `${SUPABASE_URL}/storage/v1/object/public/agreements/${agreement.pdf_path}`
      : null;

    return json({
      ok: true,
      status: agreement.status,
      venue: gig?.venue_name ?? '',
      date_from: gig?.date_from ?? '',
      date_to: gig?.date_to ?? '',
      customer_name: gig?.customer_name ?? '',
      pdf_url: pdfUrl,
      accepted_name: agreement.accepted_name ?? '',
      accepted_at: agreement.accepted_at ?? '',
    });
  }

  // ── POST: Accept the agreement ──
  if (req.method === 'POST') {
    if (agreement.status !== 'pending') {
      return json({ error: 'Avtalen er allerede godtatt.' }, 400);
    }

    let body: { name?: string } = {};
    try {
      body = await req.json();
    } catch {
      return json({ error: 'Ugyldig forespørsel.' }, 400);
    }

    const acceptedName = body.name?.trim();
    if (!acceptedName) {
      return json({ error: 'Navn er påkrevd.' }, 400);
    }

    // Update agreement status
    const { error: updateError } = await supabase
      .from('agreement_tokens')
      .update({
        status: 'accepted',
        accepted_at: new Date().toISOString(),
        accepted_name: acceptedName,
      })
      .eq('token', token);

    if (updateError) {
      console.error('Accept update error:', updateError);
      return json({ error: 'Kunne ikke registrere aksepten.' }, 500);
    }

    // Send notification to all company members
    const { data: gigFull } = await supabase
      .from('gigs')
      .select('company_id, venue_name')
      .eq('id', agreement.gig_id)
      .single();

    if (gigFull?.company_id) {
      const { data: members } = await supabase
        .from('company_members')
        .select('user_id')
        .eq('company_id', gigFull.company_id);

      if (members && members.length > 0) {
        const notifications = members.map((m: any) => ({
          user_id: m.user_id,
          title: 'Intensjonsavtale godtatt',
          body: `${acceptedName} har godtatt intensjonsavtalen for ${gigFull.venue_name || 'oppdrag'}`,
          type: 'gig',
          gig_id: agreement.gig_id,
        }));

        await supabase.from('notifications').insert(notifications);
      }
    }

    return json({ ok: true });
  }

  return json({ error: 'Method not allowed' }, 405);
});
