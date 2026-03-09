// gig-calendar/index.ts
// Supabase Edge Function — serves an iCalendar (.ics) feed for a company's gigs.
// Calendar apps poll this URL automatically for live updates.
//
// GET ?company_id=X&token=Y

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Escape special iCalendar text characters
function icsEscape(text: string): string {
  return text
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\n/g, '\\n');
}

// Format a date string (yyyy-MM-dd) + optional time (HH:mm) to iCal VALUE=DATE or DATE-TIME
function icsDate(dateStr: string, time?: string | null): string {
  // dateStr = "2026-03-15"
  const d = dateStr.replace(/-/g, '');
  if (time) {
    // time = "19:00" or "19:30"
    const t = time.replace(/:/g, '').padEnd(4, '0');
    return `${d}T${t}00`;
  }
  return d;
}

// Fold long lines per RFC 5545 (max 75 octets per line)
function foldLine(line: string): string {
  const bytes = new TextEncoder().encode(line);
  if (bytes.length <= 75) return line;

  const parts: string[] = [];
  let start = 0;
  let firstLine = true;
  while (start < bytes.length) {
    const maxLen = firstLine ? 75 : 74; // subsequent lines start with a space
    let end = start + maxLen;
    if (end > bytes.length) end = bytes.length;
    const slice = new TextDecoder().decode(bytes.slice(start, end));
    parts.push(firstLine ? slice : ' ' + slice);
    start = end;
    firstLine = false;
  }
  return parts.join('\r\n');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== 'GET') {
    return new Response('Method not allowed', { status: 405, headers: CORS_HEADERS });
  }

  try {
    const url = new URL(req.url);
    const companyId = url.searchParams.get('company_id');
    const token = url.searchParams.get('token');

    if (!companyId || !token) {
      return new Response('Missing company_id or token', {
        status: 400,
        headers: CORS_HEADERS,
      });
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Verify token matches company
    const { data: company, error: companyErr } = await supabase
      .from('companies')
      .select('id, name, calendar_token')
      .eq('id', companyId)
      .maybeSingle();

    if (companyErr || !company) {
      return new Response('Company not found', { status: 404, headers: CORS_HEADERS });
    }

    if (company.calendar_token !== token) {
      return new Response('Invalid token', { status: 403, headers: CORS_HEADERS });
    }

    // Fetch gigs (exclude cancelled)
    const { data: gigs, error: gigsErr } = await supabase
      .from('gigs')
      .select('*')
      .eq('company_id', companyId)
      .neq('status', 'cancelled')
      .order('date_from', { ascending: true });

    if (gigsErr) {
      console.error('Gigs query error:', gigsErr);
      return new Response('Database error', { status: 500, headers: CORS_HEADERS });
    }

    // Build iCalendar
    const calName = icsEscape(company.name || 'Gigs');
    const lines: string[] = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//TourFlow//Gig Calendar//EN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      `X-WR-CALNAME:${calName}`,
      'X-WR-TIMEZONE:Europe/Oslo',
    ];

    for (const gig of (gigs || [])) {
      const uid = gig.id;
      const dateFrom = gig.date_from as string | null;
      if (!dateFrom) continue;

      const dateTo = (gig.date_to as string | null) || dateFrom;
      const venue = gig.venue_name as string | null || '';
      const city = gig.city as string | null || '';
      const firma = gig.customer_firma as string | null || '';
      const status = gig.status as string | null || '';
      const type = gig.type as string | null || 'gig';
      const performanceTime = gig.performance_time as string | null;
      const meetingTime = gig.meeting_time as string | null;
      const getInTime = gig.get_in_time as string | null;
      const updatedAt = gig.updated_at as string | null;

      // SUMMARY: CompanyPrefix + type + sted
      const prefix = (company.name || '').split(' ')[0] || 'Gig';
      const address = gig.customer_address as string | null || '';
      let summary: string;
      if (type === 'rehearsal') {
        // Øvelse → vis spillested (venue) i tittel
        summary = `${prefix}Øvelse${venue ? ' ' + venue : ''}`;
      } else if (status === 'inquiry' || status === 'Inquiry') {
        summary = `${prefix}Gig?${city ? ' ' + city : ''}`;
      } else {
        summary = `${prefix}Gig${city ? ' ' + city : ''}`;
      }

      // LOCATION: full adresse så kalenderappen kan vise kart
      const location = [venue, address, city].filter(Boolean).join(', ');

      // DESCRIPTION: schedule details
      const descParts: string[] = [];
      if (meetingTime) descParts.push(`Oppmøte: ${meetingTime}`);
      if (getInTime) descParts.push(`Get-in: ${getInTime}`);
      if (performanceTime) descParts.push(`Spilletid: ${performanceTime}`);

      const description = descParts.join('\\n');

      // DTSTART / DTEND — use performance_time if available, otherwise all-day
      const hasTime = !!performanceTime;
      const dtStart = hasTime
        ? `DTSTART:${icsDate(dateFrom, performanceTime)}`
        : `DTSTART;VALUE=DATE:${icsDate(dateFrom)}`;

      let dtEnd: string;
      if (hasTime) {
        // End 2 hours after start as default duration
        const startH = parseInt(performanceTime!.split(':')[0], 10);
        const startM = parseInt(performanceTime!.split(':')[1] || '0', 10);
        const endH = startH + 2;
        const endTime = `${String(endH).padStart(2, '0')}:${String(startM).padStart(2, '0')}`;
        dtEnd = `DTEND:${icsDate(dateTo, endTime)}`;
      } else {
        // All-day event: DTEND is exclusive, so add one day
        const endDate = new Date(dateTo + 'T00:00:00');
        endDate.setDate(endDate.getDate() + 1);
        const y = endDate.getFullYear();
        const m = String(endDate.getMonth() + 1).padStart(2, '0');
        const d = String(endDate.getDate()).padStart(2, '0');
        dtEnd = `DTEND;VALUE=DATE:${y}${m}${d}`;
      }

      // LAST-MODIFIED
      let lastMod = '';
      if (updatedAt) {
        const dt = new Date(updatedAt);
        lastMod = `LAST-MODIFIED:${dt.toISOString().replace(/[-:]/g, '').replace(/\.\d+/, '')}`;
      }

      // DTSTAMP (required)
      const now = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d+/, '');

      lines.push('BEGIN:VEVENT');
      lines.push(`UID:${uid}@tourflow`);
      lines.push(`DTSTAMP:${now}`);
      lines.push(dtStart);
      lines.push(dtEnd);
      if (lastMod) lines.push(lastMod);
      lines.push(foldLine(`SUMMARY:${icsEscape(summary)}`));
      if (location) lines.push(foldLine(`LOCATION:${icsEscape(location)}`));
      if (description) lines.push(foldLine(`DESCRIPTION:${description}`));
      lines.push('END:VEVENT');
    }

    lines.push('END:VCALENDAR');

    const icsBody = lines.join('\r\n') + '\r\n';

    return new Response(icsBody, {
      status: 200,
      headers: {
        ...CORS_HEADERS,
        'Content-Type': 'text/calendar; charset=utf-8',
        'Content-Disposition': 'inline; filename="gigs.ics"',
        'Cache-Control': 'no-cache, no-store, must-revalidate',
      },
    });
  } catch (err) {
    console.error('gig-calendar error:', err);
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    );
  }
});
