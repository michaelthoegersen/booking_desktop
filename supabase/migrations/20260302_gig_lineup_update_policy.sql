-- Allow crew members to update their own lineup rows (for crew_invoiced_at)
CREATE POLICY "user_update_own_lineup" ON gig_lineup FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Allow admin/leaders to update any lineup row (for crew_paid_at)
CREATE POLICY "leader_update_lineup" ON gig_lineup FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM profiles p JOIN gigs g ON g.company_id = p.company_id
    WHERE p.id = auth.uid() AND g.id = gig_id
      AND p.role IN ('admin','gruppeleder_skarp','gruppeleder_bass')
  ));
