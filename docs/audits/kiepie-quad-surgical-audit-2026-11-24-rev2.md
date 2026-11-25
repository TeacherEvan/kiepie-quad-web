# Surgical Audit Report: Kiepie Quad Web (Rev 2 — Post-Remediation Re-Audit)

| Audit Metadata | Specification |
| :--- | :--- |
| **Audit Date** | 2026-11-24 (target `HEAD`: `2bf35700a1c8f637a9fa9cad134272cd78c26873`, 8 commits after prior `2026-11-24` audit at `f46881e`) |
| **Audited Scope** | First-party repo (`src/`, `godot/src/`, `godot/tools/`, `godot/tests/`, `index.html`, `index.service.worker.js`, `vercel.json`, `.github/workflows/gates.yml`; excluding vendored `godot/addons/`, `docs/`, `web/`, and generated `index.js`) — `109` first-party files (`82` impl/build/tool files, `27` test/gate scripts), `26,045` effective code LOC, `199` inline HTML lines (`26,244` scored effective LOC; `360` total workspace files scanned by telemetry) |
| **Tech Stack & Runtime** | `GDScript (Godot 4.3 Web/GLES3), Python 3 (Blender 5.3 bpy + build/export/SFX tooling), Vanilla HTML/CSS/JS (WebAssembly shell + Service Worker), Vercel Static Edge + GitHub Actions` |
| **Pre/Post Audit SHA-256** | `845292d2e43f2581 / 845292d2e43f2581 (VERIFIED ZERO MUTATION — full: 845292d2e43f2581982d23db0251b70367d1bc8d7bfb9eaa69c79daaa83481ca; pre-existing 7 .tscn resource-ID churn files untouched)` |
| **Deterministic Health Score** | **`81 / 100`** (`D_raw = 68`, `scale_factor = 0.195202`, `P_test = 5.3571`, `M_kill = 64.29%` [`18/28`]) |
| **Vibe-Debt Risk Level** | **`MODERATE`** |
| **Companion SARIF** | `docs/audits/kiepie-quad-surgical-audit-2026-11-24-rev2.sarif` |

## 1. Executive Architecture & Vibe-Debt Triage

Phases 1–4 following `f46881e` closed all prior P0 defects (Talo auth late-promotion, `VfxFactory` 4-module split, `CombatAoe` extraction, `VehicleHandling` extraction, `patch_web_sw.py` strict fetch guard, WCAG 2.1.1 victory overlay keyboard access, and atomic `inject_talo_key.py`), raising deterministic health to **81 / 100 (`MODERATE`)** with **0 P0** defects. However, this re-audit uncovered **5 P1** defects: 3 async lobby/join-generation race regressions centered on `TaloBackend.gd` (979 effective LOC) and `LobbyService.gd` (where the new `_join_gen` guard from `aa14285` self-invalidates `_join_auto`/`_join_by_code` on zombie-room eviction, `join_lobby_channel()` still lacks `_join_gen`, and stale cleanup in `LobbyService._enter_if_current()` cancels newer joins), 1 build-pipeline drift hazard in `patch_web_sw.py` (5/6 patches still silent-skip), and 1 **empirically reproduced CI / fresh-checkout gate failure (`talo_backend` 1/29 failing on pristine `git archive HEAD`)** because `godot/addons/talo/settings.cfg` is gitignored (`godot/.gitignore:L6`) yet asserted by `verify_talo_backend.gd:L295-L298`. Pass 2.5 live headless Chromium geometry & WCAG 2.2 checks (`1280×720`, `390×844`, `844×390`, `forced-colors: active`, `prefers-contrast: more`, `prefers-reduced-motion: reduce`) all **PASS** (`crossOriginIsolated=true`, `SharedArrayBuffer=true`, `0` console errors, `0` overflow, `44px+` skip targets, keyboard `Enter` + click dismissal verified). Two measurement caveats apply: (a) host contention was elevated (`load average > 4.2` on `4` cores from concurrent `python3`/`ffmpeg` host processes), so wall-clock FPS/latency claims are deliberately omitted; (b) outbound `curl` to `https://kiepie-quad-web.vercel.app/` returned empty in this offline/sandboxed environment, so live production parity was not asserted.

| Severity Tier | Count | Deduction Weight | Primary Failure Domains |
| :--- | :--- | :--- | :--- |
| **P0 — Critical (Crash / Data Loss / Security / Leak)** | `0` | `-18 pts ea` | `None` |
| **P1 — High (Frame-Budget / Race / Logic Bug)** | `5` | `-8 pts ea` | `TaloBackend.gd` (`_join_gen` self-invalidation & unprotected `join_lobby_channel`), `LobbyService.gd` (stale cleanup cancels newer join), `patch_web_sw.py` (silent-skip SW patches), `godot/.gitignore` + `verify_talo_backend.gd` (fresh-checkout/CI `talo_backend` failure) |
| **P2 — Medium (God File / Split-Brain State / Debt)** | `7` | `-3 pts ea` | `SideCannons.gd` (pool eviction), `NetworkedBike.gd` (invalid first pos init), `TaloBackend.gd` (hardcoded 8-player cap), `_gate_settings_guard.gd` (missing `load_from_disk`), `verify_audit_regressions.gd` (3 weak assertions), `check_scene_sync.py` (type-only SubResource), 18 god files >400 eff LOC |
| **P3 — Low (Magic Constants / DX / Portability)** | `7` | `-1 pt ea` | `TaloBackend.gd` (`JSON.new()` + `_kill_last_base` leak), `LoopZone.gd` (unused `loop_half_width`), `CombatController.gd` (cold-boot `TestRide` attribution), `TouchControls.gd` (one-way resize), `VfxCore.gd`/`VfxHeavy.gd` (quality/reduced-motion gaps), `build_testride.gd` + `run_gates.sh` (group flag + dirty `.tscn`), `index.pck` headroom & unbounded timers |

