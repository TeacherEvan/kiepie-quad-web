# Surgical Audit Report: Kiepie Quad — Frontend (`kiepie-quad-web`)

| Audit Metadata | Specification |
| :--- | :--- |
| **Audit Date** | 2026-11-19 |
| **Audited Scope** | **Frontend Gameplay, 3D Track/Physics/Camera, Weapons, UI/HUD, Touch Controls, Web Shell, Scene Builders & Blender Asset Pipeline** (`54` impl/tool files + `1` HTML file [`198` lines `index.html`], `20` test/gate files, `15,573` effective LOC [`13,352` impl + `2,023` test + `198` HTML]; covers `godot/src/{KiepieBike,FollowCam,Hud,TouchControls,TouchCapture,AnalogSteer,AnalogDrive,DestructibleBuilding}.gd`, `godot/src/game/*` [gameplay], `godot/src/ui/*`, `godot/src/audio/Sfx.gd`, `godot/tools/build_*.gd`, `godot/export_presets.cfg`, `index.html`, `web-assets/*`, and `src/*.py`). Audited on clean `HEAD` `0f3a053a0f70179971f20fe3b5fe2f4075d2f654`. |
| **Tech Stack & Runtime** | Godot 4.3 (GDScript, WebGL2 `gl_compatibility`, WebAssembly), HTML5/CSS/Vanilla JS Web shell (`#splash`, `#victory-splash`, fullscreen & mobile VK bridges), Python 3 / Blender 5.3 `bpy`, FFmpeg MP4/AAC pipeline. |
| **Pre/Post Audit SHA-256** | `17033d6846568f33 / 17033d6846568f33 (VERIFIED ZERO MUTATION)` (`17033d6846568f335797b39dc2fd8eb0e431be3be9aac01a0914bd75def24a15`) |
| **Deterministic Health Score** | **`58 / 100`** (`D_raw = 131`, `Scale = 0.2534`, `P_test = 8.37`, `M_kill = 44.2%`) |
| **Vibe-Debt Risk Level** | **`CRITICAL`** (`N_P0 = 2 >= 2`; per rubric `CRITICAL` when `S_health < 40` OR `N_P0 >= 2`) |
| **Live Verification** | **Pass 2.5 Deep Runtime, `xvfb-run` Multi-Viewport & Node DOM Verified** — Live Godot 4.3 headless, `xvfb-run` real-window (`390×843`, `843×390`, `1280×720`), Node DOM sandbox, WCAG 2.2 luminance math, and 11th-Lens unwired sweeps empirically reproduced `F-P0-1`, `F-P0-2`, `F-P1-1`, `F-P1-2`, `F-P1-3`, `F-P1-4`, `F-P1-6`, `F-P1-7`, `F-P1-8`, and `F-P2-9`. |
| **SARIF 2.1.0 Deliverable** | [`kiepie-quad-frontend-surgical-audit-2026-11-19.sarif`](kiepie-quad-frontend-surgical-audit-2026-11-19.sarif) (`23` structured findings: `10` error, `9` warning, `4` note) |

---

## 1. Executive Architecture & Vibe-Debt Triage

The core quad physics (`KiepieBike._integrate_forces`), dual-analog multi-touch state machine (`TouchControls` + `TouchCapture`, 4/4 mutants killed, `0 px²` pad overlap verified on real `390×843` and `843×390` windows), and Nardus bird-flap animation (`PogoVisual.gd`) are structurally solid, and every primary UI color token passes WCAG 2.2 AA/AAA contrast (`4.88:1`–`14.83:1`). However, the Death Race track, heavy-weapon arsenal, and Victory Splash shell introduced **two P0 playability/crash defects** and **eight P1 gameplay, physics, layout, camera, and WebGL2-budget defects**. Most severely: (1) all three Death Race hazard-pit jump ramps (`Ramp0`, `Ramp2`, `Ramp4`) are **rotated 180° backwards** (`launch_dir · travel_dir = -1.00`, live-reproduced), placing their 0.9 m vertical yellow back-wall directly in front of oncoming racers before every lava pit (`F-P0-2`); (2) both `RocketProjectile._detonate()` and `MeteorStrike._detonate()` invoke `db.call("smash", Vector3(...))` on 0-arg `DestructibleBuilding.smash()`, throwing a live `SCRIPT ERROR` and leaving every building intact (`F-P0-1`, live-reproduced). Furthermore, `TrackLoop0`/`TrackLoop1`'s `LoopZone` intrudes into the flat center lane (`z = ±44`), tilting flat-road bikes `36.9°` with `24 m/s²` radial pull (`F-P1-8`); dying after clearing checkpoints teleports racers **78.99 m backward** to the starting grid (`F-P1-1`); `MatchHud._relayout()` overlaps `KillFeed` over `Radar` on portrait mobile (`92×22 px`) and over `WeaponLabel`/`Banner` on landscape & desktop (`F-P1-2`); `FollowCam` throws `look_at() failed` inside 360° loops (`F-P1-6`); `DeathRace.tscn` starts with **11 idle `OmniLight3D`s** before a single shot (WebGL2 limit = 8, `F-P1-7`); and the Web Victory Splash hardcodes `muted`, leaks `keydown` listeners, and lets `Escape` kick the player out of the match (`F-P1-4`). The 11th Lens also surfaced 5 authored-but-unwired engagement features (`Sfx.play_3d()`, `gameplay/kill_feed`, dead-end `PlayAgainBtn`, 0 haptics, 0 high-contrast/forced-colors CSS).

| Severity Tier | Count | Deduction Weight | Primary Failure Domains |
| :--- | :--- | :--- | :--- |
| **P0 — Critical (Crash / Data Loss / Security / Leak)** | **2** | `-18 pts ea` (`-36`) | `RocketProjectile.gd` / `MeteorStrike.gd` → `DestructibleBuilding.smash()` 0-arg runtime `SCRIPT ERROR` crash + double-smash (`F-P0-1`); `build_deathrace.gd` all 3 hazard-pit jump ramps (`Ramp0`, `Ramp2`, `Ramp4`) rotated 180° backwards (`dot = -1.00`, vertical wall facing racers) + inverted landing ramps (`F-P0-2`) |
| **P1 — High (Frame-Budget / Race / Logic Bug)** | **8** | `-8 pts ea` (`-64`) | `CombatController._respawn()` overwrites Death Race checkpoint spawn (`F-P1-1`); `MatchHud._relayout()` desktop, landscape & portrait `KillFeed` overlaps (`F-P1-2`); `RaceTracker.gd` guest victory split-brain, post-`await` exit crash & solo `Match.players` leak (`F-P1-3`); `index.html` / `export_presets.cfg` / `MatchHud.gd` muted victory video, `Escape` double-action, zero tap grace & leaked `keydown` (`F-P1-4`); `SideCannons.gd` non-`dt` reticle spin & `_process()` raycast allocs (`F-P1-5`); `FollowCam.gd` 360° loop `look_at()` collinearity error (`F-P1-6`); WebGL2 uncapped `OmniLight3D` saturation (`DeathRace=11`, `Arena=9` idle vs limit 8) (`F-P1-7`); `build_deathrace.gd` `LoopZone` & `SupportPylon_L` intruding into flat center straightaway (`F-P1-8`) |
| **P2 — Medium (God File / Split-Brain State / Debt)** | **9** | `-3 pts ea` (`-27`) | `SideCannons.fire()` pre-`await` SFX/VFX/cooldown & practice broadcast leak (`F-P2-1`); `KiepieBike.reset_bike()` stale `loop_up` + `MatchHud`/`LobbyMenu` teardown gaps (`F-P2-2`); dead `on_hit` fields & per-shot `ParticleProcessMaterial` allocs (`F-P2-3`); `MobileTextInput.gd` 60–120 Hz mobile JS polling when closed (`F-P2-4`); duplicate `<meta name="viewport">` blocking WCAG zoom (`F-P2-5`); right-analog diagonal swap+dodge overlap (`F-P2-6`); unguarded `Color.html()` & `_fx_holder` root leak (`F-P2-7`); God files (`build_deathrace.gd`, `VfxFactory.gd`, `MatchHud.gd`, `qb_core.py`) & `18+ MB` tracked `renders/` PNGs (`F-P2-8`); 11th-Lens authored-but-unwired engagement & accessibility gaps (`F-P2-9`) |
| **P3 — Low (Magic Constants / DX / Portability)** | **4** | `-1 pt ea` (`-4`) | `Projectile.gd` nose pellet placed at tail `+Z` (`F-P3-1`); `HazardPit.gd` private `_invuln_until` write & dead-bike explosion tick (`F-P3-2`); linear `delta * k` lerps in `FollowCam`/`KiepieBike` (`F-P3-3`); `LoopZone.gd` hardcoded world `+Y` center offset (`F-P3-4`) |

