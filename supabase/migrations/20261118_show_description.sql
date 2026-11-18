-- Showbeskrivelse per show, i stedet for én felles for alle showene.
--
-- Beskrivelsen havner under sitt eget show i kontrakten, slik den felles
-- beskrivelsen gjør i dag. Den felles beskrivelsen (gig_offers/gigs.show_desc)
-- blir stående og brukes der et show ikke har sin egen, så eksisterende
-- avtaler leser nøyaktig som før.
--
-- To tabeller fordi showene finnes to steder: gig_offer_shows er det du
-- redigerer på tilbudet, gig_shows er det som ligger på hver gig og som
-- kontrakten leses fra.

ALTER TABLE gig_shows
  ADD COLUMN IF NOT EXISTS description TEXT;

ALTER TABLE gig_offer_shows
  ADD COLUMN IF NOT EXISTS description TEXT;

COMMENT ON COLUMN gig_shows.description IS
  'Hva dette showet går ut på. Vises under showet i kontrakten. Tom = bruk tilbudets felles showbeskrivelse.';
COMMENT ON COLUMN gig_offer_shows.description IS
  'Hva dette showet går ut på. Kopieres til gig_shows ved lagring.';
