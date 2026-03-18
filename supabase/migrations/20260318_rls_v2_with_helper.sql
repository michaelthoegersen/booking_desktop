-- ============================================================
-- RLS V2: Proper implementation using SECURITY DEFINER helpers
--
-- Problem with V1: policies on table A referenced table B which
-- also had RLS, causing silent failures (recursive RLS).
--
-- Solution: SECURITY DEFINER functions bypass RLS and return
-- the current user's company IDs and admin status.
-- ============================================================

-- ============================================================
-- STEP 1: Helper functions (SECURITY DEFINER = bypasses RLS)
-- ============================================================

CREATE OR REPLACE FUNCTION public.my_company_ids()
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT company_id FROM company_members WHERE user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.is_admin_in(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM company_members
    WHERE user_id = auth.uid()
      AND company_id = p_company_id
      AND role IN ('admin', 'management')
  );
$$;

CREATE OR REPLACE FUNCTION public.is_any_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM company_members
    WHERE user_id = auth.uid()
      AND role IN ('admin', 'management')
  );
$$;

-- ============================================================
-- STEP 2: Drop ALL policies we created in v1 (clean slate)
-- ============================================================

-- profiles
DROP POLICY IF EXISTS "Users read own profile" ON profiles;
DROP POLICY IF EXISTS "Users read company members profiles" ON profiles;
DROP POLICY IF EXISTS "Users update own profile" ON profiles;
DROP POLICY IF EXISTS "Authenticated read basic profiles" ON profiles;

-- companies
DROP POLICY IF EXISTS "Members can read own companies" ON companies;
DROP POLICY IF EXISTS "Admins can update own companies" ON companies;

-- gigs
DROP POLICY IF EXISTS "Members see company gigs" ON gigs;
DROP POLICY IF EXISTS "Admins manage company gigs" ON gigs;

-- gig_crew
DROP POLICY IF EXISTS "Members see gig crew" ON gig_crew;
DROP POLICY IF EXISTS "Admins manage gig crew" ON gig_crew;

-- gig_shows
DROP POLICY IF EXISTS "Members see gig shows" ON gig_shows;
DROP POLICY IF EXISTS "Admins manage gig shows" ON gig_shows;

-- gig_comments
DROP POLICY IF EXISTS "Members see gig comments" ON gig_comments;
DROP POLICY IF EXISTS "Members insert own gig comments" ON gig_comments;
DROP POLICY IF EXISTS "Users delete own gig comments" ON gig_comments;

-- show_types
DROP POLICY IF EXISTS "Members see company show types" ON show_types;
DROP POLICY IF EXISTS "Admins manage show types" ON show_types;

-- management_tours
DROP POLICY IF EXISTS "Members see company tours" ON management_tours;
DROP POLICY IF EXISTS "Admins manage company tours" ON management_tours;

-- management_shows
DROP POLICY IF EXISTS "Members see tour shows" ON management_shows;
DROP POLICY IF EXISTS "Admins manage tour shows" ON management_shows;

-- management_team
DROP POLICY IF EXISTS "Members see tour team" ON management_team;
DROP POLICY IF EXISTS "Admins manage tour team" ON management_team;

-- management_itinerary
DROP POLICY IF EXISTS "Members see tour itinerary" ON management_itinerary;
DROP POLICY IF EXISTS "Admins manage tour itinerary" ON management_itinerary;

-- bus_requests
DROP POLICY IF EXISTS "Members see company bus requests" ON bus_requests;
DROP POLICY IF EXISTS "Admins manage bus requests" ON bus_requests;

-- bus_request_gigs
DROP POLICY IF EXISTS "Members see bus request gigs" ON bus_request_gigs;
DROP POLICY IF EXISTS "Admins manage bus request gigs" ON bus_request_gigs;

