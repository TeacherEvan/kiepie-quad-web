# Surgical Audit (v3.0) & Remediation Plan — Kiepie Quad (`TeacherEvan/kiepie-quad-web`)

- **Date:** 2026-11-24
- **Repository:** `TeacherEvan/kiepie-quad-web`
- **Audited `HEAD`:** `f46881e9fd0267904de867df9c0fc7c2d32f293b`
- **Pre/Post Zero-Mutation SHA-256:** `74f5e78aad3b311625fd8a85f0759e61167b0bcb62f48939f5454c8245fd3c90` *(verified identical; zero tracked source, scene, test, build, or config files modified)*
- **SARIF Companion:** `docs/audits/kiepie-quad-surgical-audit-2026-11-24.sarif`

---

## 1. Executive Scorecard & Telemetry

| Metric | Measured Value | Notes |
|---|---:|---|
| **First-Party Scope** | **108 files** | Excl. `godot/addons/`, `web/`, `docs/`, Godot-generated `index.js` |
| **Implementation / Build / Tool LOC** | **20,964 eff LOC** | 79 files (`godot/src/**/*.gd`, `src/*.py`, `godot/tools/*.{gd,py,sh}`, `godot/assets/sfx/generate_sfx.py`) |
| **Test / Gate LOC** | **4,812 eff LOC** | 29 files (`godot/tools/verify_*.gd`, `truth_test.gd`, `diag2.gd`, `_check_scripts.gd`, `godot/tests/test_kiepie_pad.gd`, etc.) |
| **Scored Effective LOC** | **25,975 eff LOC** | `25,776` code eff LOC + `199` HTML lines (`index.html`) |
| **Dead Modules (`godot/src/**/*.gd`)** | **0 / 47** | All 47 runtime scripts referenced/shipped |
| **Empirical Gate Suite** | **29 / 29 green** | `bash godot/tools/run_gates.sh --no-build` (`exit 0`, GdUnit4 `6 tests \| 0 errors \| 0 failures \| 0 orphans \| PASSED 1s 154ms`) |
| **Web Hygiene** | **PASS** | `web_hygiene OK (.vercelignore=16 runtime files, vercel.json headers, single WCAG viewport, every-launch splash)` |
| **Live Production Parity** | **Bit-for-bit** | `index.html` MD5 `c715f8ad9e5efe2e9e01c34780627c02`, `index.service.worker.js` MD5 `a595b67df6bc34013e09effa42b749de` match `https://kiepie-quad-web.vercel.app/` (`HTTP/2 200`, `COOP=same-origin`, `COEP=require-corp`, `CORP=same-origin`, `nosniff`, `Referrer-Policy`, `Permissions-Policy`) |
| **Shipped Web Payload** | **`index.pck = 3,744,192 B`** | `3.57 MiB` (**89.3%** of `deploy_web.sh:L66` `4,194,304 B` cap); `index.wasm = 35,376,909 B`; `kiepie-quad-splash.mp4 = 1,817,879 B`; `kiepie-victory-splash.mp4 = 424,620 B`; `dashboard_bg.jpg = 124,137 B` |
| **Host Contention** | `nproc = 4`, `load = 3.56, 3.33, 2.63` | Wall-clock FPS claims explicitly omitted per `runtime-probe-harness.md` §8a |

### Deterministic Health Score (`score_audit.py`)

```json
{
  "effective_loc": 25975,
  "counts": { "p0": 0, "p1": 12, "p2": 15, "p3": 11 },
  "d_raw": 152,
  "scale_factor": 0.19621048979129171,
  "mutants_killed": 10,
  "mutants_evaluated": 20,
  "m_kill_pct": 50.0,
  "p_test": 7.5,
  "s_health": 63,
  "risk_level": "HIGH"
}
```

- **Health Score:** **`S_health = 63 / 100` — Risk Level: `HIGH`** (`0 P0`, `12 P1`, `15 P2`, `11 P3`, `M_kill = 10/20 = 50.0%`).
- **Delta vs. Superficial v1 (`80 / 100`):** v1 only inspected GDScript runtime files, omitted Pass 2.5 live browser probing, skipped empirical gate execution, skipped Blender/GLB/scene-builder/Python pipeline inspection, and used regex assertion counts instead of line-by-line Mental Mutation verification. Full-stack inspection uncovered 7 additional P1s (GLB geometry defects, live WCAG 2.1.1 keyboard failure, deploy/SW silent-skip bugs, GDScript lambda value-capture hollow tests, and persistent `user://settings.cfg` corruption) and dropped `M_kill` from an assumed high to a verified `50.0%`.

---

## 2. Pass 2.5: Live Browser Geometry & WCAG 2.2 Probe

Served pristine `git archive HEAD` over a local COOP/COEP/CORP HTTP server in headless Chromium (`chrome-devtools` MCP):

