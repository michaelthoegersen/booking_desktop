-- ============================================================
-- Stemme for +1 i chat-avstemminger
--
-- Krever at 20261112_chat_polls.sql er kjørt først.
--
-- På en aktivitet med allow_plus_one kan et medlem huke av "Tar med
-- +1". Da skal følget også kunne få et alternativ i avstemmingen
-- (matvalg og liknende), ellers stemmer ikke hodetellingen.
--
-- chat_poll_votes hadde UNIQUE (poll_id, user_id), som gir nøyaktig
-- én stemme per bruker. Nøkkelen utvides med is_guest, så samme bruker
-- kan ha én stemme for seg selv og én for følget -- men fortsatt bare
-- én av hver.
--
-- Idempotent.
-- ============================================================

ALTER TABLE public.chat_poll_votes
  ADD COLUMN IF NOT EXISTS is_guest boolean NOT NULL DEFAULT false;

-- Den gamle nøkkelen heter chat_poll_votes_poll_id_user_id_key når Postgres
-- har laget den selv, men navnet er ikke garantert. Finn den på
-- kolonnene i stedet, og la den stå hvis den alt er utvidet.
DO $$
DECLARE
  v_name text;
BEGIN
  SELECT c.conname INTO v_name
    FROM pg_constraint c
   WHERE c.conrelid = 'public.chat_poll_votes'::regclass
     AND c.contype = 'u'
     AND (
       SELECT array_agg(a.attname::text ORDER BY a.attname)
         FROM unnest(c.conkey) k
         JOIN pg_attribute a
           ON a.attrelid = c.conrelid AND a.attnum = k
     ) = ARRAY['poll_id', 'user_id']
   LIMIT 1;

  IF v_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.chat_poll_votes DROP CONSTRAINT %I', v_name);
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_constraint c
     WHERE c.conrelid = 'public.chat_poll_votes'::regclass
       AND c.contype = 'u'
       AND (
         SELECT array_agg(a.attname::text ORDER BY a.attname)
           FROM unnest(c.conkey) k
           JOIN pg_attribute a
             ON a.attrelid = c.conrelid AND a.attnum = k
       ) = ARRAY['is_guest', 'poll_id', 'user_id']
  ) THEN
    ALTER TABLE public.chat_poll_votes
      ADD CONSTRAINT chat_poll_votes_poll_user_guest_key
      UNIQUE (poll_id, user_id, is_guest);
  END IF;
END
$$;

-- RLS er uendret: policyene går på user_id = auth.uid(), og en
-- følge-stemme eies av den som tok følget med.
