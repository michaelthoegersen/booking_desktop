-- ============================================================
-- EXPENSES TABLE — crew expense receipts
-- ============================================================

CREATE TABLE IF NOT EXISTS expenses (
  id                   UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id           UUID NOT NULL REFERENCES companies(id),
  user_id              UUID NOT NULL REFERENCES auth.users(id),
  amount               NUMERIC(10,2) NOT NULL,
  vendor               TEXT,
  receipt_date         DATE,
  description          TEXT,
  receipt_url          TEXT,
  gig_id               UUID REFERENCES gigs(id),
  status               TEXT NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending','approved','rejected')),
  approved_by          UUID REFERENCES auth.users(id),
  approved_at          TIMESTAMPTZ,
  rejection_reason     TEXT,
  reiseregning_sent_at TIMESTAMPTZ,
  created_at           TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_expenses_company_status ON expenses(company_id, status);
CREATE INDEX IF NOT EXISTS idx_expenses_gig ON expenses(gig_id);
CREATE INDEX IF NOT EXISTS idx_expenses_user ON expenses(user_id);

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE expenses;

-- RLS
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;

-- Users can see their own expenses
CREATE POLICY "Users can view own expenses"
  ON expenses FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- Admins can see all expenses in their company
CREATE POLICY "Admins can view company expenses"
  ON expenses FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
        AND profiles.role = 'admin'
        AND profiles.company_id = expenses.company_id
    )
  );

-- Users can insert their own expenses
CREATE POLICY "Users can insert own expenses"
  ON expenses FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Admins can update expenses in their company (approve/reject)
CREATE POLICY "Admins can update company expenses"
  ON expenses FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
        AND profiles.role = 'admin'
        AND profiles.company_id = expenses.company_id
    )
  );

-- ============================================================
-- STORAGE BUCKET — expense-receipts
-- ============================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('expense-receipts', 'expense-receipts', false, 10485760)
ON CONFLICT (id) DO NOTHING;

-- Users can upload to their own folder
CREATE POLICY "Users upload own receipts"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'expense-receipts'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Users can read their own receipts
CREATE POLICY "Users read own receipts"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'expense-receipts'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Admins can read all receipts
CREATE POLICY "Admins read all receipts"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'expense-receipts'
    AND EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
        AND profiles.role = 'admin'
    )
  );