| Viewport / Mode | Isolation & Console / Net | Geometry & Overlap | WCAG 2.2 Target / Focus / Media |
|---|---|---|---|
| **Desktop `1280×720` (`dpr=1`)** | `crossOriginIsolated=true`, `SharedArrayBuffer=true`, `0` console errors, `0` failed requests (`api.trytalo.com` `/identify` 200, `/socket-tickets` 200) | `overflow={x:0, y:0}`, `#canvas=1280×720`, `#victory-skip=124.7×44 px` | `hit5=5/5`, `focusObscured=false`, `focusOutline=2px solid #ff7a1a`, `>=24×24` & `>=44 px` PASS |
| **Mobile Portrait `390×844` (`dpr=2, mobile, touch`) + `forced-colors: active` + `prefers-contrast: more`** | `overflow={x:0, y:0}` | `#victory-skip=126.7×46 px`, `titleOverlapsSkip=false` | `hitCenter=BUTTON#victory-skip`, forced-colors high-contrast borders active (`rgb(0,0,0)` on `rgb(255,255,255)`) |
| **Mobile Landscape `844×390` (`dpr=2, mobile, touch, landscape`)** | `overflow={x:0, y:0}` | `titleOverlapsSkip=false` | `#victory-skip=124.7×44 px`, in viewport |
| **`prefers-reduced-motion: reduce`** | — | `victoryCreatedUnderReducedMotion=false` | Both `#splash` and `#victory-splash` suppressed cleanly |
| **Keyboard Activation (`WCAG 2.1.1`)** | — | **`dismissedByEnterOrClick=false`**, `dismissedByPointerDown=true` | **FAIL (`P1-6`):** `#victory-skip` & `#splash-skip` only bind `pointerdown`; `Enter`/`Space`/`.click()` do not dismiss |

---

## 3. Complete Deduplicated Findings Inventory (38 Findings)

### P1 — High Severity (12 Findings)

1. **`[P1-1]` `godot/src/net/TaloBackend.gd:L357-386, L413-523` (Lens 4 — Async Generation Race)**
   - **Root cause:** No `_join_gen` guard across multi-`await` RPCs (`_create_lobby`, `_join_auto`, `_join_by_code`, `_try_join`, `join_lobby_channel`) and the 2,000 ms `_host_ack` loop.
   - **Trigger:** Cancelling `join_auto` and creating/joining Channel B lets the stale `_host_ack` loop time out and call `leave_lobby_channel()` (`L444`/`L489`) destroying Channel B, return Channel B to stale `LobbyService._enter_if_current()` (which then tears down Channel B), or fall through to `_create_lobby()` (`L458`).
   - **Fix:** Add `_join_gen: int` incremented on `leave_lobby_channel()` and at entry to `_create_lobby`/`_join_auto`/`_join_by_code`; check `if gen != _join_gen` after every `await` and before `leave_lobby_channel()`.

2. **`[P1-2]` `godot/src/game/VfxFactory.gd:L95-97, L121-124, L140-142, L186-188` vs `VfxCore.gd` / `VfxHeavy.gd` (Lens 1/8 — Facade Signature & Default Drift)**
   - **Root cause:** Commit `c9c423f` introduced 4 facade mismatches:
     1. `particle_explosion(..., spawn_scorch: bool = true)` forwards `true` into `VfxHeavy.particle_explosion(..., mushroom: bool = false)` → every 4-arg call spawns a 45 m mushroom cloud.
     2. `impact(..., normal = Vector3.UP, kind = "spark", incoming_dir = Vector3.ZERO)` swaps `VfxCore.impact(..., dir = Vector3.ZERO, surface = "metal", normal = Vector3.UP)` → live 5-arg `CombatController.gd:L458` gets `normal = Vector3.ZERO` (suppressing scars), and 3-arg calls get `surface = "spark"`.
     3. `dust_ring(..., amount: int = 24)` narrows `VfxCore.dust_ring(..., amount: float = 5.0)` grow scale to `int` → truncates `KiepieBike.gd:L394`'s `4.5` to `4`, and 3-arg calls expand `24×` (57 m ring).
     4. `_ring_quad()` drops optional `matte`, `normal`, and `MeshInstance3D` return type.
   - **Fix:** Align all 4 `VfxFactory.gd` wrapper signatures, parameter order, types, and defaults verbatim with `VfxCore.gd` / `VfxHeavy.gd`.

