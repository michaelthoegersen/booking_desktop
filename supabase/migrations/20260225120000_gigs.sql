-- ============================================================
-- TourFlow — Gig Management for Complete Drums
-- ============================================================

-- Show-typer (predefinerte Complete Drums-show)
CREATE TABLE IF NOT EXISTS show_types (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid REFERENCES companies(id),
  name        text NOT NULL,
  drummers    integer DEFAULT 0,
  dancers     integer DEFAULT 0,
  others      integer DEFAULT 0,
  price       numeric(10,2) DEFAULT 0,
  sort_order  integer DEFAULT 0,
  active      boolean DEFAULT true
);

INSERT INTO show_types (name, drummers, dancers, price, sort_order) VALUES
  ('Complete Show',        8,  0, 47000, 1),
  ('LondonShow',           7,  1, 30000, 2),
  ('CI-2 (event)',        11,  8, 90000, 3),
  ('CI-3',                11,  8,     0, 4),
  ('Maskedans',            8,  0,     0, 5),
  ('Forsoningen (CI-4)',   4,  4,     0, 6),
  ('CI-2 (tattoo)',       12, 12,     0, 7),
  ('Bøtteshow',           4,  0,     0, 8)
ON CONFLICT DO NOTHING;

-- Giger
CREATE TABLE IF NOT EXISTS gigs (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id       uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  date_from        date NOT NULL,
  date_to          date,
  venue_name       text,
  city             text,
  country          text DEFAULT 'NO',
  customer_firma   text,
  customer_name    text,
  customer_phone   text,
  customer_email   text,
  customer_org_nr  text,
  customer_address text,
  invoice_on_ehf   boolean DEFAULT false,
  responsible      text,
  show_desc        text,
  meeting_time     time,
  get_in_time      time,
  rehearsal_time   time,
  performance_time time,
  get_out_time     time,
  meeting_notes    text,
  stage_shape      text,
  stage_size       text,
  stage_notes      text,
  inear_from_us    boolean DEFAULT false,
  playback_from_us boolean DEFAULT true,
  inear_price      numeric(10,2) DEFAULT 7000,
  transport_km     integer,
  transport_price  numeric(10,2),
  extra_desc       text,
  extra_price      numeric(10,2),
  notes_for_contract  text,
  info_from_organizer text,
  status           text DEFAULT 'inquiry',
  created_by       uuid REFERENCES auth.users(id),
  created_at       timestamptz DEFAULT now(),
  updated_at       timestamptz DEFAULT now()
);

-- Show-valg per gig
CREATE TABLE IF NOT EXISTS gig_shows (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gig_id       uuid NOT NULL REFERENCES gigs(id) ON DELETE CASCADE,
  show_type_id uuid REFERENCES show_types(id),
  show_name    text NOT NULL,
  drummers     integer DEFAULT 0,
  dancers      integer DEFAULT 0,
  others       integer DEFAULT 0,
  price        numeric(10,2) DEFAULT 0,
  sort_order   integer DEFAULT 0
);

-- Crew-tilgjengelighet (som Trello-checklist)
CREATE TABLE IF NOT EXISTS gig_crew (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gig_id     uuid NOT NULL REFERENCES gigs(id) ON DELETE CASCADE,
  name       text NOT NULL,
  role       text,
  confirmed  boolean DEFAULT false,
  notes      text,
  sort_order integer DEFAULT 0
);

-- Kommentarer / aktivitetslogg
CREATE TABLE IF NOT EXISTS gig_comments (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gig_id      uuid NOT NULL REFERENCES gigs(id) ON DELETE CASCADE,
  user_id     uuid REFERENCES auth.users(id),
  author_name text,
  content     text NOT NULL,
  created_at  timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_gigs_company  ON gigs(company_id);
CREATE INDEX IF NOT EXISTS idx_gigs_date     ON gigs(date_from);
CREATE INDEX IF NOT EXISTS idx_gig_shows_gig ON gig_shows(gig_id);
CREATE INDEX IF NOT EXISTS idx_gig_crew_gig  ON gig_crew(gig_id);