### High-Risk File Telemetry Hotspots

| File Path | Effective LOC | Est. Cyclomatic Complexity / Branch Density | Silent Catches | Primary Vibe-Debt Signature |
| :--- | :--- | :--- | :--- | :--- |
| `godot/src/net/TaloBackend.gd` | `979` | High (6 interleaved async state flags) | `0` | God networking module + `_join_gen` race regressions (`[P1-1]`, `[P1-2]`, `[P2-3]`, `[P2-7]`, `[P3-1]`) |
| `godot/tools/build_deathrace.gd` | `949` | Moderate (procedural scene builder) | `0` | Large monolithic scene builder |
| `src/build_intro_splash.py` | `844` | Moderate (Blender/FFmpeg pipeline) | `0` | Large monolithic media builder |
| `godot/src/ui/MatchHud.gd` | `756` | High (HUD + scoreboard + killfeed) | `0` | God HUD controller (`[P2-7]`) |
| `godot/tools/build_arena.gd` | `716` | Moderate (procedural scene builder) | `0` | Large monolithic scene builder |
| `godot/src/game/SideCannons.gd` | `603` | High (weapon profiles + pooling + aim) | `0` | God weapon controller + round-robin pool eviction (`[P2-1]`, `[P2-7]`) |
| `godot/src/KiepieBike.gd` | `570` | High (physics + visuals + net sync) | `0` | God vehicle controller (`[P2-7]`, `[P3-7]`) |
| `godot/src/game/VfxHeavy.gd` | `546` | Moderate (heavy explosions/strikes) | `0` | Minor `reduced_motion` light tween gap (`[P3-5]`) |
| `godot/src/TouchControls.gd` | `501` | High (multitouch + layout) | `0` | One-way viewport resize (`[P3-4]`) |
| `godot/tools/patch_web_sw.py` | `~220` | Moderate (6 regex/string SW patches) | `1` | Silent-skip template drift + non-idempotent hash append (`[P1-4]`) |

### Pass 2.5 Live Browser & Baseline Gate Evidence

| Verification Target | Outcome | Key Observed Metrics |
| :--- | :--- | :--- |
| **Desktop `1280×720`** (headless Chromium, local COOP/COEP/CORP) | **PASS** | `crossOriginIsolated=true`, `SharedArrayBuffer=true`, `overflow={x:0,y:0}`, `#canvas=1280×720`, `0` console errors, `#victory-skip=124.7×44px`, `vOverlap=false`, `vOutline="rgb(255, 122, 26) solid 2px"`, `victoryClickDismissed=true`, `victoryEnterDismissed=true` |
| **Mobile Portrait `390×844`** (`dpr=2, touch` + `forced-colors: active` + `prefers-contrast: more`) | **PASS** | `overflow={x:0,y:0}`, `#victory-skip=126.7×46px`, `titleOverlapsSkip=false`, `hitCenter=BUTTON#victory-skip`, high-contrast border `2px solid rgb(0, 0, 0)` |
| **Mobile Landscape `844×390`** (`dpr=2, touch, landscape`) | **PASS** | `overflow={x:0,y:0}`, `#victory-skip=124.7×44px`, `hit5=5/5`, `titleOverlapsSkip=false` |
| **Reduced Motion** (`prefers-reduced-motion: reduce`) | **PASS** | `victoryCreatedUnderReducedMotion=false` (clean suppression) |
| **Pristine `git archive HEAD` Gate Suite** (`run_gates.sh --no-build`) | **28/29 PASS, 1 FAIL** | `gdunit` `6/6` PASS, `touch_multitouch` xvfb `0` failures, `check_scene_sync.py` PASS, `check_web_hygiene.py` PASS; **`talo_backend` FAILED (`rc=1`)** on `P1-8: addons/talo/settings.cfg ships auto_connect_socket=false` |

## 2. The 10-Principal-Engineer Deep Audit

### Lens 1: Architectural Integrity & Cognitive Load

- **[P2-7] God-File & Async Flag Concentration** — `godot/src/net/TaloBackend.gd:L1-L1169`, `godot/src/ui/MatchHud.gd`, `godot/src/game/SideCannons.gd`, `godot/src/KiepieBike.gd`
  - **Root Cause Mechanism:** `18` first-party files exceed `400` effective LOC. `TaloBackend.gd` (`979` effective LOC) interleaves `6` async coordination flags (`_join_gen`, `_prop_gen`, `_handing_off`, `_apply_inflight`, `_reconnecting`, `_host_ack`) across socket lifecycle, lobby discovery, prop persistence, and roster/kill rate-limiting.
  - **Deterministic Trigger & Failure Mode:** Adding `_join_gen` in `aa14285` without isolating the join state machine from channel-eviction helpers directly produced `[P1-1]` and `[P1-2]`.
  - **Surgical Fix Specification:** Split `TaloBackend.gd` into `TaloSessionTransport.gd` (socket/auth/join FSM) and `TaloLobbyStore.gd` (channel props, roster state, kill rate-limiting); extract scoreboard/killfeed from `MatchHud.gd` and weapon profiles from `SideCannons.gd`.

