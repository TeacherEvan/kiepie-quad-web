# Surgical Audit Report: Kiepie Quad — Backend (`kiepie-quad-web`)

| Audit Metadata | Specification |
| :--- | :--- |
| **Audit Date** | 2026-11-19 |
| **Audited Scope** | **Backend, Multiplayer Authority, Replication, Persistence & Edge/Deploy Pipeline** (`14` impl files, `6` test/gate files, `3,454` effective LOC [`2,790` impl + `664` test]; covers `godot/src/net/*`, `godot/src/game/{ArenaNet,NetworkedBike,VehicleRegistry}.gd`, `godot/src/core/{Settings,KiepieTime}.gd`, `godot/addons/talo/talo_socket.gd` integration boundary, `index.service.worker.js`, `godot/tools/{patch_web_sw.py,inject_talo_key.py,deploy_web.sh}`, and retired `supabase/` hygiene). Audited on clean `HEAD` `0f3a053a0f70179971f20fe3b5fe2f4075d2f654`. |
| **Tech Stack & Runtime** | Godot 4.3 GDScript (`TaloBackend` HTTP + WebSocket over vendored Talo 0.20.0, `MockBackend` offline parity layer), `ConfigFile` / Web IDBFS persistence, Vanilla JS Service Worker (COOP/COEP + Cache API), Python 3 / Bash Web deploy pipeline, Vercel static edge. |
| **Pre/Post Audit SHA-256** | `17033d6846568f33 / 17033d6846568f33 (VERIFIED ZERO MUTATION)` (`17033d6846568f335797b39dc2fd8eb0e431be3be9aac01a0914bd75def24a15`) |
| **Deterministic Health Score** | **`32 / 100`** (`D_raw = 111`, `Scale = 0.5381`, `P_test = 8.33`, `M_kill = 44.4%`) |
| **Vibe-Debt Risk Level** | **`CRITICAL`** (`S_health < 40` and `N_P0 = 2 >= 2`) |
| **Live Verification** | **Pass 2.5 Deep Runtime & Node `vm` Verified** — Live headless Godot 4.3 probes empirically reproduced `B-P0-1`, `B-P0-2`, `B-P1-1`, `B-P1-5` (both `SYNC` respawn reset and rogue proxy injection), and Node `vm` reproduced `B-P2-4` (SW timer leak + `206` re-wrapping) with zero source mutation. |
| **SARIF 2.1.0 Deliverable** | [`kiepie-quad-backend-surgical-audit-2026-11-19.sarif`](kiepie-quad-backend-surgical-audit-2026-11-19.sarif) (`18` structured findings: `9` error, `5` warning, `4` note) |

---

## 1. Executive Architecture & Vibe-Debt Triage

While commit `12ee11a` remediated earlier socket-authentication regressions (`lobby_update`, `kill`, `ready_request`, and `SYNC` roster pruning), the subsequent Death Race and heavy-weapon additions (`459d2f8`, `b17e068`) introduced **two P0 multiplayer trust-boundary and scoring defects** plus **seven P1 protocol, concurrency, reconnect, and replication bugs**. Specifically, `TaloBackend._register_lap()` lacks both a `game_mode == "death_race"` check and any lap-time rate limit, allowing any guest in **Battle Royale** or **Death Race** to fire three forged `lap_request` socket messages in 1 ms and win immediately (`B-P0-1`, live-reproduced). Simultaneously, both `_register_kill()` and `_register_lap()` mutate the exact same `row["score"]` column, so scoring 2 kills and finishing Lap 1 in a 3-lap Death Race sets `score = 3 >= lap_target` and ends the race on Lap 1 (`B-P0-2`, live-reproduced). On the realtime wire, `ArenaNet._spawn_remote_shot()` enforces only a global 24/s cap with zero per-weapon cooldowns for rockets (5s) or meteors (6s) (`B-P1-1`, live-reproduced at 10 meteors/frame), `PROTOCOL_VERSION` remained `"1"` across wire-breaking additions (`B-P1-2`), vendored `TaloSocket._poll()` never emits `connection_closed` when a reconnect fails before `v1.connected` (`B-P1-7`), and socket reconnect, host hand-off, `MatchState` `SYNC` respawn timers, `Lobby.leave()`, and roster-driven Nardus promotion all contain live async/desync races (`B-P1-3`–`B-P1-6`). The 6 backend gates execute 104 assertions but achieve only **44.4% (`16/36`)** estimated mutation kill rate due to `MockBackend` drift and zero coverage on `_register_lap`, `_handoff_host_before_leave`, `_on_socket_closed`, Service Worker, and deploy scripts.

| Severity Tier | Count | Deduction Weight | Primary Failure Domains |
| :--- | :--- | :--- | :--- |
| **P0 — Critical (Crash / Data Loss / Security / Leak)** | **2** | `-18 pts ea` (`-36`) | `TaloBackend.gd` / `MockBackend.gd` unthrottled cross-mode `lap_request` instant-win exploit (`B-P0-1`); `TaloBackend.gd` / `MockBackend.gd` / `MatchState.gd` split-brain `score` column collision between kills and laps in Death Race (`B-P0-2`) |
| **P1 — High (Frame-Budget / Race / Logic Bug)** | **7** | `-8 pts ea` (`-56`) | `ArenaNet.gd` missing rocket/meteor per-weapon rate limits (`B-P1-1`); `TaloBackend.gd` unbumped `PROTOCOL_VERSION` (`B-P1-2`), concurrent reconnect race (`B-P1-3`), premature host hand-off & `_write_props` channel resurrection (`B-P1-4`); `MatchState.gd` full-delay respawn reset on `SYNC` & `ArenaNet.gd` rogue-peer proxy creation (`B-P1-5`); `LobbyService.gd` unawaited `leave()` race & `NetworkedBike.gd` stale roster vehicle promotion (`B-P1-6`); `TaloSocket._poll()` silent pre-auth reconnect stall + permanent `is_ready = false` brick (`B-P1-7`) |
| **P2 — Medium (God File / Split-Brain State / Debt)** | **5** | `-3 pts ea` (`-15`) | `deploy_web.sh` static `index.html` live-check blind spot (`B-P2-1`); `TaloBackend.gd` God router & `MockBackend` parity drift (`B-P2-2`); `Settings.gd` 5× save amplification & unguarded resize timer (`B-P2-3`); `index.service.worker.js` / `patch_web_sw.py` `setTimeout` leak, uncaught media fetch & `206` re-wrapping (`B-P2-4`); `MatchState.scoreboard()` non-deterministic ties & `_join_auto` partial settings mutation (`B-P2-5`) |
| **P3 — Low (Magic Constants / DX / Portability)** | **4** | `-1 pt ea` (`-4`) | `inject_talo_key.py` double `os.close(fd)` anti-pattern (`B-P3-1`); SW `'message'` missing `waitUntil` & basename matching (`B-P3-2`); retired `supabase/` doc/migration drift & `.pck` budget headroom (`B-P3-3`); authored-but-dead backend settings keys `network/auto_join` & `friendly_fire` (`B-P3-4`) |