3. **`[P1-3]` `godot/src/game/HazardPit.gd:L142`, `CombatController.gd:L194-221`, `ArenaNet.gd:L162-192`, `MatchHud.gd:L660-711` (Lens 4/7 — Dropped Environmental Kills)**
   - **Root cause:** `HazardPit` passes `token = ""`; `CombatController._die()` (`L194-198`) strips `"hazard-pit"` to `attributable = ""` and broadcasts `"kill"` with `"token": ""`; `ArenaNet._on_broadcast("kill")` drops it at `if victim == "" or token == "": return` (`L162`).
   - **Trigger:** Any player killed by a molten hazard pit never resets `_streak`, never hides their remote proxy (`_hide_remote_briefly`/`mark_killed`), and never appears in the kill feed (and `MatchHud._name_for("")` would print `"RIDER"`).
   - **Fix:** In `CombatController._die()`, capture `var is_env := (by == "hazard-pit")` *before* roster-stripping `attributable`; when `is_env`, broadcast `"kill"` with `"killer": "hazard-pit"` and `"token": "env:hazard-pit:%d" % Time.get_ticks_msec()`. In `ArenaNet._on_broadcast("kill")`, accept `killer == "hazard-pit"` with `token.begins_with("env:")` for proxy hide + streak reset + kill feed while skipping `Match.register_kill` (never scores points). In `MatchHud._name_for("hazard-pit")`, return `"MOLTEN PIT"`.

4. **`[P1-4]` `godot/src/game/ArenaNet.gd:L154-155, L276-280`, `TaloBackend.gd:L1069-1075` (Lens 6/7 — Post-Match Remote Shot Bypass)**
   - **Root cause:** Remote `"shot"` lacks `Match.is_playing()` / `status == "playing"` gate.
   - **Trigger:** Post-match remote shots smash buildings, detonate fuel drums, play SFX, and shake the camera over the scoreboard.
   - **Fix:** In `ArenaNet._spawn_remote_shot()`, add `if Match != null and not Match.lobby.is_empty() and not Match.is_playing(): return` (preserving empty-lobby offline gates!). In `TaloBackend._on_socket_message("shot")`, add `if not _lobby.is_empty() and str(_lobby.get("status", "")) != "playing": return`.

5. **`[P1-5]` `godot/src/game/RocketProjectile.gd:L419-423`, `CombatAoe.gd:L35-36, L62-63, L88-91` (Lens 11 — Suppressed Direct-Hit Crosshair Marker)**
   - **Root cause:** `skip_proxy` executes `continue` before `hit_any_enemy = true`.
   - **Trigger:** Direct-hit lethal rocket/cigar/cash-bag kills against remote proxies silently suppress `local_combat.hit_confirmed`.
   - **Fix:** Set `hit_any_enemy = true` before `if skip_proxy: continue`.

6. **`[P1-6]` `index.html:L81` & `godot/export_presets.cfg` `html/head_include` (WCAG 2.1.1 — Keyboard Activation Failure on Splash Skip)**
   - **Root cause:** Live Pass 2.5 probe proved `victorySkip.focus(); Enter / .click()` returns `dismissedByEnterOrClick = false` (`dismissedByPointerDown = true`). Both `#victory-skip` and `#splash-skip` only bind `pointerdown` (no `click` listener), and `#victory-splash` `onKey` omits `Enter`/`Space`.
   - **Fix:** Bind `click` on `#victory-skip` and `#splash-skip` (calling `drop()`), and add `Enter`/`Space` handling to `#victory-splash` `onKey` in both `index.html` and `godot/export_presets.cfg` `html/head_include` in lockstep.

7. **`[P1-7]` `src/build_aston_martin.py:L490-499` (3D Geometry — Detached `ExhaustPipe`)**
   - **Root cause:** `lathe_x_solid("ExhaustPipe", (0.0, 1.32, 0.39), ...)` bakes `center=(0.0, 1.32, 0.39)` into mesh vertices while leaving `ex.location = (0, 0, 0)`. Line 493 rotates `ex.rotation_euler = (0, 0, math.pi * 0.5)` about `(0, 0, 0)`, moving the pipe to `x = -1.32 m` (`0.60 m` outside the left wing). Confirmed in shipped `godot/assets/Aston_Martin.glb`: `Floor_me min.x = -1.356` vs `max.x = +0.765`.
   - **Fix:** Pass `(0.0, 0.0, 0.0)` to `lathe_x_solid`, set `ex.location = (0.0, 1.32, 0.39)` and `ex.rotation_euler = (0.0, 0.0, math.pi * 0.5)` before `transform_apply`, then rebuild `Aston_Martin.glb`.

8. **`[P1-8]` `src/build_quad.py:L113-131` & `src/repair_and_verify.py:L37-62` (3D Rig — `6.78 mm` Pivot Shear in `Kiepie_Bike.glb`)**
   - **Root cause:** `build_quad.py:126-128` shifts `ob.location.z += dz` only for `ob.type == 'MESH'` before `finalize(coll)`. `EMPTY` pivots (`Steer_FL/FR`, `Muzzle_L/R`) are skipped. Confirmed in shipped `godot/assets/Kiepie_Bike.glb`: `Steer_FL/FR` at `y = 0.280000` while `Wheel_FL/FR` have `trans.y = +0.006781`; `Muzzle_L/R` at `y = 0.560000` while `Cannon_Bore_L/R` are at `y = 0.566781`.
   - **Fix:** Remove the pre-finalize mesh-only shift in `build_quad.py:113-130` so `repair_and_verify.py:56-61` shifts all top-level parentless roots rigidly after `finalize(coll)`.

