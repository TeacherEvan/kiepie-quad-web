# Surgical Audit Report: Kiepie Quad (`TeacherEvan/kiepie-quad-web`)

| Audit Metadata | Specification |
| :--- | :--- |
| **Audit Date** | 2026-11-20 |
| **Audited Scope** | `godot/src/`, `godot/tools/`, `godot/tests/`, `src/`, `index.html`, `index.service.worker.js`, `.github/workflows/gates.yml` (`68` tracked first-party impl/tool files, `27` test/gate files, `17,297` impl effective LOC / `20,358` total first-party effective LOC, `198` inline HTML lines; vendored `godot/addons/` & Godot `index.js` excluded from defect count) |
| **Tech Stack & Runtime** | Godot 4.3 (`gl_compatibility` / WebGL2 WASM), GDScript, Talo v0.20.0 WebSocket/HTTP backend, Blender 5.3 Python (`bpy`/`bmesh`), PWA Service Worker, Vercel static hosting |
| **Pre/Post Audit SHA-256** | `768713865c57eba2 / 768713865c57eba2 (VERIFIED ZERO MUTATION — full: 768713865c57eba2748562e37f9c22faa646eee0e4f8e25e91072cc35afb89fa, HEAD 298d9f40351b3dc3e2cba05edd20b61d05738153)` |
| **Deterministic Health Score** | **`64 / 100`** (`D_raw = 119`, `P_test = 7.88`, `M_kill = 47.5%` over `17,297` impl effective LOC) |
| **Vibe-Debt Risk Level** | **`CRITICAL`** (`N_P0 = 2 >= 2`) |

## 1. Executive Architecture & Vibe-Debt Triage