**Health Score Formula Verification:**
- $D_{\text{raw}} = (18 \times 2) + (8 \times 7) + (3 \times 5) + (1 \times 4) = 111$
- $\text{Scale} = \sqrt{1000 / \max(500, 3454)} = 0.53807 \implies D_{\text{scaled}} = 59.73$
- $P_{\text{test}} = 15 \times (1 - 44.44 / 100) = 8.33$
- $S_{\text{health}} = \max(0, \text{round}(100 - 59.73 - 8.33)) = \mathbf{32 / 100}$ (**CRITICAL**)

### High-Risk File Telemetry Hotspots

| File Path | Effective LOC | Branch Density / Structure | Silent Catches | Primary Vibe-Debt Signature |
| :--- | :--- | :--- | :--- | :--- |
| `godot/src/net/TaloBackend.gd` | `804` | `0.06` (`_on_socket_message` 147 LOC) | `0` | God socket/HTTP router; unthrottled cross-mode `lap_request`, score collision, reconnect & hand-off races |
| `godot/src/core/Settings.gd` | `333` | `0.06` | `1` | 5× synchronous disk write burst in `apply_quality()`, unconditional boot save, unguarded timer callback, unwired keys |
| `godot/src/net/MatchState.gd` | `293` | `0.06` | `0` | Overloaded `score` field across modes, `SYNC` resets respawn countdown, non-deterministic scoreboard ties |
| `godot/src/game/ArenaNet.gd` | `257` | `0.14` | `0` | Missing per-weapon cooldowns for remote rockets/meteors (24 meteors/s DoS), unverified rogue `state` proxy spawn |
| `godot/tools/patch_web_sw.py` | `229` | `0.03` | `1` | Emits SW with uncancelled 2.5s `setTimeout`, unguarded media fetch, and `206 Partial Content` re-wrapping |
| `godot/src/net/MockBackend.gd` | `199` | `0.06` | `0` | Contract drift vs `TaloBackend` (missing `time_up`, no-op `leave_lobby`, divergent token & lap checks) |
| `index.service.worker.js` | `150` | `0.04` | `0` | Generated SW output carrying `patch_web_sw.py` edge defects (verified in Node `vm`) |
| `godot/src/game/NetworkedBike.gd` | `137` | `0.13` | `0` | Roster vehicle assignment frozen at `setup()`, desyncing model vs projectile type on late joins/leaves |
| `godot/tools/deploy_web.sh` | `85` | `0.29` | `0` | Live deploy verification polls `index.html` MD5 (unchanged on GDScript deploys) instead of `index.service.worker.js` |
| `godot/tools/inject_talo_key.py` | `64` | `0.09` | `2` | Double `os.close(fd)` after `os.fdopen` handoff inside error handler |

---

## 2. The 10-Principal-Engineer Deep Audit

### Lens 1: Systems Architect

- **`[B-P0-2]` Split-Brain `score` Column Collision Between Kills and Laps in Death Race** — `godot/src/net/TaloBackend.gd:L667-L686,L718-L730`, `godot/src/net/MockBackend.gd:L140-L168,L185-L200`, `godot/src/net/MatchState.gd:L244-L286`
  - **Root Cause Mechanism:** Player rows store only a single integer `"score"` field. `_register_kill()` unconditionally increments `row["score"] += 1` even when `game_mode == "death_race"` (only skipping the `score >= target_kills` finish check at `L682`), while `_register_lap()` increments the exact same `row["score"] += 1` and finishes the match when `score >= target_laps`.
  - **Deterministic Trigger & Failure Mode:** In a 3-lap Death Race, a rider gets 2 combat kills (`score = 2`), then crosses the finish line on **Lap 1** (`_register_lap`). `score` becomes `3 >= lap_target (3)`, setting `status = "finished"` and `winner_id` after 1 lap. **Live Godot 4.3 reproduction confirmed:** `B-P0-2 DR kill+lap collision: status=finished winner=1 score=3`.
  - **Surgical Fix Specification:** Separate `"laps"` (int, default `0`) and `"kills"` (int) on every roster row (keeping `"score"` strictly equal to `laps` in Death Race and `kills` in Battle Royale). Only `_register_lap()` may advance `"laps"` and evaluate `laps >= target_laps`.

- **`[B-P1-2]` Unbumped `PROTOCOL_VERSION := "1"` Across Wire-Breaking Additions** — `godot/src/net/TaloBackend.gd:L11-L15,L298-L303`
  - **Root Cause Mechanism:** `PROTOCOL_VERSION` remained `"1"` after adding wire message kind `"lap_request"`, shot discriminator `"w": "rocket" | "meteor"`, and lobby setting `"game_mode": "death_race"` / `"lap_target"`.
  - **Deterministic Trigger & Failure Mode:** A cached older v1 Web client passes `protocol_ok()` and joins a Death Race lobby. When the match starts, the v1 client loads `Arena.tscn` instead of `DeathRace.tscn`, ignores `lap_request`, and spawns regular machine-gun tracers when peers fire rockets or meteors.
  - **Surgical Fix Specification:** Bump `PROTOCOL_VERSION := "2"` in `TaloBackend.gd:L15` and update `verify_talo_backend.gd` protocol checks accordingly.

