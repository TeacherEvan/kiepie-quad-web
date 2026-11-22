# Surgical Audit Report: Kiepie Quad (`TeacherEvan/kiepie-quad-web`)

| Audit Metadata | Specification |
| :--- | :--- |
| **Audit Date** | 2026-11-22 (Rev 2 — includes Live Pass 2.5 Chrome WebGL2/Viewport Probe & Pristine `git archive HEAD` 29-Gate Execution) |
| **Audited Scope** | `godot/src/`, `godot/tools/`, `godot/tests/`, `godot/addons/talo/settings.cfg`, `src/`, `index.html`, `index.service.worker.js`, `index.manifest.json`, `.github/workflows/gates.yml`, `vercel.json`, `.vercelignore`, `godot/export_presets.cfg`, `docs/` (`72` tracked first-party impl files, `29` test/gate files, `19,240` impl effective LOC / `23,480` total first-party tracked code effective LOC, `199` inline HTML lines = `19,439` scored effective LOC; vendored `godot/addons/*` source, Godot Emscripten `index.js`/`web/`, and untracked `docs/plans/Designs/` excluded from LOC/defect baseline) |
| **Tech Stack & Runtime** | Godot 4.3 (`gl_compatibility` / WebGL2 WASM), GDScript, Talo v0.20.0 WebSocket/HTTP backend, Blender 5.3 Python (`bpy`/`bmesh`), PWA Service Worker, Vercel static hosting |
| **Pre/Post Audit SHA-256** | `c39cfed0ca7295d2 / c39cfed0ca7295d2 (VERIFIED ZERO MUTATION — full: c39cfed0ca7295d2555e3cfe668900de0e020ecb28c155a69f80f040ce301e96, HEAD acef1aaf99d8eb243a077ac1f61e88b5bd6148db)` |
| **Deterministic Health Score** | **`60 / 100`** (`D_raw = 143`, `P_test = 7.75`, `M_kill = 48.3%` [`29/60`] over `19,439` effective LOC) |
| **Vibe-Debt Risk Level** | **`HIGH`** (`N_P0 = 1`; all 2026-11-20 P0s fixed, but live Pass 2.5 Web probe exposed a production cold-boot multiplayer brick) |

## 1. Executive Architecture & Vibe-Debt Triage

Kiepie Quad (`TeacherEvan/kiepie-quad-web`) remediated every P0 from the 2026-11-20 audit (`TaloBackend` `"join"` payload sanitization and reconnect stat preservation, `KiepieTime` refcounted hitstop removing permanent slow-mo locks, strict `.vercelignore` shipping 16 runtime files, fresh root `index.pck` Web export with embedded JWT, and projectile object pooling) while commit `c97a796` added the Aston Martin ("BIG-BEN") F1 vehicle, `VehicleHandling.gd`, and a rebuilt splash video. However, **live runtime verification against the exact shipped Web bundle (Pass 2.5 Chrome probe) and a pristine `git archive HEAD` 29-gate sandbox** uncovered a **critical `P0` production availability defect** and **ten `P1` defects**: on cold Web launch, `TaloBackend.start()` enforces a `2.5 s` WebSocket identification deadline while WebGL2 init and MP4 splash decoding run, then permanently abandons the connection without listening for late `"v1.players.identify.success"` frames and with zero retry trigger on `MainMenu` — live-reproduced in Chrome (`GET /v1/players/identify` 200 in `842 ms`, `POST /v1/socket-tickets` 200 in `900 ms`, yet permanently stuck on `Offline · Talo socket timed out`). Live pristine gate execution also exposed that checked-in `godot/addons/talo/settings.cfg` ships `auto_connect_socket=true`, causing 12+ offline `KIEPIE_MOCK_BACKEND=1` gates to fire real HTTPS calls to `api.trytalo.com` (`401` errors), while live desktop/mobile screenshots exposed `MainMenu` bottom clipping on both `375×667` and `667×375` viewports and a solid `StaticBody3D` cone impaling the center of `TestRide`'s `RampRight` (`0.00 m` overlap). Combined with six multiplayer/physics races (`TaloBackend` self-echo rollback, waiting-lobby host-loss soft-lock, `LobbyService` ghost-lobby leak, `ArenaNet` `5.0 m` high-speed shot drop, unfrozen dead bike free-fall, `RaceTracker`/`NetworkedBike` state ordering) and five hollow regression gate blocks, true mutation kill efficacy sits at `48.3%` (`29/60`).

| Severity Tier | Count | Deduction Weight | Primary Failure Domains |
| :--- | :--- | :--- | :--- |
| **P0 — Critical (Crash / Data Loss / Security / Leak)** | `1` | `-18 pts ea` | `TaloBackend.gd` + `MainMenu.gd` + `talo_socket.gd` (**LIVE-REPRODUCED:** `2.5 s` cold-boot WebSocket timeout permanently bricks online multiplayer with zero late-identify handler and zero retry UI) |
| **P1 — High (Frame-Budget / Race / Logic Bug)** | `10` | `-8 pts ea` | `TaloBackend.gd` (host self-echo rollback + waiting-lobby host-disconnect soft-lock); `addons/talo/settings.cfg` (**LIVE:** offline gates fire `401` HTTPS calls to `api.trytalo.com`); `LobbyService.gd` (in-flight join/create ghost-lobby leak); `ArenaNet.gd` (`5.0 m` lag drop at `28–36 m/s`); `CombatController.gd` (unfrozen dead bike free-fall); `RaceTracker.gd` (stale `current_lap` rollback & dropped final-lap lock); `NetworkedBike.gd` (pre-`_kill_lock_until` mutation); `MainMenu.tscn`/`build_menus.gd` (**LIVE:** mobile `375×667` & `667×375` bottom clipping); 5 hollow/unexecuted gate checks |
| **P2 — Medium (God File / Split-Brain State / Debt)** | `13` | `-3 pts ea` | `TaloBackend.gd` (`join_lobby_channel` missing `"vehicle"`, unbounded guest `_used_tokens`, unguarded await loops); `MatchHud.gd` (solo Death Race banner + `PlayAgainBtn` web splash DOM leak + inverted unrotated radar); `SettingsMenu.gd` (preset wiping unrelated pending writes); `LoopZone.gd` (stall trap, stale center vectors, freed-ID leak); `KiepieBike.gd`/`VehicleHandling.gd`/`KiepieTime.gd` (unclamped Euler aero drag + `NaN` hitstop scale); `PogoVisual.gd` (Euler remote yaw gimbal-lock); 15 God files + unguarded `VfxFactory._plane_basis(ZERO)`; `SideCannons.gd`/`Projectile.gd` (2nd fallback muzzle leak + inert pool divergence); `build_intro_splash.py` (non-atomic FFmpeg write + stale `matrix_world`); `build_testride.gd` (**LIVE:** solid cone impaling `RampRight` at `0.00 m`, unreadable `WeaponLabel`, stale `Help`, `0 px` button gap); `FollowCam.gd`/`KiepieBike.gd`/`qb_core.py` (180° reverse-slide snap, rolling dodge dust, broken `used_edges`); cross-doc drift & blocked CI |
| **P3 — Low (Magic Constants / DX / Portability)** | `6` | `-1 pt ea` | Unwired settings & dead fields/SW branch; per-instance `FuelDrum`/`Pickup` allocations, `TouchControls`/`MainMenu` StyleBox churn & duplicate drum timers; hardcoded `scorch` `y = 0.024` & tracked regenerable media; `38 px` compact buttons, non-reactive `touch_force`, missing `Hud.gd` click SFX, unsynced `LobbyMenu._ready_state`; `build_aston_martin.py` silent catch, `check_scene_sync.py` unclosed handle & sparse haptics; live sandbox tooling/runtime warnings (`check_web_hygiene.py` outside `.git`, `build_menus._verify`, GLB LOD non-finite normal, `ReadPixels` GPU stalls) |

### High-Risk File Telemetry Hotspots

| File Path | Effective LOC | Est. Cyclomatic Complexity / Branch Density | Silent Catches | Primary Vibe-Debt Signature |
| :--- | :--- | :--- | :--- | :--- |
| `godot/src/game/VfxFactory.gd` | `1191` | `CC 13 / 0.0101` | `0` | God VFX catalog (`1,432` raw LOC, `max_fn = 120`); unguarded `_plane_basis(ZERO)`; hardcoded `scorch` `y = 0.024` |
| `godot/src/net/TaloBackend.gd` | `918` | `CC 46 / 0.0490` | `0` | God netcode adapter (`1,104` raw LOC); **P0 `2.5 s` cold-boot brick**; host self-echo rollback; waiting-lobby soft-lock; `join_lobby_channel` missing `"vehicle"` |
| `godot/tools/build_deathrace.gd` | `949` | `CC 8 / 0.0074` | `0` | Monolithic procedural track builder (`1,069` raw LOC); duplicated ramp/building helpers across builders |
| `godot/src/ui/MatchHud.gd` | `736` | `CC 37 / 0.0489` | `0` | God HUD (`874` raw LOC); solo victory banner mismatch; `PlayAgainBtn` DOM leak; inverted unrotated radar |
| `src/build_pogo_nardus.py` | `702` | `CC 50 / 0.0698` | `0` | Monolithic Blender sculpt (`max_fn = 843` top-level procedural flow); `NardusDecal` skipped from manifold gate |
| `godot/tools/build_arena.gd` | `700` | `CC 5 / 0.0057` | `0` | Monolithic Arena builder; duplicated geometry builders with `build_testride.gd` / `build_deathrace.gd` |
| `src/build_aston_martin.py` | `584` | `CC 31 / 0.0514` | `1` | Monolithic F1 sculpt (`max_fn = 345`, `nest = 4`); silent `except Exception: pass` (`L675`) |
| `godot/src/game/SideCannons.gd` | `578` | `CC 46 / 0.0779` | `0` | Multi-weapon God controller (`MG`, `Banana`, `Rocket`, `Meteor` + pooling); 2nd `MuzzleFallback` child leak |
| `godot/src/KiepieBike.gd` | `562` | `CC 53 / 0.0925` | `0` | High branch-density physics loop; unclamped explicit-Euler aero drag; dodge dust parented to rolling bike |
| `godot/src/ui/MobileTextInput.gd` | `385` | `CC 14 / 0.0338` | `4` | Web DOM overlay bridge; 4 inline JS `catch(e) {}` blocks (`L305,L315,L316,L421`) inside `JavaScriptBridge.eval` |
| `godot/src/TouchControls.gd` | `491` | `CC 30 / 0.0591` | `0` | God input layer; per-relayout StyleBox duplication; ignores runtime `controls/touch_force` changes |
| `src/qb_body.py` / `src/qb_core.py` | `497 / 492` | `CC 15–18 / 0.028–0.035` | `0 / 0` | Blender chassis/core God modules (`qb_core.py` `nest = 5`; `_cap_holes()` never populates `used_edges`) |
| `godot/tools/build_menus.gd` | `441` | `CC 9 / 0.0181` | `0` | `MainMenu` lacks `ScrollContainer` (clips on mobile); `_verify()` skips `VehicleSelect` & checks flat leaf names |
| `godot/tools/build_testride.gd` | `443` | `CC 2 / 0.0023` | `0` | `Cone#24` at `(8, 0.35, 14)` collides with `RampRight` at `(8, 0, 14)` (`dist = 0.00 m`); HUD overlap/contrast flaws |
| `src/build_intro_splash.py` | `432` | `CC 19 / 0.0417` | `0` | Monolithic splash renderer (`max_fn = 334`); non-atomic FFmpeg write without timeout; stale `matrix_world` |
| `godot/src/game/ArenaNet.gd` | `342` | `CC 42 / 0.1199` | `0` | Highest branch density in repo (`0.1199`); hardcoded `5.0 m` muzzle check dropping fast remote shots |

### Pass 2.5 Live Runtime, Browser & Pristine Sandbox Evidence

