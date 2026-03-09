-- Add draft_id to v_turer_app so the mobile app can navigate
-- from a notification to the correct tour.
CREATE OR REPLACE VIEW v_turer_app AS
SELECT
  id         AS app_id,
  draft_id,
  dato,
  sted,
  venue,
  adresse,
  km,
  distance_total_km,
  tid,
  produksjon,
  kjoretoy,
  sjafor,
  d_drive,
  status,
  kilde,
  getin,
  kommentarer,
  vedlegg,
  contact,
  contact_name,
  contact_phone,
  contact_email
FROM samletdata;
