# Surgical Audit Report: Kiepie Quad Web (Full Codebase — 2026-11-25)

| Audit Metadata | Specification |
| :--- | :--- |
| **Audit Date** | 2026-11-25 |
| **Audited Scope** | First-party repo (`godot/src/`, `godot/tools/`, `godot/tests/`, `src/`, `godot/assets/sfx/generate_sfx.py`, `.github/workflows/`, `index.html`, `index.service.worker.js`, `vercel.json`, `.vercelignore`, `godot/export_presets.cfg`; excluding vendored `godot/addons/`, generated `index.js`/`index.wasm`/`index.pck`, generated `*.tscn`, `docs/`, `supabase/`, `renders/`, `web/`) — `121` code files + `5` root/config files (`33,214` effective code LOC + `199` HTML lines = `33,413` scored effective LOC) |
| **Tech Stack & Runtime** | GDScript (Godot 4.3 Web / GLES3), Python 3 (Blender 5.3 `bpy` + build/export/SFX tooling), Vanilla HTML/CSS/JS (WASM shell + Service Worker), Talo v0.20.0, Vercel Static Edge + GitHub Actions |
| **Pre/Post Audit SHA-256** | `4a251ac5793cf74f` / `4a251ac5793cf74f` (VERIFIED ZERO MUTATION before report write — full porcelain hash `4a251ac5793cf74f59f57529e66d6f38adddb148f2fdbbf8b2770cdcb0196aeb`, `HEAD`: `786a7bc27f93e61ca46d31e43f68ed5a50d525e7`) |
| **Deterministic Health Score** | **`88 / 100`** (`D_raw = 45`, `scale_factor = 0.172998`, `P_test = 4.2188`, `M_kill = 71.88%` [`23/32`]) |
| **Vibe-Debt Risk Level** | **`LOW`** (`>=85`, `P0 = 0`) |
| **Companion SARIF** | `docs/audits/kiepie-quad-surgical-audit-2026-11-25.sarif` |

> [!NOTE]
> **Dirty Working Tree & `[IN-PROGRESS]` Caveat:** Per user instruction, this audit evaluates the working tree **as-is** against a clean `git archive HEAD` (`786a7bc`) baseline in `/tmp/kq_baseline`. Uncommitted Evan changes (`EvanVisual.gd`, `BoomerangGuitar.gd`, `DevilHandStrike.gd`, `SideCannons.gd`, `src/build_evan_skeleton.py`, `verify_evan*.gd`) and `[IN-PROGRESS]` files from another session (`KiepieBike.gd`, `ArenaNet.gd`, `NetworkedBike.gd`, `VehicleRegistry.gd`, `MainMenu.gd`, `build_menus.gd`, `run_gates.sh`, `check_web_hygiene.py`, `verify_aston.gd`, plus untracked/new Lea Unicorn files `LeaVisual.gd`, `HornBoltProjectile.gd`, `HornBeam.gd`, `UnicornBoom.gd`, `src/build_lea_unicorn.py`, `verify_lea_*.gd`) are audited together and explicitly tagged `SHIPPED` vs `WORKTREE-ONLY` and `[IN-PROGRESS]`.

---

## 1. Executive Architecture & Vibe-Debt Triage

Compared against the `2026-11-24-rev2` (`81/100`) and `2026-11-25-evan` (`62/100`) audits, nearly every prior P1/P2 defect has been closed: `TaloBackend` `_join_gen` zombie eviction & `join_lobby_channel` races, `LobbyService._enter_if_current` stale cleanup, `ArenaNet` shot trust boundary, `patch_web_sw.py` strict markers, `run_gates.sh` anti-vacuity evidence checks, `deploy_web.sh` atomic staging sync, and `EvanVisual` remote speed clamping are all **FIXED**, bringing all **33/33 worktree gates green** and lifting deterministic health to **`88 / 100` (`LOW`)** with **0 P0** defects. The remaining primary failure mode is concentrated in **1 P1** visual/gameplay bug in `[IN-PROGRESS]` `HornBeam.gd` (where `PlasmaBeam` spawns centered at `-_direction * span * 0.5` behind Lea Unicorn), **8 P2** defects (`CombatAoe.apply_lethal_blast()` unreachable `hit_any_enemy` suppressing kill markers, missing `is_finite`/clamp/free guards in `DevilHandStrike`/`RocketProjectile`/`MeteorStrike`, `SideCannons.fire()` post-`await` respawn race, `index.pck` at `4.47 / 4.50 MiB` leaving only `32.7 KB` headroom, `.github/workflows/gates.yml` missing `permissions: contents: read`, 4 older Blender builders missing `save_version = 0`, and 5 runtime god files >500 eff LOC), and **13 P3** polish/contract items. Shipped asset checks confirm `UNSHIPPED_IN_PCK=0` and all 5 GLBs score `90–95/100` (`31–200` draw calls, `<= 44,312` tris); live `https://kiepie-quad-web.vercel.app/` HTTP/2 `200` headers enforce `COOP`/`COEP`/`CORP`/`HSTS`/`nosniff`.

