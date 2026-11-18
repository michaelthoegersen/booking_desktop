-- Testtilbud kunne ikke lagres: «new row violates row-level security policy
-- "gigs_tests_owner_only"».
--
-- Policyen fra 20261030 lot bare plattformeieren (michael@nttas.com) SETTE
-- is_test, mens USING-delen allerede sa at raden bare er synlig for den som
-- lagde den. Testtilbud-bryteren vises for alle administratorer, så for alle
-- andre enn den ene e-postadressen var bryteren en knapp som alltid feilet.
--
-- Nå kan du sette flagget på dine egne rader. USING er uendret: en testrad er
-- fortsatt bare synlig for den som lagde den.
--
-- Avveiningen: en bruker kan skjule sin egen gig for kollegene ved å merke
-- den som test. Det er rader vedkommende selv har opprettet og like gjerne
-- kunne slettet, så det gir ingen ny tilgang.

DROP POLICY IF EXISTS "gigs_tests_owner_only" ON gigs;
CREATE POLICY "gigs_tests_owner_only"
  ON gigs AS RESTRICTIVE FOR ALL TO authenticated
  USING (is_test = false OR created_by = auth.uid())
  WITH CHECK (is_test = false OR created_by = auth.uid());

DROP POLICY IF EXISTS "gig_offers_tests_owner_only" ON gig_offers;
CREATE POLICY "gig_offers_tests_owner_only"
  ON gig_offers AS RESTRICTIVE FOR ALL TO authenticated
  USING (is_test = false OR created_by = auth.uid())
  WITH CHECK (is_test = false OR created_by = auth.uid());
