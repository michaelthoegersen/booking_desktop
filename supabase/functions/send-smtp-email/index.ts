// send-smtp-email/index.ts
// Supabase Edge Function — sends email via raw SMTP socket.
//
// Accepts SMTP credentials in the request body so any account can be used.
// Falls back to looking up the user's default SMTP account from the DB.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// ---------- Raw SMTP helpers ----------

const CRLF = "\r\n";
const encoder = new TextEncoder();
const decoder = new TextDecoder();

async function readResponse(reader: ReadableStreamDefaultReader<Uint8Array>): Promise<string> {
  const { value } = await reader.read();
  return value ? decoder.decode(value) : "";
}

async function sendCmd(
  writer: WritableStreamDefaultWriter<Uint8Array>,
  reader: ReadableStreamDefaultReader<Uint8Array>,
  cmd: string,
): Promise<string> {
  await writer.write(encoder.encode(cmd + CRLF));
  return readResponse(reader);
}

function base64Wrap(b64: string): string {
  const lines: string[] = [];
  for (let i = 0; i < b64.length; i += 76) {
    lines.push(b64.substring(i, i + 76));
  }
  return lines.join(CRLF) + CRLF;
}

function encodeSubject(subject: string): string {
  // Always encode as base64 UTF-8 for safety
  return `=?UTF-8?B?${btoa(unescape(encodeURIComponent(subject)))}?=`;
}

async function rawSmtpSend(opts: {
  host: string;
  port: number;
  username: string;
  password: string;
  from: string;
  displayName: string;
  recipients: string[];
  subject: string;
  body: string;
  isHtml: boolean;
  attachments?: { name: string; contentBytes: string }[];
}) {
  const useSsl = opts.port === 465;

  let conn: Deno.TcpConn | Deno.TlsConn;
  if (useSsl) {
    conn = await Deno.connectTls({ hostname: opts.host, port: opts.port });
  } else {
    conn = await Deno.connect({ hostname: opts.host, port: opts.port });
  }

  let reader = conn.readable.getReader();
  let writer = conn.writable.getWriter();

  try {
    // Read greeting
    await readResponse(reader);

    // EHLO
    let ehlo = await sendCmd(writer, reader, "EHLO tourflow.app");

    // STARTTLS if not already SSL
    if (!useSsl && ehlo.includes("STARTTLS")) {
      await sendCmd(writer, reader, "STARTTLS");
      // Release current reader/writer before upgrading
      reader.releaseLock();
      writer.releaseLock();
      // Upgrade to TLS
      const tlsConn = await Deno.startTls(conn as Deno.TcpConn, { hostname: opts.host });
      conn = tlsConn;
      reader = conn.readable.getReader();
      writer = conn.writable.getWriter();
      ehlo = await sendCmd(writer, reader, "EHLO tourflow.app");
    }

    // AUTH LOGIN
    await sendCmd(writer, reader, "AUTH LOGIN");
    await sendCmd(writer, reader, btoa(opts.username));
    const authResp = await sendCmd(writer, reader, btoa(opts.password));
    if (!authResp.startsWith("235")) {
      throw new Error(`SMTP auth failed: ${authResp.trim()}`);
    }

    // MAIL FROM
    const fromResp = await sendCmd(writer, reader, `MAIL FROM:<${opts.from}>`);
    if (!fromResp.startsWith("250")) {
      throw new Error(`MAIL FROM failed: ${fromResp.trim()}`);
    }

    // RCPT TO
    for (const r of opts.recipients) {
      const rcptResp = await sendCmd(writer, reader, `RCPT TO:<${r}>`);
      if (!rcptResp.startsWith("250")) {
        throw new Error(`RCPT TO failed for ${r}: ${rcptResp.trim()}`);
      }
    }

    // DATA
    const dataResp = await sendCmd(writer, reader, "DATA");
    if (!dataResp.startsWith("354")) {
      throw new Error(`DATA command failed: ${dataResp.trim()}`);
    }

    // Build MIME message
    const boundary = `boundary-${Date.now()}`;
    const hasAttachments = opts.attachments && opts.attachments.length > 0;
    const fromHeader = opts.displayName
      ? `"${opts.displayName}" <${opts.from}>`
      : opts.from;

    let mime = "";
    mime += `From: ${fromHeader}${CRLF}`;
    mime += `To: ${opts.recipients.join(", ")}${CRLF}`;
    mime += `Subject: ${encodeSubject(opts.subject)}${CRLF}`;
    mime += `MIME-Version: 1.0${CRLF}`;

    const bodyB64 = btoa(unescape(encodeURIComponent(opts.body)));
    const contentType = opts.isHtml ? "text/html" : "text/plain";

    if (hasAttachments) {
      mime += `Content-Type: multipart/mixed; boundary="${boundary}"${CRLF}`;
      mime += CRLF;
      // Body part
      mime += `--${boundary}${CRLF}`;
      mime += `Content-Type: ${contentType}; charset="utf-8"${CRLF}`;
      mime += `Content-Transfer-Encoding: base64${CRLF}`;
      mime += CRLF;
      mime += base64Wrap(bodyB64);

      // Attachment parts
      for (const att of opts.attachments!) {
        mime += `--${boundary}${CRLF}`;
        mime += `Content-Type: application/pdf; name="${att.name}"${CRLF}`;
        mime += `Content-Transfer-Encoding: base64${CRLF}`;
        mime += `Content-Disposition: attachment; filename="${att.name}"${CRLF}`;
        mime += CRLF;
        mime += base64Wrap(att.contentBytes);
      }
      mime += `--${boundary}--${CRLF}`;
    } else {
      mime += `Content-Type: ${contentType}; charset="utf-8"${CRLF}`;
      mime += `Content-Transfer-Encoding: base64${CRLF}`;
      mime += CRLF;
      mime += base64Wrap(bodyB64);
    }

    // Send MIME data + end with <CRLF>.<CRLF>
    const safeData = mime.replace(/\r\n/g, "\n").replace(/\n/g, "\r\n");
    await writer.write(encoder.encode(safeData));
    const endResp = await sendCmd(writer, reader, `${CRLF}.`);
    if (!endResp.startsWith("250")) {
      throw new Error(`Message rejected: ${endResp.trim()}`);
    }

    // QUIT
    try { await sendCmd(writer, reader, "QUIT"); } catch (_) { /* ignore */ }
  } finally {
    try { reader.releaseLock(); } catch (_) { /* ignore */ }
    try { writer.releaseLock(); } catch (_) { /* ignore */ }
    try { conn.close(); } catch (_) { /* ignore */ }
  }
}