9. **`[P1-9]` `src/qb_wheels.py:L71-142, L180` & `src/qb_body.py:L146-154, L192-200, L218-264` (3D Geometry — Inside-Out Left Rims & Flipped Left Fenders)**
   - **Root cause:** `build_rim()` places all outboard features (`Face`, `HubCap`, `Bolts`, `Lip`, `Nuts`) unconditionally at `+hw` (`+X`), which is **inboard** on `side = -1` (left wheels). `build_plastics()` passes `min(x_in, x_out), max(x_in, x_out)` to `build_fender()` / `build_fender_stripe()`, reversing `u` on `side = -1` so the downward outer skirt drops the **inboard** edge.
   - **Fix:** Add `side=1` to `build_rim()` and multiply axial `±hw` offsets by `side`; pass `(x_in, x_out)` in inboard→outboard order without `min`/`max` (recalculating normals / winding when `x_out < x_in`).

10. **`[P1-10]` `godot/tools/deploy_web.sh:L60-72, L93-95` & `godot/tools/patch_web_sw.py:L18-25, L34-124, L186-187, L260-261` (Deploy & Service Worker Fragility)**
    - **Root cause:** `deploy_web.sh` checks `SIZE > 4194304` but never `SIZE >= 1048576` or `index.pck` existence in its `-s` loop, overwrites `$ROOT/` *before* `check_web_hygiene.py` (no rollback), and runs Godot export with no `timeout`. `patch_web_sw.py` silently skips 6 of 7 patches if Godot's template shifts (risking `ReferenceError: ENGINE_FILES is not defined`), returns `"missing"` in `_sha12()` on missing `.wasm`/`.pck`, leaves `index.manifest.json` `networkFirst` as dead code (absent from `FULL_CACHE`/`ENGINE_FILES`), and never clears `ENGINE_CACHE` on `'clear'`.
    - **Fix:** Enforce `[ "$SIZE" -ge 1048576 ]`, add `index.pck`/`index.audio.worklet.js`/`index.offline.html` to `-s` check, wrap export in `timeout --foreground 240`, validate before root sync / rollback on failure; make all 7 SW patches fail-fast, raise `FileNotFoundError` in `_sha12()`, include `index.manifest.json` in the fetch guard, and clear `ENGINE_CACHE` in `'clear'`.

11. **`[P1-11]` Hollow / Mutant-Surviving Test Bugs Across 7 Gates**
    - `verify_audit_regressions.gd:L70-87` & `verify_talo_backend.gd:L196-207`: GDScript primitive `int` (`sig := 0`, `post_leave_sigs := 0`) captured **by value** in lambdas → `sig == 0` / `post_leave_sigs == 0` **unconditionally true**.
    - `verify_vfx.gd:L519-528`: Bare `ArenaNet` (`_remote == {}`) drops all 40 shots → asserts `0 <= 32`.
    - `verify_match_rules.gd:L60-64`: Asserts `game_mode` & `damage` reset on `leave()` without ever mutating them first.
    - `verify_accessibility.gd:L195-198`: Waits `0.15 s` for a `4.0 s` kill-feed timer, then asserts `_check(true, ...)`.
    - `verify_dodge.gd:L58-69`: Asserts `cd > 0.0` after re-press (passes even if `_try_dodge()` ignores `_dodge_cd > 0.0` and resets `cd = 1.0`).
    - `verify_kill_flow.gd:L47-53`: Reuses same `token` and `"victim-1"` within ms, short-circuiting before `if killer == Supabase.user_id`.
    - `verify_vfx.gd:L42`: Invokes `_meteor_clamp()` without `await`.
    - `verify_talo_backend.gd:L278-287`: Asserts `not host_lost` on `_handoff_host_before_leave`, which never emits `host_lost`.
    - **Fix:** Box lambda counters in `Array` (`var sig := [0]`), populate `_remote` in pool test, mutate `game_mode`/`damage` before `leave()`, wait `> 4.0 s` (or parameterize timer), assert velocity/cooldown delta in `verify_dodge`, use fresh token in `verify_kill_flow`, `await _meteor_clamp()`, and test real `_handoff_host_before_leave` effects.

