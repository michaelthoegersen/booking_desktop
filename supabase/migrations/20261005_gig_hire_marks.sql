-- ============================================================
-- GIGGHYRER — fakturert/betalt for hyre uten lineup-rad
--
-- Fakturert- og betalt-datoene har hittil ligget på gig_lineup. Det virker
-- for den som faktisk sto på laget, men to hyretyper har ingen lineup-rad:
--
--   • 'booking' — bookinghonoraret på gigger der han ikke spilte selv
--   • 'ekstra'  — en ekstrakostnad tildelt et medlem som ikke var på laget
--
-- For disse traff oppdateringen null rader, og knappen gjorde ingenting uten
-- å si fra. Denne tabellen holder de to datoene for nettopp slike rader.
-- gig_lineup er uendret og er fortsatt fasit for alle som sto på laget.
-- ============================================================

CREATE TABLE IF NOT EXISTS gig_hire_marks (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id       UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  gig_id           UUID NOT NULL REFERENCES gigs(id) ON DELETE CASCADE,
  user_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- Hvilken hyretype raden gjelder, slik at bookinghonorar og ekstra kan
  -- markeres hver for seg på samme gig og samme person.
  section          TEXT NOT NULL,
  crew_invoiced_at TIMESTAMPTZ,
  crew_paid_at     TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (gig_id, user_id, section)
);

CREATE INDEX IF NOT EXISTS idx_ghm_company_gig
  ON gig_hire_marks(company_id, gig_id);

ALTER TABLE gig_hire_marks ENABLE ROW LEVEL SECURITY;

-- Samme krets som resten av Gigghyrer: administratorer i selskapet.
DROP POLICY IF EXISTS "ghm_select_admin" ON gig_hire_marks;
CREATE POLICY "ghm_select_admin"
  ON gig_hire_marks FOR SELECT TO authenticated
  USING (is_admin_in(company_id));

DROP POLICY IF EXISTS "ghm_insert_admin" ON gig_hire_marks;
CREATE POLICY "ghm_insert_admin"
  ON gig_hire_marks FOR INSERT TO authenticated
  WITH CHECK (is_admin_in(company_id));

DROP POLICY IF EXISTS "ghm_update_admin" ON gig_hire_marks;
CREATE POLICY "ghm_update_admin"
  ON gig_hire_marks FOR UPDATE TO authenticated
  USING (is_admin_in(company_id));

DROP POLICY IF EXISTS "ghm_delete_admin" ON gig_hire_marks;
CREATE POLICY "ghm_delete_admin"
  ON gig_hire_marks FOR DELETE TO authenticated
  USING (is_admin_in(company_id));
