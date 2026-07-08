-- Allow authenticated users to insert companies (customers).
-- The owner_company_id must match a company where the user is admin.
CREATE POLICY "companies_insert"
  ON companies FOR INSERT TO authenticated
  WITH CHECK (
    -- Allow if owner_company_id is set and user is admin in that company
    (owner_company_id IS NOT NULL AND is_admin_in(owner_company_id))
    OR
    -- Allow if no owner (self-registration / system companies)
    owner_company_id IS NULL
  );

-- Also allow deleting owned companies
DROP POLICY IF EXISTS "companies_delete" ON companies;
CREATE POLICY "companies_delete"
  ON companies FOR DELETE TO authenticated
  USING (
    is_admin_in(id)
    OR
    (owner_company_id IS NOT NULL AND is_admin_in(owner_company_id))
  );
