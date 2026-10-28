-- ============================================================
-- GIGCHAT-LISTE — siste melding + uleste per gigg i én spørring
--
-- Mobilen hentet siste melding med én spørring PER gigg (1 + N), og
-- webappen strømmet alle gig_messages som fantes for så å filtrere på
-- selskap i klienten. Begge blir tregere for hver gigg som legges til.
--
-- security invoker gjør at RLS fortsatt gjelder: funksjonen ser nøyaktig
-- de meldingene den innloggede brukeren selv har lov til å se, så
-- selskapsskillet er uendret.
--
-- NB: gig_messages har ingen deleted_at-kolonne. Den filtreres det derfor
-- ikke på her.
-- ============================================================

CREATE OR REPLACE FUNCTION gig_chat_threads(p_gig_ids uuid[])
RETURNS TABLE (
  gig_id       uuid,
  last_message text,
  last_sender  text,
  last_at      timestamptz,
  unread_count integer
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH last_msg AS (
    SELECT DISTINCT ON (m.gig_id)
           m.gig_id, m.message, m.sender_name, m.created_at
    FROM gig_messages m
    WHERE m.gig_id = ANY(p_gig_ids)
    ORDER BY m.gig_id, m.created_at DESC
  ),
  unread AS (
    SELECT m.gig_id, COUNT(*)::int AS c
    FROM gig_messages m
    LEFT JOIN gig_chat_read_cursors c
      ON c.gig_id = m.gig_id AND c.user_id = auth.uid()
    WHERE m.gig_id = ANY(p_gig_ids)
      AND m.user_id IS DISTINCT FROM auth.uid()
      AND (c.last_read_at IS NULL OR m.created_at > c.last_read_at)
    GROUP BY m.gig_id
  )
  SELECT l.gig_id,
         l.message,
         l.sender_name,
         l.created_at,
         COALESCE(u.c, 0)
  FROM last_msg l
  LEFT JOIN unread u ON u.gig_id = l.gig_id;
$$;

GRANT EXECUTE ON FUNCTION gig_chat_threads(uuid[]) TO authenticated;

-- Gjør oppslaget raskt når meldingstabellen vokser.
CREATE INDEX IF NOT EXISTS idx_gig_messages_gig_created
  ON gig_messages(gig_id, created_at DESC);
