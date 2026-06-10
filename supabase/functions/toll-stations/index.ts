// toll-stations — returns Norwegian toll stations from NVDB (Vegvesenet).
//
// Why server-side: NVDB's API does not send CORS headers and requires custom
// request headers, so a browser (the web app) cannot call it directly — the
// preflight fails and the client falls back to a flat km × rate estimate.
// This function fetches + parses NVDB server-side and returns a slim station
// list (with both car and truck/lastebil tariffs) that the client matches
// against a route polyline to compute actual bompenger.
//
// Deploy: supabase functions deploy toll-stations --no-verify-jwt --project-ref fqefvgqlrntwgschkugf

const NVDB_BASE = "https://nvdbapiles.atlas.vegvesen.no";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

// Warm-invocation cache (12h) so we don't hammer NVDB on every request.
let cache: unknown[] | null = null;
let cacheAt = 0;
const TTL_MS = 1000 * 60 * 60 * 12;

function num(v: unknown): number {
  const n = typeof v === "number" ? v : parseFloat(String(v ?? ""));
  return isNaN(n) ? 0 : n;
}

// deno-lint-ignore no-explicit-any
function parseStation(obj: any) {
  const props: Record<string, unknown> = {};
  for (const e of obj?.egenskaper ?? []) props[e.navn] = e.verdi;

  const wkt = obj?.lokasjon?.geometri?.wkt as string | undefined;
  if (!wkt) return null;

  // "POINT Z (lat lon elev)" or "POINT (lat lon)" — same order as the
  // original client parser, kept identical for parity.
  const m = wkt.match(/POINT\s*Z?\s*\(\s*([\d.+-]+)\s+([\d.+-]+)/);
  if (!m) return null;
  const lat = parseFloat(m[1]);
  const lon = parseFloat(m[2]);
  if (isNaN(lat) || isNaN(lon)) return null;

  return {
    id: obj.id ?? 0,
    name: (props["Navn bomstasjon"] as string) ?? "Ukjent",
    lat,
    lon,
    priceCar: num(props["Takst liten bil"]),
    priceCarRush: num(props["Rushtidstakst liten bil"]),
    // NVDB field for vehicles > 3500 kg (lastebil / buss / store kjøretøy)
    priceTruck: num(props["Takst stor bil"]),
    priceTruckRush: num(props["Rushtidstakst stor bil"]),
  };
}

async function loadStations() {
  if (cache && Date.now() - cacheAt < TTL_MS) return cache;

  const stations: unknown[] = [];
  let start: string | null = null;

  for (let page = 0; page < 10; page++) {
    let url = `${NVDB_BASE}/vegobjekter/45` +
      `?inkluder=egenskaper,lokasjon&srid=4326&antall=1000`;
    if (start) url += `&start=${encodeURIComponent(start)}`;

    const resp = await fetch(url, {
      headers: {
        "Accept": "application/json",
        "X-Client": "TourFlow/1.0",
        "X-Kontaktperson": "post@tourflow.no",
      },
    });
    if (!resp.ok) break;

    const body = await resp.json();
    const objs = body?.objekter ?? [];
    if (objs.length === 0) break;

    for (const o of objs) {
      const s = parseStation(o);
      if (s) stations.push(s);
    }

    const next = body?.metadata?.neste;
    if (!next || !next.start) break;
    start = next.start as string;
  }

  cache = stations;
  cacheAt = Date.now();
  return stations;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }
  try {
    const stations = await loadStations();
    return new Response(JSON.stringify({ stations }), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(
      JSON.stringify({ error: String(e), stations: [] }),
      { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }
});