12. **`[P1-12]` Persistent `user://settings.cfg` Corruption & Cross-Gate Contamination**
    - `verify_deathrace.gd:L139-140` (`BtnTouchToggle.pressed` → `touch_force=true`) and `verify_vfx.gd:L111-131, L390-703` (`reduced_motion=false`, `particles=1.0`) **permanently overwrite `user://settings.cfg` on normal exit**.
    - `verify_pogo.gd`, `verify_aston.gd`, `verify_deathrace.gd:L79-118`, `verify_audit_regressions.gd:L278-290`, `verify_features.gd:L65`, `verify_smash_impact.gd:L53` fail if a developer's `user://settings.cfg` has non-`"auto"` `gameplay/vehicle` or `reduced_motion=true` / `particles < 1.0`.
    - `test_kiepie_pad.gd:L51-76, L115-136` leaks `Settings` + `Match` state on failure.
    - **Fix:** Add a shared `user://settings.cfg` backup/restore + `"auto"`/default reset helper to all mutating gates and `test_kiepie_pad.gd` `after_test()`.

---

### P2 — Medium Severity (15 Findings)

| ID | Location | Root Cause & Fix |
|---|---|---|
| **P2-1** | `VfxHeavy.gd:L307-329` | `_build_death_wreck()` emits `GPUParticles3D` (`maxi(4, int(26 * S._q()))`) even when `video/particles = 0.0`. Guard with `if S._q() > 0.0:`. |
| **P2-2** | `Projectile.gd:L113`, `BananaProjectile.gd:L152`, `RocketProjectile.gd:L190` | `setup()` omits `not is_finite(p_speed) or p_speed <= 0.0` guard before `Basis.looking_at()`. Add guard + early return. |
| **P2-3** | `RaceTracker.gd:L227-242` | `_reconcile_pending_lap()` rolls back dropped non-final guest laps without retrying or preserving checkpoint progress. Add bounded retry / preserve checkpoints. |
| **P2-4** | `NetworkedBike.gd:L133-138` | `apply_state()` accepts arbitrary finite magnitudes (`1e30`) without arena bounds clamping. Clamp/reject out-of-bounds positions. |
| **P2-5** | `build_arena.gd:L189-199`, `build_testride.gd:L123-133` | `CameraRig` spawns at `(0, 1.6, 13)` (~40 m from `SpawnPoint0` in Arena; 5 m *in front* of bike in TestRide), causing a frame-1 camera whip. Match `build_deathrace.gd:L188`. |
| **P2-6** | `build_arena.gd:L240-468` | Omits `HUD/SpeedLabel` (present in `build_deathrace.gd:L920-934` and driven by `MatchHud.gd`). Add `SpeedLabel` to `build_arena.gd`. |
| **P2-7** | `build_testride.gd:L334-366`, `build_deathrace.gd:L630-667` | `_add_cone_ring()` creates 24 duplicate cone subresources; `_add_stunt_loop()` creates `320` unshared loop `BoxMesh`/`BoxShape3D` subresources, bloating `DeathRace.tscn` & `index.pck` (`89.3%` of cap). Share mesh/shape instances. |
| **P2-8** | `build_testride.gd:L229-266`, `TouchControls.gd:L628-637` | On `vp.x < 700`, `Hud._relayout()` narrows buttons to `-132`, while `TouchControls._relayout()` only repositions `BtnTouchToggle` when `in_arena`, leaving TestRide's `BtnTouchToggle` misaligned at `-150`. |
| **P2-9** | `godot/assets/sfx/generate_sfx.py:L51-64, L176-187, L323-351, L381-384` | `pop()` phase-multiplication bug (`+2,119 Hz` / `-764 Hz` + inverted sweep); `dink()`/`scrape()` end-of-clip truncation clicks; `engine_loop()` `out[-1] = out[0]` 1-sample wrap stutter; non-atomic WAV writes. |
| **P2-10** | `src/build_victory_splash.py:L130-158, L182-186, L213-221`, `src/build_intro_splash.py:L46, L191-196, L347` | Victory splash animates `Rider` while `Stick` stays frozen, has 4 fanfare step-gate clicks, and writes `OUT_MP4` non-atomically without timeout. Intro splash Act 5 riser sweeps to `16.7 kHz` (phase-mult) and `Path("").exists()` crashes on missing fonts. |
| **P2-11** | `src/build_aston_martin.py:L579` | `RearPlate_BigBen` uses `(-tilt, 0, 0)`, tilting `-12°` downward toward the road instead of `+12°` upward toward the chase cam. |
| **P2-12** | `godot/tools/run_gates.sh:L26-27, L76-164` | Missing `timeout` on `--import` and 5 builders; unguarded `LOGDIR`; `LOGDIR` leak on PASS; duplicate failure counting; `run_gate_gdunit` & builders ignore `SCRIPT ERROR`. |
| **P2-13** | `godot/tools/check_scene_sync.py:L59-76, L85-91`, `check_web_hygiene.py:L22-39, L88-106` | `check_scene_sync.py` collapses `[sub_resource]` by type only (hiding material/stylebox swaps) and turns git errors into `SKIP`. `check_web_hygiene.py` is polluted by `.gitignore` and omits `export_presets.cfg`/SW parity checks. |
| **P2-14** | 18 first-party files `>400` eff LOC | God-file cluster (`build_deathrace.gd` 949, `TaloBackend.gd` 937, `MatchHud.gd` 753, `build_arena.gd` 700, `SideCannons.gd` 600, `KiepieBike.gd` 570, etc.). |
| **P2-15** | Zero-behavioral-coverage modules & `_check_scripts.gd:L6-25` | Zero behavioral tests for `Pickup.gd`, `LobbyMenu.gd`, `HazardPit.gd` (positive path), `Projectile.gd` (raycast), `FollowCam.gd`, `Sfx.gd`, `MatchState.gd` (timer/`host_lost`), `TaloBackend.gd` (reconnect/20-per-min/eviction); `29/47` scripts omitted from `_check_scripts.gd` `REQUIRED`. |

