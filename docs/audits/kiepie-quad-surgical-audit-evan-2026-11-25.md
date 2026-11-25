# Surgical Audit Report: Evan the Skeleton — Vehicle & Integration

| Audit Metadata | Specification |
| :--- | :--- |
| **Audit Date** | 2026-11-25 |
| **Audited Scope** | Evan vehicle + integration surface: 13 GDScript impl files, 4 tools/build files, 4 generated/QA artifacts (`4,885` effective LOC; HTML LOC N/A — Godot Web shell unchanged this change) |
| **Tech Stack & Runtime** | Blender 5.3 `bpy` build script → plain glTF 2.0 GLB (52 joints, 4 NLA clips) → Godot 4.3 GDScript (`VehicleBody3D` / `StaticBody3D` proxies) → Godot Web/WASM; Talo v1 realtime backend (host-authoritative client logic, `PROTOCOL_VERSION = 3`) |
| **Pre/Post Audit SHA-256** | `3bbb7140833572dd…` / `3bbb7140833572dd…` (VERIFIED ZERO MUTATION — full hash `3bbb7140833572dda56268947ca6db2cbfd6e8420c2a700d03f00bf`, clean `git status`, HEAD `cedd755`) |
| **Deterministic Health Score** | **`62 / 100`** (`D_raw = 63`, `P_test = 9.9`, `M_kill = 34%`, scale factor `0.452447`) |
| **Vibe-Debt Risk Level** | **`HIGH`** (40–64 band; 0 P0) |

## 1. Executive Architecture & Vibe-Debt Triage

The Evan feature is architecturally sound at the asset and registry layer: a deterministic Blender builder emits a plain 730,720-byte GLB with 52 joints, four real NLA clips, byte-exact landmark names, and a QA-APPROVED mesh (4,062 verts / 7,354 faces / 0 non-manifold edges / `minZ = 0.000`); the shipped root `index.pck` verifiably contains every new script and asset, and the `.tscn` diff is resource-ID churn except for one correct two-line menu addition. The dominant failure mode is instead at the **behavioural assurance and trust boundary**: the remote Evan animation estimator diverges numerically in ~6 frames (`lerpf(..., 9.0)` extrapolates), the lethal resolver's victim authority is implicit in group composition rather than explicit, and the 31/31 gate suite can be green with gutted gate bodies because `verdict()` never asserts a minimum number of PASS lines. Also material: the `shot` wire branch has no roster gate, global strike cap, token dedup, or validated-before-logging order, and the deploy path verifies only `index.html` + SW hashes while copying the bundle non-atomically. None of these are P0 — no crash, data loss, confirmed exploit of a live account, or corrupted shipped artifact was proven — but together they make the current green suite an unreliable proxy for correctness.

| Severity Tier | Count | Deduction Weight | Primary Failure Domains |
| :--- | :--- | :--- | :--- |
| **P0 — Critical (Crash / Data Loss / Security / Leak)** | `0` | `-18 pts ea` | None found |
| **P1 — High (Frame-Budget / Race / Logic Bug)** | `3` | `-8 pts ea` | `ArenaNet.gd` shot trust boundary; `run_gates.sh` vacuity acceptance; `deploy_web.sh` non-atomic sync + artifact-blind verification |
| **P2 — Medium (God File / Split-Brain State / Debt)** | `10` | `-3 pts ea` | Numeric divergence in remote animation; implicit lethal authority; pooled-slot stale state; fail-open model commit; existence-only / OR'd test assertions |
| **P3 — Low (Magic Constants / DX / Portability)** | `9` | `-1 pt ea` | Dual hit channels, sqrt radius filters, dead branches, duplicated vocabularies, builder fragility, under-specified Web hygiene |

### High-Risk File Telemetry Hotspots

| File Path | Effective LOC | CC / Branch Density | Silent Catches | Primary Vibe-Debt Signature |
| :--- | :--- | :--- | :--- | :--- |
| `godot/src/game/SideCannons.gd` | 637 | CC 58 / 0.09 | 0 | God file; 4-profile branching + pooled-slot lifecycle by convention |
| `godot/src/KiepieBike.gd` | 619 | CC 58 / 0.09 | 0 | God file; duplicated vehicle-resolution pipelines |
| `godot/src/game/BoomerangGuitar.gd` | 392 | CC 20 / 0.05 | 0 | Long `_physics_process` + multi-channel hit signalling |
| `godot/src/game/DevilHandStrike.gd` | 377 | CC 17 / 0.05 | 0 | Net-supplied instant-kill parameters stored verbatim |
| `godot/src/game/ArenaNet.gd` | 370 | CC 57 / 0.15 | 0 | 24 relay branches + per-id rate dictionaries; no roster gate on `shot` |
| `godot/src/game/SoundWaveProjectile.gd` | 312 | CC 17 / 0.05 | 0 | Two hit channels with no local idempotency latch |
| `godot/tools/verify_evan_weapons.gd` | 307 | CC 22 / 0.07 | 0 | Strong lethal-blast invocation check beside presence/value proxies |
| `godot/src/game/EvanVisual.gd` | 75 | CC 20 / 0.27 | 0 | Highest branch density in scope; unbounded `lerpf` weight |
| `src/build_evan_skeleton.py` | 769 | n/a (Python) | 0 | Single ~680-line `build_evan()` with 15 nested closures |