- **Pristine Sandbox (`git archive HEAD` -> `/tmp/kiepie-audit-pristine`) Served With Exact `vercel.json` Headers (`http://127.0.0.1:18765/`) & Probed in Headless Chrome (`chrome-devtools` MCP):**
  - **Isolation & Assets:** `crossOriginIsolated = true`, `SharedArrayBuffer = true`, `swController = true`; all `13` network requests (`index.html`, `index.js`, `index.wasm` [35.38 MB], `index.pck` [3.70 MB, embedded 135-char `eyJhbGci...` JWT], `web-assets/dashboard_bg.jpg`, `kiepie-quad-splash.mp4?v=2`, `kiepie-victory-splash.mp4`, `index.png`) returned `200 OK`; `index.manifest.json` icons (`144/180/512`) exist; `export_presets.cfg` `html/head_include` matches `index.html` byte-for-byte in UTF-8; `CACHE_VERSION` (`e42148c2ea92`) and `ENGINE_CACHE` (`fe5cebc59075`) match live SHA-256 prefixes.
  - **Live Boot Failure Caught (`P0-1`):** `GET /v1/players/identify` (`200 OK`, `842 ms`) and `POST /v1/socket-tickets` (`200 OK`, `900 ms`) both succeeded, yet `MainMenu` permanently displayed **`Offline · Talo socket timed out — check your connection`** across all 3 viewports (`1280×720`, `667×375`, `375×667`).
  - **Live Viewport & 3D Screenshots Caught (`P1-10`, `P2-12`):** `MainMenu` bottom card border + `Footer` clipped off-screen at `375×667` portrait and bottom border clipped with `SETTINGS` flush against viewport edge at `667×375` landscape; live 3D `TestRide` WebGL2 screenshot (`1280×720`) showed `Cone#24` impaling `RampRight`, un-outlined `F1 AUTOCANNON · READY` over bright 3D geometry, stale `Help` copy, and `0 px` button gaps.
  - **WCAG 2.1 / 2.2 Verification:** Single viewport meta (no `user-scalable=no`), `#victory-skip` measured `124.7 × 44 px` (`>= 24 px` WCAG 2.5.8 & `44 px` HIG), all static contrast pairs pass AAA (`#e0e0e0` on `#5b3943` = `7.54:1`; `#f2ede6` on `#0b0d12` = `16.69:1`; `#f5f2eb` on `#141821` = `15.89:1`; `#a6b0c3` on `#141821` = `8.14:1`; `#f58a1f` on `#141821` = `7.22:1`).
  - **Console Telemetry:** `0` uncaught JS exceptions; `GL Driver Message: GPU stall due to ReadPixels` fired 4 times during boot (`P3-6`).
- **Pristine 29-Gate Live Run (`bash godot/tools/run_gates.sh --no-build` in `/tmp/kiepie-audit-pristine`):**
  - All `27` Godot gates (`truth`..`check_scripts` + `touch_multitouch` under `xvfb` + `gdunit` `6/6`) reported exit `0`, **while exposing `401: Bad Authorization header format` / `Failed to get socket ticket` live network calls to `api.trytalo.com` in 12+ offline gate logs (`P1-8`)**, confirming `PASS KiepieBike engine RPM pitch check skipped` in `controls.log:L18` (`P1-7`), and exposing `import.log:L4` non-finite LOD normal and `check_web_hygiene.py` crash outside `.git` (`P3-6`).

---

## 2. The 10-Principal-Engineer Deep Audit

### Lens 1: Systems Architect

- **[P1-5] `RaceTracker._on_roster_changed()` Rolls Back `completed_laps` Without Updating `current_lap`, Plus Unrecoverable Final-Lap `lap_pending` Lock** — `godot/src/game/RaceTracker.gd:L47-L60`, `godot/src/game/RaceTracker.gd:L165-L218`
  - **Root Cause Mechanism:** On a Death Race guest, `_on_finish_line_entered()` optimistically increments `completed_laps` (`L166`) and sets `current_lap` (`L180`/`L191`) while `lap_pending = true` (`L163`). When any intermediate host roster broadcast arrives before the host processes `lap_request` (or if the host rejects the lap), `_on_roster_changed()` overwrites `completed_laps = auth_laps` (`L56`) and resets `race_finished = false` (`L59`), but **never recomputes `current_lap`**. Because `_sync_hud()` displays `mini(current_lap, lap_target())`, `current_lap` and `completed_laps` split-brain permanently. Additionally, on the final lap (`L178-L186`), a guest sets `race_finished = true` while `lap_pending = true` with no retry or timeout recovery if the `lap_request` socket frame is lost.
  - **Deterministic Trigger & Failure Mode:** Guest crosses finish line on Lap 1 while a simultaneous kill/join roster frame is in flight (`auth_laps == 0`) -> `_on_roster_changed()` rolls `completed_laps` back to `0` while `current_lap` remains `2` -> HUD displays `LAP 2/3` when the player actually has `0` laps. On final lap, a dropped `lap_request` leaves `race_finished = true` forever so the guest can never finish the race.
  - **Surgical Fix Specification:** Inside `_on_roster_changed()` (`L56-L60`), recompute `current_lap = mini(completed_laps + 1, target)` and clear `lap_pending = false` when `auth_laps >= completed_laps`; on final lap when `lap_pending == true`, hold `race_finished = false` until host confirmation (or add a 3 s retry timer).

- **[P2-2] `MatchHud` Solo Death Race Victory Banner Displays `"BATTLE ROYALE CHAMPION"` & `PlayAgainBtn` Leaks Web Victory Splash DOM** — `godot/src/ui/MatchHud.gd:L618-L627`, `godot/src/ui/MatchHud.gd:L761-L774`
  - **Root Cause Mechanism:** `_play_victory_splash()` derives `mode_str` solely from `Match.game_mode()` (`L621`), which defaults to `"battle_royale"` whenever `Match.lobby` is empty (solo/practice `DeathRace.tscn` runs). Separately, `_on_play_again()` (`L761-L764`) reloads the scene directly (`get_tree().reload_current_scene()`) when `Match.lobby.is_empty()` **without** invoking `window.__kiepieDropVictory()`, unlike `_on_leave_match()` (`L769-L770`), and `MatchHud` has no `_exit_tree()` DOM cleanup.
  - **Deterministic Trigger & Failure Mode:** Completing 3 laps in solo Death Race shows `"BATTLE ROYALE CHAMPION"` instead of `"DEATH RACE CHAMPION"`; clicking `PlayAgainBtn` on Web while the victory splash video overlay is still fading leaves `#victory-splash` stuck over the reloaded track.
  - **Surgical Fix Specification:** Check whether a `RaceTracker` node exists in the scene tree (or `_race_banner_override != ""`) as fallback for `"DEATH RACE"` in `_play_victory_splash()`, and invoke `window.__kiepieDropVictory && window.__kiepieDropVictory();` inside both `_on_play_again()` and `_exit_tree()`.

- **[P2-8] 15 Tracked First-Party God Files (`>400` Effective LOC) & Unguarded `VfxFactory._plane_basis(Vector3.ZERO)`** — `godot/src/game/VfxFactory.gd:L530-L537`, `godot/src/net/TaloBackend.gd:L1-L1104`, `godot/tools/build_deathrace.gd:L1-L1069`, `godot/src/ui/MatchHud.gd:L1-L874`, `godot/src/game/SideCannons.gd:L1-L672`, `godot/src/KiepieBike.gd:L1-L691`, `godot/src/TouchControls.gd:L1-L645`
  - **Root Cause Mechanism:** Fifteen tracked first-party files exceed the `400` effective LOC threshold, topped by `VfxFactory.gd` (`1,191` LOC), `build_deathrace.gd` (`949` LOC, duplicating ramp/building/lighting helpers from `build_arena.gd` and `build_testride.gd`), `TaloBackend.gd` (`918` LOC), and `MatchHud.gd` (`736` LOC). Inside `VfxFactory._plane_basis()` (`L530-L537`), `normal.normalized()` returns `Vector3.ZERO` for a zero vector, causing `Basis.looking_at(Vector3.ZERO, up)` to error. Additionally, `KiepieBike.refresh_vehicle_assignment()` (`KiepieBike.gd:L301-L324`) can swap an active player's vehicle and wipe `_proj_pool` mid-firefight whenever `Match.roster_changed` alters the `for_player_in_roster()` Nardus promotion winner.
  - **Deterministic Trigger & Failure Mode:** Any degenerate zero contact normal triggers a Godot `looking_at` error; mid-match peer joins/leaves can abruptly transform an auto-dealt player's vehicle mid-combat; oversized God files inflate regression surface and AI context consumption.
  - **Surgical Fix Specification:** Guard `if normal.length_squared() < 1e-8: normal = Vector3.UP` at `VfxFactory.gd:L533`; freeze vehicle assignment once `Match.is_playing()` starts; progressively extract `VfxTextures.gd`, `SceneBuilderCommon.gd`, and `TaloScoringRules.gd`.

---

### Lens 2: Frame-Budget & Performance

> *Verified Strengths:* Hot-loop WebGL2 safeguards are solid — runtime-generated particle sprites (`prewarm()`), bounded pools (`_proj_pool <= 24`, `_remote_proj_pool <= 32`), strict decal/light caps (`MAX_SCORCH = 12`, `MAX_SCAR = 24`, `MAX_EXPLOSION_SHARDS = 36`, `MAX_IMPACT_LIGHTS = 8`), 1-draw-call striped kerb walls, and swept-ray projectiles keep steady-state frame times within the `16.67 ms` WebGL2 budget.

- **[P3-2] Per-Instance `FuelDrum`/`Pickup` Mesh & Material Allocations, `TouchControls`/`MainMenu` Resize StyleBox Churn & Duplicate Neighbor Timers** — `godot/src/game/FuelDrum.gd:L22-L67,L117-L132`, `godot/src/game/Pickup.gd:L51-L62`, `godot/src/TouchControls.gd:L578-L589,L630-L633`, `godot/src/ui/MainMenu.gd:L150-L156,L187-L204`
  - **Root Cause Mechanism:** Each `FuelDrum` (10 per Arena) and `Pickup` (8 per Arena) allocates fresh meshes/materials in `_ready()` instead of sharing `static var` resources. `FuelDrum.ignite()` (`L117-L132`) schedules `create_timer(0.18)` for every nearby drum without skipping `bool(d.get("_ignited"))`. `TouchControls._relayout()` (`L578-L589,L630`) duplicates four `StyleBoxFlat` instances on every viewport resize (and `_style_toggle()` only styles `"normal"`), while `MainMenu._apply_responsive_layout()` -> `_sync_mode_ui()` -> `_apply_mode_pill_style()` (`L187-L204`) rebuilds and duplicates 16+ `StyleBoxFlat`s on every un-debounced resize tick and mutates the Card panel StyleBox in place.
  - **Deterministic Trigger & Failure Mode:** Window resize drags or orientation changes churn dozens of StyleBox allocations per frame; drum chains queue redundant timers on already-ignited drums.
  - **Surgical Fix Specification:** Cache shared meshes/materials in `static var` maps on `FuelDrum`/`Pickup`; skip `_ignited` drums in `FuelDrum.gd:L122`; allocate `TouchControls` and `MainMenu` pill StyleBoxes once and debounce `MainMenu` resize callbacks.

- **[P3-3] Hardcoded `y = 0.024` in `VfxFactory.scorch()` & Tracked Regenerable Media Bloat in Git** — `godot/src/game/VfxFactory.gd:L1269`, `renders/` (`40` PNGs), `QA_debrief*` (`10` files), `Kiepie_Bike.stl` (`2.2 MB`)
  - **Root Cause Mechanism:** `VfxFactory.scorch()` pins decals to `Vector3(pos.x, 0.024, pos.z)` (`L1269`), ignoring elevated `pos.y` on Death Race ramps/loops (whereas `dust_ring()` respects `pos.y`). Although `.vercelignore` excludes all non-runtime assets from Vercel (`16` runtime files shipped, `index.pck = 3.70 MB`), git still tracks `40` regenerable `renders/*.png`, `10` `QA_debrief*` files, and `2.2 MB` `Kiepie_Bike.stl`.
  - **Deterministic Trigger & Failure Mode:** Explosions on elevated Death Race track sections paint scorch decals `3-15 m` below on `y = 0`; git clones pull unnecessary regenerable binaries.
  - **Surgical Fix Specification:** Place scorch decals at `Vector3(pos.x, maxf(0.024, pos.y + 0.024), pos.z)` aligned to the hit surface normal; untrack regenerable `renders/` and `QA_debrief*` on the next repo hygiene pass.

---

