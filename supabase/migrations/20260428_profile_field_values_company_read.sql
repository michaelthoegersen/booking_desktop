-- Allow same-company members to read each other's profile field values
-- (so contact-profile views in the mobile app can show what others have filled in).
DROP POLICY IF EXISTS "profile_field_values_select_own_or_admin"
  ON profile_field_values;

CREATE POLICY "profile_field_values_select_company"
  ON profile_field_values FOR SELECT TO authenticated
  USING (
    profile_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM profile_field_config c
      WHERE c.id = profile_field_values.field_id
        AND c.company_id IN (SELECT my_company_ids())
    )
  );