## 2. The 10-Principal-Engineer Deep Audit

### Lens 1 — Systems Architect

- **[P2-3] `hit` signal conflates scenery contact with enemy hit** — `godot/src/game/BoomerangGuitar.gd:L346-L353`, `:L371-L374`
  - **Root Cause:** `_did_hit_any` / `_first_target` are committed for *any* collider before group classification, and `_finish()` emits `hit.emit(_first_target, _first_point)` unconditionally on `_did_hit_any`.
  - **Deterministic Trigger & Failure Mode:** Outbound guitar at ~1 m altitude grazes Ground before any rider; a listener treating `hit` as hit-confirmation (the convention used elsewhere via `hit_confirmed`) records a false kill confirmation, and a clean return emits `hit` carrying `null`.
  - **Surgical Fix Specification:** Set `_did_hit_any` / `_first_target` only after `_resolve_bike(node)` yields a non-owner bike or after a destructible/hazard actually took an action; guard the emit with `_first_target != null`.
- **[P3-5] Four hand-maintained vehicle identifier vocabularies** — `godot/src/game/VehicleRegistry.gd:L8-L15`, `:L20-L42`, `:L45-L51`; `godot/src/ui/MainMenu.gd:L16`
  - **Root Cause:** `StringName` constants, duplicated literals in `sanitize_preference()`, short profile strings, and `VEHICLE_IDS` are all maintained by hand; Evan added a fifth entry manually to each relevant list.
  - **Trigger:** Rename/add a vehicle in one place → MainMenu writes an id the whitelist rejects → selection silently collapses to the hashed deal with no error.
  - **Fix:** Derive `sanitize_preference` from `VEHICLES + [VEHICLE_EVAN]`, export a single `ALL_IDS`, build the OptionButton from it, and lock set-equality in `verify_evan.gd`.

### Lens 2 — Frame-Budget & Performance

- **N/A for per-frame heap churn** — all three projectile scripts pre-allocate meshes/materials/tints; the only per-tick Dictionary is Godot's unavoidable `intersect_ray` result. No O(N²) scans or unbounded arrays/pools exist (`_shot_log`/`_rocket_last`/`_meteor_last`/`_hit_ids` are bounded and erased on roster leave).
- **[P3-2] `sqrt` used for pure radius filters** — `godot/src/game/CombatAoe.gd:L40`, `:L75`, `:L86`, `:L121`, `:L148`, `:L158`
  - **Root Cause:** `distance_to(center)` computes a square root for every candidate even where distance is never used beyond `> radius`; the lethal instant-kill path at `:121` is the hottest case.
  - **Trigger:** Large rider/hazard/destructible counts during a multi-kill Devil Hand strike — redundant sqrt per candidate per resolver call.
  - **Fix:** Filter with `distance_squared_to(center) > radius * radius`; keep `distance_to` only where falloff needs it (`apply_blast:40` → `:47-49`).
- Informational: `godot/assets/Evan_Skeleton.glb.import` sets `meshes/generate_lods=true` and `create_shadow_meshes=true` for 71 skinned meshes; import-time cost is inside the 4.5 MiB budget but worth measuring on low-end Web if more vehicles are added.

### Lens 3 — Mathematical, Physics & Algorithmic

- **[P2-1] Remote Evan animation estimator diverges geometrically** — `godot/src/game/EvanVisual.gd:L80-L90` (defect at `:85-86`)
  - **Root Cause:** `lerpf(_remote_speed, target, 9.0)` uses an unclamped weight. Godot's `lerp` extrapolates; the recurrence is `x[n+1] = 9·T − 8·x[n]`, multiplier `−8`.
  - **Trigger:** Any remote Evan proxy with `disp.length() < 8.0` (normal driving): `0 → 9 → −63 → 513 → −4095 …` reaches ±inf/NaN in ~6 frames. `speed > 1.2` at `:95` then thrashes or (on NaN) is always false, leaving remote Evan stuck in Idle. Cosmetic-only impact — no physics or scoring effect.
  - **Fix:** Frame-rate-independent smoothing as in `NetworkedBike.gd:199`: `var t := 1.0 - exp(-9.0 * minf(delta, 0.05)); _remote_speed = clampf(lerpf(_remote_speed, target, t), 0.0, 60.0)`.
