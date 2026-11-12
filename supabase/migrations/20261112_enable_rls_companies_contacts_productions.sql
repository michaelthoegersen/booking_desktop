-- ============================================================
-- Slå PÅ RLS på companies, contacts og productions
-- ============================================================
-- Supabase-linteren melder to feil per tabell:
--   policy_exists_rls_disabled  - policyene finnes, men er slått av
--   rls_disabled_in_public      - tabellen er eksponert via PostgREST
--
-- I praksis betyr det at ALLE med anon-nøkkelen (som ligger i web-bundelen
-- og i mobilappen) kan lese og skrive hele companies, contacts og
-- productions. Policyene er skrevet, men ALTER TABLE ... ENABLE ble aldri
-- kjørt - eller ble slått av igjen - så de har ikke hatt noen effekt.
--
-- ------------------------------------------------------------
-- HVORFOR DETTE HAR GÅTT GALT FØR
-- ------------------------------------------------------------
-- Da RLS ble slått på på resten av tabellene, falt ting ut fordi policyene
-- antok at brukeren står i company_members. Begge appene har en fallback:
--
--   booking_desktop  lib/state/active_company.dart  - company_members,
--                    ellers profiles.company_id
--   tourflow_mobile  lib/data/gig_repository.dart   - KUN profiles.company_id
--
-- En bruker som bare har profiles.company_id får ingen rader fra
-- my_company_ids(). I mobilappen går _applyCompany da tom, showTours og
-- showGigs blir false, og menyen er blank. Derfor har denne migrasjonen en
-- egen hjelpefunksjon som slår sammen begge kildene.
--
-- Fire konkrete hull i dagens policy-sett, funnet ved å lese koden:
--
--   1. companies DELETE  - det finnes bare companies_delete_platform_owner.
--      customers_page.dart:331 sletter kundeselskaper. For alle andre enn
--      platform owner ville den stille ikke slettet noe (en DELETE som RLS
--      blokkerer gir 0 rader og INGEN feil - samme felle som gig-slettingen).
--   2. companies UPDATE  - krever admin. gig_repository.dart:1150
--      (getOrCreateCalendarToken) skriver calendar_token, og
--      kalenderknappen i gigs_screen.dart:265 er ikke rollestyrt. En artist
--      eller crew ville fått feil når de abonnerer på kalenderen.
--   3. companies INSERT  - krever admin i eierselskapet. mgmt_gigs_page og
--      new_company_dialog oppretter kundeselskaper.
--   4. contacts/productions skriving - krever is_any_admin(). new_offer_page
--      (6734/6748) og production_dialog oppretter og endrer disse, og den
--      som lager tilbud er ikke nødvendigvis admin.
--
-- Derfor: ingen eksisterende policy røres. Migrasjonen LEGGER TIL det som
-- mangler, og slår på RLS helt til slutt. Policyer er PERMISSIVE og ORes
-- sammen, så nye policyer kan bare gi tilgang, aldri ta bort.
--
-- ------------------------------------------------------------
-- IKKE BERØRT
-- ------------------------------------------------------------
-- * Alle edge functions bruker SUPABASE_SERVICE_ROLE_KEY og går utenom RLS.
--   Sjekket alle, inkludert notify-chat, notify-company, send-push og
--   website-booking. Varslinger kan ikke påvirkes av dette.
-- * Ingen policy på noen annen tabell leser companies, contacts eller
--   productions, så det oppstår ingen rekursiv RLS (feilen som
--   20260318_rls_v2_with_helper måtte rydde opp i).
-- * Ingen side i noen av appene leser disse tabellene uinnlogget.
-- * contacts_select og productions_select er USING (true) og blir stående
--   slik. Det er fortsatt for åpent på tvers av selskaper, men å stramme
--   det krever at vi først vet at owner_company_id er satt på alle
--   kunderader. Det tas som en egen endring.
-- ============================================================


-- ============================================================
-- 1. HJELPEFUNKSJONER (nye, additive)
-- ============================================================
-- SECURITY DEFINER = går utenom RLS, så policyene ikke kaller seg selv.
-- my_company_ids() røres IKKE: den brukes av ~30 andre policyer, og å
-- endre den ville utvidet alle samtidig.

CREATE OR REPLACE FUNCTION public.my_company_ids_incl_profile()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT company_id FROM company_members
   WHERE user_id = auth.uid() AND company_id IS NOT NULL
  UNION
  SELECT company_id FROM profiles
   WHERE id = auth.uid() AND company_id IS NOT NULL;
$$;

COMMENT ON FUNCTION public.my_company_ids_incl_profile() IS
  'Selskaper brukeren hører til, fra company_members OG profiles.company_id. Mobilappen bruker kun profiles.company_id, så my_company_ids() alene låser den ute.';

-- Kundeselskapene mine selskaper eier. Ligger i en SECURITY DEFINER-funksjon
-- fordi et oppslag mot companies inne i en policy på contacts ellers ville
-- blitt filtrert av companies sin egen RLS.
CREATE OR REPLACE FUNCTION public.my_customer_company_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.id FROM companies c
   WHERE c.owner_company_id IN (SELECT public.my_company_ids_incl_profile());