-- routes
DROP POLICY IF EXISTS "Authenticated read routes" ON routes_all;
DROP POLICY IF EXISTS "Admins manage routes" ON routes_all;
DROP POLICY IF EXISTS "Authenticated read routes backup" ON routes_all_backup;
DROP POLICY IF EXISTS "Authenticated read route staging" ON route_country_km_staging;
DROP POLICY IF EXISTS "Authenticated read route costs" ON route_costs;

-- countries/ferries/vat
DROP POLICY IF EXISTS "Authenticated read countries" ON countries;
DROP POLICY IF EXISTS "Authenticated read ferries" ON ferries;
DROP POLICY IF EXISTS "Authenticated read vat rates" ON country_vat_rates;

-- samletdata
DROP POLICY IF EXISTS "Members see company samletdata" ON samletdata;
DROP POLICY IF EXISTS "Admins manage samletdata" ON samletdata;

-- contacts/customers/productions/invoices
DROP POLICY IF EXISTS "Authenticated read contacts" ON contacts;
DROP POLICY IF EXISTS "Admins manage contacts" ON contacts;
DROP POLICY IF EXISTS "Members read customers" ON customers;
DROP POLICY IF EXISTS "Admins manage customers" ON customers;
DROP POLICY IF EXISTS "Authenticated read productions" ON productions;
DROP POLICY IF EXISTS "Admins manage productions" ON productions;
DROP POLICY IF EXISTS "Admins manage invoices" ON invoices;

-- issue_reports
DROP POLICY IF EXISTS "Members read issue reports" ON issue_reports;
DROP POLICY IF EXISTS "Members insert issue reports" ON issue_reports;
DROP POLICY IF EXISTS "Admins manage issue reports" ON issue_reports;

-- system tables
DROP POLICY IF EXISTS "Authenticated manage job notifications" ON job_notifications;
DROP POLICY IF EXISTS "Authenticated manage push queue" ON push_queue;
DROP POLICY IF EXISTS "Authenticated manage draft notifications" ON draft_notifications;
DROP POLICY IF EXISTS "Authenticated manage driver push" ON driver_push_sent;
DROP POLICY IF EXISTS "Authenticated manage waiting list" ON waiting_list;

-- gig_offers (from fix_warnings)
DROP POLICY IF EXISTS "Members see company gig offers" ON gig_offers;
DROP POLICY IF EXISTS "Admins manage gig offers" ON gig_offers;
DROP POLICY IF EXISTS "Members see gig offer shows" ON gig_offer_shows;
DROP POLICY IF EXISTS "Admins manage gig offer shows" ON gig_offer_shows;
DROP POLICY IF EXISTS "Members see gig offer gigs" ON gig_offer_gigs;
DROP POLICY IF EXISTS "Admins manage gig offer gigs" ON gig_offer_gigs;
DROP POLICY IF EXISTS "Members see offer versions" ON offer_versions;
DROP POLICY IF EXISTS "Admins manage offer versions" ON offer_versions;
DROP POLICY IF EXISTS "Admins manage oauth tokens" ON microsoft_oauth_tokens;

-- offers (from fix_warnings)
DROP POLICY IF EXISTS "Members see company offers" ON offers;
DROP POLICY IF EXISTS "Admins manage offers" ON offers;

-- tokens (from fix_warnings)
DROP POLICY IF EXISTS "Anon can update offer_tokens by token" ON offer_tokens;
DROP POLICY IF EXISTS "Admins insert offer_tokens" ON offer_tokens;
DROP POLICY IF EXISTS "Admins update offer_tokens" ON offer_tokens;
DROP POLICY IF EXISTS "Admins delete offer_tokens" ON offer_tokens;
DROP POLICY IF EXISTS "Anon can update agreement_tokens by token" ON agreement_tokens;
DROP POLICY IF EXISTS "Admins insert agreement_tokens" ON agreement_tokens;
DROP POLICY IF EXISTS "Admins update agreement_tokens" ON agreement_tokens;

