-- ============================================================
-- GIG_HIRE_MARKS — medlemmet må nå selv kunne markere sin egen rad
--
-- Tabellen ble laget for Gigghyrer i webappen, der kun administratorer
-- jobber, så policyene krever is_admin_in(). Mobilappen lar medlemmet
-- markere sin EGEN hyre som fakturert, og bookinghonorar for en gigg man
-- ikke sto på laget på har ingen gig_lineup-rad — statusen havner her.
-- Uten disse policyene traff skrivingen null rader, stille.
--
-- Begrenset til egne rader: user_id = auth.uid().
-- ============================================================

DROP POLICY IF EXISTS "ghm_select_own" ON gig_hire_marks;
CREATE POLICY "ghm_select_own"
  ON gig_hire_marks FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "ghm_insert_own" ON gig_hire_marks;
CREATE POLICY "ghm_insert_own"
  ON gig_hire_marks FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "ghm_update_own" ON gig_hire_marks;
CREATE POLICY "ghm_update_own"
  ON gig_hire_marks FOR UPDATE TO authenticated
  USING (user_id = auth.uid());
