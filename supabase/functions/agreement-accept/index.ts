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
    // gig_id navngis eksplisitt: chosen_gig_id peker også på gigs, og uten
    // navnet blir embedden tvetydig (PGRST201) og oppslaget feiler.
    .select('*, gigs!agreement_tokens_gig_id_fkey(venue_name, date_from, date_to, customer_name, customer_email)')
    .eq('token', token)
    .maybeSingle();

  if (error || !agreement) {
    return json({ error: 'Avtalen ble ikke funnet.' }, 404);
  }

  const gig = agreement.gigs;

  // Datoene kunden skal velge mellom, hvis avtalen gjelder en forespørsel med
  // flere mulige datoer. Utgåtte alternativer tas ikke med — de er allerede
  // ute av bildet.
  async function dateOptions() {
    if (!agreement.date_choice_group) return [];
    const { data } = await supabase
      .from('gigs')
      .select('id, date_from, venue_name, city, date_option_state')
      .eq('date_option_group', agreement.date_choice_group)
      .neq('date_option_state', 'expired')
      .order('date_from');
    return (data ?? []).map((g: any) => ({
      id: g.id,
      date_from: g.date_from,
      venue_name: g.venue_name ?? '',
      city: g.city ?? '',
    }));
  }

  // ── GET: Return agreement data ──
  if (req.method === 'GET') {
    const pdfUrl = agreement.pdf_path
      ? `${SUPABASE_URL}/storage/v1/object/public/agreements/${agreement.pdf_path}`
      : null;

    return json({
      ok: true,
      status: agreement.status,
      date_options: await dateOptions(),
      chosen_gig_id: agreement.chosen_gig_id ?? null,
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

    let body: { name?: string; chosen_gig_id?: string } = {};
    try {
      body = await req.json();
    } catch {
      return json({ error: 'Ugyldig forespørsel.' }, 400);
    }

    const acceptedName = body.name?.trim();
    if (!acceptedName) {
      return json({ error: 'Navn er påkrevd.' }, 400);
    }

    // ── Datovalg ────────────────────────────────────────────────────────────
    // Gjelder avtalen flere mulige datoer, må kunden velge én. Valget settes
    // FØR aksepten registreres: feiler datoen, står avtalen fortsatt åpen og
    // kunden kan prøve igjen, i stedet for at vi sitter med en godtatt avtale
    // uten dato.
    let chosenGigId: string | null = null;
    if (agreement.date_choice_group) {
      const options = await dateOptions();
      chosenGigId = (body.chosen_gig_id ?? '').trim() || null;

      if (!chosenGigId) {
        return json({ error: 'Velg én av datoene.' }, 400);
      }
      if (!options.some((o: any) => o.id === chosenGigId)) {
        return json({ error: 'Ukjent dato valgt.' }, 400);
      }

      const { error: chooseError } = await supabase
        .from('gigs')
        .update({ date_option_state: 'chosen' })
        .eq('id', chosenGigId);
      if (chooseError) {
        console.error('Choose date error:', chooseError);
        return json({ error: 'Kunne ikke sette datoen.' }, 500);
      }

      const { error: expireError } = await supabase
        .from('gigs')
        .update({ date_option_state: 'expired' })
        .eq('date_option_group', agreement.date_choice_group)
        .neq('id', chosenGigId);
      if (expireError) {
        // Datoen er satt; resten står igjen som uavklart og er synlig i
        // webappen. Verdt en logg, ikke verdt å avvise kunden.
        console.error('Expire siblings error:', expireError);
      }
    }

    // Update agreement status
    const { error: updateError } = await supabase
      .from('agreement_tokens')
      .update({
        status: 'accepted',
        accepted_at: new Date().toISOString(),
        accepted_name: acceptedName,
        ...(chosenGigId ? { chosen_gig_id: chosenGigId } : {}),
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
        let chosenDate = '';
        if (chosenGigId) {
          const { data: chosen } = await supabase
            .from('gigs')
            .select('date_from')
            .eq('id', chosenGigId)
            .maybeSingle();
          if (chosen?.date_from) chosenDate = ` — datoen er satt til ${chosen.date_from}`;
        }

        const notifications = members.map((m: any) => ({
          user_id: m.user_id,
          title: 'Intensjonsavtale godtatt',
          body: `${acceptedName} har godtatt intensjonsavtalen for ${gigFull.venue_name || 'oppdrag'}${chosenDate}`,
          type: 'gig',
          gig_id: chosenGigId ?? agreement.gig_id,
        }));

        await supabase.from('notifications').insert(notifications);
      }
    }

    return json({ ok: true });
  }

  return json({ error: 'Method not allowed' }, 405);
});