-- chat (from fix_warnings)
DROP POLICY IF EXISTS "Users update own gig messages" ON gig_messages;
DROP POLICY IF EXISTS "Users update own crp messages" ON crp_messages;

-- calendar (from fix_warnings)
DROP POLICY IF EXISTS "Admins delete calendar attachments" ON calendar_attachments;
DROP POLICY IF EXISTS "Admins insert calendar attachments" ON calendar_attachments;
DROP POLICY IF EXISTS "Admins delete boarding passes" ON calendar_boarding_passes;
DROP POLICY IF EXISTS "Admins insert boarding passes" ON calendar_boarding_passes;

-- issues (from fix_warnings)
DROP POLICY IF EXISTS "Admins delete issues" ON issues;
DROP POLICY IF EXISTS "Admins update issues" ON issues;

-- ============================================================
-- STEP 3: Enable RLS on all tables + create proper policies
-- Using my_company_ids() and is_any_admin() helpers
-- ============================================================

-- ── PROFILES ─────────────────────────────────────────────
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles_select"
  ON profiles FOR SELECT TO authenticated
  USING (true);  -- all authenticated can read profiles (names, avatars)

CREATE POLICY "profiles_update_own"
  ON profiles FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- ── COMPANIES ────────────────────────────────────────────
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;

CREATE POLICY "companies_select"
  ON companies FOR SELECT TO authenticated
  USING (id IN (SELECT my_company_ids()));

CREATE POLICY "companies_update"
  ON companies FOR UPDATE TO authenticated
  USING (is_admin_in(id));

-- ── GIGS ─────────────────────────────────────────────────
ALTER TABLE gigs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "gigs_select"
  ON gigs FOR SELECT TO authenticated
  USING (company_id IN (SELECT my_company_ids()));

CREATE POLICY "gigs_insert"
  ON gigs FOR INSERT TO authenticated
  WITH CHECK (is_admin_in(company_id));

CREATE POLICY "gigs_update"
  ON gigs FOR UPDATE TO authenticated
  USING (is_admin_in(company_id));

CREATE POLICY "gigs_delete"
  ON gigs FOR DELETE TO authenticated
  USING (is_admin_in(company_id));

-- ── GIG_CREW ─────────────────────────────────────────────
ALTER TABLE gig_crew ENABLE ROW LEVEL SECURITY;

CREATE POLICY "gig_crew_select"
  ON gig_crew FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM gigs WHERE gigs.id = gig_crew.gig_id
    AND gigs.company_id IN (SELECT my_company_ids())
  ));

CREATE POLICY "gig_crew_modify"
  ON gig_crew FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM gigs WHERE gigs.id = gig_crew.gig_id
    AND is_admin_in(gigs.company_id)
  ));

-- ── GIG_SHOWS ────────────────────────────────────────────
ALTER TABLE gig_shows ENABLE ROW LEVEL SECURITY;

CREATE POLICY "gig_shows_select"
  ON gig_shows FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM gigs WHERE gigs.id = gig_shows.gig_id
    AND gigs.company_id IN (SELECT my_company_ids())
  ));

CREATE POLICY "gig_shows_modify"
  ON gig_shows FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM gigs WHERE gigs.id = gig_shows.gig_id
    AND is_admin_in(gigs.company_id)
  ));

-- ── GIG_COMMENTS ─────────────────────────────────────────
ALTER TABLE gig_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "gig_comments_select"
  ON gig_comments FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM gigs WHERE gigs.id = gig_comments.gig_id
    AND gigs.company_id IN (SELECT my_company_ids())
  ));

CREATE POLICY "gig_comments_insert"
  ON gig_comments FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "gig_comments_delete"
  ON gig_comments FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- ── SHOW_TYPES ───────────────────────────────────────────
ALTER TABLE show_types ENABLE ROW LEVEL SECURITY;

CREATE POLICY "show_types_select"
  ON show_types FOR SELECT TO authenticated
  USING (company_id IS NULL OR company_id IN (SELECT my_company_ids()));