- **`[B-P2-2]` `TaloBackend.gd` God Router (`804` eff LOC) & `MockBackend` Contract Drift** — `godot/src/net/TaloBackend.gd:L773-L919`, `godot/src/net/MockBackend.gd:L60-L204`
  - **Root Cause Mechanism:** `TaloBackend.gd` mixes auth/socket lifecycle, HTTP pagination, channel-prop single-writer queuing, match scoring, and a 147-line `_on_socket_message()` switch in one file. Meanwhile `MockBackend` omits `time_up`, makes `leave_lobby` a no-op, enforces `_issued_tokens` on kills (which `TaloBackend` cannot do), and skips `status == "playing"` and roster checks on `_mock_register_lap()`.
  - **Deterministic Trigger & Failure Mode:** Offline gates passing on `MockBackend` fail to mirror real host-authority behavior in `TaloBackend` (e.g., `time_up` and `leave_lobby` host handoff are completely unexercised offline).
  - **Surgical Fix Specification:** Extract pure socket-envelope validation & rate-limiting into a `RefCounted` helper (`TaloWireGuard.gd`) and bring `MockBackend` into 1:1 RPC parity (`time_up`, `leave_lobby`, mode/status/roster guards on `_mock_register_lap`).

### Lens 2: Frame-Budget & Performance

- **`[B-P1-1]` Missing Per-Weapon Cooldown Gate on Remote Rockets & Meteors (WebGL2 & Gameplay DoS)** — `godot/src/game/ArenaNet.gd:L237-L273`
  - **Root Cause Mechanism:** `_spawn_remote_shot()` shares one flat `24 shots/sec` window (`_shot_log`) across primary bullets, rockets, and meteors, without enforcing the 5.0 s rocket or 6.0 s meteor cooldowns per `owner_id`.
  - **Deterministic Trigger & Failure Mode:** A modified peer sends 10–24 `"shot"` packets with `"w": "meteor"` in 1 second. Every peer spawns 24–48 concurrent `MeteorStrike` trees (`GPUParticles3D` + `OmniLight3D` + `105 dmg` AOE), exhausting the WebGL2 8-omni-light limit and dropping frames below `16.67 ms`. **Live Godot 4.3 reproduction confirmed:** `B-P1-1 Meteor flood spawned in 1 frame: 10`.
  - **Surgical Fix Specification:** Maintain per-sender `_rocket_last: Dictionary` (`>= 4.5 s` interval) and `_meteor_last: Dictionary` (`>= 5.5 s` interval, allowing 0.5 s network jitter) in `ArenaNet.gd` before instantiating `ROCKET` or `METEOR`. Reject unknown `"w"` values outside `["primary", "rocket", "meteor"]`.

- **`[B-P2-3]` `Settings.gd` Write Amplification (`5×` Sync Disk Saves per Preset)** — `godot/src/core/Settings.gd:L299,L330-L336`
  - **Root Cause Mechanism:** `apply_quality(preset)` calls `set_value()` five times in sequence, invoking `_cfg.save(PATH)` (synchronous IDBFS write on Web) five times and walking the entire scene tree via `find_children()` multiple times. `_load()` also unconditionally writes `settings.cfg` on every boot even when schema version matches `2`.
  - **Deterministic Trigger & Failure Mode:** Clicking a Quality preset in `SettingsMenu` stalls Web frames with 5 consecutive ConfigFile serializations + redundant `WorldEnvironment`/`DirectionalLight3D` traversals.
  - **Surgical Fix Specification:** Batch `apply_quality()` mutations in memory, call `_save()` once, and invoke `_apply_video_to_tree()` once; in `_load()`, only `_save()` when migrating or creating a missing config.

### Lens 3: Mathematical, Physics & Algorithmic

- **`[B-P2-5]` Non-Deterministic `MatchState.scoreboard()` Tie Ordering** — `godot/src/net/MatchState.gd:L177-L192`
  - **Root Cause Mechanism:** `scoreboard()` sorts solely by `int(a["score"]) > int(b["score"])`, whereas `leader_id()` (`L168`) sorts `uids` lexicographically first for deterministic tie-breaking.
  - **Deterministic Trigger & Failure Mode:** When two players share the same score (or at 0–0 match start), Godot's `Array.sort_custom()` order depends on `Dictionary` insertion order across peers, displaying conflicting #1 leaders on different screens.
  - **Surgical Fix Specification:** Break score ties deterministically by `str(a["user_id"]) < str(b["user_id"])` (matching `leader_id()`).

### Lens 4: Concurrency, Async & Determinism

- **`[B-P1-3]` Concurrent Socket Reconnect Race & Premature `_reconnecting = false`** — `godot/src/net/TaloBackend.gd:L138-L166`
  - **Root Cause Mechanism:** `_on_socket_closed()` resets `_reconnecting = false` at `L146` *before* awaiting `Talo.players.identify(...)`, `Talo.socket.open_connection()`, and the 2.5 s `_identified` spin loop (`L150-L158`).
  - **Deterministic Trigger & Failure Mode:** On flaky mobile networks where `open_connection()` triggers a second `connection_closed` before identification finishes, two reconnect coroutines race concurrently on `Talo.socket`.
  - **Surgical Fix Specification:** Keep `_reconnecting = true` across the entire `identify` + `open_connection` + handshake window (clearing it only in a single exit path after resolution).

- **`[B-P1-4]` Premature Host Hand-Off Broadcast & Stale `_write_props` Channel Resurrection** — `godot/src/net/TaloBackend.gd:L218-L225,L458-L494,L558-L569`
  - **Root Cause Mechanism:** `_handoff_host_before_leave()` broadcasts `_send("state", {"lobby": new_lobby, ...})` at `L484` *before* the HTTP `PUT` transferring `ownerAliasId` succeeds (`L486-L490`). Separately, `leave_lobby_channel()` (`L218-L225`) clears `_channel = null` and `_channel_id = -1` without incrementing `_prop_gen`; an in-flight `_write_props()` returning HTTP 200 after `leave_lobby_channel()` passes `gen == _prop_gen` at `L562` and overwrites `_channel = TaloChannel.new(body["channel"])` at `L567`.
  - **Deterministic Trigger & Failure Mode:** If the hand-off HTTP `PUT` fails (502/timeout), guests already switched `host_id` to `next_host`, who then receives HTTP 403 on every subsequent prop write. If the host leaves during an in-flight heartbeat `PUT`, `_channel` resurrects on a disconnected lobby.
  - **Surgical Fix Specification:** Send `_send("state", ...)` only *after* `PUT` returns `200`. Increment `_prop_gen += 1` inside `leave_lobby_channel()`, and verify `_channel_id > 0` before writing `_channel` at `L567`.

