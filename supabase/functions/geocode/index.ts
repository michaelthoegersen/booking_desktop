// geocode — turns place names into coordinates, server-side.
//
// Nominatim is not usable from the client: its 1 req/sec limit is per IP, so a
// handful of route lookups from one office gets the whole IP a 429 that sticks
// around. The route preview then showed "Route cached (no map)" forever.
// Google Geocoding has no such limit and keeps the key off the client.
//
// POST { places: ["Berlin", "Alta"] }
//   → { coords: [[lat, lon], [lat, lon]] }   (null for a place that failed)
//
// No country bias: these are international tour routes, not Norwegian legs.

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const GOOGLE_KEY = Deno.env.get("GOOGLE_MAPS_API_KEY") ?? "";

const geoCache = new Map<string, [number, number]>();

async function geocode(place: string): Promise<[number, number] | null> {
  const key = place.trim().toLowerCase();
  if (!key) return null;
  if (geoCache.has(key)) return geoCache.get(key)!;

  const url = `https://maps.googleapis.com/maps/api/geocode/json` +
    `?address=${encodeURIComponent(place)}&key=${GOOGLE_KEY}`;

  const res = await fetch(url);
  if (!res.ok) return null;

  const data = await res.json();
  if (data?.status !== "OK" || !Array.isArray(data.results) || data.results.length === 0) {
    return null;
  }

  const loc = data.results[0]?.geometry?.location;
  if (loc == null) return null;

  const coord: [number, number] = [loc.lat, loc.lng];
  geoCache.set(key, coord);
  return coord;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const body = await req.json();

    // Accept a single place too, so callers that need one coordinate stay simple.
    const places: string[] = Array.isArray(body?.places)
      ? body.places.map(String)
      : body?.place != null
      ? [String(body.place)]
      : [];

    if (places.length === 0) {
      return new Response(JSON.stringify({ coords: [] }), {
        headers: { ...CORS, "Content-Type": "application/json" },
      });
    }

    const coords = await Promise.all(places.map(geocode));

    return new Response(JSON.stringify({ coords }), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ coords: [], error: String(e) }), {
      status: 200,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
});