- **[P2-4] Instant-kill zone parameters stored verbatim from net setup** — `godot/src/game/DevilHandStrike.gd:L180-L190` (defect at `:184`, `:189`; dead branch at `:187`)
  - **Root Cause:** `p_blast_radius` and `p_damage` are unvalidated and drive `CombatAoe.apply_lethal_blast()`; `fall_duration` alone is clamped. `visual_style = p_visual_style if p_visual_style in ["devil_hand"] else "devil_hand"` is a no-op.
  - **Trigger:** A malformed/oversized radius from a net-driven `setup()` widens an instant-kill zone unboundedly; non-finite values poison distance comparisons.
  - **Fix:** Reject non-finite `p_damage`/`p_blast_radius`; clamp `blast_radius` to the authored 7.5 m envelope; delete the dead ternary.
- **[P3-3] Inert re-setup of a non-pooled wave leaks an orphan** — `godot/src/game/SoundWaveProjectile.gd:L146-L149`, `:L161-L168`
  - **Root Cause:** If `setup()` is re-issued with a degenerate direction on an already-built non-pooled wave, `_rearm_wave()`'s inert branch hides the node and disables physics but never frees it; with `_physics_process` off, `_recycle()` is unreachable.
  - **Trigger:** Re-issue a wave instance with a zero/NaN direction after first use → invisible node lives until `_exit_tree`.
  - **Fix:** In the inert branch call `_recycle()` (which already `queue_free()`s non-pooled nodes).
- **[P3-4] Recoil lockout is a hardcoded 1.2 s wall** — `godot/src/game/EvanVisual.gd:L49-L55`, `:L66-L70`
  - **Root Cause:** `trigger_recoil()` sets `_finish_cd = 1.2` independent of the actual `Action_BigFinish` clip length; `_physics_process` suppresses all clip changes until it expires.
  - **Trigger:** Clip shorter than 1.2 s → frozen final pose; longer → crossfade cut mid-clip on every shot.
  - **Fix:** Derive from `_anim.get_animation(CLIP_FINISH).length / _anim.speed_scale`, or connect `animation_finished` and clear `_last_clip` there.
- **Verified clean:** great-circle return steering at constant speed with antiparallel fallbacks (`BoomerangGuitar.gd:378-403`), swept rays against tunneling (`:433-439`, `SoundWave:324-329`), degenerate-direction guards (`SoundWave:131`, `Boomerang:174-179`), delta-scaled animation blend (`:403`).

### Lens 4 — Concurrency, Async & Determinism

- **[P1-1] `shot` branch has no roster gate, sender binding, global cap, or token dedup** — `godot/src/game/ArenaNet.gd:L157-L158`, `:L279-L324`, `:L328-L373` (pre-existing relay surface, **amplified by Evan** because `rocket`/`meteor` now spawn boomerangs and instant-kill hands)
  - **Root Cause:** Unlike `"state"` at `:150-151`, `"shot"` accepts any `id` from the packet. Rate limits are per-attacker-controlled-id; there is no global strike budget and no `token` set. `_shot_log[owner_id]` is appended at `:324` *before* the `w` whitelist at `:325-327`.
  - **Trigger:** A rogue peer forges `shot` packets cycling through every roster id (each already has a proxy from `_sync_roster`), each id getting its own 24 tracers/s + 1 rocket/1.15 s + 1 meteor/5.5 s budget → multiplied damaging strikes into the local player; the same spoof can pre-fill `_rocket_last`/`_meteor_last` to suppress a real player's weapons. Invalid `w` packets still consume the 24-slot window (tracer DoS).
  - **Fix:** Apply the `:150` roster gate to `"shot"`; move the `w` whitelist above the `:324` append; add a bounded token-dedup set and a global strike budget independent of `id`. **Constraint:** Talo v1 cannot issuance-bind a client-minted token to an authenticated sender (documented in `AGENTS.md`), so sender-bound identity is not achievable without a protocol change — do not claim otherwise; the feasible containment is roster gate + dedup + global cap.
- **[P2-7] Spawn slot computed from a stale/incomplete roster, once** — `godot/src/game/ArenaNet.gd:L43`, `:L50-L78`
  - **Root Cause:** `_place_local_bike_at_roster_slot()` runs in `_ready()` before `_sync_roster()` and is never recomputed on `Match.roster_changed`; `uids.find(Supabase.user_id)` returns `−1` when the local row is missing and `maxi(0, −1)` silently maps everyone to `SPAWN_ORDER[0]`.
  - **Trigger:** A client whose arena becomes ready before its roster row arrives overlaps slot 0 with the legitimate owner, for the whole match.
  - **Fix:** Gate on `uids.has(Supabase.user_id)` and defer/re-run on `roster_changed` until the match starts or the player drives; add a one-shot applied latch.