Kiepie Quad (`TeacherEvan/kiepie-quad-web`) is a remarkably disciplined Blender-to-Godot-to-Vercel combat/racing pipeline with 27 automated gates, deterministic FNV-1a vehicle assignment, and solid WebGL2 compatibility habits (runtime-generated particle sprites, `MAX_IMPACT_LIGHTS = 8`, swept-ray projectiles, and frame-rate-independent `_integrate_forces` rollover immunity). However, rapid feature velocity in commit `298d9f4` and earlier Death Race / Talo passes left **two critical P0 defects** and **eight P1 operational/concurrency/release defects**: (1) `TaloBackend._on_socket_message()` copies untrusted `"join"` socket dictionaries straight into `_roster` without stripping or preserving `laps`/`kills`, allowing any guest to forge an instant 1-lap / 1-kill match victory (or silently wiping an honest reconnecting player's stats); (2) overlapping kill and death hitstops (`ArenaNet._do_hitstop()` + `CombatController._die()`) each capture and restore `Engine.time_scale`, permanently locking the entire engine in `0.25×`–`0.28×` slow-motion on mutual kills or scene exits; and (3) the shipped root Web bundle (`index.pck`, from `f6fa3d3`) is completely stale behind `HEAD` (`298d9f4`), meaning none of the latest reverse-thrust, 1.5 s rocket, cross-player damage-number, mushroom-cloud VFX, or Borat-mankini Nardus changes are live on Vercel. Meanwhile, the test suite (491 assertions across 27 gates) achieves only `M_kill = 47.5%` due to mock-channel blind spots, vacuous/shared-holder assertions (`verify_vfx.gd`, `verify_accessibility.gd`), and untested async failure / overlap paths.

| Severity Tier | Count | Deduction Weight | Primary Failure Domains |
| :--- | :--- | :--- | :--- |
| **P0 — Critical (Crash / Data Loss / Security / Leak)** | `2` | `-18 pts ea` | `godot/src/net/TaloBackend.gd` (`"join"` `laps`/`kills` injection & reconnect wipe); `godot/src/game/CombatController.gd` + `godot/src/game/ArenaNet.gd` (permanent `Engine.time_scale` slow-mo lock) |
| **P1 — High (Frame-Budget / Race / Logic Bug)** | `8` | `-8 pts ea` | Stale shipped `index.pck`; `Lobby.leave()` async race + stale `Match._settings_cache`; `TaloBackend` `_channel_id <= 0` bypass & missing reconnect resync; `RaceTracker` fail-open lap credit; AOE ghost damage numbers on invisible dead proxies; `VfxFactory` pre-tree `global_transform` + `reduced_motion` leaks + uncapped `Label3D`; `NetworkedBike` invisible `(0,0,0)` collider; `MatchState` per-call deep-dup + `time_up` race |
| **P2 — Medium (God File / Split-Brain State / Debt)** | `5` | `-3 pts ea` | 13 God files (`VfxFactory` 1,149 LOC, `TaloBackend` 869 LOC, `MatchHud` 680 LOC) + `VehicleRegistry`/`SideCannons` split-brain; missing `.vercelignore` exposing source/40 MB renders/audits; `vfx_light` group cleanup + `take_damage` NaN/negative guard + mushroom AABB; desktop touch-pad/CSS overlap + `MobileTextInput` missing `blur()` + OS `prefers-reduced-motion`; hot-loop `MatchHud._name_for` sort, `SideCannons` `_process` raycast, `SettingsMenu` debounce overwrite, unpruned `ArenaNet` peer maps |
| **P3 — Low (Magic Constants / DX / Portability)** | `4` | `-1 pt ea` | Unpinned CI action & unverified Godot binary download; unclamped `LobbyMenu` `OptionButton` indexing & dead `_light`/`_glow` fields; chained `FuelDrum` token reuse; missing `_exit_tree` disconnects in `MainMenu`/`Pickup` & `FollowCam` kill-cam guard |

### High-Risk File Telemetry Hotspots

| File Path | Effective LOC | Est. Cyclomatic Complexity / Branch Density | Silent Catches | Primary Vibe-Debt Signature |
| :--- | :--- | :--- | :--- | :--- |
| `godot/src/game/VfxFactory.gd` | `1149` | `CC 19 / 0.016` | `0` | God file (`1,390` raw lines); pre-tree `global_transform`; unguarded `reduced_motion` rings; uncapped `damage_number` |
| `godot/tools/build_deathrace.gd` | `917` | `CC 11 / 0.011` | `0` | Monolithic procedural track builder (`_initialize`, `_build_circuit`, `_add_stunt_loop` > 100 LOC) |
| `godot/src/net/TaloBackend.gd` | `869` | `CC 52 / 0.059` | `0` | God networking adapter; untrusted `"join"` dict clone; `_channel_id <= 0` filter bypass; reconnect state gap |
| `src/qb_core.py` | `487` | `CC 18 / 0.035` | `7` | 7 silent `except ...: pass` blocks in Blender material/collection helpers; God helper module |
| `godot/src/ui/MatchHud.gd` | `680` | `CC 51 / 0.073` | `0` | God HUD; unawaited `Lobby.leave()`; $O(N \log N)$ scoreboard sort inside `_name_for()` |
| `src/build_pogo_nardus.py` | `697` | `CC 21 / 0.029` | `0` | Top-level imperative script (`882` raw lines); zero modular function boundary for geometry/export |
| `godot/src/ui/MobileTextInput.gd` | `384` | `CC 24 / 0.034` | `3` | 60 Hz `JavaScriptBridge.eval` when open; missing `input.blur()` on `removeField()`; 3 JS silent catches |
| `godot/src/game/SideCannons.gd` | `479` | `CC 50 / 0.102` | `0` | Split-brain `_cooldown`/`_cooldowns` + duplicated `VehicleRegistry` stats; `_process` raycast fallback |
| `godot/src/TouchControls.gd` | `482` | `CC 38 / 0.077` | `0` | God input layer; `_relayout` overrides `-64` clearance to `-16`, overlapping Web hint strip |
| `godot/src/KiepieBike.gd` | `450` | `CC 52 / 0.113` | `0` | God physics/visual controller; exhaust flames/jet plume ignore `reduced_motion()` & quality |
| `godot/src/game/CombatController.gd` | `325` | `CC 35 / 0.092` | `0` | Uncoordinated `Engine.time_scale` hitstop lock; no `amount <= 0`/`NaN` guard in `take_damage()` |
| `godot/src/game/ArenaNet.gd` | `295` | `CC 41 / 0.142` | `0` | Competing `Engine.time_scale` hitstop; unpruned per-peer rate-limit maps on peer leave |
| `index.html` (inline Web shell) | `198` (raw) | `N/A (minified L80)` | `10` (inline JS) | Duplicate `<meta viewport>` (`user-scalable=no`); stale `GODOT_CONFIG.fileSizes` behind `HEAD` |

---

## 2. The 10-Principal-Engineer Deep Audit

### Lens 1 — Systems Architect

- **[P1-1] Shipped Web Production Bundle (`index.pck`) Is Stale Behind `HEAD` (`298d9f4`)** — `index.pck`, `index.html:L99`, `index.service.worker.js:L7`
  - **Root Cause Mechanism:** Commit `298d9f4` modified 10 runtime scripts, 7 scenes, and `Pogo_Nardus.glb` and pushed directly to `main` without re-exporting the Web bundle via `godot/tools/deploy_web.sh --apply`. Because Vercel auto-deploys static assets directly from the repository root on pushes to `main`, production serves `index.pck` (`3,378,400 B`) from `f6fa3d3`.
  - **Deterministic Trigger & Failure Mode:** Inspecting root `index.pck` confirms `mushroom_cloud_explosion`, `dramatic_death_explosion`, `note_local_damage_shown`, `ButtCheekRed`, `MankiniPink`, and `REMOTE_ROCKET_MIN_S` are all absent (`False`). Every live Web player still runs the pre-`298d9f4` game (`5.0 s` rocket reload, `180` reverse force, no cross-player `"hurt"` damage numbers, no mushroom cloud, old Nardus sculpt).
  - **Surgical Fix Specification:** Run `bash godot/tools/deploy_web.sh --apply` to export, patch SW, and commit refreshed `index.*` files. Add a CI check in `.github/workflows/gates.yml` (or git hook) warning/failing when `godot/src/` or `godot/scenes/` commits are newer than `index.pck`.

- **[P1-5] AOE Blasts (`RocketProjectile`, `MeteorStrike`, `FuelDrum`) Damage/Trigger Ghost Damage Numbers on Invisible Respawning Remote Bikes** — `godot/src/game/RocketProjectile.gd:L268-L291`, `godot/src/game/MeteorStrike.gd:L266-L289`, `godot/src/game/FuelDrum.gd:L83-L107`
  - **Root Cause Mechanism:** All three AOE loops scan `tree.get_nodes_in_group("bike")` and check only `is_instance_valid(b)` and `distance_to(point) <= blast_radius`, never checking `bike_node.visible` or `bool(bike_node.get("is_respawning"))`. When a remote peer dies, `NetworkedBike.set_respawning(true)` sets `visible = false` and `collision_layer = 0` while leaving the node at its death coordinates for `respawn_delay` seconds.
  - **Deterministic Trigger & Failure Mode:** Detonating a rocket, meteor, or chained fuel drum within `4.5 m` / `7.5 m` / `4.6 m` of a recently killed remote bike pops fake gold `-60` / `-105` / `-55` floating damage numbers over empty ground, flashes the shooter's `HitMarker`, and calls `_note_local_damage_shown(target_id)` (suppressing real damage numbers if the peer immediately respawns nearby).
  - **Surgical Fix Specification:** Add `if not bike_node.visible or bool(bike_node.get("is_respawning")): continue` immediately after `var bike_node := b as Node3D` in all three AOE blast loops.

- **[P2-1] God Files & Split-Brain Weapon/Cooldown State Across `VfxFactory`, `TaloBackend`, `MatchHud`, `SideCannons`, and `VehicleRegistry`** — `godot/src/game/VfxFactory.gd:L1-L1390`, `godot/src/net/TaloBackend.gd:L1-L1045`, `godot/src/ui/MatchHud.gd:L1-L813`, `godot/src/game/SideCannons.gd:L35-L48, L56-L61, L203-L212`, `godot/src/game/VehicleRegistry.gd:L82-L117`
  - **Root Cause Mechanism:** 13 tracked first-party files exceed 400 effective LOC (`VfxFactory.gd` = 1,149 LOC, `TaloBackend.gd` = 869 LOC, `MatchHud.gd` = 680 LOC). Additionally, `SideCannons.PROFILES` hardcodes 5 weapon stats (`cooldown`, `rapid_cooldown`, `damage_mult`, `spread`, `sfx`) duplicated from `VehicleRegistry.gd` (which `ArenaNet._spawn_remote_shot()` reads independently), and `SideCannons` maintains two synchronized cooldown variables (`_cooldown` + `_cooldowns`) via a bidirectional hack in `_process()`.
  - **Deterministic Trigger & Failure Mode:** Editing Nardus's `damage_mult` or `cooldown` in `SideCannons.PROFILES` silently diverges local shooter stats from `ArenaNet`'s remote projectile simulation (`VehicleRegistry.damage_multiplier()`). Setting `_cooldown` directly interacts subtly with `_process(delta)` ordering.
  - **Surgical Fix Specification:** Populate `SideCannons.PROFILES` from `VehicleRegistry` helpers (single source of truth), make `_cooldown` a pure getter/setter forwarding to `_cooldowns[current_weapon]`, and split `VfxFactory.gd` into `VfxSprites.gd`, `VfxCombat.gd`, and `VfxExplosions.gd` behind the existing `VfxFactory` facade.

### Lens 2 — Frame-Budget & Performance

- **[P1-8] `MatchState` Hot Getters Deep-Duplicate `_settings_cache` on Every Call** — `godot/src/net/MatchState.gd:L20, L110-L145`
  - **Root Cause Mechanism:** `MatchState` caches lobby settings in `_settings_cache` specifically to avoid per-frame deep duplication (`L20`), yet `kill_target()`, `game_mode()`, `lap_target()`, `max_players()`, `respawn_delay()`, `damage()`, and `pickups_enabled()` (`L118-L145`) all call `settings().get(...)`, which executes `_settings_cache.duplicate(true)` on every call. Only `time_limit_seconds()` (`L50`) reads `_settings_cache` directly.
  - **Deterministic Trigger & Failure Mode:** Every frame while dead (`MatchHud._process` calls `Match.respawn_delay()` at 60 Hz), on every shot (`SideCannons.fire` calls `Match.damage()`), and on every HUD refresh (`MatchHud._refresh_banner` calls `game_mode()`/`lap_target()`/`kill_target()`), a full recursive Dictionary copy is allocated and discarded on the WASM heap.
  - **Surgical Fix Specification:** Replace `settings().get(...)` with `_settings_cache.get(...)` across `L118-L145`, reserving `settings()`'s deep copy solely for external callers that need a mutable dictionary.

- **[P2-2] Unprotected Repo Root on Vercel Serves 40+ MB of Non-Game Assets & `index.pck` Approaches 4 MB Cap** — repo root (missing `.vercelignore`), `renders/`, `Kiepie_Bike.stl` (`2.2 MB`), `index.pck` (`3.3 MB`)
  - **Root Cause Mechanism:** No `.vercelignore` or `vercel.json` exists, so Vercel deploys the entire repository tree (including ~40 MB of PNG QA renders, `.blend`/`.stl` CAD files, raw scripts, and audit markdown/SARIF files). Meanwhile `index.pck` has grown from `2.7 MB` to `3.3 MB` (`3,378,400 B`), within `790 KB` of `deploy_web.sh`'s `4 MB` abort ceiling (`L59`), and `godot/assets/Kiepie_Bike.glb` (`1.5 MB`) is duplicated at repo root (`Kiepie_Bike.glb`, `1.5 MB`).
  - **Deterministic Trigger & Failure Mode:** Every deploy uploads ~60 MB of non-runtime artifacts to Vercel edge storage; adding one more GLB or WAV texture without compression will break `deploy_web.sh` at the 4 MB gate.
  - **Surgical Fix Specification:** Add a `.vercelignore` excluding everything except `index.*`, `favicon.ico`, and `web-assets/**`, and evaluate Draco/basis texture compression before adding further 3D assets.

- **[P2-5] Hot-Loop & Event-Path Waste (`MatchHud._name_for` Sort, `SideCannons` `_process` Raycast, `SettingsMenu` Debounce Overwrite, Unpooled `Sfx` Nodes)** — `godot/src/ui/MatchHud.gd:L641-L648, L736`, `godot/src/game/SideCannons.gd:L391`, `godot/src/ui/SettingsMenu.gd:L243-L245`, `godot/src/audio/Sfx.gd:L60-L68, L133`, `godot/src/game/PogoVisual.gd:L164-L168`
  - **Root Cause Mechanism:**
    1. `MatchHud._name_for(uid)` (`L644`) calls `Match.scoreboard()` (allocates array of dicts + `sort_custom`) twice per kill instead of $O(1)$ `Match.players.get(uid)`.
    2. `MatchHud._process()` (`L736`) queries `Settings.get_value("video", "show_fps", false)` at 60 Hz; `PogoVisual._physics_process()` (`L165`) calls `get_node_or_null("/root/Settings")` + `.call("reduced_motion")` at 60 Hz per Nardus.
    3. `SideCannons._update_aim_reticle()` (`L391`, called from `_process` and `_unhandled_key_input`) calls `compute_meteor_target()` -> `world.direct_space_state.intersect_ray()` outside `_physics_process` whenever `_has_cached_meteor` is `false`.
    4. `SettingsMenu._on_defaults()` (`L243-L245`) does not clear `_pending_writes` or stop `_flush_timer` (`0.35 s`), so dragging a slider and immediately clicking `Reset Defaults` causes the timer to overwrite the reset default back to the old slider value `0.35 s` later.
  - **Deterministic Trigger & Failure Mode:** Unnecessary GC churn in 8-player firefights, physics-space query warnings on weapon swap, and Settings `Reset Defaults` silently reverting within 350 ms of any slider drag.
  - **Surgical Fix Specification:** Direct-index `Match.players` in `_name_for()`, cache `show_fps` and `Settings` refs on `_ready`/`Settings.changed`, skip raycast until `_has_cached_meteor` is set in `_physics_process`, and clear `_pending_writes` + stop `_flush_timer` in `SettingsMenu._on_defaults()`.

### Lens 3 — Mathematical, Physics & Algorithmic

- **[P1-7] `NetworkedBike` Spawns Invisible Solid Collider at World Origin `(0, 0, 0)` Before First State Packet (and When Initial State Is Dead)** — `godot/src/game/NetworkedBike.gd:L30, L34-L41, L134-L140`
  - **Root Cause Mechanism:** `NetworkedBike.setup()` sets `visible = false` (`L30`) while enabling `collision_layer = 1` (`L40`) on a `0.95 × 0.7 × 2.1 m` `BoxShape3D` at `(0, 0.6, 0)`. Additionally, when the first `"state"` packet arrives with `d == true` (`L134-L140`), the function sets `is_respawning = true; visible = false` and returns early *without* calling `set_respawning(dead_now)` or zeroing `collision_layer`.
  - **Deterministic Trigger & Failure Mode:** Whenever a remote peer exists in `Match.players` before sending their first `bike_state` (or joins dead), an invisible solid box sits at arena origin `(0, 0, 0)` blocking the local bike and intercepting shots.
  - **Surgical Fix Specification:** Set `collision_layer = 0` in `setup()`, and inside the `if not _initialised:` branch set `collision_layer = 0 if dead_now else 1`.

- **[P2-3] `CombatController.take_damage` Lacks `amount <= 0` / `NaN` Guard + Mushroom Cloud `visibility_aabb` Clipping** — `godot/src/game/CombatController.gd:L154-L165`, `godot/src/game/VfxFactory.gd:L438, L902-L930`
  - **Root Cause Mechanism:** `take_damage()` computes `health = maxf(0.0, health - amount)` with no check for `amount <= 0.0` or `not is_finite(amount)`. Separately, `VfxFactory._particle()` hardcodes `visibility_aabb = AABB(Vector3(-8, -6, -8), Vector3(16, 16, 16))`, which clips the `mushroom_cloud_explosion` (`scale = 2.65`, stem rise `~45 m`, cap apex `~26 m`) above `y = 26.5 m` world space.
  - **Deterministic Trigger & Failure Mode:** A negative `amount` heals above `MAX_HEALTH` (or `NaN` poisons `health` so `health <= 0.0` is permanently `false` — accidental god-mode); looking upward at a Meteor mushroom cap near the camera frustum edge can pop the entire emitter out of visibility.
  - **Surgical Fix Specification:** Guard `take_damage()` with `if not is_finite(amount) or amount <= 0.0: return`, and support an `"aabb"` key in `_particle()` sized to `AABB(Vector3(-18, -6, -18), Vector3(36, 48, 36))` for `mushroom == true`.

- **[P3-3] Chained `FuelDrum` Kills Reuse a Single Shot Token & Hit 1.0 s Per-Killer Cooldown** — `godot/src/game/FuelDrum.gd:L110-L124`, `godot/src/net/TaloBackend.gd:L669-L683`
  - **Root Cause Mechanism:** `FuelDrum.ignite()` schedules chained drums `0.18 s` later passing the identical `token` (`L123`). `TaloBackend._register_kill()` marks `token` consumed on the first victim and enforces a `1.0 s` per-killer cooldown (`L682`).
  - **Deterministic Trigger & Failure Mode:** Shooting a cluster of fuel drums that kills two enemies `0.18 s` apart awards only 1 kill; the second kill fails with `token_consumed` (and would also fail `rate_limited` within `1.0 s`).
  - **Surgical Fix Specification:** Derive distinct chain tokens (`"%s:c%d" % [token, get_instance_id()]`) and allow same-blast multi-kills (e.g., 2 kills within a `0.5 s` burst sharing a base token prefix) while retaining the 20/min window.

- **[P3-4] `FollowCam` Kill-Cam Missing Collinearity Guard & Shake Feedback Into Follow Lerp** — `godot/src/FollowCam.gd:L73, L114-L117`
  - **Root Cause Mechanism:** Kill-cam (`L73`) calls `look_at(_spectate_target.global_position + look_offset, Vector3.UP)` without the collinearity guard applied in follow mode (`L105-L113`), and screen shake (`L116`) mutates the rig's `global_position` directly, which becomes the starting point for next frame's `global_position.lerp(desired, ...)` (`L96`).
  - **Deterministic Trigger & Failure Mode:** Spectating a target while pitched near zenith triggers Godot's collinear `look_at()` warning; heavy death/meteor shakes (`0.68`–`0.82`) introduce slight post-shake camera drift.
  - **Surgical Fix Specification:** Apply shake offset to the child `_cam.position` (resetting to `Vector3.ZERO` when `_shake <= 0.001`) and share a single `_safe_look_at(target, up)` helper for both follow and spectate modes.

### Lens 4 — Concurrency, Async & Determinism

- **[P0-2] Permanent `0.25×`/`0.28×` Slow-Motion Lock on Overlapping Kill & Death Hitstops + Unrestored `Engine.time_scale` on Scene Exit** — `godot/src/game/CombatController.gd:L146-L151, L204-L212`, `godot/src/game/ArenaNet.gd:L193-L203`
  - **Root Cause Mechanism:** Both `ArenaNet._do_hitstop()` (`Engine.time_scale = 0.28`, `60 ms`) and `CombatController._die()` (`Engine.time_scale = 0.25`, `55 ms`) independently save `var prev := Engine.time_scale` and restore `Engine.time_scale = prev` when their timer completes. Neither coordinates with the other, and `CombatController._exit_tree()` (`L146-L151`) never resets `Engine.time_scale = 1.0`.
  - **Deterministic Trigger & Failure Mode:** Player kills an enemy at `t = 0 ms` (`ArenaNet` captures `1.0`, sets `0.28`). At `t = 20 ms`, an enemy rocket/meteor kills the player (`CombatController` captures `prev_scale = 0.28`, sets `0.25`). At `t = 60 ms`, `ArenaNet` restores `1.0`. At `t = 75 ms`, `CombatController`'s timer fires and writes `Engine.time_scale = 0.28`, permanently locking the entire game in `0.28×` slow-motion! Likewise, pressing `Esc` / `MenuBtn` in TestRide within `55 ms` of dying leaves `Engine.time_scale = 0.25` in `MainMenu`.
  - **Surgical Fix Specification:** Route all hitstops through a single refcounted helper (e.g., `KiepieTime.request_hitstop(tree, scale, duration)` or a `Match`/`Settings` counter) that sets `Engine.time_scale = minf(...)` while `active > 0` and **always** restores `Engine.time_scale = 1.0` when `active == 0` (plus unconditional `Engine.time_scale = 1.0` in `CombatController._exit_tree()`).

- **[P1-2] Async `Lobby.leave()` Fire-and-Forget Race Traps Returning Players in Stale Lobby & Leaves Stale `Match._settings_cache`** — `godot/src/ui/LobbyMenu.gd:L76, L390-L395`, `godot/src/ui/MatchHud.gd:L718-L721`, `godot/src/net/LobbyService.gd:L65-L79`
  - **Root Cause Mechanism:** Both `LobbyMenu._on_leave()` and `MatchHud._on_leave_match()` call the `async` coroutine `Lobby.leave()` without `await` and immediately execute `get_tree().change_scene_to_file(MAIN_MENU)`. Inside `Lobby.leave()`, `Match.lobby` and `Match.players` are cleared only *after* `await Supabase.call_rpc("leave_lobby")` finishes (which includes up to 2 HTTP PUT host-handoff attempts). Worse, `LobbyService.gd:L77-L78` overwrites `Match.lobby = {}` directly without calling `Match._refresh_settings_cache()`, leaving the previous lobby's settings cached in `Match._settings_cache`.
  - **Deterministic Trigger & Failure Mode:** Clicking Leave and rapidly clicking Create / Join Auto on `MainMenu` enters `LobbyMenu._ready()` while `Match.lobby` is still non-empty (`L76: if Match.lobby.is_empty():` is `false`), aborting new room creation and stranding the user in the stale lobby. Leaving a Death Race lobby and entering Practice/TestRide inherits stale `Match._settings_cache` (`game_mode == "death_race"`, custom damage/timer).
  - **Surgical Fix Specification:** Add `Match.clear_lobby()` (clearing `lobby`, `players`, `_settings_cache`, and `_time_up_called`, then emitting signals), invoke `Match.clear_lobby()` synchronously at the top of `Lobby.leave()` before awaiting the network leave/handoff, and `await Lobby.leave()` (with button disabled) before switching scenes.

- **[P1-3] `TaloBackend._on_socket_message` Processes Frames After Lobby Leave (`_channel_id <= 0`) & Reconnect Never Resyncs Channel State** — `godot/src/net/TaloBackend.gd:L151-L170, L822-L824`
  - **Root Cause Mechanism:** Line 823 checks `if ch is Dictionary and _channel_id > 0 and int((ch as Dictionary).get("id", _channel_id)) != _channel_id: return`. When `_channel_id <= 0` (after `leave_lobby_channel()`), the channel check is skipped entirely, allowing late `"join"`, `"leave"`, `"kill"`, `"hurt"`, `"bike_state"`, and `"shot"` frames to mutate `_roster` and emit signals into `MainMenu`/`TestRide`. Furthermore, `_on_socket_closed()` (`L151-L170`) re-opens the WebSocket after a transient drop but never fetches `Talo.channels.find(_channel_id)` to reload missed `"state"` props (match start, host handoff, or winner).
  - **Deterministic Trigger & Failure Mode:** Late socket frames after leaving a lobby repopulate `_roster` and trigger `Match.roster_changed`; a brief mobile Wi-Fi/LTE drop during a match leaves the reconnected client permanently out of sync with host scoreboard/status transitions that occurred during the outage.
  - **Surgical Fix Specification:** Drop socket messages immediately when `_channel_id <= 0` (updating unit gates to stage `_channel_id = 1`), and on successful reconnect inside `_on_socket_closed()` re-fetch `Talo.channels.find(_channel_id)`, call `_load_state()`, `_emit_state()`, and `_emit_roster()`.

- **[P1-8b] `MatchState._process` `time_up` Coroutine Lacks Post-`await` Lobby-ID Guard** — `godot/src/net/MatchState.gd:L53-L70`
  - **Root Cause Mechanism:** `_process()` awaits `Supabase.call_rpc("time_up", {})` (`L65`) and unconditionally applies `apply_lobby(res)` (`L67`) when it resumes, without verifying that the active lobby ID has not changed or been cleared during the network round-trip.
  - **Deterministic Trigger & Failure Mode:** Host leaves a timed match at `t = match_seconds` right as `time_up` fires; when the RPC resolves 200 ms later, `apply_lobby(res)` overwrites the cleared or newly created lobby with the old finished match and triggers `match_finished`.
  - **Surgical Fix Specification:** Capture `var lobby_id := str(lobby.get("id", ""))` before `await` and abort if `str(lobby.get("id", "")) != lobby_id`.

### Lens 5 — Memory & Resource Lifecycle

- **[P1-6] `VfxFactory._build_death_wreck` Writes `global_transform` Before Tree Attachment + Uncapped `damage_number` & Missing Outline Fade** — `godot/src/game/VfxFactory.gd:L1062, L1148-L1149, L1316-L1341`
  - **Root Cause Mechanism:** `_build_death_wreck()` sets `wreck.global_transform = ...` (`L1062`) before `dramatic_death_explosion()` attaches `wreck` to `parent` (`L1149`), violating Godot 4.3's `is_inside_tree()` precondition for `global_transform`. In addition, `damage_number()` (`L1316-L1341`) has no cap group (unlike `MAX_SCORCH`/`MAX_SCAR`/`MAX_WRECKS`) and tweens `modulate:a` to `0.0` without tweening `outline_modulate:a`, leaving dark outline ghosts until `queue_free()`. Finally, `VfxFactory.casing()` (`L681-L682`) leaks `body` unfreed when `parent.get_tree() == null`.
  - **Deterministic Trigger & Failure Mode:** Every player death logs `!is_inside_tree()` errors (or misplaces the wreck under non-identity parents); 8-player rapid fire with `"hurt"` broadcasts (up to 24/s per peer) can spawn 60+ concurrent `Label3D` glyph meshes on WebGL2; damage numbers leave dark outline ghosts for their final 0.4 s.
  - **Surgical Fix Specification:** Call `parent.add_child(wreck)` before setting `wreck.global_transform` (or set local `wreck.transform`), group `damage_number` under `"vfx_dmg_num"` with `_cap_group(parent, "vfx_dmg_num", 18)`, parallel-tween `outline_modulate:a` to `0.0`, and free `body` in `casing()`'s `tree == null` branch.

- **[P2-3b] `RocketProjectile` & `MeteorStrike` Never Remove `_light` from `"vfx_light"` Before `queue_free()` + `ArenaNet` Unpruned Peer Maps** — `godot/src/game/RocketProjectile.gd:L184-L190, L235-L236`, `godot/src/game/MeteorStrike.gd:L191-L198, L234-L235`, `godot/src/game/ArenaNet.gd:L348-L353`
  - **Root Cause Mechanism:** `RocketProjectile` and `MeteorStrike` add `_light` to `"vfx_light"` and call `queue_free()` right after spawning their detonation explosion (which immediately calls `_cap_group(..., "vfx_light", MAX_IMPACT_LIGHTS)` while the dying projectile's light is still in the group for the rest of the frame). Separately, `ArenaNet._sync_roster()` erases departed peers from `_remote` but never clears `_shot_log`, `_rocket_last`, `_meteor_last`, `_death_gen`, or `_local_dmg_shown_at`.
  - **Deterministic Trigger & Failure Mode:** Simultaneous rocket/meteor detonations prematurely evict active explosion flash lights on the frame of impact; long multi-round sessions accumulate stale peer IDs in 5 `ArenaNet` dictionaries.
  - **Surgical Fix Specification:** Remove `_light` from `"vfx_light"` in `_detonate()` and `_exit_tree()` of both scripts; erase departed `id` from all 5 tracking dictionaries inside `ArenaNet._sync_roster()`.

- **[P3-4b] Missing `_exit_tree()` Autoload Signal Disconnects in `MainMenu` & `Pickup`** — `godot/src/ui/MainMenu.gd:L57-L59`, `godot/src/game/Pickup.gd:L76-L77`
  - **Root Cause Mechanism:** `MainMenu` connects to `Supabase.auth_status`, `Lobby.error_message`, `Match.error_message`, and `get_viewport().size_changed` without disconnecting in `_exit_tree()`; `Pickup` connects to `Match.lobby_changed` without disconnecting in `_exit_tree()`.
  - **Deterministic Trigger & Failure Mode:** If an autoload emits during the deferred `queue_free()` window on scene transition, handlers run on dying UI/pickup nodes.
  - **Surgical Fix Specification:** Mirror `LobbyMenu._exit_tree()` / `MatchHud._exit_tree()` and explicitly disconnect all autoload signals on `_exit_tree()`.

### Lens 6 — Security & Trust-Boundary

- **[P0-1] Untrusted `"join"` Socket Payload Injection Allows Instant Win (`laps`/`kills` Forgery) & Mid-Match Stat Wipe** — `godot/src/net/TaloBackend.gd:L869-L888`
  - **Root Cause Mechanism:** When handling `"join"` in `_on_socket_message()`, line 872 starts with `var row := p.duplicate(true)` (cloning the untrusted remote JSON dictionary wholesale) and only overwrites `user_id`, `display_name`, `color`, `score`, `is_ready`, and `respawn_at`. It neither strips unknown keys nor preserves `laps` and `kills` from `prev`.
  - **Deterministic Trigger & Failure Mode:**
    1. **Exploit (Instant Win):** Any connected guest sends a single Talo channel message `{"k":"join","p":{"user_id":"<own_alias_id>","display_name":"H","color":"#ff0000","laps":99,"kills":99}}`. Because `uid == sender_id`, the alias check passes, `_roster[uid]` stores `laps: 99, kills: 99`, and the host commits it via `_apply_props()`. On the guest's next single lap (`_register_lap:L764`) or single kill (`_register_kill:L701`), `99 + 1 = 100 >= target`, immediately finishing the match with the attacker as `winner_id`!
    2. **Honest Data Loss:** Any honest player whose client re-sends `"join"` mid-match (which only includes `user_id`, `display_name`, `color`) has their accumulated `kills` and `laps` reset to missing/0 on the host even though `score` is preserved.
  - **Surgical Fix Specification:** Replace `var row := p.duplicate(true)` with a strict allowlist dictionary containing ONLY `user_id`, `display_name`, `color`, and copy `score`, `kills`, `laps`, `is_ready`, and `respawn_at` strictly from `prev` (or defaults `0`/`0`/`0`/`false`/`""`).

- **[P2-2b] Public Exposure of Internal Audits, CAD Sources & Scripts on Vercel Root** — repo root (no `.vercelignore`), `docs/audits/*`
  - **Root Cause Mechanism:** Vercel serves the entire repository root statically, making `docs/audits/*.md` (which document exact protocol internals and historical exploits) and `godot/src/**/*.gd` publicly downloadable at `https://kiepie-quad-web.vercel.app/docs/audits/...`.
  - **Deterministic Trigger & Failure Mode:** Any attacker can fetch the full audit ledger and source scripts directly from the game origin.
  - **Surgical Fix Specification:** Add `.vercelignore` blocking everything outside the Web runtime bundle (`index.*`, `favicon.ico`, `web-assets/**`).

- **[P3-1] Unpinned GitHub Action & Unverified Godot Binary Download in CI** — `.github/workflows/gates.yml:L17-L27`
  - **Root Cause Mechanism:** Workflow uses floating tag `actions/checkout@v4` and pipes `curl -fL .../Godot_v4.3-stable_linux.x86_64.zip` directly to `sudo install` with no SHA-256 verification.
  - **Deterministic Trigger & Failure Mode:** Upstream tag re-pointing or release archive tampering executes arbitrary code in CI with `sudo`.
  - **Surgical Fix Specification:** Pin `actions/checkout` by full 40-char commit SHA, assert the official Godot 4.3-stable Linux x86_64 SHA-256 digest before `unzip`, and update the step title from `25 total` to `27 total`.

### Lens 7 — Reliability & Fault Tolerance

- **[P1-4] `RaceTracker._on_finish_line_entered` Fails Open on Backend/Token Errors & Credits Unverified Laps** — `godot/src/game/RaceTracker.gd:L121-L140`
  - **Root Cause Mechanism:** When `was_live_match == true`, if `Match.issue_shot()` fails (`tok == ""`), the `if tok != "":` branch (`L127`) is skipped and `completed_laps += 1` (`L139`) still executes. Likewise, if `Match.register_lap(tok)` fails with `{}` (backend not ready/timeout) or `"not_in_lobby"`, the error is absent from the 5-item denylist (`L133`), so `completed_laps` increments locally anyway and can trigger `race_won` + victory splash.
  - **Deterministic Trigger & Failure Mode:** Crossing `FinishLine` during a brief backend disconnect credits a ghost lap locally, desynchronizing `RaceTracker.completed_laps` from `Match.players[uid]["score"]` and falsely celebrating victory on a client the host never scored.
  - **Surgical Fix Specification:** Fail closed in live matches: if `tok == ""` or `not bool(lap_res.get("ok", false))`, set `_finishing_lap = false` and `return` without incrementing `completed_laps`.

### Lens 8 — Type Systems, Schema & Contracts

- **[P3-2a] Unclamped `OptionButton.selected` Indexing in `LobbyMenu._push_settings`** — `godot/src/ui/LobbyMenu.gd:L345-L349`
  - **Root Cause Mechanism:** `_kill_target.selected`, `_max_players.selected`, `_respawn.selected`, `_match_seconds.selected`, and `_damage.selected` index directly into constant arrays without `clampi(..., 0, arr.size() - 1)` (unlike `_game_mode` and `_lap_target` on `L342, L344`).
  - **Deterministic Trigger & Failure Mode:** If any dropdown triggers `_push_settings()` while unselected (`selected == -1`), GDScript negative indexing silently selects the **maximum** value (`kill_target = 20`, `damage = 50`, `match_seconds = 600`).
  - **Surgical Fix Specification:** Wrap all 5 array lookups with `clampi(opt.selected, 0, ARR.size() - 1)`.

### Lens 9 — Platform, Viewport & Portability

- **[P1-6b] Reduced-Motion Violations Across Mushroom Cloud Wilson Ring, `smash_burst`, Projectiles & Exhaust Flames** — `godot/src/game/VfxFactory.gd:L931-L936, L1260-L1262`, `godot/src/game/RocketProjectile.gd:L192-L217`, `godot/src/game/MeteorStrike.gd:L199-L232`, `godot/src/game/Projectile.gd:L161-L177`, `godot/src/game/BananaProjectile.gd:L187-L217`, `godot/src/KiepieBike.gd:L367-L376`
  - **Root Cause Mechanism:** `VfxFactory.particle_explosion(..., mushroom=true)` spawns the Wilson condensation ring (`L932-L936`) with **no `if not reduced:` guard**, and `smash_burst()` (`L1260-L1262`) still spawns an animated `4.0×` `_ring_quad` under Reduced Motion. All 4 projectile/meteor scripts and `KiepieBike`'s exhaust flames/68 rad/s pulsing jet cone ignore `Settings.reduced_motion()` completely.
  - **Deterministic Trigger & Failure Mode:** Users enabling `Reduced Motion` still see full-screen pulsing rings on meteor impacts/building collapses, `24 rad/s` pulsing meteor danger rings, tumbling boulders, and `68 rad/s` flickering jet plumes.
  - **Surgical Fix Specification:** Guard Wilson ring, projectile trails/spins, meteor pulse/tumble, and exhaust flames/jet pulse with `Settings.reduced_motion()`, substituting `_static_cue()` where visual feedback is required.

- **[P2-4] Desktop Touch-Toggle Overlap with Web Hint Strip, Missing `MobileTextInput` `blur()`, Missing OS `prefers-reduced-motion` Sync & Duplicate Viewport Meta** — `godot/src/TouchControls.gd:L90, L605`, `godot/src/ui/MobileTextInput.gd:L416-L423`, `godot/src/core/Settings.gd:L437-L438`, `index.html:L5, L80`
  - **Root Cause Mechanism:**
    1. `TouchControls._ready()` (`L90`) positions `AnalogSteer` at `offset_bottom = -64.0` to clear `index.html:L80`'s fixed desktop hint strip (`bottom: 16px`), but `_relayout()` (`L605`) overwrites it to `-16.0` on standard viewports (`>= 700×520`), causing direct visual overlap when `TOUCH: ON` is toggled on desktop.
    2. `MobileTextInput.js` `removeField()` (`L416-L423`) hides `#kiepie-vk-overlay` on scene unload without calling `input.blur()`, leaving mobile OS virtual keyboards open over the 3D arena canvas.
    3. `Settings.gd` never queries `window.matchMedia('(prefers-reduced-motion: reduce)').matches` on Web first-boot, diverging from `index.html` which skips splash videos automatically.
    4. `index.html` ships two `<meta name="viewport">` tags (`L5` has `user-scalable=no`, conflicting with WCAG 2.1 SC 1.4.4 zoom guidance, while `L80` appends `viewport-fit=cover`).
  - **Deterministic Trigger & Failure Mode:** Desktop players toggling `TOUCH: ON` see `AnalogSteer` cover `"KIEPIE QUAD · W / ↑ drive..."`; mobile players navigating away while a text field is open keep an orphaned OS keyboard covering half the screen.
  - **Surgical Fix Specification:** Keep `offset_bottom = -56.0` on wide desktop (`vp.x >= 720.0`) in `TouchControls._relayout()`, call `try { input.blur(); } catch (_) {}` in `removeField()`, seed default `reduced_motion` from `matchMedia` on first Web boot when no saved config exists, and consolidate to one accessible `<meta name="viewport">` tag.

### Lens 10 — Cognitive Load & AI Maintainability

- **[P3-2b] Dead Light Fields, Duplicate Resets, Stale Gate Docs & `qb_core.py` Silent Catches** — `godot/src/game/Projectile.gd:L21, L190-L191`, `godot/src/game/BananaProjectile.gd:L19`, `godot/src/game/Pickup.gd:L15, L72, L126-L127`, `godot/src/TouchControls.gd:L520-L529`, `godot/tools/verify_deathrace.gd:L4`, `src/qb_core.py:L39-L42, L76-L79, L96-L99`
  - **Root Cause Mechanism:** Dead `_light`/`_glow` variables remain from the WebGL2 8-light refactor and are still null-checked inside 60 Hz loops (`Projectile._physics_process`, `Pickup._process`); `TouchControls._release_all()` assigns `_analog_turbo = false; _analog_reverse = false` twice; `verify_deathrace.gd:L4` still documents `5s CD`; `src/qb_core.py` contains 7 bare/broad `except ...: pass` blocks that hide Blender API regressions across version upgrades.
  - **Deterministic Trigger & Failure Mode:** Wastes agent/maintainer context and masks Blender 5.x API deprecation errors in `qb_core.py`.
  - **Surgical Fix Specification:** Delete dead `_light`/`_glow` fields and duplicate lines, update stale header comments, and log warnings in `qb_core.py` exception handlers instead of silent `pass`.

### Pass 2.5 — Web Shell, WCAG 2.2 & Artefact Probe Summary

- **Contrast Verification (WCAG 2.2 AA `>= 4.5:1` / AAA `>= 7:1`):** All audited text tokens pass AA/AAA cleanly: `#ff7a1a` on `#060a1c` (`7.54:1`), `#ffd16b` on `#060a1c` (`13.66:1`), hint `rgba(232,238,255,.68)` on `#060a1c` (`8.01:1`), `UiTheme.TEXT` on `SURFACE_BUTTON` (`14.68:1`), `UiTheme.MUTED` (`7.60:1`), `UiTheme.DANGER` (`7.19:1`), `MobileTextInput` submit `#090b10` on `#ff8c29` (`8.47:1`).
- **Target Size (`2.5.8`) & Focus (`2.4.11`):** `#splash-skip` / `#victory-skip` (`min-height: 44px`, `:focus-visible` 2px `#ff7a1a` outline, `forced-colors`/`prefers-contrast` media query present) and `UiTheme` buttons (`min_h = 44–52px`) pass.
- **Rendered/Shipped Artefact Failures Found:** (1) `index.pck` at root lacks all `298d9f4` symbols (`P1-1`), (2) `TouchControls._relayout()` overlaps `index.html`'s desktop `body::before`/`body::after` strip at `bottom: 16px` (`P2-4`), and (3) duplicate `<meta name="viewport">` with `user-scalable=no` (`P2-4`).

---

## 3. Existing Test Suite Comparison & Mutation Truth Table

- **Test-to-Code File Ratio:** `27 / 68` (`0.40` — `3,061` test LOC vs `17,297` first-party impl LOC)
- **Estimated Mutation Kill Score ($M_{\text{kill}}$):** **`47.5%`** (`491` assertions across `27` gate/test files, `26` files with negative/boundary signals, `10` mock-backed files, `7` unpaired critical modules: `Sfx.gd`, `LobbyMenu.gd` leave-race/options, `HazardPit.gd` damage logic, `LobbyService.gd` leave/cache, `patch_web_sw.py`, `inject_talo_key.py`, `index.html`/`index.service.worker.js`)
- **Shipped-Module Proof:** While `godot/src/` modules normally pack into `index.pck`, binary verification shows **none of the new `298d9f4` code exercised by `verify_vfx.gd`, `verify_deathrace.gd`, `verify_multiplayer.gd`, and `verify_pogo.gd` currently ships in root `index.pck`** (0% deployed coverage for `298d9f4` until `deploy_web.sh --apply` runs).

| Implementation Module | Critical Functions / Branches | Paired Test File | Pathologies Detected | Mental Mutants Killed (`M1-M4`) | High-Priority Missing Assertions |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `godot/src/net/TaloBackend.gd` | `_on_socket_message`, `_register_kill`, `_register_lap`, `_on_socket_closed` | `verify_talo_backend.gd`, `verify_audit_regressions.gd`, `verify_multiplayer.gd` | Happy-Path Tunnel Vision (`join` extra keys), Mock-Mirror (`_channel = null`, `_channel_id = -1`) | `2/4 (50%)` | `"join"` `laps`/`kills` stripping, `_channel_id <= 0` drop, reconnect channel resync |
| `godot/src/game/ArenaNet.gd` | `_on_broadcast`, `_spawn_remote_shot`, `_do_hitstop`, `_sync_roster` | `verify_multiplayer.gd`, `verify_audit_regressions.gd` | Time-Window Myopia, Happy-Path Tunnel Vision | `2/4 (50%)` | `REMOTE_ROCKET_MIN_S` (`1.15 s`), `> 5.0 m` origin rejection, concurrent hitstop, map pruning |
| `godot/src/game/CombatController.gd` | `take_damage`, `_die`, `_respawn`, `_on_projectile_hit` | `verify_combat.gd`, `verify_practice.gd` | Happy-Path Tunnel Vision, Shared Mutable State (`Engine.time_scale`) | `1/4 (25%)` | `amount <= 0` / `NaN`, overlapping kill+death `Engine.time_scale`, `_exit_tree` restore |
| `godot/src/game/VfxFactory.gd` | `particle_explosion`, `mushroom_cloud_explosion`, `dramatic_death_explosion`, `damage_number` | `verify_vfx.gd`, `verify_audit_regressions.gd` | **No-Throw Theater** (shared `holder` `emitters >= 6` passes even if mushroom deleted!) | `1/4 (25%)` | Isolated mushroom cap/stem check, Wilson ring under `reduced_motion`, wreck tree order, `Label3D` cap & outline fade |
| `godot/src/game/RaceTracker.gd` | `_on_checkpoint_entered`, `_on_finish_line_entered` | `verify_deathrace.gd` | Happy-Path Tunnel Vision | `2/4 (50%)` | Empty `issue_shot` token fail-closed, `register_lap` `{}`/`not_in_lobby` rejection |
| `godot/src/game/RocketProjectile.gd` & `MeteorStrike.gd` | `_detonate`, radial falloff, AOE loops | `verify_deathrace.gd` | Happy-Path Tunnel Vision | `1/4 (25%)` | Invisible/respawning remote proxy skipped in AOE, outer falloff boundary, `vfx_light` removal |
| `godot/src/KiepieBike.gd` | `_physics_process`, `_integrate_forces`, `_try_dodge`, `reset_bike` | `verify_controls.gd`, `verify_dodge.gd`, `verify_rollover.gd`, `verify_pogo.gd` | **Result-Only / Property-Only** (`reverse_force >= 250.0` never drives in reverse) | `3/4 (75%)` | Live reverse velocity test (`move_back` at `forward_speed` < 2.5 vs > 2.5), `reduced_motion` flames |
| `godot/src/TouchControls.gd` | `_on_pointer_*`, `_sync_analog`, `_sync_drive`, `_relayout` | `verify_touch.gd`, `verify_touch_multitouch.gd`, `test_kiepie_pad.gd` | Viewport Gap (no desktop CSS hint-strip rect check) | `3/4 (75%)` | Desktop `1280×720` `AnalogSteer` clearance above `bottom: 16px` Web hint strip |
| `godot/src/net/MatchState.gd` & `LobbyService.gd` | `apply_lobby`, `set_lobby`, `leave`, `_process` (`time_up`) | `verify_match_rules.gd`, `verify_audit_regressions.gd`, `test_kiepie_pad.gd` | Happy-Path Tunnel Vision | `2/4 (50%)` | `Lobby.leave()` clearing `_settings_cache`, `time_up` lobby-switch race |
| `godot/src/ui/MatchHud.gd` & `LobbyMenu.gd` | `_relayout`, `_on_leave`, `_on_match_finished`, `_push_settings` | `verify_multiplayer.gd`, `verify_deathrace.gd`, `verify_accessibility.gd` | **Vacuous Assertion** (`verify_accessibility.gd:L89-93` pads always `null` before `_ready`) | `2/4 (50%)` | Awaited `Lobby.leave()` before scene change, `OptionButton.selected == -1` clamp, `AnalogSteer`/`AnalogDrive` post-`_ready` focus check |

### Why Existing Tests Missed Discovered P0/P1 Defects

- **P0-1 (`TaloBackend` `"join"` `laps`/`kills` injection):** `verify_audit_regressions.gd:L62-67` tested a forged `"join"` with a *mismatched* `user_id` (`"999"` from alias `7`), which failed at the alias check (`L865`) before ever reaching the sanitization block (`L872-L888`). No test sent a matching-alias `"join"` carrying extra keys (`laps: 99, kills: 99`) or re-joined an existing player with nonzero `laps`/`kills`.
- **P0-2 (`Engine.time_scale` slow-motion lock):** `verify_combat.gd` and `verify_multiplayer.gd` never trigger `ArenaNet._do_hitstop()` and `CombatController._die()` concurrently (nor assert `Engine.time_scale == 1.0` after 100 ms or after freeing `CombatController` mid-hitstop).
- **P1-1 (Stale `index.pck`):** `run_gates.sh` runs directly against `godot/` source files, never inspecting root `index.pck`.
- **P1-2 (`Lobby.leave()` race & stale `_settings_cache`):** `verify_match_rules.gd:L60` calls `lobby.call("leave")` and immediately calls `quit()` on the next line without checking `Match._settings_cache` or re-entering `LobbyMenu`.
- **P1-3 (`_channel_id <= 0` bypass):** All `TaloBackend` gates intentionally stage `_channel_id = -1` to prevent HTTP calls, masking the fact that `_on_socket_message()` should drop live frames when no channel is active.
- **P1-4 (`RaceTracker` fail-open):** `verify_deathrace.gd` only tests the `MIN_LAP_SECONDS` `"rate_limited"` rejection (which IS in the 5-item denylist), never testing an empty `issue_shot()` token or `{}` network failure.
- **P1-5 (AOE ghost damage numbers):** `verify_deathrace.gd:L182-195` only tests a *visible* `dummy_proxy`, never a `visible = false` / `is_respawning = true` remote proxy inside blast radius.
- **P1-6 (`VfxFactory` Wilson ring / shared `holder`):** `verify_vfx.gd:L102-123` reuses one `holder` across 10 effects and checks `emitters >= 6` with `reduced_motion = false`, so the Wilson ring under `reduced_motion = true` and mushroom-specific deletion are never isolated.

### Minimal Viable Test Harness (MVTH) Specifications

1. **Tier 1 — `TaloBackend` `"join"` Allowlist & Channel-Active Contract (`verify_talo_backend.gd`):**
   - Stage `_channel_id = 1`, send matching-alias `"join"` with `{"user_id": "2", "laps": 99, "kills": 99, "score": 99}` -> assert `laps == 0`, `kills == 0`, `score == 0`.
   - Award 1 lap + 1 kill to `"2"`, then re-send `"join"` without `laps`/`kills` -> assert `laps == 1` and `kills == 1` are preserved.
   - Set `_channel_id = -1`, send `"join"` -> assert `_roster` unchanged.
2. **Tier 2 — Concurrent Hitstop & `Lobby.leave()` Lifecycle Tests (`verify_combat.gd`, `verify_match_rules.gd`):**
   - Trigger `ArenaNet._do_hitstop()` (`t = 0`), then `CombatController._die()` (`t = 20 ms`), wait `120 ms` -> assert `is_equal_approx(Engine.time_scale, 1.0)`.
   - Trigger `CombatController._die()`, free `CombatController` at `t = 10 ms` -> assert `Engine.time_scale == 1.0`.
   - Enter Death Race lobby (`damage = 50`), call `Lobby.leave()`, immediately assert `Match.lobby.is_empty()` and `Match.game_mode() == "battle_royale"` and `Match.damage() == 30.0`.
3. **Tier 1 — AOE Invisible Proxy & `RaceTracker` Fail-Closed Tests (`verify_deathrace.gd`):**
   - Set `dummy_proxy.visible = false`, detonate Rocket + Meteor at its position -> assert `0` new `Label3D` nodes spawned.
   - Stub `issue_shot` / `register_lap` returning `{}` -> assert `completed_laps` does NOT increment.
4. **Tier 0 — Isolated Mushroom Cloud & Reduced-Motion VFX + Live Reverse Physics (`verify_vfx.gd`, `verify_controls.gd`):**
   - Spawn `mushroom_cloud_explosion` on an **empty** `holder` under `reduced_motion = true`, wait `0.5 s` -> assert `0` `GPUParticles3D` and `0` animated `_ring_quad` `MeshInstance3D`s.
   - Drive `KiepieBike` with `Input.action_press("move_back")` from rest for 60 physics frames -> assert reverse displacement `z < -4.0 m` (proving `reverse_force = 265.0` moves the bike cleanly).

---

## 4. Surgical Refactoring Blueprints (Zero-Mutation Drafts)

### Refactor [R1]: Allowlist `"join"` Roster Sanitization & Channel-Active Guard

- **Target Scope:** `godot/src/net/TaloBackend.gd:L822-L824, L869-L888`
- **Engineering ROI:** Closes a trivial P0 instant-win exploit (`laps: 99, kills: 99`), prevents mid-match reconnect stat wipes, and blocks late post-leave socket frames from mutating `_roster`.

**Current Pattern (Audited Code):**

```gdscript
	var ch = data.get("channel", null)
	if ch is Dictionary and _channel_id > 0 and int((ch as Dictionary).get("id", _channel_id)) != _channel_id:
		return
...
				if kind == "join":
					if _roster.size() >= 8 and not _roster.has(uid):
						return  # full lobby; no unbounded growth
					var row := p.duplicate(true)
					row["user_id"] = uid
					row["display_name"] = str(row.get("display_name", "RIDER")).substr(0, 32)
					...
					if _roster.has(uid) and _roster[uid] is Dictionary:
						var prev := _roster[uid] as Dictionary
						row["score"] = int(prev.get("score", 0))
						row["is_ready"] = bool(prev.get("is_ready", false))
						row["respawn_at"] = str(prev.get("respawn_at", ""))
					else:
						row["score"] = 0
						row["is_ready"] = false
						row["respawn_at"] = ""
					_roster[uid] = row
```

**Target Pattern (Surgical Blueprint):**

```gdscript
	if _channel_id <= 0:
		return
	var ch = data.get("channel", null)
	if ch is Dictionary and int((ch as Dictionary).get("id", _channel_id)) != _channel_id:
		return
...
				if kind == "join":
					if _roster.size() >= 8 and not _roster.has(uid):
						return
					var col := str(p.get("color", "#40c8ff"))
					if not _is_hex_color(col):
						col = "#40c8ff"
					var prev: Dictionary = (_roster[uid] as Dictionary) if (_roster.has(uid) and _roster[uid] is Dictionary) else {}
					_roster[uid] = {
						"user_id": uid,
						"display_name": str(p.get("display_name", "RIDER")).substr(0, 32),
						"color": col,
						"score": int(prev.get("score", 0)),
						"kills": int(prev.get("kills", 0)),
						"laps": int(prev.get("laps", 0)),
						"is_ready": bool(prev.get("is_ready", false)),
						"respawn_at": str(prev.get("respawn_at", "")),
					}
```

### Refactor [R2]: Refcounted `Engine.time_scale` Hitstop Coordinator

- **Target Scope:** `godot/src/core/KiepieTime.gd`, `godot/src/game/CombatController.gd:L146-L151, L204-L212`, `godot/src/game/ArenaNet.gd:L73-L77, L193-L203`
- **Engineering ROI:** Eliminates the P0 permanent slow-motion lock across overlapping kill/death hitstops and scene transitions with 20 lines of pure state logic.

**Current Pattern (Audited Code):**

```gdscript
# CombatController.gd:207-212
var prev_scale := Engine.time_scale
Engine.time_scale = 0.25
var tree := get_tree()
if tree != null:
	tree.create_timer(0.055, true, false, true).timeout.connect(func() -> void:
		Engine.time_scale = prev_scale)
```

**Target Pattern (Surgical Blueprint):**

```gdscript
# In KiepieTime.gd (shared static refcounted hitstop):
static var _hitstop_active := 0
static var _hitstop_gen := 0

static func trigger_hitstop(tree: SceneTree, scale: float, duration_s: float) -> void:
	if tree == null or Settings.reduced_motion():
		return
	_hitstop_active += 1
	var gen := _hitstop_gen
	Engine.time_scale = minf(Engine.time_scale, clampf(scale, 0.1, 1.0))
	tree.create_timer(duration_s, true, false, true).timeout.connect(func() -> void:
		if gen != _hitstop_gen:
			return
		_hitstop_active = maxi(0, _hitstop_active - 1)
		if _hitstop_active == 0:
			Engine.time_scale = 1.0)

static func reset_hitstop() -> void:
	_hitstop_gen += 1
	_hitstop_active = 0
	Engine.time_scale = 1.0
```

### Refactor [R3]: Synchronous Local Reset on `Lobby.leave()` + `Match.clear_lobby()`

- **Target Scope:** `godot/src/net/MatchState.gd`, `godot/src/net/LobbyService.gd:L65-L79`, `godot/src/ui/LobbyMenu.gd:L390-L395`, `godot/src/ui/MatchHud.gd:L718-L721`
- **Engineering ROI:** Prevents stale-lobby traps on rapid Leave -> Rejoin and stops Death Race settings leaking into TestRide via `_settings_cache`.

**Current Pattern (Audited Code):**

```gdscript
# LobbyService.gd:65-79
func leave() -> void:
	if current_lobby_id == "":
		return
	_session_gen += 1
	var gen := _session_gen
	await Supabase.call_rpc("leave_lobby", {})
	if gen != _session_gen:
		return
	Supabase.leave_lobby_channel()
	current_lobby_id = ""
	Match.lobby = {}
	Match.players.clear()
	left.emit()
```

**Target Pattern (Surgical Blueprint):**

```gdscript
# MatchState.gd:
func clear_lobby() -> void:
	lobby = {}
	players.clear()
	_time_up_called = false
	_refresh_settings_cache()
	lobby_changed.emit()
	roster_changed.emit()

# LobbyService.gd:
func leave() -> void:
	if current_lobby_id == "":
		return
	_session_gen += 1
	var gen := _session_gen
	current_lobby_id = ""
	Match.clear_lobby()
	await Supabase.call_rpc("leave_lobby", {})
	if gen != _session_gen:
		return
	Supabase.leave_lobby_channel()
	left.emit()
```

---

## 5. Phased Execution Roadmap & Scoped Agent Prompts

1. **Phase 1 — Containment & Safety Lock (`P0` Fixes + MVTH Baseline Tests):**
   - Fix `P0-1` (`TaloBackend.gd` `"join"` allowlist + `_channel_id <= 0` guard) and `P0-2` (`KiepieTime.trigger_hitstop` / `reset_hitstop` in `CombatController.gd` + `ArenaNet.gd`).
   - Add failing-first regression assertions to `verify_talo_backend.gd` and `verify_combat.gd`.
2. **Phase 2 — Concurrency, Gameplay Integrity & Production Bundle Sync (`P1` Fixes):**
   - Fix `P1-2` (`Match.clear_lobby()` + awaited/synchronous `Lobby.leave()`), `P1-3` (reconnect state resync), `P1-4` (`RaceTracker` fail-closed), `P1-5` (AOE visible/respawning check), `P1-6` (`VfxFactory` tree order, reduced-motion Wilson ring, `damage_number` cap + outline fade), `P1-7` (`NetworkedBike` initial `collision_layer = 0`), and `P1-8` (`MatchState` direct `_settings_cache` reads + `time_up` lobby-id guard).
   - Execute `bash godot/tools/deploy_web.sh --apply` to resolve `P1-1` (stale `index.pck`) and add `.vercelignore` (`P2-2`).
3. **Phase 3 — Structural De-Vibing & Modular Extraction (`P2/P3` Refactors):**
   - Unify `VehicleRegistry` <-> `SideCannons` stats (`P2-1`), split `VfxFactory.gd`, fix desktop touch clearance + `MobileTextInput` `blur()` + Web `prefers-reduced-motion` (`P2-4`), eliminate `MatchHud._name_for` sort & `SettingsMenu` debounce overwrite (`P2-5`), pin CI action/SHA-256 (`P3-1`), and clean dead fields/clamps (`P3-2`..`P3-4`).

### Copy-Paste Surgical Prompts for Coding Agents

> **Prompt [P0-1] (`godot/src/net/TaloBackend.gd`):**
> "Strictly scope edits to `godot/src/net/TaloBackend.gd` (lines 820–895) and `godot/tools/verify_talo_backend.gd` / `godot/tools/verify_audit_regressions.gd`. Do not modify any other files. Replace `var row := p.duplicate(true)` in the `"join"` branch with an explicit allowlist (`user_id`, `display_name`, `color`) preserving `score`, `kills`, `laps`, `is_ready`, and `respawn_at` from `prev` (or zero/empty defaults), and reject socket messages when `_channel_id <= 0` (updating test fixtures to stage `_channel_id = 1`). Add regression assertions proving forged `laps: 99, kills: 99` on `"join"` are stripped and existing `laps`/`kills` survive reconnect, then run `bash godot/tools/run_gates.sh` to confirm all 27 gates green."

> **Prompt [P0-2] (`godot/src/core/KiepieTime.gd`, `godot/src/game/CombatController.gd`, `godot/src/game/ArenaNet.gd`):**
> "Strictly scope edits to `godot/src/core/KiepieTime.gd`, `godot/src/game/CombatController.gd` (lines 146–152, 204–213), `godot/src/game/ArenaNet.gd` (lines 73–78, 193–204), and `godot/tools/verify_combat.gd`. Do not modify any other files. Replace independent `Engine.time_scale` save/restore logic with a refcounted `KiepieTime.trigger_hitstop()` + `reset_hitstop()` called in both `_exit_tree()` hooks so overlapping kill/death hitstops or mid-hitstop scene exits always restore `Engine.time_scale = 1.0`. Add a regression test triggering overlapping hitstops and freeing `CombatController` mid-hitstop, then run `bash godot/tools/run_gates.sh`."

> **Prompt [P1-1 + P2-2] (Web Deploy Sync & `.vercelignore`):**
> "Add a repo-root `.vercelignore` excluding everything except `index.*`, `favicon.ico`, and `web-assets/**` so internal audits, CAD `.blend`/`.stl` files, 40 MB of PNG renders, and source scripts are not exposed on Vercel. Then run `bash godot/tools/deploy_web.sh --apply` to refresh root `index.pck` / `index.html` / `index.service.worker.js` with `HEAD` (`298d9f4`) and verify `mushroom_cloud_explosion` and `MankiniPink` are present in the exported `index.pck`."

> **Prompt [P1-4 + P1-5 + P1-6 + P1-7] (Gameplay & VFX Hardening):**
> "Strictly scope edits to `godot/src/game/RaceTracker.gd` (lines 121–140), `godot/src/game/RocketProjectile.gd` (lines 184–190, 268–291), `godot/src/game/MeteorStrike.gd` (lines 191–198, 266–289), `godot/src/game/FuelDrum.gd` (lines 83–107), `godot/src/game/NetworkedBike.gd` (lines 30–42, 134–146), `godot/src/game/VfxFactory.gd` (lines 931–936, 1062, 1148–1149, 1316–1341), and their paired gates (`verify_deathrace.gd`, `verify_vfx.gd`, `verify_multiplayer.gd`). Make `RaceTracker` fail closed on empty token / non-ok `register_lap`, skip invisible/respawning bikes in all three AOE loops, initialize `NetworkedBike.collision_layer = 0` until a live non-dead state arrives, set `wreck.global_transform` only after `parent.add_child(wreck)`, guard the Wilson ring with `if not reduced:`, cap `damage_number` (`vfx_dmg_num <= 18`), and fade `outline_modulate:a`. Add regression assertions for each and confirm `bash godot/tools/run_gates.sh` passes 27/27."
