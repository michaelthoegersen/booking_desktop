CREATE TABLE IF NOT EXISTS offer_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  offer_id uuid NOT NULL REFERENCES offers(id) ON DELETE CASCADE,
  version int NOT NULL,
  payload jsonb NOT NULL,
  status text,
  total_excl_vat numeric,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  note text
);

CREATE INDEX idx_offer_versions_offer_id ON offer_versions(offer_id);

ALTER TABLE offer_versions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Auth full access offer_versions"
  ON offer_versions FOR ALL TO authenticated USING (true) WITH CHECK (true);

ALTER TABLE offers ADD COLUMN IF NOT EXISTS version int NOT NULL DEFAULT 1;
