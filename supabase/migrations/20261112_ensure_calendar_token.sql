-- ============================================================
-- ensure_calendar_token(): kalendertoken uten åpen UPDATE på companies
-- ============================================================
-- 20261112_enable_rls_companies_contacts_productions.sql måtte la
-- companies_update_mine gjelde for alle roller, ikke bare admin. Grunnen:
--
--   tourflow_mobile  lib/data/gig_repository.dart   getOrCreateCalendarToken
--   booking_desktop  lib/pages/mgmt/mgmt_gigs_page.dart:692
--
-- Begge leser companies.calendar_token, og skriver en ny hvis den mangler.
-- Kalenderknappen (gigs_screen.dart:265) er ikke rollestyrt, så en artist
-- eller crew må kunne gjøre dette. Resultatet var at et menig medlem
-- teknisk sett kan oppdatere hele sin egen selskapsrad.
--
-- Denne funksjonen gjør jobben server-side i stedet. Den er SECURITY
-- DEFINER, så UPDATE-en går utenom RLS, og den rører bare én kolonne.
-- Da kan companies UPDATE strammes til admin igjen - se
-- 20261112_tighten_companies_update.sql, som IKKE skal kjøres før en ny
-- mobilbygg er ute.
--
-- Tilgangskontrollen ligger i funksjonen selv: kalleren må høre til
-- selskapet. Uten den sjekken ville SECURITY DEFINER latt hvem som helst
-- hente kalendertokenet til et hvilket som helst selskap, og tokenet er
-- det eneste som beskytter gig-kalenderen i gig-calendar-funksjonen.
--
-- gen_random_uuid() brukes i stedet for gen_random_bytes() fordi den
-- første ligger i pg_catalog og alltid kan nås, mens pgcrypto ligger i
-- extensions-skjemaet og ikke er med i search_path her. To uuid-er uten
-- bindestrek gir 64 hex-tegn, nøyaktig samme lengde som klientene
-- genererte før (32 tilfeldige byte).
-- ============================================================

CREATE OR REPLACE FUNCTION public.ensure_calendar_token(p_company_id uuid)
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token text;
BEGIN
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'company_id mangler';
  END IF;

  IF NOT (p_company_id IN (SELECT public.my_company_ids_incl_profile())) THEN
    RAISE EXCEPTION 'Ingen tilgang til selskapet %', p_company_id
      USING ERRCODE = '42501';
  END IF;

  SELECT calendar_token INTO v_token
    FROM companies WHERE id = p_company_id;

  IF v_token IS NULL OR v_token = '' THEN
    v_token := replace(gen_random_uuid()::text, '-', '')
            || replace(gen_random_uuid()::text, '-', '');

    UPDATE companies
       SET calendar_token = v_token
     WHERE id = p_company_id;
  END IF;

  RETURN v_token;
END;
$$;

COMMENT ON FUNCTION public.ensure_calendar_token(uuid) IS
  'Returnerer selskapets calendar_token og lager den første gang. Erstatter en direkte UPDATE fra klienten, slik at companies UPDATE kan være admin-only.';

REVOKE ALL ON FUNCTION public.ensure_calendar_token(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_calendar_token(uuid) TO authenticated;
