-- ============================================================
-- Testgigger: kontrakt og chat skjules også for alle andre
-- ============================================================
-- Selve gigen er allerede usynlig for andre (20261030_test_offers.sql), men
-- avtalen og meldingene har egne flater: avtale-badgen i menyen, lista over
-- tilbud, og chat-fanen. De leser sine egne tabeller og ville ellers vist at
-- noe finnes, selv om gigen bak ikke kan åpnes.
--
-- Sending skal fortsatt virke for eieren — det er hele poenget med å teste —
-- så dette skjuler for andre, det blokkerer ingenting for den som eier testen.

-- Er dette en gig som tilhører en ANNENS test? Da skal raden skjules.
-- SECURITY DEFINER fordi policyen ellers leser gigs med RLS på, og da får vi
-- den rekursive stillheten som RLS V2 ble skrevet for å bli kvitt.
CREATE OR REPLACE FUNCTION public.gig_is_foreign_test(p_gig_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM gigs
    WHERE id = p_gig_id
      AND is_test
      AND created_by IS DISTINCT FROM auth.uid()
  );
$$;

GRANT EXECUTE ON FUNCTION public.gig_is_foreign_test(uuid) TO authenticated;

-- RESTRICTIVE: kan bare ta bort tilgang, aldri gi. Rader uten gig_id, og
-- rader på vanlige gigger, er upåvirket.
DROP POLICY IF EXISTS "agreement_tokens_hide_foreign_tests" ON agreement_tokens;
CREATE POLICY "agreement_tokens_hide_foreign_tests"
  ON agreement_tokens AS RESTRICTIVE FOR ALL TO authenticated
  USING (NOT gig_is_foreign_test(gig_id));

DROP POLICY IF EXISTS "gig_messages_hide_foreign_tests" ON gig_messages;
CREATE POLICY "gig_messages_hide_foreign_tests"
  ON gig_messages AS RESTRICTIVE FOR ALL TO authenticated
  USING (NOT gig_is_foreign_test(gig_id));
