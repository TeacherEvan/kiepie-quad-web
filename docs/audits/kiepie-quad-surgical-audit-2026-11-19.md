# Surgical Audit Report: Kiepie Bike / Kiepie Quad (`kiepie-quad-web`)

| Audit Metadata | Specification |
| :--- | :--- |
| **Audit Date** | 2026-11-19 |
| **Audited Scope** | First-party source, tooling, Web shell & Blender pipeline (`60` impl/tool files, `25` test/gate files, `14,991` effective LOC; plus `198` lines `index.html` [73 CSS / 99 JS / 26 HTML]; excludes vendored `godot/addons/` 18,488 LOC, git-ignored `web/` 771 LOC, and generated Godot JS runtime 642 LOC). Audited on `HEAD` `609d062ea5ef72deee120a4614cf251a42553c90` with dirty working tree (10 modified, 5 untracked SFX/scene/design files preserved untouched). |
| **Tech Stack & Runtime** | Godot 4.3 (GDScript, WebGL2 `gl_compatibility`, WebAssembly/SharedArrayBuffer COOP/COEP), Talo 0.20.0 (HTTP + WebSocket), Python 3 / Blender 5.3 `bpy`, Vanilla JS Service Worker & HTML5 shell, Bash deploy pipeline, Vercel static hosting. |
| **Pre/Post Audit SHA-256** | `7fec78f2126d6a0d / 7fec78f2126d6a0d (VERIFIED ZERO MUTATION)` (`7fec78f2126d6a0d4ded8e2c31622e9e6569367caf450c79aed8a88135025cbb`) |
| **Deterministic Health Score** | **`43 / 100`** (`D_raw = 185`, `P_test = 9.06`, `M_kill = 39.6%`) |
| **Vibe-Debt Risk Level** | **`HIGH`** (`40 <= S_health <= 64` and `N_P0 = 1`) |
| **Verification Status** | **Addendum A (Live Runtime & Pass 2.5 Verified)** — Isolated 26/26 gate execution, live headless Godot runtime reproductions (8 findings), Node `vm` Service Worker & Chromium CDP Web shell probes, dead-code/unwired sweep, and 11th Lens (Engagement & Game Feel). |
| **SARIF 2.1.0 Telemetry** | [`docs/audits/kiepie-quad-surgical-audit-2026-11-19.sarif`](kiepie-quad-surgical-audit-2026-11-19.sarif) (`192` total results; `95` first-party: `4` error, `63` warning, `28` note) |

---

## 1. Executive Architecture & Vibe-Debt Triage

Since the prior surgical audit on `2026-11-18` (`3700640`, 13,361 eff LOC, 0 P0 / 0 P1, score ≈79/100), the repository merged `kiepie-quad` into `kiepie-quad-web` and added **+1,630 net effective LOC across 107 touched files** spanning five major new surfaces: deterministic vehicle dealing (PRINCESS pogo + banana projectiles), a full dual-analog touch rewrite, rollover immunity & capsized recovery, a Web splash/fullscreen shell, and a `protocol_version` lobby handshake (plus uncommitted `dink`/`scrape` SFX work in the current working tree). While the core touch state machine (`TouchControls` + `TouchCapture`, 4/4 mutants killed) and GLB de-inlining are well-engineered, **multiplayer trust boundaries and lifecycle state transitions regressed sharply**: an unauthenticated `"lobby_update"` relay bypasses host authority completely (`F-01`, P0), WebSocket reconnect permanently bricks sessions because `TaloSocket` clears `_temp_socket_token` after first identify (`F-02`, P1), departed peers are never removed from `Match.players` (`F-04`, P1), and `"kill"` / `"ready_request"` lack strict sender-identity checks (`F-03`, `F-05`, P1). In gameplay and Web runtime, `KiepieBike._integrate_forces()` has an inverted roll-damping retention factor (`keep = lerpf(0.90, 0.997, lean)` retains 99.7% roll velocity instead of damping it, `F-10`), `dust_ring`/`roost` pass world coordinates as local children of `KiepieBike` (`F-09`), `CombatController.reset_state()` leaves collision disabled after death (`F-08`), the Web fullscreen toggle is permanently dead after one exit (`F-12`), and the Service Worker throws on cross-origin/opaque/204 responses (`F-07`). The 26-gate suite has 369 static assertions but an estimated mutation kill rate of only **39.6% (19/48)** due to mock-mirror drift (`MockBackend` vs `TaloBackend`), result-only assertions, and 10+ completely unpaired critical modules (`Projectile`, `BananaProjectile`, `Pickup`, `KiepieTime`, menus, Blender scripts, and Web SW/shell).

### Severity Tier Breakdown

| Severity Tier | Count | Deduction Weight | Primary Failure Domains |
| :--- | :--- | :--- | :--- |
| **P0 — Critical (Crash / Data Loss / Security / Leak)** | **1** | `-18 pts ea` (`-18`) | `TaloBackend.gd` / `MatchState.gd` unauthenticated `"lobby_update"` host-authority bypass (`F-01`) |
| **P1 — High (Frame-Budget / Race / Logic Bug)** | **13** | `-8 pts ea` (`-104`) | `TaloBackend.gd` reconnect brick, `"kill"` spoof, departed-peer ghost/deadlock, inverted `"ready_request"` guard, single-page channel scan (`F-02`–`F-06`); `patch_web_sw.py` / `index.service.worker.js` COEP/204 crash & cold-load timeout (`F-07`); `CombatController.gd` post-death collision loss (`F-08`); `KiepieBike.gd` world-as-local VFX & inverted rollover damping (`F-09`, `F-10`); `SideCannons.gd` async post-death firing (`F-11`); `index.html` / `export_presets.cfg` dead fullscreen re-entry (`F-12`); `TouchControls.gd` narrow-portrait pad overlap (`F-13`); `SettingsMenu.gd` `_exit_tree` signal/timer race (`F-14`) |
| **P2 — Medium (God File / Split-Brain State / Debt)** | **19** | `-3 pts ea` (`-57`) | `inject_talo_key.py` non-atomic write/JWT regex (`F-15`); `deploy_web.sh` swallowed commit errors & missing `curl` timeout (`F-16`); `Projectile`/`BananaProjectile` vertical `looking_at` & per-shot GPU allocs (`F-17`, `F-24`); `generate_sfx.py` inverted LP filter & click tails (`F-18`); `src/build_quad.py` / `build_pogo_princess.py` / `qb_wheels.py` / `qb_body.py` geometry/pivot defects (`F-19`, `F-30`, `F-31`); `TaloBackend` hand-off/channel-resurrection (`F-20`); `ArenaNet` & `NetworkedBike` shot/respawn/lerp/exit guards (`F-21`, `F-22`); `Settings` bus clobber & `MatchState` double-emit (`F-23`); `VfxFactory` uncapped muzzle lights & scaled `RigidBody3D` (`F-25`); `KiepieBike` stationary scrape SFX (`F-26`); UI async/tween/splash/idle-alloc/draw defects (`F-27`–`F-29`, `F-32`, `F-33`) |
| **P3 — Low (Magic Constants / DX / Portability)** | **6** | `-1 pt ea` (`-6`) | `MatchState`/`KiepieTime`/`MockBackend` contract nits (`F-34`); `Pickup` bob phase snap (`F-35`); `Sfx` pitch clamp (`F-36`); `build_testride.gd` non-persistent group & cone bloat (`F-37`); mobile bottom-margin waste (`F-38`); God files, CC hotspots, silent catches, and repo media/doc bloat (`F-39`) |

**Health Score Formula Verification:**
- $D_{\text{raw}} = (18 \times 1) + (8 \times 13) + (3 \times 19) + (1 \times 6) = 185$
- $\text{Scale} = \sqrt{1000 / \max(500, 14991)} = 0.258276 \implies D_{\text{scaled}} = 47.78$
- $P_{\text{test}} = 15 \times (1 - 39.5833 / 100) = 9.06$
- $S_{\text{health}} = \max(0, \text{round}(100 - 47.78 - 9.06)) = \max(0, \text{round}(43.16)) = \mathbf{43 / 100}$ *(identical `43` if 198-line `index.html` is added to `LOC_effective = 15,189`)*

### High-Risk File Telemetry Hotspots

| File Path | Effective LOC | Max CC / Branch Density / Max Fn LOC | Silent Catches | Primary Vibe-Debt Signature |
| :--- | :--- | :--- | :--- | :--- |
| `src/qb_core.py` | 487 | CC 18 / nest 5 | 7 | God utility module + 7 bare/silent exception handlers |
| `godot/src/game/VfxFactory.gd` | 806 | CC 19 / maxFn 104 | 0 | God VFX factory; uncapped muzzle lights + scaled `RigidBody3D` + per-shot casing allocs |
| `godot/src/net/TaloBackend.gd` | 715 | CC 48 / maxFn 120 | 0 | God socket/HTTP router (`_on_socket_message` CC 48); auth gaps, reconnect brick, single-page scan |
| `godot/tools/build_arena.gd` | 671 | CC 5 / maxFn 120 | 0 | Monolithic procedural scene generator |
| `godot/src/ui/MatchHud.gd` | 552 | CC 47 / maxFn 120 | 0 | God HUD (`_relayout` CC 47, `_ready` CC 20); uncancelled tweens & unchecked timers |
| `godot/src/ui/MobileTextInput.gd` | 371 | CC 14 | 3 | Desktop 60–120 Hz `JavaScriptBridge.eval()` polling + 3 silent catches |
| `src/qb_body.py` | 497 | CC 15 / maxFn 148 | 0 | God geometry builder; left-fender inboard droop |
| `godot/tools/build_testride.gd` | 462 | CC 3 / maxFn 120 | 0 | Monolithic practice builder; 24x duplicated cone sub-resources |
| `godot/src/TouchControls.gd` | 437 | CC 25 / maxFn 62 | 0 | Portrait pad overlap (`dodge_size > 1.0`) + 8 idle Array allocs/frame |
| `godot/src/KiepieBike.gd` | 381 | CC 50 / bd 0.129 / maxFn 120 | 0 | God physics tick (`_physics_process` CC 50); inverted rollover damping + world-as-local VFX |

---

## 2. The 10-Principal-Engineer Deep Audit

### Lens 1: Systems Architect

- **[P1-F-02] WebSocket Reconnect Always Fails & Permanently Bricks Session** — `godot/src/net/TaloBackend.gd:L55-L88, L137-L159` *(xref `godot/addons/talo/talo_socket.gd:L55-L62, L96-L100`, also Lens 4, 7)*
  - **Root Cause Mechanism:** `TaloSocket._on_message_received()` clears `_temp_socket_token = ""` upon initial `"v1.players.identify.success"`. After a disconnect (`_reset_socket()` sets `_identified = false`), `TaloBackend._on_socket_closed()` calls `await Talo.socket.open_connection()` (`L147`) without re-calling `Talo.players.identify(...)` to mint a fresh `socketToken`. On `"v1.connected"`, `TaloSocket` sees an empty `_temp_socket_token` and never sends `v1.players.identify`. After 2,500 ms, `TaloBackend` sets `is_ready = false` (`L157`) without emitting `auth_status(false, ...)`, leaving `Supabase.is_ready == true` (split-brain) and permanently disabling further reconnects (`L139`) and RPCs (`L164`). Additionally, `_starting` (`L58`) is never reset to `false` on success (`L85-L88`).
  - **Deterministic Trigger & Failure Mode:** Any transient WebSocket drop (mobile tab switch, Wi-Fi handoff) guarantees 100% reconnect failure and permanently bricks multiplayer until full page reload.
  - **Surgical Fix Specification:** In `_on_socket_closed()`, before `open_connection()`, call `if Talo.current_alias != null: await Talo.players.identify("anonymous", Talo.current_alias.identifier)`. On timeout, schedule another backoff retry (or emit `auth_status(false, ...)` and reset `_starting = false`). Reset `_starting = false` on success at `L85`.

- **[P1-F-04] Departed Players Are Never Removed From `Match.players` (Ghost Bikes & Ready Deadlock)** — `godot/src/net/TaloBackend.gd:L543-L548, L764-L773`, `godot/src/net/MatchState.gd:L77-L85, L270-L291` *(also Lens 4, 7)*
  - **Root Cause Mechanism:** When a peer leaves (`"leave"` or updated `"state"` roster), `TaloBackend._emit_roster()` only emits `UPDATE` events for remaining members and never emits `DELETE`. `MatchState._on_pg_change()` also explicitly drops `DELETE` (`if kind == "DELETE": return` at `L273`). `MatchState.set_lobby()` (`L77-L85`) fails to clear prior `players` when switching lobbies.
  - **Deterministic Trigger & Failure Mode:** A player joins a lobby and leaves. Their row remains in `Match.players` permanently on all peers: `Match.all_ready()` deadlocks if they left unready, `ArenaNet._sync_roster()` (`ArenaNet.gd:L258-L263`) never frees their `NetworkedBike` (leaving a permanent solid ghost collider), and the scoreboard retains departed players.
  - **Surgical Fix Specification:** Emit a full roster replacement event (`{"table": "lobby_players", "type": "SYNC", "records": _roster.duplicate(true)}`) or emit `DELETE` for erased `uid`s, and handle `SYNC`/`DELETE` in `MatchState._on_pg_change()`. Clear `players.clear()` in `MatchState.set_lobby()` when switching lobby IDs.