- **[P3-7] Replay guard and rate-log order fail open** — `godot/src/game/NetworkedBike.gd:L124-L129`; `godot/src/game/ArenaNet.gd:L324-L327`
  - **Root Cause:** `if n >= 0 and n <= _last_tick: return` accepts packets with missing/invalid `n` entirely; the shot log is appended before kind validation.
  - **Trigger:** A crafted `state` packet omitting `n` repeatedly drives `_target_pos` backwards within the `:140`/`:146` clamps, snapping the proxy around; junk `w` packets starve legitimate fire.
  - **Fix:** Reject `n < 0` under v3 (legacy only behind an explicit flag) and clamp `n` to `_last_tick + 1`; move the whitelist before the append.
- **Verified clean:** `_death_gen` / `_state_tick` monotonic fences on delayed coroutines; `SideCannons.fire()` cooldown-before-await ordering prevents double-fire.

### Lens 5 — Memory & Resource Lifecycle

- **[P2-5] Fail-open vehicle model commit** — `godot/src/game/NetworkedBike.gd:L65-L73`, coupled with `:L120` (pre-existing for all vehicles; Evan inherits)
  - **Root Cause:** `_assigned_vehicle = vehicle` is committed at `:68`, then `load(model_path)` returning null at `:71-73` exits silently; the `force`/equality guard at `:66-67` prevents any retry because the id now matches.
  - **Trigger:** A client with an unimported Evan GLB permanently shows a Pogo/Aston shell while `ArenaNet` resolves Evan from the roster and spawns boomerangs / devil hands from the wrong visual; `EVAN_VISUAL` is never attached.
  - **Fix:** Commit `_assigned_vehicle` only after a successful load; on failure `push_error`, restore the previous value and `call_deferred("_apply_roster_vehicle", true)` with a bounded retry cap.
- **[P2-6] Pooled projectile slots returned without explicit state reset** — `godot/src/game/SideCannons.gd:L718-L747`; `godot/src/game/ArenaNet.gd:L378-L379`, `:L397-L402`
  - **Root Cause:** `_acquire_pooled_proj` only swaps script/reparents; it never clears `visible`, transform, physics, or `on_hit`. ArenaNet sets `on_hit` only when `combat != null`, and its exhaustion loop returns slots without checking `is_physics_processing()`, stealing in-flight tracers.
  - **Trigger:** Local combat freed → a reused slot keeps a Callable to a freed `CombatController` (error on impact); `combat == null` → stale callback persists; 32 busy slots → a live tracer teleports to a new origin and its original hit vanishes.
  - **Fix:** On every acquire set `visible = true`, clear `on_hit = Callable()`, assign the current callback unconditionally, reset the transform from `setup()` and re-enable physics; prefer the oldest in-flight slot in the exhaustion path and clear its callback before reuse.
- **N/A for unbounded dictionaries** — every relay dictionary is bounded and erased on roster leave; `_exit_tree` cleanup exists in all three weapon scripts (lights released, nodes queued free).

### Lens 6 — Security & Trust-Boundary

- Primary: **[P1-1]** (see Lens 4) — client-supplied `id` drives damaging-spawn authority; mitigated only by rate limits, which Talo v1 host-authoritative-client-logic explicitly cannot harden server-side.
- **[P2-2] Lethal resolver relies on implicit victim authority** — `godot/src/game/CombatAoe.gd:L126-L138` (new Evan resolver)
  - **Root Cause:** `take_lethal_hit` is called on every in-range bike with a controller with no explicit local-victim check, unlike the sibling `BoomerangGuitar.gd:321-327` which fails closed. The assumption "only local bikes carry a CombatController" is true today but unasserted.
  - **Trigger:** A remote `NetworkedBike` proxy that gains `take_lethal_hit` (or a second locally-controlled bike in the `bike` group) is killed from the shooter's client, emitting a lethal/score event from the wrong authority.
  - **Fix:** Before `:138`, mirror the boomerang guard: `if local_uid == "" or target_id == "" or target_id != local_uid: continue`. Apply the same guard to `apply_blast` at `:59` for consistency.
- **[P3-6] Preference resolution fails open to local Settings** — `godot/src/KiepieBike.gd:L246-L257` (pre-existing pipeline; Evan inherits)
  - **Root Cause:** When `Match.players[lookup_id]["vehicle"]` is absent/invalid, `_resolve_vehicle_pref` falls through to `Settings.preferred_vehicle()` — a locally owned value — with no proof it came from the host roster.
  - **Trigger:** A client with a missing `vehicle` key self-selects any allowlisted vehicle including Evan, bypassing the deterministic deal and the roster-level Nardus guarantee; damage/cooldown/spread derive from that choice.
  - **Fix:** In networked contexts (`Match != null and Match.is_playing()` or non-empty roster) return `""`; restrict the Settings fallback to practice/solo. Keep the strict `sanitize_preference` allowlist and **do not** add Evan to `VEHICLES`.