### Lens 2: Performance, Compute & Frame Budget

- **[P2-1] Pooled Projectile Mid-Air Eviction Under Rapid Fire** — `godot/src/game/SideCannons.gd:L79-L81, L682-L705`
  - **Root Cause Mechanism:** `_acquire_pooled_proj()` advances `_proj_pool_idx = (idx + 1) % PROJ_POOL_SIZE` (`PROJ_POOL_SIZE = 24`) without checking `not cand.is_physics_processing()`.
  - **Deterministic Trigger & Failure Mode:** Under rapid fire (`~22.2 shots/s`, `2.2 s` projectile lifetime = up to `48` concurrent bolts), `_acquire_pooled_proj()` evicts and recycles still-flying bolts mid-air after `1.08 s`.
  - **Surgical Fix Specification:** Raise `PROJ_POOL_SIZE` to `48` and scan `_proj_pool` for an inactive slot (`not cand.is_physics_processing()`) before falling back to round-robin eviction, matching `ArenaNet._acquire_remote_proj()`.

- **[P3-1] Per-Message `JSON.new()` Allocation & Stale `_kill_last_base` Entries** — `godot/src/net/TaloBackend.gd:L967-L970, L1021-L1025`
  - **Root Cause Mechanism:** `_on_socket_message()` allocates a fresh `JSON.new()` per incoming message, and the `"leave"` handler never erases the departing peer from `_kill_last_base`.
  - **Deterministic Trigger & Failure Mode:** Sustained multiplayer traffic creates avoidable per-packet GC churn and retains stale entries in `_kill_last_base` for departed players.
  - **Surgical Fix Specification:** Replace `JSON.new()` with `JSON.parse_string(raw)` and call `_kill_last_base.erase(uid)` inside the `"leave"` handler.

### Lens 3: Memory Management, Leaks & Resource Lifecycles

- **[P3-7] Web PCK Headroom, Missing Wildcard Settings Reset & Unbounded Float Timers** — `index.pck`, `godot/src/game/AmbientVfx.gd:L23`, `godot/src/FollowCam.gd:L64`, `godot/src/KiepieBike.gd:L624`
  - **Root Cause Mechanism:** `index.pck` is `3,706,144 B` (`3.53 MiB`), `88.4%` of the `4 MiB` deploy cap (`488 KiB` headroom). Three `Settings.changed` listeners (`AmbientVfx.gd`, `FollowCam.gd`, `KiepieBike.gd`) omit `section == "*"` reset wildcard handling, and `_jet_t` / `_breathe_t` accumulate unboundedly. (`0 / 47` dead runtime scripts in `godot/src/**/*.gd`; `VfxFactory` scorch/scar group cleanup is clean.)
  - **Deterministic Trigger & Failure Mode:** Resetting settings to defaults fails to refresh those 3 listeners, and multi-hour sessions lose float precision on periodic trig inputs.
  - **Surgical Fix Specification:** Add `section == "*"` handling to all 3 `Settings.changed` callbacks, wrap `_jet_t` / `_breathe_t` with `fmod(..., TAU)`, and monitor `index.pck` growth before adding assets.

### Lens 4: Concurrency, Async & State Synchronization

- **[P1-1] `_join_gen` Self-Invalidation Breaks Auto-Join & Code-Join on Zombie Room Eviction** — `godot/src/net/TaloBackend.gd:L295-L299, L423-L478, L481-L523, L536-L540`
  - **Root Cause Mechanism:** Regression from commit `aa14285`: `leave_lobby_channel()` (`L299`) increments `_join_gen += 1`, but `_join_auto()` (`L462`) and `_join_by_code()` (`L517`) call `leave_lobby_channel()` internally to evict a timed-out zombie room.
  - **Deterministic Trigger & Failure Mode:** Whenever any zombie room (host vanished before 90 s heartbeat expiry) is encountered, `leave_lobby_channel()` bumps `_join_gen` past the caller's `gen`, causing subsequent candidates in `_try_join()` (`L537`) AND the fallback guard at `L463` (`if gen != _join_gen: return {}`) to abort before `_create_lobby()` (`L478`). Auto-join is completely blocked until the zombie room expires.
  - **Surgical Fix Specification:** Add `bump_join_gen: bool = true` to `leave_lobby_channel()` and pass `false` on internal zombie-eviction calls at `L462` and `L517`.

- **[P1-2] Unprotected `join_lobby_channel()` Async Race & Stale Sequence State** — `godot/src/net/TaloBackend.gd:L279-L293`
  - **Root Cause Mechanism:** `join_lobby_channel()` awaits `Talo.channels.join(id)` (`L283`) and `Talo.channels.find(id)` (`L284`) with no `_join_gen` guard and never resets `_state_seq`, `_last_state_seq`, or `_last_state_host`.
  - **Deterministic Trigger & Failure Mode:** A concurrent `leave_lobby_channel()` or lobby switch while `join_lobby_channel()` is suspended on `await` is overwritten when the stale coroutine resumes, resurrecting a left room or clobbering the new one.
  - **Surgical Fix Specification:** Capture `var gen := _join_gen` at entry, abort and call `Talo.channels.leave(id)` if `gen != _join_gen` after both `await`s, and reset `_state_seq = 0`, `_last_state_seq = -1`, `_last_state_host = ""`.