**Health Score Formula Verification:**
- $D_{\text{raw}} = (18 \times 2) + (8 \times 8) + (3 \times 9) + (1 \times 4) = 131$
- $\text{Scale} = \sqrt{1000 / \max(500, 15573)} = 0.25340 \implies D_{\text{scaled}} = 33.20$
- $P_{\text{test}} = 15 \times (1 - 44.23 / 100) = 8.37$
- $S_{\text{health}} = \max(0, \text{round}(100 - 33.20 - 8.37)) = \mathbf{58 / 100}$ (**CRITICAL** due to `N_P0 = 2 >= 2`)

### High-Risk File Telemetry Hotspots

| File Path | Effective LOC | Branch Density / Structure | Silent Catches | Primary Vibe-Debt Signature |
| :--- | :--- | :--- | :--- | :--- |
| `godot/tools/build_deathrace.gd` | `917` | `0.01` | `0` | Backwards hazard-pit jump ramps (`F-P0-2`), flat-lane `LoopZone` intrusion (`F-P1-8`), 10 pickup `OmniLight3D`s |
| `src/qb_core.py` | `487` | `0.03` | `7` | Blender utility God module with 7 bare/silent exception handlers |
| `godot/src/game/VfxFactory.gd` | `830` | `0.02` | `0` | God VFX factory; uncapped `explosion()` and `underglow()` `OmniLight3D`s |
| `godot/src/ui/MatchHud.gd` | `653` | `0.08` | `0` | God HUD; desktop/landscape/portrait `KillFeed` overlaps, missing `_exit_tree`, unguarded `JavaScriptBridge`, dead `PlayAgainBtn` |
| `godot/src/ui/MobileTextInput.gd` | `373` | `0.03` | `3` | Mobile 60–120 Hz synchronous `JavaScriptBridge.eval()` poll loop while VK closed |
| `godot/src/TouchControls.gd` | `480` | `0.07` | `0` | Diagonal right-analog pull triggers swap + dodge simultaneously |
| `godot/src/game/SideCannons.gd` | `453` | `0.10` | `0` | Non-`dt` reticle spin, `_process()` raycast allocs, pre-`await` VFX/cooldown consumption, practice broadcast |
| `godot/src/KiepieBike.gd` | `445` | `0.11` | `0` | `reset_bike()` omits `loop_up` clear; `_exit_tree()` omits `Settings.changed` disconnect |
| `godot/src/game/CombatController.gd` | `282` | `0.11` | `0` | `_respawn()` overwrites Death Race checkpoint spawn with random starting grid `SpawnPoint` |
| `godot/src/game/RocketProjectile.gd` / `MeteorStrike.gd` | `257` / `256` | `0.17` / `0.16` | `0` | `smash(Vector3)` 0-arg crash (`F-P0-1`), dead `on_hit`, uncapped `OmniLight3D` & `ParticleProcessMaterial` |
| `index.html` | `198` (HTML/CSS/JS) | — | `4` (inline JS) | Muted victory audio, `Escape` leak to Godot, instant mobile dismiss, leaked `keydown` listener, duplicate viewport meta |

---

## 2. The 10-Principal-Engineer Deep Audit

### Lens 1: Systems Architect

- **`[F-P0-1]` Runtime Argument-Count Crash (`smash(Vector3)` vs `func smash()`) Breaks Rocket & Meteor Building Destruction** — `godot/src/game/RocketProjectile.gd:L240-L242,L282-L287`, `godot/src/game/MeteorStrike.gd:L280-L285`, `godot/src/DestructibleBuilding.gd:L92-L94`
  - **Root Cause Mechanism:** `DestructibleBuilding.gd:L92` defines `func smash() -> void:` with **zero parameters** and no `if not _intact: return` guard. Both `RocketProjectile._detonate()` (lines 242 and 287) and `MeteorStrike._detonate()` (line 285) call `db.call("smash", Vector3(...))` passing a 1-argument impulse vector.
  - **Deterministic Trigger & Failure Mode:** Detonating any Rocket or Meteor within blast radius of a `DestructibleBuilding` throws a GDScript runtime error and leaves the building completely intact. Even after fixing the signature, a direct Rocket hit invokes `smash()` twice (L242 + L287), spawning 28 debris chunks and double-counting `HUD.register_smash()`. **Live Godot 4.3 reproduction confirmed:** `SCRIPT ERROR: Invalid call to function 'smash (via call)' in base 'StaticBody3D (DestructibleBuilding.gd)'. Expected 0 arguments.` and `F-P0-1 DestructibleBuilding intact after Meteor _detonate: true`.
  - **Surgical Fix Specification:** Update `DestructibleBuilding.smash(impulse: Vector3 = Vector3.ZERO) -> void:` with an immediate `if not _intact: return` guard at line 93 (applying `impulse * 0.30` to `chunk.linear_velocity`), and deduplicate direct vs AOE hits in `RocketProjectile._detonate()`.

- **`[F-P1-1]` `CombatController._respawn()` Overwrites Death Race Checkpoint Respawns** — `godot/src/game/CombatController.gd:L204-L220` vs `godot/src/game/RaceTracker.gd:L88-L92`
  - **Root Cause Mechanism:** `RaceTracker` updates `bike.set_spawn(checkpoint_xf)` at every cleared checkpoint so dying in a Hazard Pit or combat returns the rider to their last cleared checkpoint. However, `CombatController._respawn()` unconditionally picks a random `spawn_point` node from the starting grid, builds `Transform3D(Basis.IDENTITY, pos)`, and overwrites `bike.set_spawn(t)` before calling `bike.reset_bike()`.
  - **Deterministic Trigger & Failure Mode:** **Live Godot 4.3 reproduction confirmed:** `F-P1-1 Checkpoint0 pos=(58, 0.65, -16) | respawn pos=(-17, 0.6, -40.8) | dist=78.99m`.
  - **Surgical Fix Specification:** When a `race_tracker` node exists in the scene tree (Death Race), preserve `bike._spawn` (the last cleared checkpoint transform) inside `_respawn()` instead of picking a random `spawn_point`.

- **`[F-P2-3]` Dead `on_hit` Callables on `RocketProjectile` & `MeteorStrike`** — `godot/src/game/RocketProjectile.gd:L18`, `godot/src/game/MeteorStrike.gd:L22`, `godot/src/game/SideCannons.gd:L466-L467`, `godot/src/game/ArenaNet.gd:L260-L261`
  - **Root Cause Mechanism:** Both heavy weapons declare `var on_hit: Callable` and callers bind `hit_callback`, yet neither script ever invokes `on_hit`.
  - **Deterministic Trigger & Failure Mode:** Misleads maintainers into expecting centralized hit hooks in `CombatController._on_projectile_hit()`.
  - **Surgical Fix Specification:** Remove unused `on_hit` properties and dead assignments.

