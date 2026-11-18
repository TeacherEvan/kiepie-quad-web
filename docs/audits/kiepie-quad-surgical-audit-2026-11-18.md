# Surgical Audit Report: Kiepie Quad (Kiepie Bike / Sport Quad) — 2026-11-18

| Audit Metadata | Specification |
| :--- | :--- |
| **Audit Date** | 2026-11-18 (earlier full audit: 2026-11-17, `docs/plans/audit/opencode/inkling 2 small/kiepie-quad-surgical-audit-2026-11-17.md`) |
| **Audited Scope** | Root repo `TeacherEvan/kiepie-quad` @ `3700640` (`main`). In scope: `godot/src` (31 files, 6,518 eff LOC), `godot/tools` (33 files, 4,254 eff LOC), `godot/tests` (1, 85 LOC), `src/` Blender bpy pipeline (8 files, 1,928 eff LOC), `godot/assets/sfx/generate_sfx.py` (281 LOC), `web/*.js` patch/SW/worklet helpers (not `web/index.js`), scenes/configs by reference — **13,361 effective LOC in 75 files / 13 silent catches** (preflight telemetry `tree_integrity_sha256 = 5f4211ab…882e50c5`). Excluded: `godot/addons/` (vendored GdUnit4 + Talo 0.20.0, 18,488 LOC), `web/index.js` + `index.wasm` + `index.pck` (Godot-export artifacts), `supabase/` (retired per AGENTS.md), `renders/`, `.git/`. |
| **Tech Stack & Runtime** | Godot 4.3 (GL Compatibility), GDScript, headless + xvfb gate harness, GdUnit4; Blender 5.3 `bpy` build pipeline; Web export (single-thread WASM) on Vercel (`kiepie-quad-web`); backend = Talo v1 channels/props (client scoring is authoritative by documented design) |
| **Pre/Post Audit SHA-256** | `5f4211ab…` / `5f4211ab…` (**VERIFIED ZERO MUTATION** — `git status --porcelain` empty before and after; `HEAD` unchanged at `3700640`; no gates were executed, since gate runs mutate `user://settings.cfg` and `godot/reports/`) |
| **Deterministic Health Score** | **≈ 79 / 100** (Moderate). `D_raw = 57` (0×18 + 5×8 + 17×1), `P_test ≈ 5.2` (`M_kill ≈ 65 %`), `LOC_eff = 13,361`, √(1000/13361) = 0.274 |
| **Vibe-Debt Risk Level** | **MODERATE** (`N_P0 = 0`, 65–84 band). Not to be confused with the 2026-11-17 formula output of 0/100, which saturated against 195 findings, most of them already remediated by the commits landed since. |
| **Findings** | **P0: 0 · P1: 0 · P2: 5 · P3: 17 — 22 total** (pass 1). **Deep-pass addendum (later the same day): gates executed in an isolated scratch clone — all 22 green; P2-5 runtime-reproduced; one round-1 claim retracted; P2-6 added; P3s 21–26 added. Corrected totals: P2: 6 · P3: 23 — 29 findings. See Addendum A.** |

## 1. Executive Architecture & Vibe-Debt Triage

The stack is a hobbyist-scale, single-threaded multiplayer 3D racing/arena-combat game with **engineering quality well above hobby grade**. Since the 2026-11-17 audit, the head-commit series (`9e5b0e6` … `3700640`) landed nearly every P1/P2 from that report: practice-mode damage gating, socket-alias binding for `join`/`leave`/`ready_request`/`kill_request`/`bike_state`/`shot`, token consumption with a 1 s / 20-per-minute host rate limit, `_prop_gen` interleaving guard, voluntary-leave host hand-off, fullscreen-on-launch, HUD/restart interlock fixes, coast-momentum and engine-power tuning. What remains is (1) **residual trust-boundary and liveness gaps in the net layer's failure paths** — the happy path is well guarded, but the *timeouts, rejected writes and host losses* are not; (2) **one deterministic visual defect** (building-collapse dust emitted at world origin); and (3) **hygiene debt**: per-frame JS-bridge polls on Web, per-frame deep duplication of settings in the match clock, a dead/broken Blender helper, and no CI-enforced gate run. The single strongest artifact in the repo remains the runtime gate suite (278 `_check` assertions + 6 GdUnit4 tests, all executing real physics/input rather than mocks). The weakest artifact is `src/*.py`, which has **no automated QA gate at all** and relies on manual Blender QA reviewer runs.

| Severity Tier | Count | Deduction Weight | Primary Failure Domains |
| :--- | :--- | :--- | :--- |
| **P0 — Critical** | **0** | −18 pts ea | — none found (no RCE/auth-bypass/data-loss/crash-on-boot class defect) |
| **P1 — High** | **0** | −8 pts ea | — none; the two candidate "P1-shaped" items were shipped/fixed since 2026-11-17 and are verified resolved below |
| **P2 — Medium** | **5** | −3 pts ea | Net-layer failure paths (false-success readiness, silent hand-off failure, no host re-election, props PUT clobber) + one deterministic VFX placement defect |
| **P3 — Low** | **17** | −1 pt ea | Per-frame allocations/bridge evals, dead/broken helpers, unbounded token dict, corpse-raycast, dead guards, repo weight |

### High-Risk File Telemetry Hotspots

| File Path | Effective LOC | Est. CC / Branch Density | Silent Catches | Primary Vibe-Debt Signature |
| :--- | :--- | :--- | :--- | :--- |
| `godot/src/game/VfxFactory.gd` | 766 | 19 / 0.02 | 0 | God file of pooled VFX; **contains the P2-5 placement defect**; debris/casing RigidBody3D churn per burst |
| `godot/tools/build_arena.gd` | 753 | 5 / 0.01 | 0 | Deterministic god-builder; scene-generation drift risk vs `.tscn` |
| `godot/src/net/TaloBackend.gd` | 598 | 52 / 0.09 | 0 | God object (auth+props+scorer+router); **failure paths under-tested — all four net P2s live here** |
| `godot/src/ui/MatchHud.gd` | 532 | 47 / 0.09 | 0 | God file (10 subsystems, 2 layout engines, inner `RadarControl` class) |
| `godot/tools/build_testride.gd` | 546 | 3 / 0.00 | 0 | God-builder; touch overlay duplicated from `build_arena.gd` |
| `godot/src/core/Settings.gd` | 316 | 19 / 0.06 | 0 | Silent failure on `ConfigFile.save()`; per-frame Web bridge poll |
| `godot/src/KiepieBike.gd` | 315 | 42 / 0.13 | 0 | Dual-owner `ExhaustFlames.emitting`; otherwise sound |
| `godot/src/game/CombatController.gd` | 304 | 22 / 0.07 | 0 | Redundant input predicate; documented dead signal path |
| `godot/src/TouchControls.gd` | 353 | 16 / 0.04 | 0 | Sophisticated multi-touch layer; no defects found this pass |
| `src/qb_core.py` | 506 | 18 / 0.03 | **7** | God geometry kernel; **broken+dead `add_sphere`**, bare `except: pass` in `_cap_holes` |
| `godot/src/ui/MobileTextInput.gd` | 370 | 14 / 0.04 | **3** | JS bridge eval per frame per attached LineEdit; `try/catch` blocks in embedded JS |

## 2. The 10-Principal-Engineer Deep Audit

### Lens 1 — Systems Architecture & Split-Brain State