CREATE POLICY "show_types_modify"
  ON show_types FOR ALL TO authenticated
  USING (is_admin_in(company_id));

-- ── MANAGEMENT TOURS ─────────────────────────────────────
ALTER TABLE management_tours ENABLE ROW LEVEL SECURITY;

CREATE POLICY "mgmt_tours_select"
  ON management_tours FOR SELECT TO authenticated
  USING (company_id IN (SELECT my_company_ids()));

CREATE POLICY "mgmt_tours_modify"
  ON management_tours FOR ALL TO authenticated
  USING (is_admin_in(company_id));

-- ── MANAGEMENT SHOWS ─────────────────────────────────────
ALTER TABLE management_shows ENABLE ROW LEVEL SECURITY;

CREATE POLICY "mgmt_shows_select"
  ON management_shows FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM management_tours t WHERE t.id = management_shows.tour_id
    AND t.company_id IN (SELECT my_company_ids())
  ));

CREATE POLICY "mgmt_shows_modify"
  ON management_shows FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM management_tours t WHERE t.id = management_shows.tour_id
    AND is_admin_in(t.company_id)
  ));

-- ── MANAGEMENT TEAM ──────────────────────────────────────
ALTER TABLE management_team ENABLE ROW LEVEL SECURITY;

CREATE POLICY "mgmt_team_select"
  ON management_team FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM management_tours t WHERE t.id = management_team.tour_id
    AND t.company_id IN (SELECT my_company_ids())
  ));

CREATE POLICY "mgmt_team_modify"
  ON management_team FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM management_tours t WHERE t.id = management_team.tour_id
    AND is_admin_in(t.company_id)
  ));

-- ── MANAGEMENT ITINERARY ─────────────────────────────────
ALTER TABLE management_itinerary ENABLE ROW LEVEL SECURITY;

CREATE POLICY "mgmt_itin_select"
  ON management_itinerary FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM management_tours t WHERE t.id = management_itinerary.tour_id
    AND t.company_id IN (SELECT my_company_ids())
  ));

CREATE POLICY "mgmt_itin_modify"
  ON management_itinerary FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM management_tours t WHERE t.id = management_itinerary.tour_id
    AND is_admin_in(t.company_id)
  ));

-- ── BUS REQUESTS ─────────────────────────────────────────
ALTER TABLE bus_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "bus_req_select"
  ON bus_requests FOR SELECT TO authenticated
  USING (company_id IN (SELECT my_company_ids()));

CREATE POLICY "bus_req_modify"
  ON bus_requests FOR ALL TO authenticated
  USING (is_admin_in(company_id));

ALTER TABLE bus_request_gigs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "bus_req_gigs_select"
  ON bus_request_gigs FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM bus_requests br WHERE br.id = bus_request_gigs.bus_request_id
    AND br.company_id IN (SELECT my_company_ids())
  ));

CREATE POLICY "bus_req_gigs_modify"
  ON bus_request_gigs FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM bus_requests br WHERE br.id = bus_request_gigs.bus_request_id
    AND is_admin_in(br.company_id)
  ));

-- ── SAMLETDATA ───────────────────────────────────────────
ALTER TABLE samletdata ENABLE ROW LEVEL SECURITY;

-- Drop old ChatGPT policies
DROP POLICY IF EXISTS "Allow update own jobs" ON samletdata;
DROP POLICY IF EXISTS "delete all" ON samletdata;
DROP POLICY IF EXISTS "insert all" ON samletdata;
DROP POLICY IF EXISTS "update all" ON samletdata;
DROP POLICY IF EXISTS "read all" ON samletdata;

CREATE POLICY "samletdata_select"
  ON samletdata FOR SELECT TO authenticated
  USING (owner_company_id IN (SELECT my_company_ids()));

CREATE POLICY "samletdata_modify"
  ON samletdata FOR ALL TO authenticated
  USING (is_admin_in(owner_company_id));