- **`[B-P1-5]` Roster `SYNC` Resets Local Respawn Countdown & Rogue `"state"` Proxy Injection** — `godot/src/net/MatchState.gd:L349-L350,L367-L368`, `godot/src/game/ArenaNet.gd:L111-L119`
  - **Root Cause Mechanism:** On every `lobby_players` `SYNC` or `UPDATE` while the local player is respawning, `MatchState` emits `self_respawn_at.emit(respawn_delay())` (the full 2.5 s duration) instead of `respawn_remaining(my_user_id)`. In `ArenaNet._on_broadcast("state")`, any incoming `"state"` packet with an unknown `id` calls `_create_remote(id)` without checking `Match.players.has(id)`.
  - **Deterministic Trigger & Failure Mode:** **Live Godot 4.3 reproduction confirmed:** `B-P1-5 SYNC with 0.4s remaining emitted self_respawn_at=[2.5]` and `B-P1-5b Rogue non-roster peer spawned in ArenaNet._remote: true`. Any departed or unrostered member sending `"bike_state"` spawns an orphaned `StaticBody3D` proxy in the arena.
  - **Surgical Fix Specification:** Emit `respawn_remaining(my_user_id)` in `MatchState.gd:L350,L368` (only once per `respawn_at` timestamp change). In `ArenaNet.gd:L115`, return early if `not Match.players.has(id)`.

- **`[B-P1-6]` Unawaited `Lobby.leave()` Race Against Immediate Re-Join & Stale Roster Vehicle Promotion** — `godot/src/net/LobbyService.gd:L63-L71`, `godot/src/game/NetworkedBike.gd:L32-L50,L87-L98`
  - **Root Cause Mechanism:** `Lobby.leave()` awaits `Supabase.call_rpc("leave_lobby", {})` (which may await two host-handoff HTTP retries) and then unconditionally wipes `current_lobby_id = ""`, `Match.lobby = {}`, and `Match.players.clear()`. Callers (`MatchHud._on_leave_match`, `LobbyMenu._on_leave`) invoke `Lobby.leave()` fire-and-forget before changing scenes. Meanwhile, `NetworkedBike` computes `VehicleRegistry.for_player_in_roster()` once in `setup()` and never updates `_assigned_vehicle` when `ArenaNet._sync_roster()` receives late joins/leaves.
  - **Deterministic Trigger & Failure Mode:** A host leaves a match and immediately clicks Quick Join in MainMenu; the prior `leave()` coroutine finishes 300 ms later and wipes the newly joined lobby state. On a 2→3 player roster change, Peer A still renders Peer B as Nardus while `ArenaNet._spawn_remote_shot()` switches Peer B's bullets to Quad tracers.
  - **Surgical Fix Specification:** Track a monotonic `_session_gen` in `LobbyService`; increment it in `_enter()` and `leave()`, and abort `leave()`'s post-`await` wipe if `_session_gen` changed. In `NetworkedBike.update_identity()`, re-check `VehicleRegistry.for_player_in_roster()` and swap `Model` when `_assigned_vehicle` changes (matching `KiepieBike.refresh_vehicle_assignment()`).

### Lens 5: Memory & Resource Lifecycle

- **`[B-P2-4]` Service Worker Uncancelled `setTimeout`, Uncaught Media Fetch & `206` Re-Wrapping** — `index.service.worker.js:L52-L72,L135-L138,L169-L175`, `godot/tools/patch_web_sw.py:L100-L106,L192-L196`
  - **Root Cause Mechanism:** `Promise.race([netPromise, new Promise((_, rej) => setTimeout(...))])` never clears the 2.5 s timeout timer when `netPromise` wins. In the `else if (ENSURE_CROSSORIGIN_ISOLATION_HEADERS)` branch (`L169-L175`), same-origin non-cached assets (`web-assets/kiepie-victory-splash.mp4`, `dashboard_bg.jpg`) call `await fetch(event.request)` without error handling and wrap `206 Partial Content` byte-range streams into `new Response(response.body, ...)`.
  - **Deterministic Trigger & Failure Mode:** **Live Node `vm` reproduction confirmed:** `{"timers_created_on_fast_nav":1,"timers_cleared":0,"mp4_206_status":206,"mp4_206_rewrapped_with_coep":true}`. Safari/WebKit byte-range `<video>` streaming can stall on reconstructed `206` responses; offline media requests reject unhandled; timers linger on every navigation/script fetch.
  - **Surgical Fix Specification:** Store and `clearTimeout(tid)` in `.finally()` on `netPromise`; bypass `ensureCrossOriginIsolationHeaders` for `response.status === 206` (already same-origin) and catch offline fetch failures cleanly.

- **`[B-P3-1]` Double `os.close(fd)` Pattern in `inject_talo_key.py`** — `godot/tools/inject_talo_key.py:L54-L66`
  - **Root Cause Mechanism:** After `os.fdopen(fd, "wb")` succeeds, `fh` owns `fd` and closes it upon exiting the `with` block; any exception inside `write`/`fsync` triggers a second `os.close(fd)` in `except BaseException:` (swallowed by `except OSError: pass`).
  - **Deterministic Trigger & Failure Mode:** Disk-full error during `fh.write()` double-closes `fd` (unsafe POSIX pattern if copied into threaded tools).
  - **Surgical Fix Specification:** Track `fd_owned = True`, clear it immediately after `os.fdopen(fd, "wb")`, and close `fd` only if still owned.

### Lens 6: Security & Trust-Boundary

