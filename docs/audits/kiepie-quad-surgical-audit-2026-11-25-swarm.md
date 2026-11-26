# Surgical Audit Report: Kiepie Quad Web (Full Codebase — Swarm Verification, 2026-11-25)

| Audit Metadata | Specification |
| :--- | :--- |
| **Audit Date** | 2026-11-25 |
| **Audited Scope** | First-party repo (`godot/src/`, `godot/tools/`, `godot/tests/`, `godot/scenes/`, `src/`, `supabase/`, `.github/workflows/`, `index.html`, `index.service.worker.js`, `godot/assets/sfx/generate_sfx.py`, build/deploy tooling; excluding vendored `godot/addons/`, generated `index.js`/`index.wasm`/`index.pck`, `renders/`, `web-assets/`, `docs/`) — **124 scoped code files / 33,730 effective LOC + 199 HTML lines = 33,929 scored effective LOC** |
| **Tech Stack & Runtime** | GDScript (Godot 4.3 Web / GLES3), Python 3 (Blender 5.3 `bpy` + build/export/SFX tooling), Vanilla HTML/CSS/JS (WASM shell + Service Worker), Talo v0.20.0, Supabase migrations (retired), Vercel Static Edge + GitHub Actions |
| **Snapshot / Integrity** | **Frozen working-tree snapshot** at HEAD `95992734a2f6aae4bbe87ed2411597375c74db37` + 44 uncommitted modifications; `tree_integrity_sha256` = `856acd5d156a639ce1b5ec4193b9528c9af18644c7b48a66991855db789d2820` |
| **Pre/Post Audit SHA-256** | `856acd5d156a6...` / `856acd5d156a6...` (**VERIFIED ZERO MUTATION** on the frozen snapshot through all 5 passes; full hash above) |
| **Deterministic Health Score** | **`89 / 100`** (`D_raw = 43`, `scale_factor = 0.171678`, `P_test = 3.75`, `M_kill = 75.00%` [`24/32`]) |
| **Vibe-Debt Risk Level** | **`LOW`** (`>=85`, `N_P0 = 0`) |
| **Companion SARIF** | `docs/audits/kiepie-quad-surgical-audit-2026-11-25-swarm.sarif` |
| **Method** | 6 parallel principal-engineer subagents across all 10 lenses + Pass 3, followed by an adversarial code-review verifier with direct-read + Godot-doc checks. 11 peer rows were rejected/stale after verification. |

> [!IMPORTANT]
> **Concurrent-worktree caveat.** The live checkout was mutated by a sibling session during the audit (HEAD advanced `e4ca9e2` → `4862080` → `9599273`, and the porcelain count moved 17 → 44 → 46). To preserve a defensible zero-mutation proof, the entire audit was re-anchored to an immutable copy at `/tmp/opencode/kq-audit/snapshot` (HEAD `9599273` + 44 mods). **All findings and line numbers below refer to that snapshot.** The live tree may have diverged further since; re-run the telemetry hash before consuming these results against a newer tree. No audit pass mutated the snapshot.

---

## 1. Executive Architecture & Vibe-Debt Triage

The game is in good structural health: **no P0 and no P1** survive adversarial verification. The prior audit's headline P1 (HornBeam plasma beam spawning behind the caster) is fixed and regression-locked, and the two contested "visual" defects raised by peer agents (charge-ring sign, `SideCannons._fire_gen`) were disproved — the verifier confirmed Godot's `Basis.looking_at()` maps local **−Z forward**, so `HornBeam.gd:178` `position.z = -0.55` correctly places the ring 0.55 m **in front** of the horn, and `SideCannons.gd:542-551` now checks generation, `combat.alive`, and `Match.is_playing()` after the awaited shot.

The residual risk is concentrated in **7 P2 defects, all in asynchronous/state-machine edges**: a permanent host-loss blindness after reconnect (`_host_lost_emitted` never cleared on the success path), a triplicated win-condition FSM with no single authority, a boomerang 3-ray "sweep" that is actually a first-hit fallback, a frame-rate-dependent hazard tick accumulator, a race-finish latch held across two unbounded awaits, a TOCTOU over-capacity lobby join, and a protocol-version check performed only at join. These are individually conditional but share one root cause: **state transitions are latched/copied across module boundaries without a single authority or a generation/timeout guard**.