- Verified clean: no `shell=True`, no path traversal, no hardcoded secrets in the builder, no token/weapon-kind parsing in the menu/registry layer; `PROTOCOL_VERSION` untouched; hashed deal fixtures preserved (Evan is preference-only).

### Lens 7 — Reliability & Fault Tolerance

- **[P3-1] Two independent hit channels with no idempotency latch** — `godot/src/game/SoundWaveProjectile.gd:L338-L342`
  - **Root Cause:** One collider is reported via `hit.emit(...)` and `on_hit.call(...)` in the same frame; the comment says damage stays in `on_hit`, but nothing enforces it.
  - **Trigger:** Any caller wiring both channels to damage applies it twice from one wave.
  - **Fix:** Add a `_reported` latch enforcing a single authoritative channel, or rename `hit` to `contact` so its non-damage purpose is unambiguous.
- **[P3-7 / P3-4]** Deferred collision toggle leaves one frame of visible-but-intangible proxy (`NetworkedBike.gd:172-181`); hardcoded recoil lockout desyncs clip state (`EvanVisual.gd:53`). Fixes in Lens 3/4.
- Verified clean: no silent catches in scope; `Match`/`Supabase`/`Settings` autoload reads are membership-guarded; test gates abort on live backend rather than touching a real account.

### Lens 8 — Type Systems, Schema & Contracts

- **[P3-8] Builder artifact-write fragility** — `src/build_evan_skeleton.py:L83-L88`, `:L707-L714`, `:L83-L769`
  - **Root Cause:** `open(manifest_path, "w")` truncates in place with no `fsync`/`os.replace`; `bpy.ops.wm.save_as_mainfile` honours `save_version` and can emit an undeclared `.blend1`; `argv.index("--previews") + 1` can `IndexError` with no value; a ~680-line `build_evan()` holds 15 nested closures; `EXCLUDE` at `:716` is computed but never used.
  - **Trigger:** Build interrupted mid-write → truncated manifest that no longer matches the GLB; a machine with Save Versions ≥1 → stray repo file; `-- --previews` with no directory → crash before any output.
  - **Fix:** Write `<manifest>.tmp` + `flush()` + `os.fsync()` + `os.replace`; set `save_version = 0` around the save; validate the `--previews` argument; split the builder into module-level stages and either use or delete `EXCLUDE`.
- **[P3-5 / P2-4]** Duplicated id vocabulary and unsanitized wire-supplied kill radius (see Lenses 1/3).
- Verified clean: every dynamic `get()`/`set()` in the registry/bike/menu is membership-guarded; no falsy `""`/`0` coercion bugs; no mutable Python defaults; GLB stays plain (`extensionsUsed = []`, no Draco), landmark names byte-exact.

### Lens 9 — Platform, Viewport & Portability

- **[P1-3] Non-atomic bundle sync + artifact-blind live verification** — `godot/tools/deploy_web.sh:L96`, `:L114-L121`; `godot/tools/check_web_hygiene.py:L27-L108`
  - **Root Cause:** `cp -f "$ROOT/web/"* "$ROOT/"` overwrites served files one by one; the EXIT trap restores only Talo settings, not `index.*`. Post-push verification hashes only `index.html` + `index.service.worker.js`. `web_hygiene` checks policy files, never `index.pck` contents or SW precache entries.
  - **Trigger:** Timeout/SIGINT/disk-full mid-copy → root holds a new `index.wasm` with an old `index.pck`; the script commits/pushes the mismatched pair → browser WASM abort with no rollback. Or Vercel edge still serves the old cached `index.pck` while `html`/`sw` hashes match → script prints `DEPLOY OK` while players run stale assets.
  - **Fix:** Copy to `.<f>.tmp`, fsync, then `mv -f` each; snapshot `index.*` and restore on trap; hash all eight bundle files with a `?v=$git_sha` cache-buster; add a Tier-0 static gate grepping `strings index.pck` for required `res://` paths and asserting every SW precache entry exists.