- **[P1-3] Stale `LobbyService` Cleanup Cancels Newer In-Flight `create_lobby`/`join_*`** — `godot/src/net/LobbyService.gd:L37-L45`
  - **Root Cause Mechanism:** In `_enter_if_current()`, after `await Supabase.call_rpc("leave_lobby", {"p_expected_lobby_id": stale_id})`, `L42-L43` runs `if current_lobby_id == "" or current_lobby_id == stale_id: Supabase.leave_lobby_channel()`.
  - **Deterministic Trigger & Failure Mode:** If the user cancels a join and immediately invokes `create_lobby()` (`current_lobby_id` is still `""` while awaiting Talo), `L43` executes `leave_lobby_channel()`, bumping `TaloBackend._join_gen` and silently aborting the user's new `create_lobby()`.
  - **Surgical Fix Specification:** Bump a `_session_gen` counter on every `join_auto`/`join_by_code`/`create_lobby` entry, capture `var cleanup_gen := _session_gen` before the stale cleanup `await`, and only call `leave_lobby_channel()` when `current_lobby_id == stale_id` or (`cleanup_gen == _session_gen and current_lobby_id == ""`).

### Lens 5: Numerical Precision, Simulation & Physics Fidelity

- **[P3-2] Ignored `@export var loop_half_width` in `LoopZone`** — `godot/src/game/LoopZone.gd:L8, L72`
  - **Root Cause Mechanism:** `LoopZone.gd` exports `loop_half_width := 5.5` at `L8`, but `L72` hardcodes `6.0` in the lateral containment check.
  - **Deterministic Trigger & Failure Mode:** Tuning `loop_half_width` in the inspector or scene builder has no effect on loop adhesion bounds.
  - **Surgical Fix Specification:** Replace `6.0` at `L72` with `loop_half_width`.

- **[P3-3] Cold-Boot `TestRide` Practice Attribution Drift** — `godot/src/game/CombatController.gd:L49, L55, L456`
  - **Root Cause Mechanism:** Cold-boot `TestRide` caches an empty `Supabase.user_id` before async Talo auth finishes; once Talo sets `Supabase.user_id`, `owner_id == Supabase.user_id` at `L456` evaluates false for shots fired with `owner_id == ""`.
  - **Deterministic Trigger & Failure Mode:** Fuel drum explosions triggered by the player in `TestRide` stop emitting `hit_confirmed` after background auth completes.
  - **Surgical Fix Specification:** Match local ownership against `player_id` or allow `owner_id == ""` in practice mode.

### Lens 6: Security, Trust Boundaries & Data Integrity

- **[P2-3] Hardcoded `8`-Player Roster Cap Ignores Lobby `max_players`** — `godot/src/net/TaloBackend.gd:L1014-L1015`
  - **Root Cause Mechanism:** The `"join"` socket message handler checks `_roster.size() >= 8` instead of reading `settings.max_players` from `_lobby`.
  - **Deterministic Trigger & Failure Mode:** Concurrent joiners to a 2–4 player lobby bypass the host's configured `max_players` cap.
  - **Surgical Fix Specification:** Read `clampi(int((_lobby.get("settings", {}) as Dictionary).get("max_players", 8)), 2, 8)` and enforce it in the `"join"` handler.

### Lens 7: Infrastructure, CI/CD & Dependency Hygiene

- **[P1-5] Fresh-Checkout / GitHub Actions CI `talo_backend` Gate Failure (`settings.cfg` Gitignore Contradiction)** — `godot/.gitignore:L6`, `godot/tools/verify_talo_backend.gd:L294-L298`, `.github/workflows/gates.yml:L18-L33`
  - **Root Cause Mechanism:** `godot/.gitignore:L6` ignores `addons/talo/settings.cfg`, so fresh clones and GitHub Actions runners lack the file. On boot, the vendored Talo 0.20.0 autoload auto-creates `settings.cfg` with `auto_connect_socket=true` and `handle_tree_quit=true`, attempts an unauthenticated socket ticket (`401 Bad Authorization header format`), and trips `verify_talo_backend.gd:L297` (`FAIL: P1-8: addons/talo/settings.cfg ships auto_connect_socket=false`).
  - **Deterministic Trigger & Failure Mode:** Empirically reproduced by running `run_gates.sh --no-build` on pristine `git archive HEAD`: `talo_backend` fails (`28/29 PASS, 1 FAIL`), meaning CI is broken on every clean checkout.
  - **Surgical Fix Specification:** Either (a) check in a key-less default `godot/addons/talo/settings.cfg` (`access_key=""`, `auto_connect_socket=false`, `handle_tree_quit=false`) and keep live key injection out of git (e.g. `deploy_web.sh` staging), OR (b) have `run_gates.sh` / CI write a mock-safe `settings.cfg` when absent and validate `inject_talo_key.py`'s template instead of an ignored working-tree file.