No shipped-media emergency exists: the deploy budget was legitimately raised to 5.0 MiB, leaving `index.pck` at 4,686,096 B with 556,784 B (~10.6%) headroom; the peer "32 KB headroom" alarm was stale and is rejected. Test quality remains the weakest systemic axis (`M_kill = 75%`, 10 mock-heavy gate files, 11 gate defects), and the Blender builder/toolchain layer still has zero automated tests.

| Severity Tier | Count | Deduction Weight | Primary Failure Domains |
| :--- | :--- | :--- | :--- |
| **P0 — Critical (Crash / Data Loss / Security / Leak)** | `0` | `-18 pts ea` | None — no ignored server verdict, no client-authoritative damage, RLS intact |
| **P1 — High (Frame-Budget / Race / Logic Bug)** | `0` | `-8 pts ea` | None — prior HornBeam P1 fixed; hot-loop findings downgraded to P3 (counts only, no frame-time proof) |
| **P2 — Medium (State-Machine / Race / Logic Bug)** | `7` | `-3 pts ea` | `TaloBackend` (host-loss latch, win FSM, over-cap join, version drift), `BoomerangGuitar` (first-hit ray), `HazardPit` (tick drift), `RaceTracker` (await latch) |
| **P3 — Low (Polish / Test Quality / Debt / Latent)** | `22` | `-1 pt ea` | Gate pathologies (6), frame allocations (3), duplicated constants (2), latent guards (4), doc/tooling drift (3), visual polish (1) |

### High-Risk File Telemetry Hotspots (scoped, frozen snapshot)

| File Path | Effective LOC | Cyclomatic Complexity | Silent Catches | Primary Vibe-Debt Signature |
| :--- | :--- | :--- | :--- | :--- |
| `godot/tools/build_deathrace.gd` | 1,498 | 13 | 0 | Monolithic procedural track builder |
| `src/build_evan_skeleton.py` | 1,052 | 92 | 0 | Large Blender rig + 7-clip NLA builder (intentional generator) |
| `godot/src/net/TaloBackend.gd` | 1,002 | 55 | 0 | God net/lobby FSM — 4 of 7 P2s live here |
| `src/build_intro_splash.py` | 844 | 26 | 0 | Splash generator |
| `src/build_lea_unicorn.py` | 769 | 78 | 0 | Blender rig builder |
| `godot/src/game/DevilHandStrike.gd` | 814 | 28 | 0 | Procedural 3D mesh + strike FSM |
| `godot/src/ui/MatchHud.gd` | 760 | 34 | 0 | God HUD + radar + scoreboard |
| `godot/src/game/SideCannons.gd` | 689 | 68 | 0 | God weapon controller + 5-profile branching + hot-path aim |
| `godot/src/KiepieBike.gd` | 635 | 58 | 0 | God vehicle controller |

`24` scoped god files (`>400` eff LOC) and `93` high-complexity files remain, but all are concentrated in generators/tools where complexity is inherent; no *new* God object was found.

---

## 2. The 10-Principal-Engineer Deep Audit

### Lens 1 — Systems Architect

- **[P2-A1] Host-loss verdict is permanently blinded after a successful reconnect** — `godot/src/net/TaloBackend.gd:L186-L188,L223-L233,L302,L332`; `godot/src/net/MatchState.gd:L33-L42,L120-L121`
  - **Root Cause Mechanism:** `_host_lost_emitted` is a one-shot latch cleared only in `leave_lobby_channel()` (L332) and `join_lobby_channel()` (L302). The reconnect path re-fetches channel props, calls `_load_state()`, and re-emits state/roster (L223-233) but never clears the latch, so `_poll_host_alive()` returns at L188 forever.
  - **Deterministic Trigger:** Guest heartbeat goes stale → `host_lost` → MatchState ends match; socket reconnects while host is alive → authoritative `"playing"` lobby re-applied, `match_started` re-fires; host later genuinely dies → no verdict, match runs with a dead host and scoring PUTs 403.
  - **Surgical Fix:** Clear `_host_lost_emitted` whenever `_load_state()` observes a live host/heartbeat (including the reconnect re-sync), preserving one verdict per *continuous* silence.