### Lens 3: Mathematical, Physics & Algorithmic

- **[P1-3] Hardcoded `5.0 m` Muzzle Proximity Check Silently Drops Remote Shots, Rockets & Meteors at Racing Speeds** — `godot/src/game/ArenaNet.gd:L278-L284`
  - **Root Cause Mechanism:** `_spawn_remote_shot()` rejects any remote shot whose origin `o` exceeds `5.0 m` from the receiver's interpolated `sender.global_position` (`L283`). At `28-36 m/s` (Turbo/Overdrive after `c97a796`), `SEND_HZ = 15 Hz` jitter (`~33 ms`) + `NetworkedBike` `exp(-14 * dt)` smoothing lag (`~71 ms`) + WebSocket one-way latency (`80-150 ms`) equals `~185-255 ms` of visual lag = **`6.0-8.2 m` displacement** + `~1.0 m` muzzle offset (`7.0-9.2 m > 5.0 m`).
  - **Deterministic Trigger & Failure Mode:** Any multiplayer firefight above `~22 m/s` (standard in Death Race straights and Arena chases) silently drops remote bullets, bananas, rockets, and meteors on receiving clients with zero warning.
  - **Surgical Fix Specification:** Replace hardcoded `5.0` with a `16.0 m` (or speed-scaled `clampf(6.5 + est_speed * 0.35, 6.5, 18.0)`) lag window while keeping finite-coord, `is_respawning`, and `24/s` rate limits intact.

- **[P1-4] Dead Local Bike Unfrozen With `collision_mask = 0` Free-Falls Through the Floor Into the Void, Plunging `FollowCam` Under the Map** — `godot/src/game/CombatController.gd:L211-L216,L253-L257,L307-L318`
  - **Root Cause Mechanism:** `_die()` hides the bike, calls `set_physics_process(false)`, and zeroes `collision_layer = 0` / `collision_mask = 0` (`L211-L216`), **but leaves `VehicleBody3D.freeze = false`**. `PhysicsServer3D` keeps integrating gravity (`-9.81 m/s^2`) with zero floor collision (`y = -30 m` in `2.5 s`, `-122 m` in `5 s`), while `ArenaNet._send_state()` broadcasts falling coordinates and `FollowCam` plunges under the map whenever no remote killer exists. (Additionally, `_engine_player` continues revving audibly while dead.)
  - **Deterministic Trigger & Failure Mode:** Dying in Practice mode, a Death Race `HazardPit`, or a `FuelDrum`/self-explosion drops `FollowCam` into the black void beneath the floor during respawn.
  - **Surgical Fix Specification:** Set `bike.freeze = true`, `bike.linear_velocity = Vector3.ZERO`, and `bike.angular_velocity = Vector3.ZERO` in `_die()`; set `bike.freeze = false` immediately before `bike.reset_bike()` in `_respawn()` (`L253`) and `reset_state()` (`L307`).

- **[P2-3] `MatchHud.RadarControl` Axes Inverted & Non-Heading-Aligned Relative to `+Z` Forward / `+X` Left Vehicle Convention** — `godot/src/ui/MatchHud.gd:L848-L874`
  - **Root Cause Mechanism:** Forward is local `+Z` and left is `+X`, while Godot 2D Control coordinates put `+X` screen-right and `+Y` screen-down. `RadarControl._draw()` plots world-space `Vector2(d.x, d.z) / WORLD_RANGE * r` (`L867`) without projecting into the bike's horizontal heading frame.
  - **Deterministic Trigger & Failure Mode:** Driving along `+Z`, enemies directly ahead render at the **bottom** of the radar and enemies to the left render on the **right**; turning the bike leaves blips fixed in inverted world space.
  - **Surgical Fix Specification:** Project `d` onto the bike's flattened heading basis (`fwd = Vector2(basis.z.x, basis.z.z).normalized()`, `right = Vector2(-fwd.y, fwd.x)`, `local_2d = Vector2(d.dot_right, -d.dot_fwd)`) so ahead is always up (`-Y`) and right is always right (`+X`).

- **[P2-5] `LoopZone._climbed` Trap on Stall/Reverse, Stale `loop_tangent`/`loop_center_pull` at Loop Center & Freed-Bike Dictionary Leak** — `godot/src/game/LoopZone.gd:L63-L97`
  - **Root Cause Mechanism:** `_climbed[bid] = true` (`L69`) never clears if a stalled bike falls back down to the entry floor (`lp.y < 1.8 and lp.z < -0.4`), preventing `L72` from clearing adhesion; the center fallback (`L96-L97`) resets `loop_up` but leaves `loop_tangent` and `loop_center_pull` stale; removing freed bikes (`L63-L64`) leaks instance IDs in `_climbed`.
  - **Deterministic Trigger & Failure Mode:** Stalling past `4 m` in a Death Race loop and sliding back to the entry ramp pins the bike with residual helical adhesion; freeing bikes inside loops leaks dictionary entries.
  - **Surgical Fix Specification:** Clear `_climbed.erase(bid)` when `lp.y < 1.0 and lp.z < -0.5` and prune dead IDs from `_climbed`; zero `loop_tangent` and `loop_center_pull` in the `L96-L97` `else` branch.

- **[P2-6] Unclamped Explicit-Euler Aero Drag Overshoot & `KiepieTime.trigger_hitstop()` Accepts `NaN` Scale** — `godot/src/KiepieBike.gd:L646`, `godot/src/game/VehicleHandling.gd:L38-L49`, `godot/src/core/KiepieTime.gd:L55`
  - **Root Cause Mechanism:** `KiepieBike._integrate_forces()` applies explicit Euler `state.linear_velocity += aero_drag_accel * state.step` (`L646`) without clamping `drag_k * spd * dt <= 1.0` (can invert velocity sign on extreme impulse spikes); `KiepieTime.trigger_hitstop()` (`L55`) checks `scale <= 0.0 or duration_s <= 0.0` without `is_finite()`, allowing `NAN` (`NAN <= 0.0` is `false`) to poison `Engine.time_scale`.
  - **Deterministic Trigger & Failure Mode:** A physics depenetration spike + frame hitch flips velocity sign; passing `NAN` to `KiepieTime.trigger_hitstop()` breaks `Engine.time_scale` until `reset()`.
  - **Surgical Fix Specification:** Use analytical decay `vel /= (1.0 + drag_k * spd * dt)` (or clamp decel delta `<= spd`) and add `not is_finite(scale) or not is_finite(duration_s)` guard at `KiepieTime.gd:L55`.

- **[P2-7] `PogoVisual` Remote Proxy Yaw Uses Euler `global_rotation.y` (Gimbal-Lock Snaps in Loops/Cartwheels)** — `godot/src/game/PogoVisual.gd:L191-L200`
  - **Root Cause Mechanism:** Remote Nardus proxies compute `dyaw` from Euler `global_rotation.y` (`L191`), which jumps by `+/-PI` when pitch crosses `+/-90°` during loops or Q/E cartwheels.
  - **Deterministic Trigger & Failure Mode:** Remote Nardus riders visibly snap their steering/torso sideways during loops and dodges.
  - **Surgical Fix Specification:** Compute `cur_yaw = atan2(fwd.x, fwd.z)` from `global_transform.basis.z` only when `Vector2(fwd.x, fwd.z).length_squared() > 0.04`.

- **[P2-13] `FollowCam` Reverse/180°-Slide Vector Collapse, Cartwheeling Dodge Dust Puff & Broken `qb_core._cap_holes` `used_edges`** — `godot/src/FollowCam.gd:L138-L139`, `godot/src/KiepieBike.gd:L615`, `src/qb_core.py:L432-L461`
  - **Root Cause Mechanism:** Three independent math/geometry defects:
    1. `FollowCam.gd:L138-L139` blends `fwd = fwd.lerp(horiz_v.normalized(), 0.45).normalized()` whenever `horiz_v.length() > 8.0` without checking `fwd.dot(horiz_v.normalized()) > 0.0` — reversing or sliding backwards at `>8 m/s` after a spinout/knockback makes `fwd` and `horiz_v` antiparallel (`dot ≈ -1`), collapsing the lerped vector toward zero and snapping the chase camera 180°.
    2. `KiepieBike.gd:L615` spawns dodge dust via `VfxFactory.dust_puff(self, Vector3.ZERO, 28)` instead of `_fx_parent()` at `global_position`, so the dust puff cartwheels through mid-air attached to the spinning bike (same defect class as prior `F-09`).
    3. `src/qb_core.py:L432-L461` initializes `used_edges = set()` (`L432`) and checks `if start in used_edges: continue` (`L434`), but records visited edges in a separate local `used = {start}` (`L440`) and never merges `used` into `used_edges`, redundantly walking every boundary loop `N` times and failing `bm.faces.new()` `N-1` times per hole.
  - **Deterministic Trigger & Failure Mode:** High-speed spinout/reverse violently whips the camera; Q/E dodge drags ground dust through the sky; Blender hole-capping wastes $O(N^2)$ walks and emits spurious duplicate-face warnings.
  - **Surgical Fix Specification:** Gate `FollowCam.gd:L138` on `fwd.dot(horiz_v.normalized()) > 0.25`; change `KiepieBike.gd:L615` to `VfxFactory.dust_puff(_fx_parent(), global_position, 28)`; add `used_edges.update(used)` after `L456` in `src/qb_core.py`.

---

### Lens 4: Concurrency, Async & Determinism

- **[P0-1] [LIVE-REPRODUCED] `TaloBackend.start()` Permanently Bricks Online Multiplayer After `2.5 s` Cold-Boot Socket Timeout With Zero Late-Identify Handling or Retry UI** — `godot/src/net/TaloBackend.gd:L80-L95,L165-L194`, `godot/src/ui/MainMenu.gd:L236,L252,L272,L292`, `godot/addons/talo/talo_socket.gd:L49-L57,L94`
  - **Root Cause Mechanism:** `TaloBackend.start()` awaits `Talo.players.identify()` and `Talo.socket.open_connection()`, then waits only **`2500 ms`** (`sock_deadline := Time.get_ticks_msec() + 2500`, `L81`) for `Talo.socket._identified` to flip `true`. On cold Web launch (simultaneous WebGL2 shader compilation, MP4 splash playback, and non-US/EU RTT where REST calls alone measured `842 ms` + `900 ms` in live Chrome), WebSocket TLS + `v1.connected` + `v1.players.identify` + `v1.players.identify.success` routinely exceeds `2.5 s`. When the deadline expires (`L84-L90`), `start()` sets `is_ready = false`, emits `auth_status(false, "Talo socket timed out — check your connection")`, and **permanently exits**. Even if `TaloSocket` receives `"v1.players.identify.success"` `100 ms` later (`talo_socket.gd:L55`), `TaloBackend._on_socket_message()` ignores `"v1.players.identify.success"`, leaving `is_ready = false` forever. Worse, `MainMenu.gd` exposes **no Retry/Reconnect button** (tapping `CREATE LOBBY`, `JOIN AUTO`, or `JOIN` only shows `"Still connecting to the backend…"` without re-invoking `Supabase.talo.start()`), and `_on_socket_closed` (`L166`) repeats the same `2500 ms` timeout while `TaloSocket._reset_socket()` (`talo_socket.gd:L94`) refuses to reset unauthenticated closed sockets.
  - **Deterministic Trigger & Failure Mode:** **Live-reproduced on the exact shipped Web bundle in Chrome (`http://127.0.0.1:18765/`):** `identify` (`200 OK`, `842 ms`) and `socket-tickets` (`200 OK`, `900 ms`) both succeeded, yet `MainMenu` permanently locked into `Offline · Talo socket timed out — check your connection`, disabling all multiplayer until manual browser refresh.
  - **Surgical Fix Specification:** (1) Increase `sock_deadline` in `TaloBackend.gd:L81,L166` to `10000 ms` (10 s) and trigger automatic bounded retry on cold-boot timeout; (2) handle `"v1.players.identify.success"` inside `TaloBackend._on_socket_message()` so a late-identifying socket immediately promotes `is_ready = true` and emits `auth_status(true, ...)`; (3) add a `RETRY CONNECTION` action (or auto-call `Supabase.reconnect()` on multiplayer button click when `not Supabase.is_ready`) in `MainMenu.gd`.

