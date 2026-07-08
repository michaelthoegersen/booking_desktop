-- Add payment tracking to expenses
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS paid_at timestamptz;
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS paid_by uuid REFERENCES auth.users(id);

-- Add bank account number to profiles so crew can receive payments
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS account_number text;
