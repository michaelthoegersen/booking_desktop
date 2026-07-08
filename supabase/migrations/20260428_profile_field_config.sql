-- Per-company configurable profile fields that all members fill in via the mobile app.
-- Hovedbolker (sections) have parent_id = NULL.
-- Underbolker (fields) reference a hovedbolk via parent_id.

CREATE TABLE IF NOT EXISTS profile_field_config (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  parent_id   uuid REFERENCES profile_field_config(id) ON DELETE CASCADE,
  title       text NOT NULL,
  field_type  text NOT NULL DEFAULT 'text'
              CHECK (field_type IN ('section','text','longtext','number','date','bool','dropdown')),
  options     jsonb,                        -- choices for field_type = 'dropdown'
  required    boolean NOT NULL DEFAULT false,
  sort_order  integer NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_profile_field_config_company
  ON profile_field_config(company_id);
CREATE INDEX IF NOT EXISTS idx_profile_field_config_parent
  ON profile_field_config(parent_id);

ALTER TABLE profile_field_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profile_field_config_select"
  ON profile_field_config FOR SELECT TO authenticated
  USING (company_id IN (SELECT my_company_ids()));

CREATE POLICY "profile_field_config_insert"
  ON profile_field_config FOR INSERT TO authenticated
  WITH CHECK (is_admin_in(company_id));

CREATE POLICY "profile_field_config_update"
  ON profile_field_config FOR UPDATE TO authenticated
  USING (is_admin_in(company_id));

CREATE POLICY "profile_field_config_delete"
  ON profile_field_config FOR DELETE TO authenticated
  USING (is_admin_in(company_id));

-- Per-user values for the configured fields (filled in via the mobile app).
CREATE TABLE IF NOT EXISTS profile_field_values (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id  uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  field_id    uuid NOT NULL REFERENCES profile_field_config(id) ON DELETE CASCADE,
  value       text,                          -- stored as text; client casts based on field_type
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (profile_id, field_id)
);

CREATE INDEX IF NOT EXISTS idx_profile_field_values_profile
  ON profile_field_values(profile_id);
CREATE INDEX IF NOT EXISTS idx_profile_field_values_field
  ON profile_field_values(field_id);

ALTER TABLE profile_field_values ENABLE ROW LEVEL SECURITY;

-- Members can read/write their own answers; admins in the same company can read all.
CREATE POLICY "profile_field_values_select_own_or_admin"
  ON profile_field_values FOR SELECT TO authenticated
  USING (
    profile_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM profile_field_config c
      WHERE c.id = profile_field_values.field_id
        AND is_admin_in(c.company_id)
    )
  );

CREATE POLICY "profile_field_values_upsert_own"
  ON profile_field_values FOR INSERT TO authenticated
  WITH CHECK (profile_id = auth.uid());

CREATE POLICY "profile_field_values_update_own"
  ON profile_field_values FOR UPDATE TO authenticated
  USING (profile_id = auth.uid());

CREATE POLICY "profile_field_values_delete_own"
  ON profile_field_values FOR DELETE TO authenticated
  USING (profile_id = auth.uid());