- **[P3-9] Web hygiene contract under-specified** — `godot/tools/check_web_hygiene.py:L41-L47`, `:L56-L83`, `:L87-L97`, `:L99-L118`
  - **Root Cause:** Exactly one viewport meta is required and only `user-scalable=no` rejected (`width=device-width`/`initial-scale` unchecked); splash is four raw substrings (no `autoplay`+`muted` on `<video>`, no reduced-motion branch assertion); CORP header and immutable `/web-assets/*` caching unasserted; non-git fallback computes `shipped` then skips every disallow/count check.
  - **Trigger:** `width=1280` passes → 390 px phone renders at 1280 CSS px and 44 px pads shrink below ~14 px; removing `muted` blocks autoplay while the gate stays green.
  - **Fix:** Require both viewport substrings; regex the `<video>` tag for `autoplay`+`muted` and assert the reduced-motion branch; add CORP/immutable-header assertions; factor disallow/count checks out of the `else` branch. Add an xvfb leg at 390×844 asserting pad/HUD non-overlap.
- Verified shipped: root `index.pck` contains `Evan_Skeleton.glb`, `.godot/imported/Evan_Skeleton.glb-*.scn`, and compiled `.gdc` for all four Evan scripts; `web_hygiene OK`; size 4,277,536 bytes < 4.5 MiB guard.

### Lens 10 — Cognitive Load & AI Maintainability

- **[P3-5] Duplicated vehicle-resolution pipeline** — `godot/src/KiepieBike.gd:L282-L301` vs `:L304-L327`
  - **Root Cause:** `_assign_vehicle` and `refresh_vehicle_assignment` each reimplement `user_id → lookup_id → roster_keys → resolve_for_player`.
  - **Trigger:** A fix applied to one path (e.g. P3-6) leaves spawn and post-roster vehicles diverging; cannon re-`setup()` then points at stale muzzle anchors.
  - **Fix:** Extract one `_resolve_assigned_vehicle()` returning id + lookup id; keep swap/re-setup logic only in `refresh_vehicle_assignment`.
- **[P3-8]** ~680-line builder with nested closures and a dead `EXCLUDE` constant (see Lens 8). Frozen contracts (NLA clip names, landmark names, plain GLB) should be documented as such at the top of the builder rather than rediscovered.

## 3. Existing Test Suite Comparison & Mutation Truth Table

- **Test-to-Code File Ratio:** `3` focused gates / `13` implementation files (`0.23`) — plus 28 legacy gates that do not exercise Evan behaviour.
- **Estimated Mutation Kill Score ($M_{\text{kill}}$):** **`34%`** (`34/100` mental mutants; basis: ~42 hard equality/value assertions incl. 52 bones, 5 menu items, cooldowns `0.22`/`0.10`, damage `37`/`55`/`105`, radii `4.5`/`7.5`, `top_speed_cap == 36`; ~13 negative/boundary signals incl. NaN steer cap, forged-id rejection, owner-skip, out-of-zone, sub-token; 0 mock-heavy files but 2 stub-heavy gate sections; 4 unpaired critical modules — remote reconstruction, cooldown enforcement, projectile movement, impact→detonate).
- Constraint: 31/31 green is credible for **contract/value locking**; it is not evidence of behavioural, shipped-artifact, or platform assurance.

| Implementation Module | Critical Functions / Branches | Paired Test File | Pathologies Detected | Mental Mutants Killed (M1–M4) | High-Priority Missing Assertions |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `DevilHandStrike.gd` + `CombatAoe.apply_lethal_blast` | `setup()`, `_detonate()`, lethal resolver | `verify_evan_weapons.gd` | Result-Only (strong call-count check) | `3/4` | Radius boundary at exactly 7.5 m; impact-driven detonation; non-finite radius |
| `BoomerangGuitar.gd` | return steering, `_damage_bike()`, `_finish()` | `verify_evan_weapons.gd` | No-Throw Theater (`saw_arrest` OR), Happy-Path | `1/4` | `saw_return` mandatory; scenery hit must not emit `hit`; cooldown enforcement |
| `SoundWaveProjectile.gd` | `_rearm_wave()`, `_integrate`, hit dispatch | `verify_evan_weapons.gd` | Mock-Mirror (velocity set by `setup()`), Zero/Empty blind | `1/4` | Position advances over N ticks; zero-direction finite velocity; `on_hit` token/damage |
| `EvanVisual.gd` | `_physics_process()` remote estimator, `trigger_recoil()` | `verify_evan.gd` | Existence-Only | `0/4` | Finite/bounded speed after 120 frames; clip has tracks + length; recoil mutates state |
| `ArenaNet.gd` remote weapon reconstruction | `_on_broadcast("shot")`, `_spawn_remote_shot()` | NONE | N/A (untested) | `0/4` | Rogue id rejected; Evan profile → boomerang/devil-hand visuals; token dedup |
| `NetworkedBike.gd` | `_apply_roster_vehicle()`, `apply_state()` | `verify_multiplayer.gd` (generic) | N/A for Evan | `0/4` | Load-failure retry; Evan GLB swap; `n < 0` rejection |
| `deploy_web.sh` / `check_web_hygiene.py` | sync, hash check, policy checks | `web_hygiene` gate | Implementation-Coupled string checks | `0/4` | `index.pck` content grep; SW precache existence; all bundle hashes |