- **[P2-2] Voluntary host hand-off never checks its write** — `godot/src/net/TaloBackend.gd:335-336`
  - **Root Cause Mechanism:** `_handoff_host_before_leave()` fires `make_request(PUT /<channel_id>, {ownerAliasId, props})` and discards the response. `is_channel_joinable()` (same file, `:214-238`) later requires `owner_alias.id == host_id`; a failed PUT leaves the lobby with a vanished owner, so quick-join permanently hides it and **nobody owns scoring, kick or start** for the remaining members.
  - **Deterministic Trigger & Failure Mode:** Host leaves a waiting lobby with ≥2 members while the PUT fails (401/403 on token expiry, transient 5xx, rate-limit) — or when `int(next_host)` collides with a non-numeric legacy alias id and the request is malformed. Lobby becomes a frozen room: present members cannot quick-join-transition, scores already registered this session remain, future writes from the "host" fail closed.
  - **Surgical Fix Specification:** Capture `res`; on non-200 emit `backend_error("host hand-off failed: %s" % status)` and either (a) retry once, or (b) write `status: "abandoned"` as a lobby prop and `_send("state", …)` so every member shows a deterministic end-screen. Add a `verify_talo_backend.gd` case asserting the non-200 path surfaces an error instead of silence.

- **[P2-3] Involuntary host loss has no re-election path** — `godot/src/net/TaloBackend.gd:26-27, 64-75` + `godot/src/net/MatchState.gd:36-54`
  - **Root Cause Mechanism:** Heartbeat only *refreshes props*; joinability checks gate **new** members for 90 s. Existing members have no leader-election: if the host tab crashes/closes/disconnects, the lobby freezes mid-match — scores stop being written, `_start_match`/`set_ready` requests go unanswered, and there is no "host lost" UX. The fix for *voluntary* leaves (hand-off) does not cover the involuntary case, which is the common one on mobile (OS kill, network swap).
  - **Deterministic Trigger & Failure Mode:** Host on 3G loses connectivity for >2 s during a match → host's PUTs fail closed (or land orphaned), peers keep rendering/steering a local simulation whose score/win authority is permanently gone; match never ends, kills never score.
  - **Surgical Fix Specification:** Smallest correct blueprint: on `STALE_LOBBY_S` heartbeat silence **and** non-host membership, (a) mark lobby `status: "host_lost"` locally, (b) the lowest-`user_id` remaining member re-issues the `_handoff_host_before_leave` request (same shape, same auth question — if the server refuses `ownerAliasId`, surface an end-screen either way), (c) `MatchState` maps `host_lost` → `match_finished("")` so HUD shows "HOST LOST — match void". If Talo refuses client-side ownership transfer outright, the doc-comment and LobbyMenu must at least say so; a silent freeze is the worst outcome.

- **[P2-4] `_apply_props()` full-snapshot PUTs are not serialized** — `godot/src/net/TaloBackend.gd:357-389, 64-75`
  - **Root Cause Mechanism:** Heartbeat (`_process`, unawaited) and match-writers (`_start_match`, `_register_kill`, `_set_ready`, joins) each build a complete prop set from the shared `_roster`/`_lobby` dictionaries and PUT it. `_prop_gen` only suppresses the *local* response handling after the fact — the stale PUT has already reached the server. If the heartbeat PUT (snapshot score=4) lands after the kill PUT (score=5), the server persists score=4 until the next successful write; a subsequent `join` from a third party re-broadcasts the rolled-back roster.
  - **Deterministic Trigger & Failure Mode:** Concurrent kill + heartbeat (host in a fight while 20 s heartbeat fires). Roster score regresses on the server; guests re-syncing from a fresh `_load_state()` see the stale value.
  - **Surgical Fix Specification:** Single-writer queue inside `TaloBackend`: `_apply_props()` must (1) `await` any in-flight write (store `_apply_props_task`), (2) coalesce dirty requests into one follow-up write, (3) on non-200, re-`_load_state()` and re-merge rather than replay. The mutex, not the generation counter, is the actual fix — the gen guard keeps the local cache readable but cannot retract an already-sent body.

- **[P3-10] Duplicate ISO-8601 codec** — `godot/src/net/MatchState.gd:179-185` vs `godot/src/net/TaloBackend.gd:684-709`
  - Two hand-rolled formatters/parsers for the same wire timestamp format with subtly different empty-string semantics. Consolidate into one static helper (e.g. `KiepieTime`) or drift will eventually parse "2026-01-01 00:00:00Z" one way and "2026-01-01T00:00:00Z" another.

### Lens 2 — Frame Budget & Performance (16.67 ms)

- **[P3-1] `MatchState._process` deep-duplicates settings every frame** — `godot/src/net/MatchState.gd:32-33, 83-84`
  - `time_limit_seconds()` → `settings()` → `(lobby.get("settings", {}) as Dictionary).duplicate(true)` runs at 60 Hz on the host for the whole match. It is ~7 keys, but it is an unconditional per-frame deep copy plus a dictionary iteration; memoize `settings()` (invalidate on `apply_lobby`) or the check `limit <= 0` runs before touching the dict at all.

- **[P3-2] Web: `Settings._process` polls the JS bridge every frame** — `godot/src/core/Settings.gd:146-153`
  - One synchronous `JavaScriptBridge.eval("!!window.__kiepieBackPending")` per frame (60 bridge crossings/s) plus `MobileTextInput._process` (one eval/frame per attached LineEdit, `godot/src/ui/MobileTextInput.gd:64-75`). On Web this competes with the render loop. Poll at 4–10 Hz (accumulator) or move to a JS→Godot callback (`JavaScriptBridge.create_callback`) for back-events.

- **[P3-12] HUD/radar/kill-feed churn** — `godot/src/Hud.gd:58-66`, `godot/src/ui/MatchHud.gd:565-591`
  - `_process` rewrites label text every frame (`%d km/h`, `%d/%d`) and bumps an unused `_frame` counter (`MatchHud.gd:14, 590`). Text-set only when the value changes; delete `_frame`.

- **[P3-13] Vehicle-Nitro VFX allocs** — `godot/src/game/VfxFactory.gd:434-521`
  - Every shot spawns a holder + 2 GPUParticles3D + flash Billboard + ring Quad + OmniLight3D + tween, and every muzzle spawns a RigidBody3D casing. At the rapid-fire cadence (0.09 s) this is ~12 MB/s of transient allocations on Web. Acceptable today (short-lived, auto-freed, counts scaled by `_q()`); the fix when it shows up in profiles is a ring of pre-spawned casings and one light reused per salvo window — **note, not a defect**.

### Lens 3 — Mathematical, Physics & Algorithmic Integrity

- **[P2-5] Building-collapse dust columns spawn at world origin — `pos` is never added** — `godot/src/game/VfxFactory.gd:834-841`
  - **Root Cause Mechanism:** `_particle`, `_flash_billboard`, `_ring_quad` in `smash_burst()` all anchor to the `pos` argument (`VfxFactory.gd:806, 815, 820, 826`). The staggered settlement puffs instead call `dust_puff(parent, local + Vector3(0, height, 0), 22)` where `local` is the *relative* `spec["o"]` offset (`Vector3(size.x*±0.2, 0, …)`), discarding the building's world position entirely. `dust_puff` treats its argument as a position relative to `parent`, so all three columns land near `(0…±2, 0.7…2.3, 0…±2)` — the arena centre — regardless of which building collapsed.
  - **Deterministic Trigger & Failure Mode:** Any building smash anywhere in either map; three dust columns erupt near the spawn origin while the debris/flash/rings correctly appear at the building. Classic "visual at wrong coordinates" defect class.
  - **Surgical Fix Specification:** `dust_puff(parent, pos + local + Vector3(0, height, 0), 22)`. Add a `verify_vfx.gd` assertion (or a one-line positional contract check) that anchoring VFX to `pos` is coordinate-consistent across the whole `smash_burst` family — the current gate locks level counts and reduced-motion behavior but never checks *where* nodes appear, which is exactly why this shipped.