| Severity Tier | Count | Deduction Weight | Primary Failure Domains |
| :--- | :--- | :--- | :--- |
| **P0 — Critical (Crash / Data Loss / Security / Leak)** | `0` | `-18 pts ea` | `None` |
| **P1 — High (Frame-Budget / Race / Logic Bug)** | `1` | `-8 pts ea` | `HornBeam.gd` (`PlasmaBeam` spawns behind caster `-_direction`, `[IN-PROGRESS]`) |
| **P2 — Medium (God File / Split-Brain State / Debt)** | `8` | `-3 pts ea` | `CombatAoe.gd` (`hit_any_enemy` unreachable), `DevilHandStrike.gd` (missing `queue_free`/NaN check), `RocketProjectile.gd`/`MeteorStrike.gd` (missing NaN/clamp), `SideCannons.gd` (post-`await` respawn race), `gates.yml` (`permissions`), `deploy_web.sh` (`index.pck` `32.7 KB` headroom), older Blender `save_version = 0`, 5 runtime god files (`>500` eff LOC) |
| **P3 — Low (Magic Constants / DX / Portability)** | `13` | `-1 pt ea` | `CombatAoe.apply_blast` authority/unused `sqrt`, `TaloProtocol.parse_dict` `JSON.new()`, `TaloBackend` channel switch/handoff wait, `ArenaNet` signal disconnect, `MatchState` empty `uid`, `HornBeam` `hit(null)`/`_finish` nesting, dual hit channels, `PogoVisual`/phase accumulators, `VehicleRegistry`/`MainMenu`/`KiepieBike` 5-way vocab, `VfxHeavy` low-quality lights, `MatchHud`/`TouchControls` `section == "*"` reset, `run_gates.sh`/`check_web_hygiene.py`/scene builders |

### High-Risk File Telemetry Hotspots

| File Path | Effective LOC | Branch Density | Silent Catches | Primary Vibe-Debt Signature |
| :--- | :--- | :--- | :--- | :--- |
| `godot/tools/build_deathrace.gd` | `1495` | `0.008` | `0` | Monolithic procedural track builder (`[P3-13]` omits `root.free()`) |
| `src/build_evan_skeleton.py` | `1052` | `0.087` | `0` | Large Blender rig + 7-clip NLA builder (intentional generator) |
| `godot/src/net/TaloBackend.gd` | `995` | `0.054` | `0` | God net/lobby FSM (`[P2-8]`, `[P3-3]`, `[P3-4]`) |
| `godot/src/game/DevilHandStrike.gd` | `810` | `0.033` | `0` | Procedural 3D mesh + vein/nail + strike FSM (`[P2-2]`, `[P2-8]`) |
| `godot/src/ui/MatchHud.gd` | `758` | `0.044` | `0` | God HUD + radar + scoreboard (`[P2-8]`, `[P3-11]`) |
| `godot/src/game/SideCannons.gd` | `685` | `0.096` | `0` | God weapon controller + 5-profile branching (`[P2-4]`, `[P2-8]`) |
| `godot/src/KiepieBike.gd` `[IN-PROGRESS]` | `637` | `0.090` | `0` | God vehicle controller + duplicated assignment (`[P2-8]`, `[P3-9]`) |
| `godot/src/ui/MobileTextInput.gd` | `385` | `0.034` | `4` | iOS/Web JS bridge `try/catch` fallbacks (intentional defensive guards) |

### Prior Audit Carry-Forward Delta (`2026-11-24-rev2` & `2026-11-25-evan`)

| Prior ID (Source) | Summary | Status | Evidence |
| :--- | :--- | :--- | :--- |
| `rev2 [P1-1]` | `TaloBackend` `_join_gen` self-invalidation on zombie eviction | **FIXED** (`SHIPPED`) | `TaloBackend.gd:L308-L313,L476,L531` (`bump_join_gen=false`) |
| `rev2 [P1-2]` | `TaloBackend.join_lobby_channel()` async race | **FIXED** (`SHIPPED`) | `TaloBackend.gd:L279-L306` (`gen := _join_gen` + seq reset) |
| `rev2 [P1-3]` | `LobbyService._enter_if_current()` stale cleanup | **FIXED** (`SHIPPED`) | `LobbyService.gd:L9-L10,L38-L47` (`_session_gen` guard) |
| `rev2 [P1-4]` | `patch_web_sw.py` silent-skip SW patches | **FIXED** (`SHIPPED`) | `patch_web_sw.py:L36-L246` + `test_patch_web_sw.py` (`RuntimeError`) |
| `rev2 [P1-5]` | Fresh-checkout `talo_backend` failure (`settings.cfg` gitignored) | **FIXED** (`SHIPPED`) | `run_gates.sh:L87-L109` (verified `talo_backend` PASS in `/tmp/kq_baseline`) |
| `evan [P1-1]` | `ArenaNet.gd` shot trust boundary | **FIXED** (`SHIPPED`) | `ArenaNet.gd:L314-L381,L433-L446` (roster, kind, token, `12/s` cap) |
| `evan [P1-2]` | `run_gates.sh` vacuity acceptance | **FIXED** (`SHIPPED`) | `run_gates.sh:L35-L55` (`GATE_EVIDENCE_RE` min count) |
| `evan [P1-3]` | `deploy_web.sh` non-atomic sync & verification | **FIXED** (`SHIPPED`) | `deploy_web.sh:L48-L55,L114-L163` (`BUNDLE_BAK` + `md5sum` + 8-file curl) |
| `rev2 [P2-1..6]` | Pool eviction, first-pos init, 8-player cap, `_gate_settings_guard`, `verify_audit_regressions`, `check_scene_sync` | **FIXED** (`SHIPPED`) | `SideCannons.gd:L780`, `NetworkedBike.gd:L149`, `TaloBackend.gd:L1028`, `_gate_settings_guard.gd:L39`, `verify_audit_regressions.gd:L353`, `check_scene_sync.py:L85` |
| `rev2 [P2-7]` | God-file concentration (`>500` eff LOC) | **OPEN** (`[P2-8]`) | `TaloBackend`, `DevilHandStrike`, `MatchHud`, `SideCannons`, `KiepieBike` |
| `evan [P2-1,3,4,6]` | Remote Evan `lerpf` divergence, Boomerang `hit` conflation, `DevilHandStrike` bounds, pool reset | **FIXED** (`WORKTREE-ONLY` / `SHIPPED`) | `EvanVisual.gd:L255`, `BoomerangGuitar.gd:L425`, `DevilHandStrike.gd:L415`, `SideCannons.gd:L801` |
| `evan [P2-2]` | `CombatAoe.apply_lethal_blast()` implicit lethal authority | **FIXED** (left `[P2-1]` regression) | `CombatAoe.gd:L131-L147` |

