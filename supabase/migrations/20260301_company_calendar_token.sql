-- Add calendar_token to companies for iCal subscription authentication
ALTER TABLE companies ADD COLUMN IF NOT EXISTS calendar_token text;
