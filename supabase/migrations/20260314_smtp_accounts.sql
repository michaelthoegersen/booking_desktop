-- SMTP accounts for sending email via Domeneshop or other providers
CREATE TABLE IF NOT EXISTS smtp_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  email text NOT NULL,
  display_name text NOT NULL DEFAULT '',
  smtp_host text NOT NULL DEFAULT 'smtp.domeneshop.no',
  smtp_port int NOT NULL DEFAULT 587,
  password text NOT NULL,
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- RLS
ALTER TABLE smtp_accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own SMTP accounts"
  ON smtp_accounts FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
