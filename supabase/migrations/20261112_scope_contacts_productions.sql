-- ============================================================
-- Selskapsskille på contacts og productions
-- ============================================================
-- 20261112_enable_rls_companies_contacts_productions.sql slo på RLS,
-- men lot lesetilgangen stå som den var:
--
--   contacts_select     FOR SELECT TO authenticated USING (true)
--   productions_select  FOR SELECT TO authenticated USING (true)
--
-- Det betyr at enhver innlogget bruker - også en artist i et helt annet
-- selskap - kan lese alle kontakter og produksjoner i hele basen. Det
-- bryter med regelen om at data aldri skal blandes mellom selskaper.
--
-- contacts_modify og productions_modify er like åpne for lesing, selv om
-- navnet sier noe annet: en policy med FOR ALL gjelder OGSÅ SELECT. Med
-- USING (is_any_admin()) ville enhver admin i ett hvilket som helst
-- selskap fortsatt sett alt. Derfor må begge bort, ikke bare _select.
--
-- ------------------------------------------------------------
-- SLUTTILSTAND: én policy per tabell
-- ------------------------------------------------------------
-- En rad hører til et selskap via company_id. Den er tilgjengelig hvis
-- selskapet enten ER et av mine, eller EIES av et av mine
-- (companies.owner_company_id). Platform owner ser alt, som på companies.
--
-- Oppslaget går gjennom my_customer_company_ids(), som er SECURITY
-- DEFINER. Et direkte oppslag mot companies inne i en policy på contacts
-- ville blitt filtrert av companies sin egen RLS.
--
-- productions.owner_company_id brukes IKKE til dette. Kolonnen settes bare
-- av tourflow_mobile (step_customer.dart:324) - desktop sin
-- production_dialog setter den ikke - så den er delvis utfylt og duger
-- ikke som grunnlag. company_id -> companies.owner_company_id er den
-- samme veien som skrivepolicyene allerede bruker.
--
-- ------------------------------------------------------------
-- HVA SOM FAKTISK ENDRER SEG I APPEN
-- ------------------------------------------------------------
-- Alle oppslag som betyr noe filtrerer allerede på company_id:
--   customers_service.getContacts/getProductions
--   new_offer_page (6549/6555), gig_offer_page (2094)
--   tourflow_mobile step_customer (_loadContacts/_loadProductions)
--
-- To steder henter ALT og filtrerer i klienten etterpå:
--   customers_page.dart:36 (_loadAllForPdf) og :57 (_exportPdf)
-- De matcher radene mot en eierfiltrert selskapsliste, så resultatet blir
-- det samme - de slutter bare å dra hele basen over nettet først. Det
-- fjerner samtidig en skjult felle: PostgREST kutter på 1000 rader, så
-- PDF-en ville stille mistet kontakter når tabellen vokste.
-- ============================================================


-- ============================================================
-- CONTACTS
-- ============================================================
DROP POLICY IF EXISTS "contacts_select"     ON contacts;
DROP POLICY IF EXISTS "contacts_modify"     ON contacts;
DROP POLICY IF EXISTS "contacts_write_mine" ON contacts;

CREATE POLICY "contacts_company_scope"
  ON contacts FOR ALL TO authenticated
  USING (
    company_id IN (SELECT public.my_company_ids_incl_profile())
    OR company_id IN (SELECT public.my_customer_company_ids())
    OR public.is_platform_owner()
  )
  WITH CHECK (
    company_id IN (SELECT public.my_company_ids_incl_profile())
    OR company_id IN (SELECT public.my_customer_company_ids())
    OR public.is_platform_owner()
  );


-- ============================================================
-- PRODUCTIONS
-- ============================================================
DROP POLICY IF EXISTS "productions_select"     ON productions;
DROP POLICY IF EXISTS "productions_modify"     ON productions;
DROP POLICY IF EXISTS "productions_write_mine" ON productions;

CREATE POLICY "productions_company_scope"
  ON productions FOR ALL TO authenticated
  USING (
    company_id IN (SELECT public.my_company_ids_incl_profile())
    OR company_id IN (SELECT public.my_customer_company_ids())
    OR public.is_platform_owner()
  )
  WITH CHECK (
    company_id IN (SELECT public.my_company_ids_incl_profile())
    OR company_id IN (SELECT public.my_customer_company_ids())
    OR public.is_platform_owner()
  );
