# Kiepie Bike — Supabase combat backend (setup guide)

This directory contains the complete backend for the Godot Web multiplayer
combat game. It is **not applied yet**: it targets a brand-new, dedicated
Supabase project. Do not run it against the existing Bike/Vercel project.

| File | Purpose |
| --- | --- |
| `migrations/0001_kiepie_combat.sql` | Full schema, RLS, RPCs, grants, Realtime setup. Idempotent. |
| `migrations/0002_time_limit.sql` | Adds host-authoritative `game.time_up()` for lobbies with a match time limit. Idempotent. |
| `verify.sql` | Read-only queries to confirm the deployed state. |
| `README.md` | This document. |

Design summary: clients may **read** `lobbies` / `lobby_players` and subscribe
to Realtime; **every state change** goes through a `SECURITY DEFINER` RPC in a
private `game` schema.

---

## 1. Create the project

1. In [Supabase Dashboard](https://supabase.com/dashboard) → **New project**.
2. Pick an organisation, a name (e.g. `kiepie-combat`), a database password, and
   a region close to your players. Note the **Project Ref** from Settings →
   General; you need it for the CLI.
3. Wait until status is *Healthy*.

## 2. Enable anonymous sign-ins

Dashboard → **Authentication → Providers → Anonymous Sign-Ins → Enable**.

This is essential: the Godot Web client signs in anonymously and receives a
real JWT with a UUID `sub`. Anonymous users carry the Postgres role
`authenticated`, so every policy below uses `to authenticated` plus an
`auth.uid()` predicate — **never** `auth.role() = 'authenticated'` (that check
would be true for everyone once anonymous sign-ins are on) and never a
`user_metadata` claim (user-editable).

## 3. Apply the migration

### Option A — Dashboard SQL Editor (simplest)

Open **SQL Editor → New query**, paste the entire contents of
`migrations/0001_kiepie_combat.sql`, and click **Run**. The file is written to
be safe to re-run (`if not exists`, `drop policy if exists`, guarded
publication additions). Then paste and run `migrations/0002_time_limit.sql`
(optional but recommended — it enforces the lobby's "Time limit" setting).

### Option B — Supabase CLI (`supabase db push`)

```bash
# In a directory that has supabase/config.toml; if you don't have one:
supabase init

# Copy migrations/0001_kiepie_combat.sql into ./supabase/migrations/ first
supabase link --project-ref <PROJECT_REF>
supabase db push
supabase migration list          # should show 0001_kiepie_combat as applied
```

CLI notes (current as of Nov 2026):
- **CLI v3 is local by default and asks before changing a hosted project**
  ([changelog](https://supabase.com/changelog/supabase-cli-v3)). Read the prompt
  before accepting, or pin CLI v2 if your scripts rely on the old behaviour.
- Discover flags with `supabase --help` / `supabase db push --help`; do not
  guess them.
- Prefer a **scoped personal access token** in `SUPABASE_ACCESS_TOKEN` over a
  classic full-access token for scripts/CI.
- The migration was hand-authored using the imperative naming convention. If
  you need another migration later, start with `supabase migration new <name>`
  rather than inventing a filename.

### Verify

Run `supabase/verify.sql` in the SQL Editor. Check the inline "Expected"
comments — in particular RLS on all three tables, the 13 functions in `game`
(9 client RPCs + 4 private helpers), **10 of which have
`security_definer = true`** (the 9 RPCs plus `game.is_lobby_member`), policies
on `realtime.messages`, and the two publication members.

## 4. Expose the `game` schema to PostgREST (REQUIRED)

The RPCs deliberately live in a **private** `game` schema, but PostgREST can
only route `POST /rest/v1/rpc/<fn>` to functions in schemas listed in the
Data API's exposed-schema set. Without this step every RPC call returns a
404 "function not found".

Dashboard → **Project Settings → API → Data API → Exposed schemas**: add
`game` so the list contains **both `public` and `game`**. Save, then wait a few
seconds (or use **Reload schema cache** / `NOTIFY pgrst, 'reload schema';` if a
newly added function is not visible).

Why this is still safe:

- `game` contains **no client-facing tables**. Its only table is an internal
  maintenance clock (`game.maintenance`) with RLS enabled, no policies and
  **no grants at all**. Note that `USAGE ON SCHEMA game` *is* granted to
  `authenticated` — that is required for PostgREST to route `/rpc/<fn>` calls
  and for RLS policies to call `game.is_lobby_member`. It grants no table
  access and no ability to CREATE objects; `anon` and `PUBLIC` have neither
  USAGE nor EXECUTE.
- The migration runs `REVOKE EXECUTE ... FROM PUBLIC, anon` on every function
  in `game` and `GRANT EXECUTE ... TO authenticated` only. Anonymous sign-in
  users have the `authenticated` role (that is how they can call the game),
  but a raw, unauthenticated anon request cannot. There is also no `USAGE` on
  the `game` schema for `anon`/`PUBLIC`.
- All 9 RPCs plus `game.is_lobby_member` are `SECURITY DEFINER` with
  `set search_path = public, auth`, schema-qualified references, and an
  explicit `auth.uid()` check. The remaining 4 helpers are plain invoker
  functions. The client can never bypass the checks by calling an RPC directly.

> Supabase now requires explicit table exposure too: new `public` tables are
> not automatically exposed to the Data API. The migration grants only
> `SELECT` on `lobbies` / `lobby_players` to `authenticated` and explicitly
> revokes all grants from `anon`, `authenticated` and `PUBLIC` before granting
> the SELECT back. `shots` has no grants at all. All writes are RPC-only.

## 5. Project URL, key, and client sign-in

Dashboard → **Project Settings → API Keys**:

- **Project URL** — e.g. `https://<ref>.supabase.co`.
- **Publishable key** — the new `sb_publishable_...` key. Use this one in the
  Godot Web client.
- **Never** put the `service_role` / secret key in the client. It bypasses RLS
  and would make every control in this migration meaningless. (Legacy `anon`
  keys still work but publishable keys are preferred.)

Client flow (Godot Web, via HTTPRequest / WebSocket):

1. `POST /auth/v1/signup` with `{ "data": {} }` (anonymous sign-in) — or use
   your Supabase client library's `signInAnonymously()`.
2. Store the returned `access_token` + `refresh_token` for the session.
3. Send `Authorization: Bearer <access_token>` and `apikey: <publishable key>`
   on every `/rest/v1/rpc/...` call and when connecting to Realtime.
4. Call `game.heartbeat()` every ~30–60 s while in a lobby.

## 6. Realtime settings

Dashboard → **Realtime → Settings**:

- **Turn "Allow public access" OFF.** This is required for the
  `realtime.messages` RLS policies to be enforced on private channels.
- Ensure **Broadcast** and **Presence** are enabled.

The migration adds `public.lobbies` and `public.lobby_players` to the
`supabase_realtime` publication, so Postgres Changes work for lobby state and
player scores/respawn. Reads are filtered by the same RLS SELECT policies.

For Broadcast/Presence the Godot client **must join a private channel** — set
`config: { private: true }` (supabase-js) or the equivalent
`RealtimeChannelConfig(private = true)` / `isPrivate = true` in other SDKs.
Without that flag the `realtime.messages` RLS policies are not applied. Use
the topic `realtime:lobby:<uuid>` (Phoenix-style, protocol v1.0.0). The
policies normalise that form *and* the documented `lobby:<uuid>` form, so both
work. Membership of the lobby is re-checked against `lobby_players` on connect.

> Supabase caches a client's Realtime access policy for the life of the
> connection. Revoking a membership mid-session will not immediately stop
> message delivery — see the caveat in §8.

## 7. Optional development-branch workflow

Test schema changes on a branch before touching production:

```bash
supabase branch create kiepie-combat-test     # or use Dashboard > Branches
supabase link --project-ref <BRANCH_REF>
supabase db push                              # apply migration to the branch
# run verify.sql, exercise the RPCs, then merge the branch in the Dashboard
```

Branches are useful here because the migration touches `realtime.messages`
policies. Merge only after `verify.sql` and a live smoke test of
`join_auto` → `start_match` → `issue_shot` → `register_kill` → `heartbeat`.

## 8. Client session & caching caveats

- **Token expiry / refresh.** Anonymous JWTs are short-lived. The GD script
  must refresh the session before expiry (or re-sign-in anonymously) and send
  the new access token to Realtime via `access_token`; otherwise the socket is
  dropped and a player is pruned by `heartbeat()` after 2 minutes.
- **Realtime policy cache.** Access is evaluated when a channel is joined or
  a new JWT is received, not per message. A player removed from `lobby_players`
  can keep receiving broadcasts until the token is refreshed/reconnected.
  Keep the JWT expiry short and treat server-side RPC checks as authoritative.
- **Shared browser sessions / one seat per user.** Godot Web runs in one
  browser profile: `localStorage`-backed sessions are shared across tabs. Two
  tabs share one `auth.uid()` and therefore **one lobby seat** — enforced by
  the `lobby_players_one_seat` unique index on `user_id`. Use one game tab per
  player, or sign out on unload. `join_auto`, `join_by_code` and `create_lobby`
  all return the caller's existing membership, so spam-calling them cannot
  create extra lobbies.
- **Deleted users ≠ invalidated tokens.** Deleting an auth user does not
  revoke existing JWTs. Call sign-out when a player leaves, and keep token
  lifetime short for sensitive actions.
- **Schema cache after DDL.** If a freshly added RPC returns 404/42704, reload
  the PostgREST schema cache (Settings → API → Reload schema cache). This is a
  one-off after applying a migration.
- **Reconnects.** All three join/create RPCs return the caller's existing
  membership (even from a finished lobby) rather than erroring or adding a
  second seat, so reconnects are idempotent. Call `leave_lobby()` explicitly
  before joining a different match.
- **Match restarts.** `start_match()` only works from `status = 'waiting'`;
  calling it on a playing/finished lobby raises `lobby_not_waiting` rather than
  wiping scores. On a valid start it also deletes **all** shot tokens for the
  lobby (consumed and unconsumed) so tokens cannot leak across matches and
  cooldown/rate-limit counters start clean.
- **Respawn gate.** `issue_shot()` raises `shooter_respawning` while your
  `respawn_at` is in the future; `register_kill()` also refuses with
  `{"ok":false,"reason":"shooter_respawning"}` as a defensive check.
- **Heartbeat pruning is throttled.** `heartbeat()` always refreshes your
  `last_seen`, but the global DELETE/UPDATE sweep runs at most once every
  30 seconds (serialised by an advisory lock and the `game.maintenance`
  clock), so a client looping the RPC cannot burn CPU or hold table locks.
  The sweep deletes `lobby_players` rows older than 2 minutes, removes empty
  lobbies, repairs orphaned hosts, and purges shots older than 10 minutes.

---

## RPC contract (Godot client reference)

All RPCs are called as `POST /rest/v1/rpc/<name>` with the Bearer token.
Function names, argument names, and return shapes below are exact — do not
change them without updating the client.

| Function | Arguments | Returns |
| --- | --- | --- |
| `game.join_auto` | `p_display_name text, p_color text` | `{"lobby": <row jsonb>, "player": <row jsonb>}` |
| `game.join_by_code` | `p_code text, p_display_name text, p_color text` | same shape; raises `lobby_not_found` / `lobby_not_waiting` / `lobby_full` |
| `game.create_lobby` | `p_name text, p_settings jsonb, p_display_name text, p_color text` | same shape |
| `game.leave_lobby` | none | `void` |
| `game.set_settings` | `p_settings jsonb` | `<lobby row jsonb>` (host only) |
| `game.start_match` | none | `<lobby row jsonb>` (host only, ≥ 2 players, `waiting` only; raises `lobby_not_waiting` otherwise) |
| `game.issue_shot` | none | `{"token": <uuid>, "at": <timestamptz>}` |
| `game.register_kill` | `p_target uuid, p_token uuid` | `{"ok":true,"score":int,"winner_id":uuid\|null,"lobby_status":text}` or `{"ok":false,"reason":"<snake_case>"}` |
| `game.heartbeat` | none | `void` |

`register_kill` failure reasons (returned, **not** raised): `not_authenticated`,
`invalid_arguments`, `not_in_lobby`, `lobby_not_playing`, `self_kill`,
`shooter_respawning`, `target_not_in_lobby`, `target_respawning`,
`invalid_token`, `token_consumed`, `token_expired`, `kill_cooldown`,
`rate_limited`.

Raised errors from other RPCs worth handling: `not_authenticated`,
`invalid_display_name`, `invalid_color`, `invalid_lobby_code`,
`lobby_not_found`, `lobby_not_waiting`, `lobby_full`, `not_in_lobby`, `not_host`,
`not_enough_players`, `shooter_respawning`.

Settings are validated/normalised server-side (`game.normalize_settings`):

| Key | Type | Accepted range | Default |
| --- | --- | --- | --- |
| `kill_target` | int | 1–1000 | 10 |
| `max_players` | int | 2–32 | 8 |
| `respawn_delay` | number (seconds) | 0–30 | 2.5 |
| `match_seconds` | int | 0–7200 (0 = unlimited) | 0 |
| `damage` | int | 1–1000 | 30 |
| `pickups` | bool | — | true |
| `friendly_fire` | bool | — | false |

Unknown keys are dropped; out-of-range or wrongly typed values revert to the
default. The client may send a partial object.

## Security decisions worth flagging

1. **No direct writes.** No INSERT/UPDATE/DELETE grants or RLS policies exist
   on the public tables; all mutations happen inside `SECURITY DEFINER` RPCs
   in a private schema. If you later add an UPDATE policy, it **must** contain
   both `USING` and `WITH CHECK` or a user could reassign `user_id`.
2. **`shots` is default-deny** for clients; tokens are only ever created and
   consumed by RPCs.
3. **Defence in depth on RPCs.** Private schema + revoked PUBLIC/anon EXECUTE +
   `auth.uid()` checks in every privileged function body + pinned
   `search_path`; `new_lobby_code` collisions are retried on SQLSTATE 23505.
4. **No `auth.role()`, no `user_metadata`.** Authorization is solely
   `auth.uid()` (JWT `sub`) and server-side lobby membership.
5. **Realtime private channels.** Membership is checked with
   `realtime.topic()` normalised to `lobby:<uuid>`, and both `broadcast` and
   `presence` extensions are covered for SELECT and INSERT. The `CASE` regex
   guard prevents invalid-UUID cast errors on unrelated topics.
6. **Anti-cheat is server-authoritative.** A kill needs an unused shot token
   issued by the caller in the same playing lobby within 10 s, target must be
   alive and in that lobby, ≥1 s between kills and ≤20 kills/minute. Scores and
   the winner are written only by `register_kill`.
7. **One seat per user** (`lobby_players_one_seat`) stops join/create spam.
   The three join/create RPCs do a single locked re-read of lobby + player, and
   their player INSERTs catch `unique_violation` to return the concurrent
   winner's seat instead of leaking a 23505. `start_match` is `waiting`-only
   and clears stale tokens; `issue_shot` and `register_kill` refuse a
   respawning shooter (the latter re-reads the shooter's row under the lobby
   lock). Global lock order is lobby → player → shot throughout.
8. **Heartbeat is throttled** to one global sweep per 30 s via an advisory lock
   plus the internal `game.maintenance` clock, so a hostile client cannot
   create lock contention by looping the RPC.
9. **Trademark reminder from AGENTS.md:** keep any "BLASTER"/"GAMING" branding
   personal/non-commercial, or replace the decals before commercial use.