### Lens 2: Frame-Budget & Performance

- **`[F-P1-7]` WebGL2 `OmniLight3D` Budget Saturation Before First Shot (`DeathRace=11`, `Arena=9` vs Limit 8)** — `godot/src/game/Pickup.gd:L70-L75`, `Projectile.gd:L159-L164`, `BananaProjectile.gd:L185-L190`, `RocketProjectile.gd:L171-L176`, `MeteorStrike.gd:L178-L183`, `VfxFactory.gd:L707-L711,L981-L985`
  - **Root Cause Mechanism:** Every `Pickup` creates a permanent `OmniLight3D` (`10` in DeathRace, `8` in Arena) plus bike underglow (`+1`), and every bolt/banana/rocket/meteor/explosion creates an uncapped `OmniLight3D`. Godot 4.3's `gl_compatibility` (WebGL2) forward renderer caps omni lights per surface at **8**.
  - **Deterministic Trigger & Failure Mode:** **Live Godot 4.3 reproduction confirmed:** `Idle OmniLight3D count BEFORE any shots/explosions: DeathRace=11, Arena=9 (WebGL2 limit = 8 per surface!)`. Active firefights push past 30–40 lights, causing lighting pop-out and fragment-shader stalls on mobile GPUs.
  - **Surgical Fix Specification:** Remove `OmniLight3D` from `Pickup` (emissive torus already blooms) and rapid-fire `Projectile`/`BananaProjectile`; cap explosion/rocket/meteor lights through `VfxFactory._cap_group(..., "vfx_light", MAX_IMPACT_LIGHTS)`.

- **`[F-P2-4]` Mobile Web `MobileTextInput._process()` 60–120 Hz Synchronous JS Bridge Polling** — `godot/src/ui/MobileTextInput.gd:L66-L76`
  - **Root Cause Mechanism:** On mobile Web (`_mobile_like == true`), every attached `LineEdit` executes `JavaScriptBridge.eval("window.__kiepieVk.poll(...)", true)` every render frame even when the virtual keyboard overlay is closed.
  - **Deterministic Trigger & Failure Mode:** 60–120 synchronous WASM↔JS boundary crossings/sec idle on mobile menus.
  - **Surgical Fix Specification:** Throttle idle polling to 5–8 Hz (like `Settings.gd:L152-L155`) and ramp to 30 Hz only while `window.__kiepieVk.isOpen()` is `true`.

- **`[F-P2-8]` Per-Shot `ParticleProcessMaterial` Allocations & `18+ MB` Tracked `renders/` Media Bloat** — `godot/src/game/Projectile.gd:L171`, `BananaProjectile.gd:L197`, `RocketProjectile.gd:L183`, `MeteorStrike.gd:L190`, `renders/*.png`
  - **Root Cause Mechanism:** Every spawned projectile allocates a new `ParticleProcessMaterial`; `git ls-files` tracks >18 MB of regenerable `renders/*.png` QA screenshots.
  - **Deterministic Trigger & Failure Mode:** Continuous GC pressure during twin-barrel 22 shots/sec firefights; bloated clone/Vercel repo transfer.
  - **Surgical Fix Specification:** Share one `static var` `ParticleProcessMaterial` per projectile class and untrack/gitignore regenerable `renders/*.png`.

### Lens 3: Mathematical, Physics & Algorithmic

- **`[F-P0-2]` All 3 Death Race Hazard-Pit Jump Ramps Rotated 180° Backwards (`dot = -1.00`)** — `godot/tools/build_deathrace.gd:L135-L143,L720-L771`
  - **Root Cause Mechanism:** In `_add_ramp()` (`L722,L743`), `rot_x = -rot_deg.x` lifts the local **`+Z`** end of the plank up (supported by `stand` at `+stand_z`), so a ramp launches bikes along its **local `+Z` axis** (`basis.z`). However, `build_deathrace.gd` rotated the three pit launch ramps 180° backwards: `Ramp0` (`rot_y = 180°` → launches `-Z` against `+Z` travel), `Ramp2` (`rot_y = +90°` → launches `+X` against `-X` travel), and `Ramp4` (`rot_y = 0°` → launches `+Z` against `-Z` travel). Likewise, the three landing ramps (`Ramp1`, `Ramp3`, `Ramp5`) are flipped 180° so their high walls face away from the pits.
  - **Deterministic Trigger & Failure Mode:** **Live Godot 4.3 reproduction confirmed:**
    - `Ramp0: pos=(58, 0, 2) launch_dir=(-0, 0, -1) travel_dir=(0, 0, 1) dot=-1.00 (BACKWARDS WALL FACING RACER!)`
    - `Ramp2: pos=(22, 0, 44) launch_dir=(1, 0, -0) travel_dir=(-1, 0, 0) dot=-1.00 (BACKWARDS WALL FACING RACER!)`
    - `Ramp4: pos=(-58, 0, -2) launch_dir=(0, 0, 1) travel_dir=(0, 0, -1) dot=-1.00 (BACKWARDS WALL FACING RACER!)`
    Driving clockwise around the Death Race circuit slams racers headfirst into a 0.9 m vertical yellow support wall right before all three lava pits.
  - **Surgical Fix Specification:** Flip `rot_y` by 180° on all six pit ramps (`Ramp0: 0°`, `Ramp1: 180°`, `Ramp2: -90°`, `Ramp3: 90°`, `Ramp4: 180°`, `Ramp5: 0°`), rebuild `DeathRace.tscn`, and lock `launch_dir.dot(travel_dir) > 0.95` in `verify_deathrace.gd`.

- **`[F-P1-8]` `TrackLoop0`/`TrackLoop1` `LoopZone` & `SupportPylon_L` Intrude Into Flat Straightaway Center Lane (`z = ±44`)** — `godot/tools/build_deathrace.gd:L125-L127,L678,L697`
  - **Root Cause Mechanism:** `TrackLoop0` sits at `z = -47.2` with `rot_y = 90°` (local `X` maps to world `-Z`). Its `LoopZone` box has `size.x = 9.0` (`world z ∈ [-51.7, -42.7]`), and `SupportPylon_L` sits at `x = -5.2` (`world z = -42.0`). The flat center lane of `NorthStraight` is `z = -44.0` (mirrored on `SouthStraight` at `z = +44.0` for `TrackLoop1`).
  - **Deterministic Trigger & Failure Mode:** **Live Godot 4.3 reproduction confirmed:** `TrackLoop0 LoopZone center=(26, 8.5, -47.2) world_x=[16.2, 35.8] world_z=[-51.7, -42.7] (NorthStraight center z=-44.0!)` and `Flat-lane bike at (20, 0.5, -44) gets loop_up=(0.6, 0.8, -0) (tilt_from_UP=36.9 deg)`. Racers bypassing the loop on the flat straightaway get violently tilted `36.9°` and pulled upward/sideways by `24 m/s²` centripetal adhesion, then clip visually through `SupportPylon_L`.
  - **Surgical Fix Specification:** Shift `TrackLoop0` outward to `z = -51.5` (and `TrackLoop1` to `z = +51.5`), narrow `LoopZone` `zsh.size.x` to `5.6` (matching the `4.0 m` deck + helical pitch), place support pylons strictly outside the flat track (`z < -53` / `z > +53`), and gate `LoopZone` adhesion on `bike.global_position.y > 0.85` or deck proximity so flat-lane riders are untouched.