### Pass 2.5 Runtime, Asset & Web Shell Evidence

- **Host Contention:** `uptime` load average `1.04, 1.25, 1.21` (low contention).
- **Worktree Gate Suite (`bash godot/tools/run_gates.sh --no-build`):** **PASS — 33/33 gates green**, `git status --porcelain | sha256sum` verified identical (`SHA_UNCHANGED`).
- **Fresh-Checkout Baseline (`/tmp/kq_baseline` from `git archive HEAD 786a7bc`):** `30/33` pass; `talo_backend` **PASS**. Three expected baseline failures: `scene_sync` (no `.git` dir in `git archive`), `web_hygiene` (`os.walk` fallback without `git check-ignore` flags `docs/index.md`), and `evan` (missing `Run_NoGuitar`/`Action_GuitarThrow`/`Action_GuitarCatch` clips in `HEAD`, present in worktree).
- **GLB Asset Budgets (`preflight_gltf_budget.py --tier medium`):** `Kiepie_Bike.glb` `90/100` (`44,312` tris, `200` draws), `Pogo_Nardus.glb` `90/100` (`12,992` tris, `31` draws), `Aston_Martin.glb` `90/100` (`8,040` tris, `35` draws), `Evan_Skeleton.glb` `95/100` (`8,026` tris, `73` draws, `7` anims), `Lea_Unicorn.glb` `95/100` (`7,530` tris, `86` draws, `4` anims). Only advisory is intentional non-Draco GLBs for Godot 4.3 Web.
- **Shipped PCK & Live Vercel:** `UNSHIPPED_IN_PCK=0` (all `godot/src/**/*.gd` verified inside `index.pck`); `index.pck = 4,685,872` bytes (`4.47 MiB` vs `4.50 MiB` cap). `curl -sI https://kiepie-quad-web.vercel.app/` returned `HTTP/2 200` with `COOP: same-origin`, `COEP: require-corp`, `CORP: same-origin`, `HSTS`, and `X-Content-Type-Options: nosniff`.
- **Browser Probe Caveat:** `canvas_geometry_probe.mjs --wcag` could not execute because Node `playwright` is not installed in this environment (`ERR_MODULE_NOT_FOUND`); accessibility/layout coverage relies on `verify_accessibility.gd` (`56` checks) and `check_web_hygiene.py`.

---

## 2. The 10-Principal-Engineer Deep Audit (+ Lens 11)

### Lens 1: Systems Architect

- **[P2-1] Unreachable `hit_any_enemy = true` in `CombatAoe.apply_lethal_blast()` Suppresses `hit_confirmed` on Kills** — `godot/src/game/CombatAoe.gd:L131-L147` (`SHIPPED`)
  - **Root Cause Mechanism:** `L131-L132` fail-closed guard executes `if local_uid == "" or target_id == "" or target_id != local_uid: continue`, guaranteeing `target_id == local_uid` for the rest of the loop body. Consequently, `L145-L146` (`if owner_id != "" and owner_id == local_uid and target_id != local_uid: hit_any_enemy = true`) is mathematically unreachable dead code.
  - **Deterministic Trigger & Failure Mode:** Whenever the local player kills an enemy rider with Devil Hand or Unicorn Boom (without igniting a fuel drum), `apply_lethal_blast()` returns `false` and never emits `local_combat.hit_confirmed`, silently dropping hit-marker/audio feedback.
  - **Surgical Fix Specification:** Evaluate `if owner_id != "" and owner_id == local_uid and target_id != local_uid: hit_any_enemy = true` *before* the `target_id != local_uid` `continue` at `L131`.