- **`[B-P0-1]` Cross-Mode Unthrottled `lap_request` Instant-Win Exploit** — `godot/src/net/TaloBackend.gd:L699-L737,L884-L893`, `godot/src/net/MockBackend.gd:L175-L204`
  - **Root Cause Mechanism:** `_register_lap()` checks only `status == "playing"`, `_roster.has(racer)`, and `_used_tokens.has(token)`. It **never verifies `game_mode == "death_race"`** and enforces **zero cooldown / minimum lap duration** (unlike `_register_kill()`, which enforces a 1 s cooldown and 20/min window). Because tokens are client-minted strings on Talo v1, any guest can mint arbitrary unique tokens.
  - **Deterministic Trigger & Failure Mode:** In **Battle Royale** (`kill_target = 10`), a guest sends 3 `{"k":"lap_request","p":{"racer":"<own_id>","token":"x1..x3"}}` frames in 1 ms. The host scores 3 points, evaluates `3 >= target_laps (3)`, and ends the Battle Royale match naming the attacker winner. In **Death Race**, a guest wins 1 ms after match start without driving. **Live Godot 4.3 reproduction confirmed:** `B-P0-1 BR lap exploit: status=finished winner=2 guest_score=3`.
  - **Surgical Fix Specification:** In `_register_lap()` (both `TaloBackend.gd` and `MockBackend.gd`): (1) reject with `{"ok": false, "reason": "wrong_mode"}` unless `str(s_dict.get("game_mode", "battle_royale")) == "death_race"`, (2) enforce a per-racer minimum lap cooldown (`MIN_LAP_SECONDS := 12.0`) returning `{"ok": false, "reason": "rate_limited"}`.

### Lens 7: Reliability & Fault Tolerance

- **`[B-P1-7]` Vendored `TaloSocket._poll()` Silent Pre-Auth Reconnect Stall + Permanent `is_ready = false` Brick** — `godot/addons/talo/talo_socket.gd:L96-L106`, `godot/src/net/TaloBackend.gd:L150-L165`
  - **Root Cause Mechanism:** Vendored `TaloSocket._poll()` (`L105`) only calls `_reset_socket()` and emits `connection_closed` when `_socket.get_ready_state() == STATE_CLOSED and _socket_authenticated`. If a reconnect attempt drops or times out *before* receiving `"v1.connected"` (or if `Talo.players.identify()` fails transiently at `TaloBackend.gd:L151`), `TaloSocket` never fires `connection_closed` again, and `TaloBackend.gd:L162` permanently flips `is_ready = false` with no automatic retry loop.
  - **Deterministic Trigger & Failure Mode:** A single 3-second mobile network drop (tunnel/Wi-Fi handoff) during socket reconnect permanently bricks multiplayer until the player hard-reloads the browser tab.
  - **Surgical Fix Specification:** Without modifying vendored `godot/addons/talo/`, wrap reconnect inside a bounded loop in `TaloBackend._on_socket_closed()` (e.g., up to 5 attempts with exponential backoff `2s → 4s → 8s → 16s → 30s`), keeping `is_ready` intact while retrying and exposing a manual `reconnect()` trigger on `SupabaseClient`.

- **`[B-P2-1]` Live Deploy Verification Polls Static `index.html` Instead of Content-Hashed SW / `.pck`** — `godot/tools/deploy_web.sh:L98-L109`
  - **Root Cause Mechanism:** The post-push Vercel verification loop compares `md5sum "$ROOT/index.html"` against `https://kiepie-quad-web.vercel.app/index.html`.
  - **Deterministic Trigger & Failure Mode:** Whenever a release updates only GDScript/scenes (changing `index.pck` and `index.service.worker.js` while `index.html` stays byte-identical or only shifts `fileSizes`), `LOCAL_MD5 == LIVE_MD5` matches the *previous* deploy on iteration 1 (`t = 5s`), reporting `DEPLOY OK` before Vercel finishes building the new bundle.
  - **Surgical Fix Specification:** Compare `md5sum "$ROOT/index.service.worker.js"` (which embeds both `wasm_hash` and `pck_hash` in `CACHE_VERSION`) against `https://kiepie-quad-web.vercel.app/index.service.worker.js` in addition to `index.html`.

- **`[B-P3-2]` Service Worker `'message'` Listener Missing `event.waitUntil()` & Basename-Only `local` Matching** — `index.service.worker.js:L120,L179-L199`
  - **Root Cause Mechanism:** `'message'` runs async `clients.get()` / `caches.delete()` / `skipWaiting()` without `event.waitUntil()`; `u.pathname.slice(lastIndexOf('/') + 1)` matches basenames regardless of directory prefix.
  - **Deterministic Trigger & Failure Mode:** Aggressive mobile SW suspension can abort `'clear'`/`'update'` mid-flight.
  - **Surgical Fix Specification:** Wrap the `'message'` promise chain in `event.waitUntil(...)` and match root-relative paths (`u.pathname.replace(/^\/+/, '')`).

### Lens 8: Type Systems, Schema & Contracts

- **`[B-P2-5b]` `_join_auto()` Caller `args` In-Place Mutation & Partial Default Settings Schema** — `godot/src/net/TaloBackend.gd:L384-L386`
  - **Root Cause Mechanism:** When `_join_auto()` falls back to `_create_lobby(args)`, it mutates the caller's `args` dictionary in-place (`args["p_settings"] = {"game_mode": wanted_mode, "lap_target": 3, "kill_target": 10}`), omitting `max_players`, `respawn_delay`, `match_seconds`, `damage`, and `pickups`.
  - **Deterministic Trigger & Failure Mode:** Peers inspecting `channel.get_prop("settings")` receive a sparse dictionary missing standard keys; any caller reusing `args` observes unexpected mutation.
  - **Surgical Fix Specification:** Construct a fresh `create_args := args.duplicate(true)` populated from a single shared `DEFAULT_SETTINGS` constant merged with `{"game_mode": wanted_mode}`.

### Lens 9: Platform, Viewport & Portability