-- ── LOOKUP TABLES (read-only for all authenticated) ──────
ALTER TABLE countries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "countries_select" ON countries FOR SELECT TO authenticated USING (true);

ALTER TABLE ferries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ferries_select" ON ferries FOR SELECT TO authenticated USING (true);

ALTER TABLE country_vat_rates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "vat_select" ON country_vat_rates FOR SELECT TO authenticated USING (true);

ALTER TABLE routes_all ENABLE ROW LEVEL SECURITY;
CREATE POLICY "routes_select" ON routes_all FOR SELECT TO authenticated USING (true);
CREATE POLICY "routes_modify" ON routes_all FOR ALL TO authenticated USING (is_any_admin());

ALTER TABLE routes_all_backup ENABLE ROW LEVEL SECURITY;
CREATE POLICY "routes_bak_select" ON routes_all_backup FOR SELECT TO authenticated USING (true);

ALTER TABLE route_country_km_staging ENABLE ROW LEVEL SECURITY;
CREATE POLICY "route_stg_select" ON route_country_km_staging FOR SELECT TO authenticated USING (true);

ALTER TABLE route_costs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "route_costs_select" ON route_costs FOR SELECT TO authenticated USING (true);

-- ── CONTACTS / CUSTOMERS / PRODUCTIONS ───────────────────
ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "contacts_select" ON contacts FOR SELECT TO authenticated USING (true);
CREATE POLICY "contacts_modify" ON contacts FOR ALL TO authenticated USING (is_any_admin());

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "customers_select" ON customers FOR SELECT TO authenticated USING (true);
CREATE POLICY "customers_modify" ON customers FOR ALL TO authenticated USING (is_any_admin());

ALTER TABLE productions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "productions_select" ON productions FOR SELECT TO authenticated USING (true);
CREATE POLICY "productions_modify" ON productions FOR ALL TO authenticated USING (is_any_admin());

-- ── INVOICES ─────────────────────────────────────────────
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
CREATE POLICY "invoices_all" ON invoices FOR ALL TO authenticated USING (is_any_admin());

-- ── ISSUE REPORTS ────────────────────────────────────────
ALTER TABLE issue_reports ENABLE ROW LEVEL SECURITY;
CREATE POLICY "issues_select" ON issue_reports FOR SELECT TO authenticated USING (true);
CREATE POLICY "issues_insert" ON issue_reports FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "issues_modify" ON issue_reports FOR UPDATE TO authenticated USING (is_any_admin());

-- ── CRP_MESSAGES ─────────────────────────────────────────
ALTER TABLE crp_messages ENABLE ROW LEVEL SECURITY;
-- Keep existing select/insert policies, fix update
DROP POLICY IF EXISTS "Authenticated users can update crp_messages" ON crp_messages;
CREATE POLICY "crp_update_own" ON crp_messages FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- ── SYSTEM TABLES (internal, all authenticated) ──────────
ALTER TABLE job_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "job_notif_all" ON job_notifications FOR ALL TO authenticated USING (true);

ALTER TABLE push_queue ENABLE ROW LEVEL SECURITY;
CREATE POLICY "push_all" ON push_queue FOR ALL TO authenticated USING (true);

ALTER TABLE draft_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "draft_notif_all" ON draft_notifications FOR ALL TO authenticated USING (true);

ALTER TABLE driver_push_sent ENABLE ROW LEVEL SECURITY;
CREATE POLICY "driver_push_all" ON driver_push_sent FOR ALL TO authenticated USING (true);

ALTER TABLE waiting_list ENABLE ROW LEVEL SECURITY;
CREATE POLICY "waiting_all" ON waiting_list FOR ALL TO authenticated USING (true);

-- ── GIG OFFERS (replace overpermissive) ──────────────────
DROP POLICY IF EXISTS "Auth full access gig_offers" ON gig_offers;
DROP POLICY IF EXISTS "Auth full access" ON gig_offers;
CREATE POLICY "gig_offers_select" ON gig_offers FOR SELECT TO authenticated
  USING (company_id IN (SELECT my_company_ids()));
