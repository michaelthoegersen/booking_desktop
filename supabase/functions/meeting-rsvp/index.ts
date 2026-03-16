import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" };

  try {
    const url = new URL(req.url);
    const meetingId = url.searchParams.get("meeting_id");
    const userId = url.searchParams.get("user_id");
    const response = url.searchParams.get("response");

    if (!meetingId || !userId || !response) {
      return new Response(
        JSON.stringify({ error: "Mangler parametere." }),
        { status: 400, headers: jsonHeaders },
      );
    }

    if (!["attending", "not_attending"].includes(response)) {
      return new Response(
        JSON.stringify({ error: "Ugyldig svar." }),
        { status: 400, headers: jsonHeaders },
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Update RSVP status
    const { error } = await supabase
      .from("meeting_participants")
      .update({ rsvp_status: response })
      .eq("meeting_id", meetingId)
      .eq("user_id", userId);

    if (error) {
      console.error("RSVP update error:", error);
      return new Response(
        JSON.stringify({ error: "Kunne ikke registrere svaret." }),
        { status: 500, headers: jsonHeaders },
      );
    }

    // Get meeting details + user name
    const { data: meeting } = await supabase
      .from("meetings")
      .select("title, date, start_time, city")
      .eq("id", meetingId)
      .single();

    const { data: profile } = await supabase
      .from("profiles")
      .select("name")
      .eq("id", userId)
      .single();

    return new Response(
      JSON.stringify({
        ok: true,
        title: meeting?.title ?? "",
        date: meeting?.date ?? "",
        start_time: meeting?.start_time ? (meeting.start_time as string).substring(0, 5) : "",
        city: meeting?.city ?? "",
        user_name: profile?.name ?? "",
      }),
      { status: 200, headers: jsonHeaders },
    );
  } catch (e) {
    console.error("meeting-rsvp error:", e);
    return new Response(
      JSON.stringify({ error: "En uventet feil oppstod." }),
      { status: 500, headers: jsonHeaders },
    );
  }
});