- **`[B-P2-3b]` Unguarded Deferred Resize Timer in `Settings._sync_mobile_scale()`** — `godot/src/core/Settings.gd:L186-L197`
  - **Root Cause Mechanism:** `_sync_mobile_scale()` calls `get_tree().create_timer(0.1)` without checking `get_tree() != null`, and the timeout lambda invokes `_sync_mobile_scale_now()` which accesses `get_tree().root` without checking `is_inside_tree()`.
  - **Deterministic Trigger & Failure Mode:** Resizing during shutdown/tree teardown throws a null dereference on `get_tree()`.
  - **Surgical Fix Specification:** Guard `var tree := get_tree(); if tree == null: return` before creating the timer and `if not is_inside_tree() or get_tree() == null: return` inside `_sync_mobile_scale_now()`.

### Lens 10: Cognitive Load & AI Maintainability

- **`[B-P3-3]` Retired `supabase/` Drift & `.pck` Size Budget Headroom Warning** — `supabase/`, `godot/tools/deploy_web.sh:L59-L61`, `AGENTS.md`
  - **Root Cause Mechanism:** `AGENTS.md` documents expected `index.pck ≈ 2.7 MB` and `deploy_web.sh:L60` logs `(expected ~3.0 MB)`, whereas current `index.pck` is **3.38 MB (`3,381,696` bytes)** — `80.6%` of the 4.0 MB abort cap (`4,194,304` bytes). `supabase/README.md` (297 lines) still describes itself as *"the complete backend... not applied yet"* despite being retired in favor of Talo.
  - **Deterministic Trigger & Failure Mode:** Next asset addition risks unexpectedly hitting the 4 MB `deploy_web.sh` abort; onboarding agents can misread `supabase/README.md` as active.
  - **Surgical Fix Specification:** Sync `AGENTS.md` and `deploy_web.sh` expected `.pck` baseline (`~3.4 MB`), add a `[RETIRED — historical archive only]` banner at top of `supabase/README.md`, and audit `godot/assets/` before adding new media.

---

## 2.5 Pass 2.5 Live Runtime Evidence & 11th Lens (Persistence & Authored-but-Unwired Backend Surface)

### Pass 2.5 Live Reproduction Transcript (Zero Source Mutation)

```text
# Godot 4.3 headless (KIEPIE_MOCK_BACKEND=1)
B-P0-1 BR lap exploit: status=finished winner=2 guest_score=3
B-P0-2 DR kill+lap collision: status=finished winner=1 score=3
B-P1-1 Meteor flood spawned in 1 frame: 10
B-P1-5 SYNC with 0.4s remaining emitted self_respawn_at=[2.5] (expected ~0.4)
B-P1-5b Rogue non-roster peer spawned in ArenaNet._remote: true

# Node vm Service Worker probe (index.service.worker.js)
SW PROBE B-P2-4: {"timers_created_on_fast_nav":1,"timers_cleared":0,"mp4_206_status":206,"mp4_206_rewrapped_with_coep":true}
```

### 11th Lens — Authored-but-Unwired Backend Persistence & Settings (`[B-P3-4]`)

| Backend Surface | State | Evidence |
| :--- | :--- | :--- |
| `Settings` `network/auto_join` | **Authored, not wired** | Defined in `Settings.gd:L43`, `0` readers across `godot/src/` |
| `friendly_fire` match rule | **Authored, not wired** | Defined in `LobbyMenu.gd:L32` & `MockBackend.gd:L20`, `0` combat readers |
| Persistent career stats / best lap times | **Absent** | Only `user://settings.cfg` preferences persist; no Talo leaderboard / local best-lap storage |
| Host-loss void detection (`host_lost`) | **Wired** | `TaloBackend._poll_host_alive` + instant `"leave"` host check → `MatchState._on_host_lost` |

---

## 3. Existing Test Suite Comparison & Mutation Truth Table

- **Test-to-Code File Ratio:** `6 / 14` (`0.43`)
- **Estimated Mutation Kill Score ($M_{\text{kill}}$):** **`44.4%`** (`16/36` mutants killed; `104` assertions, `97` negative/boundary signals, `4` mock-heavy test files, `4` unpaired critical modules: `index.service.worker.js`, `patch_web_sw.py`, `inject_talo_key.py`, `deploy_web.sh`)

| Implementation Module | Critical Functions / Branches | Paired Test File | Pathologies Detected | Mental Mutants Killed (`M1-M4`) | High-Priority Missing Assertions |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `godot/src/net/TaloBackend.gd` | `_register_kill`, `_register_lap`, `_on_socket_message`, `_on_socket_closed`, `_handoff_host_before_leave`, `_time_up` | `verify_talo_backend.gd`, `verify_audit_regressions.gd`, `verify_multiplayer.gd` | Happy-Path Tunnel Vision (new `lap_request` untested), Mock-Mirror (`_channel = null` skips HTTP/reconnect) | `2/4` (`50%`) | `lap_request` mode+cooldown reject, kill+lap separation, reconnect retry loop, handoff HTTP failure |
| `godot/src/net/MatchState.gd` | `apply_lobby`, `register_kill`, `register_lap`, `_on_pg_change`, `scoreboard`, `_process` (`time_up`) | `verify_match_rules.gd`, `verify_audit_regressions.gd` | Mock-Mirror (`MockBackend` diverges), Result-Only | `2/4` (`50%`) | `respawn_remaining` on `SYNC`, deterministic scoreboard tie-break, `time_up` retry, Death Race `laps` vs `kills` |
| `godot/src/game/ArenaNet.gd` | `_on_broadcast`, `_spawn_remote_shot`, `_sync_roster`, `_place_local_bike_at_roster_slot` | `verify_multiplayer.gd`, `verify_kill_flow.gd`, `verify_audit_regressions.gd` | Happy-Path Tunnel Vision (only 1 primary shot tested) | `2/4` (`50%`) | Remote rocket/meteor cooldown throttle, rogue non-roster `state` rejection, unknown weapon reject |
| `godot/src/game/NetworkedBike.gd` | `setup`, `apply_state`, `update_identity`, `set_respawning` | `verify_multiplayer.gd` | Happy-Path Tunnel Vision | `2/4` (`50%`) | Out-of-order `n` drop, non-finite quaternion, dynamic vehicle re-swap on roster change |
| `godot/src/game/VehicleRegistry.gd` | `for_player`, `for_player_in_roster`, `profile` | `verify_pogo.gd` | None (pure deterministic checks) | `3/4` (`75%`) | Empty/duplicate roster edge cases |
| `godot/src/core/Settings.gd` | `_load`, `set_value`, `apply_quality`, `reset_defaults`, `_sync_mobile_scale` | `verify_settings.gd` | Result-Only (no write-count check on `apply_quality`) | `3/4` (`75%`) | Single-write batching in `apply_quality`, teardown safety on resize timer |
| `godot/src/net/LobbyService.gd` | `join_auto`, `join_by_code`, `create_lobby`, `leave` | `verify_match_rules.gd` | Happy-Path Tunnel Vision | `1/4` (`25%`) | `leave()` vs re-join async race, empty/error result handling |
| `godot/src/core/KiepieTime.gd` | `parse_iso`, `iso_from_unix`, `iso_from_now` | `verify_audit_regressions.gd` (indirect) | Unpaired directly | `1/4` (`25%`) | Malformed ISO strings, `"null"`, timezone offsets, negative seconds |
| `index.service.worker.js` + `patch_web_sw.py` + `inject_talo_key.py` + `deploy_web.sh` | SW fetch/cache/COEP, JWT atomic write, live deploy verify | **NONE** | `0%` automated coverage | `0/4` (`0%`) | Node `vm` SW unit test (206/opaque/204/timeout cleanup), `unittest` for `patch_web_sw.py` & `inject_talo_key.py` |