---

### P3 — Low Severity (11 Findings)

| ID | Location | Defect & Fix |
|---|---|---|
| **P3-1** | `TaloBackend.gd` | `"leave"` rate-map retention & handoff/heartbeat overlap — prune departed peer keys and guard heartbeat during handoff. |
| **P3-2** | `CombatController.gd` | Un-gated `_on_weapon_switch_requested`/`apply_pickup` and `reset_state` cooldown/token cleanup. |
| **P3-3** | `FollowCam.gd`, `DestructibleBuilding.gd` | `FollowCam` antiparallel lerp singularity; `DestructibleBuilding` continues `_process` post-smash (call `set_process(false)`). |
| **P3-4** | `SideCannons.gd`, `UiTheme.gd`, `AGENTS.md` | Duplicate `_cooldown` & non-reactive muzzle/flame quality; `DestructibleBuilding` null `parent`; `UiTheme.apply_safe_area` null `margin`; `AGENTS.md` pck size drift. |
| **P3-5** | `godot/tools/deploy_web.sh:L30-40, L48-51` | `mktemp` failure leaves `SETTINGS_BAK` empty so `cleanup()` deletes `SETTINGS_CFG`; failed `run_gates.sh` skips `git checkout -- godot/scenes/`. |
| **P3-6** | `src/qb_weapons.py:L80-108` | `Cannon_Barrel`, `Cannon_Muzzle_Ring`, `Cannon_Bore` coplanar front caps at `y = tip_y` cause Z-fighting. |
| **P3-7** | `src/build_quad.py:L294-321`, `src/repair_and_verify.py:L67-70, L118` | `stats()` scans `Studio/Ground` (`30×30 m`); `repair_and_verify.py` copies GLB before round-trip verify and uses `read_homefile` instead of `open_mainfile`. |
| **P3-8** | `src/build_pogo_nardus.py:L49-51, L602, L869-888`, `qb_body.py:L456-465` | `dec_img.pack()` omitted, QA metrics printed without `assert`, unsafe `argv[idx+1]`; `Grip_L/R` & `Bar_End_L/R` rotate around own symmetry axis. |
| **P3-9** | `src/gen_decal_nardus.py:L21-25`, `src/gen_plate_bigben.py:L21-25`, `src/qb_core.py:L319-327, L496-500` | `ImageFont.load_default()` ignores `size`; `_smooth_cyl()` cap check is always `False` on `MB.cylinder()`; `set_origin()` breaks on rotated/parented objects. |
| **P3-10** | `godot/tools/verify_settings.gd:L100`, `verify_cannons.gd:L32-43`, `truth_test.gd:L33` | `show_fps` written to `"gameplay"` instead of `"video"`; `verify_cannons` checks `Muzzle_L/R` before authoritative `Cannon_Bore_L/R`; `truth_test` velocity check is unsigned. |
| **P3-11** | `godot/tools/patch_web_html.py:L34` | Fixed predictable `index.html.tmp` path instead of `tempfile.mkstemp(..., dir=str(path.parent))`. |

---

## 4. Pass 3: Real Mental Mutation Table (`10 / 20 = 50.0%`)

