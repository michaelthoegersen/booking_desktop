-- ============================================================
-- ENABLE RLS + POLICIES FOR ALL PUBLIC TABLES
-- Fixes 39 security warnings from Supabase Security Advisor
-- ============================================================

-- Helper: most tables use company_id isolation via company_members.
-- Users can only see data for companies they belong to.

-- ============================================================
-- 1. CORE TABLES — enable RLS + add policies
-- ============================================================

-- PROFILES
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own profile"
  ON profiles FOR SELECT TO authenticated
  USING (id = auth.uid());

CREATE POLICY "Users read company members profiles"
  ON profiles FOR SELECT TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM company_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users update own profile"
  ON profiles FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- COMPANIES
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can read own companies"
  ON companies FOR SELECT TO authenticated
  USING (
    id IN (SELECT company_id FROM company_members WHERE user_id = auth.uid())
  );

CREATE POLICY "Admins can update own companies"
  ON companies FOR UPDATE TO authenticated
  USING (
    id IN (
      SELECT company_id FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

-- ============================================================
-- 2. GIG TABLES — company_id isolation
-- ============================================================

ALTER TABLE gigs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members see company gigs"
  ON gigs FOR SELECT TO authenticated
  USING (
    company_id IN (SELECT company_id FROM company_members WHERE user_id = auth.uid())
  );

CREATE POLICY "Admins manage company gigs"
  ON gigs FOR ALL TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

-- GIG_CREW (no company_id — join via gigs)
ALTER TABLE gig_crew ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members see gig crew"
  ON gig_crew FOR SELECT TO authenticated
  USING (
    gig_id IN (
      SELECT id FROM gigs WHERE company_id IN (
        SELECT company_id FROM company_members WHERE user_id = auth.uid()
      )
    )
  );

CREATE POLICY "Admins manage gig crew"
  ON gig_crew FOR ALL TO authenticated
  USING (
    gig_id IN (
      SELECT id FROM gigs WHERE company_id IN (
        SELECT company_id FROM company_members
        WHERE user_id = auth.uid() AND role IN ('admin', 'management')
      )
    )
  );

-- GIG_SHOWS (no company_id — join via gigs)
ALTER TABLE gig_shows ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members see gig shows"
  ON gig_shows FOR SELECT TO authenticated
  USING (
    gig_id IN (
      SELECT id FROM gigs WHERE company_id IN (
        SELECT company_id FROM company_members WHERE user_id = auth.uid()
      )
    )
  );

CREATE POLICY "Admins manage gig shows"
  ON gig_shows FOR ALL TO authenticated
  USING (
    gig_id IN (
      SELECT id FROM gigs WHERE company_id IN (
        SELECT company_id FROM company_members
        WHERE user_id = auth.uid() AND role IN ('admin', 'management')
      )
    )
  );

-- GIG_COMMENTS (no company_id — join via gigs)
ALTER TABLE gig_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members see gig comments"
  ON gig_comments FOR SELECT TO authenticated
  USING (
    gig_id IN (
      SELECT id FROM gigs WHERE company_id IN (
        SELECT company_id FROM company_members WHERE user_id = auth.uid()
      )
    )
  );

CREATE POLICY "Members insert own gig comments"
  ON gig_comments FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid() AND
    gig_id IN (
      SELECT id FROM gigs WHERE company_id IN (
        SELECT company_id FROM company_members WHERE user_id = auth.uid()
      )
    )
  );

CREATE POLICY "Users delete own gig comments"
  ON gig_comments FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- SHOW_TYPES (company-scoped)
ALTER TABLE show_types ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members see company show types"
  ON show_types FOR SELECT TO authenticated
  USING (
    company_id IS NULL OR
    company_id IN (SELECT company_id FROM company_members WHERE user_id = auth.uid())
  );

CREATE POLICY "Admins manage show types"
  ON show_types FOR ALL TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

-- ============================================================
-- 3. MANAGEMENT/TOUR TABLES
-- ============================================================

ALTER TABLE management_tours ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members see company tours"
  ON management_tours FOR SELECT TO authenticated
  USING (
    company_id IN (SELECT company_id FROM company_members WHERE user_id = auth.uid())
  );

CREATE POLICY "Admins manage company tours"
  ON management_tours FOR ALL TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

ALTER TABLE management_shows ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members see tour shows"
  ON management_shows FOR SELECT TO authenticated
  USING (
    tour_id IN (
      SELECT id FROM management_tours WHERE company_id IN (
        SELECT company_id FROM company_members WHERE user_id = auth.uid()
      )
    )
  );

CREATE POLICY "Admins manage tour shows"
  ON management_shows FOR ALL TO authenticated
  USING (
    tour_id IN (
      SELECT id FROM management_tours WHERE company_id IN (
        SELECT company_id FROM company_members
        WHERE user_id = auth.uid() AND role IN ('admin', 'management')
      )
    )
  );

ALTER TABLE management_team ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members see tour team"
  ON management_team FOR SELECT TO authenticated
  USING (
    tour_id IN (
      SELECT id FROM management_tours WHERE company_id IN (
        SELECT company_id FROM company_members WHERE user_id = auth.uid()
      )
    )
  );

CREATE POLICY "Admins manage tour team"
  ON management_team FOR ALL TO authenticated
  USING (
    tour_id IN (
      SELECT id FROM management_tours WHERE company_id IN (
        SELECT company_id FROM company_members
        WHERE user_id = auth.uid() AND role IN ('admin', 'management')
      )
    )
  );

ALTER TABLE management_itinerary ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members see tour itinerary"
  ON management_itinerary FOR SELECT TO authenticated
  USING (
    tour_id IN (
      SELECT id FROM management_tours WHERE company_id IN (
        SELECT company_id FROM company_members WHERE user_id = auth.uid()
      )
    )
  );

CREATE POLICY "Admins manage tour itinerary"
  ON management_itinerary FOR ALL TO authenticated
  USING (
    tour_id IN (
      SELECT id FROM management_tours WHERE company_id IN (
        SELECT company_id FROM company_members
        WHERE user_id = auth.uid() AND role IN ('admin', 'management')
      )
    )
  );

-- ============================================================
-- 4. BUS REQUESTS
-- ============================================================

ALTER TABLE bus_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members see company bus requests"
  ON bus_requests FOR SELECT TO authenticated
  USING (
    company_id IN (SELECT company_id FROM company_members WHERE user_id = auth.uid())
  );

CREATE POLICY "Admins manage bus requests"
  ON bus_requests FOR ALL TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

ALTER TABLE bus_request_gigs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members see bus request gigs"
  ON bus_request_gigs FOR SELECT TO authenticated
  USING (
    bus_request_id IN (
      SELECT id FROM bus_requests WHERE company_id IN (
        SELECT company_id FROM company_members WHERE user_id = auth.uid()
      )
    )
  );

CREATE POLICY "Admins manage bus request gigs"
  ON bus_request_gigs FOR ALL TO authenticated
  USING (
    bus_request_id IN (
      SELECT id FROM bus_requests WHERE company_id IN (
        SELECT company_id FROM company_members
        WHERE user_id = auth.uid() AND role IN ('admin', 'management')
      )
    )
  );

-- ============================================================
-- 5. LOOKUP/REFERENCE TABLES — read-only for authenticated
-- ============================================================

ALTER TABLE countries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read countries"
  ON countries FOR SELECT TO authenticated
  USING (true);

ALTER TABLE ferries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read ferries"
  ON ferries FOR SELECT TO authenticated
  USING (true);

ALTER TABLE country_vat_rates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read vat rates"
  ON country_vat_rates FOR SELECT TO authenticated
  USING (true);

-- ============================================================
-- 6. ROUTES (shared across companies for CSS)
-- ============================================================

ALTER TABLE routes_all ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read routes"
  ON routes_all FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admins manage routes"
  ON routes_all FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

ALTER TABLE routes_all_backup ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read routes backup"
  ON routes_all_backup FOR SELECT TO authenticated
  USING (true);

ALTER TABLE route_country_km_staging ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read route staging"
  ON route_country_km_staging FOR SELECT TO authenticated
  USING (true);

ALTER TABLE route_costs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read route costs"
  ON route_costs FOR SELECT TO authenticated
  USING (true);

-- ============================================================
-- 7. SAMLETDATA (tours data — uses owner_company_id)
-- ============================================================

ALTER TABLE samletdata ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members see company samletdata"
  ON samletdata FOR SELECT TO authenticated
  USING (
    owner_company_id IN (
      SELECT company_id FROM company_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Admins manage samletdata"
  ON samletdata FOR ALL TO authenticated
  USING (
    owner_company_id IN (
      SELECT company_id FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

-- ============================================================
-- 8. CRP_MESSAGES — enable RLS (policies exist but RLS was off)
-- ============================================================

ALTER TABLE crp_messages ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 9. OTHER TABLES
-- ============================================================

ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read contacts"
  ON contacts FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admins manage contacts"
  ON contacts FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members read customers"
  ON customers FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admins manage customers"
  ON customers FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

ALTER TABLE productions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read productions"
  ON productions FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admins manage productions"
  ON productions FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins manage invoices"
  ON invoices FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

ALTER TABLE issue_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members read issue reports"
  ON issue_reports FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Members insert issue reports"
  ON issue_reports FOR INSERT TO authenticated
  WITH CHECK (true);

CREATE POLICY "Admins manage issue reports"
  ON issue_reports FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

-- NOTIFICATION/PUSH TABLES
ALTER TABLE job_notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated manage job notifications"
  ON job_notifications FOR ALL TO authenticated
  USING (true);

ALTER TABLE push_queue ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated manage push queue"
  ON push_queue FOR ALL TO authenticated
  USING (true);

ALTER TABLE draft_notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated manage draft notifications"
  ON draft_notifications FOR ALL TO authenticated
  USING (true);

ALTER TABLE driver_push_sent ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated manage driver push"
  ON driver_push_sent FOR ALL TO authenticated
  USING (true);

ALTER TABLE waiting_list ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated manage waiting list"
  ON waiting_list FOR ALL TO authenticated
  USING (true);

-- ============================================================
-- 10. FIX OVERPERMISSIVE POLICIES on gig_offers
-- Replace "Auth full access" with company-scoped policies
-- ============================================================

DROP POLICY IF EXISTS "Auth full access" ON gig_offers;
DROP POLICY IF EXISTS "Auth full access gig_offer_shows" ON gig_offer_shows;
DROP POLICY IF EXISTS "Auth full access gig_offer_gigs" ON gig_offer_gigs;
DROP POLICY IF EXISTS "Auth full access offer_versions" ON offer_versions;
DROP POLICY IF EXISTS "Auth full access microsoft_oauth_tokens" ON microsoft_oauth_tokens;

CREATE POLICY "Members see company gig offers"
  ON gig_offers FOR SELECT TO authenticated
  USING (
    company_id IN (SELECT company_id FROM company_members WHERE user_id = auth.uid())
  );

CREATE POLICY "Admins manage gig offers"
  ON gig_offers FOR ALL TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

CREATE POLICY "Members see gig offer shows"
  ON gig_offer_shows FOR SELECT TO authenticated
  USING (
    offer_id IN (
      SELECT id FROM gig_offers WHERE company_id IN (
        SELECT company_id FROM company_members WHERE user_id = auth.uid()
      )
    )
  );

CREATE POLICY "Admins manage gig offer shows"
  ON gig_offer_shows FOR ALL TO authenticated
  USING (
    offer_id IN (
      SELECT id FROM gig_offers WHERE company_id IN (
        SELECT company_id FROM company_members
        WHERE user_id = auth.uid() AND role IN ('admin', 'management')
      )
    )
  );

CREATE POLICY "Members see gig offer gigs"
  ON gig_offer_gigs FOR SELECT TO authenticated
  USING (
    offer_id IN (
      SELECT id FROM gig_offers WHERE company_id IN (
        SELECT company_id FROM company_members WHERE user_id = auth.uid()
      )
    )
  );

CREATE POLICY "Admins manage gig offer gigs"
  ON gig_offer_gigs FOR ALL TO authenticated
  USING (
    offer_id IN (
      SELECT id FROM gig_offers WHERE company_id IN (
        SELECT company_id FROM company_members
        WHERE user_id = auth.uid() AND role IN ('admin', 'management')
      )
    )
  );

CREATE POLICY "Members see offer versions"
  ON offer_versions FOR SELECT TO authenticated
  USING (
    offer_id IN (
      SELECT id FROM gig_offers WHERE company_id IN (
        SELECT company_id FROM company_members WHERE user_id = auth.uid()
      )
    )
  );

CREATE POLICY "Admins manage offer versions"
  ON offer_versions FOR ALL TO authenticated
  USING (
    offer_id IN (
      SELECT id FROM gig_offers WHERE company_id IN (
        SELECT company_id FROM company_members
        WHERE user_id = auth.uid() AND role IN ('admin', 'management')
      )
    )
  );

CREATE POLICY "Admins manage oauth tokens"
  ON microsoft_oauth_tokens FOR ALL TO authenticated
  USING (
    company_id IN (
      SELECT company_id FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

-- ============================================================
-- 11. FIX SECURITY DEFINER VIEWS
-- Recreate as SECURITY INVOKER (uses caller's RLS)
-- ============================================================

DROP VIEW IF EXISTS v_turer_app;
CREATE VIEW v_turer_app WITH (security_invoker = true) AS
  SELECT
    id AS app_id,
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
    contact_email,
    owner_company_id
  FROM samletdata;

DROP VIEW IF EXISTS finance_offers;
CREATE VIEW finance_offers WITH (security_invoker = true) AS
  SELECT
    go.*,
    g.date_from,
    g.venue_name,
    g.customer_firma AS gig_customer_firma
  FROM gig_offers go
  LEFT JOIN gigs g ON g.id = go.gig_id;

DROP VIEW IF EXISTS v_companies_full;
CREATE VIEW v_companies_full WITH (security_invoker = true) AS
  SELECT * FROM companies;