- **[P3-14] Degenerate-zero guards missing at the margins** — `godot/src/game/Projectile.gd:108,131`, `godot/src/game/VfxFactory.gd:750,760`
  - `Projectile.setup()` does `velocity = p_direction.normalized() * p_speed` and `_tracer.basis = Basis.looking_at(velocity.normalized(), …)` with no `length_squared() > 1e-8` gate (all current callers guard, so this is latent, not live); `roost()` normalizes `-forward` (caller uses a normalized basis, fine today). Add the established `length_squared() > 1e-4` idiom defensively — the file's own comment at `:300` shows the author knows the pattern.

- **[P3-15] Anti-rollover damping runs pre-solver as designed** — `godot/src/KiepieBike.gd:375-394`
  - Correct by construction (`_integrate_forces`, dodge-time suspension), consistent with AGENTS.md. Verified, not a finding. `_try_dodge` correctly suspends damping for `dodge_duration` and the coyote timer guards suspension bounce. No action.

### Lens 4 — Concurrency, Async & Determinism

- **[P2-1] `TaloBackend.start()` reports success when the socket never identifies** — `godot/src/net/TaloBackend.gd:55-61`
  - **Root Cause Mechanism:** After `await Talo.socket.open_connection()`, the code polls `Talo.socket.get("_identified")` on a wall-clock deadline (2.5 s). When the deadline expires, control falls straight through to `is_ready = true`, `connection_state("connected")`, `auth_status(true, "talo online · …")` — with **no re-check of `_identified`**. On a slow/blocked network the player is told they are online while every `_send` is a no-op and no `message_received` handler will ever fire.
  - **Deterministic Trigger & Failure Mode:** Airplane mode / captive portal / Talo partial outage at scene load → MainMenu shows "Ready · online · RIDER", lobby joins hang with no diagnostics, the match never starts, and nothing in the logs names the socket.
  - **Surgical Fix Specification:** After the poll loop, `if not bool(Talo.socket.get("_identified")): auth_status.emit(false, "Talo socket timed out — check your connection"); is_ready = false; _starting = false; return`. Keep `_starting` latched on the failure path too (it currently early-returns on `auth_status(false, …)` for key-missing without clearing `_starting`, line `:43-45` — combine both fixes).

- **[P3-16] Time-up ties break on roster iteration order** — `godot/src/net/TaloBackend.gd:521-526`, `godot/src/net/MatchState.gd:124-131`
  - Host and clients iterate a `Dictionary`; equal scores pick an arbitrary (insertion-ordered) winner. For a competitive game with `match_seconds > 0` this produces non-deterministic winners on tie. Sort uids before selecting best (canonical total order, same rule as the 2026-11-17 report flagged for duplicate keys) and prefer `user_id` as final tie-break, or declare draws explicitly.

- **[P3-17] Reconnect storm has no backoff** — `godot/src/net/TaloBackend.gd:77-86`
  - Fixed 2.0 s reconnect timer, no jitter, no max-attempts, no `reconnecting` state surfaced to HUD. With a flapping mobile network this is a tight re-identify loop with no user-visible signal beyond a fleeting `connection_state`. Exponential backoff (2→4→8→16 s, cap 30 s) and one `connection_state("offline")` emission after N attempts.

### Lens 5 — Memory & Resource Lifecycle

- **[P3-3] `_used_tokens` grows without bound** — `godot/src/net/TaloBackend.gd:23, 481`
  - Every scored kill inserts its token into `_used_tokens` and nothing ever deletes entries (unlike `_kill_window`/`_shot_log`, which are pruned). Across a long session with many lobbies this is unbounded growth of consumed-token strings. Cap to the last N (e.g. 512) or clear on `leave_lobby_channel()` — tokens are only meaningful within a match.

- **[P3-4] Hidden remote proxies remain raycastable** — `godot/src/game/NetworkedBike.gd:110-125`
  - `set_respawning(true)` hides the proxy but leaves `collision_layer = 1` (set in `setup()`, `:56`). Local shots raycast into the invisible body: the bullet is consumed, the shooter gets `hit_confirmed`, but no damage/kill is possible — a silent "steal" of the projectile during the respawn window. Set `collision_layer = 0` while respawning and restore on false (defer the shape re-enable like `DestructibleBuilding` does, `:109`).

- **[P3-5] Casings are RigidBody3D per shot** — `godot/src/game/VfxFactory.gd:489-520`
  - Each muzzle casing allocates a RigidBody + CollisionShape + CylinderMesh for 2.4 s of life. Zero collision layer/mask so they cannot hit anything; they still occupy solver time on Web. A pooled cap (e.g. 24 concurrent, replace oldest) removes the spike entirely. Low priority; correct today.

- **[P3-6] `F-VFX` holder trees accumulate under repeated `queue_free` timing** — no leak found: every `impact`/`explosion`/`muzzle_flash` holder self-terminates via `create_tween` → `queue_free`. Detached timers hold Node references but all capture `weakref` or `is_instance_valid` guards (`FuelDrum.gd:105-111`, `MatchHud.add_kill`, `VfxFactory._static_cue`). Verified clean.

### Lens 6 — Security & Trust Boundary

- **[P3-7] Scoring remains client-authoritative — documented, rate-limited, not bulletproof** — `godot/src/net/TaloBackend.gd:443-509`, `godot/src/net/MockBackend.gd`
  - Any lobby member can mint a kill claim; the host enforces only a 1 s cooldown and 20/min window, and cannot cryptographically bind a token to an issuance (Talo v1 has no server RPC). This is the explicit, documented architecture (AGENTS.md; `TaloBackend.gd:5-7`) — **do not "fix" it by pretending Talo can verify**; the honest direction is PlayFab/Nakama-style authoritative scoring or accepting the 20/min ceiling. Value of this note: anyone reading this audit with money/score ambitions attached to it needs this in one place. Additionally, `_register_kill` trusts the killer's claim that `p_target` is a *specific other* member — fine at hobby scale; call it out if you ever add ranked play.
  - Related: kill targets are not clamped to arena bounds at ingest, so a forged `p_target` is any lobby uid (validated against `_roster`, `:462`) — acceptable under the same threat model.

- **[P3-8] Wire payload handling is exemplary — verified, not a finding** — `TaloBackend.gd:543-667`, `ArenaNet.gd:180-229`
  - Socket messages bind `playerAlias` to `user_id` on `join/leave/ready_request/kill_request/bike_state/shot`, reject non-finite/oversized/far-origin shots, cap at 12/s per sender, bound `join` to 8 members, and drop malformed arrays. The 2026-11-17 forgery chain (forge `score: 9999` via join row / kill with arbitrary token) is **verified closed** — keep `audit_regressions` green.