- **[P2-8] God-File Concentration Across 5 Core Runtime Scripts (`>500` Effective LOC)** — `godot/src/net/TaloBackend.gd:L1-L1185`, `godot/src/game/DevilHandStrike.gd:L1-L901`, `godot/src/ui/MatchHud.gd:L1-L902`, `godot/src/game/SideCannons.gd:L1-L806`, `godot/src/KiepieBike.gd:L1-L776` `[IN-PROGRESS]` (`SHIPPED` / `WORKTREE-ONLY`)
  - **Root Cause Mechanism:** Carry-forward `rev2 [P2-7]`: networking/lobby FSM, procedural mesh generation + strike FSM, HUD/radar/scoreboard, 5-vehicle weapon profiles + pooling, and vehicle chassis/VFX/assignment remain monolithic.
  - **Deterministic Trigger & Failure Mode:** Elevated regression density when editing any vehicle or lobby flow.
  - **Surgical Fix Specification:** Extract `TaloSessionTransport.gd` / `TaloLobbyStore.gd`, `WeaponProfiles.gd`, `RadarControl.gd`, and `DevilHandMesh.gd`.

- **[P3-9] Hand-Maintained 5-Vehicle Vocabularies & Settings Fallback in Net Matches** — `godot/src/game/VehicleRegistry.gd:L8-L56`, `godot/src/ui/MainMenu.gd:L16`, `godot/src/KiepieBike.gd:L253-L346` `[IN-PROGRESS]` (`SHIPPED`)
  - **Root Cause Mechanism:** `MainMenu.gd:L16` duplicates `VEHICLE_IDS` independently of `VehicleRegistry.gd`, `VehicleRegistry.gd` repeats 5-way `match` blocks, and `KiepieBike._resolve_vehicle_pref()` falls back to `Settings.preferred_vehicle()` even when `Match.is_playing()`.
  - **Surgical Fix Specification:** Consolidate `VehicleRegistry.SPECS` into one dictionary, expose `ALL_IDS` to `MainMenu.gd`, and restrict `Settings` fallback in `KiepieBike.gd` to non-playing/practice mode.

### Lens 2: Frame-Budget & Performance

- **[P3-2] Unused `sqrt` in `CombatAoe.apply_lethal_blast()` & `JSON.new()` Allocation in `TaloProtocol.parse_dict()`** — `godot/src/game/CombatAoe.gd:L125`, `godot/src/net/TaloProtocol.gd:L16-L22` (`SHIPPED`)
  - **Root Cause Mechanism:** `CombatAoe.gd:L125` computes `var dist := sqrt(dist_sq)` and never reads `dist`. `TaloProtocol.parse_dict()` instantiates `JSON.new()` on every call instead of `JSON.parse_string(text)`.
  - **Surgical Fix Specification:** Remove `L125` in `CombatAoe.gd`; switch `TaloProtocol.gd:L19-L22` to `JSON.parse_string(text)`.

- **[P3-10] `VfxHeavy.gd` Dynamic `OmniLight3D` Spawns Ignore Low-Quality Multiplier** — `godot/src/game/VfxHeavy.gd:L32-L38,L491-L497,L577-L583` (`SHIPPED`)
  - **Root Cause Mechanism:** `particle_explosion()`, `lightning_strike_explosion()`, and `cash_explosion()` allocate `OmniLight3D` even when `Settings.quality_multiplier() < 0.5` (unlike `VfxCore.gd:L49,L147`).
  - **Surgical Fix Specification:** Guard `OmniLight3D` creation in `VfxHeavy.gd:L32,L491,L577` with `if Settings.quality_multiplier() >= 0.5:`.

### Lens 3: Mathematical, Physics & Algorithmic

- **[P1-1] `HornBeam.gd` `PlasmaBeam` Mesh Placed Backwards (`-_direction`) & Charge Ring Offset in Parent Frame** — `godot/src/game/HornBeam.gd:L178,L252-L260` (`SHIPPED`, `[IN-PROGRESS]`)
  - **Root Cause Mechanism:** `_start_beam()` orients `_beam.basis = Basis.looking_at(_direction, ...)` and sets `_beam.position = -_direction * (span * 0.5)`. In world-aligned `HornBeam` space, `+_direction * (span * 0.5)` is forward toward the raycast target, so `-_direction` places the 55 m cylinder *behind* Lea Unicorn. Similarly, `L178` sets `_charge.position.z = -0.55` in world space instead of `_charge_ring.position.z = -0.55`.
  - **Deterministic Trigger & Failure Mode:** Every time Lea Unicorn fires her Horn Beam (`rocket` slot), damage rays trace forward along `+_direction` while the visible plasma beam shoots backwards out the rear of the unicorn.
  - **Surgical Fix Specification:** Change `HornBeam.gd:L256` to `_beam.position = _direction * (span * 0.5)` and `L178` to `_charge_ring.position.z = -0.55`.

- **[P3-8] Unclamped Remote Speed Estimator in `PogoVisual.gd` & Unbounded Phase Accumulators** — `godot/src/game/PogoVisual.gd:L197-L202`, `godot/src/game/EvanVisual.gd:L329`, `godot/src/game/LeaVisual.gd:L238` `[IN-PROGRESS]`, `godot/src/DestructibleBuilding.gd:L202-L215` (`SHIPPED` / `WORKTREE-ONLY`)
  - **Root Cause Mechanism:** `PogoVisual.gd` computes `disp / dt` without `maxf(dt, 0.001)` or `[0.0, 60.0]` clamping; `_run_phase`, `_gallop_phase`, and `_beacon_t` increment without `fmod(..., TAU)`.
  - **Surgical Fix Specification:** Clamp `PogoVisual` remote speed to `[0.0, 60.0]` with `maxf(dt, 0.001)` and wrap phase accumulators with `fmod(..., TAU)`.

