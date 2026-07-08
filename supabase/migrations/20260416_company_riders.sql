-- Per-company rider PDFs (replaces hardcoded Dropbox paths)
CREATE TABLE IF NOT EXISTS company_riders (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name        text NOT NULL,           -- display name, e.g. "CompleteShow Teknisk Rider"
  file_path   text NOT NULL,           -- storage path in 'riders' bucket
  file_size   integer,
  show_match  text,                    -- optional: auto-attach when show name contains this
  always_attach boolean DEFAULT false, -- e.g. hospitality rider
  active      boolean DEFAULT true,
  sort_order  integer DEFAULT 0,
  created_at  timestamptz DEFAULT now()
);

ALTER TABLE company_riders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "company_riders_select" ON company_riders FOR SELECT TO authenticated
  USING (company_id IN (SELECT my_company_ids()));
CREATE POLICY "company_riders_insert" ON company_riders FOR INSERT TO authenticated
  WITH CHECK (is_admin_in(company_id));
CREATE POLICY "company_riders_update" ON company_riders FOR UPDATE TO authenticated
  USING (is_admin_in(company_id));
CREATE POLICY "company_riders_delete" ON company_riders FOR DELETE TO authenticated
  USING (is_admin_in(company_id));

-- Storage bucket for rider PDFs
INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('riders', 'riders', false, 20971520)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "riders_upload" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'riders');
CREATE POLICY "riders_read" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'riders');
CREATE POLICY "riders_delete" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'riders');