- **[P1-1] Host Applies Its Own Echoed `"state"` Socket Frame — Stale State Rollback Race** — `godot/src/net/TaloBackend.gd:L899-L913`
  - **Root Cause Mechanism:** After every authoritative mutation, the host sends `_send("state", {"lobby": _lobby, "roster": _roster})`, which Talo echoes back to the host. `_on_socket_message("state")` (`L903`) checks only `sender_id != host_id` — it **does not ignore the host's own echo** and carries no monotonic sequence number. Worse, if an older echo arrives while the host is paused inside `await _apply_props()` (`L774`/`L828`), the rolled-back `_lobby`/`_roster` is immediately re-broadcast to every peer upon resume.
  - **Deterministic Trigger & Failure Mode:** Two rapid kills/joins/readies on the host within one WebSocket RTT (`50-150 ms`) cause the first echo to overwrite `_lobby` and `_roster` back to the older score/state and persist the rollback on the next heartbeat.
  - **Surgical Fix Specification:** Guard `if _is_host() and sender_id == user_id: _host_ack = true; return` before applying `"state"`, AND stamp a monotonic `_state_seq` integer in `"state"` payloads so guests drop out-of-order frames. Update `verify_audit_regressions.gd:L109-L118` positive control to use a guest (`user_id = "2"`, `host_id = "1"`).

- **[P1-2] Ghost Lobby Leak When Leaving/Canceling `LobbyMenu` While Join/Create RPC Is In Flight** — `godot/src/net/LobbyService.gd:L37-L83`, `godot/src/ui/LobbyMenu.gd:L76-L86,L119-L149,L392-L399`
  - **Root Cause Mechanism:** `LobbyService.leave()` returns immediately at `L69-L70` (`if current_lobby_id == "": return`) **without incrementing `_session_gen`**, and `join_auto()`, `join_by_code()`, and `create_lobby()` (`L37-L65`) never capture or verify `_session_gen` across `await Supabase.call_rpc(...)`.
  - **Deterministic Trigger & Failure Mode:** Canceling Back/Leave/Esc during the `2-6 s` `join_auto`/create await leaves the RPC running; when it resolves, `_enter(res)` joins a ghost lobby and runs 20 s heartbeats from `MainMenu`, trapping the next `LobbyMenu` visit in the abandoned room.
  - **Surgical Fix Specification:** Always increment `_session_gen += 1` at the top of `LobbyService.leave()` even when `current_lobby_id == ""`; snapshot `gen` before `await` in `join_auto`/`join_by_code`/`create_lobby` and immediately leave the room if `gen != _session_gen` on resume.

- **[P1-6] `NetworkedBike.apply_state()` Mutates `turbo_active`, `_target_pos`, `_target_basis`, and `_last_tick` Before `_kill_lock_until` Check** — `godot/src/game/NetworkedBike.gd:L126-L158` (masked by `godot/tools/verify_multiplayer.gd:L339`)
  - **Root Cause Mechanism:** `apply_state()` updates `_last_tick` (`L130`), `_target_pos` (`L135`), `_target_basis` (`L140`), and `turbo_active` (`L142`) **before** the `_kill_lock_until` early return (`L151-L153`). `verify_multiplayer.gd:L339` masked this via a typo (`nb.set("_death_lock_until", 0.0)` instead of `_kill_lock_until`), leaving the lock active while passing *because* of the premature mutation.
  - **Deterministic Trigger & Failure Mode:** An in-flight pre-death `d=false, t=true` packet arriving within `0.55 s` of a kill activates turbo flame/wing-flap VFX and shifts target transforms on the dead proxy.
  - **Surgical Fix Specification:** Short-circuit `if _initialised and is_respawning and not dead_now and now < _kill_lock_until: return` before writing `_target_pos`, `_target_basis`, or `turbo_active`; fix `verify_multiplayer.gd:L339` to `_kill_lock_until` and assert `turbo_active` remains `false` while locked.

- **[P1-9] Waiting-Lobby Host Disconnect or Failed Handoff Soft-Locks All Remaining Guests Forever in `LobbyMenu.tscn`** — `godot/src/net/TaloBackend.gd:L118-L124,L552-L554,L950-L956`, `godot/src/net/MatchState.gd:L32-L41`
  - **Root Cause Mechanism:** `TaloBackend._process()` runs `_poll_host_alive()` **only** when `status == "playing"` (`L118-L124`, resetting `_host_poll_accum = 0.0` in `"waiting"`), `"leave"` emits `host_lost` **only** when `status == "playing"` (`L952-L956`), and `MatchState._on_host_lost()` early-returns unless `is_playing()` (`L35`). Meanwhile, if a host closes their browser tab or `_handoff_host_before_leave()` fails both HTTP PUT attempts (`L552-L554`), no guest is ever promoted or notified.
  - **Deterministic Trigger & Failure Mode:** Host disconnects or closes tab while guests are in `LobbyMenu.tscn` (`status == "waiting"`) -> guests remain permanently stuck on `"Waiting for host"` while `READY` clicks go unanswered forever.
  - **Surgical Fix Specification:** Run `_poll_host_alive()` during both `"waiting"` and `"playing"`; emit `host_lost` on host `"leave"` or stale heartbeat in `"waiting"` too, and handle `host_lost` in `LobbyMenu.gd` by showing `"Host disconnected — leaving lobby…"` and returning cleanly to `MainMenu` (or promoting when Talo channel ownership updates).

---

### Lens 5: Memory & Resource Lifecycle

> *Cross-references:* `P2-2` (`PlayAgainBtn` leaking `#victory-splash` DOM overlay on Web reload) and `P2-5` (`LoopZone._climbed` retaining freed bike instance IDs).

- **[P2-9] `SideCannons` Second Fallback Muzzle Leak + `Projectile.setup()` Inert/First-Call Pooling Divergence** — `godot/src/game/SideCannons.gd:L115-L135`, `godot/src/game/Projectile.gd:L124-L135`
  - **Root Cause Mechanism:** Adding two children named `"MuzzleFallback"` (`L131`) causes Godot to auto-rename the second child (`MuzzleFallback2`/`@Node3D@...`), so cleanup `m.name == "MuzzleFallback"` (`L116`) leaks every non-first fallback `Node3D` on re-setup. Unlike `BananaProjectile.setup()` (`L162-L165`), `Projectile.setup()` (`L124-L128`) only resets `_age = 0.0` in `_rearm_tracer()` and omits immediate `_recycle()` when `_inert && pooled` on first build.
  - **Deterministic Trigger & Failure Mode:** Repeated `SideCannons.setup()` on fixtures without authored muzzles leaks child nodes; pooled `Projectile` instances receiving invalid velocity on first spawn remain visible/active instead of recycling.
  - **Surgical Fix Specification:** Tag fallbacks with `anchor.set_meta("fallback_muzzle", true)` and free by metadata; align `Projectile.setup()` with `BananaProjectile.setup()` (`_age = 0.0` always; `_recycle()` when `_inert && pooled`).

---

### Lens 6: Security & Trust-Boundary (Matrix D — Supply-Chain & Governance)

> *Verified Posture:* Within Talo v1's client-host model, `TaloBackend` enforces sender-alias binding on `"state"`, `"join"`, `"leave"`, `"kill_request"`, `"lap_request"`, `"kill"`, `"hurt"`, `"bike_state"`, and `"shot"`, plus per-killer rate limits and `PROTOCOL_VERSION = 3` isolation. `TALO_API_GAME` is a public game JWT by design (`TALO_API_ADMIN` rejected), `.vercelignore` allowlists `16` runtime files (verified by `check_web_hygiene.py`), and `vercel.json` enforces `COOP`/`COEP`/`CORP` + security headers. Two governance/isolation defects remain:

- **[P1-8] [LIVE-REPRODUCED] Tracked `godot/addons/talo/settings.cfg` Ships `auto_connect_socket=true`, Making Offline `KIEPIE_MOCK_BACKEND=1` Gates Fire Live HTTPS Calls to `api.trytalo.com`** — `godot/addons/talo/settings.cfg:L1-L9`, `godot/addons/talo/talo_manager.gd:L55-L56`, `godot/tools/run_gates.sh`
  - **Root Cause Mechanism:** `project.godot` boots the `Talo` autoload **before** `Supabase` checks `KIEPIE_MOCK_BACKEND=1`. Because checked-in `godot/addons/talo/settings.cfg` has `auto_connect_socket=true` (only `inject_talo_key.py` flips it to `false` during export), `Talo._ready()` immediately calls `socket.open_connection()` -> `POST https://api.trytalo.com/v1/socket-tickets` with an empty `Authorization: Bearer ` header on every clean-checkout/CI gate process.
  - **Deterministic Trigger & Failure Mode:** **Live-reproduced in pristine `git archive HEAD` sandbox:** `ERROR: 401: Bad Authorization header format` and `ERROR: Failed to get socket ticket` fired across **12+ offline gate logs** (`appeal`, `combat`, `controls`, `deathrace`, `features`, `gdunit`, `rollover`, `smash_impact`, `stability`, `talo_backend`, `touch_multitouch`, `vfx`), violating offline test isolation and adding live network latency/flakiness to CI.
  - **Surgical Fix Specification:** Commit `auto_connect_socket=false`, `handle_tree_quit=false`, and `[continuity] enabled=false` directly in checked-in `godot/addons/talo/settings.cfg` (matching `inject_talo_key.py`), since `TaloBackend.start()` already opens the socket explicitly only in live online mode.

- **[P2-11] Cross-Doc Constant/Contract Drift & Blocked GitHub Actions CI (`0s` Billing Lock)** — `AGENTS.md:L112,L240-L265`, `docs/project-plan.md:L16,L49,L55`, `docs/index.md:L36`, `README.md`, `.github/workflows/gates.yml:L30`
  - **Root Cause Mechanism:** Gate counts disagree across four files (`AGENTS.md` = `29`, `README.md`/`task-status.md` = `28`, `.github/workflows/gates.yml:L30` & `docs/project-plan.md:L49` = `27`, `docs/index.md:L36` = `25`); `docs/project-plan.md:L16,L55` still reports `PROTOCOL_VERSION = 2` (actual is `3`); `AGENTS.md:L241-L265` still claims `"every player is dealt a vehicle; nobody picks"`, `"bit 15"`, and `"SideCannons PROFILES is keyed bike/pogo only"` immediately below the Aston Martin selector section. Simultaneously, GitHub Actions billing lock (`TS-001`) causes workflow runs to fail in `0s`, leaving pushes to `main` ungated before Vercel auto-deploy.
  - **Deterministic Trigger & Failure Mode:** Agents/contributors following stale docs risk reverting 3-vehicle selector or protocol v3 contracts; unverified commits auto-deploy directly to production Vercel.
  - **Surgical Fix Specification:** Sweep `AGENTS.md`, `README.md`, `docs/index.md`, `docs/project-plan.md`, `docs/task-status.md`, and `.github/workflows/gates.yml` in one doc-sync commit; resolve `TS-001` so CI runs automatically on every PR/push.

---

### Lens 7: Reliability & Fault Tolerance

