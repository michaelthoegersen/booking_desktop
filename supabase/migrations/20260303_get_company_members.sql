-- Returns user profiles for members of a given company.
-- Uses SECURITY DEFINER to bypass company_members RLS.
CREATE OR REPLACE FUNCTION get_company_member_profiles(p_company_id uuid)
RETURNS TABLE (id uuid, name text, role text)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT p.id, p.name, cm.role
  FROM profiles p
  INNER JOIN company_members cm ON cm.user_id = p.id
  WHERE cm.company_id = p_company_id
  ORDER BY p.name;
$$;