### Why Existing Tests Missed Discovered P0/P1 Defects

- **P1-1 (shot trust boundary):** Gates run with `KIEPIE_MOCK_BACKEND=1`, so no forged-packet path is ever synthesized; `verify_multiplayer.gd` only checks legitimate proxy spawning, not adversarial `id` values.
- **P1-2 (vacuous gates):** `verdict()` only checks exit code, `FAIL`, and `SCRIPT ERROR`; a gate printing nothing passes. `verify_evan.gd`'s clip/recoil checks are `has_animation` / `has_method` proxies, so gutted implementations still pass.
- **P1-3 (deploy sync):** `web_hygiene` is a policy-file checker; it never reads `index.pck`, and the live curl compares only two files while the SW serves `index.pck` Cache-First.
- **P2-1 (`lerpf` divergence):** No gate constructs a remote Evan proxy and advances it on a physics clock; the local vehicle path is exercised instead.

### Minimal Viable Test Harness (MVTH) Specifications

1. **Tier 0 (pure invariants, zero mocks):** `EvanVisual` speed estimator as a pure step function — table-drive `[0, 0.5, 8.0, NaN]` displacements × `[1/60, 1/30]` deltas; assert `is_finite` and `<= 60` after 120 steps. Radius boundary helper asserted at `r−ε / r / r+ε`.
2. **Tier 1 (state machine):** Remote proxy harness with `Match.players` populated, `id` forged and legitimate; assert forged `shot` dropped, Evan profile → `BoomerangGuitar`/`DevilHandStrike`/`SoundWaveProjectile`, and token dedup across two identical packets.
3. **Tier 2 (shipped artifact):** After export, `strings index.pck | grep -F 'res://src/game/...'` for all four Evan scripts + GLB; parse SW precache array and assert each file exists; assert no `.env`/`gdUnit4` leaked.
4. **Tier 3 (harness self-defence):** Every gate prints `GATE <name> OK n=<k>`; `verdict()` requires the sentinel plus `k >= floor`; broaden error regex to `(SCRIPT ERROR|Parse Error|^\s*ERROR:)`.

## 4. Surgical Refactoring Blueprints (Zero-Mutation Drafts)

### Refactor R1 — Clamp the remote speed estimator (P2-1)

- **Target Scope:** `godot/src/game/EvanVisual.gd:L80-L90`
- **Engineering ROI:** Converts a guaranteed ±inf/NaN divergence within ~6 frames into bounded, frame-rate-independent smoothing; restores remote Evan's strum/headbang animations.

```gdscript
# current
_remote_speed = lerpf(_remote_speed,
        Vector3(disp.x, 0.0, disp.z).length() / maxf(delta, 0.001), 9.0)

# blueprint
var target := Vector3(disp.x, 0.0, disp.z).length() / maxf(delta, 0.001)
var t := 1.0 - exp(-9.0 * minf(delta, 0.05))
_remote_speed = clampf(lerpf(_remote_speed, target, t), 0.0, 60.0)
```

### Refactor R2 — Make the gate harness anti-vacuous (P1-2) and artifact-aware (P1-3)

- **Target Scope:** `godot/tools/run_gates.sh:L32-L44`; `godot/tools/deploy_web.sh:L96`, `:L114-L121`
- **Engineering ROI:** A gutted gate can no longer report green; a stale/missing GLB or mismatched WASM/PCK pair fails before push instead of in the browser.

```bash
# verdict(): require sentinel + minimum assertion count
grep -qF "GATE $name OK" "$log" || { FAILED+=("$name"); return; }
n="$(grep -c '^PASS ' "$log")"
[ "$n" -ge 3 ] || { FAILED+=("$name"); return; }

# deploy sync: atomic per-file replace with rollback snapshot
for f in "$ROOT/web/"*; do
  b="$(basename "$f")"; cp -p "$ROOT/$b" "$ROOT/.$b.predeploy" 2>/dev/null || true
  cp "$f" "$ROOT/.$b.tmp" && mv -f "$ROOT/.$b.tmp" "$ROOT/$b"
done
```

### Refactor R3 — Bind the shot trust boundary to feasible Talo primitives (P1-1)

- **Target Scope:** `godot/src/game/ArenaNet.gd:L157-L158`, `:L324-L327`
- **Engineering ROI:** Removes the N× strike amplification and the invalid-kind rate-limit starvation without changing `PROTOCOL_VERSION`.

