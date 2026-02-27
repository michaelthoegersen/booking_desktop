-- company_members: junction table for multi-company support
-- Each user can belong to multiple companies with a specific role.

CREATE TABLE IF NOT EXISTS company_members (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  role       text NOT NULL DEFAULT 'bruker',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, company_id)
);

-- Backfill from existing profiles that have a company_id
INSERT INTO company_members (user_id, company_id, role)
SELECT id, company_id, COALESCE(role, 'bruker')
FROM profiles
WHERE company_id IS NOT NULL
ON CONFLICT (user_id, company_id) DO NOTHING;

-- RLS
ALTER TABLE company_members ENABLE ROW LEVEL SECURITY;

-- Users can read their own memberships
CREATE POLICY "Users can read own memberships"
  ON company_members FOR SELECT
  USING (auth.uid() = user_id);

-- Users with admin/management role can manage members in their companies
CREATE POLICY "Admins can manage company members"
  ON company_members FOR ALL
  USING (
    company_id IN (
      SELECT cm.company_id FROM company_members cm
      WHERE cm.user_id = auth.uid()
        AND cm.role IN ('admin', 'management')
    )
  );

-- Service role can do everything (for edge functions)
CREATE POLICY "Service role full access"
  ON company_members FOR ALL
  USING (auth.role() = 'service_role');
