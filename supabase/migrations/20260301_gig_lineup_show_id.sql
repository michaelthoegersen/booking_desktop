-- Add show_id to gig_lineup so crew can be assigned per show
ALTER TABLE gig_lineup ADD COLUMN show_id uuid REFERENCES gig_shows(id) ON DELETE CASCADE;

-- Replace old unique constraint (gig_id, user_id) with (gig_id, user_id, show_id)
ALTER TABLE gig_lineup DROP CONSTRAINT IF EXISTS gig_lineup_gig_id_user_id_key;
ALTER TABLE gig_lineup ADD CONSTRAINT gig_lineup_gig_user_show_key UNIQUE (gig_id, user_id, show_id);