- **[P1-7] Five Hollow, Unexecuted, or Vacuous Regression Checks Creating False-Confidence Gate Passes** — `godot/tools/verify_deathrace.gd:L265-L283`, `godot/tools/verify_combat.gd:L127-L139`, `godot/tools/verify_accessibility.gd:L168-L185`, `godot/tools/verify_controls.gd:L100-L122`, `godot/tools/verify_talo_backend.gd:L277-L284`
  - **Root Cause Mechanism:**
    1. `verify_deathrace.gd:L268-L283`: queries nonexistent `mock_supa.get("_backend")` (`SupabaseClient` exposes `mock`/`talo`) -> `null` -> entire 3-victim AOE sub-token block **never executes** (and passes wrong arg names `killer_id`/`victim_id`/`shot_token` instead of `p_killer`/`p_target`/`p_token`).
    2. `verify_combat.gd:L127-L139`: adds `enemy_bike` to nonexistent group `"networked_bike"` instead of `"bike"`; passes `10/10` ONLY because `meteor_hazard.queue_free()` (`L125`) omitted `await process_frame`, leaving the old meteor hazard alive at `sp0`!
    3. `verify_accessibility.gd:L168-L185`: attaches `MatchHud.gd` to a bare `CanvasLayer` lacking a `KillFeed` child -> `add_kill()` exits early -> `_check(feed == null or feed.get_child_count() <= 4)` passes vacuously on `feed == null` (real cap is `5`) and `0.15 s` never reaches the `4.0 s` timer.
    4. `verify_controls.gd:L100-L122`: instantiates bare `KiepieBike.tscn` (no `CombatController` -> no `_engine_player`) -> **confirmed in live `controls.log:L18`:** `PASS KiepieBike engine RPM pitch check skipped (no _engine_player in headless)`.
    5. `verify_talo_backend.gd:L277-L284`: sets `_channel_id = 99` (never exercising `_channel_id <= 0`) and asserts unconditional `_check(true, ...)`.
  - **Deterministic Trigger & Failure Mode:** Regressions in AOE sub-token scoring, enemy-bike spawn avoidance, `MatchHud` kill-feed eviction/timers, engine RPM pitch rise, or `_poll_host_alive` guards pass `run_gates.sh` silently.
  - **Surgical Fix Specification:** Repair all five blocks with fail-first assertions (live `Supabase.call_rpc("register_kill", {"p_killer": ..., "p_target": ..., "p_token": ...})`, `await process_frame` + `"bike"` group, real `Arena.tscn` `KillFeed` asserting `count == 5`, bike with `CombatController`, and `_channel_id = 0` observable check).

- **[P2-4] `SettingsMenu` Quality Preset Wipes Unrelated Pending Debounced Writes (Audio/Controls/Color)** — `godot/src/ui/SettingsMenu.gd:L42-L52`
  - **Root Cause Mechanism:** Selecting a quality preset calls `_pending_writes.clear()` (`L48`) and stops `_flush_timer` (`L50`) before `Settings.apply_quality()`, discarding any audio, steering, or color edits queued within the `350 ms` debounce window.
  - **Deterministic Trigger & Failure Mode:** Adjusting volume or steering sensitivity and switching quality preset within `350 ms` silently drops the audio/control change on reload.
  - **Surgical Fix Specification:** Flush all non-`"video"` keys in `_pending_writes` before `Settings.apply_quality(...)`, discarding only pending `"video/*"` keys.

- **[P2-10] Non-Atomic FFmpeg Overwrite Without Timeout & 1-Frame Stale `matrix_world` in Intro Splash Pipeline** — `src/build_intro_splash.py:L180-L196,L447`
  - **Root Cause Mechanism:** `subprocess.run(["ffmpeg", ..., str(OUT_MP4)], check=True)` (`L447`) overwrites tracked `web-assets/kiepie-quad-splash.mp4` in place with no `timeout=` and no temp + `os.replace()`; Act 1 tracer spawn reads `quad_root.matrix_world` (`L180-L196`) without `bpy.context.view_layer.update()`.
  - **Deterministic Trigger & Failure Mode:** Interrupted FFmpeg leaves a corrupted video asset; Act 1 tracers lag 1 frame behind the moving quad.
  - **Surgical Fix Specification:** Write to `.tmp.mp4` with `timeout=120`, swap via `os.replace()`, and call `bpy.context.view_layer.update()` before reading `quad_root.matrix_world`.

- **[P3-5] Silent `except Exception: pass` in Aston Sculpt, Unclosed File Handle in `check_scene_sync.py` & Sparse Haptics** — `src/build_aston_martin.py:L675`, `godot/tools/check_scene_sync.py:L107`, `godot/src/KiepieBike.gd:L395`
  - **Root Cause Mechanism:** Bare `except Exception: pass` swallows AgX color-management failures (`build_aston_martin.py:L675`); `open(path).read()` omits `with` (`check_scene_sync.py:L107`); `Input.vibrate_handheld()` only fires on hard landing (`KiepieBike.gd:L395`), leaving hits, kills, dodges, and weapon fire without haptics.
  - **Deterministic Trigger & Failure Mode:** Silent Blender color fallback; mobile combat lacks tactile punch.
  - **Surgical Fix Specification:** Warn on fallback in `build_aston_martin.py:L675`; use `with open(...)` in `check_scene_sync.py:L107`; add `reduced_motion`-gated short vibration pulses on hit/kill/dodge.

- **[P3-6] [LIVE-REPRODUCED] Live Sandbox & Tooling Hygiene Warnings (`check_web_hygiene.py`, `build_menus._verify`, GLB LOD Normal, WebGL2 `ReadPixels`)** — `godot/tools/check_web_hygiene.py:L20`, `godot/tools/build_menus.gd:L471-L556`, `import.log:L4`, `accessibility.log:L42`
  - **Root Cause Mechanism:** (1) `check_web_hygiene.py:L20` calls `subprocess.check_output(["git", "ls-files"])` without handling non-git directories (crashes with `CalledProcessError` in `git archive` exports, unlike `check_scene_sync.py`); (2) `build_menus.gd:_verify()` omits `VehicleRow/VehicleSelect` and only checks flat leaf names (`node_path.get_file()`); (3) live sandbox import logged `WARNING: Ignoring face with non-finite normal in LOD generation` (`import.log:L4`), `accessibility.log:L42` logged inconsistent owner warning for `TouchHUD`, headless gates emit `ERROR: Parameter "m" is null. at: mesh_get_surface_count`, and live Chrome logged 4 `GPU stall due to ReadPixels` warnings on boot.
  - **Deterministic Trigger & Failure Mode:** Running `run_gates.sh` inside a non-`.git` release tarball crashes `web_hygiene`; mis-nested menu nodes pass `_verify()`; degenerate GLB triangles trigger import LOD warnings.
  - **Surgical Fix Specification:** Gracefully fall back or skip `.vercelignore` git check outside `.git` in `check_web_hygiene.py`; validate full relative node paths + `VehicleSelect` in `build_menus.gd`; audit/weld zero-area faces in the GLB exporters.

---

### Lens 8: Type Systems, Schema & Contracts

- **[P2-1] `TaloBackend.join_lobby_channel()` Omits `"vehicle"` in `"join"` Payload, Unbounded Guest `_used_tokens` & Unguarded Await Loops** — `godot/src/net/TaloBackend.gd:L82,L241-L243,L416,L462,L804`
  - **Root Cause Mechanism:** `join_lobby_channel()` sends `"join"` without `"vehicle": Settings.preferred_vehicle()` (`L241-L243`), so host `"join"` allowlist (`L940`) resets a rejoining player's vehicle preference to `""`; guest `_register_lap()` (`L804`) inserts into `_used_tokens` without `MAX_USED_TOKENS` eviction; `start()` (`L82`), `_join_auto()` (`L416`), and `_join_by_code()` (`L462`) await `get_tree().process_frame` without `is_inside_tree()` guards (unlike `L167`).
  - **Deterministic Trigger & Failure Mode:** Direct channel rejoin clears `BIG-BEN F1` preference back to auto-deal; exiting tree during join await risks null `get_tree()` error.
  - **Surgical Fix Specification:** Add `"vehicle": Settings.preferred_vehicle()` at `L243` (and preserve `prev.get("vehicle", "")` on host when omitted); cap `_used_tokens` via shared helper in `_register_lap()`; guard `is_inside_tree()` in `L82`, `L416`, `L462`.

---

### Lens 9: Platform, Viewport & Portability

> *Verified Strengths:* Dual-thumb multitouch arbitration (`TouchControls.gd` + `TouchCapture.gd` `MOUSE_FILTER_IGNORE` pass-through + refcounted holds + cancel/focus-out cleanup) passed `verify_touch_multitouch.gd` under `xvfb` with 0 failures; static WCAG contrast passes AAA (`>= 7.22:1`); `#victory-skip` measured `124.7 × 44 px` in live Chrome.

- **[P1-10] [LIVE-REPRODUCED] `MainMenu.tscn` Clips Bottom Card Border, `Footer` & `SETTINGS` Off-Screen on Mobile Portrait (`375×667`) & Landscape (`667×375`)** — `godot/tools/build_menus.gd:L225-L310`, `godot/src/ui/MainMenu.gd:L144-L180`
  - **Root Cause Mechanism:** Unlike `LobbyMenu.tscn` (`build_menus.gd:L322`) and `SettingsMenu.tscn` (`L406`), `MainMenu.tscn` places `Card` directly inside `SafeMargin` with **no `ScrollContainer`**. Commit `c97a796` added `VehicleRow` (`RIDE` selector, `+64 px` portrait/desktop, `+42 px` landscape), pushing `Card/VBox` minimum height past `667 px` portrait and `375 px` landscape.
  - **Deterministic Trigger & Failure Mode:** **Live-reproduced in Pass 2.5 Chrome screenshots:** at `375×667` (iPhone SE portrait), the bottom rounded border of `Card` and the entire `Footer` are clipped off-screen; at `667×375` (iPhone SE landscape), the bottom border is clipped and `SETTINGS` sits flush against the viewport bottom (and overflows completely on `<= 360 px` Android landscape viewports).
  - **Surgical Fix Specification:** Wrap `SafeMargin/Card` inside a vertical `ScrollContainer` (with `horizontal_scroll_mode = SCROLL_MODE_DISABLED` and `UI.style_scroll()`, matching `LobbyMenu`/`SettingsMenu`) in `build_menus.gd`, rebuild `MainMenu.tscn`, and verify zero clipping at `375×667`, `667×375`, and `360×640`.