- **Secrets hygiene — verified clean:** `.env` untracked and mode-600; `godot/addons/talo/settings.cfg` gitignored and not in the tree; `TALO_API_ADMIN` never committed and never shipped; the game key ships in the pck by design; `patch_web_sw.py` `new_fetch_block` uses `u.origin === self.location.origin` before trusting `pathname`; embedded JS uses `textContent`/`setField` with `JSON.stringify` interpolation only (no `innerHTML`, no string-concat HTML). `git ls-files | grep -iE "secret|private"` → nothing. No CI secrets to leak (no `.github/workflows` at all).

### Lens 7 — Reliability & Fault Tolerance

- **[P2-1, P2-2, P2-3] Net failure paths** — covered above; together they are the single theme of this audit: *the happy path is engineered; failure is not.* Health of the suite's resilience claims depends on it.
- **[P3-9] Silent `ConfigFile.save()`** — `godot/src/core/Settings.gd:284-289`
  - `_save()` returns void and never inspects the `Error` from `_cfg.save(PATH)`; on full disk or a corrupted `user://` (or a Web quota rejection, where this *will* happen eventually on aggressive players), the player's settings are silently dropped and the next launch reverts to defaults. Check the return, emit `backend_error`-style diagnostic or at least `push_warning`, and treat the cfg as corrupt if `_cfg.load` fails (current behavior: silently reset to defaults — acceptable, but log it).
- **[P3-18] VFX `_cap_group` O(n²)** — `godot/src/game/VfxFactory.gd:416-429`
  - `pop_front()` in a `while` on an Array (O(n) per pop) plus a fresh `get_nodes_in_group` query per scare/scorch. Bounded at 24/12 so this never matters today; if scar caps grow, replace with indexed truncation.
- **Blender pipeline robustness** — `src/qb_core.py:39-43, 74-80, 475-477, 483-491, 566-575`
  - 7 silent catches, all API-drift guards *by intent* (`setv` tolerates BSDF input renames between Blender versions; `_cap_holes` swallows `faces.new` failures). These are appropriate for version-spanning tooling, but `_cap_holes` hiding a genuinely un-cappable loop means a broken STL can still emerge and only the *manual* QA reviewer catches it. Acceptable given the QA gate exists; flag for awareness, no change required.
- **[P3-11] `_signal_hold` symmetry risk is guarded today** — `godot/src/TouchControls.gd:104-119`
  - Pair-ref counting between finger indices and button signals is correct under the `_drop`/`_hold` symmetry; the `touch_multitouch` gate locks it. Noted for completeness.

### Lens 8 — Type Systems, Schema & Contracts

- **Verified:** `MockBackend` and `TaloBackend` both honor the `call_rpc` shape; `MatchState` validates `record is Dictionary` before casting; `_parse_dict_static` validates `json.get_data() is Dictionary`; `Color.html` guarded by `is_valid_html_color()`; `Application` bounds (`kill_target`, `respawn_delay`, `damage`, `max_players`) are all `clampi`-bounded. `Dictionary` boundaries are consistently guarded with `.get()` + `str()`. No `any`-escaped JSON paths. Portable-integers only.
- **Unvalidated external contract:** none beyond the socket surface already covered in Lens 6. The Talo channel props are read with `str(...)`/`_parse_dict_static` — schema-silent but fail-closed (`{}` / `"waiting"` defaults). Fine for a game; would need a strict schema if props ever carried money.

### Lens 9 — Platform, Viewport & Portability

- **Verified good:** fullscreen-on-launch bridge in `export_presets.cfg` is intact (`window.__kiepieSetFullscreen` present, not clobbered); `include_filter="addons/talo/settings.cfg"` intact; `index.pck` = 3,014,976 bytes (< 4 MB deploy abort threshold); headless/`headless` paths in `_apply` skip `DisplayServer`; `KIEPIE_MOCK_BACKEND=1` short-circuits fullscreen and backend; `Settings._is_mobile_auto()` caps DPR-dependent scales at 0.72; `_sync_mobile_scale` respects touchscreen/DPR with `dpr/stretch` clamp 1.0–4.5; `verify_touch.gd` enforces ≥44 px targets and pairwise non-overlap; `touch_multitouch` runs under xvfb for real pointer streams.
- **[P3-19] `size_changed` handlers without debounce** — `godot/src/ui/MatchHud.gd:94,176`, `godot/src/Hud.gd:54`, `godot/src/core/Settings.gd:70`
  - Every resize event triggers a full `_relayout` (MatchHud: ~15 `get_node_or_null` + offset writes). On Web drag-resize this storms the same frame budget as the 3D sim. Coalesce to 0.1 s one-shots (Timer, reconnect guarded). Cosmetic; low priority.
- **Trademark hygiene** — README/repo retains "Yamaha Blaster" class descriptors and `assets/decal_*.png` are not cleared for commercial use. The repo is public for personal portfolio use. No code change; keep on the pre-commercial checklist.

### Lens 10 — Cognitive Load & AI Maintainability

- God files: `build_arena.gd` (753), `build_testride.gd` (546), `build_menus.gd` (416), `MatchHud.gd` (532), `VfxFactory.gd` (766). All are *deterministic generators* or *presentation layers* — tolerable when gated, but every scene edit is a two-step (edit `build_*.gd` → rebuild → commit both) that AGENTS.md documents. Splitting builders into per-area modules would reduce review cost but is a deliberate style decision, not a defect.
- **[P3-20] Broken + dead helper** — `src/qb_core.py:345-362` (`add_sphere`) and `src/qb_core.py:365-371` (`add_tube` ignores `taper`/`closed`)
  - `add_sphere` builds `verts`/`faces` as locals and never pushes them into `MB()`; `mb.to_object(...)` then emits a **zero-vertex mesh object**. It has no callers anywhere in `src/` — but it is exported API of the geometry kernel, and the first future caller will silently get an empty sphere. Either fix (`self._push(verts, faces)`) or delete it. Same for the dead `taper`/`closed` parameters.
- Magic constants are pervasive but consistently named and documented in-context (e.g. `dodge_*`, `MAX_SCORCH`); `_frame` (`MatchHud.gd:14,590`) and `_spawn_set` (`KiepieBike.gd:34`) are dead — remove when touching those files.

### Explicit N/A Items & Residual Risks

- **Pass 2.5 (live geometry / canvas runtime probe):** N/A for a GL-Compatibility 3D game — there is no `CanvasRenderingContext2D` to hook; layout/overlap probing is already covered by `verify_touch.gd` (≥44 px, pairwise non-overlap) and `verify_accessibility.gd`.
- **Matrix C (Python tooling):** applicable to `src/*.py`, `godot/tools/*.py`; applied — no `shell=True`, no path traversal (`Path(...).is_relative_to` not needed; all writes are in-repo siblings), `_sha12` reads are bounded; `patch_web_sw.py:199` `write_text` is non-atomic (deploy-time tool, acceptable).
- **Matrix D (supply chain):** no dependency manifests (`package.json`/`requirements.txt`) exist; GdUnit4/Talo are vendored and pinned by vendoring (Talo 0.20.0 by necessity). `osv-scanner` has nothing to scan. No SBOM — flag if this ever ships commercially.
- **`renders/` + `QA_debrief_*.png` + `Kiepie_Bike.blend1` + `.stl` committed (~7 MB of regenerable QA artifacts and ~1.5 MB duplicate `.stl`/`.blend`)** — git bloat; `.gitignore` already covers `*.blend1` for future, existing tracked files persist. Consider `git rm --cached` in a dedicated hygiene commit; **not** a mutation this audit is permitted to make.
- **No CI:** `run_gates.sh` is the entire verification story and it is local-only; a red gate on `main` today is invisible until someone runs it. Even a minimal `.github/workflows/gates.yml` on a self-hosted/xvfb runner would close this; absent that, treat every merge as verified only if the contributor ran the suite (AGENTS.md already says as much).
- **`tide`/`credit` claims:** none found. README explicitly frames this as personal portfolio use.

