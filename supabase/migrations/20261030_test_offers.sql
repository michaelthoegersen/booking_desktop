-- ============================================================
-- Testtilbud — synlige kun for den som lagde dem
-- ============================================================
-- Et testtilbud skal ikke nå noen andre: ikke i lista, ikke i kalenderen,
-- ikke som varsel. Derfor håndheves det i databasen og ikke i appen — da
-- gjelder regelen hver eneste spørring i både webapp og mobilapp, også de
-- som skrives senere, og den kan ikke glemmes bort på ett kallsted.

ALTER TABLE gigs
  ADD COLUMN IF NOT EXISTS is_test boolean NOT NULL DEFAULT false;
ALTER TABLE gig_offers
  ADD COLUMN IF NOT EXISTS is_test boolean NOT NULL DEFAULT false;

-- RESTRICTIVE-policyer legges PÅ TOPPEN av de eksisterende med AND. De kan
-- bare ta bort tilgang, aldri gi — så ingenting som virker i dag kan bli
-- åpnere av dette. Vanlige rader har is_test = false og er upåvirket.
--
--   USING      styrer hvem som SER raden      → kun den som lagde den
--   WITH CHECK styrer hvem som kan SETTE flagget → kun plattformeieren
--
-- is_platform_owner() finnes fra før (20260420_platform_admins.sql) og er
-- bundet til én e-postadresse i en SECURITY DEFINER-funksjon, så flagget kan
-- ikke settes av noen andre ved å endre en kolonne på seg selv.

DROP POLICY IF EXISTS "gigs_tests_owner_only" ON gigs;
CREATE POLICY "gigs_tests_owner_only"
  ON gigs AS RESTRICTIVE FOR ALL TO authenticated
  USING (is_test = false OR created_by = auth.uid())
  WITH CHECK (is_test = false OR is_platform_owner());

DROP POLICY IF EXISTS "gig_offers_tests_owner_only" ON gig_offers;
CREATE POLICY "gig_offers_tests_owner_only"
  ON gig_offers AS RESTRICTIVE FOR ALL TO authenticated
  USING (is_test = false OR created_by = auth.uid())
  WITH CHECK (is_test = false OR is_platform_owner());

CREATE INDEX IF NOT EXISTS idx_gigs_is_test ON gigs(is_test) WHERE is_test;
