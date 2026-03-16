-- Calendar boarding passes (flight tickets)
CREATE TABLE calendar_boarding_passes (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  samletdata_id text NOT NULL,
  passenger_name text NOT NULL,
  from_airport text NOT NULL,
  to_airport text NOT NULL,
  flight_number text NOT NULL,
  flight_date date NOT NULL,
  seat text,
  pnr text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE calendar_boarding_passes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read boarding passes"
  ON calendar_boarding_passes FOR SELECT
  TO authenticated USING (true);

CREATE POLICY "Authenticated users can insert boarding passes"
  ON calendar_boarding_passes FOR INSERT
  TO authenticated WITH CHECK (true);

CREATE POLICY "Authenticated users can delete boarding passes"
  ON calendar_boarding_passes FOR DELETE
  TO authenticated USING (true);

-- Calendar attachments (files/images/PDFs)
CREATE TABLE calendar_attachments (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  samletdata_id text NOT NULL,
  file_url text NOT NULL,
  file_name text NOT NULL,
  file_type text NOT NULL DEFAULT 'file',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE calendar_attachments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read calendar attachments"
  ON calendar_attachments FOR SELECT
  TO authenticated USING (true);

CREATE POLICY "Authenticated users can insert calendar attachments"
  ON calendar_attachments FOR INSERT
  TO authenticated WITH CHECK (true);

CREATE POLICY "Authenticated users can delete calendar attachments"
  ON calendar_attachments FOR DELETE
  TO authenticated USING (true);