- **[P2-A2] Win-transition FSM is hand-copied into three authorities** — `godot/src/net/TaloBackend.gd:L838,L895,L927`; `godot/src/net/MatchState.gd:L280-L283,L311-L314`; `godot/src/net/MockBackend.gd:L196-L199`
  - **Root Cause Mechanism:** `status="finished"` / `winner_id` / target evaluation is duplicated; MatchState re-derives it from both the RPC return and `postgres_change`. No `evaluate_outcome` helper exists.
  - **Deterministic Trigger:** A rule change applied to the live host only leaves MockBackend gates green while live host and guests finish differently; `MatchState.lobby` disagrees with `TaloBackend._lobby` until the next state echo.
  - **Surgical Fix:** Add pure static `TaloProtocol.evaluate_outcome(lobby, roster) -> {status, winner}`; call from all three sites; delete inline copies.
- **[P3-A3] Write-only fourth copy of lobby identity** — `godot/src/net/SupabaseClient.gd:L22,L85,L92`
  - `_lobby_id` is assigned twice and never read; `LobbyService` stale-cleanup can clear it while a valid lobby remains in `Match`/`Lobby`, so any future "in lobby?" gate reading it gets a false negative. Delete it or make it a read-only getter forwarding `Lobby.current_lobby_id`.
- **N/A — circular imports:** none; the `class_name` / preload DAG terminates at `TaloProtocol`/`KiepieTime`. **N/A — new God objects:** none beyond the prior known god-file set.

### Lens 2 — Frame-Budget & Performance

- **[P3-B01] Meteor reticle aim recomputed at 60 Hz for a visual-only element** — `godot/src/game/SideCannons.gd:L284-L288,L328`
  - `_physics_process` → `compute_meteor_target()` scans `get_nodes_in_group("bike")` (fresh Array/tick), looks up the camera rig, allocates `_aim_ray_query.exclude`, and issues a full downward raycast every physics tick. With 8 riders: ~480 distance checks + 120 Array allocations + 60 raycasts/s on an 8.33 ms budget. **Counts only — no A/B frame-time measurement was possible**, hence P3.
  - **Fix:** cache aim; recompute at ≤15 Hz or on bike-transform change; hoist camera lookup; reuse one preallocated `exclude` Array.
- **[P3-B02] `Dictionary.keys()` allocates a new Array per rendered frame** — `godot/src/game/SideCannons.gd:L291-L292` (`for k in _cooldowns:` fixes it).
- **[P3-B03] Per-frame Array churn in the touch input path** — `godot/src/TouchControls.gd:L298,L303,L346,L351`. Reuse a member scratch Array.
- **[P3-B04] Splash videos never released after skip** — `index.html:L81` `drop()` adds a CSS class and removes the node after 380 ms but never calls `pause()`, `removeAttribute('src')`, or `load()`. Detached `HTMLMediaElement` keeps decoding until GC. Add the three teardown calls.

**Payload / budget (measured in snapshot):** `index.wasm` 35,376,909 B (33.74 MiB, separate `ENGINE_CACHE`), `index.pck` 4,686,096 B, guard `5,242,880` B (`deploy_web.sh:82-85`) → **556,784 B / ~10.6% headroom**. Root and `web/` copies are md5-identical. Host load was low (`0.95` at start); no fps/wall-clock claims are made.

### Lens 3 — Mathematical, Physics & Algorithmic

- **[P2-C1] Boomerang "3-ray blade sweep" is a first-hit priority fallback, not a sweep** — `godot/src/game/BoomerangGuitar.gd:L544-L559`
  - **Root Cause:** the loop over `[0.0, 0.38, -0.38]` breaks on the first non-empty ray; no minimum-distance selection exists anywhere in the file. A far centre-ground hit at ~35 m shadows a near side rider 0.38 m off the flight line at 10 m → zero damage on both outbound and return legs.
  - **Fix:** evaluate all three rays, keep the result with minimum `distance_to(from)`, call `_on_contact()` once on the winner.
