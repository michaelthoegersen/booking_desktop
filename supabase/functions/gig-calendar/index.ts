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

// Format a date string (yyyy-MM-dd) + optional time to iCal VALUE=DATE or
// DATE-TIME. Time inputs are user-entered free text in places (e.g.
// "13:00-18:00 (kommentar)"), so extract the first HHMM we can find rather
// than blindly stripping colons.
function icsDate(dateStr: string, time?: string | null): string {
  const d = dateStr.replace(/-/g, '');
  if (!time) return d;
  // Find the first occurrence of HH:MM or HHMM in the string.
  const m = time.match(/\b(\d{1,2}):?(\d{2})\b/);
  if (!m) return d;
  const hh = m[1].padStart(2, '0');
  const mm = m[2];
  return `${d}T${hh}${mm}00`;
}

// Returns true when the time string is parseable as a real HH:MM, so we
// can decide whether to emit a date-time or all-day event.
function hasParseableTime(time?: string | null): boolean {
  if (!time) return false;
  return /\b\d{1,2}:?\d{2}\b/.test(time);
}

// Format ISO timestamp to iCal UTC format: 20260315T190000Z
function icsTimestamp(iso: string): string {
  return new Date(iso).toISOString().replace(/[-:]/g, '').replace(/\.\d+/, '');
}

// Compute a SEQUENCE number from updated_at (seconds since epoch, capped)
// This ensures calendar apps detect changes when a gig is edited.
function icsSequence(updatedAt: string | null, createdAt: string | null): number {
  if (!updatedAt || !createdAt) return 0;
  const updated = new Date(updatedAt).getTime();
  const created = new Date(createdAt).getTime();
  if (updated <= created) return 0;
  // Each edit bumps sequence — use seconds difference
  return Math.floor((updated - created) / 1000);
}

