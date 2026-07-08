-- Fix companies UPDATE RLS: allow admins to update companies they OWN
-- (via owner_company_id), not just companies they are members of.
DROP POLICY IF EXISTS "companies_update" ON companies;

CREATE POLICY "companies_update"
  ON companies FOR UPDATE TO authenticated
  USING (
    -- Admin in this company itself (e.g. Complete Drums settings)
    is_admin_in(id)
    OR
    -- Admin in the owning company (e.g. CSS editing their customers)
    (owner_company_id IS NOT NULL AND is_admin_in(owner_company_id))
  );
