-- "Tar med +1" på sosiale aktiviteter (julebord, sommerfest ...).
-- Slås på per aktivitet i stedet for å gjette ut fra tittelen, så det virker
-- uansett hva arrangementet heter.
ALTER TABLE gigs
  ADD COLUMN IF NOT EXISTS allow_plus_one BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE gig_availability
  ADD COLUMN IF NOT EXISTS plus_one BOOLEAN NOT NULL DEFAULT false;