// ---------- Main handler ----------

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return new Response("Method not allowed", {
      status: 405,
      headers: CORS_HEADERS,
    });
  }

  try {
    const {
      to,
      subject,
      body,
      contentType,
      attachments,
      // SMTP credentials — either passed directly or looked up from DB
      smtpHost,
      smtpPort,
      smtpUser,
      smtpPass,
      fromEmail,
      fromName,
      // Flutter client sends these field names:
      from: fromAlt,
      isHtml: isHtmlFlag,
    } = (await req.json()) as {
      to: string;
      subject: string;
      body: string;
      contentType?: string;
      attachments?: { name: string; contentBytes: string; filename?: string; content?: string }[];
      smtpHost?: string;
      smtpPort?: number;
      smtpUser?: string;
      smtpPass?: string;
      fromEmail?: string;
      fromName?: string;
      from?: string;
      isHtml?: boolean;
    };

    if (!to || !subject || !body) {
      return new Response(
        JSON.stringify({ error: "to, subject and body are required" }),
        {
          status: 400,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        }
      );
    }

    // Resolve SMTP credentials
    let host = smtpHost;
    let port = smtpPort ?? 587;
    let user = smtpUser;
    let pass = smtpPass;
    let senderEmail = fromEmail ?? fromAlt;
    let senderName = fromName ?? "";

    // If credentials not provided, look up from DB using auth token
    if (!host || !user || !pass) {
      const authHeader = req.headers.get("Authorization") ?? "";
      const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
      const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

      const sb = createClient(supabaseUrl, supabaseKey);

      // Extract user from JWT
      const token = authHeader.replace("Bearer ", "");
      const {
        data: { user: authUser },
      } = await sb.auth.getUser(token);

      if (!authUser) {
        return new Response(
          JSON.stringify({ error: "Authentication required for DB lookup" }),
          {
            status: 401,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          }
        );
      }

      const { data: accounts } = await sb
        .from("smtp_accounts")
        .select("*")
        .eq("user_id", authUser.id)
        .order("is_default", { ascending: false })
        .limit(1);

      if (!accounts || accounts.length === 0) {
        return new Response(
          JSON.stringify({ error: "No SMTP account configured" }),
          {
            status: 400,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          }
        );
      }

      const account = accounts[0];
      host = account.smtp_host ?? "smtp.domeneshop.no";
      port = account.smtp_port ?? 587;
      user = account.email;
      pass = account.password;
      senderEmail = senderEmail ?? account.email;
      senderName = senderName || account.display_name || "";
    }

    if (!senderEmail) senderEmail = user!;

    // Parse recipients
    const recipients = to
      .split(/[,;]/)
      .map((a: string) => a.trim())
      .filter((a: string) => a.length > 0);

    // Normalize attachments — Flutter client uses 'filename'/'content',
    // while the original API used 'name'/'contentBytes'
    const normalizedAttachments = attachments?.map((a) => ({
      name: a.name ?? a.filename ?? "attachment.pdf",
      contentBytes: a.contentBytes ?? a.content ?? "",
    }));

    const isHtml = isHtmlFlag === true || contentType === "HTML";

    await rawSmtpSend({
      host: host!,
      port,
      username: user!,
      password: pass!,
      from: senderEmail,
      displayName: senderName,
      recipients,
      subject,
      body,
      isHtml,
      attachments: normalizedAttachments,
    });

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("send-smtp-email error:", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
