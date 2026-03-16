// website-booking/index.ts
// Receives a booking request from the CSS website and creates:
//   1. Company (find or create, with owner_company_id = CSS)
//   2. Contact (find or create for that company)
//   3. Production (find or create for that company)
//   4. Management tour (for production name display + offer prefill)
//   5. Gig records for each date/city in the route
//   6. bus_request with tour_id
//   7. bus_request_gigs junction records
//
// Payload:
// {
//   contact_name, contact_email, contact_phone?,
//   company_name, production_name,
//   pax?, bus_count?, trailer?,
//   notes?,
//   rounds: [{ start_city, end_city, date_from, date_to, date_cities: [{date, city}] }]
// }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const CSS_COMPANY_NAME = 'Coach Service Scandinavia';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  try {
    const sb = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const body = await req.json();
    const {
      contact_name,
      contact_email,
      contact_phone,
      company_name,
      production_name,
      pax,
      bus_count,
      trailer,
      notes,
      rounds,
    } = body;

    // Validate required fields
    if (!contact_name || !contact_email || !company_name || !production_name) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: contact_name, contact_email, company_name, production_name' }),
        { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      );
    }
    if (!rounds || !rounds.length) {
      return new Response(
        JSON.stringify({ error: 'At least one round is required' }),
        { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      );
    }

    // 1. Resolve CSS company_id
    const { data: cssCompany } = await sb
      .from('companies')
      .select('id')
      .eq('name', CSS_COMPANY_NAME)
      .single();

    if (!cssCompany) {
      return new Response(
        JSON.stringify({ error: 'CSS company not found' }),
        { status: 500, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      );
    }
    const cssCompanyId = cssCompany.id;

    // 2. Find or create CLIENT company
    let clientCompanyId: string;
    const { data: existingCompany } = await sb
      .from('companies')
      .select('id')
      .eq('name', company_name)
      .eq('owner_company_id', cssCompanyId)
      .maybeSingle();

    if (existingCompany) {
      clientCompanyId = existingCompany.id;
    } else {
      const { data: newCompany, error: companyErr } = await sb
        .from('companies')
        .insert({
          name: company_name,
          owner_company_id: cssCompanyId,
        })
        .select('id')
        .single();
      if (companyErr) throw companyErr;
      clientCompanyId = newCompany.id;
    }

    // 3. Find or create contact
    const { data: existingContact } = await sb
      .from('contacts')
      .select('id')
      .eq('company_id', clientCompanyId)
      .eq('email', contact_email)
      .maybeSingle();

    if (!existingContact) {
      const { error: contactErr } = await sb
        .from('contacts')
        .insert({
          company_id: clientCompanyId,
          name: contact_name,
          email: contact_email,
          phone: contact_phone || null,
        });
      if (contactErr) throw contactErr;
    }

    // 4. Find or create production
    const { data: existingProd } = await sb
      .from('productions')
      .select('id')
      .eq('company_id', clientCompanyId)
      .eq('name', production_name)
      .maybeSingle();

    if (!existingProd) {
      const { error: prodErr } = await sb
        .from('productions')
        .insert({
          company_id: clientCompanyId,
          name: production_name,
        });
      if (prodErr) throw prodErr;
    }

    // 5. Create management_tour (shared across all rounds)
    const firstRound = rounds[0];
    const lastRound = rounds[rounds.length - 1];

    const { data: tourData, error: tourErr } = await sb
      .from('management_tours')
      .insert({
        company_id: clientCompanyId,
        name: production_name,
        artist: production_name,
        status: 'planning',
        tour_start: firstRound.date_from,
        tour_end: lastRound.date_to,
        notes: `Website request from ${contact_name} (${contact_email})`,
      })
      .select('id')
      .single();
    if (tourErr) throw tourErr;
    const tourId = tourData.id;

    // 6. Build notes
    const notesLines: string[] = [
      `[Website Request]`,
      `Contact: ${contact_name}`,
      `Email: ${contact_email}`,
    ];
    if (contact_phone) notesLines.push(`Phone: ${contact_phone}`);
    notesLines.push(`Company: ${company_name}`);
    notesLines.push(`Production: ${production_name}`);
    if (notes) {
      notesLines.push('');
      notesLines.push(`Additional: ${notes}`);
    }

    // 7. Create gig records for ALL rounds
    const allGigs: { id: string; sortOrder: number; roundIndex: number; roundStartCity: string; roundEndCity: string }[] = [];
    let globalSort = 0;

    for (let ri = 0; ri < rounds.length; ri++) {
      const round = rounds[ri];
      const dateCities = round.date_cities || [];

      for (const dc of dateCities) {
        if (!dc.date) continue;
        const { data: gig, error: gigErr } = await sb
          .from('gigs')
          .insert({
            company_id: clientCompanyId,
            date_from: dc.date,
            city: dc.city || round.start_city,
            customer_firma: company_name,
            customer_name: contact_name,
            customer_email: contact_email,
            customer_phone: contact_phone || null,
            status: 'inquiry',
          })
          .select('id')
          .single();
        if (gigErr) throw gigErr;
        allGigs.push({
          id: gig.id,
          sortOrder: globalSort++,
          roundIndex: ri,
          roundStartCity: round.start_city,
          roundEndCity: round.end_city,
        });
      }
    }

    // 8. Create ONE bus_request (overall dates from first to last round)
    const { data: busRequest, error: brErr } = await sb
      .from('bus_requests')
      .insert({
        company_id: clientCompanyId,
        tour_id: tourId,
        from_city: firstRound.start_city,
        to_city: lastRound.end_city,
        date_from: firstRound.date_from,
        date_to: lastRound.date_to,
        pax: pax || null,
        bus_count: bus_count || 1,
        trailer: trailer || false,
        notes: notesLines.join('\n'),
        status: 'pending',
      })
      .select('id')
      .single();

    if (brErr) throw brErr;

    // 9. Create bus_request_gigs junction records with round_index + start/end city
    if (allGigs.length > 0) {
      const junctionRows = allGigs.map(g => ({
        bus_request_id: busRequest.id,
        gig_id: g.id,
        sort_order: g.sortOrder,
        round_index: g.roundIndex,
        round_start_city: g.roundStartCity,
        round_end_city: g.roundEndCity,
      }));

      const { error: junctionErr } = await sb
        .from('bus_request_gigs')
        .insert(junctionRows);
      if (junctionErr) throw junctionErr;
    }

    return new Response(
      JSON.stringify({ success: true, bus_request_id: busRequest.id }),
      { status: 200, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('website-booking error:', err);
    return new Response(
      JSON.stringify({ error: err.message || 'Internal server error' }),
      { status: 500, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    );
  }
});