```gdscript
"shot":
    var id := str(p.get("id", ""))
    if id == "" or id == Supabase.user_id: return
    if Match != null and not Match.players.is_empty() and not Match.players.has(id): return
    var kind := str(p.get("w", "primary"))
    if kind != "primary" and kind != "rocket" and kind != "meteor": return
    var tok := str(p.get("token", ""))
    if tok != "" and not _seen_shot_tokens.add_bounded(tok): return
    _spawn_remote_shot(p)
```

### Refactor R4 — Explicit victim authority in the lethal resolver (P2-2)

- **Target Scope:** `godot/src/game/CombatAoe.gd:L126-L138`
- **Engineering ROI:** Converts an implicit group-composition assumption into an enforced invariant; matches the already-fail-closed boomerang guard.

```gdscript
if local_uid == "" or target_id == "" or target_id != local_uid:
    continue   # remote proxies are never mutated from the shooter's client
```

## 5. Phased Execution Roadmap & Scoped Agent Prompts

1. **Phase 1 — Containment & safety lock:** R1 (divergence), R3 (shot gate), R4 (lethal authority), `*victim` fail-closed parity in `apply_blast`; MVTH Tier 1/2. All fixes are behaviour-preserving for legitimate play.
2. **Phase 2 — Frame-budget, concurrency & state hardening:** R2 (anti-vacuous harness + atomic deploy), pooled-slot explicit reset, spawn-slot re-sync, fail-open model load retry, radius clamping, tick guard `n < 0` rejection, radius `distance_squared_to`.
3. **Phase 3 — Structural de-vibing:** extract the duplicated vehicle-resolution pipeline, derive the identifier vocabularies from one source, split the Blender builder into staged functions with atomic artifact writes, close the Web hygiene under-specification.

### Copy-Paste Surgical Prompts for Coding Agents

> **Prompt [P1-1] (`godot/src/game/ArenaNet.gd`):** "Strictly scope edits to `ArenaNet.gd:L157-L158,L324-L327` and `tools/verify_multiplayer.gd`. Add roster-membership gating, kind validation before the rate-log append, bounded token dedup and a global strike cap to the `shot` branch. Keep wire kinds `primary`/`rocket`/`meteor` and `PROTOCOL_VERSION = 3`. Add a gate asserting a forged `id` cannot spawn a boomerang or devil hand, and that Evan's profile still reconstructs all three weapons. Run `bash godot/tools/run_gates.sh` to green."

> **Prompt [P2-1] (`godot/src/game/EvanVisual.gd`):** "Strictly scope edits to `EvanVisual.gd:L80-L90` and `tools/verify_evan.gd`. Replace the unclamped `lerpf(..., 9.0)` with delta-normalised exponential smoothing clamped to `[0, 60]`. Add a gate that advances a remote Evan proxy 120 physics frames with a 0.5 m per-frame displacement and asserts `_remote_speed` stays finite and bounded. No physics/scoring changes."

> **Prompt [P1-2] (`godot/tools/run_gates.sh`):** "Strictly scope edits to `run_gates.sh:L32-L44` and the 31 gate scripts. Introduce a `GATE <name> OK n=<k>` sentinel, require `k >= 3` and a `^PASS ` count in `verdict()`, and broaden the error regex. Prove the harness by mechanically gutting one gate body in scratch and confirming the suite goes red, then restore."

> **Prompt [P2-2] (`godot/src/game/CombatAoe.gd`):** "Strictly scope edits to `CombatAoe.gd:L126-L138` and `:L59`. Add an explicit fail-closed local-victim guard mirroring `BoomerangGuitar.gd:321-327` to both blast resolvers. Extend `verify_evan_weapons.gd` so a remote-proxy stub with `take_lethal_hit` is asserted not to be mutated. Keep the `':v<victim>'` sub-token contract."

## 6. Zero-Mutation Verification & Provenance

| Check | Before | After | Result |
| :--- | :--- | :--- | :--- |
| `git status --porcelain` | empty | empty (before report commit) | PASS |
| `git rev-parse HEAD` | `cedd755a0050af6e9c1294bd3c8830979ef672c5` | unchanged | PASS |
| `preflight_telemetry.py godot` `tree_integrity_sha256` | `3bbb7140833572dda56268947ca6db2cbfd6e8420c2a700d03f00bf` | identical | PASS |
| Report artifact | n/a | `docs/audits/kiepie-quad-surgical-audit-evan-2026-11-25.md` | docs-only commit, no source mutation |

Audit method: deterministic AST telemetry (346 files / 42,663 effective LOC in `godot/`), four disjoint read-only lens batches (≤4 files each), independent re-verification of every P1/P2 claim against source lines, deterministic scoring via `score_audit.py`, and direct binary inspection of `Evan_Skeleton.glb` and root `index.pck`. No gates were executed and no repository source was modified during Passes 1–4.