### Why Existing Tests Missed Discovered P0/P1 Defects

- **`B-P0-1` & `B-P0-2`:** `verify_deathrace.gd` tested `RaceTracker` solely against `MockBackend` with 0 kills, and `verify_talo_backend.gd` was never updated with a single `register_lap` or `lap_request` assertion.
- **`B-P1-1`:** `verify_multiplayer.gd:L92-L99` sends only one `"primary"` remote shot and never tests `"w": "rocket"` or `"w": "meteor"` floods.
- **`B-P1-2`:** `verify_talo_backend.gd:L126` hardcoded `proto = "1"` matching `PROTOCOL_VERSION := "1"`, so wire-breaking schema changes passed silently.
- **`B-P1-3`, `B-P1-4`, `B-P1-7`:** `_channel = null` in all `TaloBackend` unit tests bypassed `_write_props`, `_handoff_host_before_leave`, and `_on_socket_closed` / `TaloSocket._poll()`.

### Minimal Viable Test Harness (MVTH) Specifications

1. **Tier 1 (`verify_talo_backend.gd` additions):** Table-driven tests asserting: (a) `lap_request` rejected with `wrong_mode` in `battle_royale`, (b) second `lap_request` within `MIN_LAP_SECONDS` rejected with `rate_limited`, (c) 2 kills + 1 lap in a 3-lap `death_race` yields `laps == 1`, `status == "playing"`, (d) `ArenaNet._spawn_remote_shot` drops a second `"meteor"` within 5.5 s and second `"rocket"` within 4.5 s, (e) `ArenaNet._on_broadcast("state")` ignores unknown non-roster `id`.
2. **Tier 2 (`verify_talo_backend.gd` / `verify_match_rules.gd`):** Async lifecycle tests asserting `leave_lobby_channel()` bumps `_prop_gen` (preventing stale `_write_props` resurrection), `Lobby.leave()` race against immediate `join_auto()` preserves the new lobby, and `MatchState` `SYNC` emits `respawn_remaining()` instead of full `respawn_delay()`.
3. **Tier 3 (`python3 -m unittest` + Node `vm` script in `godot/tools/`):** Automated checks for `patch_web_sw.py` (`206` passthrough, `clearTimeout` cleanup, offline catch) and `inject_talo_key.py` (valid/invalid JWT, atomic write without double-close).

---

## 4. Surgical Refactoring Blueprints (Zero-Mutation Drafts)

### Refactor `[B-R1]`: Mode-Scoped, Rate-Limited `_register_lap()` & Separated `laps` Counter

- **Target Scope:** `godot/src/net/TaloBackend.gd:L667-L738` (and matching parity in `MockBackend.gd:L140-L204`)
- **Engineering ROI:** Eliminates both Backend P0 defects (`B-P0-1`, `B-P0-2`) in ~30 lines with zero new wire messages.

**Current Pattern (Audited Code):**

```gdscript
func _register_lap(args: Dictionary) -> Dictionary:
	...
	var row: Dictionary = _roster.get(racer, {})
	var score := int(row.get("score", 0)) + 1
	row["score"] = score
	_roster[racer] = row
	...
	var target_laps := maxi(1, int(s_dict.get("lap_target", 3)))
	if score >= target_laps:
		status = "finished"
		winner = racer
```

**Target Pattern (Surgical Blueprint):**

```gdscript
const MIN_LAP_SECONDS := 12.0
var _lap_timestamps: Dictionary = {}  # racer -> msec timestamp of last scored lap

func _register_lap(args: Dictionary) -> Dictionary:
	var token := str(args.get("p_token", ""))
	var racer := str(args.get("p_racer", user_id))
	if token == "" or racer == "":
		return {}
	if not _is_host():
		_send("lap_request", {"racer": racer, "token": token})
		return {"ok": true, "pending": true,
				"lobby_status": str(_lobby.get("status", "")),
				"winner_id": str(_lobby.get("winner_id", ""))}
	var s_dict := _lobby.get("settings", {}) as Dictionary
	if str(s_dict.get("game_mode", "battle_royale")) != "death_race":
		return {"ok": false, "reason": "wrong_mode"}
	if _used_tokens.has(token):
		return {"ok": false, "reason": "token_consumed"}
	if str(_lobby.get("status", "")) != "playing":
		return {"ok": false, "reason": "lobby_not_playing"}
	if not _roster.has(racer):
		return {"ok": false, "reason": "not_in_lobby"}
	var now_s := Time.get_ticks_msec() / 1000.0
	var last_lap := float(_lap_timestamps.get(racer, -MIN_LAP_SECONDS))
	if now_s - last_lap < MIN_LAP_SECONDS:
		return {"ok": false, "reason": "rate_limited"}
	_lap_timestamps[racer] = now_s
	_used_tokens[token] = true
	...
	var row: Dictionary = _roster.get(racer, {})
	var laps := int(row.get("laps", 0)) + 1
	row["laps"] = laps
	row["score"] = laps  # Death Race leaderboard tracks laps; _register_kill updates row["kills"] only
	_roster[racer] = row
	var target_laps := maxi(1, int(s_dict.get("lap_target", 3)))
	if laps >= target_laps:
		status = "finished"
		winner = racer
```