- **[P2-C2] Hazard tick accumulator discards overshoot → frame-rate-dependent cadence** — `godot/src/game/HazardPit.gd:L124-L127`
  - `_tick_accum = 0.0` instead of subtracting the interval: effective period `ceil(0.32/dt)·dt`. At 10 fps (dt=0.1) ticks every 0.4 s (25% slow); two 55-dmg ticks kill in 0.8 s vs 0.64 s at 60 fps; a 0.5 s focus stall loses 0.18 s of accrued damage.
  - **Fix:** `while _tick_accum >= tick_interval:` subtract with a 4-iteration cap and clamp `delta = minf(delta, 0.1)`.
- **[P3-C8] Identical overshoot-discard bug in beacon animation** — `godot/src/DestructibleBuilding.gd:L202-L206` (harmless at ≤12 fps); use `fmod` or bounded subtraction.
- **[P3-C4] Empty sanitized vehicle preference overrides the player's choice** — `godot/src/KiepieBike.gd:L258-L261`; only return when the sanitized value is non-empty, otherwise fall through to `Settings.preferred_vehicle()`.
- **[P3-C5] Solo blast ignites a hazard and emits a false hit marker** — `godot/src/game/CombatAoe.gd:L80-L82,L157-L158`; hazard ignition sets `hit_any_enemy = true` on owner id alone with no enemy-in-zone condition. Gate on a confirmed enemy from the bike loop.

### Lens 4 — Concurrency, Async & Determinism

- **[P2-C3] Race-finish latch held across two unbounded awaits** — `godot/src/game/RaceTracker.gd:L147-L171` (`await` at L151, L160)
  - `_finishing_lap` has no timeout, no generation guard, and is reset only on success (L184). A stalled Talo socket leaves it `true` forever; every later finish-line crossing returns at L143, so the race can never complete.
  - **Fix:** add `_lap_async_gen` bumped in `_exit_tree`/reset; race both awaits against `create_timer(5.0, ..., true)`; clear latch on timeout or gen mismatch.
- **[P2-D2] TOCTOU over-capacity lobby join** — `godot/src/net/TaloBackend.gd:L550-L559`
  - `member_count >= max_players` is checked on a cached channel snapshot before `await Talo.channels.join()`, with no post-join revalidation. Two guests reading `max-1` concurrently both pass and join; the host roster guard caps `_roster`, not channel membership.
  - **Fix:** after `join`, re-`find(id)`; if `> max` and not owner, `leave(id)` and report full; host evicts via authoritative prop rewrite.
- **[P2-E1] `PROTOCOL_VERSION` checked only at join, never on reconnect** — `godot/src/net/TaloBackend.gd:L634-L653,L223-L233,L949-L953,L991-L992`; `godot/src/net/TaloProtocol.gd:L37`
  - The wire envelope `{k, p}` carries no version; the reconnect path reloads props and calls `_load_state()` without `protocol_ok(ch)`. A host upgrading mid-session rewrites `protocol_version`; a reconnecting guest keeps applying new-encoding `state` payloads; `MatchState._refresh_settings_cache` (`MatchState.gd:L131`) calls `.duplicate(true)` on a null `as Dictionary` cast → script error and silent scoreboard divergence.
  - **Fix:** add `v` to `_send()` envelopes; reject mismatched `v` in `_on_socket_message`; call `protocol_ok(ch)` in `_load_state`/reconnect and leave the channel on mismatch.
- **[P3-D4] `_time_up_called` guard leaks across lobby switches** — `godot/src/net/MatchState.gd:L71-L72,L80-L81,L93-L106`; `reset_time_limit_guard()` has zero callers. Reset on the id-mismatch branch and in `set_lobby()` when the id changes.

### Lens 5 — Memory & Resource Lifecycle