### Lens 4: Concurrency, Async & Determinism

- **[P2-4] `SideCannons.fire()` Post-`await` Stale Shot on Death/Respawn** — `godot/src/game/SideCannons.gd:L539-L547` (`SHIPPED`)
  - **Root Cause Mechanism:** `fire()` sets `_cooldowns[active_weapon]` and `await`s `Match.issue_shot()`, then checks `alive` and `Match.is_playing()`. If the rider dies and respawns during the async `await`, `alive` is `true` again on resume.
  - **Deterministic Trigger & Failure Mode:** A shot triggered immediately before death fires from the respawn transform after respawn.
  - **Surgical Fix Specification:** Add a `_fire_gen: int` counter incremented in `setup()` and `reset_cooldowns()`, and abort after `await Match.issue_shot()` if `gen != _fire_gen`.

- **[P3-3] `TaloBackend.join_lobby_channel()` Overwrites Active `_channel_id` Without Leaving Prior Channel** — `godot/src/net/TaloBackend.gd:L279-L306` (`SHIPPED`)
  - **Root Cause Mechanism:** `if _channel_id == id or id <= 0: return` does not leave `_channel_id` when switching to a different `id`.
  - **Surgical Fix Specification:** Call `leave_lobby_channel(false)` if `_channel_id > 0 and _channel_id != id` before awaiting `Talo.channels.join(id)`.

- **[P3-4] `TaloBackend._handoff_host_before_leave()` Does Not Await `_apply_inflight`** — `godot/src/net/TaloBackend.gd:L586-L625,L655-L689` (`SHIPPED`)
  - **Root Cause Mechanism:** `_handoff_host_before_leave()` can issue a `PUT` concurrently with an in-flight heartbeat `_apply_props()` `PUT`.
  - **Surgical Fix Specification:** Await `_apply_drained` when `_apply_inflight` is true before sending the handoff `PUT`.

### Lens 5: Memory & Resource Lifecycle

- **[P2-2] `DevilHandStrike.setup()` Leaks Node on Invalid-Arg Rejection & Leaves `p_target_pos` Unchecked** — `godot/src/game/DevilHandStrike.gd:L415-L427` (`WORKTREE-ONLY` / `SHIPPED`)
  - **Root Cause Mechanism:** Rejection at `L415-L417` returns without `queue_free()`, leaving an orphan `DevilHandStrike` in `fx_parent`; `p_target_pos` and `p_fall_duration` also lack `is_finite()`.
  - **Deterministic Trigger & Failure Mode:** Rejected strikes leak nodes until scene exit; non-finite `p_target_pos` propagates `NaN` into `CombatAoe.apply_lethal_blast()`.
  - **Surgical Fix Specification:** Validate `is_finite()` on `p_target_pos` and `p_fall_duration` and call `queue_free()` before returning on rejection.

- **[P3-5] `ArenaNet._exit_tree()` Misses Signal Disconnect & `MatchState._on_pg_change()` `"UPDATE"` Allows Empty `user_id`** — `godot/src/game/ArenaNet.gd:L55,L122-L125` `[IN-PROGRESS]`, `godot/src/net/MatchState.gd:L397-L406` (`SHIPPED`)
  - **Root Cause Mechanism:** `ArenaNet._exit_tree()` disconnects `_sync_roster` but not `_on_roster_changed_for_spawn`; `MatchState._on_pg_change()` `"UPDATE"` omits `if uid == "": return`.
  - **Surgical Fix Specification:** Disconnect `_on_roster_changed_for_spawn` in `_exit_tree()` and guard `uid == ""` in `MatchState.gd:L399`.

### Lens 6: Security & Trust-Boundary (+ Supply Chain / Matrix D)

- **[P2-5] `.github/workflows/gates.yml` Lacks Explicit `permissions: contents: read`** — `.github/workflows/gates.yml:L1-L36` (`SHIPPED`)
  - **Root Cause Mechanism:** Workflow relies on org/repo default `GITHUB_TOKEN` permissions instead of least-privilege `permissions: contents: read`.
  - **Surgical Fix Specification:** Add `permissions:\n  contents: read` at the top level of `.github/workflows/gates.yml`.

- **[P3-1] `CombatAoe.apply_blast()` Lacks Explicit Local-Victim Authority Guard** — `godot/src/game/CombatAoe.gd:L58-L60` (`SHIPPED`)
  - **Root Cause Mechanism:** Unlike `apply_lethal_blast()` (`L131`), `apply_blast()` invokes `take_damage` on any `bike` child exposing it without asserting `target_id == local_uid`.
  - **Surgical Fix Specification:** Add `if local_uid == "" or target_id == "" or target_id != local_uid: continue` before `controller.call("take_damage", ...)`.

### Lens 7: Reliability & Fault Tolerance

