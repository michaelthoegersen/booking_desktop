-- Microsoft OAuth tokens (delegated permissions, per company)
CREATE TABLE IF NOT EXISTS microsoft_oauth_tokens (
  company_id uuid PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
  email      text NOT NULL DEFAULT '',
  refresh_token text NOT NULL DEFAULT '',
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE microsoft_oauth_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Auth full access"
  ON microsoft_oauth_tokens
  FOR ALL TO authenticated
  USING (true)
  WITH CHECK (true);
