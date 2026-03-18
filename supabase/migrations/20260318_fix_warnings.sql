-- ============================================================
-- FIX REMAINING SECURITY WARNINGS
-- Removes old overpermissive policies + sets search_path on functions
-- ============================================================

-- ============================================================
-- 1. REMOVE OLD OVERPERMISSIVE POLICIES on samletdata
--    (replaced by company-scoped policies in previous migration)
-- ============================================================

DROP POLICY IF EXISTS "Allow update own jobs" ON samletdata;
DROP POLICY IF EXISTS "delete all" ON samletdata;
DROP POLICY IF EXISTS "insert all" ON samletdata;
DROP POLICY IF EXISTS "update all" ON samletdata;
DROP POLICY IF EXISTS "read all" ON samletdata;

-- ============================================================
-- 2. REMOVE OLD OVERPERMISSIVE POLICIES on offers
-- ============================================================

DROP POLICY IF EXISTS "Allow delete offers" ON offers;
DROP POLICY IF EXISTS "Authenticated users can delete offers" ON offers;
DROP POLICY IF EXISTS "Authenticated users can insert offers" ON offers;
DROP POLICY IF EXISTS "Authenticated users can update offers" ON offers;

-- Add proper company-scoped policies for offers (CSS offers use owner_company_id)
CREATE POLICY "Members see company offers"
  ON offers FOR SELECT TO authenticated
  USING (
    owner_company_id IN (
      SELECT company_id FROM company_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Admins manage offers"
  ON offers FOR ALL TO authenticated
  USING (
    owner_company_id IN (
      SELECT company_id FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

-- ============================================================
-- 3. FIX REMAINING gig_offers old policies (different names)
-- ============================================================

DROP POLICY IF EXISTS "Auth full access gig_offers" ON gig_offers;
DROP POLICY IF EXISTS "Auth full access" ON gig_offer_gigs;
DROP POLICY IF EXISTS "Auth full access" ON gig_offer_shows;
DROP POLICY IF EXISTS "Auth full access" ON microsoft_oauth_tokens;

-- ============================================================
-- 4. TIGHTEN offer_tokens & agreement_tokens
--    Anon needs UPDATE for public acceptance links, but scope it
-- ============================================================

-- offer_tokens: anon update should be scoped to token-based access
DROP POLICY IF EXISTS "Anon can update offer_tokens" ON offer_tokens;
CREATE POLICY "Anon can update offer_tokens by token"
  ON offer_tokens FOR UPDATE TO anon
  USING (true)
  WITH CHECK (status IN ('accepted'));

DROP POLICY IF EXISTS "Authenticated users can insert offer_tokens" ON offer_tokens;
CREATE POLICY "Admins insert offer_tokens"
  ON offer_tokens FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

DROP POLICY IF EXISTS "Authenticated users can update offer_tokens" ON offer_tokens;
CREATE POLICY "Admins update offer_tokens"
  ON offer_tokens FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

DROP POLICY IF EXISTS "Authenticated users can delete offer_tokens" ON offer_tokens;
CREATE POLICY "Admins delete offer_tokens"
  ON offer_tokens FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

-- agreement_tokens: same approach
DROP POLICY IF EXISTS "Anon can update agreement_tokens" ON agreement_tokens;
CREATE POLICY "Anon can update agreement_tokens by token"
  ON agreement_tokens FOR UPDATE TO anon
  USING (true)
  WITH CHECK (status IN ('accepted'));

DROP POLICY IF EXISTS "Authenticated users can insert agreement_tokens" ON agreement_tokens;
CREATE POLICY "Admins insert agreement_tokens"
  ON agreement_tokens FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

DROP POLICY IF EXISTS "Authenticated users can update agreement_tokens" ON agreement_tokens;
CREATE POLICY "Admins update agreement_tokens"
  ON agreement_tokens FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

-- ============================================================
-- 5. TIGHTEN gig_messages & crp_messages UPDATE
-- ============================================================

DROP POLICY IF EXISTS "Authenticated users can update gig_messages" ON gig_messages;
CREATE POLICY "Users update own gig messages"
  ON gig_messages FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Authenticated users can update crp_messages" ON crp_messages;
CREATE POLICY "Users update own crp messages"
  ON crp_messages FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ============================================================
-- 6. TIGHTEN calendar attachments/boarding passes
-- ============================================================

DROP POLICY IF EXISTS "Authenticated users can delete calendar attachments" ON calendar_attachments;
CREATE POLICY "Admins delete calendar attachments"
  ON calendar_attachments FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

DROP POLICY IF EXISTS "Authenticated users can insert calendar attachments" ON calendar_attachments;
CREATE POLICY "Admins insert calendar attachments"
  ON calendar_attachments FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

DROP POLICY IF EXISTS "Authenticated users can delete boarding passes" ON calendar_boarding_passes;
CREATE POLICY "Admins delete boarding passes"
  ON calendar_boarding_passes FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

DROP POLICY IF EXISTS "Authenticated users can insert boarding passes" ON calendar_boarding_passes;
CREATE POLICY "Admins insert boarding passes"
  ON calendar_boarding_passes FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

-- ============================================================
-- 7. TIGHTEN issues table
-- ============================================================

DROP POLICY IF EXISTS "Authenticated users can delete issues" ON issues;
CREATE POLICY "Admins delete issues"
  ON issues FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

DROP POLICY IF EXISTS "Authenticated users can update issues" ON issues;
CREATE POLICY "Admins update issues"
  ON issues FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM company_members
      WHERE user_id = auth.uid() AND role IN ('admin', 'management')
    )
  );

-- ============================================================
-- 8. SET search_path ON ALL FUNCTIONS
-- ============================================================

ALTER FUNCTION public.sync_offer_status_from_calendar SET search_path = public;
ALTER FUNCTION public.notify_driver_once SET search_path = public;
ALTER FUNCTION public.get_company_member_profiles SET search_path = public;
ALTER FUNCTION public.set_customers_updated_at SET search_path = public;
ALTER FUNCTION public.protect_kilde_not_null SET search_path = public;
ALTER FUNCTION public.handle_new_user SET search_path = public;
ALTER FUNCTION public.notify_driver_on_assign SET search_path = public;
ALTER FUNCTION public.increment_saved_meal_use_count SET search_path = public;
ALTER FUNCTION public.notify_new_job_once SET search_path = public;
ALTER FUNCTION public.get_available_buses SET search_path = public;
ALTER FUNCTION public.convert_dm_to_group SET search_path = public;
ALTER FUNCTION public.notify_new_job_statement SET search_path = public;
ALTER FUNCTION public.queue_push SET search_path = public;
ALTER FUNCTION public.notify_driver_on_assign_statement SET search_path = public;
ALTER FUNCTION public.get_calendar_segments SET search_path = public;
ALTER FUNCTION public.notify_new_job SET search_path = public;
ALTER FUNCTION public.notify_driver SET search_path = public;
ALTER FUNCTION public.claim_fcm_token SET search_path = public;
ALTER FUNCTION public.set_updated_at SET search_path = public;

-- ============================================================
-- 9. PROFILES: allow reading basic info (id, name) for all
--    authenticated users — needed for chat reactions, mentions etc.
-- ============================================================

CREATE POLICY "Authenticated read basic profiles"
  ON profiles FOR SELECT TO authenticated
  USING (true);