- **[P1-4] Silent-Skip SW Patching & Non-Idempotent Cache Hash Append** — `godot/tools/patch_web_sw.py:L38-L43, L67-L68, L75-L76, L92-L93, L107-L108, L122-L123`
  - **Root Cause Mechanism:** Only `old_fetch_block` (`L233-L234`) raises `RuntimeError` on mismatch; 5 other critical Service Worker patches (`old_install`, `old_clean`, `old_activate`, `old_coep_fn`, `old_fetch_fn`) silently no-op via `if old_* in out:`, and `L38-L43` blindly appends `|{pck_hash}` if run twice.
  - **Deterministic Trigger & Failure Mode:** Any Godot export template drift silently drops `ENGINE_CACHE` pre-caching, `clients.claim()`, or `cache.put` quota guards without failing the build.
  - **Surgical Fix Specification:** Assert every patch marker matches (raising `RuntimeError` with the marker name on miss) and reject already-patched input (`"const ENGINE_CACHE =" in out`).

- **[P2-4] Broken `Settings.load_from_disk()` Call in Gate Settings Guard** — `godot/tools/_gate_settings_guard.gd:L38-L40`
  - **Root Cause Mechanism:** `restore()` checks `has_method("load_from_disk")` and calls `Settings.load_from_disk()`, which does not exist (`Settings.gd` defines `_load()`).
  - **Deterministic Trigger & Failure Mode:** After a gate restores `user://settings.cfg` on disk, in-memory `Settings.data` remains unsynced.
  - **Surgical Fix Specification:** Expose `reload()` on `Settings.gd` (calling `_load()` + `_apply_all()`) and invoke it from `_gate_settings_guard.gd`.

- **[P3-6] Missing Persistent Group Flag in `build_testride.gd` & Dirty `.tscn` Side-Effect of `run_gates.sh`** — `godot/tools/build_testride.gd:L111`, `godot/tools/run_gates.sh:L80-L146`
  - **Root Cause Mechanism:** `bike.add_to_group("bike")` omits `, true` (persistent flag), and `run_gates.sh` rebuilds scenes by default, overwriting tracked `.tscn` resource IDs.
  - **Deterministic Trigger & Failure Mode:** Running `run_gates.sh` without `--no-build` leaves 7 `.tscn` files dirty in `git status`.
  - **Surgical Fix Specification:** Pass `, true` to `add_to_group("bike", true)` and default `run_gates.sh` to `--no-build` or restore/check via `check_scene_sync.py`.

### Lens 8: Error Handling, Observability & Edge Cases

- **[P2-2] Remote Proxy Initialized Visible & Collidable on Invalid First Position Packet** — `godot/src/game/NetworkedBike.gd:L133-L151`
  - **Root Cause Mechanism:** A first `apply_state()` packet with missing or out-of-bounds `"p"` (e.g., `[1e30, 0, 0]`) skips `_target_pos` assignment yet still sets `_initialised = true`, `visible = true`, and `collision_layer = 1`.
  - **Deterministic Trigger & Failure Mode:** A malformed initial state packet spawns a phantom solid bike at `Vector3.ZERO`.
  - **Surgical Fix Specification:** Require a validated finite, in-bounds `"p"` before setting `_initialised = true` and enabling visibility/collision.

- **[P2-6] `check_scene_sync.py` SubResource Normalization Reverted to Type-Only** — `godot/tools/check_scene_sync.py:L25, L60-L63`
  - **Root Cause Mechanism:** Commit `233cd74` reverted `sub_map` to `attrs.get("type", "SubResource")` (leaving dead `import hashlib` at `L25`).
  - **Deterministic Trigger & Failure Mode:** Swapping two same-type `SubResource` references (e.g., two `StandardMaterial3D` or `BoxShape3D` nodes) between scene nodes passes `check_scene_sync.py` undetected.
  - **Surgical Fix Specification:** Hash normalized sub-resource body properties (excluding volatile IDs) so same-type swaps are caught.

### Lens 9: UI, UX, Accessibility & Responsive Layout

Pass 2.5 live Chromium verification **PASSED** across desktop `1280×720`, mobile portrait `390×844`, mobile landscape `844×390`, `forced-colors: active`, `prefers-contrast: more`, and `prefers-reduced-motion: reduce`.

- **[P3-4] One-Way `BtnTouchToggle` Narrowing on Viewport Resize** — `godot/src/TouchControls.gd:L638-L640`
  - **Root Cause Mechanism:** `TestRide` `_relayout()` sets `offset_left = -132.0` when `vp.x < 700` with no `else` branch to restore `-150.0` when widened.
  - **Deterministic Trigger & Failure Mode:** Shrinking and re-widening the browser window leaves `BtnTouchToggle` permanently narrowed.
  - **Surgical Fix Specification:** Add an `else` branch restoring `offset_left = -150.0` when `vp.x >= 700`.

- **[P3-5] Minor VFX Quality / Reduced-Motion Guard Gaps** — `godot/src/game/VfxCore.gd:L147`, `godot/src/game/VfxHeavy.gd:L508, L591`
  - **Root Cause Mechanism:** `VfxCore.impact()` spawns `OmniLight3D` even when `quality_multiplier() < 0.5`; `VfxHeavy.lightning_strike_explosion()` and `cash_explosion()` tween `light_energy` instead of a static `tween_interval` under `reduced_motion`.
  - **Deterministic Trigger & Failure Mode:** Low-quality or reduced-motion users still receive unguarded dynamic light spawns/tweens.
  - **Surgical Fix Specification:** Guard `OmniLight3D` on `quality_multiplier() >= 0.5` and use `tween_interval` under `reduced_motion`.

