-- gigs_type_check tillot ikke 'other', så aktiviteter av typen "Annet" ble
-- avvist av databasen selv om UI-et tilbyr typen. Constrainten er laget
-- manuelt i Supabase og finnes ikke i noen migrasjon, så vi vet ikke hvilke
-- verdier den tillot.
--
-- Bygger den derfor på nytt fra verdiene som faktisk er i bruk, pluss de fire
-- typene appen kjenner. Da kan ingen eksisterende rad bli ugyldig.
DO $$
DECLARE
  vals TEXT;
BEGIN
  SELECT string_agg(DISTINCT quote_literal(t), ', ')
    INTO vals
  FROM (
    SELECT type AS t FROM gigs WHERE type IS NOT NULL
    UNION
    SELECT unnest(ARRAY['gig', 'rehearsal', 'meeting', 'other'])
  ) s;

  EXECUTE 'ALTER TABLE gigs DROP CONSTRAINT IF EXISTS gigs_type_check';
  EXECUTE format(
    'ALTER TABLE gigs ADD CONSTRAINT gigs_type_check CHECK (type IN (%s))',
    vals);
END $$;
