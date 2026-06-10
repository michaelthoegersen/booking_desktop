// truck-toll — actual Norwegian toll (bompenger) for one truck leg.
//
// Does the whole thing server-side (geocode → route → NVDB station match) so it
// is not subject to browser CORS or per-client rate limits, which made the old
// client-side version silently return 0 and fall back to km × 2.80.
//
// POST { "from": "Moss", "to": "Oslo" }  ->  { "toll": 123, "stations": 2 }
//
// Deploy: supabase functions deploy truck-toll --no-verify-jwt --project-ref fqefvgqlrntwgschkugf

const NVDB_BASE = "https://nvdbapiles.atlas.vegvesen.no";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

// ── caches (warm invocations) ───────────────────────────────────────────────
// deno-lint-ignore no-explicit-any
let stationCache: any[] | null = null;
let stationCacheAt = 0;
const STATION_TTL = 1000 * 60 * 60 * 12;
const geoCache = new Map<string, [number, number]>();
const tollCache = new Map<string, number>();

function num(v: unknown): number {
  const n = typeof v === "number" ? v : parseFloat(String(v ?? ""));
  return isNaN(n) ? 0 : n;
}

// ── NVDB stations ───────────────────────────────────────────────────────────
// deno-lint-ignore no-explicit-any
function parseStation(obj: any) {
  const props: Record<string, unknown> = {};
  for (const e of obj?.egenskaper ?? []) props[e.navn] = e.verdi;
  const wkt = obj?.lokasjon?.geometri?.wkt as string | undefined;
  if (!wkt) return null;
  const m = wkt.match(/POINT\s*Z?\s*\(\s*([\d.+-]+)\s+([\d.+-]+)/);
  if (!m) return null;
  const lat = parseFloat(m[1]);
  const lon = parseFloat(m[2]);
  if (isNaN(lat) || isNaN(lon)) return null;
  return {
    lat,
    lon,
    priceCar: num(props["Takst liten bil"]),
    priceTruck: num(props["Takst stor bil"]),
    // Toll-ring group for the one-hour rule: stations sharing this id belong to
    // the same bomring and are charged ONCE per pass, not per station.
    gruppe: num(props["Timesregel, passeringsgruppe"]),
  };
}

async function loadStations() {
  if (stationCache && Date.now() - stationCacheAt < STATION_TTL) {
    return stationCache;
  }
  // deno-lint-ignore no-explicit-any
  const stations: any[] = [];
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
  stationCache = stations;
  stationCacheAt = Date.now();
  return stations;
}

// ── geocode (Google) + route (OSRM) ─────────────────────────────────────────
// Google Geocoding is used instead of Nominatim because Nominatim's 1 req/sec
// limit made parallel leg lookups (the client prefetches all legs at once) fail
// and return 0 → km × rate fallback.
const GOOGLE_KEY = Deno.env.get("GOOGLE_MAPS_API_KEY") ?? "";

async function geocode(place: string): Promise<[number, number] | null> {
  const key = place.trim().toLowerCase();
  if (geoCache.has(key)) return geoCache.get(key)!;
  const url = `https://maps.googleapis.com/maps/api/geocode/json` +
    `?address=${encodeURIComponent(`${place}, Norway`)}&region=no&key=${GOOGLE_KEY}`;
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

// Returns the OSRM route geometry as [lat, lon] points (one retry on failure).
async function routePoints(
  from: [number, number],
  to: [number, number],
): Promise<[number, number][]> {
  const coordStr = `${from[1]},${from[0]};${to[1]},${to[0]}`;
  const url = `https://router.project-osrm.org/route/v1/driving/${coordStr}` +
    `?overview=full&geometries=geojson`;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const res = await fetch(url, {
        headers: { "User-Agent": "TourFlow/1.0 (post@tourflow.no)" },
      });
      if (!res.ok) continue;
      const data = await res.json();
      if (data?.code !== "Ok") continue;
      const coords = data?.routes?.[0]?.geometry?.coordinates;
      if (!Array.isArray(coords)) continue;
      return coords.map((c: number[]) => [c[1], c[0]] as [number, number]);
    } catch (_) {
      // retry
    }
  }
  return [];
}

// ── matching (haversine, same logic as the Flutter TollService) ─────────────
function haversine(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number,
): number {
  const r = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return r * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// deno-lint-ignore no-explicit-any
function truckTollForPoints(points: [number, number][], stations: any[]) {
  const thresholdMeters = 50;
  const geoDedupMeters = 300;
  // deno-lint-ignore no-explicit-any
  const passed: any[] = [];
  for (const [pLat, pLon] of points) {
    for (const s of stations) {
      if (haversine(pLat, pLon, s.lat, s.lon) > thresholdMeters) continue;
      const dup = passed.some((p) =>
        haversine(p.lat, p.lon, s.lat, s.lon) < geoDedupMeters
      );
      if (dup) continue;
      passed.push(s);
    }
  }
  // One-hour rule (timesregel): stations in the same passeringsgruppe (toll
  // ring) are charged once per pass — the highest tariff in the ring — not once
  // per station. Stations with no group (single toll roads/bridges) are charged
  // individually.
  let toll = 0;
  const ringMax = new Map<number, number>();
  for (const s of passed) {
    const price = s.priceTruck > 0 ? s.priceTruck : s.priceCar;
    if (s.gruppe && s.gruppe > 0) {
      ringMax.set(s.gruppe, Math.max(ringMax.get(s.gruppe) ?? 0, price));
    } else {
      toll += price;
    }
  }
  for (const v of ringMax.values()) toll += v;
  return { toll, stations: passed.length, rings: ringMax.size };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const { from, to } = await req.json();
    if (!from || !to) {
      return new Response(JSON.stringify({ toll: 0, stations: 0 }), {
        headers: { ...CORS, "Content-Type": "application/json" },
      });
    }
    const cacheKey = `${String(from).toLowerCase()}__${String(to).toLowerCase()}`;
    if (tollCache.has(cacheKey)) {
      return new Response(
        JSON.stringify({ toll: tollCache.get(cacheKey), stations: -1, cached: true }),
        { headers: { ...CORS, "Content-Type": "application/json" } },
      );
    }

    const [stations, fromC, toC] = await Promise.all([
      loadStations(),
      geocode(String(from)),
      geocode(String(to)),
    ]);
    if (!fromC || !toC) {
      return new Response(JSON.stringify({ toll: 0, stations: 0, geocodeFailed: true }), {
        headers: { ...CORS, "Content-Type": "application/json" },
      });
    }
    const points = await routePoints(fromC, toC);
    const result = truckTollForPoints(points, stations);
    tollCache.set(cacheKey, result.toll);
    return new Response(JSON.stringify(result), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ toll: 0, stations: 0, error: String(e) }), {
      status: 200,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
});