- **[P1-F-08] `CombatController.reset_state()` Leaves Collision Disabled After Death** — `godot/src/game/CombatController.gd:L230-L242` *(xref `L189-L190, L217-L218`, also Lens 7)*
  - **Root Cause Mechanism:** `_die()` sets `bike.collision_layer = 0` and `bike.collision_mask = 0` (`L189-L190`); `_respawn()` restores both to `1` (`L217-L218`), but `reset_state()` (called by `Hud._on_restart()` on `R` / `RestartBtn`) restores `visible`, `physics_process`, and `health` without restoring `collision_layer`/`collision_mask` or clearing active buff timers (`_rapid_until`, `_overdrive_until`, `_shield_until`) and `bike.overdrive_active` / `bike.engine_power`.
  - **Deterministic Trigger & Failure Mode:** Die in TestRide (e.g. FuelDrum blast) and press `R` / `RestartBtn` before the respawn timer expires -> bike reappears alive with `collision_mask == 0` and falls straight through the ground indefinitely while unable to collide with pickups or projectiles (`collision_layer == 0`).
  - **Surgical Fix Specification:** In `reset_state()`, restore `bike.collision_layer = 1`, `bike.collision_mask = 1`, zero `_rapid_until`/`_overdrive_until`/`_shield_until`, and reset `bike.overdrive_active = false` and `bike.engine_power = _base_power`.

- **[P1-F-11] Async `await Match.issue_shot()` Allows Dead or Post-Match Firing** — `godot/src/game/SideCannons.gd:L132-L163` *(also Lens 7)*
  - **Root Cause Mechanism:** `fire()` yields at `await Match.issue_shot()` (`L132`). On resume, `L143` checks `is_instance_valid(...)` but never checks `is_inside_tree()`, shooter liveness (`owner_node.visible` / `CombatController.alive`), or `Match.is_playing()`. With `0.09s` rapid cooldown and >90 ms RTT, multiple coroutines overlap.
  - **Deterministic Trigger & Failure Mode:** Fire in Arena immediately before dying or match end under >=50–100 ms RTT -> resumed coroutine spawns live projectiles from the invisible dead bike and broadcasts `"shot"`.
  - **Surgical Fix Specification:** Immediately after `await Match.issue_shot()`, abort if `not is_inside_tree()`, `not is_instance_valid(owner_node)`, `not owner_node.visible`, `combat != null and not combat.alive`, or `(not practice_mode and not Match.is_playing())`.

- **[P2-F-19] Ground-Seating Shifts Child MESHes Only, Desyncing `Steer_FL/FR` & `Muzzle_L/R` EMPTY Pivots** — `src/build_quad.py:L122-L129`, `src/repair_and_verify.py:L52-L57` *(also Lens 8)*
  - **Root Cause Mechanism:** After parenting meshes under `Bike_Root` and `Steer_FL`/`Steer_FR`, both scripts seat the model with `if ob.type == 'MESH': ob.location.z += dz`. EMPTYs (`Bike_Root`, `Steer_FL/FR`, `Muzzle_L/R`) are skipped, offsetting wheel meshes from their steering pivots and `Cannon_Bore_*` from `Muzzle_*` while mutating parent-local Z instead of world Z.
  - **Deterministic Trigger & Failure Mode:** Any non-zero `dz` during Blender rebuild shifts front wheels off their steering axis and drifts `Muzzle_L/R` relative to barrels.
  - **Surgical Fix Specification:** Translate only top-level root objects (`ob.parent is None`, i.e., `root.location.z += dz`) so the entire hierarchy moves rigidly in world Z.

### Lens 2: Frame-Budget & Performance

