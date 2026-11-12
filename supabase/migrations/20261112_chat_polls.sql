-- ============================================================
-- Chat polls (avstemminger i chat)
--
-- 20260310_chat_polls.sql ble aldri kjørt mot databasen, så
-- chat_polls / chat_poll_options / chat_poll_votes manglet helt.
-- PollService.createPoll kastet PGRST205 ("Could not find the table")
-- med en gang, og "Opprett"-knappen sto og spant.
--
-- Denne er idempotent og kan kjøres flere ganger.
-- ============================================================

-- -- chat_polls ----------------------------------------------
CREATE TABLE IF NOT EXISTS public.chat_polls (
  id         uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  question   text NOT NULL,
  created_by uuid NOT NULL REFERENCES public.profiles(id),
  created_at timestamptz DEFAULT now(),
  is_closed  boolean NOT NULL DEFAULT false
);

-- -- chat_poll_options ---------------------------------------
CREATE TABLE IF NOT EXISTS public.chat_poll_options (
  id       uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  poll_id  uuid NOT NULL REFERENCES public.chat_polls(id) ON DELETE CASCADE,
  label    text NOT NULL,
  position int NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS chat_poll_options_poll_id_idx
  ON public.chat_poll_options (poll_id);

-- -- chat_poll_votes -----------------------------------------
CREATE TABLE IF NOT EXISTS public.chat_poll_votes (
  id        uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  poll_id   uuid NOT NULL REFERENCES public.chat_polls(id) ON DELETE CASCADE,
  option_id uuid NOT NULL REFERENCES public.chat_poll_options(id) ON DELETE CASCADE,
  user_id   uuid NOT NULL REFERENCES public.profiles(id),
  voted_at  timestamptz DEFAULT now(),
  UNIQUE (poll_id, user_id)
);

CREATE INDEX IF NOT EXISTS chat_poll_votes_poll_id_idx
  ON public.chat_poll_votes (poll_id);

-- ============================================================
-- RLS
--
-- En avstemming er ikke knyttet til selskap i seg selv -- den henger
-- på en chatmelding, og den meldingen er allerede beskyttet av sin
-- egen RLS. Lesetilgang er derfor åpen for innloggede, mens skriving
-- er bundet til auth.uid(). Originalmigrasjonen brukte
-- auth.role() = 'authenticated'; her er det byttet til TO authenticated,
-- som er det Supabase anbefaler nå og som ikke avhenger av at
-- role-claimet finnes i tokenet.
-- ============================================================

ALTER TABLE public.chat_polls        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_poll_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_poll_votes   ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.chat_polls        TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.chat_poll_options TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.chat_poll_votes   TO authenticated;

-- -- chat_polls ----------------------------------------------
DROP POLICY IF EXISTS "Authenticated users can read polls" ON public.chat_polls;
CREATE POLICY "Authenticated users can read polls"
  ON public.chat_polls FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Users can create polls" ON public.chat_polls;
CREATE POLICY "Users can create polls"
  ON public.chat_polls FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid());

DROP POLICY IF EXISTS "Poll creators can update" ON public.chat_polls;
CREATE POLICY "Poll creators can update"
  ON public.chat_polls FOR UPDATE TO authenticated
  USING (created_by = auth.uid())
  WITH CHECK (created_by = auth.uid());

-- -- chat_poll_options ---------------------------------------
DROP POLICY IF EXISTS "Authenticated users can read poll options" ON public.chat_poll_options;
CREATE POLICY "Authenticated users can read poll options"
  ON public.chat_poll_options FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Poll creator can insert options" ON public.chat_poll_options;
CREATE POLICY "Poll creator can insert options"
  ON public.chat_poll_options FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.chat_polls p
       WHERE p.id = poll_id AND p.created_by = auth.uid()
    )
  );

-- -- chat_poll_votes -----------------------------------------
DROP POLICY IF EXISTS "Authenticated users can read votes" ON public.chat_poll_votes;
CREATE POLICY "Authenticated users can read votes"
  ON public.chat_poll_votes FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Users can insert own votes" ON public.chat_poll_votes;
CREATE POLICY "Users can insert own votes"
  ON public.chat_poll_votes FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update own votes" ON public.chat_poll_votes;
CREATE POLICY "Users can update own votes"
  ON public.chat_poll_votes FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete own votes" ON public.chat_poll_votes;
CREATE POLICY "Users can delete own votes"
  ON public.chat_poll_votes FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- ============================================================
-- Realtime -- streamVotes() lytter på chat_poll_votes.
-- ALTER PUBLICATION feiler hvis tabellen alt er med, derfor sjekken.
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime'
       AND schemaname = 'public'
       AND tablename = 'chat_poll_votes'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_poll_votes;
  END IF;
END
$$;
