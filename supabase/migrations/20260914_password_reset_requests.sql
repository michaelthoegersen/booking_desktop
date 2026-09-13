-- ============================================================
-- GLEMT PASSORD — forespørsel til administrator
-- Medlemmet ber om nytt passord fra innloggingssiden. Raden opprettes av
-- edge-funksjonen request-password-reset med service-nøkkel, så tabellen er
-- ikke åpen for anonyme skrivinger.
-- ============================================================

CREATE TABLE IF NOT EXISTS password_reset_requests (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email        TEXT NOT NULL,
  user_id      UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id   UUID REFERENCES companies(id) ON DELETE CASCADE,
  status       TEXT NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending', 'handled', 'dismissed')),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  handled_at   TIMESTAMPTZ,
  handled_by   UUID REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_prr_company_status
  ON password_reset_requests(company_id, status);

ALTER TABLE password_reset_requests ENABLE ROW LEVEL SECURITY;

-- Kun administratorer i selskapet ser og behandler forespørslene.
-- Ingen INSERT-policy: rader opprettes utelukkende av edge-funksjonen med
-- service-nøkkel, slik at en anonym besøkende ikke kan fylle tabellen direkte.
DROP POLICY IF EXISTS "prr_select_admin" ON password_reset_requests;
CREATE POLICY "prr_select_admin"
  ON password_reset_requests FOR SELECT TO authenticated
  USING (is_admin_in(company_id));

DROP POLICY IF EXISTS "prr_update_admin" ON password_reset_requests;
CREATE POLICY "prr_update_admin"
  ON password_reset_requests FOR UPDATE TO authenticated
  USING (is_admin_in(company_id));
