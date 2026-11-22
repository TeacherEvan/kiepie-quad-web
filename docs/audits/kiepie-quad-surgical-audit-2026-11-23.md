# Surgical Audit Report: Kiepie Quad (`TeacherEvan/kiepie-quad-web`)

| Audit Metadata | Specification |
| :--- | :--- |
| **Audit Date** | `2026-11-23` (post-Rev 2 remediation baseline at commit `5f82af03b353f9070b62d029c3e74c6a5a62fcea`) |
| **Audited Scope** | `godot/src/`, `godot/tools/`, `godot/tests/`, `src/`, root Web runtime (`index.html`, `index.service.worker.js`, `vercel.json`, `.vercelignore`, `.github/workflows/gates.yml`) — `75` tracked impl/build/tool files (`19,731` effective LOC), `26` tracked gate/test files (`4,167` effective LOC; `101` tracked first-party code files / `23,898` effective LOC), `199` HTML/inline Web-shell lines (`index.html`), total scored **`24,097` effective LOC** (plus `203` lines `index.service.worker.js`, `23` `vercel.json`, `7` `.vercelignore`; vendored `godot/addons/` and git-ignored `web/` & `docs/plans/Designs/` excluded from first-party score). |
| **Tech Stack & Runtime** | Godot 4.3 (`gl_compatibility` / WebGL2 WASM single-threaded), GDScript, Python 3 / Blender `bpy` 5.3, Talo `0.20.0` backend, Vercel static hosting + PWA Service Worker, GitHub Actions (`ubuntu-24.04` + `xvfb`). |
| **Pre/Post Audit SHA-256** | `3a027b97da9d7324 / 3a027b97da9d7324 (VERIFIED ZERO MUTATION — full: 3a027b97da9d73248b13477e7fbedfd8961da4f6130b041cabcbe37c4b9f4399)` |
| **Deterministic Health Score** | **`82 / 100`** (`D_raw = 69`, `scale = 0.2037`, `P_test = 4.0625`, `M_kill = 72.92%` (`35/48`)) — up from `60 / 100` (`HIGH`) in the 2026-11-22 Rev 2 audit. |
| **Vibe-Debt Risk Level** | **`MODERATE`** (`P0 = 0`, `P1 = 5`, `P2 = 8`, `P3 = 5`). |

---

## 1. Executive Architecture & Vibe-Debt Triage

All prior `P0` defects from the 2026-11-22 Rev 2 audit (Talo cold-boot timeout brick, forged `join`/`state` injection, `.vercelignore` exposure, and hitstop `Engine.time_scale` lock) are verified closed and live-proven on `https://kiepie-quad-web.vercel.app/` (`index.html` MD5 `df04e533dfc03061e331e316c10eafdf`, `index.service.worker.js` MD5 `dce71f8a84758678416d6768a6a00d77`, `COOP=same-origin`, `COEP=require-corp`, `CORP=same-origin`, `scene_sync OK`, `web_hygiene OK`, `0` console errors in live Chrome DevTools probe).

The primary residual risk is **second-order distributed state-machine regressions** around the Rev 2 hardening (`TaloBackend` host-handoff `_state_seq` rollover, `LobbyService._enter_if_current()` unguarded channel wipe, and `RaceTracker` missing-`"laps"` recovery disarm), one **multiplayer physics/trust-boundary exploit** (`R` instant spawn teleport active during live matches), and one **silent split-brain control bug** (`TouchControls._on_settings_changed()` failing to update `_force`).

| Severity Tier | Count | Deduction Weight | Primary Failure Domains |
| :--- | :--- | :--- | :--- |
| **P0 — Critical (Crash / Data Loss / Security / Leak)** | `0` | `-18 pts ea` | None (all prior P0s resolved and verified) |
| **P1 — High (Frame-Budget / Race / Logic Bug)** | `5` | `-8 pts ea` | `TaloBackend.gd`, `LobbyService.gd`, `KiepieBike.gd`, `TouchControls.gd`, `RaceTracker.gd` |
| **P2 — Medium (God File / Split-Brain State / Debt)** | `8` | `-3 pts ea` | `Projectile.gd`/`BananaProjectile.gd`, `VfxFactory.gd`, `MainMenu.gd`, `SettingsMenu.gd`, `TaloBackend.gd`, God-file cluster (`17` files `> 400` eff LOC), Web payload headroom (`index.pck` `3.54 MiB` / `4 MiB` cap) |
| **P3 — Low (Magic Constants / DX / Portability)** | `5` | `-1 pt ea` | `MatchState.gd`, `MatchHud.gd`/`TouchControls.gd`/`RocketProjectile.gd`/`MeteorStrike.gd`, `src/repair_and_verify.py`, `patch_web_html.py`/`AGENTS.md` |

### High-Risk File Telemetry Hotspots

| File Path | Effective LOC | Branch Density | Silent Catches | Risk Score | Primary Vibe-Debt Signature |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `godot/src/game/VfxFactory.gd` | `1191` | `0.010` | `0` | `1203.0` | God file (`>400` LOC); `impact()` light-budget hold; `casing()` reduced-motion bypass |
| `godot/src/net/TaloBackend.gd` | `976` | `0.052` | `0` | `1027.0` | God file; host-handoff `_state_seq` rollover; `_player_row()` missing `"laps"` |
| `godot/tools/build_deathrace.gd` | `949` | `0.007` | `0` | `956.0` | God scene builder (`>400` LOC) |
| `godot/src/ui/MatchHud.gd` | `748` | `0.048` | `0` | `784.0` | God HUD controller; `_fps_label` hardcoded landscape overlap |
| `src/build_pogo_nardus.py` | `702` | `0.070` | `0` | `751.0` | God Blender sculpt script |
| `godot/tools/build_arena.gd` | `700` | `0.006` | `0` | `704.0` | God scene builder |
| `godot/src/game/SideCannons.gd` | `579` | `0.078` | `0` | `624.0` | God weapon controller; primary casing spawn on banana profile |
| `godot/src/KiepieBike.gd` | `567` | `0.092` | `0` | `619.0` | God vehicle controller; ungated `reset_bike` in live multiplayer |
| `src/build_aston_martin.py` | `585` | `0.051` | `0` | `615.0` | God Blender sculpt script |
| `godot/src/ui/MobileTextInput.gd` | `385` | `0.034` | `4` | `598.0` | JS-bridge DOM catches (`L305, 315, 316, 421` — intentional browser-quirk guards) |
| `godot/tools/verify_vfx.gd` | `518` | `0.043` | `0` | `540.0` | God gate script |
| `godot/tools/verify_deathrace.gd` | `494` | `0.065` | `0` | `526.0` | God gate script |