| # | File & Line | Mutation (Type) | Result | Killing Gate / Why It Survives |
|---:|---|---|---|---|
| 1 | `TaloBackend.gd:L646` | Bypass `host_id` check on `state` (`M2`) | **KILLED** | `verify_audit_regressions.gd` (`_state_spoof`) |
| 2 | `TaloBackend.gd:L720` | Allow `register_kill` when `status == "waiting"` (`M2`) | **KILLED** | `verify_talo_backend.gd` (`L91-94`) |
| 3 | `TaloBackend.gd:L735` | Skip `token_consumed` check (`M1`) | **KILLED** | `verify_talo_backend.gd` (`L70-73`) |
| 4 | `TaloBackend.gd:L758` | Allow `register_lap` in `battle_royale` (`M2`) | **KILLED** | `verify_talo_backend.gd` (`L174-176`) |
| 5 | `ArenaNet.gd:L302` | Drop `o.size() == 3` check (`M2`) | **KILLED** | `verify_audit_regressions.gd` (`_malformed_shot`) |
| 6 | `MatchState.gd:L153` | Allow `respawn_delay < 0.5` (`M3`) | **KILLED** | `verify_match_rules.gd` |
| 7 | `VehicleHandling.gd:L22` | Return `0.0` from `effective_steer_cap` (`M4`) | **KILLED** | `verify_controls.gd` |
| 8 | `RaceTracker.gd:L145` | Count FinishLine without checkpoints (`M2`) | **KILLED** | `verify_deathrace.gd` (`L291-293`) |
| 9 | `VfxCore.gd:L52` | Collapse 3-stop `_ramp` to 2 stops (`M1`) | **KILLED** | `verify_vfx.gd` (`L69-73`) |
| 10 | `Settings.gd:L40` | Default `video/fullscreen = false` (`M3`) | **KILLED** | `verify_settings.gd` |
| 11 | `TaloBackend.gd:L912` | Delete `if _channel_id <= 0: return` (`M1`) | **SURVIVED** | `verify_audit_regressions.gd:L71` & `verify_talo_backend.gd:L197` capture `int` by value → `sig == 0` always true |
| 12 | `ArenaNet.gd:L381` | Delete `REMOTE_PROJ_POOL_SIZE` cap (`M1`) | **SURVIVED** | `verify_vfx.gd:L519-528` runs on empty `_remote` → asserts `0 <= 32` |
| 13 | `MatchState.gd:L88` | Delete `_refresh_settings_cache()` in `clear_lobby()` (`M1`) | **SURVIVED** | `verify_match_rules.gd:L60-64` never mutated `game_mode`/`damage` before `leave()` |
| 14 | `MatchHud.gd:L683` | Remove `is_instance_valid` in kill-feed timer (`M1`) | **SURVIVED** | `verify_accessibility.gd:L197` waits `0.15 s` for a `4.0 s` timer |
| 15 | `KiepieBike.gd:L603` | Remove `_dodge_cd > 0.0` guard (`M2`) | **SURVIVED** | `verify_dodge.gd:L68` only asserts `cd > 0.0` (resetting `cd = 1.0` still passes) |
| 16 | `ArenaNet.gd:L179` | Delete `if killer == Supabase.user_id` (`M2`) | **SURVIVED** | `verify_kill_flow.gd:L47-53` reuses same token/victim, short-circuiting earlier |
| 17 | `KiepieBike.gd:L46` | Flip `+Z` forward axis to `-Z` (`M3`) | **SURVIVED** | `truth_test.gd:L33` checks unsigned `linear_velocity.length() > 5.0` |
| 18 | `CombatController.gd:L250` | Ignore `_shield_until` in `take_damage()` (`M2`) | **SURVIVED** | `verify_combat.gd` never tests normal `take_damage` blocked by shield |
| 19 | `Pickup.gd:L65` | Make `Pickup._on_body_entered` a no-op (`M1`) | **SURVIVED** | `verify_appeal.gd:L40-41` only counts `Pickup*` nodes; 0 behavioral tests |
| 20 | `HazardPit.gd:L110` | Make `HazardPit` deal `0.0` damage (`M3`) | **SURVIVED** | `verify_deathrace.gd:L550-559` only tests negative proxy case |

---

## 5. Execution-Grade 4-Phase Remediation Plan

### Phase 1 — Runtime Gameplay, Networking & Web Accessibility P1s (Commits 1–3)
- **Targets:** `P1-1` (`TaloBackend._join_gen`), `P1-2` (`VfxFactory` signatures), `P1-3` (environmental `"hazard-pit"` / `"env:hazard-pit:*"` kill flow + `"MOLTEN PIT"` label), `P1-4` (`ArenaNet._spawn_remote_shot` + `TaloBackend` `"shot"` playing-state gate preserving `not Match.lobby.is_empty()`), `P1-5` (`hit_any_enemy = true` before `skip_proxy`), `P1-6` (`index.html` + `export_presets.cfg` `html/head_include` `click` + `Enter`/`Space` on `#victory-skip` & `#splash-skip`), plus `P2-1`..`P2-4` and `P3-1`..`P3-4`.
- **Pre-Fix Failing Regression Proofs (write & run BEFORE applying each fix):**
  1. `P1-1`: Start `_join_auto()` with `gen=1`, bump `_join_gen` via `leave_lobby_channel()`, resolve mock response → assert Channel B is not left/overwritten (fails pre-fix).
  2. `P1-2`: Call `VfxFactory.particle_explosion(holder, Vector3.ZERO, Color.ORANGE, 1.0)` (4-arg) → assert 0 mushroom stem emitters; call `VfxFactory.dust_ring(holder, Vector3.ZERO, 1.0)` (3-arg) → assert scale `< 10.0` (fails pre-fix: spawns mushroom + 57 m ring).
  3. `P1-3`: Call `CombatController._die("hazard-pit", "")` → assert `"kill"` broadcast has `killer == "hazard-pit"` and `token.begins_with("env:")`, and `ArenaNet._on_broadcast("kill", ...)` hides proxy & adds `"MOLTEN PIT"` feed row without incrementing score (fails pre-fix: dropped).
  4. `P1-4`: Set `Match.lobby = {"id":"1","status":"finished"}` and call `ArenaNet._spawn_remote_shot(...)` → assert 0 projectiles spawned (fails pre-fix: spawns projectile).
  5. `P1-5`: Fire Rocket at visible `NetworkedBike` proxy → assert `hit_confirmed` emitted (fails pre-fix: suppressed).
  6. `P1-6`: In Chromium probe, `victorySkip.focus(); victorySkip.click()` → assert `dismissedByEnterOrClick === true` (fails pre-fix: `false`).

