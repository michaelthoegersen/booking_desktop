-- Endre tidsplan-kolonner fra TIME til TEXT
-- Tillater fritekst i tidsplanfeltene

ALTER TABLE gigs
  ALTER COLUMN meeting_time     SET DATA TYPE text,
  ALTER COLUMN get_in_time      SET DATA TYPE text,
  ALTER COLUMN rehearsal_time   SET DATA TYPE text,
  ALTER COLUMN performance_time SET DATA TYPE text,
  ALTER COLUMN get_out_time     SET DATA TYPE text;