- **[P2-6] `index.pck` Deploy Budget Headroom Exhausted to `32.7 KB` (`4.47 / 4.50 MiB`)** — `godot/tools/deploy_web.sh:L82-L90` (`SHIPPED`)
  - **Root Cause Mechanism:** Root `index.pck` is `4,685,872` bytes against the `4,718,592`-byte (`4.5 MiB`) abort cap in `deploy_web.sh:L87`.
  - **Deterministic Trigger & Failure Mode:** Any modest asset addition causes `deploy_web.sh` to abort.
  - **Surgical Fix Specification:** Trim redundant assets/exports in `godot/` or bump/document the cap in `deploy_web.sh` + `AGENTS.md`.

- **[P3-6] `HornBeam.gd` Unconditional `hit.emit(null, end_point)` & Guarded `_finish()`** — `godot/src/game/HornBeam.gd:L262,L336-L344` (`SHIPPED`, `[IN-PROGRESS]`)
  - **Root Cause Mechanism:** Emits `hit(null, ...)` before checking hits, and nests `_finish()` inside `if _beam != null:`.
  - **Surgical Fix Specification:** Remove `L262` and move `if _age >= CHARGE_TIME + BEAM_TIME: _finish()` outside `if _beam != null:`.

- **[P3-7] Dual Hit Channels (`hit.emit` + `on_hit.call`) Without Idempotency Latch** — `godot/src/game/SoundWaveProjectile.gd:L339-L341`, `godot/src/game/HornBoltProjectile.gd:L339-L341` `[IN-PROGRESS]` (`SHIPPED`)
  - **Root Cause Mechanism:** Carry-forward `evan [P3-1]`: emits both channels on the same impact frame.
  - **Surgical Fix Specification:** Unify onto `on_hit` or rename `hit` to `contact`.

- **[P3-12] `run_gates.sh` Double-Counts Builder Failures & Swallows `--import` Exit Code; Stale CI Label** — `godot/tools/run_gates.sh:L108,L115-L175` `[IN-PROGRESS]`, `.github/workflows/gates.yml:L30` (`SHIPPED`)
  - **Surgical Fix Specification:** Merge `rc != 0` and `! grep -q "saved"` checks per builder, remove `|| true` on `--import`, and update `gates.yml:L30` from `29` to `33`.

- **[P3-13] Build/Tooling Hygiene (`check_web_hygiene.py`, `deploy_web.sh`, Scene Builders, `verify_talo_backend.gd`)** — `godot/tools/check_web_hygiene.py:L141-L152` `[IN-PROGRESS]`, `godot/tools/deploy_web.sh:L120-L121`, `godot/tools/build_{testride,arena,deathrace}.gd`, `godot/tools/verify_talo_backend.gd:L296-L299` (`SHIPPED`)
  - **Surgical Fix Specification:** Add `Kiepie_Bike.glb`/`Pogo_Nardus.glb`/`Aston_Martin.glb`/`addons/talo/settings.cfg` to `REQUIRED_PCK_PATHS`, `fsync` temp files in `deploy_web.sh`, and call `root.free()` before `quit()` in the 3 scene builders.

### Lens 8: Type Systems, Schema & Contracts

- **[P2-3] `RocketProjectile.gd` and `MeteorStrike.gd` Lack `is_finite()` & `blast_radius` Clamping in `setup()`** — `godot/src/game/RocketProjectile.gd:L185-L199`, `godot/src/game/MeteorStrike.gd:L158-L167` (`SHIPPED`)
  - **Root Cause Mechanism:** Unlike `DevilHandStrike`, `HornBeam`, and `UnicornBoom`, `setup()` accepts non-finite `p_damage`/`p_blast_radius`/`p_target_pos` and unclamped `p_blast_radius`.
  - **Surgical Fix Specification:** Reject non-finite args with `queue_free(); return` and clamp `blast_radius <= BLAST_RADIUS`.

- **[P2-7] Older Blender Builders Omit `save_version = 0` Around `.blend` Saves** — `src/build_pogo_nardus.py:L854`, `src/build_aston_martin.py:L635`, `src/build_quad.py:L322`, `src/repair_and_verify.py:L66` (`SHIPPED`)
  - **Root Cause Mechanism:** Saving on Blender profiles with `save_version >= 1` writes undeclared `*.blend1` files in the repo root.
  - **Surgical Fix Specification:** Wrap `save_as_mainfile` in `save_version = 0` + `try...finally` restore (matching `build_evan_skeleton.py:L1159`).

### Lens 9: Platform, Viewport & Portability

- **[P3-11] Missing Wildcard `section == "*"` Settings Reset & Dead Branch in `Settings.gd`** — `godot/src/ui/MatchHud.gd:L604-L606`, `godot/src/TouchControls.gd:L127-L134`, `godot/src/core/Settings.gd:L86-L90` (`SHIPPED`)
  - **Root Cause Mechanism:** `Settings.reset_defaults()` emits `changed.emit("*", "*", null)`, ignored by `MatchHud` (`_show_fps`) and `TouchControls` (`_force`/layout); `Settings.effective_resolution_scale()` `L88-L89` makes `minf(scale, 0.72)` unreachable.
  - **Surgical Fix Specification:** Handle `section == "*"` in both listeners and simplify `effective_resolution_scale()`.

### Lens 10: Cognitive Load & AI Maintainability

