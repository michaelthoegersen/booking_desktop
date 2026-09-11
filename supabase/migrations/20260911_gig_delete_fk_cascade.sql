-- Sletting av gig feilet:
--   update or delete on table "gigs" violates foreign key constraint
--   "gig_lineup_gig_id_fkey" on table "gig_lineup"
--
-- 20260301_gig_lineup.sql definerer gig_id med ON DELETE CASCADE, men den
-- brukte CREATE TABLE IF NOT EXISTS mot en tabell som allerede fantes, så
-- CASCADE ble aldri satt i databasen. Constrainten rettes opp her.
--
-- Ingen rader slettes av denne migrasjonen — kun FK-reglene endres.

-- 1. gig_lineup: lineup-rader hører til giggen og skal følge den. CASCADE er
--    det 20260301-migrasjonen alltid har ment.
ALTER TABLE gig_lineup DROP CONSTRAINT IF EXISTS gig_lineup_gig_id_fkey;
ALTER TABLE gig_lineup
  ADD CONSTRAINT gig_lineup_gig_id_fkey
  FOREIGN KEY (gig_id) REFERENCES gigs(id) ON DELETE CASCADE;

-- 2. expenses: utlegg/kvitteringer er regnskapsdata og skal IKKE slettes med
--    giggen. gig_id er nullable, så koblingen løsnes i stedet — utlegget blir
--    stående, bare uten gig-tilknytning.
ALTER TABLE expenses DROP CONSTRAINT IF EXISTS expenses_gig_id_fkey;
ALTER TABLE expenses
  ADD CONSTRAINT expenses_gig_id_fkey
  FOREIGN KEY (gig_id) REFERENCES gigs(id) ON DELETE SET NULL;
