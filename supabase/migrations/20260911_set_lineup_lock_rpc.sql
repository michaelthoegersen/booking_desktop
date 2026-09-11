-- Gruppeledere klarte ikke å låse laget:
-- RLS-policyen "gigs_update" slipper dem inn via is_leader_in(), som leser
-- company_members.role — men appene lagrer rollen kun i profiles.role.
-- UPDATE-en traff derfor 0 rader, og PostgREST gir ingen feil på en
-- RLS-blokkert UPDATE, så låsen feilet stille.
--
-- Løsning: en SECURITY DEFINER-funksjon som gjør rolle-sjekken selv (mot
-- BÅDE profiles.role og company_members.role) og som kun kan skrive til de
-- to lineup_locked-kolonnene. Ingen andre policyer eller kolonner berøres.

CREATE OR REPLACE FUNCTION public.set_lineup_lock(
  p_gig_id  UUID,
  p_section TEXT,
  p_locked  BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_role       TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  IF p_section NOT IN ('skarp', 'bass') THEN
    RAISE EXCEPTION 'Ugyldig seksjon: %', p_section;
  END IF;

  SELECT company_id INTO v_company_id FROM gigs WHERE id = p_gig_id;
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke gig';
  END IF;

  -- Må være medlem av selskapet giggen tilhører (ingen data på tvers av selskap)
  IF NOT EXISTS (
    SELECT 1 FROM company_members
    WHERE user_id = auth.uid() AND company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'Ingen tilgang til denne giggen';
  END IF;

  -- Rollen appene faktisk bruker ligger i profiles.role
  SELECT role INTO v_role FROM profiles WHERE id = auth.uid();

  -- Fall tilbake på company_members.role hvis profilen ikke har en kjent rolle
  IF COALESCE(v_role, '') NOT IN
       ('admin', 'management', 'gruppeleder_skarp', 'gruppeleder_bass') THEN
    SELECT role INTO v_role FROM company_members
     WHERE user_id = auth.uid() AND company_id = v_company_id;
  END IF;

  IF NOT (
       COALESCE(v_role, '') IN ('admin', 'management')
    OR (p_section = 'skarp' AND v_role = 'gruppeleder_skarp')
    OR (p_section = 'bass'  AND v_role = 'gruppeleder_bass')
  ) THEN
    RAISE EXCEPTION 'Du har ikke tilgang til å låse seksjonen %', p_section;
  END IF;

  IF p_section = 'skarp' THEN
    UPDATE gigs SET lineup_locked_skarp = p_locked WHERE id = p_gig_id;
  ELSE
    UPDATE gigs SET lineup_locked_bass = p_locked WHERE id = p_gig_id;
  END IF;

  RETURN p_locked;
END;
$$;

REVOKE ALL ON FUNCTION public.set_lineup_lock(UUID, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_lineup_lock(UUID, TEXT, BOOLEAN) TO authenticated;
