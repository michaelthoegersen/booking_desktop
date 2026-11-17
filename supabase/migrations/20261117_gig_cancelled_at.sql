-- ============================================================
-- Når ble aktiviteten avlyst?
--
-- Stian: «Avlyst Aktivitet - Arkiveres automatisk etter 2 uker.»
--
-- En avlyst gig skal bli stående synlig en stund så alle ser at den er
-- avlyst, og så forsvinne av seg selv. Uten et tidspunkt å regne fra finnes
-- det ingen måte å vite når de to ukene er gått.
--
-- Eksisterende avlyste rader får updated_at som utgangspunkt — nærmeste vi
-- kommer sannheten — så de ikke blir arkivert i samme øyeblikk.
-- ============================================================

ALTER TABLE gigs
  ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;

COMMENT ON COLUMN gigs.cancelled_at IS
  'Når aktiviteten ble avlyst. Arkiveres automatisk to uker etter.';

UPDATE gigs
   SET cancelled_at = COALESCE(updated_at, now())
 WHERE status = 'cancelled'
   AND cancelled_at IS NULL;
