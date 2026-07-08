-- Add language preference to profiles (default 'no' for Norwegian)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS language TEXT NOT NULL DEFAULT 'no';
COMMENT ON COLUMN profiles.language IS 'ISO 639-1: no, en, sv';