## 3. Existing Test Suite Comparison & Mutation Truth Table

- **Test-to-Code File Ratio:** 21 gate scripts + 1 GdUnit4 file vs 31 `godot/src` + 33 `godot/tools` + 8 `src` — strong **integration** coverage, zero unit-level coverage of `src/*.py` (Blender pipeline) and of `VfxFactory` coordinate behavior.
- **Estimated Mutation Kill Score (M_kill): ≈ 65 %** (`278 _check` assertions + `6` GdUnit4 tests, behavioral rather than mocked; `~0` mock-heavy files; but `~0` coordinate/placement assertions and `0 %` Blender-suite coverage). Basis: assertion count above; the 2026-11-17 `M_kill ≈ 60 %` estimate is consistent — gates grew, not the mutants.

| Implementation Module | Critical Functions / Branches | Paired Test File | Pathologies Detected | Mental Mutants Killed (M1–M4) | High-Priority Missing Assertions |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `godot/src/net/MatchState.gd` | `register_kill`, `is_respawning`, `_process` time-up | `verify_match_rules.gd`, `verify_kill_flow.gd`, `verify_audit_regressions.gd`, `verify_combat.gd` | Happy-Path Tunnel Vision (zero malformed-record cases) | 3/4 (75%) | Records with `score: "NaN"`/negative, `respawn_at` past deadline |
| `godot/src/net/TaloBackend.gd` | `_on_socket_message`, `_register_kill`, `_handoff_host_before_leave`, `start()` | `verify_talo_backend.gd`, `verify_multiplayer.gd`, `verify_audit_regressions.gd` | Happy-Path Tunnel Vision on **failure** paths (P2-1/2/3 live here) | 2/4 (50%) | Non-200 hand-off PUT, identify timeout, host-silent election, props PUT ordering |
| `godot/src/game/CombatController.gd` | `take_damage`, `_die`, `_respawn`, auto-fire | `verify_practice.gd`, `verify_combat.gd`, `verify_kill_flow.gd` | Mock-Mirror (low), Happy-Path on drum/building attribution | 3/4 (75%) | Attacker not in lobby ⇒ attribution must be `""` (covered by rel audit, re-assert) |
| `godot/src/game/VfxFactory.gd` | `smash_burst`, `impact`, `_cap_group`, `damage_number` | `verify_vfx.gd` | Happy-Path; **zero coordinate/placement assertions** (P2-5 escaped all 278 checks) | 1/4 (25%) | Emitted-node world position == `pos` for every burst family |
| `godot/src/KiepieBike.gd` | `_physics_process`, `_integrate_forces`, `_try_dodge`, `reset_bike` | `truth_test.gd`, `verify_controls.gd`, `verify_dodge.gd`, `verify_stability.gd`, `verify_features.gd` | Strong; Implementation-Coupled via private vars | 4/4 (100%) | — |
| `godot/src/TouchControls.gd` / `TouchCapture.gd` | two-thumb holds, slide-swap, refcounted holds | `verify_touch.gd`, `verify_touch_multitouch.gd` (xvfb) | None significant | 4/4 (100%) | — (strongest artifact in repo) |
| `godot/src/core/Settings.gd` | `_load`/`_save`/`reset_defaults`/`v1→v2 migration` | `verify_settings.gd` | Result-Only (unobserved save errors — P3-9) | 3/4 (75%) | Corrupt-cfg recovery path asserts warning emitted |
| `src/*.py` (Blender) | `MB.to_object`, `_cap_holes`, `mirror_x`, `repair_and_verify` | `blender_qa_reviewer.py` (manual), `truth_test` downstream | Unpaired; no runnable suite | 0/4 (0%) | Headless "rebuild → QA reviewer → assert APPROVED" gate |

### Why Existing Tests Missed Discovered Findings

- **P2-5 (dust at origin):** `verify_vfx.gd` locks level counts, caps, reduced-motion collapse and flat normals — it never asserts a single emitted node's `global_position`. A placement bug is invisible to every assertion the suite has.
- **P2-1/P2-2/P2-3 (net failure paths):** gates assert what happens when things *succeed* (kill scores, roster updates, join works) and what happens on *rejected* payloads (forged events dropped). None of them simulate a socket that never identifies, a PUT that returns 403, or a host that goes silent while members keep playing — the exact paths this audit found unguarded.
- **P2-4 (props clobber):** gates run single-threaded with `KIEPIE_MOCK_BACKEND=1`; the mock backend's `call_rpc` never interleaves with the heartbeat, so the write race cannot manifest. The live ordering hazard is invisible to the offline harness by construction.

### Minimal Viable Test Harness (MVTH)

1. **Gate: VFX placement contract** (`tools/verify_vfx.gd` extension or `verify_smash_burst.gd`): spawn `smash_burst` at `(12, 0.5, -8)`; assert ≥1 emitted `dust_puff`-tagged particle system with `global_position.distance_to(pos) < 4.0`; fails pre-fix, passes post-fix. Tier 1.
2. **Gate: `MockBackend` heartbeat/kill interleave** — script `_apply_props`-equivalent ordering or simulate two concurrent `_apply_props` and assert server-side roster reflects the *last* writer deterministically; document the single-writer queue invariant. Tier 2.
3. **Gate: hand-off failure surfacing** — `verify_talo_backend.gd` with a stubbed `make_request` returning 403: assert `backend_error` emitted and lobby not silently hostless. Tier 2.
4. **Gate: socket identify timeout** — stub `_identified=false` past 2.5 s; assert `auth_status(false)` and `is_ready == false`. Tier 1.
5. **Gate: Blender QA** — `bash` wrapper running `blender -b -P blender_qa_reviewer.py -- Kiepie_Bike.stl spatial_manifest.json QA_debrief_stl.json` and `grep -q '"status": "APPROVED"'` + `non_manifold_edges == 0` as a `run_gates.sh` stage. Tier 2 (build time permitting).

## 4. Surgical Refactoring Blueprints (Zero-Mutation Drafts)

### Refactor R1: Net failure-path hardening (one concern, one PR)

- **Target Scope:** `godot/src/net/TaloBackend.gd:38-62, 77-87, 309-337, 357-389`
- **Blueprint:**
  1. `start()`: after the poll loop, branch on `_identified`; failure ⇒ `is_ready = false`, `_starting = false`, `auth_status.emit(false, …)`; success unchanged. Clear `_starting = false` on the key-missing path too.
  2. `_handoff_host_before_leave()`: capture response; non-200 ⇒ `backend_error(…)` + emit `lobby_status: "abandoned"` prop write; optionally one retry.
  3. `_apply_props()`: introduce `_apply_inflight: bool`/`_apply_dirty: bool`; entry sets dirty and `await`s prior; single writer loop drains; keep `_prop_gen` purely for response freshness.
  4. Heartbeat silence > `STALE_LOBBY_S` while non-host: emit new signal `host_lost()` from `MatchState`; LobbyMenu shows deterministic end-screen. (Smallest viable version: detect, emit, display — no re-election; server-side owner transfer stays a stretch goal.)