CREATE POLICY "gig_offers_modify" ON gig_offers FOR ALL TO authenticated
  USING (is_admin_in(company_id));

DROP POLICY IF EXISTS "Auth full access gig_offer_shows" ON gig_offer_shows;
DROP POLICY IF EXISTS "Auth full access" ON gig_offer_shows;
CREATE POLICY "gig_offer_shows_select" ON gig_offer_shows FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM gig_offers go WHERE go.id = gig_offer_shows.offer_id AND go.company_id IN (SELECT my_company_ids())));
CREATE POLICY "gig_offer_shows_modify" ON gig_offer_shows FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM gig_offers go WHERE go.id = gig_offer_shows.offer_id AND is_admin_in(go.company_id)));

DROP POLICY IF EXISTS "Auth full access gig_offer_gigs" ON gig_offer_gigs;
DROP POLICY IF EXISTS "Auth full access" ON gig_offer_gigs;
CREATE POLICY "gig_offer_gigs_select" ON gig_offer_gigs FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM gig_offers go WHERE go.id = gig_offer_gigs.offer_id AND go.company_id IN (SELECT my_company_ids())));
CREATE POLICY "gig_offer_gigs_modify" ON gig_offer_gigs FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM gig_offers go WHERE go.id = gig_offer_gigs.offer_id AND is_admin_in(go.company_id)));

DROP POLICY IF EXISTS "Auth full access offer_versions" ON offer_versions;
DROP POLICY IF EXISTS "Auth full access" ON offer_versions;
CREATE POLICY "offer_versions_select" ON offer_versions FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM gig_offers go WHERE go.id = offer_versions.offer_id AND go.company_id IN (SELECT my_company_ids())));
CREATE POLICY "offer_versions_modify" ON offer_versions FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM gig_offers go WHERE go.id = offer_versions.offer_id AND is_admin_in(go.company_id)));

-- ── MICROSOFT OAUTH TOKENS ───────────────────────────────
DROP POLICY IF EXISTS "Auth full access" ON microsoft_oauth_tokens;
DROP POLICY IF EXISTS "Auth full access microsoft_oauth_tokens" ON microsoft_oauth_tokens;
CREATE POLICY "oauth_modify" ON microsoft_oauth_tokens FOR ALL TO authenticated
  USING (is_admin_in(company_id));

-- ── CSS OFFERS (owner_company_id) ────────────────────────
DROP POLICY IF EXISTS "Allow delete offers" ON offers;
DROP POLICY IF EXISTS "Authenticated users can delete offers" ON offers;
DROP POLICY IF EXISTS "Authenticated users can insert offers" ON offers;
DROP POLICY IF EXISTS "Authenticated users can update offers" ON offers;
CREATE POLICY "offers_select" ON offers FOR SELECT TO authenticated
  USING (owner_company_id IN (SELECT my_company_ids()));
CREATE POLICY "offers_modify" ON offers FOR ALL TO authenticated
  USING (is_admin_in(owner_company_id));

-- ── OFFER/AGREEMENT TOKENS (anon needs read+update for acceptance links) ──
-- Keep existing anon SELECT policies, tighten INSERT/UPDATE/DELETE
DROP POLICY IF EXISTS "Anon can update offer_tokens" ON offer_tokens;
DROP POLICY IF EXISTS "Authenticated users can insert offer_tokens" ON offer_tokens;
DROP POLICY IF EXISTS "Authenticated users can update offer_tokens" ON offer_tokens;
DROP POLICY IF EXISTS "Authenticated users can delete offer_tokens" ON offer_tokens;
CREATE POLICY "offer_tokens_admin_insert" ON offer_tokens FOR INSERT TO authenticated WITH CHECK (is_any_admin());
CREATE POLICY "offer_tokens_admin_update" ON offer_tokens FOR UPDATE TO authenticated USING (is_any_admin());
CREATE POLICY "offer_tokens_admin_delete" ON offer_tokens FOR DELETE TO authenticated USING (is_any_admin());
CREATE POLICY "offer_tokens_anon_update" ON offer_tokens FOR UPDATE TO anon USING (true) WITH CHECK (status IN ('accepted'));

