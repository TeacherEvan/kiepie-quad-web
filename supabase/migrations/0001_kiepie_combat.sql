-- =============================================================================
-- Kiepie Bike — Web multiplayer combat backend
-- =============================================================================
-- Target: a NEW, dedicated Supabase project (Postgres 15+ / 17).
--
-- Security model (see supabase/README.md for the full rationale):
--   * Every table in `public` has RLS enabled. Clients may only SELECT.
--     All writes go through SECURITY DEFINER RPCs in the private `game` schema.
--   * `game` is not an exposed schema by default. Add it to the project's
--     Data API "Exposed schemas" (alongside `public`) so PostgREST can route
--     `POST /rest/v1/rpc/<fn>` to these functions. Exposure only makes the
--     function names routable: EXECUTE is revoked from PUBLIC/anon and granted
--     only to `authenticated`, so anon callers still cannot invoke them. The
--     only table in `game` is an internal maintenance clock with RLS enabled
--     and no client grants, so exposure leaks no data.
--   * Every SECURITY DEFINER function has `set search_path = public, auth`,
--     schema-qualified object references, and an explicit auth.uid() check.
--   * No use of user_metadata, auth.role(), or JWT-derived authorization
--     beyond auth.uid() (the JWT `sub` claim).
--   * UPDATE policies (where present) always carry both USING and WITH CHECK.
--   * Realtime private channels: membership of `lobby:<uuid>` is checked
--     against public.lobby_players. `ALTER TABLE realtime.messages ENABLE RLS`
--     is intentionally NOT present — Supabase already enables it and the
--     statement fails with `42501 must be owner of table messages`.
--
-- Idempotency: objects use IF NOT EXISTS / DROP POLICY IF EXISTS / DO guards,
-- so re-running this file is safe. It has been authored by hand but follows
-- the imperative-migration naming convention (`supabase migration new`).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Private schema for all privileged functions
-- -----------------------------------------------------------------------------
create schema if not exists game;

-- No implicit PUBLIC access to anything in this schema.
revoke all on schema game from public, anon;
grant usage on schema game to authenticated;

-- Default: new functions in `game` are callable only by authenticated users.
alter default privileges in schema game revoke execute on functions from public;
alter default privileges in schema game grant execute on functions to authenticated;

-- -----------------------------------------------------------------------------
-- 1. Tables (schema public, RLS enabled, default-deny on writes)
-- -----------------------------------------------------------------------------

create table if not exists public.lobbies (
  id          uuid        primary key default gen_random_uuid(),
  code        text        not null unique,
  name        text        not null,
  host_id     uuid        not null references auth.users(id) on delete cascade,
  settings    jsonb       not null default '{"kill_target":10,"max_players":8,"respawn_delay":2.5,"match_seconds":0,"damage":30,"pickups":true,"friendly_fire":false}'::jsonb,
  status      text        not null default 'waiting' check (status in ('waiting', 'playing', 'finished')),
  winner_id   uuid        references auth.users(id),
  created_at  timestamptz default now(),
  started_at  timestamptz
);

create table if not exists public.lobby_players (
  id            uuid        primary key default gen_random_uuid(),
  lobby_id      uuid        not null references public.lobbies(id) on delete cascade,
  user_id       uuid        not null references auth.users(id) on delete cascade,
  display_name  text        not null,
  color         text        not null,
  score         int         not null default 0,
  is_ready      bool        not null default false,
  respawn_at    timestamptz,
  last_seen     timestamptz default now(),
  joined_at     timestamptz default now(),
  constraint lobby_players_one_per_user unique (lobby_id, user_id)
);

create table if not exists public.shots (
  token        uuid        primary key default gen_random_uuid(),
  lobby_id     uuid        not null references public.lobbies(id) on delete cascade,
  shooter_id   uuid        not null references auth.users(id) on delete cascade,
  issued_at    timestamptz default now(),
  consumed_at  timestamptz
);

alter table public.lobbies       enable row level security;
alter table public.lobby_players enable row level security;
alter table public.shots         enable row level security;

-- Foreign-key / housekeeping indexes.
create index if not exists lobbies_host_id_idx          on public.lobbies (host_id);
-- Every RPC resolves the caller by user_id; UNIQUE(lobby_id, user_id) has
-- lobby_id leading and cannot serve those lookups.
create index if not exists lobby_players_user_id_idx    on public.lobby_players (user_id);
create index if not exists lobby_players_last_seen_idx  on public.lobby_players (last_seen);
create index if not exists shots_lobby_id_idx           on public.shots (lobby_id);
-- Required by the contract: anti-cheat lookups are by (shooter, time).
create index if not exists shots_shooter_issued_at_idx  on public.shots (shooter_id, issued_at);
-- heartbeat() prunes old tokens by issued_at.
create index if not exists shots_issued_at_idx          on public.shots (issued_at);

