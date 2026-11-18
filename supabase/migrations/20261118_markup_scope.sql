-- Påslag: én avhuking per ting påslaget kan ligge på, i stedet for én
-- «markup_on_all».
--
-- Bakgrunnen: markup_on_all ble lest ulikt tre steder. Webappen tok den som
-- «påslag på alt», mobilappen kalte den «påslag kun på hyrer», og
-- kontrakt-PDF-en hadde sin egen gren som var snudd igjen. Samme tilbud fikk
-- derfor ulik fordeling mellom prislinjene avhengig av hvor det ble åpnet.
--
-- Nå: påslag ligger alltid på utøverhyrene. Transport og ekstrakostnad har
-- hver sin avhuking, begge av som standard.
--
-- Eksisterende tilbud settes til av/av, altså påslag kun på hyrer. Det er
-- det vanlige oppsettet, og det er den eneste tolkningen som er entydig —
-- for rader der markup_on_all var true kan vi ikke vite hvilken av de to
-- motsatte betydningene som var ment. Signerte avtaler er upåvirket: de
-- ligger arkivert som PDF.
--
-- markup_on_all beholdes i tabellen, men skrives ikke lenger.

ALTER TABLE gig_offers
  ADD COLUMN IF NOT EXISTS markup_on_transport BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE gig_offers
  ADD COLUMN IF NOT EXISTS markup_on_extras BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN gig_offers.markup_on_transport IS
  'Påslag regnes også av transport. Av som standard.';
COMMENT ON COLUMN gig_offers.markup_on_extras IS
  'Påslag regnes også av ekstrakostnadene. Av som standard. Påslaget tilfaller Complete, uansett hvem som mottar selve ekstrakostnaden.';
COMMENT ON COLUMN gig_offers.markup_on_all IS
  'UTGÅTT. Ble lest ulikt i web, mobil og PDF. Erstattet av markup_on_transport og markup_on_extras.';