### Shipped Payload & Pass 2.5 Live Probe Summary

- **Shipped Payload:** `index.wasm` (`34M` / `35,376,909 B`), `index.pck` (`3.6M` / `3,707,328 B` = `88.4%` of `deploy_web.sh:66`'s `4,194,304 B` abort ceiling), `web-assets/kiepie-quad-splash.mp4` (`1.9M` / `1,950,286 B`). All `41/41` `godot/src/*.gd` scripts are verified referenced and shipped (`0` dead modules).
- **Host Contention Guard (§8):** Host `nproc = 4`, `load average = 5.19 / 5.44 / 5.66` (`chrome` `309%` CPU). Wall-clock FPS timings are **unproven** under noisy host; all reported metrics below are deterministic counts, DOM rects, and hashes.
- **Pass 2.5 Pristine Baseline Probe (`git archive HEAD` at `http://127.0.0.1:18771/` with COOP/COEP/CORP):**
  - `1280×720`: `crossOriginIsolated=true`, `statusRemoved=true`, `canvas=1280×720`, `scrollW=1280`, `scrollH=720`, all 4 JS bridges (`__kiepieSetFullscreen`, `__kiepiePlayVictorySplash`, `__kiepieBackInstalled`, `__kiepieVk`) active, single accessible viewport meta, `0` console errors / `0` Talo `401`s.
  - `375×667`: `scrollW=375`, `scrollH=667`, `canvas=375×667`, `#victory-skip` measured `125×44 px` (`top=12, right=361`), `elementFromPoint` hit-tested directly onto `victory-skip` (WCAG 2.5.8 pass, zero occlusion).
- **Live Vercel Verification (`https://kiepie-quad-web.vercel.app/`):** `index.html` MD5 (`df04e533dfc03061e331e316c10eafdf`) and `index.service.worker.js` MD5 (`dce71f8a84758678416d6768a6a00d77`) match `HEAD` bit-for-bit; `COOP=same-origin`, `COEP=require-corp`, `CORP=same-origin`, `X-Content-Type-Options=nosniff`, `Referrer-Policy=strict-origin-when-cross-origin`, and `/web-assets/*` `immutable` caching verified via `curl -sI`.

---

## 2. The 10-Principal-Engineer Deep Audit (+ Lens 11)

### Lens 1: Systems Architect

- **[P1-4] `TouchControls._on_settings_changed()` never updates `_force` (Split-Brain Settings)** — `godot/src/TouchControls.gd:L127-L132, L499-L508, L522-L525`
  - **Root Cause Mechanism:** `_on_settings_changed(section: String, key: String, _val: Variant)` ignores `_val` and calls `_apply_visibility()` and `_sync_toggle_text()` without updating `_force = bool(_val)`. `_force` is only initialized once in `_ready()` (`L75`).
  - **Deterministic Trigger & Failure Mode:** Toggling `Settings -> Controls -> Force Touch` at runtime updates `Settings.data["controls"]["touch_force"]`, but `TouchControls._force` stays stale, leaving the overlay visibility and `BtnTouchToggle` label unchanged until scene reload.
  - **Surgical Fix Specification:** In `_on_settings_changed()`, when `key == "touch_force"`, assign `_force = bool(_val)` before calling `_apply_visibility()` and `_sync_toggle_text()`.

- **[P2-6] Persistent Architectural God Files (`17` tracked first-party files `> 400` eff LOC)** — `godot/src/game/VfxFactory.gd:L1-L1432`, `godot/src/net/TaloBackend.gd:L1-L1170`
  - **Root Cause Mechanism:** `VfxFactory.gd` (`1,191` eff LOC), `TaloBackend.gd` (`976` eff LOC), `build_deathrace.gd` (`949`), `MatchHud.gd` (`748`), `build_pogo_nardus.py` (`702`), and `build_arena.gd` (`700`) bundle unrelated concerns (sprite generation, particle pooling, physics wrecks, transport, adjudication, and scene layout) in single files.
  - **Deterministic Trigger & Failure Mode:** High cognitive load and merge/edit collision surface for both human developers and AI agents.
  - **Surgical Fix Specification:** Split `VfxFactory` into `VfxSprites` + `VfxExplosions` + `VfxCombat`, `TaloBackend` into `TaloSocketTransport` + `TaloLobbyAdjudicator`, and extract shared scene-builder helpers into `LevelKit.gd`.

### Lens 2: Frame-Budget & Performance

- **[P2-2] `VfxFactory.impact()` holds WebGL2 `OmniLight3D` budget slots for `0.70 s` after `0.12 s` fade** — `godot/src/game/VfxFactory.gd:L725-L743`
  - **Root Cause Mechanism:** Unlike `muzzle_flash()` (`L640-643`) and `particle_explosion()` (`L844-847`), `impact()` creates `light` in group `"vfx_light"` and tweens `light_energy` to `0.0` over `0.12 s`, but never frees `light` or removes it from `"vfx_light"` until `holder` frees at `0.70 s`.
  - **Deterministic Trigger & Failure Mode:** During sustained firefights, `OmniLight3D` instances occupy `1/8` of WebGL2's `MAX_IMPACT_LIGHTS = 8` budget for `5.8×` longer than visible, starving explosion flash lights.
  - **Surgical Fix Specification:** Attach `lt.tween_callback` (and a `0.14 s` reduced-motion callback) to `remove_from_group("vfx_light")` and `queue_free()` on `light`.

- **[P2-8] Web Payload Ceiling Proximity (`index.pck` at `88.4%` of `4 MiB` cap)** — `godot/tools/deploy_web.sh:L63-L69`
  - **Root Cause Mechanism:** `index.pck` is `3,707,328` bytes (`3.54 MiB`) against `deploy_web.sh:66`'s `4,194,304` byte (`4 MiB`) abort threshold (`index.wasm` is `35.4 MiB`).
  - **Deterministic Trigger & Failure Mode:** Adding another vehicle GLB or high-res texture will trip `deploy_web.sh` (`DEPLOY ABORTED: pck unexpectedly large`).
  - **Surgical Fix Specification:** Audit GLB texture compression and `Aston_Martin` / `Pogo_Nardus` mesh budgets before adding new assets, and sync expected-size notes in `AGENTS.md` / `deploy_web.sh`.

- **[P3-1] `MatchState._process()` parses ISO-8601 `started_at` at `60–120 Hz` on host** — `godot/src/net/MatchState.gd:L53-L63`
  - **Root Cause Mechanism:** `_process()` calls `_iso_to_unix(str(lobby.get("started_at", "")))` every frame while a timed match is playing.
  - **Deterministic Trigger & Failure Mode:** Unnecessary per-frame string/dictionary allocation on the host during timed matches.
  - **Surgical Fix Specification:** Cache `_started_unix := _iso_to_unix(...)` inside `_refresh_settings_cache()`.

### Lens 3: Mathematical, Physics & Algorithmic

- **[P3-3] `src/repair_and_verify.py` shifts every `MESH` directly, skipping `EMPTY` anchors** — `src/repair_and_verify.py:L43-L58`
  - **Root Cause Mechanism:** `for ob in bike_meshes: ob.location.z += dz` shifts only `MESH` objects, leaving `EMPTY` anchors (`Muzzle_L/R`, `Steer_FL/FR`) unshifted and double-shifting any child mesh parented to another mesh by `2 * dz`.
  - **Deterministic Trigger & Failure Mode:** Any non-zero `dz` ground-datum adjustment misaligns empty-parented muzzles or nested meshes.
  - **Surgical Fix Specification:** Shift only top-level root objects (`ob.parent is None`) in the collection so children and empties move rigidly together.
- *Verified Clean:* `MatchHud.RadarControl` right-handed projection (`right = Vector2(-fwd.y, fwd.x)`), `KiepieBike._integrate_forces` frame-rate-independent damping & aero-drag clamp, `PogoVisual` sub-stepped springs & `atan2` yaw, `LoopZone` stall recovery.

### Lens 4: Concurrency, Async & Determinism

- **[P1-1] Host-handoff `_state_seq` rollover drops all new-host `"state"` broadcasts on guests** — `godot/src/net/TaloBackend.gd:L158-L164, L211-L219, L527-L528, L905-L907, L960-L977`
  - **Root Cause Mechanism:** Host A increments `_state_seq` to `N >= 2` (guest join + handoff broadcast), advancing every guest's `_last_state_seq = N`, while Guest B's own `_state_seq` remains `0`. When Guest B is promoted to Host B and calls `_start_match()`, `_set_settings()`, `_register_kill()`, or `_register_lap()`, `_broadcast_state()` sends `seq = 1`. Every guest hits `if seq <= _last_state_seq: return` (`L969`) and drops the frame.
  - **Deterministic Trigger & Failure Mode:** After any host handoff in `LobbyMenu`, Host B's `start_match` `"state"` broadcast (`seq = 1 <= N`) is silently dropped by every guest, stranding all guests in `LobbyMenu` while Host B enters the arena alone.
  - **Surgical Fix Specification:** Track `_last_state_host := ""` and reset `_last_state_seq = -1` whenever `sender_id != _last_state_host` (and in `_load_state()` when `host_id` changes); additionally, when `str(_lobby.get("host_id", "")) == user_id`, seed `_state_seq = maxi(_state_seq, _last_state_seq)` so a promoted host continues monotonically above prior sequences.

- **[P1-2] `LobbyService._enter_if_current()` wipes newly entered active lobby on late cancel resolution** — `godot/src/net/LobbyService.gd:L37-L43`, `godot/src/net/TaloBackend.gd:L538-L546`
  - **Root Cause Mechanism:** When `gen != _session_gen`, `_enter_if_current()` calls `await Supabase.call_rpc("leave_lobby", {})` and `Supabase.leave_lobby_channel()` with no lobby-ID check.
  - **Deterministic Trigger & Failure Mode:** User starts `join_auto` (gen 0), cancels (`leave()`, gen 1), and immediately creates/joins a new lobby (gen 2). When the stale `join_auto` resolves, `_enter_if_current(0, res)` tears down the active gen-2 `_channel_id` while `Lobby.current_lobby_id` and `Match.lobby` still point to the new room (Split-Brain State).
  - **Surgical Fix Specification:** Pass `{"p_expected_lobby_id": str((res["lobby"] as Dictionary).get("id", ""))}` to `leave_lobby` and only call `leave_lobby_channel()` if `current_lobby_id == ""` or matches the stale ID; in `TaloBackend._leave_lobby()`, if `expected_id > 0` and `_channel_id != expected_id`, call `Talo.channels.leave(expected_id)` directly without touching the active `_channel_id`/`_lobby`/`_roster`.

- **[P1-5] `RaceTracker._on_roster_changed()` defaults missing `"laps"` to `completed_laps` and disarms `3 s` recovery** — `godot/src/game/RaceTracker.gd:L49-L67, L189-L205`, `godot/src/net/TaloBackend.gd:L318-L326`
  - **Root Cause Mechanism:** `TaloBackend._player_row()` omits `"laps": 0`. Before a guest's first host-confirmed lap, any unrelated `"state"` broadcast (kill/join) evaluates `row.get("laps", completed_laps)` to `completed_laps`, enters `elif _lap_pending: _lap_pending = false`, and permanently disarms the `3 s` final-lap recovery timer. On an intervening mid-flight rollback (`auth_laps < completed_laps`), `next_checkpoint` stays `0` instead of `total_checkpoints`.
  - **Deterministic Trigger & Failure Mode:** A guest crossing the final-lap finish line while another peer's kill/join `"state"` arrives before the host's `lap_request` confirmation loses the `3 s` recovery guard if the lap packet is dropped.
  - **Surgical Fix Specification:** Initialize `"laps": 0, "kills": 0` in `TaloBackend._player_row()`, default missing `"laps"` to `0` in `RaceTracker._on_roster_changed()`, and only clear `_lap_pending` when `auth_laps >= completed_laps` (never on an unrelated stale broadcast while a lap is in flight).

### Lens 5: Memory & Resource Lifecycle

- **[P2-1] Pooled `Projectile` / `BananaProjectile` slots freeze invisible after degenerate first call** — `godot/src/game/Projectile.gd:L124-L131, L178-L181`, `godot/src/game/BananaProjectile.gd:L145-L169, L202-L205`
  - **Root Cause Mechanism:** If a pooled slot receives a degenerate zero/NaN direction before `_tracer` is built, `_recycle()` sets `visible = false` and `set_physics_process(false)`. On subsequent valid reuse, `_tracer == null` routes to `_build_tracer()`, which never restores `visible = true` or `set_physics_process(true)` (`BananaProjectile.setup()` also omits `_age = 0.0`).
  - **Deterministic Trigger & Failure Mode:** That pooled slot becomes permanently invisible and non-ticking for the rest of the match.
  - **Surgical Fix Specification:** Explicitly set `visible = true`, `set_physics_process(true)`, and `_age = 0.0` at the top of `_build_tracer()` (and `_age = 0.0` in `BananaProjectile.setup()`).

- **[P2-7] `TaloBackend.reconnect()` / `start()` mints a fresh anonymous alias on manual retry** — `godot/src/net/TaloBackend.gd:L75-L98`
  - **Root Cause Mechanism:** `start()` unconditionally calls `Talo.players.identify("anonymous", Talo.players.generate_identifier())`, unlike `_on_socket_closed()` (`L193-L194`) which reuses `Talo.current_alias.identifier`.
  - **Deterministic Trigger & Failure Mode:** Tapping `BtnRetry` after a cold-boot timeout creates a new player alias instead of reusing the already-identified alias.
  - **Surgical Fix Specification:** Reuse `Talo.current_alias.identifier` in `start()` when `Talo.current_alias != null`.

### Lens 6: Security & Trust-Boundary

- **[P1-3] Unconditional `R` (`reset_bike`) instant spawn teleport exploit in live multiplayer** — `godot/src/KiepieBike.gd:L361-L364`
  - **Root Cause Mechanism:** `KiepieBike._physics_process()` calls `reset_bike()` on `Input.is_action_just_pressed("reset_bike")` (`R`) with no `practice_mode` or `Match.is_playing()` guard.
  - **Deterministic Trigger & Failure Mode:** Pressing `R` during live Battle Royale combat or over a Death Race `HazardPit` immediately teleports the player to `_spawn` via `PhysicsServer3D.body_set_state` with zero cooldown, zero death broadcast, zero attacker kill credit, and zero `2.5 s` respawn penalty.
  - **Surgical Fix Specification:** Gate `reset_bike` in `KiepieBike._physics_process()` to practice/offline mode only (`combat == null or bool(combat.get("practice_mode")) or Match == null or not Match.is_playing()`).
- *Verified Clean:* `TaloBackend` alias-bound `join`/`leave`/`ready_request`/`kill_request`/`lap_request`/`kill`/`hurt`/`bike_state`/`shot`, `ArenaNet` `16.0 m` muzzle & `24/s` shot validation, `.vercelignore` allowlist (`16` runtime files), `vercel.json` COOP/COEP/CORP headers, CI SHA-512 + commit-SHA pin.

### Lens 7: Reliability & Fault Tolerance

- **[P2-3] `MainMenu._ready()` leaves `BtnRetry` hidden after returning from Practice/Settings** — `godot/src/ui/MainMenu.gd:L83-L88`, `godot/src/net/SupabaseClient.gd:L18-L63`, `godot/src/net/TaloBackend.gd:L81-L118`
  - **Root Cause Mechanism:** `MainMenu._ready()` only checks `if Supabase.is_ready:` and otherwise sets `"Connecting to backend…"`, never surfacing `BtnRetry` if an earlier `TaloBackend.start()` already timed out before the scene change.
  - **Deterministic Trigger & Failure Mode:** Returning to `MainMenu` after a cold-boot timeout leaves the user stuck on `"Connecting to backend…"` with `BtnRetry` hidden.
  - **Surgical Fix Specification:** Expose `is_connecting()` and `last_auth_error` on `SupabaseClient`/`TaloBackend`; in `MainMenu._ready()`, if `not Supabase.is_ready` and `not Supabase.is_connecting()`, display the offline status and set `_btn_retry.visible = true`.

- **[P3-5] Minor durability/doc drift** — `godot/tools/patch_web_html.py:L34-L36`, `AGENTS.md`, `godot/src/game/CombatController.gd:L34, L51, L322`, `godot/src/ui/MatchHud.gd:L836`
  - **Root Cause Mechanism:** `patch_web_html.py` lacks `fsync` + `unlink` cleanup on error; `AGENTS.md` still cites `kiepie_splash_seen_v1` (live `index.html` uses `v2`) and `~3.4 MB` (`3.54 MiB` actual); `CombatController._base_power` is redundant; `RadarControl` comment at `MatchHud.gd:836` still describes world-locked X/Z instead of heading-aligned.
  - **Surgical Fix Specification:** Add `fsync` + `except BaseException: unlink` in `patch_web_html.py`, sync `AGENTS.md` constants, and remove redundant `_base_power`/stale comment.

### Lens 8: Type Systems, Schema & Contracts

- **[P2-4] `SettingsMenu` Quality preset selection drops pending debounced `video/fov` writes** — `godot/src/ui/SettingsMenu.gd:L48-L55`
  - **Root Cause Mechanism:** `if str(entry[0]) != "video":` discards all pending `"video"` keys, including `video.fov`, even though `Settings.apply_quality()` only writes `resolution_scale`, `particles`, `shadows`, and `glow`.
  - **Deterministic Trigger & Failure Mode:** Dragging the `FOV` slider and clicking a Quality preset within `350 ms` silently loses the `FOV` change.
  - **Surgical Fix Specification:** Flush every pending key except `video.resolution_scale`, `video.particles`, `video.shadows`, `video.glow`, and `video.quality`.

### Lens 9: Platform, Viewport & Portability

- **[P2-5] `VfxFactory.casing()` ignores `Settings.reduced_motion()` and `_q() <= 0.0`** — `godot/src/game/VfxFactory.gd:L659-L667`, `godot/src/game/SideCannons.gd:L516-L518`
  - **Root Cause Mechanism:** `casing()` spawns spinning `RigidBody3D` brass casings without checking `Settings.reduced_motion()` or `_q() <= 0.0`, and `SideCannons.fire()` spawns brass casings even for Nardus's Banana Cannon.
  - **Deterministic Trigger & Failure Mode:** Reduced-motion users still see spinning 3D physics casings on every shot.
  - **Surgical Fix Specification:** Return early in `VfxFactory.casing()` when `Settings.reduced_motion() or _q() <= 0.0`, and skip brass casings in `SideCannons.fire()` when `bool(_profile["banana"])`.

- **[P3-4] `MatchHud._fps_label` hardcoded at `Vector2(12, 272)` overlaps `AnalogSteer` on `667×375` landscape** — `godot/src/ui/MatchHud.gd:L799-L805`
  - **Root Cause Mechanism:** `_fps_label.position = Vector2(12, 272)` is static and falls inside `AnalogSteer` (`y = 257..361`) on `375 px`-tall landscape mobile viewports.
  - **Surgical Fix Specification:** Position `_fps_label` dynamically inside `_relayout()` (top-center or right of `Radar` on short viewports).

### Lens 10: Cognitive Load & AI Maintainability

- Cross-references **[P2-6]** (`17` tracked God files `> 400` eff LOC) and **[P3-5]** (stale comments/docs). All `41/41` `godot/src/*.gd` files are wired and shipped with `0` dead modules.

### Lens 11: Engagement & Game-Feel Coverage

- **[P3-2] Missing UI click SFX on Arena/Touch buttons & unattenuated distant AOE shake** — `godot/src/ui/MatchHud.gd:L89-L108`, `godot/src/TouchControls.gd:L516-L520`, `godot/src/game/RocketProjectile.gd:L265-L267`, `godot/src/game/MeteorStrike.gd:L272-L274`
  - **Root Cause Mechanism:** `MatchHud` (`ScoreToggle`, `MenuBtn`, `PlayAgainBtn`, `LeaveBtn`) and `TouchControls` (`BtnTouchToggle`) omit `Sfx.play_ui("ui_click")`; `RocketProjectile` (`0.36`) and `MeteorStrike` (`0.68`) trigger full `add_shake` regardless of distance from the local camera/bike.
  - **Surgical Fix Specification:** Add `Sfx.play_ui("ui_click")` to those 5 handlers and attenuate AOE camera shake by distance.

| Practice | State | Evidence |
| :--- | :--- | :--- |
| **Audio feedback (`play`/`play_3d`/`play_ui`)** | Wired (partial on Arena HUD) | `9` `play`/`play_3d` sites + `20` `play_ui` sites in `godot/src/`; missing on `MatchHud` & `BtnTouchToggle` (`P3-2`) |
| **Haptics (`vibrate_handheld`)** | Wired | `3` sites: death (`CombatController.gd:196`), hard landing (`KiepieBike.gd:395`), dodge (`KiepieBike.gd:617`) |
| **Camera shake (`add_shake`) & Hitstop** | Wired | Centralized `FollowCam.add_shake` sink + `3` `KiepieTime.trigger_hitstop` sites (`52` `reduced_motion()` guards) |
| **Reduced motion / High contrast / Forced colors** | Wired | `52` `reduced_motion()` guards in `godot/src/`; `prefers-contrast: more` & `forced-colors: active` in `index.html:81` |
| **Vehicles, Weapons, Pickups, Modes** | Wired | `4` vehicle profiles (`KiepieBike`, `PogoNardus`, `AstonMartin`, `auto`), `3` weapons, `4` pickups, `2` modes |
| **Persistent Progression / Unlocks** | Absent (by design) | Stateless session arcade; only `Settings` (`user://settings.cfg`) persists across reloads |

---

## 3. Existing Test Suite Comparison & Mutation Truth Table

- **Test-to-Code File Ratio:** `26 / 75` (`0.347`; `4,167 / 19,731` eff LOC = `0.211`)
- **Estimated Mutation Kill Score ($M_{\text{kill}}$):** **`72.92%`** (`35/48` mutants killed; `633` assertions across `26` test files, `26` files with negative/boundary checks, `9` mock-touching files, `0` unpaired critical modules).

| Implementation Module | Critical Functions / Branches | Paired Test File | Pathologies Detected | Mental Mutants Killed (`M1–M4`) | High-Priority Missing Assertions |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `TaloBackend.gd` | `_on_socket_message`, `_register_kill`, `_register_lap`, `_handoff_host_before_leave` | `verify_talo_backend.gd`, `verify_audit_regressions.gd` | Happy-path on host-handoff seq rollover | `3/4 (75%)` | Host-handoff `_state_seq` rollover (`P1-1`) |
| `LobbyService.gd` | `_enter_if_current()`, `leave()`, `join_auto()` | `verify_audit_regressions.gd`, `verify_match_rules.gd` | Mock-coupled gen check | `2/4 (50%)` | Stale cancel resolving after new lobby entered (`P1-2`) |
| `MatchState.gd` | `apply_lobby()`, `is_respawning()`, `_on_pg_change()` | `verify_match_rules.gd`, `verify_audit_regressions.gd` | None significant | `4/4 (100%)` | Timed `time_up()` boundary |
| `KiepieBike.gd` + `VehicleHandling.gd` | `_physics_process()`, `_integrate_forces()`, `reset_bike()` | `verify_controls.gd`, `verify_dodge.gd`, `verify_rollover.gd` | Missing live-match `reset_bike` guard | `3/4 (75%)` | Live-match `R` teleport blocked (`P1-3`) |
| `CombatController.gd` | `take_damage()`, `_die()`, `_respawn()` | `verify_combat.gd`, `verify_kill_flow.gd`, `verify_practice.gd` | None significant | `4/4 (100%)` | Shield-block VFX under `reduced_motion` |
| `SideCannons.gd` + `Projectile.gd` + `BananaProjectile.gd` | `fire()`, `_acquire_pooled_proj()`, `setup()`, `_build_tracer()` | `verify_cannons.gd`, `verify_pogo.gd`, `verify_deathrace.gd` | Happy-path pooling | `2/4 (50%)` | Degenerate-first-call pooled slot reuse (`P2-1`) |
| `ArenaNet.gd` + `NetworkedBike.gd` | `_spawn_remote_shot()`, `apply_state()`, `mark_killed()` | `verify_multiplayer.gd`, `verify_audit_regressions.gd` | Mock-state only | `3/4 (75%)` | Out-of-order `n` after `mark_killed` |
| `RaceTracker.gd` + `LoopZone.gd` + `HazardPit.gd` | `_on_roster_changed()`, `_on_finish_line_entered()`, `_physics_process()` | `verify_deathrace.gd` | Missing-`"laps"` key blind spot | `2/4 (50%)` | Missing `"laps"` in roster during `3 s` recovery (`P1-5`) |
| `TouchControls.gd` + `TouchCapture.gd` | `_on_settings_changed()`, `_sync_analog()`, `_sync_drive()` | `verify_touch.gd`, `verify_touch_multitouch.gd`, `test_kiepie_pad.gd` | Missing runtime `Settings` toggle test | `3/4 (75%)` | Runtime `touch_force` `Settings.changed` sync (`P1-4`) |
| `VfxFactory.gd` | `impact()`, `casing()`, `particle_explosion()`, `scorch()` | `verify_vfx.gd`, `verify_audit_regressions.gd` | Light-release timing unasserted | `3/4 (75%)` | `impact()` `0.12 s` light free (`P2-2`), `casing()` RM (`P2-5`) |
| `Settings.gd` + `SettingsMenu.gd` + `MainMenu.gd` | `apply_quality()`, `_ready()`, `_on_auth_status()` | `verify_settings.gd`, `verify_accessibility.gd`, `verify_aston.gd` | Missing `fov` + preset race; `BtnRetry` return | `3/4 (75%)` | `video/fov` preserved on preset (`P2-4`), `BtnRetry` (`P2-3`) |
| `MatchHud.gd` + `Hud.gd` | `_relayout()`, `_on_match_finished()`, `_refresh_banner()` | `verify_accessibility.gd`, `verify_deathrace.gd`, `verify_practice.gd` | `show_fps` overlap untested | `3/4 (75%)` | `FpsLabel` non-overlap on `667×375` (`P3-4`) |

### Why Existing Tests Missed Discovered P1/P2 Defects

- **`P1-1`:** `verify_talo_backend.gd` tests `seq` ordering on a single static host (`"1"`), never simulating a host handoff where Guest B (`_state_seq = 0`) becomes host and emits `seq = 1` to guests with `_last_state_seq >= 2`.
- **`P1-2`:** `verify_audit_regressions.gd` tests `_enter_if_current()` with `current_lobby_id == ""`, never while a second active lobby is already joined.
- **`P1-3`:** `verify_controls.gd` and `verify_dodge.gd` call `reset_bike()` directly in offline scenes; no gate tests pressing `reset_bike` while `Match.is_playing() == true`.
- **`P1-4`:** `verify_touch.gd` sets `touch_force = true` *before* instantiating `TestRide.tscn`, never toggling `Settings.set_value("controls", "touch_force", ...)` after `TouchControls._ready()`.
- **`P1-5`:** `verify_deathrace.gd` tests `_on_roster_changed()` with explicit `"laps"` keys, never with `TaloBackend._player_row()`'s default row (which omits `"laps"`).
- **`P2-1..P2-5`:** Gates never reused a pooled `Projectile` after a degenerate `Vector3.ZERO` call (`P2-1`), never asserted `impact()`'s `OmniLight3D` release at `0.15 s` (`P2-2`), never re-instantiated `MainMenu` after a failed `TaloBackend.start()` (`P2-3`), never combined `video/fov` slider + `Quality` preset within `350 ms` (`P2-4`), and never asserted `0` `RigidBody3D` casings under `reduced_motion = true` (`P2-5`).

### Minimal Viable Test Harness (MVTH) Specifications

1. **`verify_talo_backend.gd` (`P1-1`, `P1-2`):** Stage Guest B with `_last_state_seq = 3`, promote to host, emit `_broadcast_state()`, and assert guests accept `seq = 4` (or reset on host change); in `LobbyService`, start `join_auto` (gen 0), `leave()`, enter active lobby `"L2"`, resolve stale `"L1"`, and assert `_channel_id` remains `"L2"`.
2. **`verify_controls.gd` (`P1-3`):** With `Match.lobby["status"] = "playing"` and `practice_mode = false`, press `reset_bike` and assert bike position does not snap to `_spawn`.
3. **`verify_touch.gd` (`P1-4`):** After `TouchControls._ready()` with `touch_force = false`, call `Settings.set_value("controls", "touch_force", true)` and assert `is_overlay_active() == true` and `BtnTouchToggle.text == "TOUCH: ON"`.
4. **`verify_deathrace.gd` (`P1-5`):** Stage `completed_laps = 1`, `_lap_pending = true`, emit `_on_roster_changed()` with a `_player_row()` lacking `"laps"`, and assert `_lap_pending` stays `true` until confirmed or `3 s` timer fires.
5. **`verify_vfx.gd` & `verify_settings.gd` (`P2-1`, `P2-2`, `P2-4`, `P2-5`):** Reuse pooled `Projectile` after `Vector3.ZERO` and assert `visible == true`; assert `vfx_light` count drops to `0` within `0.20 s` of `VfxFactory.impact()`; assert `VfxFactory.casing()` spawns `0` bodies under `reduced_motion`; queue `video/fov = 75.0` then `apply_quality("low")` and assert `fov == 75.0`.

---

## 4. Surgical Refactoring Blueprints (Zero-Mutation Drafts)

### Refactor R1 (`P1-1`): Host-Epoch-Aware `_state_seq` in `TaloBackend.gd`

- **Target Scope:** `godot/src/net/TaloBackend.gd:L58-L60, L960-L977`
- **Engineering ROI:** Eliminates 100% guest-stranding after host handoff.

**Current Pattern (Audited Code):**
```gdscript
if _is_host() and sender_id == user_id:
	return
if payload is Dictionary:
	var p := payload as Dictionary
	var seq := int(p.get("seq", -1))
	if seq >= 0:
		if seq <= _last_state_seq:
			return
		_last_state_seq = seq
```

**Target Pattern (Surgical Blueprint):**
```gdscript
if _is_host() and sender_id == user_id:
	return
if sender_id != _last_state_host:
	_last_state_host = sender_id
	_last_state_seq = -1
if payload is Dictionary:
	var p := payload as Dictionary
	var seq := int(p.get("seq", -1))
	if seq >= 0:
		if seq <= _last_state_seq:
			return
		_last_state_seq = seq
	if p.has("lobby") and p["lobby"] is Dictionary:
		_lobby = (p["lobby"] as Dictionary).duplicate(true)
	if str(_lobby.get("host_id", "")) == user_id:
		_state_seq = maxi(_state_seq, _last_state_seq)
```

### Refactor R2 (`P1-2`): Expected-Lobby-ID-Scoped Cleanup in `LobbyService.gd` + `TaloBackend.gd`

- **Target Scope:** `godot/src/net/LobbyService.gd:L37-L43`, `godot/src/net/TaloBackend.gd:L538-L546`
- **Engineering ROI:** Prevents stale cancelled joins from tearing down a newly active lobby.

**Current Pattern (Audited Code):**
```gdscript
func _enter_if_current(gen: int, res: Dictionary) -> bool:
	if gen != _session_gen:
		if not res.is_empty() and res.has("lobby"):
			await Supabase.call_rpc("leave_lobby", {})
			Supabase.leave_lobby_channel()
		return false
	return _enter(res)
```

**Target Pattern (Surgical Blueprint):**
```gdscript
func _enter_if_current(gen: int, res: Dictionary) -> bool:
	if gen != _session_gen:
		if not res.is_empty() and res.has("lobby"):
			var stale_id := str((res["lobby"] as Dictionary).get("id", ""))
			await Supabase.call_rpc("leave_lobby", {"p_expected_lobby_id": stale_id})
			if current_lobby_id == "" or current_lobby_id == stale_id:
				Supabase.leave_lobby_channel()
		return false
	return _enter(res)
```

### Refactor R3 (`P1-3`): Practice-Only `reset_bike` Gate in `KiepieBike.gd`

- **Target Scope:** `godot/src/KiepieBike.gd:L361-L364`
- **Engineering ROI:** Closes instant-teleport combat/hazard-pit evasion in live multiplayer.

**Current Pattern (Audited Code):**
```gdscript
	if Input.is_action_just_pressed("reset_bike"):
		reset_bike()
```

**Target Pattern (Surgical Blueprint):**
```gdscript
	if Input.is_action_just_pressed("reset_bike"):
		var combat := get_node_or_null("CombatController")
		var in_live_match := typeof(Match) != TYPE_NIL and Match != null and Match.is_playing() \
				and (combat == null or not bool(combat.get("practice_mode")))
		if not in_live_match:
			reset_bike()
```

### Refactor R4 (`P1-4`): Sync `_force` in `TouchControls._on_settings_changed()`

- **Target Scope:** `godot/src/TouchControls.gd:L127-L132`
- **Engineering ROI:** Eliminates split-brain between `Settings` and `TouchControls`.

**Current Pattern (Audited Code):**
```gdscript
func _on_settings_changed(section: String, key: String, _val: Variant) -> void:
	if section == "controls":
		if key == "touch_force":
			_apply_visibility()
			_sync_toggle_text()
		_relayout()
```

**Target Pattern (Surgical Blueprint):**
```gdscript
func _on_settings_changed(section: String, key: String, val: Variant) -> void:
	if section == "controls":
		if key == "touch_force":
			_force = bool(val)
			_apply_visibility()
			_sync_toggle_text()
		_relayout()
```

### Refactor R5 (`P1-5`): Authoritative `"laps"` Initialization & Recovery Guard in `RaceTracker.gd` + `TaloBackend.gd`

- **Target Scope:** `godot/src/game/RaceTracker.gd:L49-L67`, `godot/src/net/TaloBackend.gd:L318-L326`
- **Engineering ROI:** Guarantees `3 s` guest final-lap recovery cannot be disarmed by unrelated `"state"` broadcasts.

**Current Pattern (Audited Code):**
```gdscript
	if Match.players.has(uid) and Match.players[uid] is Dictionary:
		var auth_laps := int((Match.players[uid] as Dictionary).get("laps", completed_laps))
		if auth_laps != completed_laps:
			...
		elif _lap_pending:
			_lap_pending = false
```

**Target Pattern (Surgical Blueprint):**
```gdscript
	if Match.players.has(uid) and Match.players[uid] is Dictionary:
		var auth_laps := int((Match.players[uid] as Dictionary).get("laps", 0))
		if auth_laps >= completed_laps:
			_lap_pending = false
		if auth_laps != completed_laps and not _lap_pending:
			completed_laps = auth_laps
			var target := maxi(1, int(Match.lap_target()))
			current_lap = mini(completed_laps + 1, target)
			if completed_laps < target:
				race_finished = false
			_sync_hud()
```

### Refactor R6 (`P2-1`, `P2-2`, `P2-5`): Projectile Pool Re-Arm + `VfxFactory` Light/Casing Guards

- **Target Scope:** `godot/src/game/Projectile.gd:L178-L181`, `godot/src/game/BananaProjectile.gd:L160-L169, L202-L205`, `godot/src/game/VfxFactory.gd:L659-L667, L725-L743`
- **Engineering ROI:** Prevents permanent invisible pooled projectiles, frees WebGL2 light slots `5.8×` faster, and honors `reduced_motion()` for casings.

**Target Pattern (Surgical Blueprint):**
```gdscript
# Projectile.gd / BananaProjectile.gd _build_tracer():
visible = true
set_physics_process(true)
_age = 0.0

# VfxFactory.gd impact() light cleanup:
		if Settings.reduced_motion():
			light.light_energy = 1.6
			var rmt := holder.create_tween()
			rmt.tween_interval(0.14)
			rmt.tween_callback(func() -> void:
				if is_instance_valid(light):
					light.remove_from_group("vfx_light")
					light.queue_free())
		else:
			var lt := holder.create_tween()
			lt.tween_property(light, "light_energy", 0.0, 0.12)
			lt.tween_callback(func() -> void:
				if is_instance_valid(light):
					light.remove_from_group("vfx_light")
					light.queue_free())

# VfxFactory.gd casing():
	if parent == null or Settings.reduced_motion() or _q() <= 0.0:
		return
```

---

## 5. Phased Execution Roadmap & Scoped Agent Prompts

1. **Phase 1 — Multiplayer State & Security Hardening (`P1-1..5` + MVTH Regressions)**
   - Land `R1–R5` (`TaloBackend.gd`, `LobbyService.gd`, `KiepieBike.gd`, `TouchControls.gd`, `RaceTracker.gd`) with MVTH regression tests in `verify_talo_backend.gd`, `verify_controls.gd`, `verify_touch.gd`, and `verify_deathrace.gd`.
2. **Phase 2 — Lifecycle, WebGL Budget & UI Polish (`P2-1..5`, `P2-7..8`)**
   - Land `R6` (`Projectile.gd`, `BananaProjectile.gd`, `VfxFactory.gd`, `SideCannons.gd`), `MainMenu.gd` / `SupabaseClient.gd` `BtnRetry` persistence, `SettingsMenu.gd` `video/fov` preset flush, and `TaloBackend.start()` alias reuse.
3. **Phase 3 — Modular De-Vibing & DX Hygiene (`P2-6`, `P3-1..5`)**
   - Split `VfxFactory.gd` and `TaloBackend.gd`, cache `MatchState._started_unix`, position `MatchHud._fps_label` in `_relayout()`, add `ui_click` & distance-attenuated AOE shake, fix `repair_and_verify.py` root-only shift, and sync `AGENTS.md` / `patch_web_html.py`.

### Copy-Paste Surgical Prompts for Coding Agents

> **Prompt [P1-1] (`godot/src/net/TaloBackend.gd`):**
> "Strictly scope edits to `godot/src/net/TaloBackend.gd` and `godot/tools/verify_talo_backend.gd`. Track `_last_state_host: String` alongside `_last_state_seq`, reset `_last_state_seq = -1` when `sender_id != _last_state_host`, and seed `_state_seq = maxi(_state_seq, _last_state_seq)` when promoted to host. Add a host-handoff sequence-rollover regression test in `verify_talo_backend.gd` and run `bash godot/tools/run_gates.sh`."

> **Prompt [P1-2] (`godot/src/net/LobbyService.gd`, `godot/src/net/TaloBackend.gd`):**
> "Strictly scope edits to `godot/src/net/LobbyService.gd`, `godot/src/net/TaloBackend.gd`, and `godot/tools/verify_audit_regressions.gd`. Pass `p_expected_lobby_id` from `LobbyService._enter_if_current()` to `leave_lobby`, and in `TaloBackend._leave_lobby()` leave only `expected_id` without wiping an active newer `_channel_id`. Add a regression test for cancel-then-rejoin in `verify_audit_regressions.gd`."

> **Prompt [P1-3] (`godot/src/KiepieBike.gd`):**
> "Strictly scope edits to `godot/src/KiepieBike.gd` and `godot/tools/verify_controls.gd`. Gate `Input.is_action_just_pressed("reset_bike")` in `KiepieBike._physics_process()` so instant spawn teleport is disabled during live multiplayer (`Match.is_playing()` and not `practice_mode`). Add a regression assertion in `verify_controls.gd`."

> **Prompt [P1-4] (`godot/src/TouchControls.gd`):**
> "Strictly scope edits to `godot/src/TouchControls.gd` and `godot/tools/verify_touch.gd`. Update `_force = bool(val)` inside `TouchControls._on_settings_changed()` when `section == "controls"` and `key == "touch_force"`. Add a runtime `Settings.set_value` regression check in `verify_touch.gd`."

> **Prompt [P1-5] (`godot/src/game/RaceTracker.gd`, `godot/src/net/TaloBackend.gd`):**
> "Strictly scope edits to `godot/src/game/RaceTracker.gd`, `godot/src/net/TaloBackend.gd`, and `godot/tools/verify_deathrace.gd`. Initialize `"laps": 0, "kills": 0` in `TaloBackend._player_row()`, default missing `"laps"` to `0` in `RaceTracker._on_roster_changed()`, and only clear `_lap_pending` when `auth_laps >= completed_laps`. Add a regression test in `verify_deathrace.gd`."

> **Prompt [P2-1..5] (`Projectile.gd`, `BananaProjectile.gd`, `VfxFactory.gd`, `SideCannons.gd`, `MainMenu.gd`, `SettingsMenu.gd`):**
> "Strictly scope edits to `Projectile.gd`, `BananaProjectile.gd`, `VfxFactory.gd`, `SideCannons.gd`, `MainMenu.gd`, `SupabaseClient.gd`, `SettingsMenu.gd`, and their paired `verify_*.gd` gates. Fix pooled `_build_tracer()` visibility/physics/age re-arm, `VfxFactory.impact()` `0.12 s` light release, `VfxFactory.casing()` `reduced_motion()` guard, `MainMenu` `BtnRetry` return state, and `SettingsMenu` `video/fov` preset flush. Run `bash godot/tools/run_gates.sh` to confirm all 29 gates green."
