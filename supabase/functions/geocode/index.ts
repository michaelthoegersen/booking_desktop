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
// POST { points: [[lat, lon], ...] }
//   → { countries: ["NO", "SE", ...] }       ("Unknown" for one that failed)
//
// The reverse direction is batched because the country analyser samples a
// route every N points and used to fire one client request per sample — which
// is what made Nominatim 429 the whole IP in the first place.
//
// No country bias on forward lookups: these are international tour routes,
// not Norwegian legs.

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

// ── reverse: coordinate → country code ──────────────────────────────────────
// BigDataCloud is free and needs no key, so it carries the volume; Google is
// only there for the odd failure.
const countryCache = new Map<string, string>();

function cacheKey(lat: number, lon: number): string {
  // ~0.02° ≈ 2 km, same rounding the client used, so neighbouring samples on
  // one route collapse into a single lookup.
  return `${Math.round(lat * 50) / 50},${Math.round(lon * 50) / 50}`;
}

async function reverseCountry(lat: number, lon: number): Promise<string> {
  const key = cacheKey(lat, lon);
  if (countryCache.has(key)) return countryCache.get(key)!;

  try {
    const res = await fetch(
      `https://api.bigdatacloud.net/data/reverse-geocode-client` +
        `?latitude=${lat}&longitude=${lon}&localityLanguage=en`,
    );
    if (res.ok) {
      const data = await res.json();
      const code = data?.countryCode;
      if (typeof code === "string" && code.length === 2) {
        countryCache.set(key, code);
        return code;
      }
    }
  } catch (_) {
    // fall through to Google
  }

  try {
    const res = await fetch(
      `https://maps.googleapis.com/maps/api/geocode/json` +
        `?latlng=${lat},${lon}&result_type=country&key=${GOOGLE_KEY}`,
    );
    if (res.ok) {
      const data = await res.json();
      if (data?.status === "OK") {
        for (const c of data.results?.[0]?.address_components ?? []) {
          if (c.types?.includes("country")) {
            countryCache.set(key, c.short_name);
            return c.short_name;
          }
        }
      }
    }
  } catch (_) {
    // give up below
  }

  return "Unknown";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const body = await req.json();

    // ---- reverse: points → country codes ----
    if (Array.isArray(body?.points)) {
      const points = body.points as unknown[];

      const countries = await Promise.all(
        points.map((p) => {
          if (!Array.isArray(p) || p.length < 2) return "Unknown";
          return reverseCountry(Number(p[0]), Number(p[1]));
        }),
      );

      return new Response(JSON.stringify({ countries }), {
        headers: { ...CORS, "Content-Type": "application/json" },
      });
    }

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
    return new Response(JSON.stringify({ coords: [], countries: [], error: String(e) }), {
      status: 200,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
});