- **[P3-B04] (also Lens 2)** unreleased `HTMLMediaElement` after splash skip — `index.html:L81`.
- **[P3-C7] Non-atomic writes in the export verifier** — `src/repair_and_verify.py:L69,L72-L73,L81`; the final `.blend`/2×`.glb`/`.stl` are written in place, unlike sibling builders' `fsync`+`os.replace` manifest path. An OOM/kill mid-export leaves a truncated shipped binary that git can commit and `scene_sync` gates accept. Export to a sibling `.tmp`, fsync, then `os.replace`.
- **Verified clean:** FollowCam, AmbientVfx, SettingsMenu, LobbyMenu, MainMenu, and MatchHud mirror autoload signal connections in `_exit_tree`; `Hud`/`MatchHud` combat/cannon connections auto-disconnect on free; `Sfx` pre-allocates voice pools and prunes freed engine hosts; no manual WebGL `gl.create*` buffers and `GodotAudio` closes its `AudioContext`.

### Lens 6 — Security & Trust-Boundary

- **[P3-E2] Empty and malformed JSON are indistinguishable** — `godot/src/net/TaloProtocol.gd:L16-L20`; `godot/src/net/MatchState.gd:L131`; callers at `TaloBackend.gd:L183,L546,L631,L646,L1026`. `parse_dict()` returns `{}` for both cases and callers feed it into unguarded `as Dictionary → .duplicate(true)` chains. A truncated `roster` prop silently empties the scoreboard and lets late joiners pass the capacity check. Distinguish parse failure from empty; keep last-good on non-Dictionary input; add a minimal schema check.
- **[P3-E4] HTTP 200 treated as proof of a well-formed channel body** — `godot/src/net/TaloBackend.gd:L689-L693`; `TaloChannel.new(body["channel"])` has no `is Dictionary` guard (the outer guard covers only `res`). Keep the previous `_channel` on malformed bodies.
- **No P0 found.** Verified: `MatchState.register_kill` honors `pending`, `apply_lobby` honors `status/winner_id`, `_process` honors `time_up`; ArenaNet recomputes damage locally (`:423`) so no client-authoritative damage crosses the wire; `SubToken` + victim authority and the `apply_lethal_blast` fail-closed guard are intact (no reintroduced identity guard); `JavaScriptBridge.eval` interpolations use `JSON.stringify`; `.env` is gitignored and untracked; retired Supabase SQL has RLS on all tables with `SECURITY DEFINER`, pinned `search_path`, and a TOCTOU unique-violation catch.

### Lens 7 — Reliability & Fault Tolerance

- **[P2-C2], [P2-C3], [P3-C7], [P3-E2], [P3-E4]** as detailed above — all are missing timeout/retry/guard or non-atomic-write patterns.
- **[P3-C8]** accumulator drift; **[P3-D4]** unreset guard.
- **Rejected as false positive:** peer C6 (`repair_and_verify.py` missing output dir) — `godot/assets` contains tracked GLBs so the `isdir` branch always succeeds.

### Lens 8 — Type Systems, Schema & Contracts

- **[P2-E1], [P3-E2], [P3-E4]** as above.
- **[P3-A4] Hand-maintained constants across modules** — `godot/src/game/ArenaNet.gd:L429` (literal `52.0` with a "keep in sync" comment), `godot/src/game/SideCannons.gd:L26`, `godot/src/net/TaloProtocol.gd:L5` (unused `STALE_LOBBY_S`), `godot/src/net/MockBackend.gd:L37`. Tuning `SHOT_SPEED` leaves remote tracers at 52.0, desyncing from muzzle/damage timing. Move `SHOT_SPEED` to a single shared constant and unify the lap constant.
- **`PROTOCOL_VERSION = 3` is consistent** across `TaloProtocol.gd:4`, `TaloBackend.gd:16`, all join paths, and the shipped SW/HTML; the gate asserts `"3"`.

### Lens 9 — Platform, Viewport & Portability

- **[P3-B04]** splash media teardown (mobile battery/decode cost).
- **Verified clean:** WCAG 2.5.8 target sizes 44–52 px with focus styleboxes (`MatchHud.gd:L310-L352`, `MainMenu.gd:L165-L172`, three `.tscn` toggles), splash skip buttons 44 px with `:focus-visible`, and `prefers-reduced-motion`/`prefers-contrast`/`forced-colors` in `index.html:81`. `Settings.gd:L204-L226` applies `devicePixelRatio`; the canvas is 100%×100% with no letterboxing, so `MobileTextInput` normalized rects and `canvas.getBoundingClientRect()` agree. The four silent JS catches are benign focus/selection guards. **Pass 2.5 live probe was not possible** (no Playwright/prod build arms and a concurrently mutating tree) — WCAG 2.4.11 focus-occlusion during the ~16 s intro and composited contrast remain *unverified*, not asserted as defects. Supabase migrations are retired per `AGENTS.md`, so schema strictness there is non-actionable.

