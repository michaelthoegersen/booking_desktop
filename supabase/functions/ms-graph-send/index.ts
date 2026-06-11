// ms-graph-send — send email via Microsoft Graph using a company's DELEGATED
// OAuth token (the one stored when the user pressed "Koble til Microsoft").
//
// This lets the WEB app send via Microsoft Graph (the desktop app does the same
// client-side). Delegated = sends as the connected user; needs only that user's
// consent, NOT tenant admin or SMTP AUTH. Public client refresh (no secret).
//
// POST { company_id, to, subject, body, is_html?, attachments?: [{name, contentBytes(base64)}] }
//   -> { sent: true } | { sent: false, error }
//
// Deploy: supabase functions deploy ms-graph-send --no-verify-jwt --project-ref fqefvgqlrntwgschkugf

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CLIENT_ID = "c9a7931d-973f-4278-90d6-f825250d4b49";
const SCOPE = "Mail.Send offline_access User.Read";
const TOKEN_URL =
  "https://login.microsoftonline.com/organizations/oauth2/v2.0/token";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const { company_id, to, subject, body, is_html, attachments } =
      await req.json();
    if (!company_id || !to) return reply({ sent: false, error: "missing fields" });

    const sb = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // 1. Look up the stored delegated refresh token for this company.
    const { data: row } = await sb
      .from("microsoft_oauth_tokens")
      .select("refresh_token, email")
      .eq("company_id", company_id)
      .maybeSingle();

    if (!row?.refresh_token) {
      return reply({ sent: false, error: "no_oauth_connection" });
    }

    // 2. Refresh → access token (public client, no secret).
    const tokenRes = await fetch(TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: CLIENT_ID,
        grant_type: "refresh_token",
        refresh_token: row.refresh_token,
        scope: SCOPE,
      }),
    });
    const tokens = await tokenRes.json();
    if (!tokenRes.ok || !tokens.access_token) {
      return reply({ sent: false, error: tokens.error_description ?? tokens });
    }

    // 3. Persist a rotated refresh token if Microsoft returned a new one.
    if (tokens.refresh_token && tokens.refresh_token !== row.refresh_token) {
      await sb
        .from("microsoft_oauth_tokens")
        .update({
          refresh_token: tokens.refresh_token,
          updated_at: new Date().toISOString(),
        })
        .eq("company_id", company_id);
    }

    // 4. Build the Graph message.
    const recipients = String(to)
      .split(/[,;]/)
      .map((s: string) => s.trim())
      .filter((s: string) => s.length > 0)
      .map((a: string) => ({ emailAddress: { address: a } }));

    // deno-lint-ignore no-explicit-any
    const message: any = {
      subject: subject ?? "",
      body: { contentType: is_html ? "HTML" : "Text", content: body ?? "" },
      toRecipients: recipients,
    };
    if (Array.isArray(attachments) && attachments.length > 0) {
      // deno-lint-ignore no-explicit-any
      message.attachments = attachments.map((a: any) => ({
        "@odata.type": "#microsoft.graph.fileAttachment",
        name: a.name,
        contentType: "application/pdf",
        contentBytes: a.contentBytes,
      }));
    }

    // 5. Send as the connected user.
    const sendRes = await fetch(
      "https://graph.microsoft.com/v1.0/me/sendMail",
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${tokens.access_token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ message, saveToSentItems: true }),
      },
    );

    if (sendRes.status === 202 || sendRes.status === 200) {
      return reply({ sent: true, email: row.email });
    }
    const errText = await sendRes.text();
    return reply({ sent: false, error: errText });
  } catch (e) {
    return reply({ sent: false, error: String(e) });
  }
});