- **`[F-P1-5]` `SideCannons._update_aim_reticle()` Frame-Rate-Dependent Spin & `_process()` Physics Raycast Allocation** — `godot/src/game/SideCannons.gd:L199,L287-L303,L374-L376`
  - **Root Cause Mechanism:** `_aim_reticle.rotate_y(0.035)` omits `delta` (2.4× faster at 144 Hz than 60 Hz) and ignores `Settings.reduced_motion()`. `compute_meteor_target()` allocates a fresh `PhysicsRayQueryParameters3D` and calls `world.direct_space_state.intersect_ray()` inside `_process()` every render frame instead of `_physics_process()`.
  - **Deterministic Trigger & Failure Mode:** Variable-refresh speed drift + 60–120/s heap allocations + out-of-sync physics-space reads while Meteor is selected.
  - **Surgical Fix Specification:** Cache `_cached_meteor_target` in `_physics_process()` using a single reused `_aim_ray_query`, and rotate `_aim_reticle.rotate_y(2.1 * delta)` in `_process()` (guarded by `not Settings.reduced_motion()`).

- **`[F-P1-6]` `FollowCam.look_at(..., Vector3.UP)` Collinearity Error & Gimbal Flip Inside 360° Loops** — `godot/src/FollowCam.gd:L80-L87`
  - **Root Cause Mechanism:** `FollowCam._process()` unconditionally passes `Vector3.UP` to `look_at()` even when the bike climbs vertically (`basis.z ≈ ±Vector3.UP`).
  - **Deterministic Trigger & Failure Mode:** **Live Godot 4.3 reproduction confirmed:** `ERROR: Up vector and direction between node origin and target are aligned, look_at() failed. at: look_at_from_position (scene/3d/node_3d.cpp:948)`.
  - **Surgical Fix Specification:** Smoothly align camera `up` toward `_target.loop_up` when inside a `LoopZone`, with a collinearity fallback to `_target.global_transform.basis.y` whenever `absf(dir.normalized().dot(up)) > 0.96`.

- **`[F-P3-1]` `Projectile.gd` Leading-Edge Nose Pellet Placed at Tail (`+Z`)** — `godot/src/game/Projectile.gd:L142,L146`
  - **Root Cause Mechanism:** `Basis.looking_at(dir, up)` points local `-Z` forward, so `nose.position.z = 0.22` places the white-hot tip at the rear (compare `RocketProjectile.gd:L146`: `-0.36`).
  - **Surgical Fix Specification:** Change `Projectile.gd:L142` to `nose.position.z = -0.22`.

- **`[F-P3-3]` Linear `delta * k` Lerps in `FollowCam.gd` & `KiepieBike.gd`** — `godot/src/FollowCam.gd:L78,L83`, `godot/src/KiepieBike.gd:L419`
  - **Root Cause Mechanism:** `clampf(delta * follow_speed, 0.0, 1.0)` varies damping stiffness across 60 Hz vs 144 Hz displays.
  - **Surgical Fix Specification:** Replace with `1.0 - exp(-rate * minf(delta, 0.05))`.

### Lens 4: Concurrency, Async & Determinism

- **`[F-P1-3]` `RaceTracker.gd` Guest Victory Split-Brain, Post-`await` Scene-Exit Crash & Global `Match.players` Leak** — `godot/src/game/RaceTracker.gd:L44-L51,L120-L136`
  - **Root Cause Mechanism:** (1) On the final lap in multiplayer, a guest's `Match.register_lap(tok)` returns `{"ok": true, "pending": true}`; line 133 immediately triggers local Victory Splash before host arbitration. (2) Lines 121–124 perform two `await`s with no `is_inside_tree()` check afterward. (3) Solo mode writes into global `Match.players` (`L45`) and never cleans it up on `_exit_tree()`.
  - **Deterministic Trigger & Failure Mode:** **Live Godot 4.3 reproduction confirmed:** `F-P1-3 Solo DeathRace Match.players injected=["mock-host"] | STILL LEAKED after exit=["mock-host"]`. Photo-finish guests can see a false Victory Splash before host declares another winner.
  - **Surgical Fix Specification:** Guard `if not is_inside_tree(): return` after each `await`; only invoke `hud._on_match_finished(uid)` directly in solo/practice mode (not live `Match.is_playing()`); track `_injected_solo_player := true` and clear it in `_exit_tree()`.

- **`[F-P2-1]` `SideCannons.fire()` Premature SFX/VFX/Shake/Cooldown Before `await Match.issue_shot()` + Practice Broadcast Leak** — `godot/src/game/SideCannons.gd:L403-L445,L468,L498,L528`
  - **Root Cause Mechanism:** `fire()` locks the 5–6 s cooldown, plays SFX, shakes the camera, and reads `_muzzles[i].global_position` (missing `is_instance_valid` at `L425`) *before* `await Match.issue_shot()`; broadcasts `"shot"` even when `practice == true`.
  - **Deterministic Trigger & Failure Mode:** Empty token wastes a 5–6 s cooldown with phantom VFX/SFX; practice shots loop back on `MockBackend`.
  - **Surgical Fix Specification:** Guard `is_instance_valid(muzzle)` at `L425`, gate `Supabase.broadcast("shot", ...)` behind `if not practice:`, and refund `_cooldowns[active_weapon] = 0.0` if `token == ""`.

### Lens 5: Memory & Resource Lifecycle

- **`[F-P2-2]` Stale `loop_up` on `KiepieBike.reset_bike()`, Unhidden `RespawnOverlay` on Finish & Partial Signal Teardown** — `godot/src/KiepieBike.gd:L89,L96-L99,L439-L465`, `godot/src/ui/MatchHud.gd:L536-L550,L723-L730`, `godot/src/ui/LobbyMenu.gd:L84,L191-L200,L352-L355`
  - **Root Cause Mechanism:** `reset_bike()` never resets `loop_up = Vector3.ZERO` or `overdrive_active = false`; `MatchHud._on_match_finished()` leaves `RespawnOverlay` visible over `ResultPanel` if dead; `KiepieBike`, `MatchHud`, and `LobbyMenu` omit autoload signal disconnects in `_exit_tree()`, and `LobbyMenu` lacks `is_inside_tree()` guards after `await`.
  - **Surgical Fix Specification:** Clear `loop_up = Vector3.ZERO` in `reset_bike()`; hide `RespawnOverlay` and clear `_dead` in `MatchHud._on_match_finished()`; disconnect all autoload signals in `_exit_tree()` across all three scripts and guard post-`await` resumptions in `LobbyMenu`.

- **`[F-P2-7]` Detached `_fx_holder` Root Node Leak & Unguarded `Color.html()`** — `godot/src/game/CombatController.gd:L47,L322-L325`, `godot/src/game/SideCannons.gd:L391-L395`
  - **Root Cause Mechanism:** Fallback `_fx_holder` nodes added to `get_tree().root` are never freed in `_exit_tree()`; `CombatController.gd:L47` calls `Color.html()` unvalidated.
  - **Surgical Fix Specification:** Free `_fx_holder` in `_exit_tree()` and use `Color.from_string(Settings.player_color(), Color(1.0, 0.48, 0.12))`.

### Lens 6: Security & Trust-Boundary

- **`N/A — Covered in Backend Audit`:** Frontend Web shell escapes `winner_name` via `JSON.stringify()` (`MatchHud.gd:L559`) and writes via `.textContent` (`index.html:L80`) preventing DOM XSS; multiplayer authority trust boundaries are audited in [`kiepie-quad-backend-surgical-audit-2026-11-19.md`](kiepie-quad-backend-surgical-audit-2026-11-19.md).

### Lens 7: Reliability & Fault Tolerance