### Lens 10 — Cognitive Load & AI Maintainability

- **[P3-A3], [P3-A4]** dead/duplicated state and constants; **[P3-B01-B03]** hot-path churn adds avoidable complexity to the input/weapon loops.
- **24 god files** remain, concentrated in generators/tools. Deep nesting `>3` was not found (max 3 in `_on_socket_message`). No 5-way naming-vocab gap: `SideCannons.PROFILES` does contain `"lea"`. The generated `.tscn` vs builder diff could not be executed read-only (running builders writes repo files); grep cross-reference and the prior `scene_sync` gate result were used instead.

### New Finding Found Only by the Verifier

- **[P3-NEW] Charge-spark particles stream out of the unicorn's rear** — `godot/src/game/HornBeam.gd:L188` (`pm.direction = Vector3(0,0,1)` on the `GPUParticles3D` parented to `_charge` at L199). Because `_charge.basis` uses `Basis.looking_at(_direction)` (local −Z forward), local +Z is backward, so the "vortex in front of her horn" (`:3`) emits backward. Set `pm.direction = Vector3(0,0,-1)` (or parent the emitter to a non-rotated node with world-space direction). The peer agents fixated on the ring's sign and missed the emitter's.

---

## 3. Existing Test Suite Comparison & Mutation Truth Table

- **Test-to-code file ratio:** 28 gate/test files vs 124 scoped implementation files (`~0.23`).
- **Ship proof:** `index.html:98` loads `index.js`; `:100` names `index.pck`/`index.wasm`; `index.service.worker.js:20-24` precaches `index.html`/`js`/`offline`/`audio.worklet` + `index.pck`. All 14 tested `.gd` modules (`TaloBackend`, `ArenaNet`, `CombatAoe`, `KiepieBike`, `SideCannons`, `HornBeam`, `DevilHandStrike`, `BoomerangGuitar`, `EvanVisual`, `LeaVisual`, `PogoVisual`, `MatchHud`, `TouchControls`, `NetworkedBike`) are present in `index.pck` → **unshipped tested modules = 0**. Gate tools and `tests/` are excluded from export and run only through `run_gates.sh` (SceneTree `-s`) and GdUnit4 (`run_gates.sh:181-182`); they gate CI, not the shipped bundle. `supabase/verify.sql` is dead weight.
- **Estimated Mutation Kill Score ($M_{\text{kill}}$): `75.00%` (`24/32`)** — basis: **890** assertion tokens across 28 files; **705** narrow negative/boundary signals; **13** mock/stub-heavy gate files; **0** unshipped tested modules; 10 hand-selected module groups (selection-biased estimate, not mechanical enumeration). Band: **Partial (40–80%)**. The prior 71.88% is superseded: `verify_lea_unicorn_weapons.gd:L240-L244` now kills the HornBeam sign-flip mutant.

| Implementation Module | Critical Functions / Branches | Paired Gate | Pathologies | Mutants Killed | Missing Assertions |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `TaloBackend.gd` | join/handoff/host-loss | `verify_talo_backend`, `verify_audit_regressions` | Mock-Mirror (F-1, F-2) | partial M4 | rejected-request rollback; reconnect latch reset |
| `ArenaNet.gd` / `NetworkedBike.gd` | shot trust, roster | `verify_multiplayer`, `verify_audit_regressions` | none material | strong | signal-disconnect P3 |
| `CombatAoe.gd` | lethal/blast/hazard | `verify_evan_weapons` | result-only (now partially fixed) | M1, M3 | hazard false hit marker (C5) |
| `HornBeam.gd` | beam/charge | `verify_lea_unicorn_weapons` | existence-only now closed | M1 (sign) | spark direction (new P3) |
| `SideCannons.gd` | fire/cooldown/aim | `verify_cannons`, `verify_evan_weapons` | Happy-Path (F-7) | M4 (post-await gen) | cooldown boundaries; 60 Hz aim cost |
| `RaceTracker.gd` | finish latch | none | **unpaired** | 0/4 | timeout/gen during awaits |
| `HazardPit.gd` | tick accumulator | none | **unpaired** | 0/4 | dt variation 10/60 fps |
| `BoomerangGuitar.gd` | 3-ray sweep | `verify_evan_weapons`, `verify_evan` | result-only | M1 | nearest-ray selection |
| `src/qb_core.py` + 7 builders | geometry/dimensions | **none** | untested | 0/4 | pytest dimension invariants |