$$;

COMMENT ON FUNCTION public.my_customer_company_ids() IS
  'Kundeselskaper eid av et selskap brukeren hører til (companies.owner_company_id).';

GRANT EXECUTE ON FUNCTION public.my_company_ids_incl_profile() TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_customer_company_ids()    TO authenticated;


-- ============================================================
-- 2. COMPANIES - legg til det som mangler
-- ============================================================

-- SELECT: eget selskap, også når tilhørigheten bare står i profiles.
-- companies_select dekker company_members-varianten og blir stående.
DROP POLICY IF EXISTS "companies_select_mine" ON companies;
CREATE POLICY "companies_select_mine"
  ON companies FOR SELECT TO authenticated
  USING (id IN (SELECT public.my_company_ids_incl_profile()));

-- SELECT: kundeselskaper vi eier (customers_page, new_offer_page, tilbud).
DROP POLICY IF EXISTS "companies_select_owned" ON companies;
CREATE POLICY "companies_select_owned"
  ON companies FOR SELECT TO authenticated
  USING (owner_company_id IN (SELECT public.my_company_ids_incl_profile()));

-- INSERT: kundeselskaper under et selskap brukeren hører til.
-- owner_company_id IS NULL (nye tenants) treffer IKKE denne, så det er
-- fortsatt bare platform owner som kan opprette tenants via companies_insert.
DROP POLICY IF EXISTS "companies_insert_owned" ON companies;
CREATE POLICY "companies_insert_owned"
  ON companies FOR INSERT TO authenticated
  WITH CHECK (
    owner_company_id IS NOT NULL
    AND owner_company_id IN (SELECT public.my_company_ids_incl_profile())
  );

-- UPDATE: eget selskap uansett rolle, pluss kundeselskaper vi eier.
-- Rollekravet er bevisst utelatt fordi kalenderknappen i mobilappen skriver
-- companies.calendar_token for alle brukere. Dette er fortsatt en kraftig
-- innsnevring: i dag kan hvem som helst oppdatere hvilket som helst selskap.
-- Riktigere løsning er en SECURITY DEFINER-RPC for selve tokenet, men den
-- krever ny mobilbygg, så den må komme etterpå.
DROP POLICY IF EXISTS "companies_update_mine" ON companies;
CREATE POLICY "companies_update_mine"
  ON companies FOR UPDATE TO authenticated
  USING (
    id IN (SELECT public.my_company_ids_incl_profile())
    OR owner_company_id IN (SELECT public.my_company_ids_incl_profile())
  )
  WITH CHECK (
    id IN (SELECT public.my_company_ids_incl_profile())
    OR owner_company_id IN (SELECT public.my_company_ids_incl_profile())
  );

-- DELETE: kundeselskaper vi eier. Uten denne ville customers_page sin
-- sletting stille gjort ingenting for alle andre enn platform owner.
-- Tenants (owner_company_id IS NULL) er fortsatt kun platform owner.
DROP POLICY IF EXISTS "companies_delete_owned" ON companies;
CREATE POLICY "companies_delete_owned"
  ON companies FOR DELETE TO authenticated
  USING (
    owner_company_id IS NOT NULL
    AND owner_company_id IN (SELECT public.my_company_ids_incl_profile())
  );


-- ============================================================
-- 3. CONTACTS / PRODUCTIONS - legg til skrivetilgang
-- ============================================================
-- contacts_modify og productions_modify (is_any_admin()) blir stående.
-- Disse legger til medlemmer uten admin-rolle, som er de som faktisk
-- redigerer kontakter når de lager tilbud.

DROP POLICY IF EXISTS "contacts_write_mine" ON contacts;
CREATE POLICY "contacts_write_mine"
  ON contacts FOR ALL TO authenticated
  USING (
    company_id IN (SELECT public.my_company_ids_incl_profile())
    OR company_id IN (SELECT public.my_customer_company_ids())
  )
  WITH CHECK (
    company_id IN (SELECT public.my_company_ids_incl_profile())
    OR company_id IN (SELECT public.my_customer_company_ids())
  );

DROP POLICY IF EXISTS "productions_write_mine" ON productions;
CREATE POLICY "productions_write_mine"
  ON productions FOR ALL TO authenticated
  USING (
    company_id IN (SELECT public.my_company_ids_incl_profile())
    OR company_id IN (SELECT public.my_customer_company_ids())
  )
  WITH CHECK (
    company_id IN (SELECT public.my_company_ids_incl_profile())
    OR company_id IN (SELECT public.my_customer_company_ids())
  );


-- ============================================================
-- 4. SLÅ PÅ RLS - helt til slutt
-- ============================================================
-- Rekkefølgen er med vilje: feiler noe over, står tabellene fortsatt
-- åpne i stedet for å bli låst ned med et halvt policy-sett.

ALTER TABLE companies   ENABLE ROW LEVEL SECURITY;
ALTER TABLE contacts    ENABLE ROW LEVEL SECURITY;
ALTER TABLE productions ENABLE ROW LEVEL SECURITY;