-- One lobby seat per user: prevents seat duplication and unlimited lobby
-- creation spam. The three join/create RPCs return the existing membership.
create unique index if not exists lobby_players_one_seat
  on public.lobby_players (user_id);

-- -----------------------------------------------------------------------------
-- 2. Privileges
-- -----------------------------------------------------------------------------
-- Supabase default privileges often grant ALL on new public tables to
-- anon/authenticated. Revoke that: RPCs (SECURITY DEFINER) perform all writes.
revoke all on public.lobbies, public.lobby_players, public.shots from anon, authenticated;
revoke all on table public.lobbies, public.lobby_players, public.shots from public;

-- Only SELECT is needed by the client (REST reads + Realtime Postgres Changes).
grant select on public.lobbies, public.lobby_players to authenticated;
-- public.shots: intentionally no grant at all (default deny, RPC-only).

-- -----------------------------------------------------------------------------
-- 3. Helper functions (all inside the private `game` schema)
-- -----------------------------------------------------------------------------

-- 3a. Membership check used by RLS policies. SECURITY DEFINER is required here
--     so the policy can look up lobby_players without recursively applying the
--     very policy being evaluated. auth.uid() is checked in the body.
create or replace function game.is_lobby_member(p_lobby_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select (select auth.uid()) is not null
     and exists (
       select 1
       from public.lobby_players lp
       where lp.lobby_id = p_lobby_id
         and lp.user_id = (select auth.uid())
     );
$$;

-- 3b. Generate a collision-resistant 6-character uppercase join code.
--     A pre-flight existence check cannot close the generate/insert race, so
--     callers wrap their lobby INSERT in a short SQLSTATE 23505 retry loop.
create or replace function game.new_lobby_code()
returns text
language plpgsql
volatile
set search_path = public, auth
as $$
declare
  v_code text;
  v_i int;
begin
  for v_i in 1..12 loop
    select string_agg(
             substr('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', 1 + floor(random() * 36)::int, 1),
             ''
           )
      into v_code
      from generate_series(1, 6);

    if not exists (select 1 from public.lobbies l where l.code = v_code) then
      return v_code;
    end if;
  end loop;
  raise exception 'lobby_code_exhausted'
    using hint = 'Could not generate a unique 6-character lobby code.';
end;
$$;

-- 3c. Server-side validation of player-supplied identity strings.
create or replace function game.validate_identity(p_display_name text, p_color text)
returns void
language plpgsql
immutable
set search_path = public, auth
as $$
begin
  if p_display_name is null
     or length(btrim(p_display_name)) < 1
     or length(btrim(p_display_name)) > 32 then
    raise exception 'invalid_display_name'
      using hint = 'Display name must be 1-32 non-blank characters.';
  end if;
  if p_color is null
     or length(btrim(p_color)) < 1
     or length(btrim(p_color)) > 24 then
    raise exception 'invalid_color'
      using hint = 'Color must be a short non-blank token (e.g. #33AAFF).';
  end if;
end;
$$;

-- 3d. Normalise match settings. Unknown keys are dropped; out-of-range or
--     wrong-typed values fall back to the default for that key. This is the
--     single source of truth for settings validation on the server.
create or replace function game.normalize_settings(p_settings jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public, auth
as $$
declare
  v_in  jsonb := coalesce(p_settings, '{}'::jsonb);
  v_out jsonb := '{"kill_target":10,"max_players":8,"respawn_delay":2.5,"match_seconds":0,"damage":30,"pickups":true,"friendly_fire":false}'::jsonb;
  v_num numeric;
begin
  if jsonb_typeof(v_in->'kill_target') = 'number' then
    v_num := (v_in->>'kill_target')::numeric;
    if v_num between 1 and 1000 then
      v_out := jsonb_set(v_out, '{kill_target}', to_jsonb(round(v_num)::int));
    end if;
  end if;

  if jsonb_typeof(v_in->'max_players') = 'number' then
    v_num := (v_in->>'max_players')::numeric;
    if v_num between 2 and 32 then
      v_out := jsonb_set(v_out, '{max_players}', to_jsonb(round(v_num)::int));
    end if;
  end if;

  if jsonb_typeof(v_in->'respawn_delay') = 'number' then
    v_num := (v_in->>'respawn_delay')::numeric;
    if v_num between 0 and 30 then
      v_out := jsonb_set(v_out, '{respawn_delay}', to_jsonb(v_num));
    end if;
  end if;

  if jsonb_typeof(v_in->'match_seconds') = 'number' then
    v_num := (v_in->>'match_seconds')::numeric;
    if v_num between 0 and 7200 then
      v_out := jsonb_set(v_out, '{match_seconds}', to_jsonb(round(v_num)::int));
    end if;
  end if;

  if jsonb_typeof(v_in->'damage') = 'number' then
    v_num := (v_in->>'damage')::numeric;
    if v_num between 1 and 1000 then
      v_out := jsonb_set(v_out, '{damage}', to_jsonb(round(v_num)::int));
    end if;
  end if;

  if jsonb_typeof(v_in->'pickups') = 'boolean' then
    v_out := jsonb_set(v_out, '{pickups}', v_in->'pickups');
  end if;

  if jsonb_typeof(v_in->'friendly_fire') = 'boolean' then
    v_out := jsonb_set(v_out, '{friendly_fire}', v_in->'friendly_fire');
  end if;

  return v_out;
end;
$$;

-- 3e. Single-row maintenance clock. heartbeat() is called by every client;
--     without this throttle a hostile client calling it in a tight loop would
--     run the global DELETE/UPDATE sweep on every request and cause lock
--     contention. The table lives in the private `game` schema (no client
--     access) and RLS is enabled as defence in depth; SECURITY DEFINER RPCs
--     run as the owner, which bypasses RLS.
create table if not exists game.maintenance (
  singleton  boolean primary key default true check (singleton),
  last_prune timestamptz not null default now() - interval '31 seconds'
);

alter table game.maintenance enable row level security;

insert into game.maintenance (singleton, last_prune)
values (true, now() - interval '31 seconds')
on conflict (singleton) do nothing;

-- -----------------------------------------------------------------------------
-- 4. RLS policies on public tables
-- -----------------------------------------------------------------------------
-- There are deliberately NO INSERT/UPDATE/DELETE policies: clients cannot
-- mutate game state directly. SELECT is scoped to lobby membership (plus
-- discovery of waiting lobbies).
--
-- NOTE on UPDATE: no UPDATE policy exists, but if one is added later it MUST
-- include both USING and WITH CHECK (see README).

drop policy if exists "lobbies_select_members_or_waiting" on public.lobbies;
create policy "lobbies_select_members_or_waiting"
  on public.lobbies
  for select
  to authenticated
  using (
    game.is_lobby_member(id)
    or status = 'waiting'
  );

drop policy if exists "lobby_players_select_same_lobby" on public.lobby_players;
create policy "lobby_players_select_same_lobby"
  on public.lobby_players
  for select
  to authenticated
  using (
    user_id = (select auth.uid())       -- own row (also breaks policy recursion)
    or game.is_lobby_member(lobby_id)   -- co-players in the same lobby
  );

-- No policy on public.shots: default deny even for authenticated clients.

-- -----------------------------------------------------------------------------
-- 5. RPCs (SECURITY DEFINER, private schema, explicit auth.uid() checks)
-- -----------------------------------------------------------------------------

-- 5a. join_auto ---------------------------------------------------------------
create or replace function game.join_auto(p_display_name text, p_color text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid     uuid := (select auth.uid());
  v_lobby   public.lobbies%rowtype;
  v_player  public.lobby_players%rowtype;
  v_seat    jsonb;
  v_attempt int;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  -- One seat per user (enforced by lobby_players_one_seat): always return the
  -- existing membership, including a finished lobby. This makes reconnects
  -- idempotent and stops unlimited lobby/join spam. The client must call
  -- leave_lobby() explicitly before joining a different match.
  -- Single locked re-read of BOTH rows so a concurrent stale-player sweep
  -- cannot leave us with a half-populated / NULL-valued result.
  select jsonb_build_object('lobby', to_jsonb(l), 'player', to_jsonb(lp))
    into v_seat
    from public.lobbies l
    join public.lobby_players lp on lp.lobby_id = l.id
   where lp.user_id = v_uid
   for update of l, lp;

  if v_seat is not null then
    return v_seat;
  end if;

  perform game.validate_identity(p_display_name, p_color);

  -- Atomically pick the oldest waiting lobby with free slots, skipping rows
  -- already locked by a concurrent join.
  select l.*
    into v_lobby
    from public.lobbies l
   where l.status = 'waiting'
     and (select count(*) from public.lobby_players lp where lp.lobby_id = l.id)
         < (l.settings->>'max_players')::int
   order by l.created_at, l.id
   limit 1
   for update skip locked;

  if not found then
    -- Retry on a code collision (23505) to close the generate/insert race.
    for v_attempt in 1..5 loop
      begin
        insert into public.lobbies (code, name, host_id, settings, status)
        values (
          game.new_lobby_code(),
          left(btrim(p_display_name), 32) || '''s lobby',
          v_uid,
          game.normalize_settings(null),
          'waiting'
        )
        returning * into v_lobby;
        exit;
      exception when unique_violation then
        if v_attempt = 5 then raise; end if;
      end;
    end loop;
  end if;

  -- The early check is TOCTOU: a concurrent call for the same auth.uid() can
  -- win the single seat between that check and this INSERT. Catch only the
  -- unique_violation and return the winning membership in the same shape.
  begin
    insert into public.lobby_players (lobby_id, user_id, display_name, color)
    values (v_lobby.id, v_uid, btrim(p_display_name), btrim(p_color))
    returning * into v_player;
  exception when unique_violation then
    select jsonb_build_object('lobby', to_jsonb(l), 'player', to_jsonb(lp))
      into v_seat
      from public.lobbies l
      join public.lobby_players lp on lp.lobby_id = l.id
     where lp.user_id = v_uid
     for update of l, lp;
    if v_seat is not null then
      return v_seat;
    end if;
    raise;  -- no winning row visible: never swallow an unrelated error
  end;

  return jsonb_build_object('lobby', to_jsonb(v_lobby), 'player', to_jsonb(v_player));
end;
$$;

-- 5b. join_by_code ------------------------------------------------------------
create or replace function game.join_by_code(p_code text, p_display_name text, p_color text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_lobby  public.lobbies%rowtype;
  v_player public.lobby_players%rowtype;
  v_seat   jsonb;
  v_count  int;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  -- One seat per user: return the existing membership unchanged (even from a
  -- finished lobby) instead of joining a second one. Call leave_lobby() first.
  -- Locked re-read of both rows (see join_auto).
  select jsonb_build_object('lobby', to_jsonb(l), 'player', to_jsonb(lp))
    into v_seat
    from public.lobbies l
    join public.lobby_players lp on lp.lobby_id = l.id
   where lp.user_id = v_uid
   for update of l, lp;

  if v_seat is not null then
    return v_seat;
  end if;

  perform game.validate_identity(p_display_name, p_color);

  if p_code is null or length(btrim(p_code)) <> 6 then
    raise exception 'invalid_lobby_code'
      using hint = 'Lobby codes are exactly 6 uppercase characters.';
  end if;

  select l.* into v_lobby
  from public.lobbies l
  where l.code = upper(btrim(p_code))
  for update;

  if not found then
    raise exception 'lobby_not_found' using hint = 'No lobby has that 6-character code.';
  end if;
  if v_lobby.status <> 'waiting' then
    raise exception 'lobby_not_waiting'
      using hint = case when v_lobby.status = 'finished'
                        then 'That match has already finished.'
                        else 'That match has already started.' end;
  end if;

  select count(*) into v_count
  from public.lobby_players lp where lp.lobby_id = v_lobby.id;
  if v_count >= (v_lobby.settings->>'max_players')::int then
    raise exception 'lobby_full'
      using hint = 'The lobby has reached its maximum player count.';
  end if;

  -- Same TOCTOU guard as join_auto: on a 23505 from the one-seat index,
  -- return the concurrent winner's membership rather than leaking the error.
  begin
    insert into public.lobby_players (lobby_id, user_id, display_name, color)
    values (v_lobby.id, v_uid, btrim(p_display_name), btrim(p_color))
    returning * into v_player;
  exception when unique_violation then
    select jsonb_build_object('lobby', to_jsonb(l), 'player', to_jsonb(lp))
      into v_seat
      from public.lobbies l
      join public.lobby_players lp on lp.lobby_id = l.id
     where lp.user_id = v_uid
     for update of l, lp;
    if v_seat is not null then
      return v_seat;
    end if;
    raise;
  end;

  return jsonb_build_object('lobby', to_jsonb(v_lobby), 'player', to_jsonb(v_player));
end;
$$;

-- 5c. create_lobby ------------------------------------------------------------
create or replace function game.create_lobby(
  p_name text,
  p_settings jsonb,
  p_display_name text,
  p_color text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid     uuid := (select auth.uid());
  v_lobby   public.lobbies%rowtype;
  v_player  public.lobby_players%rowtype;
  v_seat    jsonb;
  v_attempt int;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  -- One seat per user: an existing member gets their current lobby back, so
  -- repeatedly calling create_lobby cannot spawn unlimited empty lobbies.
  -- Locked re-read of both rows (see join_auto).
  select jsonb_build_object('lobby', to_jsonb(l), 'player', to_jsonb(lp))
    into v_seat
    from public.lobbies l
    join public.lobby_players lp on lp.lobby_id = l.id
   where lp.user_id = v_uid
   for update of l, lp;

  if v_seat is not null then
    return v_seat;
  end if;

  perform game.validate_identity(p_display_name, p_color);

  if p_name is null or length(btrim(p_name)) < 1 or length(btrim(p_name)) > 60 then
    raise exception 'invalid_lobby_name'
      using hint = 'Lobby name must be 1-60 non-blank characters.';
  end if;

  -- Retry on a code collision (23505) to close the generate/insert race.
  for v_attempt in 1..5 loop
    begin
      insert into public.lobbies (code, name, host_id, settings, status)
      values (
        game.new_lobby_code(),
        btrim(p_name),
        v_uid,
        game.normalize_settings(p_settings),
        'waiting'
      )
      returning * into v_lobby;
      exit;
    exception when unique_violation then
      if v_attempt = 5 then raise; end if;
    end;
  end loop;

  -- Same TOCTOU guard as join_auto; the lobby-code retry loop above stays
  -- separate and only handles the lobbies.code unique violation.
  begin
    insert into public.lobby_players (lobby_id, user_id, display_name, color)
    values (v_lobby.id, v_uid, btrim(p_display_name), btrim(p_color))
    returning * into v_player;
  exception when unique_violation then
    select jsonb_build_object('lobby', to_jsonb(l), 'player', to_jsonb(lp))
      into v_seat
      from public.lobbies l
      join public.lobby_players lp on lp.lobby_id = l.id
     where lp.user_id = v_uid
     for update of l, lp;
    if v_seat is not null then
      return v_seat;
    end if;
    raise;
  end;

  return jsonb_build_object('lobby', to_jsonb(v_lobby), 'player', to_jsonb(v_player));
end;
$$;

-- 5d. leave_lobby -------------------------------------------------------------
create or replace function game.leave_lobby()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid       uuid := (select auth.uid());
  v_lobby_id  uuid;
  v_host_id   uuid;
  v_new_host  uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  -- Defensive loop: the one-seat unique index now guarantees at most one row,
  -- but this also cleans up any pre-existing duplicates safely.
  for v_lobby_id in
    select lp.lobby_id
    from public.lobby_players lp
    where lp.user_id = v_uid
  loop
    -- Lock the lobby row FIRST so the global order is lobby -> player,
    -- matching register_kill and the locked seat re-reads in the join RPCs
    -- (avoids a lobby/player deadlock with a concurrent join).
    select l.host_id into v_host_id
    from public.lobbies l where l.id = v_lobby_id for update;

    delete from public.lobby_players
    where user_id = v_uid and lobby_id = v_lobby_id;

    if v_host_id = v_uid then
      select lp.user_id into v_new_host
      from public.lobby_players lp
      where lp.lobby_id = v_lobby_id
      order by lp.joined_at, lp.id
      limit 1;

      if v_new_host is not null then
        update public.lobbies l set host_id = v_new_host where l.id = v_lobby_id;
      else
        delete from public.lobbies l where l.id = v_lobby_id;
      end if;
    end if;
  end loop;
end;
$$;

-- 5e. set_settings ------------------------------------------------------------
create or replace function game.set_settings(p_settings jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_lobby public.lobbies%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select l.* into v_lobby
  from public.lobbies l
  where l.id = (
    select lp.lobby_id from public.lobby_players lp where lp.user_id = v_uid limit 1
  )
  for update;

  if not found then
    raise exception 'not_in_lobby' using hint = 'Join a lobby before changing settings.';
  end if;
  if v_lobby.host_id <> v_uid then
    raise exception 'not_host'
      using errcode = '42501',
            hint = 'Only the lobby host may change match settings.';
  end if;

  update public.lobbies l
     set settings = game.normalize_settings(p_settings)
   where l.id = v_lobby.id
  returning l.* into v_lobby;

  return to_jsonb(v_lobby);
end;
$$;

-- 5f. start_match -------------------------------------------------------------
create or replace function game.start_match()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_lobby  public.lobbies%rowtype;
  v_players int;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select l.* into v_lobby
  from public.lobbies l
  where l.id = (
    select lp.lobby_id from public.lobby_players lp where lp.user_id = v_uid limit 1
  )
  for update;

  if not found then
    raise exception 'not_in_lobby' using hint = 'Join a lobby before starting a match.';
  end if;
  if v_lobby.host_id <> v_uid then
    raise exception 'not_host'
      using errcode = '42501',
            hint = 'Only the lobby host may start the match.';
  end if;
  if v_lobby.status <> 'waiting' then
    -- Never wipe the scores / respawn state of a live or finished match.
    raise exception 'lobby_not_waiting'
      using errcode = '55000',
            hint = 'Only a waiting lobby can be started.';
  end if;

  select count(*) into v_players
  from public.lobby_players lp where lp.lobby_id = v_lobby.id;
  if v_players < 2 then
    raise exception 'not_enough_players'
      using hint = 'At least 2 players are required to start a match.';
  end if;

  -- Clear all tokens from any previous match: unconsumed tokens cannot be
  -- replayed after a restart, and consumed ones no longer pollute the
  -- cooldown / 20-per-minute rate-limit counters.
  delete from public.shots s
   where s.lobby_id = v_lobby.id;

  update public.lobbies l
     set status = 'playing', started_at = now(), winner_id = null
   where l.id = v_lobby.id;

  update public.lobby_players lp
     set score = 0, respawn_at = null
   where lp.lobby_id = v_lobby.id;

  select l.* into v_lobby from public.lobbies l where l.id = v_lobby.id;
  return to_jsonb(v_lobby);
end;
$$;

-- 5g. issue_shot --------------------------------------------------------------
create or replace function game.issue_shot()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid       uuid := (select auth.uid());
  v_lobby_id  uuid;
  v_respawn_at timestamptz;
  v_status    text;
  v_token     uuid;
  v_at        timestamptz;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select lp.lobby_id, lp.respawn_at into v_lobby_id, v_respawn_at
  from public.lobby_players lp where lp.user_id = v_uid limit 1;
  if v_lobby_id is null then
    raise exception 'not_in_lobby' using hint = 'You must be in a lobby to fire.';
  end if;

  select l.status into v_status
  from public.lobbies l where l.id = v_lobby_id;
  if v_status is distinct from 'playing' then
    raise exception 'lobby_not_playing' using hint = 'Shots can only be issued during a live match.';
  end if;
  if v_respawn_at is not null and v_respawn_at > now() then
    raise exception 'shooter_respawning' using hint = 'Wait for respawn before firing.';
  end if;

  insert into public.shots (lobby_id, shooter_id)
  values (v_lobby_id, v_uid)
  returning token, issued_at into v_token, v_at;

  return jsonb_build_object('token', v_token, 'at', v_at);
end;
$$;

-- 5h. register_kill -----------------------------------------------------------
-- Validation failures return {"ok": false, "reason": "<snake_case>"} rather
-- than raising, so the Godot client can handle them without exception parsing.
create or replace function game.register_kill(p_target uuid, p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid         uuid := (select auth.uid());
  v_lobby_id    uuid;
  v_caller_respawn timestamptz;
  v_lobby       public.lobbies%rowtype;
  v_target      public.lobby_players%rowtype;
  v_shot        public.shots%rowtype;
  v_last_kill   timestamptz;
  v_kill_count  int;
  v_score       int;
  v_winner      uuid;
  v_status      text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  end if;
  if p_target is null or p_token is null then
    return jsonb_build_object('ok', false, 'reason', 'invalid_arguments');
  end if;

  -- Resolve caller's lobby. respawn_at is deliberately NOT trusted from here:
  -- it is re-read under the lobby lock below (see the shooter-respawn guard).
  select lp.lobby_id into v_lobby_id
  from public.lobby_players lp where lp.user_id = v_uid limit 1;
  if v_lobby_id is null then
    return jsonb_build_object('ok', false, 'reason', 'not_in_lobby');
  end if;

  -- Lock the lobby row: this serialises all kill resolution for the match,
  -- which also prevents deadlocks between concurrent shooters/targets.
  select l.* into v_lobby from public.lobbies l where l.id = v_lobby_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_in_lobby');
  end if;
  if v_lobby.status <> 'playing' then
    return jsonb_build_object('ok', false, 'reason', 'lobby_not_playing');
  end if;
  if p_target = v_uid then
    return jsonb_build_object('ok', false, 'reason', 'self_kill');
  end if;

  -- Shooter-respawn guard: re-read the caller's row FOR UPDATE AFTER the lobby
  -- lock. A concurrent register_kill that just put this shooter into respawn
  -- commits before our lobby lock is granted; the earlier unlocked read was
  -- stale and must not be used. Lock order is lobby -> caller -> target -> shot
  -- for every kill, so concurrent kills cannot deadlock.
  select lp.respawn_at into v_caller_respawn
  from public.lobby_players lp
  where lp.lobby_id = v_lobby.id and lp.user_id = v_uid
  for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_in_lobby');
  end if;
  if v_caller_respawn is not null and v_caller_respawn > now() then
    return jsonb_build_object('ok', false, 'reason', 'shooter_respawning');
  end if;

  -- Target must be a live, non-respawning member of the SAME lobby.
  select lp.* into v_target
  from public.lobby_players lp
  where lp.lobby_id = v_lobby.id and lp.user_id = p_target
  for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'target_not_in_lobby');
  end if;
  if v_target.respawn_at is not null and v_target.respawn_at > now() then
    return jsonb_build_object('ok', false, 'reason', 'target_respawning');
  end if;

  -- Token must be an unused shot issued by this caller in this lobby.
  select s.* into v_shot from public.shots s where s.token = p_token for update;
  if not found
     or v_shot.shooter_id <> v_uid
     or v_shot.lobby_id <> v_lobby.id then
    return jsonb_build_object('ok', false, 'reason', 'invalid_token');
  end if;
  if v_shot.consumed_at is not null then
    return jsonb_build_object('ok', false, 'reason', 'token_consumed');
  end if;
  if v_shot.issued_at < now() - interval '10 seconds' then
    return jsonb_build_object('ok', false, 'reason', 'token_expired');
  end if;

  -- Anti-cheat: >= 1.0 s between this caller's kills and <= 20 kills / minute.
  select max(s.consumed_at) into v_last_kill
  from public.shots s
  where s.shooter_id = v_uid and s.lobby_id = v_lobby.id and s.consumed_at is not null;
  if v_last_kill is not null and now() - v_last_kill < interval '1 second' then
    return jsonb_build_object('ok', false, 'reason', 'kill_cooldown');
  end if;

  select count(*) into v_kill_count
  from public.shots s
  where s.shooter_id = v_uid
    and s.lobby_id = v_lobby.id
    and s.consumed_at >= now() - interval '1 minute';
  if v_kill_count >= 20 then
    return jsonb_build_object('ok', false, 'reason', 'rate_limited');
  end if;

  -- Apply atomically (the lobby row lock from above is still held).
  update public.shots s set consumed_at = now() where s.token = p_token;

  update public.lobby_players lp
     set score = lp.score + 1
   where lp.lobby_id = v_lobby.id and lp.user_id = v_uid
  returning lp.score into v_score;

  update public.lobby_players lp
     set respawn_at = now() + make_interval(secs => (v_lobby.settings->>'respawn_delay')::double precision)
   where lp.lobby_id = v_lobby.id and lp.user_id = p_target;

  v_status := 'playing';
  v_winner := null;
  if v_score >= (v_lobby.settings->>'kill_target')::int then
    update public.lobbies l
       set status = 'finished', winner_id = v_uid
     where l.id = v_lobby.id;
    v_status := 'finished';
    v_winner := v_uid;
  end if;

  return jsonb_build_object(
    'ok', true,
    'score', v_score,
    'winner_id', v_winner,       -- SQL NULL -> JSON null
    'lobby_status', v_status
  );
end;
$$;

-- 5i. heartbeat ---------------------------------------------------------------
create or replace function game.heartbeat()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_last_prune timestamptz;
begin
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  -- Always keep this caller alive; this is the only write on every call.
  update public.lobby_players lp
     set last_seen = now()
   where lp.user_id = (select auth.uid());

  -- Throttle the global sweep. A hostile client calling heartbeat() in a tight
  -- loop would otherwise run DELETE/UPDATE over every lobby/player/shot row on
  -- every call. Serialise on one advisory lock and prune at most every 30 s.
  perform pg_advisory_xact_lock(7246319001::bigint);

  select m.last_prune into v_last_prune
  from game.maintenance m
  where m.singleton = true;

  if not found then
    insert into game.maintenance (singleton, last_prune)
    values (true, now() - interval '31 seconds')
    on conflict (singleton) do nothing;

    select m.last_prune into v_last_prune
    from game.maintenance m
    where m.singleton = true;
  end if;

  if v_last_prune is null or now() - v_last_prune >= interval '30 seconds' then
    update game.maintenance m
       set last_prune = now()
     where m.singleton = true;

    -- Prune stale memberships, then empty lobbies, then repair orphaned hosts.
    delete from public.lobby_players lp
     where lp.last_seen < now() - interval '2 minutes';

    delete from public.lobbies l
     where not exists (
       select 1 from public.lobby_players lp where lp.lobby_id = l.id
     );

    update public.lobbies l
       set host_id = (
         select lp.user_id
         from public.lobby_players lp
         where lp.lobby_id = l.id
         order by lp.joined_at, lp.id
         limit 1
       )
     where exists (
       select 1 from public.lobby_players lp where lp.lobby_id = l.id
     )
     and not exists (
       select 1 from public.lobby_players h
       where h.lobby_id = l.id and h.user_id = l.host_id
     );

    -- Bound growth of the anti-cheat token table (tokens are valid 10 s).
    delete from public.shots s where s.issued_at < now() - interval '10 minutes';
  end if;
end;
$$;

-- Final privilege pass: EXECUTE on every function in `game` to authenticated
-- only (explicitly NOT to anon/PUBLIC), regardless of migration ordering.
revoke all on all functions in schema game from public, anon;
grant execute on all functions in schema game to authenticated;

-- -----------------------------------------------------------------------------
-- 6. Realtime
-- -----------------------------------------------------------------------------

-- 6a. Postgres Changes: publish the two tables the Godot client watches.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'lobbies'
  ) then
    execute 'alter publication supabase_realtime add table public.lobbies';
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'lobby_players'
  ) then
    execute 'alter publication supabase_realtime add table public.lobby_players';
  end if;
end $$;

-- 6b. Private Broadcast/Presence channels for a match.
--     RLS is ALREADY enabled on realtime.messages in Supabase — do not try to
--     enable it here. The dashboard setting "Allow public access" must be
--     OFF for these policies to be enforced (see README).
--
--     Topic forms: the Godot (Phoenix-style, protocol v1.0.0) client joins
--     `realtime:lobby:<uuid>`, while many Supabase docs examples use the
--     stripped form `lobby:<uuid>`. Some code paths/examples of realtime.topic()
--     return the prefix already removed, so we normalise BOTH to `lobby:<uuid>`
--     before extracting the lobby id. The CASE with a regex guard is a safe
--     parser: a malformed or unrelated topic yields NULL instead of throwing
--     on an invalid ::uuid cast.

drop policy if exists "lobby_members_receive_broadcast_presence" on realtime.messages;
create policy "lobby_members_receive_broadcast_presence"
  on realtime.messages
  for select
  to authenticated
  using (
    realtime.messages.extension in ('broadcast', 'presence')
    and exists (
      select 1
      from public.lobby_players lp
      where lp.user_id = (select auth.uid())
        and lp.lobby_id = (
          case
            when regexp_replace((select realtime.topic()), '^realtime:', '')
                 ~ '^lobby:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
            then split_part(regexp_replace((select realtime.topic()), '^realtime:', ''), ':', 2)::uuid
          end
        )
    )
  );

drop policy if exists "lobby_members_send_broadcast_presence" on realtime.messages;
create policy "lobby_members_send_broadcast_presence"
  on realtime.messages
  for insert
  to authenticated
  with check (
    realtime.messages.extension in ('broadcast', 'presence')
    and exists (
      select 1
      from public.lobby_players lp
      where lp.user_id = (select auth.uid())
        and lp.lobby_id = (
          case
            when regexp_replace((select realtime.topic()), '^realtime:', '')
                 ~ '^lobby:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
            then split_part(regexp_replace((select realtime.topic()), '^realtime:', ''), ':', 2)::uuid
          end
        )
    )
  );

-- =============================================================================
-- END OF MIGRATION
-- Run supabase/verify.sql afterwards to confirm the deployed state.
-- =============================================================================