- Covered by **[P2-8]** (God files) and **[P3-9]** (5-vehicle vocabularies).

### Lens 11: Engagement, Game Feel & Accessibility

- Verified cohesive across `FollowCam` shake/FOV, `VfxCore`/`VfxHeavy` hit numbers & explosions, `Sfx` pitch jitter, `Settings` Web `prefers-reduced-motion` auto-seed, and `UiTheme` contrast (`>= 8:1`). Two gameplay/feedback gaps are captured above: **[P1-1]** (`HornBeam` beam rendering backwards) and **[P2-1]** (`CombatAoe.apply_lethal_blast` suppressing `hit_confirmed`).

---

## 3. Existing Test Suite Comparison & Mutation Truth Table

- **Test-to-Code File Ratio:** `28 / 121` (`0.231`) — `27` `godot/tools/verify_*.gd` gates + `1` GdUnit4 suite (`godot/tests/test_kiepie_pad.gd`), plus `scene_sync` and `web_hygiene` (`test_patch_web_sw.py`).
- **Shipped Coverage:** `UNSHIPPED_IN_PCK=0` — `100%` of `godot/src/**/*.gd` modules tested by gates ship in `index.pck`.
- **Estimated Mutation Kill Score ($M_{\text{kill}}$):** **`71.88%`** (`23 / 32` mutants killed; `888` assert tokens, `1455` negative/boundary signals, `13` mock-using gate files, `0` unshipped tested modules).

| Implementation Module | Critical Functions / Branches | Paired Gate / Test | Pathologies Detected | Mutants Killed (`M1–M4`) | High-Priority Missing Assertions |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `TaloBackend.gd`, `LobbyService.gd` | `_join_auto`, `join_lobby_channel`, `_enter_if_current`, `_handoff_host` | `verify_talo_backend.gd`, `verify_audit_regressions.gd` | `Mock-Mirror` (Talo v1 HTTP mocked) | `4 / 5` (`80%`) | `_handoff_host` concurrent `_apply_inflight` drain |
| `ArenaNet.gd`, `NetworkedBike.gd` | `_spawn_remote_shot`, `apply_state` | `verify_multiplayer.gd`, `verify_audit_regressions.gd` | None significant | `2 / 2` (`100%`) | None critical |
| `CombatAoe.gd` | `apply_lethal_blast`, `apply_blast` | `verify_evan_weapons.gd`, `verify_combat.gd` | `Happy-Path` (`hit_confirmed` unasserted) | `0 / 1` (`0%`) | Assert `hit_confirmed` emitted on owner lethal AOE kill |
| `HornBeam.gd` | `_start_beam`, `_physics_process` | `verify_lea_unicorn_weapons.gd` | `Existence-Only` (`PlasmaBeam` child present, sign unchecked) | `1 / 2` (`50%`) | Assert `PlasmaBeam.position.dot(_direction) > 0` |
| `SideCannons.gd` | `fire()`, `_acquire_pooled_proj()` | `verify_cannons.gd`, `verify_evan_weapons.gd` | `Time-Window` (no mid-`await` respawn) | `1 / 2` (`50%`) | Respawn during `await Match.issue_shot()` cancels shot |
| `DevilHandStrike`, `RocketProjectile`, `MeteorStrike` | `setup()` validation & clamping | `verify_evan_weapons.gd`, `verify_combat.gd` | `Happy-Path` on `Rocket`/`Meteor` | `1 / 2` (`50%`) | Reject `NaN`/`<=0` & clamp `blast_radius` on `Rocket`/`Meteor` |
| `BoomerangGuitar.gd`, `Evan/Lea/PogoVisual.gd` | `_on_contact`, `_damage_bike`, remote `disp/dt` | `verify_evan.gd`, `verify_evan_weapons.gd`, `verify_pogo.gd` | `PogoVisual` remote speed gap | `3 / 4` (`75%`) | `PogoVisual` `dt = 0.0001` speed clamp |
| `TouchControls.gd`, `MatchHud.gd`, `Settings.gd` | `_sync_analog`, `_on_settings_changed`, `_load` | `verify_touch_multitouch.gd`, `verify_settings.gd` | None in touch; `section == "*"` gap | `4 / 5` (`80%`) | `Settings.reset_defaults()` updates `MatchHud`/`TouchControls` |
| `RaceTracker.gd`, `VfxSprites.gd`, `VfxHeavy.gd` | `_on_finish_line_entered`, `_cap_group`, lights | `verify_deathrace.gd`, `verify_vfx.gd` | Low-quality `OmniLight3D` gap | `2 / 3` (`67%`) | `VfxHeavy` low-quality light count `== 0` |
| `patch_web_sw.py`, `check_scene_sync.py`, `run_gates.sh`, `deploy_web.sh` | SW patches, SubResource digest, `verdict()`, atomic sync | `test_patch_web_sw.py`, `scene_sync`, `web_hygiene` | None significant | `5 / 6` (`83%`) | `deploy_web.sh` temp-file `fsync` |

### Why Existing Tests Missed Discovered P1/P2 Defects

