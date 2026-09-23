-- Aktiviteter av typen "Annet" trenger et navn. Fram til nå ble venue_name
-- brukt som overskrift, så navn og sted var det samme feltet.
ALTER TABLE gigs ADD COLUMN IF NOT EXISTS title TEXT;