### Why Tests Missed the Surviving P2s

- **C1/C2/C3:** gates assert geometry/values at a single nominal `dt` or a single ray hit; no boundary or time-variation input.
- **A1/D2/E1:** all Talo gates force `_channel = null`/mock transport, so no failure/reconnect/version-drift path is exercised — M4 survives every real-I/O rejection.
- **A2:** win FSM is verified per-module, never cross-checked between host, mock, and MatchState.

### Minimal Viable Test Harness (MVTH)

- **Tier 0 — spatial invariants:** generalize `verify_lea_unicorn_weapons.gd:L240-L244` into pure geometry assertions (`beam_end·dir > 0`, `charge·dir > 0`, nearest-of-3-ray wins, `radius 7.5/7.51` table).
- **Tier 1 — pure math/parsers:** table-driven setup validation `[NAN, INF, 0, -1, boundary]` for all projectiles and hazard/RaceTracker dt matrices; `pytest` for `qb_core.py` dimensions.
- **Tier 2 — concurrency/state machines:** `SideCannons.fire()` + `reset_cooldowns()` during await; `TaloBackend` rejected-request rollback and reconnect latch reset; `RaceTracker` hung-await timeout.
- **Tier 3 — contract boundaries:** signal-count assertions (`hit_confirmed`, `broadcast_received`), SW executed in a stub scope for TTL/cache survival, and a `protocol_ok` reconnect gate.

### Confirmed gate-quality defects (6 P3)

`verify_talo_backend.gd:L33-L48` (Mock-Mirror), `verify_audit_regressions.gd:L54-L84` (forged JSON bypasses parser), `test_kiepie_pad.gd:L22-L29` (presence-only), `verify_evan_weapons.gd:L65-L66,L116,L509` (global state restore bypassed by early `quit(2)`), `verify_cannons.gd:L27-L45` (happy-path only), `test_patch_web_sw.py:L99-L106` (literal-marker coupling), `verify_audit_regressions.gd:L360-L368` (single-sample time window).

---

## 4. Pass 4 — Quantitative Score & Surgical Refactoring Architecture

Computed with `scripts/score_audit.py` (no hand math):

| Metric | Value |
| :--- | :--- |
| Effective LOC | 33,929 (33,730 code + 199 inline HTML) |
| P0 / P1 / P2 / P3 | 0 / 0 / 7 / 22 |
| $D_{\text{raw}}$ | $18·0 + 8·0 + 3·7 + 1·22 = 43$ |
| Scale factor | $\sqrt{1000/33929} = 0.171678$ |
| $M_{\text{kill}}$ / $P_{\text{test}}$ | 75.0% / $15·(1−0.75) = 3.75$ |
| $S_{\text{health}}$ | $\max(0, \mathrm{round}(100 − 43·0.171678 − 3.75)) = \mathbf{89}$ |
| Risk level | **LOW** (≥85, $N_{P0}=0$) |

### Before / After Blueprints (anti-over-abstraction: pure helpers + generation latches, no new frameworks)