### Refactor `[B-R2]`: Per-Weapon Cooldown Gate & Roster Guard in `ArenaNet.gd`

- **Target Scope:** `godot/src/game/ArenaNet.gd:L18-L21,L111-L119,L234-L274`
- **Engineering ROI:** Blocks 24-meteor/s AOE & WebGL2 light-DoS attacks and eliminates ghost non-roster `StaticBody3D` proxies.

**Current Pattern (Audited Code):**

```gdscript
if kept.size() >= 24:
	return
...
var weapon_kind := str(p.get("w", "primary"))
if weapon_kind == "rocket":
	# unthrottled!
elif weapon_kind == "meteor":
	# unthrottled!
```

**Target Pattern (Surgical Blueprint):**

```gdscript
var _rocket_last: Dictionary = {}  # owner_id -> sec
var _meteor_last: Dictionary = {}  # owner_id -> sec
const REMOTE_ROCKET_MIN_S := 4.5
const REMOTE_METEOR_MIN_S := 5.5

# Inside _spawn_remote_shot():
var weapon_kind := str(p.get("w", "primary"))
if weapon_kind == "rocket":
	if now - float(_rocket_last.get(owner_id, -10.0)) < REMOTE_ROCKET_MIN_S:
		return
	_rocket_last[owner_id] = now
elif weapon_kind == "meteor":
	if now - float(_meteor_last.get(owner_id, -10.0)) < REMOTE_METEOR_MIN_S:
		return
	_meteor_last[owner_id] = now
elif weapon_kind != "primary":
	return
```

---

## 5. Phased Execution Roadmap & Scoped Agent Prompts

1. **Phase 1 — Containment & Safety Lock (`P0` Fixes + MVTH Baseline Tests):** Fix `B-P0-1` (mode + lap cooldown guard) and `B-P0-2` (separate `laps` vs `kills` in Death Race) across `TaloBackend.gd`, `MockBackend.gd`, and `MatchState.gd`, bump `PROTOCOL_VERSION` to `"2"` (`B-P1-2`), and lock with negative regression assertions in `verify_talo_backend.gd`.
2. **Phase 2 — Wire Security, Concurrency & State Hardening (`P1` Fixes):** Add `ArenaNet` per-weapon cooldowns + roster check (`B-P1-1`, `B-P1-5`), fix `TaloBackend` bounded reconnect loop + host-handoff ordering + `_prop_gen` bump on leave (`B-P1-3`, `B-P1-4`, `B-P1-7`), and guard `LobbyService.leave()` + dynamic `NetworkedBike` vehicle re-sync (`B-P1-6`).
3. **Phase 3 — Edge/Deploy Hardening & Modular Cleanup (`P2/P3` Refactors):** Fix `deploy_web.sh` to verify `index.service.worker.js` MD5 (`B-P2-1`), batch `Settings.apply_quality()` writes (`B-P2-3`), clear SW timeout + handle `206`/offline fetch (`B-P2-4`), and add deterministic scoreboard tie-breaks (`B-P2-5`).

### Copy-Paste Surgical Prompts for Coding Agents

> **Prompt `[B-P0-1/B-P0-2]` (`TaloBackend.gd`, `MockBackend.gd`, `verify_talo_backend.gd`):**
> "Strictly scope edits to `godot/src/net/TaloBackend.gd`, `godot/src/net/MockBackend.gd`, and `godot/tools/verify_talo_backend.gd`. In `_register_lap()`, reject calls unless `game_mode == 'death_race'` (`reason: 'wrong_mode'`) and enforce a per-racer `12.0 s` minimum lap cooldown (`reason: 'rate_limited'`). Separate `row['kills']` from `row['laps']` so `_register_kill()` in Death Race never increments the lap counter `row['score']`. Bump `PROTOCOL_VERSION` to `'2'`. Add regression assertions reproducing both exploits first, then run `bash godot/tools/run_gates.sh`."

> **Prompt `[B-P1-1/B-P1-5]` (`ArenaNet.gd`, `MatchState.gd`, `verify_multiplayer.gd`):**
> "Strictly scope edits to `godot/src/game/ArenaNet.gd`, `godot/src/net/MatchState.gd`, and `godot/tools/verify_multiplayer.gd`. Add per-sender `4.5 s` rocket and `5.5 s` meteor cooldown maps plus `['primary','rocket','meteor']` allowlist in `ArenaNet._spawn_remote_shot()`. Guard `_on_broadcast('state')` with `Match.players.has(id)`. Change `MatchState._on_pg_change` to emit `respawn_remaining(my_user_id)` instead of `respawn_delay()`. Add regression tests and run `bash godot/tools/run_gates.sh`."

> **Prompt `[B-P1-3/B-P1-4/B-P1-6/B-P1-7]` (`TaloBackend.gd`, `LobbyService.gd`, `NetworkedBike.gd`):**
> "Strictly scope edits to `godot/src/net/TaloBackend.gd`, `godot/src/net/LobbyService.gd`, and `godot/src/game/NetworkedBike.gd`. Hold `_reconnecting = true` across a bounded 5-attempt exponential-backoff reconnect loop; broadcast host-handoff `'state'` only after HTTP `PUT` returns `200`; bump `_prop_gen` in `leave_lobby_channel()`; guard `LobbyService.leave()` post-await clears with a session generation counter; re-evaluate `VehicleRegistry.for_player_in_roster()` inside `NetworkedBike.update_identity()`. Run `bash godot/tools/run_gates.sh`."
