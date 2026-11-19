-- Siste to kolonnene tilbudsraden manglet.
--
-- Tilbudet speiler kundefeltene fra gigen, og overskrift + sluttkunde var
-- med i det som skrives, men aldri lagt på tabellen. Nå er hele payloaden
-- dekket: alle nøkler appen skriver til gig_offers finnes som kolonner.

ALTER TABLE gig_offers ADD COLUMN IF NOT EXISTS title TEXT;
ALTER TABLE gig_offers ADD COLUMN IF NOT EXISTS end_customer TEXT;

COMMENT ON COLUMN gig_offers.title IS 'Overskrift på oppdraget, speilet fra gigs.title.';
COMMENT ON COLUMN gig_offers.end_customer IS 'Sluttkunde når bestilleren er et mellomledd, speilet fra gigs.end_customer.';