1. **Host-loss latch (A1):** *Before* — clear only on join/leave; *After* — one line in `_load_state()`: `if <heartbeat fresh and host in roster>: _host_lost_emitted = false`. No new class.
2. **Win FSM (A2):** *Before* — three inline copies; *After* — one `static func evaluate_outcome()` in `TaloProtocol`, three call sites, delete the copies.
3. **Boomerang rays (C1):** *Before* — `break` on first hit; *After* — track `best` by `distance_squared_to(from)` across all three offsets, call `_on_contact(best)` once.
4. **Hazard tick (C2):** *Before* — `_tick_accum = 0.0`; *After* — bounded `while` subtraction with `delta = minf(delta, 0.1)`.
5. **Race latch (C3) / fire latch (D-1 pattern):** *Before* — bare `await`; *After* — `gen := _gen` before await, `if gen != _gen: return` after, plus a 5 s timer race.
6. **Join TOCTOU (D2) / version drift (E1):** *After* — post-join `find()` recheck and `protocol_ok` on reconnect with channel leave on mismatch; add `v` to the wire envelope.

---

## 5. Carry-Forward Delta & Rejected Peer Findings

| Peer ID | Verdict | Reason |
| :--- | :--- | :--- |
| B-05 (script/headroom half) | **STALE** | Guard raised to 5.0 MiB (`deploy_web.sh:82-85`); real headroom 556,784 B (~10.6%), not 32,496 B. B-05 *doc half* is confirmed (`AGENTS.md:167` still says 4,279,216 B / 4.5 MiB). |
| C6 | **FALSE POSITIVE** | `godot/assets` contains tracked GLBs, so `isdir` always succeeds; trigger impossible. |
| D-1 (SideCannons respawn race) | **STALE** | `_fire_gen` present (`:98,116,124,542,544`) and post-await guard checks gen + `combat.alive` (`:547`) + `Match.is_playing()` (`:550`). |
| D-3 (CI permissions) | **STALE** | `permissions: contents: read` now at `gates.yml:7-8`. |
| D-5 (handoff race) | **STALE** | `await _apply_drained` + `_handing_off` now at `TaloBackend.gd:598-600,616-618`. |
| D-6 (apply_blast identity) | **FALSE POSITIVE** | `allow_local_damage` guard exists at `CombatAoe.gd:58-61`. |
| E3 (`"*"` settings reset) | **FALSE POSITIVE** | Both consumers handle `"*"`: `TouchControls.gd:128` re-reads/re-layouts, `MatchHud.gd:605` re-reads `show_fps`. |
| F-3 (charge ring behind horn) | **FALSE POSITIVE** | Godot `Basis.looking_at` maps local −Z forward, so `z = -0.55` is in front; test now asserts `z < -0.1`. |
| F-5 (`hit_confirmed` unasserted) | **STALE** | Signal counter now asserted at `verify_evan_weapons.gd:417-428`. |
| F-10 (CI gate label) | **STALE** | `gates.yml:33` already reads "33 total". |

Prior audit carry-forwards verified still fixed: join-gen zombie eviction and `join_lobby_channel` race, LobbyService `_session_gen` cleanup, ArenaNet shot trust boundary (24/s per-sender + 12/s global caps), EvanVisual remote speed clamp, Boomerang single-hit channel, SideCannons pool eviction, deploy_web atomic sync, `patch_web_sw` strict markers, `run_gates` anti-vacuity, and the HornBeam beam-sign P1.

---

## 6. Zero-Mutation Verification

1. **Pass 1 preflight:** `tree_integrity_sha256` captured for the frozen snapshot = `856acd5d156a639ce1b5ec4193b9528c9af18644c7b48a66991855db789d2820`.
2. **Passes 1–4:** all tools invoked with `python3 -B`; probes and scratch confined to `/tmp/opencode/kq-audit/`; no repo source/config/test file was created, edited, formatted, or deleted.
3. **Pass 5 pre-report recheck:** snapshot hash re-computed and identical to Pass 1. The *live* checkout diverged (`456632d4…`, 46 porcelain entries) because of an independent sibling session; this audit never used the live tree as its authoritative source after freezing.
4. **Report write:** only the two new `docs/audits/*-swarm.*` deliverables are added to the live repo, as a separate docs artifact; they are excluded from the scored scope.

**Bottom line:** `89/100`, **LOW** risk, **0 P0 / 0 P1**, 7 P2 and 22 P3 confirmed after adversarial verification. The dominant remediation value is closing the four net-state edges (A1, A2, D2, E1) with generation/authority helpers and adding Tier 0–2 MVTH assertions for the three unpaired async/math modules.
