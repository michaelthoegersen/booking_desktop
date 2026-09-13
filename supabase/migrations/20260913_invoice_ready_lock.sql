-- ============================================================
-- KLAR FOR FAKTURERING
-- Erstatter "Send til Tripletex" på tilbudssiden. Den som er ferdig med
-- tilbudet melder det klart, økonomiansvarlig får varsel, og tilbudet +
-- de tilknyttede giggene låses for endringer til økonomi låser opp igjen.
-- ============================================================

-- 1. Økonomiansvarlig. Et eget flagg i stedet for en rolle, slik at en admin
--    beholder admin-rettighetene sine og flere kan ha ansvaret samtidig.
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS is_finance BOOLEAN NOT NULL DEFAULT false;

-- 2. Låsen på tilbudet.
ALTER TABLE gig_offers
  ADD COLUMN IF NOT EXISTS invoice_ready_at TIMESTAMPTZ;
ALTER TABLE gig_offers
  ADD COLUMN IF NOT EXISTS invoice_ready_by UUID REFERENCES auth.users(id);

-- 3. Samme lås speiles på giggene, så hver skjerm kan sjekke ett felt i
--    stedet for å slå opp tilbudet. Settes og fjernes av samme handling.
ALTER TABLE gigs
  ADD COLUMN IF NOT EXISTS invoice_locked BOOLEAN NOT NULL DEFAULT false;

-- Raskt oppslag på hvem som skal varsles.
CREATE INDEX IF NOT EXISTS idx_profiles_is_finance
  ON profiles(company_id) WHERE is_finance;