### Lens 10: Testability, Modularity & Anti-Pattern Hygiene

- **[P2-5] Three Weakened Regression Assertions Fail Mutation Acceptance** — `godot/tools/verify_audit_regressions.gd:L350-L376`
  - **Root Cause Mechanism:** (1) `L353-L355` only asserts `_join_gen == jg0 + 1` after `leave_lobby_channel()`, missing `[P1-1]` and `[P1-2]`; (2) `L362-L369` checks frame-0 `rings <= 3`, which passes even if `mushroom=true` is broken because the Wilson ring spawns at `t=0.10 s`; (3) `L370-L375` checks `QuadMesh.size.x < 10.0`, which only inspects initial `radius=1.0`, never the broken `grow=24` vs `5.0` scale tween.
  - **Deterministic Trigger & Failure Mode:** Regressions in join-generation handling, mushroom Wilson rings, or shockwave scale pass `verify_audit_regressions.gd` silently.
  - **Surgical Fix Specification:** Replace those 3 checks with end-to-end zombie-room `_join_auto` fallback, `t >= 0.15 s` Wilson ring count, and post-tween shockwave `scale.x` assertions.

## 3. Existing Test Suite Comparison & Mutation Truth Table

- **Test-to-Code File Ratio:** `27 / 82` (`0.33` — `27` test/gate scripts across `godot/tools/verify_*.gd`, `truth_test.gd`, `diag2.gd`, `godot/tests/test_kiepie_pad.gd`, `check_scene_sync.py`, `check_web_hygiene.py`, plus `82` first-party impl/tool files; `29` orchestrated gates in `run_gates.sh`)
- **Estimated Mutation Kill Score ($M_{\text{kill}}$):** **`64.29%`** (`663` assertions, `25` negative/boundary signals, `12` mocked files, `1` unpaired critical module [`patch_web_sw.py`])

| Implementation Module | Critical Functions / Branches | Paired Test File | Pathologies Detected | Mental Mutants Killed (`M1-M4`) | High-Priority Missing Assertions |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `TaloBackend.gd` | `_join_auto()`, `_join_by_code()`, `join_lobby_channel()`, `_on_socket_message()` | `verify_talo_backend.gd`, `verify_audit_regressions.gd` | Mock-bound; weak `_join_gen` check | `3/4 (75%)` | Zombie-room fallback after eviction (`[P1-1]`), `join_lobby_channel()` race (`[P1-2]`), `max_players` cap (`[P2-3]`) |
| `LobbyService.gd` + `MatchState.gd` | `_enter_if_current()`, `start_match()` | `verify_match_rules.gd` | Happy-path cancel/re-create gap | `3/4 (75%)` | Stale cleanup `await` vs immediate `create_lobby()` (`[P1-3]`) |
| `CombatController.gd` + `CombatAoe.gd` | `take_damage()`, `take_lethal_hit()`, `apply_aoe()` | `verify_combat.gd`, `verify_kill_flow.gd` | Cold-boot `TestRide` gap | `3/4 (75%)` | Cold-boot empty `user_id` drum hit (`[P3-3]`) |
| `ArenaNet.gd` + `NetworkedBike.gd` | `apply_state()`, `_acquire_remote_proj()` | `verify_multiplayer.gd` | Invalid first-packet blind spot | `2/4 (50%)` | Missing/out-of-bounds `"p"` on first `apply_state()` (`[P2-2]`) |
| `VfxFactory.gd` + `VfxCore.gd` + `VfxHeavy.gd` | `impact()`, `explosion()`, `lightning_strike_explosion()` | `verify_vfx.gd`, `verify_audit_regressions.gd` | Frame-0 timing blind spot | `3/4 (75%)` | `t >= 0.15 s` Wilson ring & post-tween shockwave scale (`[P2-5]`) |
| `KiepieBike.gd` + `VehicleHandling.gd` + `TouchControls.gd` | `_integrate_forces()`, `_relayout()` | `verify_controls.gd`, `verify_dodge.gd`, `verify_rollover.gd`, `test_kiepie_pad.gd` | One-way resize blind spot | `3/4 (75%)` | Viewport widen restore on `BtnTouchToggle` (`[P3-4]`) |
| `patch_web_sw.py` + `check_scene_sync.py` | `patch_sw()`, `normalize_tscn()` | `NONE` (for `patch_web_sw.py`) / `check_scene_sync.py` | Unpaired build script; type-only SubResource | `1/4 (25%)` | Fail-fast on missing SW blocks (`[P1-4]`), same-type SubResource swap (`[P2-6]`) |

### Why Existing Tests Missed Discovered P0/P1 Defects

- **[P1-1] & [P1-2]:** `verify_audit_regressions.gd:L353-L355` only checked `_join_gen == jg0 + 1` after `leave_lobby_channel()` and never simulated `_join_auto()` encountering a zombie room followed by `_create_lobby()` fallback, nor a concurrent `leave_lobby_channel()` during `join_lobby_channel()`.
- **[P1-3]:** `verify_match_rules.gd` never tests cancelling a join and immediately calling `create_lobby()` while `_enter_if_current()` is suspended on `leave_lobby`.
- **[P1-4]:** `patch_web_sw.py` has no unit test; only `old_fetch_block` raised `RuntimeError`, so mutating any of the other 5 SW blocks passes silently.
- **[P1-5]:** Local developer workspaces already have `godot/addons/talo/settings.cfg` populated by `inject_talo_key.py`, masking the fact that `godot/.gitignore:L6` excludes it from clean checkouts and GitHub Actions CI.

