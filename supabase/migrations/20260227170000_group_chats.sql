-- ============================================================
-- Group chats: tables + RLS
-- ============================================================

-- 1. group_chats
create table if not exists public.group_chats (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.group_chats enable row level security;

-- Alle autentiserte kan opprette grupper
create policy "Authenticated users can create groups"
  on public.group_chats for insert
  to authenticated
  with check (true);

-- Medlemmer kan lese gruppen
create policy "Members can read their groups"
  on public.group_chats for select
  to authenticated
  using (
    id in (
      select group_chat_id from public.group_chat_members
      where user_id = auth.uid()
    )
  );

-- 2. group_chat_members
create table if not exists public.group_chat_members (
  id            uuid primary key default gen_random_uuid(),
  group_chat_id uuid not null references public.group_chats(id) on delete cascade,
  user_id       uuid not null references public.profiles(id),
  joined_at     timestamptz not null default now(),
  unique (group_chat_id, user_id)
);

alter table public.group_chat_members enable row level security;

-- Medlemmer kan lese medlemslisten for sine grupper
create policy "Members can read group members"
  on public.group_chat_members for select
  to authenticated
  using (
    group_chat_id in (
      select group_chat_id from public.group_chat_members
      where user_id = auth.uid()
    )
  );

-- Autentiserte kan legge til medlemmer (ved opprettelse)
create policy "Authenticated users can add members"
  on public.group_chat_members for insert
  to authenticated
  with check (true);

-- 3. group_chat_messages
create table if not exists public.group_chat_messages (
  id            uuid primary key default gen_random_uuid(),
  group_chat_id uuid not null references public.group_chats(id) on delete cascade,
  user_id       uuid not null references auth.users(id),
  sender_name   text not null default '',
  message       text not null,
  created_at    timestamptz not null default now()
);

alter table public.group_chat_messages enable row level security;

-- Medlemmer kan lese meldinger i sine grupper
create policy "Members can read group messages"
  on public.group_chat_messages for select
  to authenticated
  using (
    group_chat_id in (
      select group_chat_id from public.group_chat_members
      where user_id = auth.uid()
    )
  );

-- Kun egne meldinger kan insertes
create policy "Users can insert own messages"
  on public.group_chat_messages for insert
  to authenticated
  with check (user_id = auth.uid());

-- Realtime
alter publication supabase_realtime add table public.group_chats;
alter publication supabase_realtime add table public.group_chat_members;
alter publication supabase_realtime add table public.group_chat_messages;