DROP POLICY IF EXISTS "Anon can update agreement_tokens" ON agreement_tokens;
DROP POLICY IF EXISTS "Authenticated users can insert agreement_tokens" ON agreement_tokens;
DROP POLICY IF EXISTS "Authenticated users can update agreement_tokens" ON agreement_tokens;
CREATE POLICY "agreement_tokens_admin_insert" ON agreement_tokens FOR INSERT TO authenticated WITH CHECK (is_any_admin());
CREATE POLICY "agreement_tokens_admin_update" ON agreement_tokens FOR UPDATE TO authenticated USING (is_any_admin());
CREATE POLICY "agreement_tokens_anon_update" ON agreement_tokens FOR UPDATE TO anon USING (true) WITH CHECK (status IN ('accepted'));

-- ── FIX gig_messages UPDATE ──────────────────────────────
DROP POLICY IF EXISTS "Authenticated users can update gig_messages" ON gig_messages;
CREATE POLICY "gig_msg_update_own" ON gig_messages FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- ── CALENDAR ATTACHMENTS (tighten) ───────────────────────
DROP POLICY IF EXISTS "Authenticated users can delete calendar attachments" ON calendar_attachments;
DROP POLICY IF EXISTS "Authenticated users can insert calendar attachments" ON calendar_attachments;
CREATE POLICY "cal_attach_insert" ON calendar_attachments FOR INSERT TO authenticated WITH CHECK (is_any_admin());
CREATE POLICY "cal_attach_delete" ON calendar_attachments FOR DELETE TO authenticated USING (is_any_admin());

DROP POLICY IF EXISTS "Authenticated users can delete boarding passes" ON calendar_boarding_passes;
DROP POLICY IF EXISTS "Authenticated users can insert boarding passes" ON calendar_boarding_passes;
CREATE POLICY "boarding_insert" ON calendar_boarding_passes FOR INSERT TO authenticated WITH CHECK (is_any_admin());
CREATE POLICY "boarding_delete" ON calendar_boarding_passes FOR DELETE TO authenticated USING (is_any_admin());

-- ── ISSUES TABLE ─────────────────────────────────────────
DROP POLICY IF EXISTS "Authenticated users can delete issues" ON issues;
DROP POLICY IF EXISTS "Authenticated users can update issues" ON issues;
CREATE POLICY "issues_tbl_update" ON issues FOR UPDATE TO authenticated USING (is_any_admin());
CREATE POLICY "issues_tbl_delete" ON issues FOR DELETE TO authenticated USING (is_any_admin());

-- ── VIEWS: SECURITY INVOKER ──────────────────────────────
DROP VIEW IF EXISTS v_turer_app;
CREATE VIEW v_turer_app WITH (security_invoker = true) AS
  SELECT id AS app_id, draft_id, dato, sted, venue, adresse, km,
         distance_total_km, tid, produksjon, kjoretoy, sjafor, d_drive,
         status, kilde, getin, kommentarer, vedlegg, contact,
         contact_name, contact_phone, contact_email, owner_company_id
  FROM samletdata;

DROP VIEW IF EXISTS finance_offers;
CREATE VIEW finance_offers WITH (security_invoker = true) AS
  SELECT go.*, g.date_from, g.venue_name, g.customer_firma AS gig_customer_firma
  FROM gig_offers go LEFT JOIN gigs g ON g.id = go.gig_id;

DROP VIEW IF EXISTS v_companies_full;
CREATE VIEW v_companies_full WITH (security_invoker = true) AS
  SELECT * FROM companies;
