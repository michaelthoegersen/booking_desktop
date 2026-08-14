// send-smtp-email/index.ts
// Supabase Edge Function — sends email via SMTP (Domeneshop etc.)
//
// Accepts SMTP credentials in the request body so any account can be used.
// Falls back to looking up the user's default SMTP account from the DB.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SmtpClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

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
    } = (await req.json()) as {
      to: string;
      subject: string;
      body: string;
      contentType?: string;
      attachments?: { name: string; contentBytes: string }[];
      smtpHost?: string;
      smtpPort?: number;
      smtpUser?: string;
      smtpPass?: string;
      fromEmail?: string;
      fromName?: string;
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
    let senderEmail = fromEmail;
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

    // Connect to SMTP
    const client = new SmtpClient();

    const connectConfig: Record<string, unknown> = {
      hostname: host!,
      port: port,
    };

    if (port === 465) {
      await client.connectTLS(connectConfig);
    } else {
      await client.connect(connectConfig);
      await client.starttls();
    }

    await client.login({ username: user!, password: pass! });

    // Build email content
    const isHtml = contentType === "HTML";
    const fromHeader = senderName
      ? `"${senderName}" <${senderEmail}>`
      : senderEmail;

    const boundary = `----=_Part_${Date.now()}_${Math.random().toString(36)}`;
    const hasPdfAttachments = attachments && attachments.length > 0;

    let rawEmail = "";
    rawEmail += `From: ${fromHeader}\r\n`;
    rawEmail += `To: ${recipients.join(", ")}\r\n`;
    rawEmail += `Subject: =?UTF-8?B?${btoa(
      unescape(encodeURIComponent(subject))
    )}?=\r\n`;
    rawEmail += `MIME-Version: 1.0\r\n`;

    if (hasPdfAttachments) {
      rawEmail += `Content-Type: multipart/mixed; boundary="${boundary}"\r\n`;
      rawEmail += `\r\n--${boundary}\r\n`;
      rawEmail += `Content-Type: ${
        isHtml ? "text/html" : "text/plain"
      }; charset=UTF-8\r\n`;
      rawEmail += `Content-Transfer-Encoding: base64\r\n\r\n`;
      rawEmail += `${btoa(unescape(encodeURIComponent(body)))}\r\n`;

      for (const att of attachments!) {
        rawEmail += `\r\n--${boundary}\r\n`;
        rawEmail += `Content-Type: application/pdf; name="${att.name}"\r\n`;
        rawEmail += `Content-Disposition: attachment; filename="${att.name}"\r\n`;
        rawEmail += `Content-Transfer-Encoding: base64\r\n\r\n`;
        // Split base64 into 76-char lines
        const b64 = att.contentBytes;
        for (let i = 0; i < b64.length; i += 76) {
          rawEmail += b64.substring(i, i + 76) + "\r\n";
        }
      }
      rawEmail += `\r\n--${boundary}--\r\n`;
    } else {
      rawEmail += `Content-Type: ${
        isHtml ? "text/html" : "text/plain"
      }; charset=UTF-8\r\n`;
      rawEmail += `Content-Transfer-Encoding: base64\r\n\r\n`;
      rawEmail += `${btoa(unescape(encodeURIComponent(body)))}\r\n`;
    }

    await client.sendRaw({
      from: senderEmail,
      to: recipients,
      data: rawEmail,
    });

    await client.close();

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
