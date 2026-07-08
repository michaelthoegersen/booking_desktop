-- Add company isolation to waiting_list
ALTER TABLE waiting_list ADD COLUMN IF NOT EXISTS owner_company_id uuid REFERENCES companies(id);

-- Set existing entries to CSS
UPDATE waiting_list
SET owner_company_id = 'd3695282-4eb2-4883-8580-581b0f261ae3'
WHERE owner_company_id IS NULL;

-- Replace open policy with company-scoped one
DROP POLICY IF EXISTS "waiting_all" ON waiting_list;
DROP POLICY IF EXISTS "Authenticated manage waiting list" ON waiting_list;

CREATE POLICY "waiting_list_select" ON waiting_list FOR SELECT TO authenticated
  USING (owner_company_id IN (SELECT my_company_ids()));
CREATE POLICY "waiting_list_insert" ON waiting_list FOR INSERT TO authenticated
  WITH CHECK (owner_company_id IN (SELECT my_company_ids()));
CREATE POLICY "waiting_list_update" ON waiting_list FOR UPDATE TO authenticated
  USING (owner_company_id IN (SELECT my_company_ids()));
CREATE POLICY "waiting_list_delete" ON waiting_list FOR DELETE TO authenticated
  USING (owner_company_id IN (SELECT my_company_ids()));
