// fix-offers-rls/index.ts
// One-time migration: allow all authenticated users to manage offers.
// Deploy, call once, then delete from Supabase dashboard.

import { Pool } from "https://deno.land/x/postgres@v0.17.0/mod.ts";

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  const dbUrl = Deno.env.get('SUPABASE_DB_URL');
  if (!dbUrl) {
    return new Response(JSON.stringify({ error: 'SUPABASE_DB_URL not available' }),
      { status: 500, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } });
  }

  const pool = new Pool(dbUrl, 1, true);
  const conn = await pool.connect();

  const statements = [
    // Drop any restrictive per-owner policies
    `DROP POLICY IF EXISTS "Users can update own offers" ON offers`,
    `DROP POLICY IF EXISTS "Users can update their own offers" ON offers`,
    `DROP POLICY IF EXISTS "Users can delete their own offers" ON offers`,
    `DROP POLICY IF EXISTS "Users can delete own offers" ON offers`,
    `DROP POLICY IF EXISTS "Users can insert their own offers" ON offers`,
    `DROP POLICY IF EXISTS "Users can insert own offers" ON offers`,
    `DROP POLICY IF EXISTS "Users can view their own offers" ON offers`,
    `DROP POLICY IF EXISTS "Users can view own offers" ON offers`,
    // Drop any previous team-wide policies (idempotent re-run)
    `DROP POLICY IF EXISTS "Authenticated users can select offers" ON offers`,
    `DROP POLICY IF EXISTS "Authenticated users can insert offers" ON offers`,
    `DROP POLICY IF EXISTS "Authenticated users can update offers" ON offers`,
    `DROP POLICY IF EXISTS "Authenticated users can delete offers" ON offers`,
    // Create open policies for all authenticated team members
    `CREATE POLICY "Authenticated users can select offers" ON offers FOR SELECT TO authenticated USING (true)`,
    `CREATE POLICY "Authenticated users can insert offers" ON offers FOR INSERT TO authenticated WITH CHECK (true)`,
    `CREATE POLICY "Authenticated users can update offers" ON offers FOR UPDATE TO authenticated USING (true) WITH CHECK (true)`,
    `CREATE POLICY "Authenticated users can delete offers" ON offers FOR DELETE TO authenticated USING (true)`,
  ];

  const results: { sql: string; ok: boolean; error?: string }[] = [];

  try {
    for (const sql of statements) {
      try {
        await conn.queryArray(sql);
        results.push({ sql: sql.substring(0, 80), ok: true });
      } catch (e) {
        results.push({ sql: sql.substring(0, 80), ok: false, error: String(e) });
      }
    }
  } finally {
    conn.release();
    await pool.end();
  }

  return new Response(
    JSON.stringify({ done: true, results }),
    { headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
  );
});
