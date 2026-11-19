// send-resend-email/index.ts
// Supabase Edge Function — sends email through Resend's HTTPS API.
//
// Why this exists: the edge runtime runs on AWS, and Domeneshop refuses mail
// from AWS IPs ([ACR04]). The old path retried the SMTP call up to eight
// times hoping for a kinder IP, and the Microsoft Graph fallback only works
// for a company that has connected Microsoft from the desktop app — a
// connection that silently expires. Neither is something to rely on for a
// contract going to a customer.
//
// Resend is spoken over HTTPS, so no IP reputation is involved and nothing
// per-user has to stay connected. The sending domain is verified once with
// DNS records, after which every company whose from-address lives on a
// verified domain can send.
//
// POST { to, subject, body, from, fromName?, isHtml?, cc?, bcc?,
//        replyTo?, attachments?: [{ filename, content(base64) }] }
//   -> { sent: true, id } | { sent: false, error }

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const RESEND_URL = "https://api.resend.com/emails";

function reply(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

/// Resend takes recipients as a list; callers pass either a single address or
/// several separated by comma or semicolon.
function addressList(raw: unknown): string[] {
  if (typeof raw !== "string") return [];
  return raw
    .split(/[,;]/)
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    // Not configured yet. Say so plainly so the caller can fall through to
    // the older paths instead of treating this as a delivery failure.
    return reply({ sent: false, error: "resend_not_configured" });
  }

  try {
    const payload = await req.json();
    const to = addressList(payload.to);
    const from = (payload.from as string | undefined)?.trim() ?? "";
    const subject = (payload.subject as string | undefined) ?? "";
    const body = (payload.body as string | undefined) ?? "";

    if (to.length === 0) return reply({ sent: false, error: "missing to" });
    if (from.length === 0) return reply({ sent: false, error: "missing from" });

    const fromName = (payload.fromName as string | undefined)?.trim();
    const fromHeader = fromName && fromName.length > 0
      ? `${fromName} <${from}>`
      : from;

    const mail: Record<string, unknown> = {
      from: fromHeader,
      to,
      subject,
    };
    if (payload.isHtml === true) {
      mail.html = body;
    } else {
      mail.text = body;
    }

    const cc = addressList(payload.cc);
    if (cc.length > 0) mail.cc = cc;
    const bcc = addressList(payload.bcc);
    if (bcc.length > 0) mail.bcc = bcc;
    const replyTo = addressList(payload.replyTo);
    if (replyTo.length > 0) mail.reply_to = replyTo;

    if (Array.isArray(payload.attachments) && payload.attachments.length > 0) {
      mail.attachments = payload.attachments.map((a: Record<string, unknown>) => ({
        filename: a.filename ?? a.name ?? "vedlegg",
        content: a.content ?? a.contentBytes,
      }));
    }

    const res = await fetch(RESEND_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(mail),
    });

    const text = await res.text();
    if (!res.ok) {
      // Resend's own message is the useful part — an unverified sending
      // domain reads as "The <domain> domain is not verified", which tells
      // the operator exactly what to do.
      return reply({ sent: false, error: text || `HTTP ${res.status}` });
    }

    let id: unknown;
    try {
      id = JSON.parse(text)?.id;
    } catch (_) {
      id = null;
    }
    return reply({ sent: true, id });
  } catch (e) {
    return reply({ sent: false, error: String(e) });
  }
});
