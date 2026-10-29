-- ============================================================
-- Flere mulige datoer for én forespørsel
-- ============================================================
-- Kunden forespeiler f.eks. tre datoer. Hver dato blir en egen gig, slik at
-- medlemmene ser og kan holde av alle tre i kalenderen. De deler
-- date_option_group så appen kan vise at de hører sammen («Alternativ 2 av 3»).
--
-- date_option_state:
--   'pending'  uavklart alternativ. Skal IKKE telle i gigghyre eller
--              fakturering — datoen er ikke solgt ennå.
--   'chosen'   datoen kunden valgte. Oppfører seg som en helt vanlig gig.
--   'expired'  alternativet ble ikke noe av. Beholdes som dokumentasjon på
--              hva som faktisk ble tilbudt.
--   NULL       vanlig gig uten alternativer — alt som finnes fra før.

ALTER TABLE gigs
  ADD COLUMN IF NOT EXISTS date_option_group uuid,
  ADD COLUMN IF NOT EXISTS date_option_state text;

ALTER TABLE gigs DROP CONSTRAINT IF EXISTS gigs_date_option_state_check;
ALTER TABLE gigs ADD CONSTRAINT gigs_date_option_state_check
  CHECK (date_option_state IS NULL
         OR date_option_state IN ('pending', 'chosen', 'expired'));

-- En gig er enten et alternativ (gruppe OG tilstand) eller ikke (begge NULL).
ALTER TABLE gigs DROP CONSTRAINT IF EXISTS gigs_date_option_pair_check;
ALTER TABLE gigs ADD CONSTRAINT gigs_date_option_pair_check
  CHECK ((date_option_group IS NULL) = (date_option_state IS NULL));

CREATE INDEX IF NOT EXISTS idx_gigs_date_option_group
  ON gigs(date_option_group)
  WHERE date_option_group IS NOT NULL;

-- ── Kontrakten: kunden velger datoen når avtalen aksepteres ─────────────────
-- date_choice_group settes når intensjonsavtalen sendes for en gruppe
-- uavklarte datoer. Da krever accept-siden at kunden velger én dato, og
-- chosen_gig_id lagrer hvilken.
ALTER TABLE agreement_tokens
  ADD COLUMN IF NOT EXISTS date_choice_group uuid,
  ADD COLUMN IF NOT EXISTS chosen_gig_id uuid REFERENCES gigs(id) ON DELETE SET NULL;
