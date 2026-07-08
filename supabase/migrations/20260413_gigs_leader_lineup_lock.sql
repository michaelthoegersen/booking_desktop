-- Allow group leaders (gruppeleder_skarp, gruppeleder_bass) to update
-- lineup lock fields on gigs, not just admins.

-- Helper: true if the user is a group leader in the given company
CREATE OR REPLACE FUNCTION public.is_leader_in(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM company_members
    WHERE user_id = auth.uid()
      AND company_id = p_company_id
      AND role IN ('gruppeleder_skarp', 'gruppeleder_bass')
  );
$$;

-- Drop the existing admin-only update policy and replace with one
-- that also allows group leaders to update gigs (for lineup locking).
DROP POLICY IF EXISTS "gigs_update" ON gigs;

CREATE POLICY "gigs_update"
  ON gigs FOR UPDATE TO authenticated
  USING (
    is_admin_in(company_id) OR is_leader_in(company_id)
  );
