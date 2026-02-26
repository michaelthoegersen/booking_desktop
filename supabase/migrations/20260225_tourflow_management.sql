-- TourFlow Management schema
-- Koble brukere til management-selskap

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES companies(id),
  ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'user';

-- Turnéer
CREATE TABLE IF NOT EXISTS management_tours (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name        text NOT NULL,
  artist      text NOT NULL,
  status      text NOT NULL DEFAULT 'planning',
  tour_start  date,
  tour_end    date,
  notes       text,
  created_by  uuid REFERENCES auth.users(id),
  created_at  timestamptz DEFAULT now(),
  updated_at  timestamptz DEFAULT now()
);

-- Shows
CREATE TABLE IF NOT EXISTS management_shows (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tour_id         uuid NOT NULL REFERENCES management_tours(id) ON DELETE CASCADE,
  date            date NOT NULL,
  venue_name      text,
  city            text,
  country         text DEFAULT 'NO',
  status          text DEFAULT 'confirmed',
  capacity        integer,
  notes           text,
  needs_nightliner boolean DEFAULT false,
  nightliner_from date,
  nightliner_to   date,
  bus_request_id  uuid,
  sort_order      integer DEFAULT 0,
  created_at      timestamptz DEFAULT now()
);

-- Team
CREATE TABLE IF NOT EXISTS management_team (
  id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tour_id  uuid NOT NULL REFERENCES management_tours(id) ON DELETE CASCADE,
  user_id  uuid REFERENCES auth.users(id),
  name     text NOT NULL,
  email    text,
  phone    text,
  role     text,
  notes    text,
  created_at timestamptz DEFAULT now()
);

-- Itinerary
CREATE TABLE IF NOT EXISTS management_itinerary (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tour_id     uuid NOT NULL REFERENCES management_tours(id) ON DELETE CASCADE,
  show_id     uuid REFERENCES management_shows(id),
  date        date NOT NULL,
  time        time,
  type        text,
  description text NOT NULL,
  location    text,
  notes       text,
  sort_order  integer DEFAULT 0,
  created_at  timestamptz DEFAULT now()
);

-- Bus requests
CREATE TABLE IF NOT EXISTS bus_requests (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES companies(id),
  tour_id     uuid REFERENCES management_tours(id),
  show_id     uuid REFERENCES management_shows(id),
  date_from   date NOT NULL,
  date_to     date NOT NULL,
  from_city   text,
  to_city     text,
  pax         integer,
  notes       text,
  status      text DEFAULT 'pending',
  offer_id    uuid,
  created_at  timestamptz DEFAULT now()
);

-- Indekser
CREATE INDEX IF NOT EXISTS idx_management_tours_company   ON management_tours(company_id);
CREATE INDEX IF NOT EXISTS idx_management_shows_tour      ON management_shows(tour_id);
CREATE INDEX IF NOT EXISTS idx_management_team_tour       ON management_team(tour_id);
CREATE INDEX IF NOT EXISTS idx_management_itinerary_tour  ON management_itinerary(tour_id);
CREATE INDEX IF NOT EXISTS idx_bus_requests_company       ON bus_requests(company_id);
CREATE INDEX IF NOT EXISTS idx_bus_requests_status        ON bus_requests(status);