- **`[F-P1-4]` Victory Splash Audio Hardcoded `muted`, `Escape` Kicks Player to Menu, Instant Mobile Dismissal & Leaked `keydown` Listener** — `index.html:L80`, `godot/export_presets.cfg:L23`, `godot/src/ui/MatchHud.gd:L552-L561,L700`
  - **Root Cause Mechanism:** (1) `<video id=victory-video ... muted autoplay>` silences the synthesized AAC fanfare; (2) `onKey` omits `e.preventDefault(); e.stopPropagation()` so `Escape` propagates into Godot `MatchHud._unhandled_key_input` (`L700`) and exits to `MainMenu`; (3) `pointerdown` capture has zero grace delay against active mobile thumb input; (4) re-invoking `__kiepiePlayVictorySplash` removes `old` DOM without removing its `document.keydown` listener; (5) `MatchHud.gd:L558` omits `Engine.has_singleton("JavaScriptBridge")`.
  - **Deterministic Trigger & Failure Mode:** **Live Node DOM probe confirmed:** `{"victory_video_hardcoded_muted":true,"leaked_keydown_listeners_after_reentry":2,"leaked_listeners_remaining_after_escape":1,"escape_stopped_propagation_to_godot":false}`.
  - **Surgical Fix Specification:** Attempt unmuted `vid.play()` (respecting Settings mute flag) with `.catch(() => { vid.muted = true; return vid.play(); })`; stop propagation on `Escape`; require 600 ms grace before background `pointerdown` dismisses (always allow `#victory-skip` immediately); invoke prior `window.__kiepieDropVictory()` on re-entry; guard `Engine.has_singleton("JavaScriptBridge")` in `MatchHud.gd`. Sync both `export_presets.cfg` and `index.html`.

- **`[F-P3-2]` `HazardPit.gd` Private Field Mutation & Dead-Bike Explosion Tick** — `godot/src/game/HazardPit.gd:L133-L139`
  - **Root Cause Mechanism:** Directly writes private `combat.set("_invuln_until", 0.0)` and emits `VFX.explosion()` even when `combat.alive == false`.
  - **Surgical Fix Specification:** Add optional `bypass_invuln: bool = false` parameter to `CombatController.take_damage()` and skip explosion when `not alive`.

### Lens 8: Type Systems, Schema & Contracts

- **`[F-P3-4]` `LoopZone.gd` Hardcoded World `+Y` Center Offset** — `godot/src/game/LoopZone.gd:L39`
  - **Root Cause Mechanism:** Uses `Vector3(0, loop_radius, 0)` instead of `global_transform.basis.y.normalized() * loop_radius`, and omits `_exit_tree()` `loop_up` cleanup.
  - **Surgical Fix Specification:** Use local `basis.y * loop_radius` and zero `loop_up` on tracked bikes in `_exit_tree()`.

### Lens 9: Platform, Viewport & Portability (Pass 2.5 Real-Window `xvfb-run` & WCAG 2.2)

- **`[F-P1-2]` `MatchHud._relayout()` Hard `KillFeed` Overlaps Across All Three Viewports** — `godot/src/ui/MatchHud.gd:L249-L275,L334-L355`
  - **Root Cause Mechanism:** Adding `WeaponLabel` + `ReloadBar` pushed `Radar` down to `y = [90, 182]` on portrait (`vp.x <= 640`) while leaving `KillFeed` at `y = [160, 236]`, and widened left-corner labels (`x = 12..206`) into `KillFeed` (`x = 154`) on landscape & desktop.
  - **Deterministic Trigger & Failure Mode:** **Live `xvfb-run` real-window & desktop reproductions confirmed:**
    - Portrait `390×843`: **`KF ∩ Radar = [P: (12, 160), S: (92, 22)]`** (`2,024 px²` overlap)
    - Landscape `843×390`: **`KF ∩ WeaponLbl = [P: (154, 58), S: (42, 15)]`** (`630 px²`) & **`KF ∩ Banner = [P: (154, 40), S: (26, 18)]`** (`468 px²`)
    - Desktop `1280×720`: **`KF ∩ WeaponLbl = [P: (154, 60), S: (52, 15)]`** (`780 px²`) & **`KF ∩ Banner = [P: (154, 42), S: (36, 18)]`** (`648 px²`)
    - *(Positive verification: `AnalogSteer ∩ AnalogDrive = 0 px²` across all three viewports.)*
  - **Surgical Fix Specification:** Set `KillFeed.offset_left = 224.0` on desktop/landscape (`18 px` clear of `WeaponLabel.offset_right = 206`), and `KillFeed.offset_top = 190.0` / `offset_bottom = 266.0` on narrow portrait (`8 px` below `Radar.offset_bottom = 182`).

- **`[F-P2-5]` Duplicate `<meta name="viewport">` with `maximum-scale=1, user-scalable=no` (WCAG 1.4.4)** — `index.html:L5,L80`, `godot/export_presets.cfg:L23`
  - **Root Cause Mechanism:** Two viewport meta tags; `user-scalable=no` blocks pinch-zoom accessibility.
  - **Surgical Fix Specification:** Remove `maximum-scale=1,user-scalable=no` from `html/head_include` (canvas `touch-action: none` already prevents gameplay pinch jitter).

- **`[F-P2-6]` Right-Analog Diagonal Ambiguity (Simultaneous Weapon Swap + Dodge)** — `godot/src/TouchControls.gd:L367-L395`
  - **Root Cause Mechanism:** Downward weapon switch and horizontal dodge thresholds fire independently without axis-dominance arbitration.
  - **Surgical Fix Specification:** Require `-best_down > absf(target) * 1.15` for swap and `absf(target) > maxf(best_up, -best_down) * 1.15` for dodge.

### Lens 10: Cognitive Load & AI Maintainability

- **`[F-P2-8b]` Frontend God Files & Blender `qb_core.py` Silent Exception Handlers** — `godot/tools/build_deathrace.gd` (`917` LOC), `godot/src/game/VfxFactory.gd` (`830` LOC), `godot/src/ui/MatchHud.gd` (`653` LOC), `src/qb_core.py` (`487` LOC, `7` silent catches)
  - **Surgical Fix Specification:** Narrow `src/qb_core.py` exception handlers to explicit `(AttributeError, RuntimeError)` with stderr logging; extract `MatchHud._relayout()` pure `Rect2` helper for Tier-0 non-overlap verification.

---

## 2.5 Pass 2.5 Live Evidence, WCAG 2.2 Math & 11th Lens (Engagement & Game Feel)

### Pass 2.5 Live Reproduction Transcript (Zero Source Mutation)

```text
# DeathRace ramp orientation & LoopZone flat-lane intrusion (Godot 4.3)
Ramp0: pos=(58, 0, 2) launch_dir=(-0, 0, -1) travel_dir=(0, 0, 1) dot=-1.00 (BACKWARDS WALL FACING RACER!)
Ramp2: pos=(22, 0, 44) launch_dir=(1, 0, -0) travel_dir=(-1, 0, 0) dot=-1.00 (BACKWARDS WALL FACING RACER!)
Ramp4: pos=(-58, 0, -2) launch_dir=(0, 0, 1) travel_dir=(0, 0, -1) dot=-1.00 (BACKWARDS WALL FACING RACER!)
TrackLoop0 LoopZone center=(26, 8.5, -47.2) world_z=[-51.7, -42.7] -> Flat-lane bike at (20, 0.5, -44) gets tilt_from_UP=36.9 deg

# DestructibleBuilding smash crash, checkpoint respawn, OmniLight count, FollowCam loop error
SCRIPT ERROR: Invalid call to function 'smash (via call)' in base 'StaticBody3D (DestructibleBuilding.gd)'. Expected 0 arguments.
F-P0-1 DestructibleBuilding intact after Meteor _detonate: true
F-P1-1 Checkpoint0 pos=(58, 0.65, -16) | respawn pos=(-17, 0.6, -40.8) | dist=78.99m
Idle OmniLight3D count BEFORE any shots/explosions: DeathRace=11, Arena=9 (WebGL2 limit = 8 per surface!)
ERROR: Up vector and direction between node origin and target are aligned, look_at() failed.

# Real-window xvfb-run layout probes
REAL_WINDOW vp=(390, 843): KF∩Radar=[P: (12, 160), S: (92, 22)] | Steer∩Drive=[P: (0, 0), S: (0, 0)]
REAL_WINDOW vp=(843, 390): KF∩WeaponLbl=[P: (154, 58), S: (42, 15)] | KF∩Banner=[P: (154, 40), S: (26, 18)]

# Node DOM sandbox probe (index.html Victory Splash)
DOM PROBE F-P1-4: {"victory_video_hardcoded_muted":true,"leaked_keydown_listeners_after_reentry":2,"leaked_listeners_remaining_after_escape":1,"escape_stopped_propagation_to_godot":false}
```

