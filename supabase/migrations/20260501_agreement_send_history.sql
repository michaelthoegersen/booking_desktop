-- ============================================================
-- Track every send of an intensjonsavtale: timestamp + recipients
-- ============================================================

CREATE TABLE IF NOT EXISTS agreement_token_sends (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  token_id    UUID NOT NULL REFERENCES agreement_tokens(id) ON DELETE CASCADE,
  recipients  TEXT[] NOT NULL,
  sent_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_by     UUID REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_agreement_token_sends_token
  ON agreement_token_sends(token_id);

ALTER TABLE agreement_token_sends ENABLE ROW LEVEL SECURITY;

CREATE POLICY "agreement_sends_admin_read"
  ON agreement_token_sends FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "agreement_sends_admin_insert"
  ON agreement_token_sends FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "agreement_sends_service_role"
  ON agreement_token_sends FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