### Phase 2 — Test Suite Integrity, Settings Isolation & Hollow-Test Eradication (Commits 4–6)
- **Targets:** `P1-11` (all 9 hollow tests), `P1-12` (shared `user://settings.cfg` backup/restore + `"auto"` reset helper across all mutating gates & GdUnit `after_test()`), `P2-12` (`run_gates.sh` builder timeouts, `SCRIPT ERROR` checks in builders/GdUnit, `LOGDIR` cleanup), `P2-13` (`check_scene_sync.py` body-hashed subresources, `check_web_hygiene.py` isolated `.vercelignore` + `export_presets.cfg`/SW parity), `P2-15` (behavioral gates for `Pickup.gd`, `HazardPit.gd` positive tick, `Projectile.gd` raycast, `FollowCam.gd`, `Sfx.gd`, `LobbyMenu.gd`, `truth_test.gd` signed `+Z` check, full 47-script `_check_scripts.gd`), and `P3-10`.
- **Target:** `M_kill >= 90%` (`18+ / 20` mutants killed).

### Phase 3 — Blender 3D Models, Scene Builders & Media/SFX Pipeline (Commits 7–9)
- **Targets:**
  - `P1-7` & `P2-11` (`build_aston_martin.py` ExhaustPipe pivot + `+tilt` rear plate → rebuild `Aston_Martin.glb`, verify `Floor_me` bounds symmetric & `minZ == 0.000`).
  - `P1-8` & `P1-9` (`build_quad.py`, `qb_wheels.py`, `qb_body.py` → rebuild via `blender -b -noaudio -P src/repair_and_verify.py` + `blender_qa_reviewer.py`, target `APPROVED`, `non_manifold_edges == 0`, `minZ == 0.000`, `Wheel_FL.trans.y == 0.0`).
  - `P2-5`, `P2-6`, `P2-7`, `P2-8` (`build_arena.gd` CameraRig + `SpeedLabel`, `build_testride.gd` CameraRig + single `_add_cones`, `build_deathrace.gd` shared loop deck/rail `BoxMesh`/`BoxShape3D` reducing `.tscn`/`index.pck` size, `TouchControls.gd` TestRide narrow `BtnTouchToggle` alignment; regenerate `.tscn` via `run_gates.sh` and commit builders + `.tscn` together).
  - `P2-9` (`generate_sfx.py` phase-accumulated `pop()`, fade ramps on `dink`/`scrape`, drop `out[-1] = out[0]`, atomic writes + regenerate WAVs).
  - `P2-10` (`build_victory_splash.py` `NardusRoot` + fanfare release fades + atomic ffmpeg w/ timeout; `build_intro_splash.py` phase-accumulated riser + `Path.is_file()` font guard) & `P3-6`..`P3-9`.

### Phase 4 — Deploy/SW Hardening, Structural Decomposition & Web Re-Export (Commits 10–11)
- **Targets:** `P1-10` (`deploy_web.sh` `index.pck >= 1 MiB`, `timeout 240`, stage-validate before root sync, rollback on failure; `patch_web_sw.py` fail-fast on all 7 patches, raise on missing `.wasm`/`.pck`, fix `index.manifest.json`, clear `ENGINE_CACHE`), `P3-5`, `P3-11`, optional God-file split (`P2-14`: extract `TaloChannelSync.gd` from `TaloBackend.gd` and `MatchHudFeed.gd` from `MatchHud.gd` behind green Phase 1–2 tests), and final `bash godot/tools/deploy_web.sh` dry-run verification (`--apply` only when explicitly requested).

### Pitfall & Rollback Guards
- Never hand-edit `.tscn` files (`check_scene_sync.py` enforces parity with `build_*.gd`).
- Never upgrade `godot/addons/talo/` (pinned `0.20.0` for Godot 4.3).
- Keep `KIEPIE_MOCK_BACKEND=1` in all gates; preserve `not Match.lobby.is_empty()` in `ArenaNet._spawn_remote_shot()`.
- Always run `repair_and_verify.py` + `blender_qa_reviewer.py` after Blender edits.