- **[P2-12] [LIVE-REPRODUCED] `TestRide.tscn` Solid `StaticBody3D` Cone Impales Center of `RampRight` (`dist = 0.00 m`) + Unreadable `WeaponLabel` + Stale `Help` Copy + `0 px` Button Gap** — `godot/tools/build_testride.gd:L77,L95,L142-L144,L179-L188,L225-L263`, `godot/tools/TouchOverlayKit.gd:L28-L37`
  - **Root Cause Mechanism:** Four compounding Practice-scene defects caught directly in the live `1280×720` WebGL2 screenshot:
    1. `build_testride.gd:L77` places a solid `StaticBody3D` cone (`Cone#24`) at `Vector3(8, 0.35, 14)` and `L95` places `RampRight` at `Vector3(8.0, 0.0, 14.0)` — **exact `0.00 m` overlap**, impaling the ramp face with an immovable collider!
    2. `WeaponLabel` (`L179-L188`) has no dark `outline_size` or backdrop chip (unlike `Arena.tscn`'s `_outlined()`), making light-blue `F1 AUTOCANNON · READY` low-contrast over bright 3D asphalt/ramps.
    3. `Help` text (`L142-L144`) completely omits `F / Click = fire` and `TAB / 1-3 = weapon` even though Practice mode has the full 3-weapon arsenal.
    4. Right-side buttons (`RestartBtn`, `ViewBtn`, `MenuBtn`, `BtnTouchToggle`) use `min_h = 52 px` (`UI.style_button`) while `offset_top` steps by `52 px` (`10 -> 62 -> 114 -> 166`), leaving **`0 px` gap** with overlapping drop shadows.
  - **Deterministic Trigger & Failure Mode:** Driving up `RampRight` in Practice mode smashes into an impaled static cone; players see contradictory controls and low-contrast weapon text.
  - **Surgical Fix Specification:** Move the slalom cone pair off `RampRight` (e.g., `z = 20` or `x = +-4.5`), add a dark outline (`outline_size = 5`, black outline) or chip to `WeaponLabel`, update `Help` to include `F/Click fire · TAB/1-3 weapon`, and space right-side button `offset_top` by `58 px` (`10, 68, 126, 184`), then rebuild `TestRide.tscn`.

- **[P3-4] Compact `38 px` `MainMenu` Targets, Non-Reactive `controls/touch_force`, Missing `Hud.gd` Click SFX & Unsynced `LobbyMenu._ready_state`** — `godot/src/ui/MainMenu.gd:L171-L178`, `godot/src/TouchControls.gd:L127-L129`, `godot/src/Hud.gd:L40-L60`, `godot/src/ui/LobbyMenu.gd:L57,L234-L278`
  - **Root Cause Mechanism:** At `vp.y <= 420`, `MainMenu` shrinks buttons to `38 px` (passes WCAG `24 px`, below Apple/Material `44 px`; unnecessary once `P1-10` adds a `ScrollContainer`); `TouchControls._on_settings_changed()` ignores `"controls/touch_force"`; `Hud.gd` buttons omit `Sfx.play_ui("ui_click")`; `LobbyMenu._ready_state` never syncs from `Match.players[my_user_id]["is_ready"]` on refresh.
  - **Deterministic Trigger & Failure Mode:** Cramped landscape buttons, non-live `touch_force` toggle, silent Practice HUD clicks, and stale READY toggle state on lobby re-entry.
  - **Surgical Fix Specification:** Keep `MainMenu` buttons `>= 44 px` inside the new `ScrollContainer`; react to `touch_force` in `TouchControls`; add `ui_click` in `Hud.gd`; sync `_ready_state` in `LobbyMenu._refresh_players()`.

---

### Lens 10: Cognitive Load & AI Maintainability

> *Cross-references:* `P2-8` (15 God files `>400` effective LOC) and `P2-11` (contradictory `AGENTS.md` vehicle/protocol rules).

- **[P3-1] Authored-but-Unwired Config Keys, Dead Fields/Helpers & Unreachable Service Worker Branch** — `godot/src/core/Settings.gd:L44`, `godot/src/net/TaloBackend.gd:L433`, `godot/src/net/MockBackend.gd:L20`, `godot/src/ui/LobbyMenu.gd:L32`, `godot/src/ui/MatchHud.gd:L649`, `godot/src/game/CombatController.gd:L34,L125`, `godot/src/game/NetworkedBike.gd:L21,L117`, `index.service.worker.js:L126`
  - **Root Cause Mechanism:** Authored keys with zero live wiring: `Settings.DEFAULTS["network"]["auto_join"]` (`Settings.gd:L44`), `"friendly_fire": false` (`TaloBackend.gd:L433`, `MockBackend.gd:L20`, `LobbyMenu.gd:L32`), unexposed `gameplay/kill_feed` (`MatchHud.gd:L649`); dead members `CombatController._smoke_accum` (`L34`), `_flames()` (`L125`), `NetworkedBike._ring` (`L21`), `prev_vehicle` (`L117`); and unreachable `index.manifest.json` SW branch (`index.service.worker.js:L126`, absent from `FULL_CACHE`).
  - **Deterministic Trigger & Failure Mode:** Dead fields and fake settings mislead future contributors and waste AI agent context.
  - **Surgical Fix Specification:** Remove dead members and unreachable SW branch; expose `gameplay/kill_feed` in `SettingsMenu` or delete the key; remove or mark `network/auto_join` and `friendly_fire` reserved.

---

### Lens 11: Engagement, Game-Feel & Feedback Coverage Table

| Gameplay Loop / Event | Visual Feedback | Audio Feedback | Haptic / Juice | Verified Status & Gaps |
| :--- | :--- | :--- | :--- | :--- |
| **Online Boot & Matchmaking** | Status label, mode/vehicle selectors | Menu `ui_click` | N/A | **CRITICAL (`P0-1`):** `2.5 s` cold-boot timeout permanently bricks online play with no retry; `MainMenu` clips on mobile (`P1-10`); waiting-lobby host disconnect soft-locks guests (`P1-9`) |
| **Throttle, Steer, Turbo & Camera** | Tire roost, afterburner plume, FOV kick, `PogoVisual` hop/flap | Continuous engine RPM pitch + turbo whoosh | None | **Strong forward driving**; `FollowCam` snaps 180° on fast reverse slide (`P2-13`); `PogoVisual` remote yaw snaps in loops (`P2-7`) |
| **Q/E Dodge Cartwheel** | 360° chassis roll + dust puff | None dedicated | None | **Bugged dust anchor:** takeoff dust puff cartwheels mid-air with bike (`P2-13`); add subtle whoosh + `15 ms` haptic (`P3-5`) |
| **Firing MG / Banana / Rocket / Meteor** | Muzzle flash pool, tracers, 3D meteor reticle, `ReloadBar` | `cannon_fire`, `pop`, `explosion` | None | **Broken at speed in MP** (`P1-3` drops remote shots `> 5.0 m`); `TestRide` `WeaponLabel` unreadable & `Help` omits weapons (`P2-12`) |
| **Damage, Kills & Explosions** | Damage numbers, scorch/scars, mushroom cloud, wreck, `KiepieTime` hitstop | `impact`, `dink`, `explosion`, `kill` | None | **Strong VFX/audio**; dead local bike plunges under map with `FollowCam` (`P1-4`); `scorch` ignores elevated `y` (`P3-3`) |
| **Death Race Laps, Loops & Practice Pad** | Ordered checkpoints, `LoopZone`, finish gantry, victory video | `pickup` (lap), `kill` (finish) | Hard landing only (`28 ms`) | **Physics/UI bugs:** `Cone#24` impales `TestRide` `RampRight` (`P2-12`); guest lap rollback HUD drift (`P1-5`); solo `"BATTLE ROYALE"` banner (`P2-2`); loop stall trap (`P2-5`) |
| **Spatial Awareness (Radar & HUD)** | Corner radar, kill feed, scoreboard dropdown | Menu `ui_click` only | None | **Disorienting radar** (`P2-3` inverted `+Z`/`+X` & unrotated); `Hud.gd` buttons lack click SFX (`P3-4`) |

---

## 3. Existing Test Suite Comparison & Mutation Truth Table

- **Test-to-Code File Ratio:** `29 / 72` (`0.40`; `4,240 / 19,240` effective LOC = `0.22`)
- **Shipped Module Verification:** All `41` runtime scripts in `godot/src/` are verified referenced/shipped via `godot/project.godot`, `godot/scenes/*.tscn`, or `class_name` consumers (`0%` unshipped test-only modules).
- **Estimated Mutation Kill Score ($M_{\text{kill}}$):** **`48.3%`** (`29/60` mutants killed across `15` critical module groups; `586` assertions across `29` test/gate files, `29/29` files contain negative/boundary signals, `10` mock-using files, `1` directly unpaired critical runtime module [`LobbyService.gd`])

| Implementation Module | Critical Functions / Branches | Paired Test File(s) | Pathologies Detected | Mental Mutants Killed (`M1–M4`) | High-Priority Missing Assertions |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `godot/src/net/TaloBackend.gd` + `settings.cfg` | `start`, `_on_socket_message`, `_poll_host_alive`, `_register_kill`, `_register_lap` | `verify_talo_backend.gd`, `verify_audit_regressions.gd` | `No-Throw Theater` (`L283`), `Happy-Path`, live `401` leak (`P1-8`) | `1/4 (25%)` | Late `"v1.players.identify.success"` recovery (`P0-1`); host self-echo ignored (`P1-1`); waiting-lobby host-loss (`P1-9`); `auto_connect_socket=false` (`P1-8`) |
| `godot/src/net/LobbyService.gd` | `join_auto`, `join_by_code`, `create_lobby`, `leave` | `NONE` (indirect via `verify_match_rules.gd`) | Unpaired critical async module | `1/4 (25%)` | `leave()` while `current_lobby_id == ""` cancels in-flight join/create RPC without ghost lobby (`P1-2`) |
| `godot/src/game/ArenaNet.gd` | `_spawn_remote_shot`, `_send_state`, `_create_remote` | `verify_multiplayer.gd`, `verify_audit_regressions.gd`, `verify_vfx.gd` | `Happy-Path` (stationary sender at origin) | `3/4 (75%)` | Remote shot accepted at `32 m/s` (`8 m` lag offset) while spoofed `25 m` origin still rejected (`P1-3`) |
| `godot/src/game/NetworkedBike.gd` | `apply_state`, `set_respawning`, `update_identity` | `verify_multiplayer.gd`, `verify_aston.gd`, `verify_pogo.gd` | `Result-Only` + typo (`_death_lock_until` at `L339`) | `2/4 (50%)` | Stale pre-death `d=false, t=true` inside `_kill_lock_until` mutates neither `turbo_active` nor `_target_pos` (`P1-6`) |
| `godot/src/game/CombatController.gd` | `_die`, `_respawn`, `reset_state`, `_pick_safe_spawn`, `take_damage` | `verify_combat.gd`, `verify_kill_flow.gd`, `verify_practice.gd` | `Shared Mutable State` (`queue_free` without `await` + wrong group `"networked_bike"`) | `3/4 (75%)` | `bike.freeze == true` & `y >= -0.5` for 60 frames after `_die()` (`P1-4`); `_pick_safe_spawn` avoids `"bike"` (`P1-7`) |
| `godot/src/game/RaceTracker.gd` | `_on_finish_line_entered`, `_on_roster_changed` | `verify_deathrace.gd` | `Happy-Path Tunnel Vision` (solo/host only) | `2/4 (50%)` | Guest rollback in `_on_roster_changed()` resets `current_lap`; dropped final-lap RPC recovery (`P1-5`) |
| `godot/src/KiepieBike.gd` + `VehicleHandling.gd` + `FollowCam.gd` | `_integrate_forces`, `_try_dodge`, `aero_drag_accel`, `FollowCam._process` | `verify_controls.gd`, `verify_dodge.gd`, `verify_rollover.gd`, `truth_test.gd` | `No-Throw Theater` (`controls.log:L18` skips RPM check) | `3/4 (75%)` | Engine RPM rise with `CombatController`; aero drag at `400 m/s`; reverse-slide `FollowCam` stability; world-anchored dodge dust |
| `godot/src/game/LoopZone.gd` | `_physics_process` (`_climbed`, center fallback) | `verify_deathrace.gd` | `Happy-Path` (never tests stall/center/free) | `1/4 (25%)` | Stall-back clears `_climbed`; center fallback zeroes tangent/pull; freed bike prunes `_climbed` (`P2-5`) |
| `godot/src/game/SideCannons.gd` + Projectiles | `setup`, `fire`, `Projectile.setup`, AOE sub-tokens | `verify_cannons.gd`, `verify_vfx.gd`, `verify_deathrace.gd`, `verify_practice.gd` | Unexecuted block (`verify_deathrace.gd:L268` `_backend == null`) | `2/4 (50%)` | Live 3-victim AOE sub-token `register_kill` scoring (`P1-7`); repeated fallback muzzle cleanup; inert `Projectile` pool (`P2-9`) |
| `godot/src/TouchControls.gd` + Pads | `_input`, `_relayout`, `_on_settings_changed` | `verify_touch.gd`, `verify_touch_multitouch.gd`, `test_kiepie_pad.gd` | None (gold-standard `xvfb` suite; minor reactivity gap) | `3/4 (75%)` | Runtime `Settings.set_value("controls", "touch_force", ...)` updates overlay live (`P3-4`) |
| `godot/src/ui/MatchHud.gd` | `add_kill`, `_play_victory_splash`, `_on_play_again`, `RadarControl._draw` | `verify_accessibility.gd`, `verify_multiplayer.gd`, `verify_deathrace.gd` | `No-Throw Theater` (`feed == null`) + `Time-Window Myopia` (`0.15 s` vs `4.0 s`) | `0/4 (0%)` | Real `KillFeed` eviction (`== 5`) & timer cleanup (`P1-7`); solo Death Race banner (`P2-2`); heading-aligned radar (`P2-3`) |
| `godot/src/ui/MainMenu.gd` + `LobbyMenu.gd` + `build_menus.gd` | `_apply_responsive_layout`, `_on_auth_status`, `_refresh_players`, `_verify` | `verify_deathrace.gd`, `verify_aston.gd`, `verify_accessibility.gd` | Missing viewport overflow & offline-retry tests | `1/4 (25%)` | Zero `Card` clipping at `375×667` & `667×375` (`P1-10`); `MainMenu` offline retry action (`P0-1`); `build_menus` path check (`P3-6`) |
| `godot/src/core/Settings.gd` + `SettingsMenu.gd` | `apply_quality`, `_connect_controls`, `v1 -> v2` migration | `verify_settings.gd`, `verify_accessibility.gd` | `Happy-Path` (preset debounce interaction untested) | `2/4 (50%)` | Changing quality preset within `350 ms` preserves pending audio/controls writes (`P2-4`) |
| `godot/src/game/VfxFactory.gd` | `prewarm`, `_plane_basis`, `scorch`, caps, `reduced_motion` | `verify_vfx.gd`, `verify_audit_regressions.gd` | Minor boundary gap (`Vector3.ZERO`, elevated `scorch`) | `3/4 (75%)` | `_plane_basis(Vector3.ZERO)` finite basis (`P2-8`); `scorch` respects elevated `pos.y` (`P3-3`) |
| `godot/src/game/PogoVisual.gd` + `KiepieTime.gd` | `_process` remote yaw, `trigger_hitstop` | `verify_pogo.gd`, `verify_combat.gd` | Missing `NaN` & pitch-inversion boundaries | `2/4 (50%)` | `KiepieTime.trigger_hitstop(root, NAN, 0.1)` leaves `time_scale == 1.0` (`P2-6`); inverted loop proxy causes no yaw snap (`P2-7`) |

### Why Existing Tests Missed Discovered P0/P1 Defects

- **P0-1 (`TaloBackend` `2.5 s` cold-boot multiplayer brick):** All 29 gates run under `KIEPIE_MOCK_BACKEND=1`, never testing real WebSocket boot latency (`>2.5 s`) or late `"v1.players.identify.success"` delivery against `TaloBackend.start()` + `MainMenu`.
- **P1-1 (`TaloBackend` host self-echo rollback):** `verify_audit_regressions.gd:L109-L118` never delivers an older host `"state"` echo after a newer host mutation.
- **P1-2 (`LobbyService` ghost lobby leak):** `LobbyService.gd` has no unit test exercising `leave()` while `join_auto`/`create_lobby` is awaiting RPC resolution.
- **P1-3 (`ArenaNet` `5.0 m` muzzle drop):** Tests park stub senders at `(0, 0, 0)` and shoot from `(0, 0, 0)`, never simulating `6-10 m` high-speed lag.
- **P1-4 (`CombatController` unfrozen corpse free-fall):** Gates check `alive`/`visible`/`collision_layer` immediately after `_die()` without stepping physics for `60+` frames.
- **P1-5 (`RaceTracker` guest rollback):** `verify_deathrace.gd` tests solo/host laps only, never guest `_on_roster_changed()` rollback or dropped final-lap RPCs.
- **P1-6 (`NetworkedBike` pre-`_kill_lock_until` mutation):** `verify_multiplayer.gd:L339` has a typo (`_death_lock_until` instead of `_kill_lock_until`), so the test passed *because* of the premature `turbo_active` write.
- **P1-7 (Five hollow gate checks):** Gate scripts lacked fail-first mutation validation (`_backend` typo silently skipped, `meteor_hazard` leaked across subtests, `feed == null` passed vacuously, `_engine_player` skipped, `_check(true)` no-op).
- **P1-8 (Offline gates hitting live `api.trytalo.com`):** `run_gates.sh` only rejects `FAIL` / script errors and ignores Talo `ERROR: 401` stderr lines emitted when `settings.cfg` has `auto_connect_socket=true`.
- **P1-9 (Waiting-lobby host disconnect soft-lock):** `verify_talo_backend.gd` tests `_poll_host_alive` / `host_lost` only in `"playing"` state, never `"waiting"`.
- **P1-10 (`MainMenu` mobile clipping):** `verify_accessibility.gd` checks button minimum height, never verifying `Card.get_global_rect().end.y <= viewport.size.y` (or scrollable container) at `375×667` / `667×375`.

### Minimal Viable Test Harness (MVTH) Specifications

1. **MVTH-1 (`TaloBackend` Late-Identify Recovery, Self-Echo, Waiting Host-Loss & Zero-Network Gate Guard — Tier 1):** Assert `godot/addons/talo/settings.cfg` has `auto_connect_socket=false`; feed late `"v1.players.identify.success"` after `start()` timeout and assert `is_ready == true`; feed stale host `"state"` echo and assert `_roster` does not roll back; simulate host `"leave"` / stale heartbeat in `"waiting"` state and assert `host_lost` fires.
2. **MVTH-2 (`LobbyService` In-Flight Cancellation — Tier 2):** Start `Lobby.join_auto()` against a delayed RPC, invoke `Lobby.leave()` while `current_lobby_id == ""`, let RPC resolve, and assert `Match.lobby.is_empty()` and `Lobby.current_lobby_id == ""`.
3. **MVTH-3 (`ArenaNet` High-Speed Lag Window & `CombatController` Frozen Corpse — Tier 2):** Assert `_spawn_remote_shot` accepts an `8 m` lag offset and rejects a `25 m` spoof; kill local bike and step `90` physics frames asserting `bike.freeze == true` and `bike.global_position.y > -1.0`.
4. **MVTH-4 (`NetworkedBike` Kill-Lock Ordering & `RaceTracker` Guest Rollback — Tier 1):** Apply `{d: false, t: true, p: [9,0,9], n: 50}` inside `_kill_lock_until` and assert `turbo_active == false` and `_target_pos` unchanged; trigger `_on_roster_changed()` rollback on guest `RaceTracker` asserting `current_lap == completed_laps + 1`.
5. **MVTH-5 (`MainMenu` Mobile Scroll/Bounds & `TestRide` Cone/Ramp Clearance — Tier 2):** Mount `MainMenu.tscn` at `375×667` and `667×375` asserting either `Card` fits inside viewport or sits inside a `ScrollContainer` covering all controls; in `verify_vfx.gd`, assert every `TestRide` cone clears every `Ramp*` AABB by `>= 1.5 m`.
6. **MVTH-6 (Repair 5 Hollow Gates + Pure Math Edge Table — Tier 0/1):** Fix all 5 checks in `P1-7` (fail-first verified), plus assertions for `MatchHud` real `KillFeed` (`count == 5`), heading-aligned radar math, `KiepieTime.trigger_hitstop(root, NAN, 0.1)` (`time_scale == 1.0`), `VfxFactory._plane_basis(Vector3.ZERO)`, and `FollowCam` reverse-slide stability.

---

## 4. Surgical Refactoring Blueprints (Zero-Mutation Drafts)

### Refactor [R0]: Resilient `TaloBackend` Cold-Boot Socket Identification & `MainMenu` Retry (`P0-1`)

- **Target Scope:** `godot/src/net/TaloBackend.gd:L80-L95,L871-L914`, `godot/src/ui/MainMenu.gd:L232-L297`
- **Engineering ROI:** Eliminates the live-reproduced production Web multiplayer lockout for non-low-latency / cold-boot users in ~25 LOC.

**Current Pattern (Audited Code):**

```gdscript
# TaloBackend.gd:L80-L90
await Talo.socket.open_connection()
var sock_deadline := Time.get_ticks_msec() + 2500
while not bool(Talo.socket.get("_identified")) and Time.get_ticks_msec() < sock_deadline:
	await get_tree().process_frame
if not bool(Talo.socket.get("_identified")):
	is_ready = false
	_starting = false
	auth_status.emit(false, "Talo socket timed out — check your connection")
	return
```

**Target Pattern (Surgical Blueprint):**

```gdscript
# TaloBackend.gd: tolerate cold WebGL2 boot / >800 ms RTT AND promote late identify frames
const SOCKET_IDENTIFY_TIMEOUT_MS := 10000

func _promote_online() -> void:
	if is_ready:
		return
	is_ready = true
	_starting = false
	_reconnect_attempts = 0
	connection_state.emit("connected")
	var ident := str(Talo.current_alias.identifier) if Talo.current_alias != null else user_id
	auth_status.emit(true, "talo online · " + ident)

# Inside start():
var sock_deadline := Time.get_ticks_msec() + SOCKET_IDENTIFY_TIMEOUT_MS
while is_inside_tree() and not bool(Talo.socket.get("_identified")) and Time.get_ticks_msec() < sock_deadline:
	await get_tree().process_frame
if bool(Talo.socket.get("_identified")):
	_promote_online()
	return
is_ready = false
_starting = false
auth_status.emit(false, "Talo socket timed out — tap any multiplayer mode to retry")

# At top of _on_socket_message(res, data):
if res == "v1.players.identify.success":
	if not is_ready and Talo.current_alias != null:
		user_id = str(Talo.current_alias.id)
		_promote_online()
	return
```

---

### Refactor [R1]: Host Self-Echo Guard, Monotonic `state_seq` & Waiting-Lobby Host-Loss (`P1-1` & `P1-9`)

- **Target Scope:** `godot/src/net/TaloBackend.gd:L118-L124,L899-L913,L950-L956`, `godot/src/net/MatchState.gd:L32-L41`
- **Engineering ROI:** Eliminates host score/lap rollback races under RTT and prevents permanent `LobbyMenu` guest soft-locks on host disconnect.

**Current Pattern (Audited Code):**

```gdscript
# TaloBackend.gd:L899-L913
"state":
	if sender_id == "" or sender_id != str(_lobby.get("host_id", "")):
		return
	_host_ack = true
	if payload is Dictionary:
		... # overwrites host _lobby and _roster with own delayed echo
```

**Target Pattern (Surgical Blueprint):**

```gdscript
"state":
	if sender_id == "" or sender_id != str(_lobby.get("host_id", "")):
		return
	_host_ack = true
	if _is_host() and sender_id == user_id:
		return  # host owns authoritative _lobby/_roster; never roll back on own echo
	if payload is Dictionary:
		var p := payload as Dictionary
		var seq := int(p.get("seq", -1))
		if seq >= 0:
			if seq <= _last_state_seq:
				return
			_last_state_seq = seq
		if p.has("lobby") and p["lobby"] is Dictionary:
			_lobby = (p["lobby"] as Dictionary).duplicate(true)
		if p.has("roster") and p["roster"] is Dictionary:
			_roster = (p["roster"] as Dictionary).duplicate(true)
		_emit_state()
		_emit_roster()
```

---

### Refactor [R2]: Generation-Token Cancellation Across In-Flight `LobbyService` RPCs (`P1-2`)

- **Target Scope:** `godot/src/net/LobbyService.gd:L37-L83`
- **Engineering ROI:** Closes the ghost-lobby leak and prevents orphaned 20 s Talo heartbeats on cancel in ~15 LOC.

**Current Pattern (Audited Code):**

```gdscript
func join_auto(game_mode: String = "battle_royale") -> bool:
	var res: Dictionary = await Supabase.call_rpc("join_auto", { ... })
	return _enter(res)

func leave() -> void:
	if current_lobby_id == "":
		return
	_session_gen += 1
```

**Target Pattern (Surgical Blueprint):**

```gdscript
func _enter_if_current(gen: int, res: Dictionary) -> bool:
	if gen != _session_gen:
		if not res.has("error") and res.has("lobby"):
			await Supabase.call_rpc("leave_lobby", {})
			Supabase.leave_lobby_channel()
		return false
	return _enter(res)

func join_auto(game_mode: String = "battle_royale") -> bool:
	var gen := _session_gen
	var res: Dictionary = await Supabase.call_rpc("join_auto", { ... })
	return await _enter_if_current(gen, res)

func leave() -> void:
	_session_gen += 1  # ALWAYS invalidate any in-flight join/create RPC
	if current_lobby_id == "":
		return
	...
```

---

### Refactor [R3]: Speed-Scaled Muzzle Lag Window & Frozen Corpse Body (`P1-3` & `P1-4`)

- **Target Scope:** `godot/src/game/ArenaNet.gd:L280-L284`, `godot/src/game/CombatController.gd:L211-L216,L253-L257,L307-L318`
- **Engineering ROI:** Restores 100% of multiplayer shots/rockets/meteors at `28-36 m/s` and prevents under-map `FollowCam` plunges on death.

**Current Pattern (Audited Code):**

```gdscript
# ArenaNet.gd:L283
if sender.global_position.distance_to(o) > 5.0:
	return

# CombatController.gd:L211-L216
bike.visible = false
bike.set_physics_process(false)
bike.collision_layer = 0
bike.collision_mask = 0
```

**Target Pattern (Surgical Blueprint):**

```gdscript
# ArenaNet.gd: allow ~0.35 s net+smoothing lag at 36 m/s (~13 m) + 1.5 m muzzle offset
const MAX_REMOTE_MUZZLE_LAG_M := 16.0
if sender.global_position.distance_to(o) > MAX_REMOTE_MUZZLE_LAG_M:
	return

# CombatController.gd (_die):
bike.visible = false
bike.set_physics_process(false)
bike.freeze = true
bike.linear_velocity = Vector3.ZERO
bike.angular_velocity = Vector3.ZERO
bike.collision_layer = 0
bike.collision_mask = 0

# CombatController.gd (_respawn & reset_state, before bike.reset_bike()):
bike.freeze = false
```

---

### Refactor [R4]: Pre-Mutation `_kill_lock_until` Guard & Authoritative `current_lap` Sync (`P1-5` & `P1-6`)

- **Target Scope:** `godot/src/game/NetworkedBike.gd:L126-L158`, `godot/src/game/RaceTracker.gd:L47-L60`
- **Engineering ROI:** Eliminates ghost turbo VFX/position snaps on dead proxies and keeps guest lap HUD converged with host arbitration.

**Current Pattern (Audited Code):**

```gdscript
# NetworkedBike.gd:L141-L153
var dead_now := bool(data.get("d", false))
turbo_active = bool(data.get("t", false)) and not dead_now
...
if is_respawning and not dead_now:
	if (Time.get_ticks_msec() / 1000.0) < _kill_lock_until:
		return

# RaceTracker.gd:L55-L60
if auth_laps != completed_laps:
	completed_laps = auth_laps
	var target := maxi(1, int(Match.lap_target()))
	if completed_laps < target:
		race_finished = false
	_sync_hud()
```

**Target Pattern (Surgical Blueprint):**

```gdscript
# NetworkedBike.gd: check kill-lock BEFORE mutating _target_pos / _target_basis / turbo_active
var dead_now := bool(data.get("d", false))
if _initialised and is_respawning and not dead_now:
	if (Time.get_ticks_msec() / 1000.0) < _kill_lock_until:
		return

# RaceTracker.gd:
if auth_laps != completed_laps:
	completed_laps = auth_laps
	var target := maxi(1, int(Match.lap_target()))
	current_lap = mini(completed_laps + 1, target)
	if completed_laps < target:
		race_finished = false
	lap_pending = false
	_sync_hud()
```

---

### Refactor [R5]: Heading-Aligned Radar Projection & `FollowCam` Reverse Guard (`P2-3` & `P2-13`)

- **Target Scope:** `godot/src/ui/MatchHud.gd:L848-L874`, `godot/src/FollowCam.gd:L135-L140`
- **Engineering ROI:** Fixes inverted radar spatial awareness for every player and prevents 180° camera whip during high-speed reverse slides.

**Current Pattern (Audited Code):**

```gdscript
# MatchHud.gd:L866-L867
var d := node.global_position - origin
var offset := Vector2(d.x, d.z) / WORLD_RANGE * r

# FollowCam.gd:L138-L139
if horiz_v.length() > 8.0 and _cam_up.dot(Vector3.UP) > 0.85:
	fwd = fwd.lerp(horiz_v.normalized(), 0.45).normalized()
```

**Target Pattern (Surgical Blueprint):**

```gdscript
# MatchHud.gd: project into flattened local bike heading (+Z forward -> screen -Y, -X right -> screen +X)
var fwd3 := _local.global_transform.basis.z
var fwd := Vector2(fwd3.x, fwd3.z)
fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector2(0.0, 1.0)
var right := Vector2(-fwd.y, fwd.x)
var d := node.global_position - origin
var local_2d := Vector2(d.x * right.x + d.z * right.y, -(d.x * fwd.x + d.z * fwd.y))
var offset := local_2d / WORLD_RANGE * r

# FollowCam.gd: blend velocity heading only when moving forward, never antiparallel
if horiz_v.length() > 8.0 and _cam_up.dot(Vector3.UP) > 0.85:
	var vel_dir := horiz_v.normalized()
	if fwd.dot(vel_dir) > 0.25:
		fwd = fwd.lerp(vel_dir, 0.45).normalized()
```

---

## 5. Phased Execution Roadmap & Scoped Agent Prompts

1. **Phase 1 — Production Availability Containment (`P0-1`, `P1-8` + MVTH-1)**
   - Fix `TaloBackend.start()` `10 s` cold-boot socket deadline, handle late `"v1.players.identify.success"`, and add `MainMenu` offline retry/auto-reconnect (`P0-1`).
   - Commit `auto_connect_socket=false`, `handle_tree_quit=false`, and `[continuity] enabled=false` in `godot/addons/talo/settings.cfg` so offline gates never hit live `api.trytalo.com` (`P1-8`).
2. **Phase 2 — Netcode Races, Physics Safety, Mobile Layout & Gate Integrity (`P1-1`..`P1-7`, `P1-9`, `P1-10`, `P2-12` + MVTH-2..6)**
   - Fix host self-echo rollback (`P1-1`), waiting-lobby host-loss soft-lock (`P1-9`), `LobbyService` ghost-lobby leak (`P1-2`), `ArenaNet` `16.0 m` lag window (`P1-3`), unfrozen dead bike (`P1-4`), `RaceTracker` guest rollback (`P1-5`), and `NetworkedBike` `_kill_lock_until` order (`P1-6`).
   - Wrap `MainMenu` `Card` in a `ScrollContainer` (`P1-10`), move `TestRide` `Cone#24` off `RampRight` + fix `WeaponLabel`/`Help`/button spacing (`P2-12`), repair all 5 hollow gate checks (`P1-7`), rebuild scenes, run `bash godot/tools/run_gates.sh`, and re-deploy Web via `bash godot/tools/deploy_web.sh --apply`.
3. **Phase 3 — Math/State Polish, CI Governance & Modular Extraction (`P2-1`..`P2-11`, `P2-13`, `P3-1`..`P3-6`)**
   - Fix `MatchHud` solo banner, `PlayAgainBtn` DOM cleanup, heading-aligned radar, `SettingsMenu` debounce flush, `LoopZone` stall/center/leak, aero-drag clamp, `KiepieTime` `NaN` guard, `PogoVisual` loop yaw, `FollowCam` reverse guard, world-anchored dodge dust, `qb_core._cap_holes`, `SideCannons`/`Projectile` pooling, and `build_intro_splash.py` atomic FFmpeg write.
   - Sweep canonical constants across all docs & `gates.yml`, restore GitHub Actions CI (`TS-001`), clean dead config/members, and progressively split top God files (`VfxFactory`, `TaloBackend`, shared scene-builder helpers).

### Copy-Paste Surgical Prompts for Coding Agents

> **Prompt [P0-1 + P1-8] (`TaloBackend.gd` + `MainMenu.gd` + `addons/talo/settings.cfg`):**
> "Strictly scope edits to `godot/src/net/TaloBackend.gd`, `godot/src/net/SupabaseClient.gd`, `godot/src/ui/MainMenu.gd`, `godot/addons/talo/settings.cfg`, and `godot/tools/verify_talo_backend.gd`. Set `auto_connect_socket=false`, `handle_tree_quit=false`, and `[continuity] enabled=false` in `godot/addons/talo/settings.cfg` so offline gates never hit `api.trytalo.com`. Raise `TaloBackend` socket identify deadline to `10000 ms`, promote `is_ready = true` on late `v1.players.identify.success` in `_on_socket_message`, expose `Supabase.reconnect()`, and trigger reconnect from `MainMenu` when clicking multiplayer actions while offline. Add fail-first assertions in `verify_talo_backend.gd` and run `bash godot/tools/run_gates.sh --no-build`."

> **Prompt [P1-1 + P1-2 + P1-9] (`TaloBackend.gd` + `LobbyService.gd` + `MatchState.gd` + `LobbyMenu.gd`):**
> "Strictly scope edits to `godot/src/net/TaloBackend.gd`, `godot/src/net/LobbyService.gd`, `godot/src/net/MatchState.gd`, `godot/src/ui/LobbyMenu.gd`, `godot/tools/verify_audit_regressions.gd`, and `godot/tools/verify_talo_backend.gd`. Ignore host's own echoed `'state'` frame and add monotonic `_state_seq` (update `verify_audit_regressions.gd` positive control to guest `user_id = '2'`). Always bump `_session_gen` in `LobbyService.leave()` even when `current_lobby_id == ''` and abort/cleanup in-flight `join_auto`/`join_by_code`/`create_lobby` on mismatch. Run `_poll_host_alive()` and emit `host_lost` in `'waiting'` lobbies too, and return guests cleanly to `MainMenu` on `host_lost` in `LobbyMenu.gd`. Add regression tests and run `bash godot/tools/run_gates.sh --no-build`."

> **Prompt [P1-3 + P1-4 + P1-5 + P1-6] (`ArenaNet.gd` + `CombatController.gd` + `RaceTracker.gd` + `NetworkedBike.gd`):**
> "Strictly scope edits to those four runtime scripts plus `verify_combat.gd`, `verify_multiplayer.gd`, and `verify_deathrace.gd`. Raise `ArenaNet` muzzle lag ceiling to `16.0 m`; freeze (`bike.freeze = true`) and zero velocities in `CombatController._die()` and unfreeze before `reset_bike()` in `_respawn()`/`reset_state()`; recompute `current_lap = mini(completed_laps + 1, target)` in `RaceTracker._on_roster_changed()` without locking `race_finished` while `lap_pending`; move `NetworkedBike._kill_lock_until` guard before mutating `_target_pos`/`_target_basis`/`turbo_active` and fix `_death_lock_until` typo in `verify_multiplayer.gd:L339`. Add fail-first assertions and run `bash godot/tools/run_gates.sh --no-build`."

> **Prompt [P1-7] (Repair 5 Hollow Gates):**
> "Strictly scope edits to `godot/tools/verify_deathrace.gd`, `verify_combat.gd`, `verify_accessibility.gd`, `verify_controls.gd`, and `verify_talo_backend.gd`. Fix `verify_deathrace.gd:L265-L283` to call `Supabase.call_rpc('register_kill', {'p_killer': ..., 'p_target': ..., 'p_token': ...})` directly against an active mock lobby; add `await process_frame` after `meteor_hazard.queue_free()` and use group `'bike'` in `verify_combat.gd:L125-L139`; instantiate real `Arena.tscn` HUD in `verify_accessibility.gd:L168-L185` asserting `feed != null and feed.get_child_count() == 5`; test engine RPM rise with `CombatController` in `verify_controls.gd:L100-L122`; assert observable `_channel_id <= 0` guard in `verify_talo_backend.gd:L277-L284`. Run `bash godot/tools/run_gates.sh --no-build`."

> **Prompt [P1-10 + P2-12] (`build_menus.gd` + `MainMenu.gd` + `build_testride.gd` + `TouchOverlayKit.gd`):**
> "Strictly scope edits to `godot/tools/build_menus.gd`, `godot/src/ui/MainMenu.gd`, `godot/tools/build_testride.gd`, `godot/tools/TouchOverlayKit.gd`, and `godot/tools/verify_vfx.gd`. Wrap `MainMenu` `Card` in a vertical `ScrollContainer` so `375×667` and `667×375` viewports never clip `SETTINGS` or `Footer` (and keep buttons `>= 44 px`). In `build_testride.gd`, move the `(8, 0.35, 14)` slalom cone off `RampRight` `(8, 0, 14)`, add dark outline/chip to `WeaponLabel`, add `F/Click fire · TAB/1-3 weapon` to `Help`, and increase right-side HUD button vertical pitch to `58 px`. Add cone-to-ramp clearance assertion in `verify_vfx.gd` and run `bash godot/tools/run_gates.sh` so scenes rebuild in sync."

> **Prompt [P2-2 + P2-3 + P2-4 + P2-13 + P2-11] (HUD, Physics Edge Guards & Doc Sync):**
> "Strictly scope edits to `MatchHud.gd`, `SettingsMenu.gd`, `FollowCam.gd`, `KiepieBike.gd`, `VehicleHandling.gd`, `KiepieTime.gd`, `LoopZone.gd`, `PogoVisual.gd`, `VfxFactory.gd`, `src/qb_core.py`, `AGENTS.md`, `README.md`, `docs/index.md`, `docs/project-plan.md`, and `.github/workflows/gates.yml`. Fix `MatchHud` solo Death Race banner, `PlayAgainBtn`/`_exit_tree` splash drop, and heading-aligned radar; flush non-video pending writes in `SettingsMenu`; guard `FollowCam` forward dot `> 0.25`, world-anchor dodge dust in `KiepieBike:L615`, clamp aero drag, guard `KiepieTime` `is_finite()`, fix `qb_core._cap_holes` `used_edges.update(used)`, and sweep gate count (`29`), `PROTOCOL_VERSION = 3`, and 3-vehicle rules across docs."
