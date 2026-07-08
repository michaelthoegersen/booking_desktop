-- Per-company labels for the 3 crew role slots (drummers/dancers/others).
-- Default values keep the original Complete Drums labels — other companies
-- can override in Settings (e.g. "Musikere", "Teknikere", "Andre").
ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS role_labels jsonb
  NOT NULL DEFAULT '{"role1":"Trommeslagere","role2":"Dansere","role3":"Andre"}'::jsonb;
