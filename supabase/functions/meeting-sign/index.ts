// meeting-sign/index.ts
// API for meeting minutes signing flow.
// GET  ?token=xxx  → returns signing data (meeting title, status, signer name)
// POST ?token=xxx  → records signature

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

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

  // Look up signature request
  const { data: sig, error: sigErr } = await supabase
    .from('meeting_signatures')
    .select('*, meetings(title, date, start_time, end_time)')
    .eq('token', token)
    .maybeSingle();

  if (sigErr || !sig) {
    return json({ error: 'Ugyldig eller utløpt lenke.' }, 404);
  }

  // Get signer name
  const { data: profile } = await supabase
    .from('profiles')
    .select('name')
    .eq('id', sig.user_id)
    .maybeSingle();

  const meeting = sig.meetings;

  if (req.method === 'POST') {
    if (sig.status === 'signed') {
      return json({ status: 'already_signed', signed_at: sig.signed_at });
    }

    let signedName = profile?.name ?? 'Ukjent';
    try {
      const body = await req.json();
      if (body.signed_name) signedName = body.signed_name;
    } catch (_) {}

    const now = new Date().toISOString();
    await supabase
      .from('meeting_signatures')
      .update({ status: 'signed', signed_at: now, signed_name: signedName })
      .eq('token', token);

    return json({ status: 'signed', signed_at: now, signed_name: signedName });
  }

  // Get PDF URL from meeting
  const { data: meetingFull } = await supabase
    .from('meetings')
    .select('minutes_pdf_url')
    .eq('id', sig.meeting_id)
    .maybeSingle();

  // GET → return data for the signing page
  return json({
    status: sig.status,
    signed_at: sig.signed_at,
    signer_name: profile?.name ?? 'Ukjent',
    meeting_title: meeting?.title ?? 'Møte',
    meeting_date: meeting?.date ?? '',
    meeting_time_start: meeting?.start_time ?? '',
    meeting_time_end: meeting?.end_time ?? '',
    pdf_url: meetingFull?.minutes_pdf_url ?? null,
  });
});
