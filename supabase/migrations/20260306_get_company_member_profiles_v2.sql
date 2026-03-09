-- Extend get_company_member_profiles to return full profile data
-- (phone, email, avatar_url) so callers don't need a second query
-- on profiles (which is blocked by RLS for non-admin users).
DROP FUNCTION IF EXISTS get_company_member_profiles(uuid);
CREATE OR REPLACE FUNCTION get_company_member_profiles(p_company_id uuid)
RETURNS TABLE (id uuid, name text, role text, phone text, email text, avatar_url text)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT p.id, p.name, cm.role, p.phone, p.email, p.avatar_url
  FROM profiles p
  INNER JOIN company_members cm ON cm.user_id = p.id
  WHERE cm.company_id = p_company_id
  ORDER BY p.name;
$$;
