-- Company bank account connections (PSD2 via Enable Banking)
CREATE TABLE IF NOT EXISTS company_bank_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  session_id text,                    -- Enable Banking session ID
  account_external_id text,           -- Enable Banking account UID
  bank_name text DEFAULT 'DNB',
  account_name text,
  iban text,
  currency text DEFAULT 'NOK',
  balance numeric,
  balance_updated_at timestamptz,
  session_valid_until timestamptz,    -- PSD2 consent expiry
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(company_id, account_external_id)
);

ALTER TABLE company_bank_accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "company_bank_accounts_select"
  ON company_bank_accounts FOR SELECT TO authenticated
  USING (is_admin_in(company_id));

CREATE POLICY "company_bank_accounts_insert"
  ON company_bank_accounts FOR INSERT TO authenticated
  WITH CHECK (is_admin_in(company_id));

CREATE POLICY "company_bank_accounts_update"
  ON company_bank_accounts FOR UPDATE TO authenticated
  USING (is_admin_in(company_id));

CREATE POLICY "company_bank_accounts_delete"
  ON company_bank_accounts FOR DELETE TO authenticated
  USING (is_admin_in(company_id));
