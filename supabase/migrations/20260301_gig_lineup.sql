-- Admin kan sette availability for alle (for øvelse auto-set)
CREATE POLICY "Admin can insert availability for others"
  ON gig_availability FOR INSERT
  TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = auth.uid()
      AND p.role = 'admin'
  ));

-- Seksjon på profil
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS section text;

-- Lineup-lås per seksjon på gigs
ALTER TABLE gigs ADD COLUMN IF NOT EXISTS lineup_locked_skarp boolean NOT NULL DEFAULT false;
ALTER TABLE gigs ADD COLUMN IF NOT EXISTS lineup_locked_bass boolean NOT NULL DEFAULT false;

-- Lineup-tabell
CREATE TABLE IF NOT EXISTS gig_lineup (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gig_id     uuid NOT NULL REFERENCES gigs(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  section    text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (gig_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_gig_lineup_gig ON gig_lineup(gig_id);

-- RLS
ALTER TABLE gig_lineup ENABLE ROW LEVEL SECURITY;

CREATE POLICY "read_lineup" ON gig_lineup FOR SELECT TO authenticated USING (true);

CREATE POLICY "leader_insert_lineup" ON gig_lineup FOR INSERT TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM profiles p JOIN gigs g ON g.company_id = p.company_id
    WHERE p.id = auth.uid() AND g.id = gig_id
      AND p.role IN ('admin','gruppeleder_skarp','gruppeleder_bass')
  ));

CREATE POLICY "leader_delete_lineup" ON gig_lineup FOR DELETE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM profiles p JOIN gigs g ON g.company_id = p.company_id
    WHERE p.id = auth.uid() AND g.id = gig_id
      AND p.role IN ('admin','gruppeleder_skarp','gruppeleder_bass')
  ));
