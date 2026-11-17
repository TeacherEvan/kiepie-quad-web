-- =============================================================================
-- Kiepie Bike combat backend — read-only verification
-- =============================================================================
-- Run this in the Supabase dashboard SQL Editor (or `supabase db query`) AFTER
-- applying migrations/0001_kiepie_combat.sql. Every statement is a SELECT, so
-- it is safe to run against a live project. Expected outcomes are noted inline.
-- =============================================================================

-- 1. Tables exist and RLS is enabled on all three -----------------------------
-- Expected: 3 rows, relrowsecurity = true for each.
select
  n.nspname                    as schema_name,
  c.relname                    as table_name,
  c.relrowsecurity             as rls_enabled,
  c.relforcerowsecurity        as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('lobbies', 'lobby_players', 'shots')
order by c.relname;

-- Confirm RTS is already enabled on realtime.messages (must be true).
-- Do NOT try to change it: Supabase owns that table.
select
  'realtime.messages' as table_name,
  relrowsecurity      as rls_enabled
from pg_class
where oid = 'realtime.messages'::regclass;

-- 2. Column shapes -----------------------------------------------------------
-- Expected: the exact columns/types/defaults from the contract.
select
  table_name,
  column_name,
  data_type,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in ('lobbies', 'lobby_players', 'shots')
order by table_name, ordinal_position;

-- 3. RPC signatures ----------------------------------------------------------
-- Expected: 14 functions in schema `game` (10 client RPCs incl. time_up from
-- migration 0002, plus private helpers). All have a proconfig entry containing
-- search_path=public, auth; the SECURITY DEFINER ones (10 RPCs +
-- is_lobby_member) have prosecdef = true.
select
  n.nspname                                   as schema_name,
  p.proname                                   as function_name,
  pg_get_function_identity_arguments(p.oid)   as arguments,
  pg_get_function_result(p.oid)               as returns,
  p.prosecdef                                 as security_definer,
  p.provolatile                               as volatility,
  p.proconfig                                 as settings
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'game'
order by p.proname;

-- 4. EXECUTE privileges on the RPCs ------------------------------------------
-- Expected: `authenticated` = true; `anon` = false; `public` = false.
-- (ACL grantee OID 0 is the PUBLIC pseudo-role; a NULL proacl means "owner
-- only", which also yields false here.)
select
  p.proname as function_name,
  coalesce((select bool_or(a.privilege_type = 'EXECUTE') from aclexplode(p.proacl) a
             where a.grantee = (select oid from pg_roles where rolname = 'anon')), false) as anon_execute,
  coalesce((select bool_or(a.privilege_type = 'EXECUTE') from aclexplode(p.proacl) a
             where a.grantee = (select oid from pg_roles where rolname = 'authenticated')), false) as authenticated_execute,
  coalesce((select bool_or(a.privilege_type = 'EXECUTE') from aclexplode(p.proacl) a
             where a.grantee = 0), false) as public_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'game'
order by p.proname;

-- 5. Schema usage ------------------------------------------------------------
-- Expected: authenticated has USAGE on `game`; anon/PUBLIC do not.
select
  n.nspname as schema_name,
  coalesce((select bool_or(a.privilege_type = 'USAGE') from aclexplode(n.nspacl) a
             where a.grantee = (select oid from pg_roles where rolname = 'anon')), false) as anon_usage,
  coalesce((select bool_or(a.privilege_type = 'USAGE') from aclexplode(n.nspacl) a
             where a.grantee = (select oid from pg_roles where rolname = 'authenticated')), false) as authenticated_usage,
  coalesce((select bool_or(a.privilege_type = 'USAGE') from aclexplode(n.nspacl) a
             where a.grantee = 0), false) as public_usage
from pg_namespace n
where n.nspname = 'game';

-- 6. Table grants (Data API exposure) ----------------------------------------
-- Expected: authenticated SELECT on lobbies + lobby_players;
-- anon NONE on all three; shots NONE for both.
select
  t.tablename,
  g.grantee,
  string_agg(g.privilege_type, ', ' order by g.privilege_type) as privileges
from pg_tables t
left join information_schema.role_table_grants g
  on g.table_schema = t.schemaname
 and g.table_name = t.tablename
where t.schemaname = 'public'
  and t.tablename in ('lobbies', 'lobby_players', 'shots')
  and g.grantee in ('anon', 'authenticated')
group by t.tablename, g.grantee
order by t.tablename, g.grantee;

-- 7. RLS policies ------------------------------------------------------------
-- Expected on public.lobbies:      1 SELECT policy
-- Expected on public.lobby_players: 1 SELECT policy
-- Expected on public.shots:         0 policies (default deny)
-- Expected on realtime.messages:    2 policies (SELECT + INSERT).
select
  schemaname,
  tablename,
  policyname,
  cmd           as command,
  roles,
  using_expression,
  with_check
from pg_policies
where (schemaname = 'public'   and tablename in ('lobbies', 'lobby_players', 'shots'))
   or (schemaname = 'realtime' and tablename = 'messages')
order by schemaname, tablename, policyname;

-- 8. Realtime publication members --------------------------------------------
-- Expected: public.lobbies and public.lobby_players.
select
  pubname,
  schemaname,
  tablename
from pg_publication_tables
where pubname = 'supabase_realtime'
order by schemaname, tablename;

-- 9. Indexes -----------------------------------------------------------------
-- Expected: shots_shooter_issued_at_idx, shots_issued_at_idx,
-- lobby_players_user_id_idx, the UNIQUE lobby_players_one_seat index, plus the
-- remaining FK/housekeeping indexes.
select
  tablename,
  indexname,
  indexdef
from pg_indexes
where schemaname = 'public'
  and tablename in ('lobbies', 'lobby_players', 'shots')
order by tablename, indexname;

-- 10. Default settings sanity ------------------------------------------------
-- Expected: the exact seven-key default object.
select column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'lobbies'
  and column_name = 'settings';

-- 11. Data API exposed schemas (config check) -------------------------------
-- The RPC functions live in `game`; PostgREST must have it in its schema
-- cache. This query only shows DB-side state — the authoritative setting is
-- Dashboard > Project Settings > API > Data API > Exposed schemas.
-- Expected: at least public and game.
select current_schemas(false) as search_path_schemas;

-- 12. Throttle clock ---------------------------------------------------------
-- Expected: game.maintenance exists, RLS enabled, exactly one row with
-- singleton = true. This backs heartbeat()'s 30-second sweep throttle.
select
  c.relname                    as table_name,
  c.relrowsecurity             as rls_enabled,
  (select count(*) from game.maintenance) as row_count
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'game' and c.relname = 'maintenance';
