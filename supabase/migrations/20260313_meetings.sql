-- ============================================================
-- MEETINGS SYSTEM
-- ============================================================

-- 1. meetings
CREATE TABLE IF NOT EXISTS meetings (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  title       text NOT NULL,
  date        date NOT NULL,
  start_time  time,
  end_time    time,
  address     text,
  postal_code text,
  city        text,
  comment     text,
  status      text NOT NULL DEFAULT 'draft',  -- draft, finalized, in_progress, completed
  created_by  uuid REFERENCES auth.users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_meetings_company ON meetings(company_id);
CREATE INDEX idx_meetings_date    ON meetings(date);

-- 2. meeting_participants
CREATE TABLE IF NOT EXISTS meeting_participants (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id  uuid NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rsvp_status text NOT NULL DEFAULT 'pending',  -- pending, attending, not_attending
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE(meeting_id, user_id)
);

CREATE INDEX idx_meeting_participants_meeting ON meeting_participants(meeting_id);

-- 3. meeting_agenda_items
CREATE TABLE IF NOT EXISTS meeting_agenda_items (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id  uuid NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
  title       text NOT NULL,
  item_type   text NOT NULL DEFAULT 'none',  -- none, other, information, decision
  description text,
  assigned_to uuid REFERENCES auth.users(id),
  notes       text,  -- referat
  sort_order  int NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_meeting_agenda_items_meeting ON meeting_agenda_items(meeting_id);

-- 4. meeting_agenda_files
CREATE TABLE IF NOT EXISTS meeting_agenda_files (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agenda_item_id  uuid NOT NULL REFERENCES meeting_agenda_items(id) ON DELETE CASCADE,
  file_url        text NOT NULL,
  file_name       text NOT NULL,
  file_size       bigint,
  content_type    text,
  uploaded_by     uuid REFERENCES auth.users(id),
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_meeting_agenda_files_item ON meeting_agenda_files(agenda_item_id);

-- 5. meeting_agenda_templates
CREATE TABLE IF NOT EXISTS meeting_agenda_templates (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  title       text NOT NULL,
  item_type   text NOT NULL DEFAULT 'none',
  description text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_meeting_agenda_templates_company ON meeting_agenda_templates(company_id);

-- 6. Storage bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('meeting-attachments', 'meeting-attachments', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policy: authenticated users can upload
CREATE POLICY "Authenticated users can upload meeting attachments"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'meeting-attachments');

CREATE POLICY "Anyone can read meeting attachments"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'meeting-attachments');

CREATE POLICY "Authenticated users can delete own meeting attachments"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'meeting-attachments');

-- RLS policies
ALTER TABLE meetings ENABLE ROW LEVEL SECURITY;
ALTER TABLE meeting_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE meeting_agenda_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE meeting_agenda_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE meeting_agenda_templates ENABLE ROW LEVEL SECURITY;

-- meetings: company members can read/write
CREATE POLICY "Company members can manage meetings"
ON meetings FOR ALL TO authenticated
USING (company_id IN (
  SELECT company_id FROM company_members WHERE user_id = auth.uid()
))
WITH CHECK (company_id IN (
  SELECT company_id FROM company_members WHERE user_id = auth.uid()
));

-- meeting_participants: accessible if you can access the meeting
CREATE POLICY "Access meeting participants via meeting"
ON meeting_participants FOR ALL TO authenticated
USING (meeting_id IN (
  SELECT id FROM meetings WHERE company_id IN (
    SELECT company_id FROM company_members WHERE user_id = auth.uid()
  )
))
WITH CHECK (meeting_id IN (
  SELECT id FROM meetings WHERE company_id IN (
    SELECT company_id FROM company_members WHERE user_id = auth.uid()
  )
));

-- meeting_agenda_items: accessible via meeting
CREATE POLICY "Access agenda items via meeting"
ON meeting_agenda_items FOR ALL TO authenticated
USING (meeting_id IN (
  SELECT id FROM meetings WHERE company_id IN (
    SELECT company_id FROM company_members WHERE user_id = auth.uid()
  )
))
WITH CHECK (meeting_id IN (
  SELECT id FROM meetings WHERE company_id IN (
    SELECT company_id FROM company_members WHERE user_id = auth.uid()
  )
));

-- meeting_agenda_files: accessible via agenda item
CREATE POLICY "Access agenda files via agenda item"
ON meeting_agenda_files FOR ALL TO authenticated
USING (agenda_item_id IN (
  SELECT id FROM meeting_agenda_items WHERE meeting_id IN (
    SELECT id FROM meetings WHERE company_id IN (
      SELECT company_id FROM company_members WHERE user_id = auth.uid()
    )
  )
))
WITH CHECK (agenda_item_id IN (
  SELECT id FROM meeting_agenda_items WHERE meeting_id IN (
    SELECT id FROM meetings WHERE company_id IN (
      SELECT company_id FROM company_members WHERE user_id = auth.uid()
    )
  )
));

-- meeting_agenda_templates: company access
CREATE POLICY "Company members can manage agenda templates"
ON meeting_agenda_templates FOR ALL TO authenticated
USING (company_id IN (
  SELECT company_id FROM company_members WHERE user_id = auth.uid()
))
WITH CHECK (company_id IN (
  SELECT company_id FROM company_members WHERE user_id = auth.uid()
));
