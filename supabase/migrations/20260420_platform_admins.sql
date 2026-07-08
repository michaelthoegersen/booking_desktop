-- ============================================================
-- PLATFORM OWNER
-- Only a single hardcoded user (michael@nttas.com) can create
-- new tenant companies (companies with owner_company_id IS NULL).
--
-- No role/flag on profiles — the allowed identity is baked into
-- a SECURITY DEFINER function so the check cannot be bypassed
-- by setting a flag on another user.
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_platform_owner()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = auth.uid()
      AND lower(email) = 'michael@nttas.com'
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_platform_owner() TO authenticated;

-- Tighten companies INSERT: tenant companies require platform owner.
DROP POLICY IF EXISTS "companies_insert" ON companies;
CREATE POLICY "companies_insert"
  ON companies FOR INSERT TO authenticated
  WITH CHECK (
    -- Customer companies owned by a tenant: user must be admin in that tenant.
    (owner_company_id IS NOT NULL AND is_admin_in(owner_company_id))
    OR
    -- Tenant companies (no owner): only the platform owner.
    (owner_company_id IS NULL AND is_platform_owner())
  );

-- Let the platform owner SELECT all companies (for the admin UI list).
DROP POLICY IF EXISTS "companies_select_platform_admin" ON companies;
DROP POLICY IF EXISTS "companies_select_platform_owner" ON companies;
CREATE POLICY "companies_select_platform_owner"
  ON companies FOR SELECT TO authenticated
  USING (is_platform_owner());

-- Let the platform owner UPDATE/DELETE any company.
DROP POLICY IF EXISTS "companies_update_platform_admin" ON companies;
DROP POLICY IF EXISTS "companies_update_platform_owner" ON companies;
CREATE POLICY "companies_update_platform_owner"
  ON companies FOR UPDATE TO authenticated
  USING (is_platform_owner());

DROP POLICY IF EXISTS "companies_delete_platform_admin" ON companies;
DROP POLICY IF EXISTS "companies_delete_platform_owner" ON companies;
CREATE POLICY "companies_delete_platform_owner"
  ON companies FOR DELETE TO authenticated
  USING (is_platform_owner());
