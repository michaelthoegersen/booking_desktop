-- ============================================================
-- Sluttkunde på aktiviteter
--
-- Stian: «Ønsker meg et valgfritt felt for hvem sluttkunden er, som gjerne
-- ligger rett under den nevnte overskriften. Ref «Nammo» og
-- «Kongsberggruppen».»
--
-- Kunden vi fakturerer (customer_firma) er ofte et byrå eller en arrangør,
-- mens sluttkunden er den showet faktisk er for. Overskriften gjenbruker
-- gigs.title, som allerede fantes for «Annet»-aktiviteter.
-- ============================================================

ALTER TABLE gigs
  ADD COLUMN IF NOT EXISTS end_customer TEXT;

COMMENT ON COLUMN gigs.end_customer IS
  'Sluttkunde: hvem showet er for, når det er en annen enn den vi fakturerer.';
