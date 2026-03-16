import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { RtcTokenBuilder, RtcRole } from "npm:agora-token@2.0.3";

const APP_ID = "4fe1ae5ea7454ba9adc19030d559ce74";
const APP_CERTIFICATE = "a702163a3b08454bb4a80beae42e2dcc";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { channelName, uid } = await req.json();

    if (!channelName) {
      return new Response(
        JSON.stringify({ error: "channelName is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const role = RtcRole.PUBLISHER;
    const expireTs = Math.floor(Date.now() / 1000) + 86400; // 24 hours
    const privilegeExpireTs = expireTs;

    const token = RtcTokenBuilder.buildTokenWithUid(
      APP_ID,
      APP_CERTIFICATE,
      channelName,
      uid ?? 0,
      role,
      expireTs,
      privilegeExpireTs,
    );

    return new Response(
      JSON.stringify({ token }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: String(e) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
