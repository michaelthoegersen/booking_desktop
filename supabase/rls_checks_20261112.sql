-- ============================================================
-- Sjekker rundt 20261112_enable_rls_companies_contacts_productions.sql
-- Kjøres i Supabase SQL Editor. Endrer ingenting.
-- ============================================================

-- ------------------------------------------------------------
-- FØR: brukere som bare har profiles.company_id
-- ------------------------------------------------------------
-- Dette er gruppen som faller utenfor my_company_ids(). Migrasjonen dekker
-- dem via my_company_ids_incl_profile(). Er tallet > 0, er det nettopp
-- disse som ville mistet companies-tilgang uten den hjelpefunksjonen.
SELECT count(*) AS brukere_uten_company_members
FROM profiles p
WHERE p.company_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM company_members cm WHERE cm.user_id = p.id
  );

-- ------------------------------------------------------------
-- FØR: kundeselskaper uten eier
-- ------------------------------------------------------------
-- Rader her blir usynlige for alle andre enn platform owner etter at RLS
-- slås på, fordi ingen SELECT-policy treffer dem. Er listen tom, er vi
-- trygge. Er den ikke tom: sett owner_company_id på dem først.
SELECT c.id, c.name, c.owner_company_id
FROM companies c
WHERE c.owner_company_id IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM company_members cm WHERE cm.company_id = c.id
  )
  AND NOT EXISTS (
    SELECT 1 FROM profiles p WHERE p.company_id = c.id
  )
ORDER BY c.name;

-- ------------------------------------------------------------
-- FØR: contacts/productions som peker på et selskap uten eier
-- ------------------------------------------------------------
-- Disse kan fortsatt LESES (contacts_select er USING (true)), men ikke
-- skrives av andre enn admin. Mest sannsynlig tomt.
SELECT 'contacts' AS tabell, count(*) AS rader_uten_eier
FROM contacts t JOIN companies c ON c.id = t.company_id
WHERE c.owner_company_id IS NULL
  AND NOT EXISTS (SELECT 1 FROM company_members cm WHERE cm.company_id = c.id)
UNION ALL
SELECT 'productions', count(*)
FROM productions t JOIN companies c ON c.id = t.company_id
WHERE c.owner_company_id IS NULL
  AND NOT EXISTS (SELECT 1 FROM company_members cm WHERE cm.company_id = c.id);


-- ------------------------------------------------------------
-- ETTER: RLS er på alle tre
-- ------------------------------------------------------------
SELECT relname AS tabell, relrowsecurity AS rls_pa, relforcerowsecurity AS tvunget
FROM pg_class
WHERE relnamespace = 'public'::regnamespace
  AND relname IN ('companies','contacts','productions')
ORDER BY relname;

-- ------------------------------------------------------------
-- ETTER: hele policy-settet, med PERMISSIVE/RESTRICTIVE
-- ------------------------------------------------------------
-- Alt skal stå som PERMISSIVE. En RESTRICTIVE policy her ville ANDes inn
-- og kunne ta bort tilgang de nye policyene gir.
SELECT tablename, policyname, permissive, cmd, roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('companies','contacts','productions')
ORDER BY tablename, cmd, policyname;

-- ------------------------------------------------------------
-- ETTER: er alle fire operasjoner dekket på companies?
-- ------------------------------------------------------------
-- Forventet: SELECT, INSERT, UPDATE og DELETE skal alle ha minst én
-- policy. Mangler DELETE, sletter customers_page stille ingenting.
SELECT cmd, count(*) AS antall_policyer
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'companies'
GROUP BY cmd
ORDER BY cmd;


-- ============================================================
-- TILBAKERULLING
-- ============================================================
-- Skulle noe falle ut i appen, slår dette av RLS igjen uten å fjerne
-- policyene. Tilstanden blir nøyaktig som før migrasjonen, og linteren
-- melder de samme seks feilene på nytt.
--
--   ALTER TABLE companies   DISABLE ROW LEVEL SECURITY;
--   ALTER TABLE contacts    DISABLE ROW LEVEL SECURITY;
--   ALTER TABLE productions DISABLE ROW LEVEL SECURITY;


-- ============================================================
-- Sjekker rundt 20261112_scope_contacts_productions.sql
-- ============================================================

-- ------------------------------------------------------------
-- FØR: rader som ville blitt usynlige for ALLE
-- ------------------------------------------------------------
-- Scopingen går via company_id. En rad uten company_id, eller med en
-- company_id som ikke finnes i companies, treffes av ingen policy og blir
-- borte for alle utenom platform owner. Begge tallene bør være 0.
SELECT 'contacts' AS tabell, count(*) AS foreldrelose
FROM contacts t
WHERE t.company_id IS NULL
   OR NOT EXISTS (SELECT 1 FROM companies c WHERE c.id = t.company_id)
UNION ALL
SELECT 'productions', count(*)
FROM productions t
WHERE t.company_id IS NULL
   OR NOT EXISTS (SELECT 1 FROM companies c WHERE c.id = t.company_id);

-- ------------------------------------------------------------
-- FØR: hvem eier radene?
-- ------------------------------------------------------------
-- Viser fordelingen per eierselskap. Rader med eier NULL tilhører et
-- tenant-selskap direkte og er synlige for medlemmene der.
SELECT COALESCE(eier.name, '(ingen eier - tenant selv)') AS eierselskap,
       count(*) FILTER (WHERE kilde = 'contacts')    AS kontakter,
       count(*) FILTER (WHERE kilde = 'productions') AS produksjoner
FROM (
  SELECT 'contacts' AS kilde, company_id FROM contacts
  UNION ALL
  SELECT 'productions', company_id FROM productions
) t
JOIN companies c ON c.id = t.company_id
LEFT JOIN companies eier ON eier.id = c.owner_company_id
GROUP BY 1
ORDER BY 1;

-- ------------------------------------------------------------
-- ETTER: nøyaktig én policy per tabell, og den dekker ALL
-- ------------------------------------------------------------
SELECT tablename, policyname, permissive, cmd
FROM pg_policies
WHERE schemaname = 'public' AND tablename IN ('contacts','productions')
ORDER BY tablename, policyname;

-- Tilbakerulling til det åpne settet (lesing på tvers av selskaper):
--
--   DROP POLICY IF EXISTS "contacts_company_scope" ON contacts;
--   CREATE POLICY "contacts_select" ON contacts
--     FOR SELECT TO authenticated USING (true);
--   CREATE POLICY "contacts_modify" ON contacts
--     FOR ALL TO authenticated USING (is_any_admin());
--
--   DROP POLICY IF EXISTS "productions_company_scope" ON productions;
--   CREATE POLICY "productions_select" ON productions
--     FOR SELECT TO authenticated USING (true);
--   CREATE POLICY "productions_modify" ON productions
--     FOR ALL TO authenticated USING (is_any_admin());
