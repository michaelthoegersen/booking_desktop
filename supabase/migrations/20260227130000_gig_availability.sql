-- Gig availability: crew-members kan markere om de kan eller ikke per gig
-- Kjøres manuelt i Supabase SQL Editor

-- 1. Availability-tabell
CREATE TABLE IF NOT EXISTS gig_availability (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gig_id     uuid NOT NULL REFERENCES gigs(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status     text NOT NULL DEFAULT 'pending',  -- 'pending', 'available', 'unavailable'
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (gig_id, user_id)
);

-- 2. Legg til user_id på gig_crew for kobling til auth-brukere
ALTER TABLE gig_crew ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES auth.users(id);

-- 3. RLS
ALTER TABLE gig_availability ENABLE ROW LEVEL SECURITY;

-- Alle autentiserte brukere kan lese availability
CREATE POLICY "Authenticated users can read gig_availability"
  ON gig_availability FOR SELECT
  TO authenticated
  USING (true);

-- Brukere kan sette sin egen availability
CREATE POLICY "Users can insert own availability"
  ON gig_availability FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own availability"
  ON gig_availability FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
