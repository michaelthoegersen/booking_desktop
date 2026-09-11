-- is_leader_in() leste kun company_members.role, men rollen redigeres kun i
-- profiles.role (mgmt_settings_page skriver aldri til company_members).
-- Gruppeledere forfremmet etter opprettelse ble derfor aldri gjenkjent, og
-- gigs_update-policyen blokkerte dem stille.
--
-- Utvider funksjonen til å godta rollen fra BEGGE kildene. Funksjonen brukes
-- kun av policyen "gigs_update" — ingen andre policyer påvirkes.

CREATE OR REPLACE FUNCTION public.is_leader_in(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM company_members cm
    WHERE cm.user_id = auth.uid()
      AND cm.company_id = p_company_id
      AND cm.role IN ('gruppeleder_skarp', 'gruppeleder_bass')
  )
  OR EXISTS (
    -- Rollen appene faktisk redigerer. Krever fortsatt medlemskap i selskapet,
    -- så ingen tilgang på tvers av selskaper.
    SELECT 1 FROM profiles p
    JOIN company_members cm2
      ON cm2.user_id = p.id AND cm2.company_id = p_company_id
    WHERE p.id = auth.uid()
      AND p.role IN ('gruppeleder_skarp', 'gruppeleder_bass')
  );
$$;
