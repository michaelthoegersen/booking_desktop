-- ============================================================
-- Dropbox integration: tokens + shared folders
-- ============================================================

CREATE TABLE IF NOT EXISTS dropbox_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  access_token text NOT NULL,
  refresh_token text NOT NULL,
  expires_at timestamptz NOT NULL,
  account_display_name text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(company_id)
);

CREATE TABLE IF NOT EXISTS dropbox_shared_folders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  dropbox_path text NOT NULL,
  display_name text NOT NULL,
  sort_order int DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  UNIQUE(company_id, dropbox_path)
);

-- RLS
ALTER TABLE dropbox_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE dropbox_shared_folders ENABLE ROW LEVEL SECURITY;

-- Tokens: kun admin
CREATE POLICY "admin_manage_dropbox_tokens" ON dropbox_tokens FOR ALL
  USING (EXISTS (
    SELECT 1 FROM company_members cm
    WHERE cm.company_id = dropbox_tokens.company_id
      AND cm.user_id = auth.uid() AND cm.role IN ('admin', 'management')
  ));

-- Shared folders: alle i selskapet kan lese
CREATE POLICY "members_view_shared_folders" ON dropbox_shared_folders FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM company_members cm
    WHERE cm.company_id = dropbox_shared_folders.company_id
      AND cm.user_id = auth.uid()
  ));

-- Shared folders: admin kan skrive
CREATE POLICY "admin_manage_shared_folders" ON dropbox_shared_folders FOR ALL
  USING (EXISTS (
    SELECT 1 FROM company_members cm
    WHERE cm.company_id = dropbox_shared_folders.company_id
      AND cm.user_id = auth.uid() AND cm.role IN ('admin', 'management')
  ));