- **[P2-F-24] Uncached Per-Shot GPU Mesh, Material & Texture Allocations** — `godot/src/game/BananaProjectile.gd:L91-L105, L153-L185`, `godot/src/game/VfxFactory.gd:L534-L550` *(also Lens 5)*
  - **Root Cause Mechanism:** `BananaProjectile._add_tip()` and `_build_tracer()` allocate 3 `SphereMesh`, 3 `StandardMaterial3D`, 1 `Gradient`, and 1 `GradientTexture1D` per banana (unlike `Projectile.gd`'s static caches). `VfxFactory.casing()` allocates fresh `CylinderShape3D`, `CylinderMesh`, and `StandardMaterial3D` per shot.
  - **Deterministic Trigger & Failure Mode:** Rapid-fire PRINCESS (~11 bananas/s) allocates 33 meshes, 33 materials, and 11 GPU textures per second, causing WebGL2 buffer/texture churn and GC frame spikes.
  - **Surgical Fix Specification:** Cache tip mesh, trail puff mesh, and trail gradient/texture in `static var`s in `BananaProjectile.gd`; cache casing shape/mesh/material in `static var`s in `VfxFactory.gd`.

- **[P2-F-25] Uncapped Muzzle `OmniLight3D`s Held for 0.9 s + Scaled `RigidBody3D` Parent in `explosion()`** — `godot/src/game/VfxFactory.gd:L498-L518, L684, L743-L760` *(also Lens 3)*
  - **Root Cause Mechanism:** (a) `muzzle_flash()` spawns an `OmniLight3D` per barrel without `Settings.quality_multiplier()` or `MAX_IMPACT_LIGHTS` gating, and keeps it alive for the full `0.9s` smoke timer after fading at `0.14s` (~20 concurrent lights during rapid fire, exceeding WebGL2 `gl_compatibility`'s 8-light-per-object limit). (b) `explosion()` sets `holder.scale = Vector3.ONE * scale` (`1.2`/`1.3`) and parents `RigidBody3D` debris under `holder`.
  - **Deterministic Trigger & Failure Mode:** Rapid fire on WebGL2 causes lighting pop/dropouts; any bike/drum explosion spawns `RigidBody3D` chunks under a non-unit scaled parent.
  - **Surgical Fix Specification:** Gate muzzle lights on `quality_multiplier() >= 0.75` and the `vfx_light` cap, and `queue_free()` the `OmniLight3D` when its `0.14s` tween finishes. Parent explosion `RigidBody3D` chunks directly to unscaled `parent` instead of scaled `holder`.

- **[P2-F-28] Splash Video Pre-Fetched Before `seen()` / `reduced-motion` Check, `keydown` Leak & Unquoted `aria-label`** — `godot/export_presets.cfg:L23`, `index.html:L80` *(also Lens 5, 9)*
  - **Root Cause Mechanism:** `boot()` injects `<video src=web-assets/kiepie-quad-splash.mp4 preload=auto autoplay>` into `document.body` *before* checking `if (rm || seen())`; `document.addEventListener('keydown', ..., true)` is never removed on dismissal or skip; `aria-label=Skip intro` is unquoted, parsing as `aria-label="Skip"` + bogus `intro` attribute.
  - **Deterministic Trigger & Failure Mode:** Every returning visitor and `prefers-reduced-motion` user wastes up to 1.9 MB fetching the splash MP4; the capture-phase `keydown` listener leaks for the session; screen readers announce `"Skip"`.
  - **Surgical Fix Specification:** Return early on `if (rm || seen()) return;` before creating any DOM; attach a named `keydown` handler only when showing splash and remove it in `drop()`; quote `aria-label="Skip intro"`.

- **[P2-F-29] Per-Frame Idle Array Allocations in `TouchControls` & Desktop Web `JavaScriptBridge.eval()` Polling** — `godot/src/TouchControls.gd:L247-L249, L370-L385`, `godot/src/ui/MobileTextInput.gd:L53-L75`
  - **Root Cause Mechanism:** `TouchControls._process()` calls `_sync_analog()` and `_sync_drive()` every frame even when idle; `_update_drive_pad()` allocates 8 temporary Arrays per frame. `MobileTextInput._ready()` sets `_web_active = true` even when `_mobile_like == false`, calling `JavaScriptBridge.eval("...poll(...)")` every frame on desktop Web.
  - **Deterministic Trigger & Failure Mode:** 480–960 idle Array allocations/sec during gameplay and continuous WASM->JS `eval()` overhead on desktop Web menus at 60–120 Hz.
  - **Surgical Fix Specification:** Short-circuit `_sync_analog()`/`_sync_drive()` when active pointer maps are empty and latched states are idle, and unroll `_update_drive_pad()` comparisons. In `MobileTextInput._ready()`, only enable `_web_active` / `set_process(true)` when `_mobile_like` is `true`.

- **[P3-F-37] Missing `persistent = true` on TestRide Bike Group & 24x Duplicated Cone Resources** — `godot/tools/build_testride.gd:L159, L353-L385` *(also Lens 8)*
  - **Root Cause Mechanism:** `L159` calls `bike.add_to_group("bike")` without `, true`, so the group is dropped on `PackedScene.pack()`. `_add_cone_ring()` calls `_add_cones(root, [pos])` 24 times instead of batching, creating 72 sub-resources instead of 3.
  - **Deterministic Trigger & Failure Mode:** Rebuilding `TestRide.tscn` omits the `"bike"` group from the packed scene and bloats scene serialization/load with 24x duplicate cone meshes/materials.
  - **Surgical Fix Specification:** Change `L159` to `bike.add_to_group("bike", true)` and pass all 24 positions to `_add_cones()` in one call.

### Lens 3: Mathematical, Physics & Algorithmic

- **[P1-F-09] World-Space VFX Coordinates Applied as Local Child Positions on `KiepieBike`** — `godot/src/KiepieBike.gd:L282-L299` *(xref `godot/src/game/VfxFactory.gd:L791-L813`)*
  - **Root Cause Mechanism:** `_physics_process()` computes world-space `rear` (`L283`) and `at` (`L296`) from `global_position`, then passes `self` as `parent` to `VfxFactory.dust_ring(self, ...)` and `VfxFactory.roost(self, ...)`, which assign `pos` to local `node.position` as children of `parent`.
  - **Deterministic Trigger & Failure Mode:** Drive away from `(0, 0, 0)` and land (`vy < -3.5`) or exceed `42 km/h` -> dust rings and rooster tails spawn at `bike.global_transform * world_pos` (double-translated & rotated tens of meters away / floating), and dust rings move rigidly with the bike.
  - **Surgical Fix Specification:** Pass `get_tree().current_scene as Node3D` (fallback `get_parent() as Node3D`) instead of `self` to `VfxFactory.dust_ring()` and `VfxFactory.roost()`.

- **[P1-F-10] Inverted Roll/Pitch Damping Retention Factor (`keep`) & Unclamped Righting `effort` Overshoot** — `godot/src/KiepieBike.gd:L486-L506`
  - **Root Cause Mechanism:** (a) `L487` sets `var keep := lerpf(0.90, 0.997, lean)` and computes `yaw + trans * pow(keep, dt_scale)`. The comment (`L472`) intends 90%->99.7% *damping* (`keep = 0.10 -> 0.003`), but as written `keep -> 0.997` at `lean = 1.0`, leaving 83.5%/s of roll momentum undamped when tipped. (b) `L503` multiplies `dt_scale` outside `minf(..., 0.14)` without clamping `effort <= tilt`; at `dt_scale = 4.0`, `effort = 0.56 rad` overshoots vertical for `tilt < 0.56 rad`.
  - **Deterministic Trigger & Failure Mode:** Oblique ramp/wall hit with high roll velocity or a physics frame stall -> roll momentum fights the righting spring and high `dt_scale` overshoots upright, oscillating.
  - **Surgical Fix Specification:** Invert retention to `lerpf(0.10, 0.003, lean)` (re-verified against `verify_rollover.gd`), and clamp `var effort := minf(minf(tilt * (0.10 + lean * 1.5), 0.14) * dt_scale, tilt)`.

- **[P2-F-17] Collinear `Basis.looking_at(velocity.normalized(), Vector3.UP)` Failure on Near-Vertical Shots** — `godot/src/game/Projectile.gd:L144`, `godot/src/game/BananaProjectile.gd:L137`
  - **Root Cause Mechanism:** Both scripts call `Basis.looking_at(velocity.normalized(), Vector3.UP)` with no alternate up-vector guard (unlike `VfxFactory._plane_basis()` at `VfxFactory.gd:L405-L412`).
  - **Deterministic Trigger & Failure Mode:** Fire while pitched near vertical off a steep ramp or mid-cartwheel dodge -> Godot `look_at()` collinearity error and degenerate tracer basis.
  - **Surgical Fix Specification:** Guard with `var up := Vector3.FORWARD if absf(dir.dot(Vector3.UP)) > 0.98 else Vector3.UP; _tracer.basis = Basis.looking_at(dir, up)`.

- **[P2-F-22] Frame-Rate-Dependent Linear `lerp` in `NetworkedBike._process()`** — `godot/src/game/NetworkedBike.gd:L146-L153`
  - **Root Cause Mechanism:** `clampf(delta * 14.0, 0.0, 1.0)` varies convergence rate across 60 vs 144 Hz displays and clamps to `1.0` (hard snap) whenever `delta >= 71 ms`.
  - **Deterministic Trigger & Failure Mode:** High-refresh monitors or >71 ms WebGL hitches produce inconsistent interpolation and position snaps on remote player proxies.
  - **Surgical Fix Specification:** Replace with frame-rate-independent exponential smoothing: `var t := 1.0 - exp(-14.0 * minf(delta, 0.05))`.

- **[P3-F-35] Pickup Bob Animation Phase Snap Every `TAU` Seconds** — `godot/src/game/Pickup.gd:L121-L124`
  - **Root Cause Mechanism:** `_t = fmod(_t + delta, TAU)` combined with non-integer frequency `sin(_t * 2.2)` jumps discontinuously from `+0.951` to `0.0` every `6.283 s`.
  - **Deterministic Trigger & Failure Mode:** Watch any idle Arena pickup for 6.3 s -> visible vertical snap.
  - **Surgical Fix Specification:** Use integer multiplier `sin(_t * 2.0)` or wrap `_t` at `TAU * 5.0`.

### Lens 4: Concurrency, Async & Determinism

- **[P1-F-06] Single-Page Channel Scan (`get_channels(0)`) Drops Lobbies Beyond Page 0** — `godot/src/net/TaloBackend.gd:L327, L358` *(also Lens 7)*
  - **Root Cause Mechanism:** `_join_auto()` and `_join_by_code()` call `Talo.channels.get_channels(0)` once and ignore `res[2]` (`isLastPage`).
  - **Deterministic Trigger & Failure Mode:** Once Talo's channel list exceeds one page (active + stale rooms), lobbies on page 1+ cannot be found by code (`join_by_code` returns `{}`) and are invisible to `join_auto`.
  - **Surgical Fix Specification:** Add `_fetch_all_channels(max_pages := 10)` looping `page = 0..max_pages-1` while `res is Array and res.size() >= 3 and not bool(res[2])` (with early exit in `_join_by_code` on code match).

- **[P2-F-20] Host Hand-Off Broadcasts `"state"` Before HTTP Ownership Transfer & `_write_props` Can Resurrect `_channel`** — `godot/src/net/TaloBackend.gd:L451-L462, L525-L536` *(also Lens 7)*
  - **Root Cause Mechanism:** `_handoff_host_before_leave()` broadcasts `"state"` naming `next_host` (`L451`) *before* `PUT /<id>` transfers `ownerAliasId` (`L453-L456`). If the PUT fails, `next_host` gets HTTP 403 on every `_apply_props()` while Talo deletes the `autoCleanup=true` channel when the old owner leaves. Separately, `_write_props()` (`L527-L534`) does not check if `_channel_id` changed across `await`, allowing a stale PUT to overwrite `_channel` after `leave_lobby_channel()`. `_kill_cooldowns`/`_kill_window`/`_used_tokens` are also not cleared on leave, and `_host_lost_emitted` is not reset on join/create.
  - **Deterministic Trigger & Failure Mode:** Failed host transfer leaves an unrecoverable 403 lobby; leaving and rejoining a lobby during an in-flight PUT corrupts `_channel`.
  - **Surgical Fix Specification:** Broadcast `"state"` in `_handoff_host_before_leave()` *only after* PUT returns 200; capture `var cid := _channel_id` before `await` in `_write_props()` and abort if `cid != _channel_id`; clear rate/token tables in `leave_lobby_channel()` and reset `_host_lost_emitted = false` on join/create.

- **[P2-F-23] `Settings._ensure_audio_buses()` Bus-Index Clobber & `MatchState.register_kill()` Double-Emit** — `godot/src/core/Settings.gd:L272-L285, L369-L374`, `godot/src/net/MatchState.gd:L230-L241` *(also Lens 5, 8)*
  - **Root Cause Mechanism:** (a) `Settings._ensure_audio_buses()` calls `AudioServer.add_bus()` then `set_bus_name(i, wanted[i])` using loop index `i` instead of `AudioServer.bus_count - 1`, and `_apply()` hardcodes indices `0..3` instead of `AudioServer.get_bus_index()`. (b) `MatchState.register_kill()` (`L230-L241`) unconditionally emits `score_updated` and `match_finished` even when `TaloBackend._register_kill()` already emitted them via `_emit_roster()`/`_emit_state()`.
  - **Deterministic Trigger & Failure Mode:** Non-default bus layouts get overwritten; host receives duplicate `score_updated` and `match_finished` signals on every kill/win.
  - **Surgical Fix Specification:** Use `var idx := AudioServer.bus_count - 1` and `AudioServer.get_bus_index()` in `Settings.gd`; guard `MatchState.register_kill()` with `old_score != score` and `not was_finished`.

### Lens 5: Memory & Resource Lifecycle

- **[P1-F-14] `SettingsMenu._exit_tree()` Flushes Writes While Still Connected to `Settings.changed`** — `godot/src/ui/SettingsMenu.gd:L95-L99, L225-L234` *(also Lens 7)*
  - **Root Cause Mechanism:** `_exit_tree()` calls `_flush_writes()` -> `Settings.set_value()` -> emits `Settings.changed` -> synchronously invokes `_on_setting_changed()` because `Settings.changed` is never disconnected in `_exit_tree()`, calling `get_tree().create_timer(0.15)` on an exiting node.
  - **Deterministic Trigger & Failure Mode:** Drag any slider in Settings and press Back/`Esc` within 350 ms -> `_on_setting_changed()` runs during teardown, risking a null `get_tree()` error or post-exit timer callback.
  - **Surgical Fix Specification:** Disconnect `Settings.changed` in `_exit_tree()` *before* `_flush_writes()`, and guard `if not is_inside_tree() or get_tree() == null: return` in `_on_setting_changed()`.

- **[P2-F-27] Unchecked `SceneTreeTimer` / `await` Resumptions After Scene Exit** — `godot/src/ui/MatchHud.gd:L185-L188`, `godot/src/Hud.gd:L128-L131`, `godot/src/ui/LobbyMenu.gd:L66-L74, L251-L255, L327-L330` *(also Lens 7)*
  - **Root Cause Mechanism:** `MatchHud`/`Hud` viewport-resize timer lambdas lack `is_instance_valid(self) and is_inside_tree()` guards (`MatchHud._relayout()` dereferences `get_viewport()` unchecked at `L192`). `LobbyMenu._ready()` and `_on_start()` resume after `await Lobby.*`/`Match.start_match()` without `is_inside_tree()` checks.
  - **Deterministic Trigger & Failure Mode:** Viewport resize within 100 ms of scene transition or pressing Leave/`Esc` during an in-flight lobby RPC causes null-viewport or freed-node errors.
  - **Surgical Fix Specification:** Guard `if not is_instance_valid(self) or not is_inside_tree(): return` after every `await` and in every timer callback, plus `if get_viewport() == null: return` in `MatchHud._relayout()`.

- **[P2-F-30] `build_pogo_princess.py` Smooth-Shading Selection Bug, Asymmetric Left Arm, Invalid `export_yup="Y"` & `bmesh` Leak** — `src/build_pogo_princess.py:L237-L242, L307-L310, L414-L420, L436-L440` *(also Lens 8)*
  - **Root Cause Mechanism:** `L307-L310` sets `active = ob` without selecting `ob`, so `bpy.ops.object.shade_smooth()` only shades `PrincessDecal` (leaving `Belly`/`Head`/`Torso` flat-shaded). `L238-L241` uses `math.radians(71)` instead of `math.radians(sgn * 71)`, tilting the left arm downward. `L415` passes `export_yup="Y"` (throws `TypeError`, caught by fallback). `L436-L437` `continue`s before `bm.free()`.
  - **Deterministic Trigger & Failure Mode:** Rebuilding `Pogo_Princess.glb` produces a faceted mesh with an asymmetric left arm and leaks a `BMesh`.
  - **Surgical Fix Specification:** Select each object before `shade_smooth()` (or set `p.use_smooth = True`), use `math.radians(sgn * 71)` for arm Y-rotation, pass `export_yup=True`, and skip `PrincessDecal` before `bmesh.new()`.

### Lens 6: Security & Trust-Boundary

- **[P0-F-01] Unauthenticated `"lobby_update"` Broadcast Bypasses Host Authority** — `godot/src/net/TaloBackend.gd:L825-L826`, `godot/src/net/MatchState.gd:L299-L301` *(also Lens 8)*
  - **Root Cause Mechanism:** `TaloBackend._on_socket_message()` validates `sender_id == host_id` for `"state"` (`L723`), but relays `"lobby_update"` unconditionally with zero `sender_id` check (`L825-L826`). `MatchState._on_broadcast()` immediately passes `p["lobby"]` to `apply_lobby()` (`L299-L301`).
  - **Deterministic Trigger & Failure Mode:** Any guest in a Talo channel sends `{"k":"lobby_update","p":{"lobby":{"status":"finished","winner_id":"<attacker>","host_id":"<attacker>"}}}`. Every peer immediately terminates the match with the attacker as winner, starts matches without the host, or overwrites match `settings`.
  - **Surgical Fix Specification:** Either delete `"lobby_update"` handling completely (authoritative updates already arrive via host-verified `"state"` -> `postgres_change`) or gate `TaloBackend.gd:L825` with `if sender_id == "" or sender_id != str(_lobby.get("host_id", "")): return`, and lock it with a regression test in `verify_audit_regressions.gd`.

- **[P1-F-03] Unauthenticated `"kill"` Broadcast Spoofing (Kill-Cam Hijack, Proxy Hiding & Forced Host Scoring)** — `godot/src/net/TaloBackend.gd:L804-L810`, `godot/src/game/ArenaNet.gd:L115-L137` *(also Lens 8)*
  - **Root Cause Mechanism:** `TaloBackend` relays `"kill"` without checking that `sender_id` matches `payload["victim"]` (unlike `"join"`, `"leave"`, `"bike_state"`, `"shot"`, and `"kill_request"`).
  - **Deterministic Trigger & Failure Mode:** Any peer `M` broadcasts `{"k":"kill","p":{"killer":"<host>","victim":"<V>","token":"forged-1"}}`. Victim `V` loses streak and has its camera hijacked into kill-cam while alive (`ArenaNet.gd:L130-L132`); all peers hide `V` and disable `V`'s collision (`L133-L134`); and the honest host calls `Match.register_kill(V, token)` (`L123`), awarding itself a forged kill and potentially ending the match.
  - **Surgical Fix Specification:** In `TaloBackend.gd:L804-L810`, enforce `var victim := str(p.get("victim", "")); if victim == "" or sender_id == "" or victim != sender_id: return` before emitting `broadcast_received("kill", payload)`.

- **[P1-F-05] `"ready_request"` Sender Verification Inverted (Bypassable When `sender_id == ""`)** — `godot/src/net/TaloBackend.gd:L777-L784` *(also Lens 8)*
  - **Root Cause Mechanism:** `L783` checks `if sender_id != "" and uid != sender_id: return` instead of `if sender_id == "" or uid != sender_id: return`, and `_on_socket_message()` does not reject empty `sender_id` at entry when `playerAlias` is missing/non-Dict.
  - **Deterministic Trigger & Failure Mode:** Any socket message lacking a valid `playerAlias` Dict bypasses the identity check and toggles any player's `is_ready` state on the host.
  - **Surgical Fix Specification:** Reject `if sender_id == "": return` right after `L710` in `_on_socket_message()`, and fix `L783` to `if sender_id == "" or uid != sender_id: return`.

- **[P2-F-15] `inject_talo_key.py` Non-Atomic Secret Write (`0644` Window) & Loose JWT Validation** — `godot/tools/inject_talo_key.py:L35-L49` *(also Lens 7)*
  - **Root Cause Mechanism:** `OUT.write_text(...)` creates `addons/talo/settings.cfg` under default umask (`0644`) before `os.chmod(OUT, 0o600)` (TOCTOU + non-atomic crash truncation). Validation only checks `key.startswith("eyJ")`, permitting quotes/newlines in `.env` to inject arbitrary INI keys (`api_url`/`socket_url`).
  - **Deterministic Trigger & Failure Mode:** Malformed `.env` injects INI directives into `settings.cfg`, or interrupted write leaves a truncated config.
  - **Surgical Fix Specification:** Validate `re.fullmatch(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", key)`; write to a sibling temp file via `os.open(..., O_WRONLY|O_CREAT|O_EXCL, 0o600)` + `os.fsync()`, then `os.replace(tmp, OUT)`.

- **[P2-F-21] `ArenaNet` Remote-Shot Guard Bypass, Respawn Timer Race & Exit Signal Window** — `godot/src/game/ArenaNet.gd:L63-L67, L166-L174, L208-L215` *(also Lens 4, 7)*
  - **Root Cause Mechanism:** (a) `_spawn_remote_shot()` (`L208-L210`) skips the 5 m muzzle-origin proximity check if `sender == null` and allows shots while `sender.is_respawning == true`. (b) `_hide_remote_briefly()` (`L166-L174`) unconditionally calls `set_respawning(false)` after `respawn_delay + 0.5s`, racing with `"state"` snapshots and resurrecting proxies killed a second time. (c) `_exit_tree()` (`L63-L67`) never disconnects `Supabase.broadcast_received` / `Match.roster_changed`, risking `get_tree() == null` crashes during deferred free.
  - **Deterministic Trigger & Failure Mode:** Remote `"shot"` before first `"state"` or while dead spawns projectiles at arbitrary world coordinates; double-kill within `respawn_delay + 0.5s` prematurely unhides dead proxy; signal during scene teardown crashes `get_tree()`.
  - **Surgical Fix Specification:** Require `sender != null and is_instance_valid(sender) and bool(sender.get("_initialised")) and not bool(sender.get("is_respawning")) and sender.global_position.distance_to(o) <= 5.0`; let `"state"`'s `"d"` flag own respawn visibility (or guard timer with a death-generation counter); disconnect autoload signals in `_exit_tree()`.

### Lens 7: Reliability & Fault Tolerance

- **[P1-F-07] Service Worker Crashes on Cross-Origin/Opaque/204 Responses & 2.5 s `Promise.race` Breaks Cold Slow Loads** — `godot/tools/patch_web_sw.py:L148-L207`, `index.service.worker.js:L52-L68, L121-L137, L148-L154` *(also Lens 8)*
  - **Root Cause Mechanism:** (a) With `ENSURE_CROSSORIGIN_ISOLATION_HEADERS = true`, the `else if` branch intercepts every non-cached request (cross-origin Talo API, non-GET, `204`/`304`, `opaque` `status === 0`) and calls `new Response(response.body, { status: response.status, ... })`, throwing `TypeError`/`RangeError` on `status === 0` or null-body statuses (`204`/`205`/`304`). (b) On a cold cache when `fetchAndCache` takes >2.5 s, `Promise.race` rejects with `sw-timeout`: `isNavigate` returns `caches.match(OFFLINE_URL)` (`undefined` or offline page instead of waiting for the in-flight request, and misses cached `index.html` for `/`); non-navigate (`index.js`) fires a duplicate `fetchAndCache`; losing promise rejection is unhandled. (c) `patch_web_sw.py` writes non-atomically and silently emits `"missing"` if `index.wasm`/`index.pck` are absent.
  - **Deterministic Trigger & Failure Mode:** Any opaque or `204` cross-origin response fails with `net::ERR_FAILED`; first-time visitor on throttled 3G (>2.5 s TTFB) hits a hard SW error or double-downloads `index.js`.
  - **Surgical Fix Specification:** Ignore non-`GET` and cross-origin requests in `fetch`; return `response` unchanged in `ensureCrossOriginIsolationHeaders` when `response.status === 0 || [204,205,304].includes(response.status) || response.type === 'opaque'`; hold `const netP = fetchAndCache(...)` and on `sw-timeout` with no cache return `await netP` (falling back to `cache.match('index.html')` before `OFFLINE_URL`); fail fast in Python on `"missing"` hashes and write atomically via `os.replace`.

- **[P2-F-16] `deploy_web.sh` Swallows `git commit` Failures & Lacks `curl` Timeouts** — `godot/tools/deploy_web.sh:L83-L104` *(also Lens 6)*
  - **Root Cause Mechanism:** `git commit --only ... || { echo "(nothing to commit — bundle identical)"; }` (`L85-L90`) masks real commit errors (missing pathspec, hook failure, untracked new bundle file), proceeds to `git push origin main`, and polls Vercel for 120 s against an uncommitted `index.html`. `curl -s` (`L97`) has no `--fail --max-time`.
  - **Deterministic Trigger & Failure Mode:** Any git hook failure or new export file pushes the old commit and fails after 120 s; a stalled HTTP response hangs `deploy_web.sh` indefinitely holding the flock.
  - **Surgical Fix Specification:** Check `git diff --quiet -- <files>` before `git commit --only` and abort on non-zero `git commit` exit; change `L97` to `curl -fsS --max-time 15`.

- **[P2-F-26] Uncommitted Handbrake `"scrape"` SFX Plays While Stationary** — `godot/src/KiepieBike.gd:L353-L356`
  - **Root Cause Mechanism:** `if braking and grounded and _scrape_cd <= 0.0:` omits a velocity threshold (unlike `CombatController.gd:L101` which checks `speed > 3.0`).
  - **Deterministic Trigger & Failure Mode:** Hold Space while stopped on ground -> plays tire-slide `"scrape"` every 1.6 s while stationary.
  - **Surgical Fix Specification:** Add `and linear_velocity.length() > 2.5`.

- **[P2-F-33] Uncancelled Overlapping Hurt Vignette Tweens & Reduced-Motion Timer Races** — `godot/src/ui/MatchHud.gd:L325-L338, L353-L357, L377-L383`, `godot/src/Hud.gd:L114-L118` *(also Lens 9)*
  - **Root Cause Mechanism:** `_on_hurt()` creates an untracked tween without killing any prior hurt tween; reduced-motion `await create_timer(...)` paths lack generation guards, allowing an older timer to clear a newer flash/announcement.
  - **Deterministic Trigger & Failure Mode:** Rapid hits or back-to-back pickups flicker or prematurely wipe HUD feedback.
  - **Surgical Fix Specification:** Track and `kill()` `_hurt_tween` before creating a new one; add monotonic generation counters checked after every reduced-motion `await`.

- **[P3-F-36] `Sfx._pitch()` Only Clamps `maxf(0.05, ...)` for `JITTERED` Sounds** — `godot/src/audio/Sfx.gd:L162-L165`
  - **Root Cause Mechanism:** Non-jittered sounds return raw `pitch` without `maxf(0.05, pitch)`.
  - **Deterministic Trigger & Failure Mode:** Any caller passing `pitch <= 0.0` for a non-jittered sound triggers a Godot `pitch_scale` runtime error.
  - **Surgical Fix Specification:** Return `maxf(0.05, pitch)` unconditionally.

### Lens 8: Type Systems, Schema & Contracts

- **[P2-F-18] Inverted One-Pole Low-Pass Filter & Hard-Cut Click Endings in `generate_sfx.py`** — `godot/assets/sfx/generate_sfx.py:L41-L44, L323-L352` *(modified in working tree)*
  - **Root Cause Mechanism:** `one_pole_lp()` returns `prev + a * (value - prev)` where `a = exp(-TAU * fc / SR)` instead of `prev + (1.0 - a) * (value - prev)`. Low cutoffs (`20 Hz`, `a = 0.994`) pass raw unfiltered noise while high cutoffs attenuate, inverting sweeps in `cannon_fire`, `explosion`, `respawn`, `dink`, and `scrape`. New `dink()` (`L323-L332`) ends at ~50% amplitude (`exp(-0.7)`) with non-integrated `freq * t` phase; `scrape()` (`L338-L351`) has no tail fade-out (`exp(-0.35/0.9) = 0.68`).
  - **Deterministic Trigger & Failure Mode:** Regenerated WAVs have inverted brightness sweeps and audible end-of-buffer DC clicks on every `dink.wav` / `scrape.wav` playback.
  - **Surgical Fix Specification:** Change `one_pole_lp` to `return prev + (1.0 - a) * (value - prev)`; integrate phase in `dink()`; add a 15–30 ms linear/cosine tail fade-out to `dink()` and `scrape()`, then regenerate WAVs.

- **[P2-F-31] Left Rims Place Outboard Details Inboard & Left Fenders Droop Inward** — `src/qb_wheels.py:L71-L143`, `src/qb_body.py:L152-L153, L219-L220`
  - **Root Cause Mechanism:** `build_rim()` lacks a `side` parameter and always places beadlock/hubcap/nuts at `+hw` (`+X`, which is inboard on left wheels). `build_plastics()` passes `min(x_in, x_out), max(x_in, x_out)` into `fender_grid()`, causing `u > 0.72` to droop the inboard edge on left fenders (`side = -1`).
  - **Deterministic Trigger & Failure Mode:** Rebuilding `Kiepie_Bike.glb` renders left wheels with their rear dish facing outward and left fenders drooping toward the frame.
  - **Surgical Fix Specification:** Pass `side` into `build_rim()` and multiply `hw` X-offsets by `side`; pass `(x_in, x_out)` in inboard-to-outboard order to `fender_grid()`/`build_fender_stripe()`.

- **[P3-F-34] Latent Contract Nits (`self_respawn_at`, `KiepieTime.parse_iso` `weekday` Arg, `MockBackend` Param Drift)** — `godot/src/net/MatchState.gd:L289-L290`, `godot/src/core/KiepieTime.gd:L14-L19`, `godot/src/net/MockBackend.gd:L104`
  - **Root Cause Mechanism:** (a) `MatchState._on_pg_change()` emits `self_respawn_at` whenever `str(row.get("respawn_at", ""))` is non-empty (including `"null"` or expired timestamps) instead of checking `is_respawning(uid)`. (b) `KiepieTime.parse_iso()` passes `utc` to `Time.get_datetime_dict_from_datetime_string(s, weekday)` whose 2nd param is `weekday: bool`, not UTC. (c) `MockBackend._mock_register_kill` reads `p_shooter` while `TaloBackend._register_kill` reads `p_killer`.
  - **Deterministic Trigger & Failure Mode:** Any future listener on `self_respawn_at` fires spuriously; `KiepieTime` performs a redundant fallback; `MockBackend` diverges from live `TaloBackend` RPC arguments.
  - **Surgical Fix Specification:** Gate `MatchState.gd:L289` on `is_respawning(uid)`; pass `false` as 2nd arg in `KiepieTime.gd:L16` and drop redundant retry; accept `args.get("p_killer", args.get("p_shooter", "mock-host"))` in `MockBackend.gd:L104`.

### Lens 9: Platform, Viewport & Portability

- **[P1-F-12] Web Fullscreen Toggle Permanently Dead After Exiting or Toggling OFF Once** — `godot/export_presets.cfg:L23`, `index.html:L80` *(also Lens 7)*
  - **Root Cause Mechanism:** `window.__kiepieSetFullscreen(on)` sets `w.__kiepieFsDone = true` upon entering fullscreen and when `on == false`, but never resets `w.__kiepieFsDone = false` when `on == true`. The guard `if (!w.__kiepieFsDone && !fsEl())` stays permanently `false`.
  - **Deterministic Trigger & Failure Mode:** Launch in fullscreen -> press `Esc` or toggle Settings -> Fullscreen OFF -> toggle Fullscreen ON. Fullscreen can never be re-entered without reloading the page.
  - **Surgical Fix Specification:** Inside `if (on)` in `godot/export_presets.cfg:L23` and `index.html:L80`, reset `w.__kiepieFsDone = false;` before `if (!fsEl())`.

- **[P1-F-13] TouchControls Mobile Layout Branches Unreachable Under `canvas_items`/`expand` (and Overlap When Reached)** — `godot/src/TouchControls.gd:L536-L542` *(Recalibrated via Live Runtime Proof — see Addendum A.2)*
  - **Root Cause Mechanism (Empirical Recalibration):** In the live app, `project.godot` configures `1280×720` with `stretch/mode="canvas_items"` and `stretch/aspect="expand"`, so a `390×844` root window reports `visible_rect = (1280, 2770)` (`360×800` → `(1280, 2844)`, `844×390` → `(1558, 720)`). Consequently, **both mobile branches (`vp.x < 700.0` and `vp.y < 520.0`) in `TouchControls._relayout()` are unreachable dead code in the live app**: overlap is `0.0 px²`, and instead the desktop layout stays active and shrinks the touch pads to ~`91 px` / `64 px` CSS on `390 px` screens. When the `vp.x < 700.0` branch *is* reached (e.g., direct `SubViewport` or `content_scale_factor` change with `dodge_size = 1.6`), `_analog_pad` (`[10, 10 + clampf(vp.x * 0.44, 168, 250)]`) overlaps `_drive_pad` (`rw = clampf(148.0 * pad_scale, 110.0, 210.0)`) by **`1872.0 px²` (`15.6 × 120`)** at `390×844` and **`5040.0 px²` (`42.0 × 120`)** at `360×800`.
  - **Deterministic Trigger & Failure Mode:** On real portrait phones (`390×844`), mobile layout branches never activate, shrinking touch targets; in any viewport where `vp.x < 700` is reached with `dodge_size >= 1.25`, `_on_pointer_down()` (`L167-L176`) hit-tests `_analog_rect()` first and hijacks `dodge_left` touches on the right pad.
  - **Surgical Fix Specification:** Branch mobile layout on physical/CSS screen width (or `DisplayServer.window_get_size()` / `Settings._sync_mobile_scale_now()`), AND clamp `rw` against remaining width with a `>=16 px` center gap: `var max_rw := maxf(110.0, vp.x - 10.0 - pad_w - 16.0 - 14.0); var rw := clampf(148.0 * pad_scale, 110.0, minf(210.0, max_rw))`.

- **[P2-F-32] `AnalogDrive._draw()` Corner Arcs Drawn as 180° Semicircles & Inward-Pointing Dodge Chevrons** — `godot/src/AnalogDrive.gd:L124-L138`
  - **Root Cause Mechanism:** `L133-L136` draws 180° semicircles (`PI * 0.5..PI * 1.5` and `-PI * 0.5..PI * 0.5`) at all 4 corners and omits left/right vertical border lines; `L126-L129` draws `>` on the left and `<` on the right (pointing inward instead of outward).
  - **Deterministic Trigger & Failure Mode:** Visible on every mobile/touch session whenever the right analog pad is displayed.
  - **Surgical Fix Specification:** Draw four 90° quarter-arcs + left/right vertical border lines, and flip dodge chevron apexes outward (`<` on left, `>` on right).

- **[P3-F-38] Hardcoded 56 px Bottom Margin on Mobile Menus Where Desktop Hint Strip Is Hidden** — `godot/src/ui/LobbyMenu.gd:L386`, `godot/src/ui/SettingsMenu.gd:L277`
  - **Root Cause Mechanism:** `index.html:L80` hides the bottom hint strip below `720px` / touch devices, but `LobbyMenu` and `SettingsMenu` always reserve `56 px` (plus `60 px` `BottomPad`), unlike `MainMenu.gd:L92`.
  - **Deterministic Trigger & Failure Mode:** Wastes 56 px of vertical screen space on portrait/landscape mobile menus.
  - **Surgical Fix Specification:** Reuse `MainMenu.gd:L92`'s responsive `min_b` formula in `LobbyMenu` and `SettingsMenu`.

### Lens 10: Cognitive Load & AI Maintainability

- **[P3-F-39] God Files, High-CC Hotspots, Silent Catches, Minified HTML Line & Repo Payload/Doc Drift** — Repo-wide (`telemetry` #8: `VfxFactory.gd:L1-L983`, `TaloBackend.gd:L695-L814`, `KiepieBike.gd:L259-L377`, `MatchHud.gd:L191-L310`, `src/qb_core.py`, `index.html:L80`, `AGENTS.md`, `renders/`) *(also Lens 2)*
  - **Root Cause Mechanism:** 9 first-party God files exceed 400 eff LOC (`VfxFactory.gd` 806, `TaloBackend.gd` 715, `build_arena.gd` 671, `MatchHud.gd` 552, `src/qb_body.py` 497, `src/qb_core.py` 487, `build_testride.gd` 462, `TouchControls.gd` 437, `build_menus.gd` 416); 101 complex functions exceed CC>=10 or LOC>=60 (`KiepieBike._physics_process` CC 50, `TaloBackend._on_socket_message` CC 48, `MatchHud._relayout` CC 47); 13 silent catches exist across 5 first-party files (`src/qb_core.py` 7, `MobileTextInput.gd` 3, `Settings.gd` 1, `src/build_quad.py` 1, `index.service.worker.js` 1); `index.html:L80` packs 5,539 chars of CSS+JS onto one line duplicated verbatim in `export_presets.cfg:L23`. Repo tracks 18+ MB of `renders/` PNGs and duplicate `Kiepie_Bike.glb` (1.5 MB x2), and `AGENTS.md` still cites `index.pck` ≈2.7 MB while current root `index.pck` is 3.0 MB.
  - **Deterministic Trigger & Failure Mode:** High cognitive load and duplicated single-line shell scripts increase regression probability on every edit (as evidenced by `F-01`, `F-12`, `F-28`).
  - **Surgical Fix Specification:** Extract `TaloBackend` message dispatch into per-kind handlers, split `KiepieBike` VFX/SFX hooks out of `_physics_process`, log/narrow silent catches, update `AGENTS.md` `index.pck` baseline note to ≈3.0 MB, and consider untracking regenerable `renders/` artifacts.

---

## 3. Existing Test Suite Comparison & Mutation Truth Table

- **Test-to-Code File Ratio:** `26 / 60` (`0.43` — 24 `.gd` gates + `check_scene_sync.py` + `test_kiepie_pad.gd` vs 60 first-party impl/tool files)
- **Estimated Mutation Kill Score ($M_{\text{kill}}$):** **`39.6%` (19 / 48 mutants)** (`369` static assertions [339 gates + 30 GdUnit4], `11/26` negative/boundary assertion files, `6/26` mock-heavy files, `10+` unpaired critical modules)
- **Web Export Ship Verification:** Inspected `godot/export_presets.cfg`, `index.html`, `index.service.worker.js`, and binary `index.pck` (GDPC v2, Godot 4.3.0, 215 files, 3,076,960 B ≈ 2.93 MB < 4 MB cap): **35/35** `res://src/**/*.gd` modules and **6/6** scenes ship; `res://addons/talo/settings.cfg` ships; **0** `tests/`/`tools/`/`gdUnit4` files leaked. **Gap:** Web shell JS (`index.html:L80`) and `index.service.worker.js` have **0** automated tests.

| Implementation Module | Critical Functions / Branches | Paired Test / Gate Files | Pathologies Detected | Mental Mutants Killed (`M1-M4`) | High-Priority Missing Assertions |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `KiepieBike.gd` (506) | `_integrate_forces`, `_try_dodge`, `_physics_process` | `truth_test`, `verify_{stability,controls,dodge,rollover,features,smash_impact,audit_regressions,pogo,touch_multitouch}` | Time-Window Myopia, Impl-Coupled | 3/8 (37.5%) | `keep` damping direction, airborne dodge reject, dodge re-fire after 1s cd, world-space VFX pos |
| `TouchControls.gd` + `TouchCapture` + `Analog*` | `_on_pointer_down`, `_sync_analog`, `_sync_drive` | `verify_touch`, `verify_touch_multitouch`, `verify_practice`, `test_kiepie_pad` | Shared Mutable State (`settings.cfg` on fail) | 4/4 (100%) | Narrow portrait `dodge_size = 1.6` non-overlap |
| `TaloBackend.gd` (877) | `_on_socket_message`, `_register_kill`, `is_channel_joinable`, `_on_socket_closed` | `verify_talo_backend`, `verify_audit_regressions`, `verify_multiplayer` | Mock-Mirror (`_channel=null`), Result-Only | 4/8 (50%) | `"lobby_update"` / `"kill"` / `"ready_request"` forgery, reconnect re-identify, pagination, HTTP 500 |
| `CombatController.gd` (307) | `take_damage`, `_die`, `reset_state` | `verify_combat`, `verify_practice`, `verify_appeal` | Result-Only, Time-Window Myopia, Happy-Path | 2/8 (25%) | `reset_state()` `collision_layer/mask == 1`, negative/NaN damage, shield/invuln, unknown killer |
| `SideCannons.gd` (163) | `fire()` (async `issue_shot`) | `verify_cannons`, `verify_practice`, `verify_pogo` | No-Throw Theater, Happy-Path | 1/4 (25%) | Post-`await` liveness / `!is_playing()`, empty token, real banana spawn |
| `ArenaNet.gd` (263) | `_spawn_remote_shot`, `_hide_remote_briefly`, `_sync_roster` | `verify_multiplayer`, `verify_kill_flow`, `verify_audit_regressions` | Happy-Path, Mock-Mirror | 2/4 (50%) | `Inf/NaN`, `>5m` origin with `sender==null`, `>24/s` cap, peer removal |
| `NetworkedBike.gd` (153) | `apply_state`, `_process` | `verify_multiplayer` | Happy-Path | 1/4 (25%) | Monotonic `n` drop, `NaN/Inf` `p`/`r`, respawn `collision_layer=0` |
| `MatchState.gd` (304) | `apply_lobby`, `all_ready`, `is_respawning`, `_on_pg_change` | `verify_match_rules`, `verify_audit_regressions`, `test_kiepie_pad` | Mock-Mirror (`MockBackend` drift) | 2/4 (50%) | `DELETE`/`SYNC` roster removal, `_on_host_lost`, transition-only guard |
| `Projectile.gd` & `BananaProjectile.gd` | `setup`, `_physics_process` | **NONE** (`_check_scripts` only) | Unpaired | 0/4 (0%) | Live collider hit, self-exclusion, vertical `looking_at`, zero/NaN dir |
| **Other Unpaired Critical Modules** | `Pickup.gd`, `PogoVisual.gd`, `KiepieTime.gd`, `LobbyMenu.gd`, `MainMenu.gd`, `SettingsMenu.gd`, `src/*.py`, `index.html`, `index.service.worker.js` | **NONE** | Unpaired / No-Throw Theater | 0% | All behavioral, lifecycle, SW fetch/isolation, and Web fullscreen invariants |

### Seven Vibe-Coded Test Pathologies Observed

1. **Mock-Mirror Tautology:** `verify_match_rules.gd` & `verify_kill_flow.gd` test `MockBackend.gd`, which diverged from `TaloBackend.gd` (`p_shooter` vs `p_killer`, `"kill_cooldown"` vs `"rate_limited"`, 10 s token expiry). `verify_talo_backend.gd` sets `_channel = null`, turning `_apply_props`/`_send` into no-ops.
2. **No-Throw Theater:** `verify_vfx.gd:L87-L100` checks only `holder.get_child_count() > 0`; `verify_appeal.gd:L27, L41` checks array counts without exercising audio or pickups; `verify_pogo.gd` never fires a banana.
3. **Happy-Path Tunnel Vision:** Zero negative/degenerate tests for `CombatController.take_damage` (negative damage heals), `Projectile.setup`, `ArenaNet._spawn_remote_shot` (`Inf/NaN`, `>5m`, `>24/s`), `NetworkedBike.apply_state`, or corrupt `settings.cfg`.
4. **Shared Mutable State:** `verify_touch.gd:L77`, `verify_practice.gd:L89`, and `verify_touch_multitouch.gd:L102` mutate `user://settings.cfg` and `quit(1)` early without restoring priors; `verify_audit_regressions.gd` and `verify_combat.gd` dirty `Match` autoload state.
5. **Implementation-Coupled Assertions:** `verify_pogo.gd` pins private `_profile`/`_muzzles`; `verify_dodge.gd` asserts private `_dodge_cd > 0.0` instead of re-fire behavior; `verify_appeal.gd` pins `SAMPLES.size() == 12`; `verify_vfx.gd` pins private `hud._total`.
6. **Time-Window Myopia:** `verify_combat.gd:L58` zeroes `_invuln_until` so post-respawn invulnerability is never tested; `verify_dodge.gd` samples only 6 frames (~0.1 s vs 1.0 s cooldown); 15 s/20 s/90 s Talo heartbeats are never compressed or sampled.
7. **Result-Only Assertions:** `verify_practice.gd:L217-L219` verifies `RestartBtn` via `alive`/`health`/`visible`/`pos` and completely misses `bike.collision_layer == 0` / `collision_mask == 0` (`F-08`).

### Why Existing Tests Missed Discovered P0/P1 Defects

- **F-01 / F-03 / F-05 (`TaloBackend` forged broadcasts):** `verify_audit_regressions.gd` only tested forged `"state"` messages; `"lobby_update"`, `"kill"`, and empty-alias `"ready_request"` were never fuzzed.
- **F-02 / F-06 (`TaloBackend` reconnect & pagination):** `verify_talo_backend.gd` never exercised `_on_socket_closed()` against `TaloSocket`'s `_temp_socket_token` lifecycle or multi-page `get_channels()` responses.
- **F-04 (Departed players):** No gate tests peer `"leave"` propagation through `TaloBackend` -> `MatchState` -> `ArenaNet._sync_roster()`.
- **F-07 / F-12 (Web SW & Fullscreen):** `index.html` inline JS and `index.service.worker.js` have zero automated tests.
- **F-08 (`CombatController.reset_state`):** Result-only assertions in `verify_practice.gd` omitted `collision_layer`/`collision_mask`.
- **F-09 / F-10 (`KiepieBike` VFX & rollover damping):** `verify_rollover.gd` tested static tilt recovery (where the righting spring alone eventually uprights the bike), masking the inverted `keep` retention factor; no test asserted world coordinates of spawned `dust_ring`/`roost`.
- **F-11 / F-13 / F-14 (`SideCannons`, `TouchControls`, `SettingsMenu`):** `MockBackend.issue_shot()` resolves synchronously (hiding the async death window); `verify_touch.gd` tested default `dodge_size = 1.0` (not `1.6` at `390px`); `verify_settings.gd` never dragged a slider and exited `SettingsMenu` within 350 ms.

### Minimal Viable Test Harness (MVTH) Specifications

1. **MVTH-1 (Tier 2 — Combat, Projectiles & Pickups Gate):** Assert `CombatController.reset_state()` restores `bike.collision_layer == 1` & `collision_mask == 1` after `_die()` (fails on current code); table-drive `take_damage([0, -25, NAN, 30, 100])`, shield/invuln, `!Match.is_playing()`, and unknown-attacker stripping; fire real `Projectile` and `BananaProjectile` (60 dmg) including near-vertical shots into live colliders; trigger all 4 `Pickup` kinds.
2. **MVTH-2 (Tier 1 — Pure Core & Wire-Guard GdUnit4 Table Suite):** Table-drive `KiepieTime.parse_iso` / `iso_from_unix`, `ArenaNet._spawn_remote_shot` adversarial inputs (`Inf/NaN`, `sender==null`, `>5m`, `>100`, 25th shot/s), and `NetworkedBike.apply_state` monotonic `n` (`5 -> 4 -> 5 -> 6`), `NaN` `p`/`r`, and `collision_layer` toggling.
3. **MVTH-3 (Tier 2/3 — TaloBackend Auth, Reconnect & Counting-Stub Gate):** Fuzz forged `"lobby_update"`, forged `"kill"` (`sender_id != victim`), and empty-`sender_id` `"ready_request"` (all must be dropped); verify peer `"leave"` removes `Match.players[uid]` and frees `NetworkedBike`; inject a ~30-line counting fake `Talo.channels.client` to verify `_apply_props` coalescing, 20/min kill cap, multi-page channel scan, and reconnect re-identification.
4. **MVTH-4 (Tier 1/3 — Web Service Worker & Shell Node Smoke Test):** Lightweight Node test loading `index.service.worker.js` with stubbed `caches`/`fetch` verifying non-GET/cross-origin pass-through, `204`/`opaque` non-throw, 2.5 s timeout reuse of in-flight `netP`, `ENGINE_CACHE` survival, and `__kiepieSetFullscreen(true)` re-entry after `false`.

---

## 4. Surgical Refactoring Blueprints (Zero-Mutation Drafts)

### Refactor [R1]: TaloBackend Socket Authority Gate & Reconnect Re-Identify (`F-01`, `F-02`, `F-03`, `F-05`)

- **Target Scope:** `godot/src/net/TaloBackend.gd:L85-L88, L137-L159, L705-L827`
- **Engineering ROI:** Eliminates the lone P0 (host-authority hijack) plus 3 P1s (permanent reconnect brick, kill spoofing, inverted ready check) in ~25 net lines.

**Current Pattern (Audited Code):**

```gdscript
# TaloBackend.gd:L146-L158
if is_ready:
	await Talo.socket.open_connection()
	# ... 2500ms wait for _identified (always times out: _temp_socket_token was cleared) ...
	if bool(Talo.socket.get("_identified")):
		connection_state.emit("connected")
	else:
		is_ready = false
		connection_state.emit("disconnected")

# TaloBackend.gd:L783, L804-L810, L825-L826
if sender_id != "" and uid != sender_id:
	return
# ...
"kill":
	if payload is Dictionary:
		broadcast_received.emit("kill", payload)
# ...
"lobby_update":
	broadcast_received.emit("lobby_update", payload)
```

**Target Pattern (Surgical Blueprint):**

```gdscript
# TaloBackend.gd (reconnect): mint a fresh socketToken before opening the socket
if is_ready:
	if Talo.current_alias != null:
		await Talo.players.identify("anonymous", Talo.current_alias.identifier)
	await Talo.socket.open_connection()
	var sock_deadline := Time.get_ticks_msec() + 2500
	while not bool(Talo.socket.get("_identified")) and Time.get_ticks_msec() < sock_deadline:
		await get_tree().process_frame
	if bool(Talo.socket.get("_identified")):
		_reconnect_attempts = 0
		connection_state.emit("connected")
	else:
		connection_state.emit("disconnected")
		_on_socket_closed(0, "identify_timeout") # bounded backoff retry instead of permanent brick

# TaloBackend.gd (_on_socket_message): reject empty sender_id at entry + bind victim/host
if sender_id == "":
	return
# ... in "ready_request":
if uid != sender_id:
	return
# ... in "kill":
"kill":
	if payload is Dictionary:
		var victim := str((payload as Dictionary).get("victim", ""))
		if victim == "" or victim != sender_id:
			return
		broadcast_received.emit("kill", payload)
# ... in "lobby_update":
"lobby_update":
	if sender_id != str(_lobby.get("host_id", "")):
		return
	broadcast_received.emit("lobby_update", payload)
```

### Refactor [R2]: KiepieBike Rollover Damping Sign Fix & World-Space VFX Parent (`F-09`, `F-10`)

- **Target Scope:** `godot/src/KiepieBike.gd:L282-L299, L486-L506`
- **Engineering ROI:** Fixes inverted anti-rollover physics and eliminates double-transformed floating dust/roost VFX with zero new allocations.

**Current Pattern (Audited Code):**

```gdscript
# KiepieBike.gd:L283-L298
var rear: Vector3 = global_position - global_transform.basis.z * 0.66
VfxFactory.dust_ring(self, Vector3(rear.x, 0.0, rear.z), 1.1, 4.5)
# ...
VfxFactory.roost(self, at, global_transform.basis.z)

# KiepieBike.gd:L486-L506
var dt_scale := clampf(state.step * 60.0, 0.25, 4.0)
var keep := lerpf(0.90, 0.997, lean)
state.angular_velocity = yaw + trans * pow(keep, dt_scale)
# ...
var effort := minf(tilt * (0.10 + lean * 1.5), 0.14) * dt_scale
```

**Target Pattern (Surgical Blueprint):**

```gdscript
# KiepieBike.gd: parent world-space VFX to scene root (not self)
var fx_root: Node3D = get_tree().current_scene as Node3D
if fx_root == null:
	fx_root = get_parent() as Node3D
VfxFactory.dust_ring(fx_root, Vector3(rear.x, 0.0, rear.z), 1.1, 4.5)
# ...
VfxFactory.roost(fx_root, at, global_transform.basis.z)

# KiepieBike.gd: true retention factor (1 - damping) and overshoot-clamped righting effort
var dt_scale := clampf(state.step * 60.0, 0.25, 4.0)
var keep := lerpf(0.10, 0.003, lean)
state.angular_velocity = yaw + trans * pow(keep, dt_scale)
# ...
var effort := minf(minf(tilt * (0.10 + lean * 1.5), 0.14) * dt_scale, tilt)
```

### Refactor [R3]: CombatController Full Reset & SideCannons Post-Await Liveness Guard (`F-08`, `F-11`)

- **Target Scope:** `godot/src/game/CombatController.gd:L230-L242`, `godot/src/game/SideCannons.gd:L132-L163`
- **Engineering ROI:** Prevents TestRide floor-fall softlock on restart and eliminates ghost projectiles fired after death/match-end.

**Current Pattern (Audited Code):**

```gdscript
# CombatController.gd:L236-L242
bike.set_physics_process(true)
bike.visible = true
health = MAX_HEALTH
alive = true

# SideCannons.gd:L132-L145
var res: Dictionary = await Match.issue_shot()
var token := str(res.get("token", ""))
if token == "":
	return
# ... spawns projectiles without checking owner_node.visible / alive / Match.is_playing()
```

**Target Pattern (Surgical Blueprint):**

```gdscript
# CombatController.gd: restore collision + clear buffs symmetrically with _respawn()
bike.collision_layer = 1
bike.collision_mask = 1
_rapid_until = 0.0
_overdrive_until = 0.0
_shield_until = 0.0
bike.overdrive_active = false
bike.engine_power = _base_power
bike.set_physics_process(true)
bike.visible = true
health = MAX_HEALTH
alive = true

# SideCannons.gd: re-verify tree/liveness/match state after async round-trip
var res: Dictionary = await Match.issue_shot()
if not is_inside_tree() or not is_instance_valid(owner_node) or not owner_node.visible:
	return
var combat := owner_node.get_node_or_null("CombatController")
if combat != null and not bool(combat.get("alive")):
	return
if not bool(combat.get("practice_mode")) and not Match.is_playing():
	return
```

### Refactor [R4]: Service Worker Cross-Origin/204 Guard & Cold-Load Single-Fetch (`F-07`)

- **Target Scope:** `godot/tools/patch_web_sw.py:L148-L207` (regenerates `index.service.worker.js`)
- **Engineering ROI:** Prevents `net::ERR_FAILED` on opaque/204 responses and eliminates cold-load SW failures & duplicate `index.js` downloads on slow networks.

**Current Pattern (Audited Code):**

```js
// index.service.worker.js:L52-L68, L121-L136, L148-L154
function ensureCrossOriginIsolationHeaders(response) {
	// throws RangeError/TypeError on status === 0 (opaque) or 204/205/304
	return new Response(response.body, { status: response.status, ... });
}
// ...
try {
	return await Promise.race([fetchAndCache(...), timeout(2500)]);
} catch (e) {
	let cached = await cache.match(event.request);
	if (cached != null) return ...;
	if (isNavigate) return caches.match(OFFLINE_URL);
	return await fetchAndCache(...); // duplicate fetch!
}
```

**Target Pattern (Surgical Blueprint):**

```js
function ensureCrossOriginIsolationHeaders(response) {
	if (!response || response.type === 'opaque' || response.status === 0
		|| response.status === 204 || response.status === 205 || response.status === 304) {
		return response;
	}
	if (response.headers.get('Cross-Origin-Embedder-Policy') === 'require-corp'
		&& response.headers.get('Cross-Origin-Opener-Policy') === 'same-origin') {
		return response;
	}
	const h = new Headers(response.headers);
	h.set('Cross-Origin-Embedder-Policy', 'require-corp');
	h.set('Cross-Origin-Opener-Policy', 'same-origin');
	return new Response(response.body, { status: response.status, statusText: response.statusText, headers: h });
}

// In fetch handler: ignore non-GET and cross-origin completely
if (event.request.method !== 'GET') return;
if (new URL(event.request.url, self.location.href).origin !== self.location.origin) return;

// In networkFirst: reuse in-flight netP on sw-timeout when cold
const netP = fetchAndCache(event, cache, isCachable);
netP.catch(() => {});
try {
	return await Promise.race([netP, new Promise((_, rej) => setTimeout(() => rej(new Error('sw-timeout')), 2500))]);
} catch (e) {
	let cached = await cache.match(event.request);
	if (!cached && isNavigate) cached = await cache.match('index.html');
	if (cached != null) return ENSURE_CROSSORIGIN_ISOLATION_HEADERS ? ensureCrossOriginIsolationHeaders(cached) : cached;
	if (e && e.message === 'sw-timeout') return await netP;
	if (isNavigate) { const off = await caches.match(OFFLINE_URL); if (off) return off; }
	throw e;
}
```

---

## 5. Phased Execution Roadmap & Scoped Agent Prompts

1. **Phase 1 — Containment & Safety Lock (`P0` + Auth/Reconnect/Reset `P1`s + MVTH Baseline):**
   - Land `F-01`, `F-02`, `F-03`, `F-04`, `F-05`, `F-06` (`TaloBackend.gd` + `MatchState.gd`) with MVTH-3 regression tests in `verify_audit_regressions.gd` / `verify_talo_backend.gd`.
   - Land `F-08` (`CombatController.reset_state`) + `F-11` (`SideCannons.fire`) with MVTH-1 assertions.
2. **Phase 2 — Gameplay Physics, Touch/Web Shell & SW Hardening (Remaining `P1`s):**
   - Land `F-09`, `F-10` (`KiepieBike.gd`), `F-07` (`patch_web_sw.py` + MVTH-4), `F-12` (`export_presets.cfg` + `index.html`), `F-13` (`TouchControls.gd`), `F-14` (`SettingsMenu.gd`).
3. **Phase 3 — Structural De-Vibing, Audio/Blender Pipeline & Performance (`P2`/`P3`):**
   - Fix uncommitted `generate_sfx.py` (`F-18`) and `KiepieBike.gd` scrape threshold (`F-26`) before committing the current SFX WIP.
   - Land `F-15`–`F-17`, `F-19`–`F-39`, MVTH-2 GdUnit4 table tests, and `run_gates.sh` full green verification.

### Copy-Paste Surgical Prompts for Coding Agents

> **Prompt [P0-1] (`godot/src/net/TaloBackend.gd`, `godot/src/net/MatchState.gd`):**
> "Strictly scope edits to `godot/src/net/TaloBackend.gd` (lines 55–88, 137–159, 543–548, 705–827), `godot/src/net/MatchState.gd` (lines 77–85, 270–301), and `godot/tools/verify_audit_regressions.gd`. Do not modify any other files. (1) Reject empty `sender_id` at entry in `_on_socket_message()`, gate `"lobby_update"` on `sender_id == host_id` (or remove it), gate `"kill"` on `victim == sender_id`, and fix `"ready_request"` to reject `sender_id == ""`. (2) In `_on_socket_closed()`, re-call `Talo.players.identify(...)` before `open_connection()`, reset `_starting = false` on `start()` success, and retry instead of bricking `is_ready`. (3) Emit full roster `SYNC` / `DELETE` on leave and handle it in `MatchState._on_pg_change()` + clear `players` in `set_lobby()`. Add regression tests proving forged `"lobby_update"`, forged `"kill"`, empty-sender `"ready_request"`, and peer leave removal, then run `bash godot/tools/run_gates.sh --no-build`."

> **Prompt [P1-2] (`godot/src/KiepieBike.gd`, `godot/src/game/CombatController.gd`, `godot/src/game/SideCannons.gd`):**
> "Strictly scope edits to `godot/src/KiepieBike.gd` (lines 282–299, 353–356, 486–506), `godot/src/game/CombatController.gd` (lines 230–242), `godot/src/game/SideCannons.gd` (lines 132–163), and `godot/tools/verify_practice.gd` / `verify_rollover.gd`. (1) In `CombatController.reset_state()`, restore `bike.collision_layer = 1`, `bike.collision_mask = 1`, and reset buff timers/overdrive. (2) In `KiepieBike._physics_process()`, pass scene root instead of `self` to `VfxFactory.dust_ring()`/`roost()`, add `linear_velocity.length() > 2.5` to handbrake scrape, and in `_integrate_forces()` fix `keep = lerpf(0.10, 0.003, lean)` and clamp `effort <= tilt`. (3) In `SideCannons.fire()`, verify `is_inside_tree()`, `owner_node.visible`, `combat.alive`, and `Match.is_playing()` after `await Match.issue_shot()`. Add assertions in `verify_practice.gd` checking `collision_layer == 1` & `collision_mask == 1` after death+restart, and run `bash godot/tools/run_gates.sh --no-build`."

> **Prompt [P1-3] (`godot/tools/patch_web_sw.py`, `godot/export_presets.cfg`, `index.html`, `godot/src/TouchControls.gd`, `godot/src/ui/SettingsMenu.gd`):**
> "Strictly scope edits to those 5 files (plus `godot/tools/verify_touch.gd`). (1) In `patch_web_sw.py`, skip non-GET/cross-origin requests, guard `ensureCrossOriginIsolationHeaders()` against `status === 0`/`204`/`205`/`304`/`opaque`, reuse in-flight `netP` on `sw-timeout`, fall back to cached `index.html`, fail on missing hashes, and write atomically via `os.replace`. (2) In `export_presets.cfg:L23` and `index.html:L80`, reset `w.__kiepieFsDone = false` inside `if (on)` of `__kiepieSetFullscreen`, return early on `if (rm || seen()) return;` before creating splash DOM, remove the `keydown` listener in `drop()`, and quote `aria-label="Skip intro"`. (3) In `TouchControls.gd:L536-L542`, fix the unreachable `vp.x < 700` / `vp.y < 520` mobile threshold under `canvas_items`/`expand`, clamp `rw` against `vp.x - 10.0 - pad_w - 16.0 - 14.0`, and add a `390x844` `dodge_size = 1.6` non-overlap check in `verify_touch.gd`. (4) In `SettingsMenu.gd:L95-L99`, disconnect `Settings.changed` before `_flush_writes()` and guard `is_inside_tree()` in `_on_setting_changed()`. Run `bash godot/tools/run_gates.sh --no-build`."

---

## Addendum A — Live Gate Execution, Empirical Runtime Reproductions, Pass 2.5 Web/SW Probe, Dead-Code/Unwired Sweep & 11th Lens (Engagement & Game Feel)

All live probes ran in isolated scratch copies under `/tmp/` with isolated XDG directories and `python3 -B` — **zero mutations** to any source, scene, config, or test file in the repository.

### A.1 Isolated 26-Gate Execution Truth Table

Executed `bash godot/tools/run_gates.sh --no-build` in `/tmp/kiepie-scratch-gates` (`KIEPIE_MOCK_BACKEND=1`, isolated `XDG_*` and `TMPDIR`): **26/26 PASS (`rc=0`, 79.2 s wall-clock)**. Independently verified `python3 -B godot/tools/check_scene_sync.py` on the real repo (**PASS, `rc=0`**, 6/6 `.tscn` files match `HEAD`) and ran all 4 scene builders (`build_bike.gd`, `build_testride.gd`, `build_menus.gd`, `build_arena.gd`, all `rc=0`) in scratch with normalized diff against the working tree (**6/6 MATCH** — zero builder/scene drift).

| # | Gate | Status | RC | Duration | Evidence / Hidden Log Errors |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | `scene_sync` | PASS* | 0 | 0.0s | *SKIP in scratch (no `.git`); PASS on read-only real repo check (`6/6` match `HEAD`) + `6/6` MATCH scratch rebuild |
| 2 | `truth` | PASS | 0 | 3.1s | `MIN_UP_Y: 0.998`; 2x Talo 401/socket-ticket err |
| 3 | `stability` | PASS | 0 | 4.0s | `min up.y = 0.993`, `final up.y = 1.000`; 2x Talo 401/socket-ticket err |
| 4 | `touch` | PASS | 0 | 0.8s | `TOUCH VERIFY: 0 failure(s)` |
| 5 | `features` | PASS | 0 | 1.9s | turbo + 3 smashes + 43 rigid bodies; 2x Talo 401 err |
| 6 | `smash_impact` | PASS | 0 | 5.6s | `UP_Y_AFTER_SMASH: 1.000`, 15 bodies; 2x Talo 401 err |
| 7 | `diag2` | PASS | 0 | 0.7s | Workshop/Shed/Store smashes 0→3/4 |
| 8 | `cannons` | PASS | 0 | 0.4s | opposite/front/symmetric muzzles, 192 chassis meshes |
| 9 | `settings` | PASS | 0 | 0.4s | v1→v2 fullscreen migration + `SettingsMenu` ON |
| 10 | `match_rules` | PASS | 0 | 0.4s | kill target 2 + match finished |
| 11 | `combat` | PASS | 0 | 1.2s | damage, respawn, health restore; 2x Talo 401 err |
| 12 | `kill_flow` | PASS | 0 | 0.5s | shot token + death broadcast + spectator guard |
| 13 | `appeal` | PASS | 0 | 1.3s | drum chain + termination + blast damage; 2x Talo 401 err |
| 14 | `accessibility` | PASS | 0 | 0.7s | `focus_mode` checks pass |
| 15 | `talo_backend` | PASS | 0 | 1.5s | 19 checks, 0 failures; 2x Talo 401 err |
| 16 | `audit_regressions` | PASS | 0 | 0.6s | 0 failures |
| 17 | `controls` | PASS | 0 | 5.7s | yaw 31.2°, min_up 0.999, sens 14.7° vs 32.4°; 2x Talo 401 err |
| 18 | `dodge` | PASS | 0 | 2.3s | cooldown 0.95s, upright recovery 1.00; 2x Talo 401 err |
| 19 | `rollover` | PASS | 0 | 5.0s | capsized `up.dot=0.61`, upright `min up=1.00`; 2x Talo 401 err |
| 20 | `vfx` | PASS | 0 | 1.3s | 0 failures, scars capped 24; **3x freed-lambda err**, 2x Talo 401 err |
| 21 | `practice` | PASS | 0 | 1.8s | 0 failures (100→70 dmg, death, RestartBtn revive); 2x Talo 401 err |
| 22 | `multiplayer` | PASS | 0 | 1.0s | 0 failures (`bike_state` relay + float alias IDs + sender mismatch drop) |
| 23 | `pogo` | PASS | 0 | 0.7s | 0 failures (2 banana muzzles, deterministic draw); **236x `!is_inside_tree()` `get_global_transform` err** |
| 24 | `check_scripts` | PASS | 0 | 0.8s | all scripts OK |
| 25 | `touch_multitouch` | PASS | 0 | 35.0s | xvfb 1280×720, `0 failure(s)`; 2x Talo 401 err |
| 26 | `gdunit` | PASS | 0 | 2.1s | 6/6 tests PASSED, 0 errors/failures/flaky/skipped/orphans; **3x freed-lambda err**, 2x Talo 401 err |

**Three Hidden Non-Benign Error Classes Masked by Passing Gates:**
1. **14× Talo 401 Live Socket Attempts in Mock Mode:** 14 gates log `ERROR: 401: Bad Authorization header format` + `ERROR: Failed to get socket ticket` even with `KIEPIE_MOCK_BACKEND=1` because the vendored `Talo` autoload initiates a socket ticket request on startup regardless of the mock env var.
2. **6× Freed-Lambda Capture Errors (`vfx` 3×, `gdunit` 3×):** `ERROR: Lambda capture at index 0 was freed. Passed "null" instead.` (`gdscript_lambda_callable.cpp:108`) from cleanup timers firing after captured nodes are freed.
3. **236× Out-of-Tree Transform Errors (`verify_pogo`):** `ERROR: Condition "!is_inside_tree()" is true. Returning: Transform3D()` (`node_3d.cpp:345`) during pre-tree mesh/AABB inspection in `verify_pogo.gd`.

---

### A.2 Empirical Runtime Reproduction Table

All 8 targeted findings were executed against the real GDScript runtime in an isolated scratch copy (`/tmp/kiepie-scratch-repro`, `godot-4.3 --headless`, `KIEPIE_MOCK_BACKEND=1`):

| Finding | Tier | Verdict | Exact Observed Values & Nuance |
| :--- | :--- | :--- | :--- |
| **F-01** | P0 | **PROVEN** | Guest (`playerAlias.id=200`) sends `lobby_update` → `Match.lobby` & `match_finished` overwritten: `BEFORE: status=playing host_id=100 winner_id=` → `AFTER: status=finished host_id=evil-guest winner_id=evil-guest match_finished_signals=["evil-guest"]`. |
| **F-03** | P1 | **PROVEN** *(alias-type nuance)* | Guest (`playerAlias.id=3`, `sender_id='3'`) or missing `playerAlias` (`sender_id=''`) sending `{"k":"kill","p":{"killer":"host-1","victim":"victim-2","token":"forged"}}` emits `broadcast_received("kill", {"killer":"host-1","token":"forged","victim":"victim-2"})`. *Nuance:* non-numeric string `playerAlias.id="evil-3"` is dropped at `TaloBackend.gd:707-709` (`int("evil-3")==0<=0`), but any real Talo integer alias `id>=1` forges arbitrary kills. |
| **F-04** | P1 | **PROVEN** | Peers `100` (ready), `200` (unready), `300` (ready) join; `200` leaves → `Talo._roster keys=["100","300"]`, `Match.players keys=["100","200","300"]`, `Match.all_ready()=false`. Even an explicit `{"table":"lobby_players","type":"DELETE","record":{"user_id":"200"}}` is ignored (`MatchState.gd:273`), leaving `Match.players.has("200")=true` & `all_ready=false`. |
| **F-05** | P1 | **PROVEN** *(payload-key nuance)* | `TaloBackend.gd:780` reads `"user_id"`, not `"uid"`: `{"uid":"victim","ready":true}` is a no-op; control `{"user_id":"victim","ready":true}` with `sender_id="300"` is blocked (`is_ready=false`); `{"user_id":"victim","ready":true}` with missing `playerAlias` (`sender_id=""`) **bypasses** `L783` (`victim.is_ready=true`). |
| **F-08** | P1 | **PROVEN** | `TestRide.tscn`: `INITIAL: layer=1 mask=1 visible=true alive=true` → `AFTER _die(): layer=0 mask=0 visible=false alive=false` → `AFTER reset_state(): layer=0 mask=0 visible=true alive=true health=100.0` (revived as zero-collision ghost). |
| **F-09** | P1 | **PROVEN** | `bike.global_position=(20,0,20)`: `dust_ring(bike, ...)` spawns `MeshInstance3D` at `local=(20,0.1,20)` → **`global=(40,0.1,40)`** and `GPUParticles3D` at `local=(20,0.16,20)` → **`global=(40,0.16,40)`**; `roost(bike, ...)` spawns `GPUParticles3D` at `local=(20,0,20)` → **`global=(40,0,40)`** (exact 2× position doubling). |
| **F-10** | P1 | **PROVEN** *(spring nuance)* | `keep=lerpf(0.90, 0.997, lean)` is inverted (`keep(0.0)=0.9000` vs `keep(0.9)=0.9873`). Live `VehicleBody3D` (`angular_damp=0.0`): 1 tick retains **`97.14%`** at `lean=0.9` vs **`90.13%`** at `lean=0.0`; 60 ticks with `lean` pinned=`0.9` retains **`27.50%`** (`25.33%` w/ default `angular_damp=0.1`) vs **`0.18%`** upright (152× more retained). *Nuance:* unpinned in free space, the righting spring pulls `lean` `0.9000→0.6043` (tick 1) `→0.0013` (tick 60), so `trans_av` decays to `0.21%` by tick 60 once upright; the defect degrades roll damping while actively tilted/fighting external torque. |
| **F-13** | P1 | **NUANCED** *(FALSIFIED on live root Window; PROVEN in `vp.x<700` branch)* | **Live-app catch:** `project.godot` uses `1280×720` + `canvas_items` + `expand`, so `root.size=(390,844)` yields `visible_rect=(1280,2770)` (`(360,800)→(1280,2844)`, `(844,390)→(1558,720)`). Both mobile branches (`vp.x<700`, `vp.y<520`) are **unreachable dead code** in the live app (`overlap=0.0 px²`; pads shrink to ~`91px`/`64px` CSS on `390px` screens). When `vp.x<700` *is* reached (direct `SubViewport`, `dodge_size=1.6`): `390×844` → **overlap=`1872.0 px²` (`15.6×120`)**; `360×800` → **overlap=`5040.0 px²` (`42.0×120`)**. |

---

### A.3 Pass 2.5 Live Web Shell & Service Worker Probe

#### 1. Service Worker Live Execution Probe (`F-07`, Node `v26.8.2` `vm` harness on `index.service.worker.js`)
- **Cross-origin opaque (`status: 0, type: 'opaque'`, `mode: 'no-cors'`):** **CONFIRMED CRASH** — `ensureCrossOriginIsolationHeaders()` threw `RangeError: init["status"] must be in the range of 200 to 599, inclusive.` (`L61` via catch-all `L148-154`).
- **`204 No Content`:** `body: null` succeeded (`status=204`, COEP/COOP set); non-null `body` (empty `ReadableStream`) **CONFIRMED CRASH** (`TypeError: Response constructor: Invalid response status code 204`).
- **Cold-cache `networkFirst` slow network (`2700 ms > 2500 ms`):** **CONFIRMED DOUBLE-FETCH** on both `index.html` (`call #1` at `1 ms`, timeout at `2500 ms`, un-aborted `call #2` at `2504 ms`, `L135`) and `index.js` (`2 ms` & `2503 ms`).
- **Offline navigate `/` after `install`:** **MISSED** cached `index.html` and fell back to `index.offline.html`, whereas `/index.html` returned `index.html`.

#### 2. Live Headless Chromium CDP Probe (`F-12`, `F-28`, WCAG 2.2; Brave `155.1.97.56` + `python3 -B -m http.server`, `.wasm`/`.pck` blocked to isolate shell)
- **Fullscreen `__kiepieFsDone` lockup (`F-12`):** **CONFIRMED** — `afterFirstEnter: {reqCalls:1, fsActive:true, want:true, done:true}` → `afterExit (__kiepieSetFullscreen(false)): {reqCalls:1, fsActive:false, want:false, done:true}` → `afterSecondEnter (__kiepieSetFullscreen(true)): {reqCalls:1, fsActive:false, want:true, done:true}` (permanently locked out).
- **Splash MP4 pre-guard fetch (`F-28`):** **CONFIRMED** — `web-assets/kiepie-quad-splash.mp4` (`type: "Media", initiator: "parser"`) was fetched over the network for BOTH returning visitors (`kiepie_splash_seen_v1="1"`) AND `prefers-reduced-motion: reduce` (`#splash` removed from DOM only *after* injection).
- **`aria-label` truncation (`F-28`):** **CONFIRMED** — parsed DOM is `<button id="splash-skip" type="button" aria-label="Skip" intro="">Tap to skip</button>` (`getAttribute('aria-label') === "Skip"`, `hasAttribute('intro') === true`).
- **Leaked `keydown` listener (`F-28`):** **CONFIRMED** via CDP `DOMDebugger.getEventListeners(document)` — `1` capture-phase `keydown` listener (`index.html:80`) persisted after `Escape` dismiss + `500 ms`.
- **COOP/COEP & Viewport:** `vercel.json` is absent; cold load runs with `window.crossOriginIsolated === false` (`SharedArrayBuffer` unavailable until SW activates & reloads). Duplicate `<meta name="viewport">` (`L5`, `L80`) both disable zoom (`user-scalable=no`, `maximum-scale=1`).
- **WCAG 2.2 AA Contrast Audit (normal text threshold `>= 4.5:1`):**
  - `body::after` hint strip (`rgba(232,238,255,.45)` on `#060a1c`, `11px`): **`4.03:1` (FAIL AA)**.
  - `#splash-skip` (`#ffd16b` on `rgba(6,10,28,.55)` over bright video frame, `12px`): **`3.04:1` (FAIL AA)** (`13.66:1` over `#060a1c`).
  - `body::before` `KIEPIE QUAD` (`6.23:1`), `.splash-brand` (`7.54:1`), `#status-notice` (`7.54:1`): **PASS**.

---

### A.4 Dead-Code, Unused-Asset & Authored-but-Unwired Sweep

*(Note: `dead_export_sweep.py --src src` targets JS/TS and exited 2; custom AST/regex sweeps covered `godot/src/`, `godot/assets/`, `godot/tools/`, and `src/`.)*

#### Authored-but-Unwired Features (Highest Leverage — Wire, Don't Rebuild)
| Category | Asset / Symbol | Location | Evidence |
| :--- | :--- | :--- | :--- |
| **UI Audio** | `ui_click.wav` + `Sfx.play_ui()` + `audio/ui` slider | `Sfx.gd:24,91`, `SettingsMenu.gd:61` | **0 call sites** in `godot/src/`; Settings UI volume slider controls an empty bus |
| **Turbo Audio** | `turbo.wav` (`Sfx.SAMPLES["turbo"]`) | `Sfx.gd:22`, `KiepieBike.gd:306` | **0 `Sfx.play("turbo")` calls**; turbo is completely silent |
| **3D Spatial Audio** | `Sfx.play_3d()` | `Sfx.gd:71` | **0 call sites**; all combat/world SFX play 2D non-positional |
| **VFX** | `VfxFactory.steam_vent()` | `VfxFactory.gd:570` | **0 call sites** anywhere *(note: `scorch()` IS called internally at `:773`)* |
| **Settings Keys** | `gameplay/kill_feed`, `network/auto_join` | `Settings.gd:40,43` | **0 external reads/writes** (`MatchHud.add_kill` never checks `kill_feed`) |
| **Remote Turbo VFX** | `"t": turbo_active` net field | `ArenaNet.gd:92`, `NetworkedBike.gd:91` | Broadcast at 15 Hz, never read by `NetworkedBike.apply_state()` |
| **Lobby Rule** | `friendly_fire` | `LobbyMenu.gd:26`, `MockBackend.gd:18` | Present in `DEFAULT_SETTINGS`, never read in combat |

#### Unused Functions, Signals, Assets & Tools
- **Unused GDScript functions (0 prod refs):** `VehicleRegistry.fire_sfx()` (`:79`), `MatchState.reset_time_limit_guard()` (`:71`), `MatchState.player_count()` (`:139`), `MatchState.leader_id()` (`:148`), `MatchState.respawn_remaining()` (`:197`), `TaloBackend._iso_from_unix()` (`:851`), `MockBackend.simulate_host_loss()` (`:178`).
- **Unused fields/consts:** `NetworkedBike._ring` (`:18`), `MainMenu.SCENE_ARENA` (`:8`).
- **Unconnected signals (0 prod `.connect`):** `DestructibleBuilding.smashed`, `Projectile.hit`, `BananaProjectile.hit`, `SideCannons.fired` (2 test refs), `LobbyService.joined`.
- **Unused `godot/assets/` PNGs (0 refs in `.gd`/`.tscn`/`.glb`; textures already embedded in `.glb`):** `Kiepie_Bike_decal_blaster.png`, `Kiepie_Bike_decal_gaming.png`, `Kiepie_Bike_number_plate.png`, `Pogo_Princess_decal_princess.png`.
- **Unreferenced `godot/tools/` (manual utilities documented in docs):** `gen_arena_textures.py`, `screenshot.gd`, `screenshot_gameplay.gd`.
- **Unused Blender Python functions (`src/`):** `src/build_pogo_princess.py:154 face_assign()`, `src/qb_core.py:410 _cap_holes()`, `src/qb_core.py:472 mirror_x()`.

---

### A.5 11th Lens — Engagement & Game Feel Feedback Matrix

#### Core Player Verb Coverage Matrix
| Player Verb | Visual (VFX / HUD) | Audio (SFX) | Kinesthetic (Shake / FOV / Hitstop / Squash) | Reduced-Motion Fallback | Gaps / Broken Loops |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Accelerate / Turbo** | Exhaust flames + jet plume + roost `>42 km/h` | **MISSING** (`turbo.wav` unwired; engine loop fixed pitch `1.0`) | FOV kick `+9°` (`FollowCam.gd:76`) | FOV kick disabled | **No turbo SFX**; `Sfx.start_engine(bike)` handle discarded (`CombatController.gd:252`), so engine pitch never tracks RPM/speed/death |
| **Drift / Brake** | `tire_smoke` `>3 m/s` (`CombatController.gd:101`) | `scrape` (1.6 s CD, `KiepieBike.gd:356`) | None | `tire_smoke` suppressed | Smoke requires `brake` action (not reverse-brake) |
| **Jump / Land** | Hard (`vy<-3.5`): `dust_ring`; soft: none | Soft (`-3.5..-1.5`): `dink`; **Hard: MISSING** | Hard: shake `0.08`; Pogo: continuous squash | Shake/ring gated; **Pogo squash NOT gated** | **Hard landing is silent** (`dink` is in `elif`, skipped when `vy < -3.5`) |
| **Dodge / Cartwheel** | `dust_puff` (`KiepieBike.gd:451`) | **MISSING** | Impulse leap + roll spin; no cam shake | Puff gated; roll physics unchanged | **No dodge SFX**, no HUD cooldown cue |
| **Cannon / Banana Fire** | Muzzle flash + brass casing + tracer/banana | `fire` / `pop` (2D, ±5% jitter) | Shake `0.10` (`SideCannons.gd:107`) | Shake/casing gated | Strong 3-channel coverage |
| **Hit Confirm** | Impact VFX + `HitMarker` `×` tween | Hazard: `impact`; **Remote bike: MISSING** | None | Static 0.12 s flash | **No hit-confirm audio** when shooting rival bikes (`CombatController.gd:305`) |
| **Kill** | Explosion + kill feed + `RAMPAGE ×N` (streak `>=3`) | `kill` (`ArenaNet.gd:124`) | Hitstop `0.28x` for 60 ms (`ArenaNet.gd:151`) | Hitstop skipped; static banner | Strong 3-channel coverage |
| **Take Damage** | Impact VFX + damage number + red vignette + armor bar color | `impact` (`CombatController.gd:157`) | Shake `0.18` | Static 0.15 s vignette; no shake | **Shield block** (`:150`) has VFX only — **no block SFX/shake** |
| **Die / Respawn** | Explosion → hide → countdown → `shield_pulse` | `explosion` / `respawn` | Shake `0.55` + kill-cam spectate | Shake gated | Dead bike keeps running looping engine SFX |
| **Pickup** | `pickup_burst` + `shield_pulse` + banner | `pickup` (`CombatController.gd:129`) | None | Static banner | No active buff timer bar on HUD (shield/rapid/overdrive) |
| **Building Smash** | 14 debris RigidBodies + `smash_burst` + HUD counter | **MISSING** | Shake `0.32` (`DestructibleBuilding.gd:160`) | Shake/burst gated | **Completely silent** (`DestructibleBuilding.gd` never calls `Sfx`) |
| **Drum Chain** | `explosion` + staggered 0.18 s chain (`FuelDrum.gd:75`) | **MISSING** (only initial hit plays `impact`) | **MISSING** (no shake unless player damaged) | Burst gated | **Chained explosions have zero explosion SFX and zero camera shake** |

#### Progression, Loop Dead-Ends & Accessibility Gaps
- **Rematch Dead-End (`MatchHud.gd:77-82`):** `ResultPanel/PlayAgainBtn` and `LeaveBtn` both connect to `_on_leave_match()`, kicking players out of the lobby to `MainMenu.tscn`.
- **Zero Haptics & Persistence:** `0` references to `navigator.vibrate` / `Input.vibrate_handheld`; no saved wins, smash records, or unlocks (`localStorage` stores only `kiepie_splash_seen_v1`).
- **Reduced-Motion Disconnect:** `index.html:80` checks `prefers-reduced-motion: reduce` for the HTML splash, but `Settings.gd` never reads `matchMedia('(prefers-reduced-motion: reduce)')` on Web boot (defaults `false`). Inside Godot, `PogoVisual.gd` (continuous bounce/squash/belly-slosh) and `Pickup.gd:118` (continuous spin/bob) have **no `Settings.reduced_motion()` guard**.
- **Contrast & Forced-Colors:** `UiTheme.gd` achieves `>=8.2:1` contrast on `BG`, but **`prefers-contrast: more` and `forced-colors: active` have 0 CSS rules** in `index.html` / `export_presets.cfg`.
- **Colorblind Differentiation:** Pickups (`Pickup.gd:22-34`) are identical `TorusMesh` shapes differentiated **only by color** (cyan/yellow/green/magenta). Radar (`MatchHud.gd:654-672`) uses same-shape circles (green local vs custom-colored remote; a rival choosing green collides visually with self).

---

### A.6 SARIF 2.1.0 Telemetry Summary

Artifact written to [`docs/audits/kiepie-quad-surgical-audit-2026-11-19.sarif`](kiepie-quad-surgical-audit-2026-11-19.sarif) (validated JSON, SARIF `2.1.0`, schema `https://json.schemastore.org/sarif-2.1.0.json`, 1 run `surgical-audit-preflight`).

| Scope | Total | `error` (`SA-SILENT-CATCH`) | `warning` (`SA-GOD-FILE`) | `warning` (`SA-HIGH-COMPLEXITY`) | `note` (`SA-HOT-LOOP`) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **All Scanned Files** | **192** | 8 | 16 | 93 | 75 |
| **First-Party (`godot/src`, `godot/tools`, `src`)** | **95** | 4 | 9 | 54 | 28 |
| Vendored / Export (`godot/addons`, `index.*`, `web/`) | 97 | 4 | 7 | 39 | 47 |

- **First-Party `SA-SILENT-CATCH` (`error`, 4 files):** `src/qb_core.py` (7), `godot/src/ui/MobileTextInput.gd` (3), `godot/src/core/Settings.gd` (1), `src/build_quad.py` (1).
- **First-Party `SA-GOD-FILE` (`warning`, 9 files `>400` eff LOC):** `VfxFactory.gd` (806), `TaloBackend.gd` (715), `build_arena.gd` (671), `MatchHud.gd` (552), `qb_body.py` (497), `qb_core.py` (487), `build_testride.gd` (462), `TouchControls.gd` (437), `build_menus.gd` (416).

---

## Addendum B — Remediation Closure & Final Health Score

Executed post-audit remediation across Phases 1–3 (`net-fixer`, `gameplay-fixer`, `ui-web-fixer`, `polish-fixer`) and verified end-to-end by `remediation-verifier` and `release-shepherd` on 2026-11-19.

### B.1 Finding Closure Ledger

| Severity Tier | Initial | Resolved | Remaining Open | Open Backlog IDs |
| :--- | :---: | :---: | :---: | :--- |
| **P0 — Critical (`-18`)** | 1 | **1 / 1** (`F-01`) | **0** | *(none)* |
| **P1 — High (`-8`)** | 13 | **13 / 13** (`F-02`–`F-14`) | **0** | *(none)* |
| **P2 — Medium (`-3`)** | 19 | **14 / 19** (`F-15`–`F-17`, `F-21`–`F-29`, `F-32`, `F-33`) | **5** | `F-18` (SFX generator filter/tails), `F-19` / `F-30` / `F-31` (Blender `src/` geometry/pivots), `F-20` (`TaloBackend` host hand-off / channel resurrection) |
| **P3 — Low (`-1`)** | 6 | **4 / 6** (`F-34`, `F-35`, `F-36`, `F-38`) | **2** | `F-37` (`build_testride.gd` cone/group polish), `F-39` (God files, CC hotspots, silent catches & media/doc bloat) |
| **Total** | **39** | **32 / 39 (82.1%)** | **7** | `5 P2` + `2 P3` (0 P0, 0 P1) |

- **Additional 11th-Lens Game-Feel & WCAG AA Fixes Landed:**
  - Wired `Sfx.play("turbo")` on turbo activation, hard-landing `dink`/`impact` SFX, and `explosion` SFX on `DestructibleBuilding.smash()` and `FuelDrum.ignite()`.
  - Fixed WCAG 2.2 AA contrast failures in `index.html` and `godot/export_presets.cfg` in lockstep (`body::after` opacity `0.68` → `8.04:1`; `#splash-skip` opacity `0.82` over white → `8.37:1`).

### B.2 Final Deterministic Health Score

Using the baseline formula ($\text{Scale} = \sqrt{1000 / \max(500, 14991)} = 0.258276$):

- **Remaining Defect Weight:** $D_{\text{raw}} = (18 \times 0) + (8 \times 0) + (3 \times 5) + (1 \times 2) = \mathbf{17}$
- **Scaled Defect Deduction:** $D_{\text{scaled}} = 17 \times 0.258276 = \mathbf{4.39}$
- **Test Penalty ($P_{\text{test}}$):**
  - Conservative baseline ($M_{\text{kill}} = 39.6\%$ / `19/48`): $P_{\text{test}} = 9.06 \implies S_{\text{health}} = \text{round}(100 - 4.39 - 9.06) = \mathbf{87 / 100}$
  - Updated with new regression gates ($M_{\text{kill}} = 52.1\%$ / `25/48`): $P_{\text{test}} = 7.19 \implies S_{\text{health}} = \text{round}(100 - 4.39 - 7.19) = \mathbf{88 / 100}$
- **Final Score & Risk Level:** **`88 / 100`** (`87 / 100` conservative) — **`LOW`** Vibe-Debt Risk Level (**`+44` to `+45` pts** from `43 / 100` `HIGH`).

### B.3 Release Verification Proof

1. **Full 26-Gate Suite (`bash godot/tools/run_gates.sh --no-build`):**
   - **Result:** `GATE SUITE: PASS — all 26 gates green` (`exit 0`), including `scene_sync` (6/6 scenes), `audit_regressions` (20/20), `touch_multitouch` (xvfb, `0 failure(s)`), and `gdunit` (`6 tests cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans | PASSED`).
2. **Dry-Run Web Export (`bash godot/tools/deploy_web.sh`, no `--apply`):**
   - **Result:** `exit 0` (`web bundle complete`, `DRY RUN only`).
   - **Gates:** Full rebuild + `26/26` PASS.
   - **Talo Key Injection:** `inject_talo_key: wrote godot/addons/talo/settings.cfg (135 char game key)` (atomic `0600` + JWT regex validated).
   - **Bundle Size:** `web/index.pck = 3,104,240 bytes` (`2.96 MiB`, well under the `4 MB` abort ceiling).
   - **Service Worker Patch:** `patch_web_sw: patched .../web/index.service.worker.js (wasm=fe5cebc59075 pck=2d0c265bbd4c)`.