### WCAG 2.2 Exact Composited Luminance Contrast Audit

| UI Element / Token Pair | Measured Ratio | WCAG 2.2 Verdict |
| :--- | :---: | :---: |
| `UiTheme TEXT` on `SURFACE_BUTTON` | **`14.83 : 1`** | **AAA** |
| `UiTheme GOLD` on `SURFACE_BUTTON` | **`12.10 : 1`** | **AAA** |
| `UiTheme MUTED` on `SURFACE_BUTTON` | **`7.67 : 1`** | **AAA** |
| `index.html #splash-skip` (`#ffd16b` on `rgba(6,10,28,.82)`) | **`13.66 : 1`** | **AAA** |
| `index.html body::after` hint (`rgba(232,238,255,.68)` on `#060a1c`) | **`8.01 : 1`** | **AAA** |
| `index.html .splash-brand` (`#ff7a1a` on `#060a1c`) | **`7.54 : 1`** | **AAA** |
| `AnalogDrive FIRE_GUIDE` on `TRACK_INNER` | **`5.30 : 1`** | **AA** |
| `AnalogDrive SWAP_GUIDE` on `TRACK_INNER` | **`4.88 : 1`** | **AA** |
| `UiTheme DISABLED` text on `SURFACE_DISABLED` | **`4.08 : 1`** | **AA-Large** *(exempt as inactive UI)* |

### 11th Lens — Engagement, Game Feel & Authored-but-Unwired Coverage Matrix (`[F-P2-9]`)

| Engagement / Accessibility Practice | State | Evidence |
| :--- | :--- | :--- |
| Spatial 3D positional SFX (`Sfx.play_3d`) | **Authored, not wired** | Implemented in `Sfx.gd:L71-L89` with voice pool `_voices3d`; **`0` call sites** anywhere (every blast plays flat 2D stereo) |
| Kill-feed visibility setting (`gameplay/kill_feed`) | **Authored, not wired** | Persisted in `Settings.gd:L40`; `MatchHud.add_kill()` (`L580`) ignores it and `SettingsMenu` has no toggle |
| Instant Rematch (`ResultPanel/PlayAgainBtn`) | **Dead-end loop** | `MatchHud.gd:L93-L98` binds `PlayAgainBtn` to `_on_leave_match` (identical to `LeaveBtn` → boots player to MainMenu) |
| `RaceTracker` signals (`checkpoint_cleared`, `lap_completed`, `race_won`) | **Authored, not wired externally** | Emitted in `RaceTracker.gd:L8-L10`, `0` external listeners (HUD updated imperatively via `call()`) |
| Mobile Haptics (`Input.vibrate_handheld` / `navigator.vibrate`) | **Absent** | `0` calls on impact, rocket/meteor blast, pit burn, or weapon swap |
| High-Contrast / Forced-Colors (`prefers-contrast: more`, `forced-colors: active`) | **Absent** | `0` CSS rules in `index.html`; `0` `:active` visual press rules on `#splash-skip` / `#victory-skip` |
| Persistent lap timer / Personal Best / Career wins | **Absent** | `RaceTracker` tracks laps without elapsed lap clock or persistent PB storage |
| Visual + audio + shake + hitstop combat juice | **Wired** | Hitmarker, hurt vignette, camera shake, `0.28×` kill hitstop, Nardus bird-flap turbo, Victory Splash video |

---

## 3. Existing Test Suite Comparison & Mutation Truth Table

- **Test-to-Code File Ratio:** `20 / 55` (`0.36`)
- **Estimated Mutation Kill Score ($M_{\text{kill}}$):** **`44.2%`** (`23/52` mutants killed; `340` assertions, `189` negative/boundary signals, `5` mock-heavy test files, `5` unpaired critical modules: `index.html` Web shell, `build_deathrace.gd` spatial orientation/clearance, `HazardPit.gd`, `FollowCam.gd` loop path, `build_victory_splash.py`)

| Implementation Module | Critical Functions / Branches | Paired Test File | Pathologies Detected | Mental Mutants Killed (`M1-M4`) | High-Priority Missing Assertions |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `godot/tools/build_deathrace.gd` | `_add_ramp`, `_add_stunt_loop`, `_add_hazard_pit`, `_build_circuit` | `verify_deathrace.gd` | Existence-Only (checks node names exist, never checks `launch_dir.dot(travel_dir)` or `LoopZone` flat-lane clearance!) | `0/4` (`0%`) | Ramp facing direction `dot > 0.95`, `LoopZone` clear of `z = ±44` center lane, idle `OmniLight3D <= 8` |
| `godot/src/game/SideCannons.gd` | `fire`, `compute_meteor_target`, `_update_aim_reticle`, `cycle_weapon` | `verify_cannons.gd`, `verify_practice.gd`, `verify_deathrace.gd` | Happy-Path Tunnel Vision, Time-Window Myopia | `2/4` (`50%`) | 60 Hz vs 144 Hz reticle spin parity, empty-token cooldown refund, practice no-broadcast |
| `godot/src/game/RocketProjectile.gd` | `setup`, `_physics_process`, `_detonate` | `verify_deathrace.gd` | Happy-Path Tunnel Vision (dummy bike only, never tested against `DestructibleBuilding`) | `2/4` (`50%`) | Building smash without script error, zero-dir degenerate vector, direct-hit single smash |
| `godot/src/game/MeteorStrike.gd` | `setup`, `_physics_process`, `_detonate` | `verify_deathrace.gd` | Happy-Path Tunnel Vision | `2/4` (`50%`) | Building smash without script error, post-match detonation guard |
| `godot/src/game/RaceTracker.gd` | `_on_checkpoint_entered`, `_on_finish_line_entered`, `_setup_solo_or_match_mode` | `verify_deathrace.gd` | Happy-Path Tunnel Vision (host-only) | `2/4` (`50%`) | Guest pending lap does not trigger local victory, `_exit_tree()` clears solo `Match.players` |
| `godot/src/game/CombatController.gd` | `take_damage`, `_die`, `_respawn`, `reset_state` | `verify_combat.gd`, `verify_practice.gd` | Happy-Path Tunnel Vision | `2/4` (`50%`) | Death Race respawn preserves checkpoint transform, malformed `player_color` fallback |
| `godot/src/KiepieBike.gd` | `_physics_process`, `_integrate_forces`, `reset_bike`, `_try_dodge`, `_assign_vehicle` | `verify_controls.gd`, `verify_dodge.gd`, `verify_rollover.gd`, `verify_pogo.gd`, `truth_test.gd` | Minor gap on `reset_bike()` inside `LoopZone` | `3/4` (`75%`) | `reset_bike()` clears `loop_up`, `Settings.changed` disconnect on exit |
| `godot/src/TouchControls.gd` + `TouchCapture.gd` | `_on_pointer_*`, `_sync_analog`, `_sync_drive`, `_relayout` | `verify_touch.gd`, `verify_touch_multitouch.gd`, `verify_deathrace.gd` | Well-hardened | `4/4` (`100%`) | Diagonal swap-vs-dodge dominance |
| `godot/src/ui/MatchHud.gd` | `_relayout`, `_on_match_finished`, `_play_victory_splash`, `add_kill` | `verify_multiplayer.gd`, `verify_deathrace.gd`, `verify_accessibility.gd` | Existence-Only / No pairwise `Rect2` intersection assertions | `1/4` (`25%`) | Pairwise non-overlap across `1280×720`, `844×390`, `390×844`; dead-at-finish hides `RespawnOverlay` |
| `godot/src/FollowCam.gd` | `_process`, `toggle_view`, `spectate` | `verify_features.gd` | Existence-Only | `1/4` (`25%`) | Vertical `basis.z == Vector3.UP` inside 360° loop without `look_at()` error |
| `godot/src/DestructibleBuilding.gd` | `_on_body_entered`, `smash` | `verify_smash_impact.gd` | Happy-Path Tunnel Vision | `2/4` (`50%`) | `smash(impulse)` optional arg & double-`smash()` idempotency |
| `godot/src/game/PogoVisual.gd` | `_ready`, `_physics_process` | `verify_pogo.gd` | Happy-Path Tunnel Vision | `2/4` (`50%`) | Reduced-motion flap scaling, missing `Belly` safety |
| `index.html` (Web shell) | `__kiepiePlayVictorySplash`, `__kiepieSetFullscreen`, splash boot | **NONE** | `0%` automated coverage | `0/4` (`0%`) | Node/Playwright test for unmuted fallback, `Escape` stopPropagation, grace period, listener cleanup |