- **Non-goals:** no Talo schema changes, no new network messages without a matching `verify_*.gd`, no touching the documented client-authoritative scoring contract.

### Refactor R2: `smash_burst` coordinate fix (one line + gate)

- `VfxFactory.gd:841` → `dust_puff(parent, pos + local + Vector3(0, height, 0), 22)`; add MVTH-1 assertion. Pure, isolated, 1-line.

### Refactor R3: Per-frame hygiene sweep (batch, mechanical)

- `MatchState.settings()`: memoize; `_process` reads cached value (invalidate in `apply_lobby`/`set_lobby`).
- `Settings._process`: accumulate 0.25 s before the pending-eval; delete dead `_frame` in MatchHud; guard `%d km/h`/`%s of HP` label writes by value-change.
- `MobileTextInput._process`: 4 Hz accumulator (or callback-driven).
- Delete `add_sphere` (`qb_core.py:345-362`) or implement it correctly; delete `taper`/`closed` params on `add_tube`.
- Delete `_spawn_set` (`KiepieBike.gd:34`) and `_frame` (`MatchHud.gd:14,590`); remove `is_action_just_pressed("fire") or` redundancy (`CombatController.gd:80`).

### Refactor R4: Corpse-raycast fix

- `NetworkedBike.gd:set_respawning(true)` → defer `collision_layer = 0`; restore on false. Add `verify_multiplayer.gd` assertion that a respawning proxy does not intersect ray queries.

## 5. Pass 4.5 / Pass 5 Notes

- **Zero-mutation compliance:** no file was created, edited, moved or deleted during Passes 1–4; the tree was clean before and after (`git status --porcelain` empty; `HEAD` = `3700640`). Gates were deliberately **not** executed (they mutate `user://settings.cfg` / `godot/reports/`); all runtime claims are grounded in source reading and the gate contracts documented in AGENTS.md.
- **Health Score honesty:** `S_health ≈ 79` (Moderate). The 2026-11-17 report's formula output of 0/100 saturated against ~195 findings of which the commits since have demonstrably closed the serious ones (all net-layer P1s, practice-mode contradiction, gate-against-live-backend hazard — `KIEPIE_MOCK_BACKEND` is now exported by `run_gates.sh` and backend gates `quit(2)` without it, verified in `run_gates.sh:17` and `verify_practice.gd:28-31`). Report per-defect evidence, not just the aggregate.
- **Deliverable status:** this report is a new file under `docs/audits/`; it does not touch source. It is intended as a single separate docs commit — left uncommitted for your review.
- **Hand-off checklist (if remediation is requested):** (1) R2 + MVTH-1 first (one line, one gate, instant proof); (2) R1 net failure paths with the three new gate cases; (3) R4 corpse-raycast; (4) R3 hygiene sweep; then re-run `run_gates.sh` and confirm green; commit one concern per commit; do not squash R1's four hunks together.

## Appendix A — Evidence Index (file:line)

| ID | Evidence |
| :--- | :--- |
| P2-1 | `godot/src/net/TaloBackend.gd:55-61` (deadline falls through to `is_ready=true`), `:43-45` (`_starting` latch on key-missing path) |
| P2-2 | `godot/src/net/TaloBackend.gd:335-336` (response discarded), `:181-213` + `:214-238` (joinable requires owner==host_id) |
| P2-3 | `godot/src/net/TaloBackend.gd:26-27,64-75` (heartbeat writes only), absence of re-election anywhere in `MatchState`/`LobbyMenu` |
| P2-4 | `godot/src/net/TaloBackend.gd:357-389` (`_prop_gen` suppresses local response only), `:71-74` (unawaited heartbeat call) |
| P2-5 | `godot/src/game/VfxFactory.gd:834-841` (`local + Vector3(0, height, 0)` — `pos` missing) vs `:806,815,820,826` (all siblings anchor to `pos`) |
| P3-1 | `godot/src/net/MatchState.gd:32-33,83-84` |
| P3-2 | `godot/src/core/Settings.gd:146-153`; `godot/src/ui/MobileTextInput.gd:64-75` |
| P3-3 | `godot/src/net/TaloBackend.gd:23,481` |
| P3-4 | `godot/src/game/NetworkedBike.gd:110-125`, `:56` |
| P3-5 | `godot/src/game/VfxFactory.gd:489-520` |
| P3-7 | `godot/src/net/TaloBackend.gd:443-509` |
| P3-8 | `godot/src/net/TaloBackend.gd:543-667`, `godot/src/game/ArenaNet.gd:180-229` |
| P3-9 | `godot/src/core/Settings.gd:284-289` |
| P3-11 | `godot/src/game/CombatController.gd:175-180` |
| P3-12 | `godot/src/Hud.gd:58-66`; `godot/src/ui/MatchHud.gd:565-591`, `:14`, `:590` |
| P3-13 | `godot/src/game/VfxFactory.gd:434-521`, `casing()` muzzle per shot |
| P3-16 | `godot/src/net/TaloBackend.gd:521-526`; `godot/src/net/MatchState.gd:124-132` |
| P3-17 | `godot/src/net/TaloBackend.gd:77-86` |
| P3-19 | `godot/src/ui/MatchHud.gd:94,176`; `godot/src/Hud.gd:54`; `godot/src/core/Settings.gd:70` |
| P3-20 | `src/qb_core.py:345-362`, `:365-371` |
| P3-14 | `godot/src/game/Projectile.gd:108,131`; `godot/src/game/VfxFactory.gd:750,760` |
| P3-18 | `godot/src/game/VfxFactory.gd:416-429` |
| P3-10 | `godot/src/net/MatchState.gd:179-185` vs `godot/src/net/TaloBackend.gd:684-709` |
| P3-15 | `godot/src/KiepieBike.gd:375-394` (verified correct — no action) |
| P3-6 | Verified clean: `FuelDrum.gd:105-111`, `MatchHud.gd` `add_kill`, `VfxFactory._static_cue` — weakref/is_instance_valid guards throughout |

---

## Addendum A — Deep Pass (runtime execution + files initially skipped; same date)

Round 1 was a static desk-check of the risk-ranked files that happened to be open. This addendum closes the three gaps that report had: (1) nothing was executed, (2) `godot/tools/build_*.gd` and most of `src/*.py` were function-mapped but not read, and (3) one of its claims was wrong. Everything below was done against a pristine `git archive HEAD` clone at `/tmp/opencode/audit-scratch/repo` with an isolated `HOME` (`/tmp/opencode/audit-scratch/home`) and `KIEPIE_MOCK_BACKEND=1`; the audited tree was not touched (`git status --porcelain` still shows only `docs/audits/`).

### A.1 Runtime evidence — gate suite, isolated scratch clone

`bash godot/tools/run_gates.sh --no-build` (scenes committed, so no rebuild):

```
GATE SUITE: PASS — all 22 gates green
```

including truth, stability, touch, features, smash_impact, diag2, cannons, settings, match_rules, combat, kill_flow, appeal, accessibility, talo_backend, audit_regressions, controls, dodge, vfx, practice, multiplayer, touch_multitouch (xvfb), and GdUnit4 (**6/6 tests, 0 failures**, 1,182 dummy-renderer orphans — benign per repo convention). The 2026-11-17 report’s central performance claim ("gates green on this tree") is now my own measurement, not the AGENTS.md contract. Zero source mutation; scratch only.