### Minimal Viable Test Harness (MVTH) Specifications

1. **Zombie-Room Auto-Join & Concurrent `join_lobby_channel` (`verify_talo_backend.gd`):** Seed a mock channel with no host ack, call `_join_auto()`, assert `_create_lobby()` succeeds; await `join_lobby_channel()` and call `leave_lobby_channel()` mid-await, asserting `_channel == null`.
2. **Cancel-Then-Create Race (`verify_match_rules.gd`):** Trigger `join_auto()`, cancel, immediately call `create_lobby()`, flush stale `leave_lobby` await, and assert the new lobby remains active.
3. **SW Patcher Drift & Idempotency (`tests/test_patch_web_sw.py`):** Feed a Godot 4.3 SW fixture with each of the 6 blocks mutated one at a time, asserting `RuntimeError` on every miss and on double-patching.
4. **Fresh-Checkout `talo_backend` Gate:** Run `run_gates.sh --no-build` in a clean `git archive HEAD` directory in CI and assert `29/29 PASS`.
5. **Projectile Pool & Invalid First Packet (`verify_combat.gd`, `verify_multiplayer.gd`):** Fire `30` rapid shots and assert the first bolt remains `is_physics_processing()`; feed `{"p": [1e30, 0, 0]}` to `NetworkedBike.apply_state()` and assert `_initialised == false` and `visible == false`.

## 4. Surgical Refactoring Blueprints (Zero-Mutation Drafts)

### Refactor R1: Scoped Join Generation & Explicit Channel Eviction Flag

- **Target Scope:** `godot/src/net/TaloBackend.gd:L279-L302, L455-L478, L510-L545`
- **Engineering ROI:** Eliminates `[P1-1]` zombie-room auto-join deadlock and `[P1-2]` `join_lobby_channel()` stale-coroutine resurrection without altering public API signatures.

**Current Pattern (Audited Code):**

```gdscript
func join_lobby_channel(lobby_id: String) -> void:
	var id := int(lobby_id)
	if _channel_id == id or id <= 0:
		return
	var joined = await Talo.channels.join(id)
	_channel = joined if joined != null else await Talo.channels.find(id)
	if _channel != null:
		_channel_id = id
...
func leave_lobby_channel() -> void:
	_prop_gen += 1
	_join_gen += 1
...
			# Host vanished before heartbeat expired — leave zombie room and try next.
			leave_lobby_channel()
```

**Target Pattern (Surgical Blueprint):**

```gdscript
func join_lobby_channel(lobby_id: String) -> void:
	var id := int(lobby_id)
	if _channel_id == id or id <= 0:
		return
	var gen := _join_gen
	var joined = await Talo.channels.join(id)
	if gen != _join_gen:
		if joined != null:
			Talo.channels.leave(id)
		return
	var found = joined if joined != null else await Talo.channels.find(id)
	if gen != _join_gen:
		if found != null:
			Talo.channels.leave(id)
		return
	_channel = found
	if _channel != null:
		_channel_id = id
		_state_seq = 0
		_last_state_seq = -1
		_last_state_host = ""
...
func leave_lobby_channel(bump_join_gen: bool = true) -> void:
	_prop_gen += 1
	if bump_join_gen:
		_join_gen += 1
...
			# Host vanished before heartbeat expired — leave zombie room without invalidating caller gen.
			leave_lobby_channel(false)
```

### Refactor R2: Fail-Fast Idempotent Service Worker Patcher

- **Target Scope:** `godot/tools/patch_web_sw.py:L38-L125, L225-L236`
- **Engineering ROI:** Prevents silent Service Worker regressions on Godot template updates and eliminates double-hash corruption on re-runs (`[P1-4]`).

**Current Pattern (Audited Code):**

```python
    out = re.sub(
        r"const CACHE_VERSION = '([^']+)';",
        f"const CACHE_VERSION = '\\1|{pck_hash}';",
        out,
        count=1,
    )
    ...
    if old_install in out:
        out = out.replace(old_install, new_install, 1)
    if old_clean in out:
        out = out.replace(old_clean, new_clean, 1)
```

**Target Pattern (Surgical Blueprint):**

```python
    if "const ENGINE_CACHE =" in out:
        raise RuntimeError("patch_web_sw: service worker is already patched")
    out, n = re.subn(
        r"const CACHE_VERSION = '([^']+)';",
        f"const CACHE_VERSION = '\\1|{pck_hash}';",
        out,
        count=1,
    )
    if n != 1:
        raise RuntimeError("patch_web_sw: CACHE_VERSION marker not found")
    for name, old, new in [
        ("old_install", old_install, new_install),
        ("old_clean", old_clean, new_clean),
        ("old_activate", old_activate, new_activate),
        ("old_coep_fn", old_coep_fn, new_coep_fn),
        ("old_fetch_fn", old_fetch_fn, new_fetch_fn),
    ]:
        if old not in out:
            raise RuntimeError(f"patch_web_sw: {name} not found")
        out = out.replace(old, new, 1)
```

### Refactor R3: Active-Slot-Aware Projectile Pool

