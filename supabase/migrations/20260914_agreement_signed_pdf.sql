-- Lagre den faktiske signerte intensjonsavtalen — den som sendes til kunden
-- når begge parter har signert. Fram til nå ble den generert, sendt og kastet,
-- så det eneste eksemplaret lå i kundens innboks. Samme mønster som
-- offer_tokens.signed_pdf_path.
ALTER TABLE agreement_tokens
  ADD COLUMN IF NOT EXISTS signed_pdf_path TEXT;