### A.2 P2-5 runtime-reproduced (was: source-read defect)

`tools/probe_smash_dust.gd` (scratch-only, `-s` runtime-`load()` per the tool-script rule) called `VfxFactory.smash_burst(parent, Vector3(12, 0.5, −8), Vector3(6.5, 3.4, 5.0))` and enumerated emitted `GPUParticles3D` systems after the staggered timers:

```
particle systems emitted: 5
  @GPUParticles3D@7 at (12, 1.7, -8)   dist=1.20   ← glass glints  (anchored, correct)
  @GPUParticles3D@8 at (12, 1.5, -8)   dist=1.00   ← splinters     (anchored, correct)
  @GPUParticles3D@10 at (0, 0.7, 0)    dist=14.42  ← P2-5 dust column 1
  @GPUParticles3D@11 at (1.3, 1.5, -0.75) dist=12.96 ← P2-5 dust column 2
  @GPUParticles3D@12 at (-1.17, 2.3, 0.9) dist=16.00 ← P2-5 dust column 3
```

The three settlement columns erupt at/near world origin, 13–16 m from the collapse site, on every smash, in both maps. The shipped gate suite passes regardless — `verify_vfx.gd` asserts level counts, caps and reduced-motion collapse, and contains **zero positional assertions** on emitted nodes (grepped: `global_position` appears only in building-footprint AABBs). This is the strongest available argument for MVTH-1 (VFX anchoring contract in `verify_vfx.gd`). The one-line fix is unchanged (`pos + local + Vector3(0, height, 0)`).

### A.3 Retraction — round-1 claim `Settings.set_value calls _save() on every change — fine` was wrong

Un-debounced writes are live along the whole settings hot path:

- `SettingsMenu._bind_slider` (`godot/src/ui/SettingsMenu.gd:88-99`) → `Settings.set_value` → `_save()` (`godot/src/core/Settings.gd:297-306` → `_save :284-289`) → `ConfigFile.save(PATH)` **per `value_changed` tick** — i.e., dozens of file rewrites per second during a slider drag, and per color picker tick (`:79-83`, same path). On Web each is an IndexedDB round trip on the main thread; on desktop a file rewrite per mouse-move event.
- F-UI-11’s companion cost is also live: `_on_setting_changed` (`:190-192`) → `_refresh_all()` (`:154-187`) — ~30 widget writes per tick, recursion-guarded but not free.
- Same on slider *release*; no debounce anywhere in the chain.

**[P2-6] Un-debounced settings persistence on every drag tick** — `godot/src/ui/SettingsMenu.gd:88-99,79-83` + `godot/src/core/Settings.gd:297-306,284-289`.
- **Root Cause:** value-changed → save → refresh, no coalescing; `set_value`’s `old == value` early-out only catches identical values, not distinct tick values.
- **Deterministic Trigger:** any slider or ColorPickerButton drag (FOV, resolution scale, particles, volumes, steer sensitivity, dodge size, screen shake, reduced motion).
- **Surgical Fix:** debounce into `Settings` itself — `set_value` marks dirty, one `SceneTreeTimer` (0.35 s) coalesces, then a single `_save()`; flush synchronously on `NOTIFICATION_WM_CLOSE_REQUEST`/scene change. Pair with `_refresh_all` coalescing in `SettingsMenu._on_setting_changed` (same timer). One concern, one PR; re-run `verify_settings.gd` (which backup/restores `user://settings.cfg` itself — confirmed `SAV`/`BAK` at `verify_settings.gd:8-9,22-31`).

### A.4 New/confirmed low findings

- **[P3-21] Pickup `_process` burns while collected** — `godot/src/game/Pickup.gd:79-88`: `_t += delta` and the method run every frame even when `_collected` (the visual block is guarded but the tick is not); `_t` grows unbounded over the session. `set_process(false)` on collect; reset `_t = fmod(_t, TAU)`.
- **[P3-22] CVT belt wall section uses uncrossed raw tangent** (F-001-05, confirmed present) — `src/qb_engine.py:189-198`: `yn/zn` is built from `(dz, dx)` differences without crossing to the in-plane normal; on the long diagonal runs (x changes ~0.3 m over the same length as the y/z traverse) the inner/outer wall pairs shear and the belt reads as a twisted ribbon on close inspection. Cosmetic; QA gate passes (mesh is watertight). Fix: build the 2D normal from the (y,z) tangent only (`ny = -tz, nz = ty`) and keep thickness orthogonal to the loop.
- **[P3-23] `deploy_web.sh` commits the web artifact with a canned message** — `godot/tools/deploy_web.sh:39-41`: `git commit -m "Kiepie Quad: multiplayer combat, cannons, mobile Web build" || true` — every deploy records an identical, content-free message and `|| true` swallows identity/hook failures; `git add -A` in `web/` stages without review. Pass `--message "deploy: pck <sha12> wasm <sha12>"` or fail loudly; run `git status --porcelain` and require emptiness before `vercel deploy`.
- **[P3-24] Touch-overlay duplication across builders** — `godot/tools/build_arena.gd:461-543` vs `godot/tools/build_testride.gd:367-447` (~80 lines ×2). Diff shows intentional divergence only (layout/offset values, dodge button styling, comment wording); the structure is identical. Consider one parameterized builder; severity low because both sides are gate-covered (`verify_touch*`).
- **[P3-25] Orphaned `overheat` SFX** — `godot/src/audio/Sfx.gd:23` ships `res://assets/sfx/overheat.wav` with **zero call sites** after the overheat mechanic was removed (`verify_practice.gd:111-122` locks its absence). Delete the key (and the generated WAV if unreferenced elsewhere); dead audio shipped to players.
- **[P3-26] `_starting` latch never resets on early-return failure paths** — `godot/src/net/TaloBackend.gd:39-50`: key-missing and `current_alias == null` paths return without `_starting = false`, so a transient identify failure at boot permanently disables `start()` for the rest of the session (LobbyMenu shows “Still connecting…” forever with no recovery short of scene reload). One-line sibling of the P2-1 fix; fix both together.

### A.5 Confirmed clean on the deeper pass (no action)

- **All backend-touching gates hard-abort without the mock** — `verify_kill_flow.gd:25`, `verify_match_rules.gd:26`, `verify_multiplayer.gd:32`, `verify_practice.gd:37`, `verify_talo_backend.gd:59`, `verify_vfx.gd:7`; `run_gates.sh` exports `KIEPIE_MOCK_BACKEND=1` and wraps the suite in `timeout`. Confirmed by scratch run: zero live-backend traffic (my initial *probe* run without the env var did reach `api.trytalo.com` with an **empty** key and received a harmless `401 Bad Authorization`; no account state was touched — still set the env var for any future scratch probes).
- **Builders (`build_arena`, `build_testride`, `build_menus`, `build_bike`)** are deterministic scene generators: no runtime `.connect()`, owner propagation rules match the Godot 4.3 sub-scene packing semantics (in-house verified in comments), spawn/ramp layout documented in-line, `_add_touch_controls` drift is deliberate as noted. `build_menus.gd:214-220` has an explicit save-verification stage.
- **Blender pipeline**: no subprocess/shell anywhere (`grep` clean), deterministic seeds for generated textures, `repair_and_verify.py` re-verifies its own exports (AABB, weld, manifold counts, previews).
- **`gen_arena_textures.py`** deterministic; **`patch_web_sw.py`** same-origin guarded; **`inject_talo_key.py`** writes `settings.cfg` mode 0600 and ignores the admin key by name; `.env` contains `TALO_API_ADMIN` locally but it is never read by any committed tool (verified by reading `inject_talo_key.py`), and neither key is tracked in git.
- **`FollowCam`, `Sfx`, `AmbientVfx`, `BuildingDecor`, `LobbyMenu`, `SettingsMenu`, `MainMenu`** read in full this pass: no defects beyond A.4 (watch: `LobbyMenu` auto-start path is double-guarded by `_transitioning` + `_auto_start_gen`; `MainMenu._busy` dead-guard remains P3-16, now confirmed unreachable rather than latent-race).