- **Target Scope:** `godot/src/game/SideCannons.gd:L79-L81, L682-L705`
- **Engineering ROI:** Prevents mid-air projectile disappearance under rapid fire (`~22.2 shots/s` × `2.2 s` = `48` live bolts) while keeping zero heap allocations during steady-state combat (`[P2-1]`).

**Current Pattern (Audited Code):**

```gdscript
const PROJ_POOL_SIZE := 24
var _proj_pool: Array[Node3D] = []
var _proj_pool_idx := 0
...
func _acquire_pooled_proj(proj_script: GDScript, fx_parent: Node3D) -> Node3D:
	...
	var idx := _proj_pool_idx
	_proj_pool_idx = (idx + 1) % PROJ_POOL_SIZE
	var slot := _proj_pool[idx]
```

**Target Pattern (Surgical Blueprint):**

```gdscript
const PROJ_POOL_SIZE := 48
var _proj_pool: Array[Node3D] = []
var _proj_pool_idx := 0
...
func _acquire_pooled_proj(proj_script: GDScript, fx_parent: Node3D) -> Node3D:
	...
	var idx := _proj_pool_idx
	for offset in range(PROJ_POOL_SIZE):
		var cand_idx := (_proj_pool_idx + offset) % PROJ_POOL_SIZE
		var cand := _proj_pool[cand_idx]
		if not is_instance_valid(cand) or not cand.is_physics_processing():
			idx = cand_idx
			break
	_proj_pool_idx = (idx + 1) % PROJ_POOL_SIZE
	var slot := _proj_pool[idx]
```

## 5. Phased Execution Roadmap & Scoped Agent Prompts

1. **Phase 1 — Containment & CI Unblock (`P1` Fixes + MVTH Baseline Tests):** Fix `[P1-5]` (`settings.cfg` CI/fresh-checkout failure), `[P1-1]` & `[P1-2]` (`TaloBackend.gd` `_join_gen` races), `[P1-3]` (`LobbyService.gd` stale cleanup), and `[P1-4]` (`patch_web_sw.py` fail-fast).
2. **Phase 2 — Gameplay, Net-Safety & Verification Integrity (`P2` Fixes):** Fix `[P2-1]`–`[P2-6]` (`SideCannons.gd` pool, `NetworkedBike.gd` first-packet guard, `TaloBackend.gd` `max_players`, `_gate_settings_guard.gd` reload, `verify_audit_regressions.gd` 3 assertions, `check_scene_sync.py` SubResource hashing).
3. **Phase 3 — Structural De-Vibing & Modular Extraction (`P2-7` & `P3` Fixes):** Split `TaloBackend.gd` into transport + lobby store, and resolve `[P3-1]`–`[P3-7]`.

### Copy-Paste Surgical Prompts for Coding Agents

> **Prompt [P1-1 / P1-2] (`godot/src/net/TaloBackend.gd`):**
> "Strictly scope edits to `godot/src/net/TaloBackend.gd` (lines 279–302, 462, 517) and `godot/tools/verify_talo_backend.gd`. Do not modify any other files. Add `bump_join_gen: bool = true` to `leave_lobby_channel()`, pass `false` at lines 462 and 517, and add `_join_gen` + sequence-counter reset guards to `join_lobby_channel()`. Add a regression test for zombie-room `_join_auto()` fallback and run `run_gates.sh --no-build`."

> **Prompt [P1-3] (`godot/src/net/LobbyService.gd`):**
> "Strictly scope edits to `godot/src/net/LobbyService.gd` (lines 37–45) and `godot/tools/verify_match_rules.gd`. Add a `_session_gen` counter incremented on `join_auto`/`join_by_code`/`create_lobby` entry so `_enter_if_current()` never calls `leave_lobby_channel()` when a newer session attempt is in flight. Add a cancel-then-create regression test and run `verify_match_rules.gd`."

> **Prompt [P1-4] (`godot/tools/patch_web_sw.py`):**
> "Strictly scope edits to `godot/tools/patch_web_sw.py` and a new `godot/tools/test_patch_web_sw.py`. Reject already-patched input (`ENGINE_CACHE` present), use `re.subn` for `CACHE_VERSION`, and raise `RuntimeError` if any of the 6 SW patch blocks is missing. Run `python3 -B godot/tools/test_patch_web_sw.py`."

> **Prompt [P1-5] (`godot/.gitignore`, `godot/tools/run_gates.sh`, `godot/tools/verify_talo_backend.gd`):**
> "Strictly scope edits to `godot/.gitignore`, `godot/addons/talo/settings.cfg`, and/or `godot/tools/verify_talo_backend.gd`. Ensure a fresh `git archive HEAD` checkout passes `bash godot/tools/run_gates.sh --no-build` with `talo_backend` green (`29/29 PASS`) without committing any `TALO_API_GAME` secret."

> **Prompt [P2-1 / P2-2 / P2-5] (`SideCannons.gd`, `NetworkedBike.gd`, `verify_audit_regressions.gd`):**
> "Strictly scope edits to `godot/src/game/SideCannons.gd` (lines 79, 682–705), `godot/src/game/NetworkedBike.gd` (lines 133–151), and `godot/tools/verify_audit_regressions.gd` (lines 350–376). Raise `PROJ_POOL_SIZE` to 48 and prefer inactive slots; require valid `"p"` before `_initialised = true`; strengthen the 3 weakened regression assertions."