// Fold long lines per RFC 5545 (max 75 octets per line).
// Must not split multi-byte UTF-8 characters across lines.
function foldLine(line: string): string {
  const encoder = new TextEncoder();
  const totalBytes = encoder.encode(line);
  if (totalBytes.length <= 75) return line;

  const parts: string[] = [];
  let currentLine = '';
  let currentBytes = 0;
  let firstLine = true;

  for (const char of line) {
    const charBytes = encoder.encode(char).length;
    const maxLen = firstLine ? 75 : 74;
    if (currentBytes + charBytes > maxLen) {
      parts.push(firstLine ? currentLine : ' ' + currentLine);
      currentLine = char;
      currentBytes = charBytes;
      firstLine = false;
    } else {
      currentLine += char;
      currentBytes += charBytes;
    }
  }
  if (currentLine) {
    parts.push(firstLine ? currentLine : ' ' + currentLine);
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

    // Fetch all non-cancelled gigs for this company. We deliberately do NOT
    // filter on `archived` here — the multi-condition OR filter has bitten
    // us before (rows with `archived` literally NULL were getting dropped),
    // and archived gigs are extremely rare in practice. Filter manually.
    const { data: gigsRaw, error: gigsErr } = await supabase
      .from('gigs')
      .select('*')
      .eq('company_id', companyId)
      .neq('status', 'cancelled')
      .order('date_from', { ascending: true });

    if (gigsErr) {
      console.error('Gigs query error:', gigsErr);
      return new Response('Database error', { status: 500, headers: CORS_HEADERS });
    }
    const gigs = (gigsRaw || []).filter((g: any) => g.archived !== true);

    // Mark which gigs belong to a multi-date offer so rehearsals can be
    // labeled "Prøve" instead of "Øvelse".
    const offerPartIds = new Set<string>();
    const gigIds = (gigs || []).map((g: any) => g.id as string);
    if (gigIds.length > 0) {
      const { data: junction } = await supabase
        .from('gig_offer_gigs')
        .select('gig_id, offer_id')
        .in('gig_id', gigIds);
      const counts = new Map<string, number>();
      const offerByGig = new Map<string, string>();
      for (const r of (junction || [])) {
        const oid = r.offer_id as string;
        counts.set(oid, (counts.get(oid) || 0) + 1);
        offerByGig.set(r.gig_id as string, oid);
      }
      for (const [gigId, oid] of offerByGig) {
        if ((counts.get(oid) || 0) > 1) offerPartIds.add(gigId);
      }
    }

    // Also fetch meetings — they live in a separate table and were never
    // included in the calendar feed before.
    const { data: meetings } = await supabase
      .from('meetings')
      .select('*')
      .eq('company_id', companyId)
      .neq('status', 'draft')
      .order('date', { ascending: true });

    // Build iCalendar
    const calName = icsEscape(company.name || 'Gigs');
    const now = icsTimestamp(new Date().toISOString());

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
      const status = gig.status as string | null || '';
      const type = gig.type as string | null || 'gig';
      const performanceTime = gig.performance_time as string | null;
      const meetingTime = gig.meeting_time as string | null;
      const getInTime = gig.get_in_time as string | null;
      const rehearsalTime = gig.rehearsal_time as string | null;
      const getOutTime = gig.get_out_time as string | null;
      const updatedAt = gig.updated_at as string | null;
      const createdAt = gig.created_at as string | null;
      const address = gig.customer_address as string | null || '';
      const firma = gig.customer_firma as string | null || '';
      const showDesc = gig.show_desc as string | null || '';
      const notesContract = gig.notes_for_contract as string | null || '';

      // SUMMARY: prefix + type + sted
      const prefix = (company.name || '').split(' ')[0] || 'Gig';
      const isOfferPart = offerPartIds.has(gig.id as string);
      let summary: string;
      if (type === 'rehearsal') {
        const label = isOfferPart ? 'Prøve' : 'Øvelse';
        summary = `${prefix} ${label}${venue ? ' — ' + venue : ''}`;
      } else if (type === 'other') {
        summary = `${prefix} Aktivitet${venue ? ' — ' + venue : (city ? ' — ' + city : '')}`;
      } else if (status === 'inquiry' || status === 'Inquiry') {
        summary = `${prefix} Gig?${venue ? ' — ' + venue : (city ? ' — ' + city : '')}`;
      } else {
        summary = `${prefix} Gig${venue ? ' — ' + venue : (city ? ' — ' + city : '')}`;
      }

      // Add customer name if available
      if (firma) {
        summary += ` (${firma})`;
      }

      // LOCATION
      const location = [venue, address, city].filter(Boolean).join(', ');

      // DESCRIPTION
      const descParts: string[] = [];
      if (firma) descParts.push(`Kunde: ${firma}`);
      if (meetingTime) descParts.push(`Oppmøte: ${meetingTime}`);
      if (getInTime) descParts.push(`Get-in: ${getInTime}`);
      if (rehearsalTime) descParts.push(`Prøver: ${rehearsalTime}`);
      if (performanceTime) descParts.push(`Spilletid: ${performanceTime}`);
      if (getOutTime) descParts.push(`Get-out: ${getOutTime}`);
      if (showDesc) descParts.push(`Show: ${showDesc}`);
      if (notesContract) descParts.push(`Notater: ${notesContract}`);
      if (status) descParts.push(`Status: ${status}`);
      const description = descParts.join('\\n');

      // DTSTART / DTEND
      // For gigs we anchor on performance_time. For rehearsals/other we
      // prefer rehearsal_time, then meeting_time, then performance_time —
      // anything that gives a real time so the event isn't shown as
      // all-day in the calendar.
      const startTimeStr = type === 'gig'
          ? performanceTime
          : (hasParseableTime(rehearsalTime)
              ? rehearsalTime
              : (hasParseableTime(meetingTime)
                  ? meetingTime
                  : performanceTime));
      const hasTime = hasParseableTime(startTimeStr);
      const dtStart = hasTime
        ? `DTSTART:${icsDate(dateFrom, startTimeStr)}`
        : `DTSTART;VALUE=DATE:${icsDate(dateFrom)}`;

      let dtEnd: string;
      if (hasTime) {
        const m = startTimeStr!.match(/\b(\d{1,2}):?(\d{2})\b/)!;
        const startH = parseInt(m[1], 10);
        const startM = parseInt(m[2], 10);
        const endH = (startH + 2) % 24;
        const endTime =
            `${String(endH).padStart(2, '0')}:${String(startM).padStart(2, '0')}`;
        dtEnd = `DTEND:${icsDate(dateTo, endTime)}`;
      } else {
        // All-day: DTEND is exclusive
        const endDate = new Date(dateTo + 'T00:00:00');
        endDate.setDate(endDate.getDate() + 1);
        const y = endDate.getFullYear();
        const m = String(endDate.getMonth() + 1).padStart(2, '0');
        const d = String(endDate.getDate()).padStart(2, '0');
        dtEnd = `DTEND;VALUE=DATE:${y}${m}${d}`;
      }

      // SEQUENCE — critical for calendar apps to detect updates
      const sequence = icsSequence(updatedAt, createdAt);

      // LAST-MODIFIED
      const lastMod = updatedAt ? icsTimestamp(updatedAt) : now;

      lines.push('BEGIN:VEVENT');
      lines.push(`UID:${uid}@tourflow`);
      lines.push(`DTSTAMP:${now}`);
      lines.push(`SEQUENCE:${sequence}`);
      lines.push(`LAST-MODIFIED:${lastMod}`);
      lines.push(dtStart);
      lines.push(dtEnd);
      lines.push(foldLine(`SUMMARY:${icsEscape(summary)}`));
      if (location) lines.push(foldLine(`LOCATION:${icsEscape(location)}`));
      if (description) lines.push(foldLine(`DESCRIPTION:${description}`));

      // STATUS mapping
      if (status === 'confirmed') {
        lines.push('STATUS:CONFIRMED');
      } else if (status === 'inquiry') {
        lines.push('STATUS:TENTATIVE');
      }

      // VALARM — fire a notification at the event start (only for timed
      // events; all-day events get a default-time alarm instead).
      if (hasTime) {
        lines.push('BEGIN:VALARM');
        lines.push('ACTION:DISPLAY');
        lines.push(foldLine(`DESCRIPTION:${icsEscape(summary)}`));
        lines.push('TRIGGER:PT0M');
        lines.push('END:VALARM');
      }

      lines.push('END:VEVENT');
    }

    // Meetings — emit one VEVENT per row.
    for (const meeting of (meetings || [])) {
      const uid = meeting.id as string;
      const dateStr = meeting.date as string | null;
      if (!dateStr) continue;
      const title = (meeting.title as string | null) || 'Møte';
      const address = (meeting.address as string | null) || '';
      const city = (meeting.city as string | null) || '';
      const startTime = meeting.start_time as string | null;
      const endTime = meeting.end_time as string | null;
      const comment = (meeting.comment as string | null) || '';
      const updatedAt = meeting.updated_at as string | null;
      const createdAt = meeting.created_at as string | null;

      const prefix = (company.name || '').split(' ')[0] || 'Møte';
      const summary = `${prefix} Møte — ${title}`;
      const location = [address, city].filter(Boolean).join(', ');
      const description = comment;

      const hasTime = hasParseableTime(startTime);
      const dtStart = hasTime
        ? `DTSTART:${icsDate(dateStr, startTime)}`
        : `DTSTART;VALUE=DATE:${icsDate(dateStr)}`;
      let dtEnd: string;
      if (hasTime && hasParseableTime(endTime)) {
        dtEnd = `DTEND:${icsDate(dateStr, endTime)}`;
      } else if (hasTime) {
        // Default duration 1h if no end time
        const m = startTime!.match(/\b(\d{1,2}):?(\d{2})\b/)!;
        const startH = parseInt(m[1], 10);
        const startM = parseInt(m[2], 10);
        const endH = (startH + 1) % 24;
        const t = `${String(endH).padStart(2, '0')}:${String(startM).padStart(2, '0')}`;
        dtEnd = `DTEND:${icsDate(dateStr, t)}`;
      } else {
        const endDate = new Date(dateStr + 'T00:00:00');
        endDate.setDate(endDate.getDate() + 1);
        const y = endDate.getFullYear();
        const m = String(endDate.getMonth() + 1).padStart(2, '0');
        const d = String(endDate.getDate()).padStart(2, '0');
        dtEnd = `DTEND;VALUE=DATE:${y}${m}${d}`;
      }

      const sequence = icsSequence(updatedAt, createdAt);
      const lastMod = updatedAt ? icsTimestamp(updatedAt) : now;

      lines.push('BEGIN:VEVENT');
      lines.push(`UID:meeting-${uid}@tourflow`);
      lines.push(`DTSTAMP:${now}`);
      lines.push(`SEQUENCE:${sequence}`);
      lines.push(`LAST-MODIFIED:${lastMod}`);
      lines.push(dtStart);
      lines.push(dtEnd);
      lines.push(foldLine(`SUMMARY:${icsEscape(summary)}`));
      if (location) lines.push(foldLine(`LOCATION:${icsEscape(location)}`));
      if (description) lines.push(foldLine(`DESCRIPTION:${icsEscape(description)}`));
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
        'ETag': `"${now}"`,
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