### A.6 Corrected totals and score

| Tier | Round 1 | Addendum | Corrected |
| :--- | :--- | :--- | :--- |
| P0 | 0 | 0 | **0** |
| P1 | 0 | 0 | **0** |
| P2 | 5 | +1 (P2-6) | **6** |
| P3 | 17 | +6 (P3-21…26) | **23** |
| **Total** | 22 | +7 | **29** |

`D_raw = 6×8 + 23×1 = 71` → `S_health = 100 − 71 × √(1000/13361) − 5.2 ≈ 75.3` → **MODERATE** (unchanged band; trend downward, as it should after an honest deep pass). The Dominant Issue this pass: round 1’s blind spot was *behavioral verification* — with the suite now executed, two of its green lights coexist with a deterministic, player-visible defect (A.2) and one disk-churn defect (A.3). The gates are necessary and not sufficient; add the MVTH-1 anchoring gate and the P2-1/P2-6 cases and the suite becomes sufficient for the classes it claims to lock.

*Zero-mutation statement for this addendum: all scratch work confined to `/tmp/opencode/audit-scratch/` (probe script lives there, not in the repo); the audited tree remains `git status --porcelain` = `?? docs/audits/` only; `HEAD` unchanged at `3700640`.*

---

## Remediation log — 2026-11-18 (implemented, verified, uncommitted at time of writing)

Fixes validated on the working tree with `run_gates.sh` → **22 gates green** + GdUnit4 **6/6** (`KIEPIE_MOCK_BACKEND=1`).
Scene .tscn diffs produced by the rebuild were inspected: pure `ext_resource`/`sub_resource` UID churn, zero property changes (verified by filtered diff); scenes were restored to HEAD — next gate run regenerates them.

| Finding | Change | Proof |
| --- | --- | --- |
| P2-1 / P3-26 | `TaloBackend.start()` rewritten: explicit `_identified` verdict with wall-clock deadline; `_starting` resets on every failure path (key-missing, alias-null, socket timeout); `is_ready=false` on timeout instead of false "online" | gates: talo_backend, match_rules green |
| P2-2 | `_handoff_host_before_leave()` response checked (status==200) + one retry; failure surfaces via `backend_error` | gates green |
| P2-3 | Host heartbeat now flows during `playing` (skips only `finished`); non-hosts poll `channels.find()` every 15 s; one-shot `host_lost` (deduped per lobby); `MatchState._on_host_lost()` voids the match deterministically (`status=finished`, empty winner); `MatchHud` renders "HOST LOST — MATCH VOID"; `MockBackend.simulate_host_loss()` test hook | gates: multiplayer, match_rules, audit_regressions green; **live Talo untested** |
| P2-4 | `_apply_props()` is now a queued single-writer (`_apply_inflight`/`_apply_dirty`/`_apply_extra`); `_prop_gen` retained as response-freshness guard; heartbeat cannot land after a fresher roster write | gates: kill_flow, combat green |
| P2-5 | `smash_burst()` settlement puffs anchor `pos + local` (were spawned at world origin); casing cap (`MAX_CASINGS=24`); `roost()` zero-vector guard; `_cap_group()` O(n) | **MVTH-1 regression gate added** to `verify_vfx.gd`: `smash_burst` at (12, 0.5, -8), ≥3/5 GPUParticles3D within 5 m |
| P2-6 / P3-2 / P3-9 | `SettingsMenu` debounced persistence (0.35 s coalescer, flushed on exit, signal bursts coalesced into one `_refresh_all`); Web JS-bridge back-poll 60 Hz→4 Hz; `ConfigFile` load/save failures `push_warning` | gates: settings, accessibility green |
| P3-1 | `MatchState` `_settings_cache` memo; `_process` no longer deep-dups per frame | gates: match_rules green |
| P3-3 / P3-16 | `_used_tokens` capped at 512 (insertion-order evict); deterministic lowest-uid tie-break (`_time_up`, `leader_id`) | gates: kill_flow green |
| P3-4 | `NetworkedBike.set_respawning()` toggles `collision_layer` deferred — hidden proxy no longer eats projectiles | gates: multiplayer, combat green |
| P3-5 / P3-18 | Casing RigidBody3D cap 24 with tree-timer decrement; `_cap_group` no per-frame pop_front O(n²) | vfx green |
| P3-10 | Shared `KiepieTime.gd` ISO-8601 codec (UTC semantics probed in-engine); `MatchState`/`TaloBackend` delegate; `preload` const (autoload-safe) | all gates green |
| P3-12 / P3-19 | `Hud`/`MatchHud` text writes only on change; resize handlers 0.1 s debounced; dead `_frame` removed; respawn-overlay text cached | gates: practice, multiplayer, touch_multitouch green |
| P3-14 / P3-26 | `Projectile.setup()` degenerate-direction guard + `_inert` self-terminating bolt (replaces a `_ready` early-free that would have killed **all** bolts); `MatchHud`/HUD resized | gates: combat, practice, multiplayer green |
| P3-17 | Reconnect backoff `2^n` capped 30 s, reset on any socket message | gates: talo_backend green |
| P3-20 | `qb_core.py`: dead `add_sphere()` removed; `add_tube()` ignores nothing (dead `taper`/`closed` params deleted). `qb_engine.py`: CVT belt in-plane normal from (y,z) tangent, central difference, uncrossed components | `py_compile` clean; model **not** rebuilt (cosmetic; next `repair_and_verify.py` run picks it up) |
| P3-21 | `Pickup._process()` set_process(false) on collect, `_t = fmod(_t, TAU)` | gates: features green |
| P3-22 | See P3-20 | — |
| P3-23 | `deploy_web.sh`: content-hash deploy message (`deploy(web): wasm=<h12> pck=<h12>`); aborts on empty staged set; prints staged files; no `|| true` | shellcheck-by-reading; not executed here (no deploy requested) |
| P3-24 | `TouchOverlayKit.gd` parameterized builder (`arena`/`testride` presets); byte-identical scene output (verified: rebuilt .tscn diffs are resource-UID churn only) | gates: touch, touch_multitouch green |
| P3-25 | Dead `overheat` SFX removed: `Sfx.gd` key, `generate_sfx.py` section, `overheat.wav[.import]` (`git rm`); appeal gate sample count 10→9 | gates: appeal green |
| MVTH-1 | Anchored-dust regression gate (see P2-5) | vfx gate FAILS without the fix (pre-fix behavior) |

**Limitations (unchanged from audit):** client-authoritative scoring by design (Talo v1); live Talo path untested (mock only); waiting-room host loss covered only by the 2 s join-ack timeout; host re-election deemed impossible client-side on Talo v1 — replaced by deterministic match-void.
**Not committed yet** — await user review; nothing pushed.