### Why Existing Tests Missed Discovered P0/P1 Defects

- **`F-P0-1`:** `verify_deathrace.gd:L158-L209` placed only a `DummyEnemy` bike in Rocket/Meteor blast radius, never a `DestructibleBuilding`.
- **`F-P0-2` & `F-P1-8`:** `verify_deathrace.gd:L100-L106` only asserted `Ramp0 != null` and `TrackLoop0/LoopZone != null` ("Existence-Only Pathology"), never testing ramp launch vector alignment (`launch_dir.dot(travel_dir)`) or flat-lane `LoopZone` intrusion!
- **`F-P1-1`:** `verify_deathrace.gd` cleared checkpoints without ever calling `CombatController._respawn()` mid-lap.
- **`F-P1-2`:** `verify_multiplayer.gd` checked individual node coordinates instead of pairwise `Rect2.intersection()` across desktop, mobile landscape, and mobile portrait.
- **`F-P1-4`:** `verify_deathrace.gd:L228` only read `hud.victory_splash_shown` in headless Godot without executing `index.html` JavaScript.

### Minimal Viable Test Harness (MVTH) Specifications

1. **Tier 0 — Pure Geometry & Track Invariants (`verify_deathrace.gd`):**
   - Assert `ramp.global_transform.basis.z.normalized().dot(expected_travel_dir) > 0.95` for `Ramp0`, `Ramp2`, `Ramp4` (and landing ramp inverse alignment for `Ramp1`, `Ramp3`, `Ramp5`).
   - Assert `TrackLoop0/LoopZone` and `TrackLoop1/LoopZone` AABBs do NOT contain flat straightaway centerline points `(26, 0.5, -44)` and `(-14, 0.5, 44)`.
   - Assert `r_a.intersection(r_b).get_area() == 0.0` for all HUD pairs `{HealthBar, Banner, WeaponLabel, ReloadBar, Radar, KillFeed, ScoreToggle, MenuBtn}` at `1280×720`, `844×390`, and `390×844` under `xvfb-run`.
2. **Tier 1 — Heavy Weapon & Checkpoint Respawn Regressions (`verify_deathrace.gd`):** Detonate `RocketProjectile` and `MeteorStrike` beside a `DestructibleBuilding` asserting `_intact == false` and 1 `smashed` emit; clear `Checkpoint1`, trigger `CombatController._respawn()`, and assert `bike.global_position.distance_to(cp1.global_position) < 2.0`.
3. **Tier 2 — Loop Camera, Light Budget & Async Race Lifecycle:** Orient bike straight up (`basis.z = Vector3.UP`, `loop_up = Vector3.BACK`), step `FollowCam._process(0.016)` with zero `look_at()` errors; assert idle `OmniLight3D` count `<= 8` in both `DeathRace.tscn` and `Arena.tscn`; verify guest pending lap does not trigger premature local victory.
4. **Tier 3 — Web Shell DOM Test (Node `vm` / Playwright):** Verify `__kiepiePlayVictorySplash` attempts unmuted playback, stops `Escape` propagation, enforces 600 ms tap grace, and cleans up `keydown` listeners on re-entry.

---

## 4. Surgical Refactoring Blueprints (Zero-Mutation Drafts)

### Refactor `[F-R1]`: Fix Inverted Death Race Pit Ramps & Isolate `LoopZone` From Flat Lane

- **Target Scope:** `godot/tools/build_deathrace.gd:L125-L147,L678,L697`
- **Engineering ROI:** Fixes `F-P0-2` (un-jumpable pit walls) and `F-P1-8` (flat-road centripetal tilt bug) cleanly before regenerating `DeathRace.tscn`.

**Current Pattern (Audited Code):**

```gdscript
_add_stunt_loop(root, "TrackLoop0", Vector3(26.0, 0.0, -47.2), 90.0, 8.5)
_add_stunt_loop(root, "TrackLoop1", Vector3(-14.0, 0.0, 47.2), -90.0, 8.5)
...
_add_ramp(root, "Ramp0", Vector3(58.0, 0.0, 2.0), Vector3(15.0, 180.0, 0.0))  # launches -Z (BACKWARDS!)
_add_ramp(root, "Ramp2", Vector3(22.0, 0.0, 44.0), Vector3(15.0, 90.0, 0.0))  # launches +X (BACKWARDS!)
_add_ramp(root, "Ramp4", Vector3(-58.0, 0.0, -2.0), Vector3(15.0, 0.0, 0.0))  # launches +Z (BACKWARDS!)
```

**Target Pattern (Surgical Blueprint):**

```gdscript
# Push stunt loops to outer apron (z = +-51.5) with narrow LoopZone (size.x = 5.4) so flat lane z = +-44 stays 100% clear
_add_stunt_loop(root, "TrackLoop0", Vector3(26.0, 0.0, -51.5), 90.0, 8.5)
_add_stunt_loop(root, "TrackLoop1", Vector3(-14.0, 0.0, 51.5), -90.0, 8.5)
...
# Local +Z is the high launch lip: rot_y=0 launches +Z, rot_y=-90 launches -X, rot_y=180 launches -Z
_add_ramp(root, "Ramp0", Vector3(58.0, 0.0, 2.0), Vector3(15.0, 0.0, 0.0))
_add_ramp(root, "Ramp1", Vector3(58.0, 0.0, 18.0), Vector3(10.0, 180.0, 0.0))
_add_ramp(root, "Ramp2", Vector3(22.0, 0.0, 44.0), Vector3(15.0, -90.0, 0.0))
_add_ramp(root, "Ramp3", Vector3(6.0, 0.0, 44.0), Vector3(10.0, 90.0, 0.0))
_add_ramp(root, "Ramp4", Vector3(-58.0, 0.0, -2.0), Vector3(15.0, 180.0, 0.0))
_add_ramp(root, "Ramp5", Vector3(-58.0, 0.0, -18.0), Vector3(10.0, 0.0, 0.0))
```

