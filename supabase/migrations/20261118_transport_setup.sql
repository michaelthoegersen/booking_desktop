-- Transport-oppsettet på et tilbud: hvilke transportformer som er valgt,
-- om turen er tur/retur, hvor mange privatbiler som kjører og hva hver bil
-- frakter, samt antall hyrebildager.
--
-- Dette har aldri vært lagret. Tilbudet husket bare km og totalpris, så når
-- det ble åpnet igjen var oppsettet borte og måtte settes opp på nytt.
--
-- Form:
--   {
--     "modes": ["privatbil", "hyrebil"],
--     "return_trip": true,
--     "cars": [{"passengers": 2, "trailer": false, "heavy_load": true}],
--     "hyre_days": 2
--   }

ALTER TABLE gig_offers
  ADD COLUMN IF NOT EXISTS transport_setup JSONB;

COMMENT ON COLUMN gig_offers.transport_setup IS
  'Valgte transportformer, tur/retur, privatbiler med passasjerer/tilhenger/tung last, og antall hyrebildager.';