- **`[P1-1]` (`HornBeam.gd`):** `verify_lea_unicorn_weapons.gd` checks that `PlasmaBeam` spawns and is visible, without asserting `beam.position.dot(aim_dir) > 0.0`.
- **`[P2-1]` (`CombatAoe.gd`):** `verify_evan_weapons.gd` verifies `take_lethal_hit` is skipped on remote proxies, but never listens for `local_combat.hit_confirmed` when an enemy proxy is inside an owner's lethal blast.
- **`[P2-3]` / `[P2-4]` (`RocketProjectile`/`MeteorStrike`/`SideCannons`):** No gate feeds `NaN`/`INF` into `RocketProjectile.setup()`/`MeteorStrike.setup()` or calls `reset_cooldowns()` while `fire()` is suspended on `Match.issue_shot()`.

### Minimal Viable Test Harness (MVTH) Specifications

1. **`verify_lea_unicorn_weapons.gd` (Tier 0 Spatial):** Assert `beam.position.dot(dir) > 0.0` and `charge_ring.position.z < 0.0` in `_charge`'s local space.
2. **`verify_evan_weapons.gd` / `verify_combat.gd` (Tier 1/2):** Assert `hit_confirmed` fires when `apply_lethal_blast` catches an enemy proxy owned by `local_uid`; test `RocketProjectile`/`MeteorStrike`/`DevilHandStrike` `setup()` with `NAN` `target_pos` -> freed & ignored; test `SideCannons.fire()` + `reset_cooldowns()` during `await` aborts shot.

---

## 4. Surgical Refactoring Blueprints (Zero-Mutation Drafts)

### Refactor [R1]: Fix `HornBeam` Forward Beam & Charge Ring Local Offset (`[P1-1]`)

- **Target Scope:** `godot/src/game/HornBeam.gd:L178,L256`
- **Engineering ROI:** Fixes backwards visual plasma beam on 100% of Lea Unicorn `rocket`-slot shots in 2 lines.

```gdscript
# Before:
_charge.position.z = -0.55
...
_beam.position = -_direction * (span * 0.5)

# After:
_charge_ring.position.z = -0.55
...
_beam.position = _direction * (span * 0.5)
```

### Refactor [R2]: Restore `hit_confirmed` Before Fail-Closed Guard in `CombatAoe.apply_lethal_blast()` (`[P2-1]`)

- **Target Scope:** `godot/src/game/CombatAoe.gd:L128-L147`
- **Engineering ROI:** Restores hit-marker/audio feedback on Devil Hand & Unicorn Boom kills without relaxing fail-closed victim authority.

```gdscript
var target_id := str(bike_node.get("player_id")) if "player_id" in bike_node else ""
if owner_id != "" and owner_id == local_uid and target_id != local_uid:
	hit_any_enemy = true
if local_uid == "" or target_id == "" or target_id != local_uid:
	continue
```

---

## 5. Phased Execution Roadmap & Scoped Agent Prompts

1. **Phase 1 — P1 Visual/Gameplay Fix (`HornBeam.gd`):** Fix `[P1-1]` (`L178, L256`) and `[P3-6]` (`L262, L336-L344`), plus spatial assertion in `verify_lea_unicorn_weapons.gd`.
2. **Phase 2 — Combat & Contract Hardening (`P2-1..P2-7`):** Fix `CombatAoe` (`[P2-1]`, `[P3-1]`), `DevilHandStrike`/`RocketProjectile`/`MeteorStrike` `setup()` (`[P2-2]`, `[P2-3]`), `SideCannons` `_fire_gen` (`[P2-4]`), `gates.yml` `permissions: contents: read` (`[P2-5]`), `index.pck` budget (`[P2-6]`), and older Blender `save_version = 0` (`[P2-7]`).
3. **Phase 3 — Modular De-Vibing (`P2-8`, `P3-*`):** Split `TaloBackend`, `MatchHud`, `SideCannons`, `KiepieBike`, and `VehicleRegistry` `SPECS`; wire `section == "*"` resets and `VfxHeavy` light guard.

### Copy-Paste Surgical Prompts for Coding Agents

> **Prompt [P1-1] (`godot/src/game/HornBeam.gd`):**
> "Strictly scope edits to `godot/src/game/HornBeam.gd` (`L178, L256, L262, L336-L344`) and `godot/tools/verify_lea_unicorn_weapons.gd`. Move `_charge.position.z = -0.55` to `_charge_ring.position.z = -0.55`, change `_beam.position` from `-_direction * (span * 0.5)` to `+_direction * (span * 0.5)`, move `_finish()` outside `if _beam != null:`, and add a gate check asserting `PlasmaBeam.position.dot(aim_dir) > 0.0`. Run `bash godot/tools/run_gates.sh --no-build`."

> **Prompt [P2-1] (`godot/src/game/CombatAoe.gd`):**
> "Strictly scope edits to `godot/src/game/CombatAoe.gd` (`L125-L147`) and `godot/tools/verify_evan_weapons.gd`. Compute `if owner_id != "" and owner_id == local_uid and target_id != local_uid: hit_any_enemy = true` before the `target_id != local_uid` `continue` in `apply_lethal_blast()`, remove unused `sqrt(dist_sq)`, and add a regression check verifying `local_combat.hit_confirmed` fires when an enemy proxy is inside an owner's lethal blast. Run `bash godot/tools/run_gates.sh --no-build`."