### Refactor `[F-R2]`: Idempotent `DestructibleBuilding.smash(impulse)` & Checkpoint-Preserving `_respawn()`

- **Target Scope:** `godot/src/DestructibleBuilding.gd:L92-L150`, `godot/src/game/CombatController.gd:L204-L220`, `godot/src/ui/MatchHud.gd:L343-L355`
- **Engineering ROI:** Fixes `F-P0-1` runtime `SCRIPT ERROR`, `F-P1-1` 79 m checkpoint setback, and `F-P1-2` multi-viewport HUD overlaps.

**Target Pattern (Surgical Blueprint):**

```gdscript
# DestructibleBuilding.gd
func smash(impulse: Vector3 = Vector3.ZERO) -> void:
	if not _intact:
		return
	_intact = false
	...
	chunk.linear_velocity = (outward * rng.randf_range(2.5, 7.0)
			+ Vector3(0.0, rng.randf_range(2.2, 5.2), 0.0)
			+ impulse * 0.30)

# CombatController.gd (_respawn)
func _respawn() -> void:
	var in_race := get_tree() != null and get_tree().get_first_node_in_group("race_tracker") != null
	if not in_race:
		var points := get_tree().get_nodes_in_group("spawn_point")
		var pos := Vector3(0.0, 0.6, 0.0)
		if not points.is_empty():
			var pick: Node3D = points[randi_range(0, points.size() - 1)] as Node3D
			pos = pick.global_position + Vector3(0.0, 0.6, 0.0)
		elif not practice_mode:
			pos = Vector3(randf_range(-25.0, 25.0), 0.6, randf_range(-25.0, 25.0))
		bike.set_spawn(Transform3D(Basis.IDENTITY, pos))
	bike.reset_bike()

# MatchHud.gd (_relayout KillFeed)
if narrow:
	feed.offset_left = 12.0
	feed.offset_right = minf(220.0, vp.x * 0.56)
	feed.offset_top = 190.0   # 8px below Radar (90 + 92 = 182)
	feed.offset_bottom = 266.0
else:
	feed.offset_left = 224.0  # 18px right of WeaponLabel (12 + 130 + 64 = 206)
	feed.offset_right = maxf(310.0, minf(440.0, vp.x - 336.0))
	feed.offset_top = 10.0
	feed.offset_bottom = 106.0
```

---

## 5. Phased Execution Roadmap & Scoped Agent Prompts

1. **Phase 1 — Containment & Safety Lock (`P0` + Core Death Race `P1` Fixes):** Fix backwards pit ramps & flat-lane `LoopZone` intrusion in `build_deathrace.gd` (`F-P0-2`, `F-P1-8`), fix `DestructibleBuilding.smash(impulse = Vector3.ZERO)` (`F-P0-1`), preserve Death Race checkpoint spawns in `CombatController._respawn()` (`F-P1-1`), fix `MatchHud._relayout()` overlaps (`F-P1-2`), and harden `RaceTracker.gd` async/guest/cleanup paths (`F-P1-3`).
2. **Phase 2 — Web Shell, Frame-Budget & 3D Camera Hardening (`P1` Fixes):** Fix Victory Splash unmuted playback, `Escape` stopPropagation, 600 ms tap grace, and listener cleanup in `export_presets.cfg` + `index.html` + `MatchHud.gd` (`F-P1-4`); move `SideCannons` raycast to `_physics_process()` with `dt`-scaled reticle spin (`F-P1-5`); fix `FollowCam` 360° loop `look_at()` collinearity (`F-P1-6`); cap WebGL2 `OmniLight3D` emitters below 8 (`F-P1-7`).
3. **Phase 3 — Lifecycle Hygiene, 11th-Lens Quick Wins & Debt Paydown (`P2/P3`):** Wire `Sfx.play_3d()` for explosions/impacts, wire `gameplay/kill_feed`, make `PlayAgainBtn` restart solo races, add subtle mobile haptics + `forced-colors` CSS (`F-P2-9`); guard `SideCannons.fire()` pre-`await` flow + practice broadcast (`F-P2-1`), clear `loop_up` in `reset_bike()` (`F-P2-2`), throttle idle `MobileTextInput` polling (`F-P2-4`), remove WCAG viewport zoom lock (`F-P2-5`), add right-analog axis dominance (`F-P2-6`), and flip `Projectile.gd` nose pellet to `-0.22` (`F-P3-1`).

### Copy-Paste Surgical Prompts for Coding Agents

> **Prompt `[F-P0-1/F-P0-2/F-P1-1/F-P1-8]` (`build_deathrace.gd`, `DestructibleBuilding.gd`, `CombatController.gd`, `verify_deathrace.gd`):**
> "Strictly scope edits to `godot/tools/build_deathrace.gd`, `godot/src/DestructibleBuilding.gd`, `godot/src/game/CombatController.gd`, `godot/src/game/RocketProjectile.gd`, and `godot/tools/verify_deathrace.gd`. Flip `Ramp0..Ramp5` `rot_y` by 180° so pit launchers face the travel direction (`dot > 0.95`), shift `TrackLoop0`/`TrackLoop1` outward to `z = ±51.5` with `LoopZone` `size.x = 5.4` clear of flat center lane `z = ±44`, and regenerate `DeathRace.tscn`. Update `DestructibleBuilding.smash(impulse: Vector3 = Vector3.ZERO)` with `if not _intact: return`. Preserve `bike._spawn` inside `CombatController._respawn()` when `race_tracker` is present. Add regression assertions for all four fixes and run `bash godot/tools/run_gates.sh`."

> **Prompt `[F-P1-2/F-P1-3/F-P1-4]` (`MatchHud.gd`, `RaceTracker.gd`, `export_presets.cfg`, `index.html`):**
> "Strictly scope edits to `godot/src/ui/MatchHud.gd`, `godot/src/game/RaceTracker.gd`, `godot/export_presets.cfg`, `index.html`, and `godot/tools/verify_deathrace.gd`. Fix `MatchHud._relayout()` (`KillFeed` `offset_left = 224.0` on desktop/landscape, `offset_top = 190.0` on narrow portrait), hide `RespawnOverlay` on finish, and guard `Engine.has_singleton('JavaScriptBridge')`. In `RaceTracker.gd`, guard `is_inside_tree()` after `await`, defer multiplayer victory to `Match.match_finished`, and clean up solo `Match.players` in `_exit_tree()`. In `export_presets.cfg` and `index.html`, attempt unmuted Victory Splash playback with muted fallback, stop propagation on `Escape`, add 600 ms tap grace (always permitting `#victory-skip`), and remove prior `keydown` listeners on re-entry. Run `bash godot/tools/run_gates.sh`."

> **Prompt `[F-P1-5/F-P1-6/F-P1-7]` (`SideCannons.gd`, `FollowCam.gd`, `Pickup.gd`, `Projectile.gd`, `RocketProjectile.gd`, `MeteorStrike.gd`, `VfxFactory.gd`):**
> "Strictly scope edits to `SideCannons.gd`, `FollowCam.gd`, `Pickup.gd`, `Projectile.gd`, `BananaProjectile.gd`, `RocketProjectile.gd`, `MeteorStrike.gd`, and `VfxFactory.gd`. Move `SideCannons.compute_meteor_target()` raycasting to `_physics_process()` with a reused `PhysicsRayQueryParameters3D` and make reticle spin `2.1 * delta`. Make `FollowCam.look_at()` align `up` safely inside 360° loops without collinearity errors. Remove `OmniLight3D` from `Pickup` and rapid-fire `Projectile`/`BananaProjectile` and cap dynamic explosion/rocket/meteor lights via `VfxFactory._cap_group` so idle scene light count is `<= 8`. Run `bash godot/tools/run_gates.sh`."
