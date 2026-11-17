# Surgical Audit Report: Kiepie Quad (Kiepie Bike / Kiepie Quad)

| Audit Metadata | Specification |
| :--- | :--- |
| **Audit Date** | 2026-11-17 |
| **Audited Scope** | `godot/src` (29 files, 5,186 eff LOC), `godot/tools` (31 files, 3,726 eff LOC), `src/` Blender pipeline (8 files, 1,928 eff LOC), `godot/scenes`, `godot/project.godot`, `godot/export_presets.cfg` — **10,840 effective LOC** plus scene/config. Excluded: `addons/` (vendored GdUnit4/Talo), `supabase/` (retired, documented), `web/` (separate public repo, 15 files, no application logic authored here), `godot/reports/` (regenerable QA artifacts), `.git/` |
| **Tech Stack & Runtime** | Godot 4.3 (GL Compatibility), GDScript, headless+xvfb gate harness; Blender 5.3 bpy pipeline; Web export (single-thread WASM) on Vercel (`kiepie-quad-web`); backend = Talo v1 channels/props (client-authoritative scoring, documented by design) |
| **Audited Refs** | Source repo `TeacherEvan/kiepie-quad` @ HEAD **0dbfd44** (`main` ≡ `origin/main`); web repo @ `7647908` (deployed live, HTTP 200 verified 2026-11-17 ~18:30) |
| **Working Tree** | Audit ran against the **working tree**, which carried the user's uncommitted in-flight pass (14 source files + scenes regenerated 22:15 + `report_50..52`). See §9 Attribution & Drift. |
| **Pre/Post Audit Integrity** | Baseline extracted to `/tmp/opencode/audit/baseline/` before any inspection; telemetry `tree_integrity_sha256` (scan-time WT): `godot/src a086ea0b…`, `godot/tools e3ddb0ed…`, `src 8f92169f…`, `godot (incl addons) 363afde5…`. **Audit performed zero mutations** (all subagents + main session read-only; no gates executed by the audit — gate execution is mutation: it rewrites `user://settings.cfg` and `godot/reports/`). WT drifted **underneath** the audit from the user's own concurrent session (22:05 → 22:2x); §9 documents the window and which files moved. This report says only "the tree the auditors looked at", not a reproducible HEAD. |
| **Deterministic Health Score** | **\(S_{health} = 0 / 100\) — saturated, see caveat.** \(D_{raw} = 1,126\) (\(9×18 + 55×8 + 131×3 + 131×1\)); \(P_{test} ≈ 6\) (\(M_{kill} ≈ 60\%\)); \(LOP = 10,840\) → \(\sqrt{1000/10840} = 0.304\); \(100 − 1,126 × 0.304 − 6 \le 0\). Formula saturates at ~180 findings; it does not distinguish "149 hygiene nits" from "10 live bugs". **Calibrated read: HIGH risk, not CRITICAL** — no P0s, no crash/auth/RCE finding; the dominant failure domains are silent-degradation and trust-boundary gaps in the net layer. |
| **Vibe-Debt Risk Level (formula)** | **CRITICAL** (\(N_{P0}=0\), but \(D_{raw}\) any config ⇒ 0) — reported per skill honestly, with the calibrated interpretation above. |
| **Findings** | **P0: 0 · P1: 9 · P2: 55 · P3: 131 — 195 total** (no P0) |

## 1. Executive Architecture & Vibe-Debt Triage

The Kiepie Quad stack is a hobbyist-scale, single-threaded multiplayer 3D racing/combat game whose engineering quality is **above typical hobby grade and below production grade**. Positive foundations are real: single source of truth for vehicle scale (`qb_spec.py`), a working 21-gate offline suite with genuine multi-touch coverage (42 assertions, the strongest artifact in the repo), documented constraints in AGENTS.md, deploy tooling with live HTTP verification, and — newly verified in this audit — a committed environment where `controls/steer_sensitivity`, `dodge_size`, `touch_force`, `fire_size` are all **live** end-to-end. However, the same audit found: (1) an **end-to-end trust-boundary chain in the net layer** — any lobby member can forge `join` roster rows with `score: 9999`, erase the match leader, spawn killable-by-proxy projectiles at a victim's coordinates, and auto-bank kills nobody scored, and TaloBackend accepts any non-empty token as kill proof (client-authoritative by design, but even its own mock enforces issuance — the live path does not); (2) **the practice-mode contract is not delivered** — `take_damage()` still gates on `Match.is_playing()` with no practice bypass, so TestRide drums/cannons deal zero damage and practice death/respawn is unreachable, contradicting 0dbfd44's commit message and AGENTS.md; (3) **gate theatre** — several locks are one-sided or vacuous, the suite wipes the developer's real `user://settings.cfg`, and standalone gate invocations (the exact commands AGENTS.md gives) connect to the *live* Talo backend, because `KIEPIE_MOCK_BACKEND=1` is only exported by `run_gates.sh`; and (4) **silent failure everywhere** — `except Exception: pass` in the Blender pipeline, unobserved `ConfigFile.save()` failures, latched `_starting`, and an AGENTS-documented QA invariant (`minZ == 0`, `non_manifold == 0`, rim/tyre ≈ 0.55) that no `src/` script ever enforces. If two things are read from this report, read the nine **P1**s (§2-L6 and the Pass-3 table) and the [WT] defect cluster (§3), not the 131 P3s hygiene line items.

| Severity Tier | Count | Deduction Weight | Primary Failure Domains |
| :--- | :--- | :--- | :--- |
| **P0 — Critical** | **0** | −18 pts ea | — none found (no crash/auth/RCE/data-loss class defect) |
| **P1 — High** | **9** | −8 pts ea | Net trust boundary (join/leave/shot/kill forgery, token non-issuance): `TaloBackend.gd:450-465,87-88,488`, `ArenaNet.gd:69-83,142-167`; practice-mode contradiction: `CombatController.gd:124`; attribution spoof: `CombatController.gd:230`; gates hitting production + wiping dev config: `verify_match_rules.gd:28`, `verify_settings.gd:36-44`, `verify_audit_regressions.gd:38-51` |
| **P2 — Medium** | **55** | −3 pts ea | Silent-degrade Blender passes (F-001-01…08); settings persistence (non-atomic save, unclamped values, boot re-apply gaps F-AUD-01…07); props PUT ordering split-brain (F-01-03); reconnect w/o resync (F-01-04); host-leave cascade (F-01-05); mock≈/superset of live contract (F-03-01/02/04); pickup consumed-when-dead (F-PICK-01); single-muzzle triple-fire (F-CANN-01); fire-after-free on freed nodes (F-CANN-02); dead `video.shadows` + false-confidence gate (F-AUD-05); off-screen health bars on narrow/short phones (F-UI-01, WT); gate gaps leaking scar cap/dodge spin/respawn deadline (F-TST-04/05/06); reports/tools shipping in the public pck (F-BUILD-01/09) |
| **P3 — Low** | **131** | −1 pt ea | Dead code (`project hit` signal, `_spawn_set`, `CROSSHAIR`, `_frame`, `_Chip/_style_button`); zero guards (normals/directions); O(n²) `_cap_group`; magic constants; no debounce on resize/slider/save; cosmetic layering (FPS↔radar, heat hues, sign overdraw) |

### High-Risk File Telemetry Hotspots

| File Path | Effective LOC | Est. Branch Density | Silent Catches / Time-Sync Risks | Primary Vibe-Debt Signature |
| :--- | :--- | :--- | :--- | :--- |
| `godot/tools/build_arena.gd` (WT) | ~937 | high | builders not run in CI | God builder; duplicated touch cluster |
| `godot/src/game/VfxFactory.gd` | 878 | high | 0 catches, 2× light-budget gap | God file, zero pooling despite doc-contract |
| `godot/tools/build_testride.gd` (WT) | ~723 | high | id churn per rebuild | God builder; dead helpers (WT) |
| `godot/src/ui/MatchHud.gd` (WT) | 562 | high | resize handlers no-debounce | God file: 10 subsystems, 2 layout engines |
| `godot/src/net/TaloBackend.gd` | 541 | high | mocked-out wire path | God object: auth+props+scorer+router |
| `godot/src/TouchControls.gd` (WT) | 383 | high | co-hold global release bug | Shared global actions vs layer-local holds |
| `godot/src/KiepieBike.gd` | 298 | med | none | Dual-owner ExhaustFlames flag (F-CC-04) |
| `godot/src/net/MatchState.gd` | 265 | med | time_up busy-loop | Re-emit on echo; untyped casts |
| `src/qb_core.py` / `qb_body.py` | ~600 combined | high | `except: pass` ×4 | God geometry kernels |
| `godot/src/Hud.gd` (WT) | 147 | med | — | Divergent sibling of MatchHud |

## 2. The 10-Principal-Engineer Deep Audit

Recency legend: **[WT]** = introduced by (or located inside) the user's uncommitted in-flight pass (current working tree) · **[HEAD]** = present in committed `0dbfd44` · **[WT∘HEAD]** = pre-existing, exposed/aggravated by the WT pass. Every line number cites the working tree as read; files that drifted mid-audit are flagged in §9.

### Lens 1 — Systems Architecture (God Objects, Split-Brain State, Duplication)

- **[P1-adjacent→P2] F-CC-01** [WT∘HEAD] `CombatController.gd:124` — `take_damage()` gates on `Match.is_playing()` with no `practice_mode` bypass while `_physics_process()` does; **practice cannons ship but nothing can hurt you in TestRide** — the 0dbfd44 commitment ("local death/respawn flow works") and `verify_practice.gd` (which never asserts damage) both pass regardless. Fix: `if not alive or (not practice_mode and not Match.is_playing()): return` + assert in `verify_practice.gd`. **Highest-confidence, lowest-effort P1: 3 lines. Runtime-verified 2026-11-17** — practice `take_damage(30)` on the TestRide bike: health 100.0→100.0; with lobby `playing`: 100.0→70.0 (Appendix A).
- **[P2] F-01-15** [HEAD] `TaloBackend.gd:20-21,231-247` + `MatchState.gd:13-14` — split-brain mirrored `lobby/roster/players` in two autoloads, bridged only by `postgres_change`; `_load_state()` mutates without emitting; `_apply_props()` not awaited before `_send("state")`; missed messages unreconciled ⇒ late joiners and peers silently diverge. Fix: single source of truth (MatchState) or mandatory post-write re-fetch + emit on load/reconnect.
- **[P2] F-BUILD-02** [WT∘HEAD] `build_testride.gd:408-520` vs `build_arena.gd:462-580` — touch overlay duplicated with two style vocabularies; WT mirrored edits **already drifting**; HUD forked (`Hud.gd` vs `MatchHud.gd`). Fix: shared parameterized `_touch_layout.gd`; adopt one heat-gauge contract (`UI.HEAT_LOCKED`).
- **[P2] F-01-03** [HEAD] `TaloBackend.gd:249-280` — `_apply_props` is a fire-and-forget full-snapshot PUT; the generation guard only suppresses the local refresh — the stale PUT is already on the wire and can clobber the newer roster (kill+join race; Talo `continuity_manager` replays ≥500s later). Fix: serialize writes (await prior or dirty-flag single writer); on failure re-fetch + re-merge, never replay stale body.
- **[P3] F-01-16** [HEAD] `TaloBackend.gd:1-541` — God Node: auth+channel+props+scorer+router interleaved; every change cross-cuts. Fix (blueprint): split into `TaloAuth`, `TaloChannelProps`, `TaloScorer`, `TaloSocketRouter` behind the documented facade.
- **[P2] F-01-05** [HEAD] `TaloBackend.gd:172,296-298` — channel created `autoCleanup=true`; host tab-close ⇒ server deletes channel; **no host re-election anywhere** ⇒ all peers freeze mid-match with zero diagnostics. Fix: `autoCleanup=false` + elect lowest `user_id` (or `owner_alias_id` reassign) or emit host_left.
- **[P3] F-UI-07** [HEAD] `MatchHud.gd:1-562` — God file: combat feedback, scoreboard, kill-feed, banner, respawn, result panel, FPS, runtime-created vignette/hitmarker, inner `RadarControl` class, its own `_relayout` engine; "adding a widget = re-verify 6 subsystems". Fix: extract `RadarControl.gd`, `KillFeed.gd`, pure `RelayoutLayout.gd`; MatchHud = signal wiring only.
- **[P2] F-UI-08** [HEAD] `MainMenu.gd:24,56-63,99,113,127` — `_busy` only ever set `false`; **double-click CREATE/JOIN ⇒ two scene changes ⇒ two lobbies, first orphaned on the backend**. Fix: `_set_busy(true)` in the three entry paths before transition.
- **[P3] F-CC-04** [HEAD] `CombatController.gd:106-109` vs `KiepieBike.gd:170-171` — two writers own `ExhaustFlames.emitting`; bike wins by a frame ⇒ overdrive flame cue never reads. Fix: gate on `KiepieBike.overdrive_active` or dedicated cue.
- **[P3] F-FUEL-01** [WT] `FuelDrum.gd:111-129` — respawned drum stays in group `hazard` while invisible; a chain-ignite in the same 0.18s batch can re-detonate it. Fix: `remove_from_group("hazard")` on ignite, re-add on respawn (see race note in §5).
- **[P3] F-CANN-06** [HEAD] `SideCannons.gd:50-53` — `setup()` appends `MuzzleFallback` pairs without removing old ones. Fix: purge fallbacks first.
- **[P3] F-DEST-01** [HEAD] `DestructibleBuilding.gd:57-60` — smash detection accepts only `VehicleBody3D`/`RigidBody3D`; remote proxies are kinematic `StaticBody3D` ⇒ **a remote player smashing a building does nothing and replicates nothing**; HUD smash counter diverges from physics reality. Fix (cross-file): host-authoritative smash RPC or velocity-sync'd proxies.

### Lens 2 — Frame Budget & Hot Paths

- **[P2] F-VFX-01** [HEAD] `VfxFactory.gd:417-421,586-590` — point-light budget enforced **only** on `impact()`; `explosion()` (26 energy, 10m range) and `muzzle_flash()` uncounted ⇒ chained drum explosions + sustained fire blow gl_compatibility's forward-light limit (shader recompile/stalls). Fix: route all one-shot lights through the capped helper with a reserved explosion sub-budget.
- **[P3] F-PROJ-02** [HEAD] `Projectile.gd:138` — `PhysicsRayQueryParameters3D.create()` per physics step per projectile (~240 allocs/s in a full-auto burst). Fix: hoist, mutate from/to.
- **[P2→P3] F-DEST-02** [HEAD] `DestructibleBuilding.gd:88,99-127` — 14 unique `RigidBody3D` + materials + `continuous_cd` per smash, on layer 1 vs the bike; web frame-spike + unrealistic launch. Fix: shared mesh/material cache, debris on a dedicated layer, cap concurrent bodies.
- **[P3] F-DEST-03** [HEAD] `DestructibleBuilding.gd:144-155` — 7 buildings × 60Hz `get_material()` + autoload lookup for a cosmetic beacon pulse. Fix: 10Hz throttle or Tween.
- **[P3] F-VFX-02** [HEAD] `VfxFactory.gd:361-374` — `_cap_group()` is O(n²) `pop_front()` + per-call group-query Array. Fix: index-range truncation.
- **[P3] F-VFX-04** [HEAD] `VfxFactory.gd:205-275,232-275` — "Pooled-by-convention" contract violated: fresh `StandardMaterial3D` + `QuadMesh` per effect, per spawn; bytes×60×burst on Web. Fix: static keyed material/mesh cache; clone only per-instance α-tweens.
- **[P3] F-FUEL-02** [HEAD∘WT] `FuelDrum.gd:105-109` — chain-ignite allocates a `SceneTreeTimer` + closure per hazard even when already ignited. Fix: pre-check visibility/ignited.
- **[P3] F-PICK-02** [HEAD] `Pickup.gd:79-88` — `_process` rotates pickups every frame even while collected/hidden; `_t` grows unbounded. Fix: `set_process(false)` on collect; wrap `_t`.
- **[P3] F-05-06** [HEAD] `ArenaNet.gd:29-36` — `_send_accum` unbounded; under hitstop (time_scale=0.28) 15Hz broadcast stretches ×3.6; after a hitch, burst-sends pile up. Fix: `minf` cap / tick-based accumulator.
- **[P3] F-UI-05** [WT] `MatchHud.gd:175-178,524-534` — `RadarControl` invisible on short/narrow but still `queue_redraw()` + group scan every 0.1s. Fix: early-return on `is_visible_in_tree()`.
- **[P3] F-UI-04** [WT] `MatchHud.gd:84`, `LobbyMenu.gd:55`, `SettingsMenu.gd:19`, `MainMenu.gd:29` — raw `size_changed`, no debounce; Web drag-resize ⇒ layout storms on the same frame budget as the 3D sim. Fix: 0.1s one-shot coalescing helper in `UiTheme.gd`.
- **[P3] F-UI-10 / F-UI-11** [HEAD] `SettingsMenu.gd:75-86,178-180` (×`Settings.gd:141-150`) — per-slider-tick un-debounced full `ConfigFile.save()` **and** unconditional `_refresh_all()` (~30 writes); the pair is O(widgets × disk) per drag. Fix: jointly debounce; target per-key refresh.
- **[P3] F-PROJ-01** [HEAD] `Projectile.gd:29,78,92` — zero direction ⇒ zero-velocity immortal projectile, `Basis.looking_at(ZERO)` degenerate. Fix: length-squared early-out.
- **[P3] F-VFX-08** [HEAD] `VfxFactory.gd:235` — `maxi(2, amount × _q())` floor defeats quality 0 ⇒ "off" setting still spawns 2 motes per burst. Fix: `_q()<=0` early-out or document hero floor.

### Lens 3 — Math, Physics & Determinism

- **[P3] F-001-05** [HEAD] `qb_engine.py:189-198` — CVT belt cross-section "normal" built from raw tangent pair `(Δz, Δx)`, never crossed/normalized; walls shear on wrap arcs (watertight, so QA passes — visual banding only). Fix: proper perpendicular from `hypot` with guard.
- **[P3] F-VFX-03 / F-VFX-06 / F-PROJ-04** [HEAD] — zero-vector `normalized()` surfaces: `_plane_basis` (`:527-549`), `casing()` eject_dir (`:458`), checked Variant→Vector3 cast in `Projectile.gd:166`. File's own idiom (`length_squared() > 1e-4`) applied everywhere **except** these three. Fix: same guard, three sites.
- **[P3] F-05-03** [HEAD] `ArenaNet.gd:146-157` — `1e999` → `inf` survives the `< 1e-8` guard; no upper bound on origin/dir; JSON strings → per-component engine errors on every peer, forever. Fix: `is_finite` whitelist + clamp `d` ∈ [0.1, 100].
- **[P3] F-FUEL-03** [HEAD] `FuelDrum.gd:84` — blast distance measured from bike *origin*; bike origin outside radius + fenders inside ⇒ explosion VFX with zero damage on the player standing inside it. Fix: subtract ~1.0 m bike half-length.
- **[P3] F-02-05 / F-01-14** [HEAD] — ISO parse passes tz flag into the documented `weekday` parameter (4.3 source verified: pure UTC arithmetic, **no timezone bug**); timezone-naive-by-contract, misdocumented, pays weekday cost per kill. Fix: `get_unix_time_from_datetime_string`.
- **[P3] F-02-06** [HEAD] `MatchState.gd:45,150-163` — wall-clock match/respawn timing (user-settable system clock). Note.
- **Verified correct**: dodge spin/lift signs (Q ⇒ +X leap/cartwheel); smoothstep deadzone curve; anti-rollover damps roll/pitch only; spawn pick; heat decay; respawn order (visible→collider→`_ignited`); GLB `export_yup=True` end-to-end (−Y-forward model ↔ +Z Godot); ISO math. **The respawn_at-as-deadline regression from the prior cycle is RESOLVED at all three sites (verified — §7).**

### Lens 4 — Concurrency, Async & Ordering

- **[P2] F-CANN-02** [HEAD] `SideCannons.gd:127-149` — `await Match.issue_shot()` then dereferences `owner_node.global_transform`, `muzzle.global_position`, `fx_parent`: any scene change / arena teardown across the yield ⇒ frees ⇒ silent lost shot, **heat/cooldown/SFX/VFX already consumed**. Fix: capture transforms pre-await; post-await `is_instance_valid` guards.
- **[P2] F-01-04** [HEAD] `TaloBackend.gd:53-63,411-414` — reconnect = constant 2.0 s retry forever, no backoff/jitter, no re-join/re-sync, `_send` on half-open socket fails silently ⇒ permanent roster divergence after one Wi-Fi drop. Fix: capped exp backoff + jitter; after reconnect `find(channel)` + `_load_state()` + resync request + `connection_state("stalled")` outbound gate.
- **[P2] F-02-01** [HEAD] `MatchState.gd:36-54` — on `time_up` RPC failure, `_time_up_called=false` ⇒ **immediate 60Hz retry**; with Mock (no `time_up` RPC) an offline `match_seconds > 0` match busy-loops forever, `settings()` deep-copy per frame. Fix: backoff + cap + surfaced error.
- **[P2] F-06-01** [HEAD] `LobbyService.gd:35-59` — no busy latch; double-tap JOIN ⇒ N channels joined, only the last recorded; ghost members hold slots forever (autoCleanup can't fire). Fix: `_busy` latch at entry, cleared in all terminal paths.
- **[P2] F-06-02** [HEAD] `LobbyService.gd:62-70` — `leave()` writes `Match.lobby = {}` / `players.clear()` directly ⇒ no signals emit; HUD keeps stale banners; `MatchState._process` keeps ticking a match that no longer exists. Fix: `Match.clear()` with both signals + timer reset.
- **[P2] F-01-01** [HEAD] `TaloBackend.gd:450-465` — **join/leave socket branches have no sender binding** (ready_request/kill_request do) ⇒ any member forges a `score: 9999` roster row for anyone; `Leave` erases the leader; auto-persisted by the host on next `_apply_props()`. Fix: `uid == sender_id` guard + roster cap + channel-id filter (none exists — **all channels' traffic is processed**).
- **[P3] F-FUEL-01 / F-FUEL-05** [WT] — respawn-window ordering bug: invisible drum group membership, `_ignited=false` set **before** collider re-enable ⇒ mid-respawn invisible drum can still be chain-detonated. Fix: reorder to visible→collider→`_ignited` last (+ F-FUEL-02 pre-check).
- **[P2] F-PICK-01** [HEAD] `Pickup.gd:95-99,114-130` — `_collect()` unconditionals: handler `apply_pickup()` early-returns when dead ⇒ pickup consumed with zero effect (dead rider, overlapping Area3D). Fix: return `bool`; collect only on success.
- **[P3] F-05-04 / F-05-05 / F-02-03** [HEAD] — respawn-hide timer races; `_streak` persists across matches into TestRide; `self_respawn_at` re-emits per roster echo, string never cleared. Fix per entry.
- **[P3] F-CANN-03** [HEAD] `SideCannons.gd:144-149` — **one trigger pull, one token, two `"shot"` broadcasts**; second victim's `register_kill` hits `token_consumed` ⇒ a legitimate 2-kill registers 1. Design choice needs an owner decision (per-barrel token vs barrels-array payload vs accept-and-document), not silence.

### Lens 5 — Memory & Resource Lifecycle

- **[P2] F-CC-02** [HEAD] `CombatController.gd:158-160` — dead bike: `visible=false` + physics off but **collider & layer intact** ⇒ invisible wall for `respawn_delay`; unhittable rays grant free pass; remote proxies brake against a ghost. Fix: zero velocities + `collision_layer/mask=0` in `_die()`; restore in `_respawn()`.
- **[P2] F-CANN-05** [HEAD] `SideCannons.gd:111-113` — headless/no-current-scene ⇒ fresh `CannonFX` `Node3D` at `/root` **per shot, never freed** (gate-run-driven leak). Fix: cached member holder (mirror `CombatController._fx_parent` — but fix *that* too).
- **[P3] F-CC-09** [HEAD] `CombatController.gd:218-227` — `_fx_parent()` parks orphan `_fx_holder` at `/root` in the null-scene frame; never re-parented/freed; accumulates across scene transitions. Fix: Bike-relative holder or `_exit_tree()` free.
- **[P3] F-01-07** [HEAD] `TaloBackend.gd:277-278` — `_channel` replaced by `TaloChannel.new()` from the PUT response per kill/join/ready ⇒ orphan `TaloChannel`+props nodes. Fix: don't replace, or free the old.
- **[P3] F-CC-07** [HEAD] `CombatController.gd:161-166` — `_die()` connects one-shot `self_respawn_at → _on_server_respawn(){}`; practice/no-pg ⇒ connection never fires, handler is a no-op; pure placebo. Fix: delete both.
- **[P2] F-BUILD-01** [WT∘HEAD] `export_presets.cfg:8-9` — `export_filter="all_resources"` + **no `reports/*` exclusion**; QA HTML/PNG (≈1.1 MB source) enter the **public** pck; aggravated by WT's untracked `reports/49..52`; 4 MB abort may fire, or QA bundles ship. Fix: `exclude_filter += "reports/*, tools/*"` (see §4-R4).
- **[P3] F-BUILD-09** [HEAD] — `godot/tools/*.gd` (31 gate/builders) compile into the public pck. Same fix.
- **[P3] F-DEST-05** [HEAD] — 14 one-shot `SceneTreeTimer`s per smash, chunk-capturing. Fix: single cleanup pass.
- **[P3] F-001-14 / F-001-15** [HEAD] `qb_core.py:19-30,61-68,545-558,32-43` — purge misses `node_groups/worlds/fonts`; `images.load()` without `check_existing` ⇒ duplicate Image datablocks; `except RuntimeError: pass` on collection link ⇒ detached hierarchy. Fix as blueprint.
- **[P3] F-BUILD-05** [WT] — scene rebuilds re-mint ~1–2k ext/sub-resource IDs ⇒ semantic diffs hidden (a lost `practice_mode` would scroll past review). Fix: review `.tscn` via word-diff/structural tools, not eyeball.

### Lens 6 — Security & Trust Boundary

All of the below are **client-trust-boundary** defects in a client-authoritative architecture — the design is documented and out of scope for re-litigation, but its *minimum viable integrity* (don't let garbage through unchecked) is not met.

- **[P1] F-01-01** [HEAD] `TaloBackend.gd:450-465` — join/leave forgery (see Lens 4). Score/leaderboard integrity, one packet.
- **[P1] F-01-02** [HEAD] `TaloBackend.gd:87-88,340-359,488` — `issue_shot` returns `"%d-%d"` and **forgets it**; `_used_tokens` records only consumed; `_register_kill` binds proof to nothing. Guest sends `kill_request{killer:self, target:leader, token:"anything"}`; host scores repeatedly; `kill_target` reached at attacker's arbitrary pace. MockBackend enforces issuance TTL+cooldown+rate-limit; **TaloBackend enforces replay only** — the exact asymmetry class that produced the `respawn_at` incident. Fix: `_issued_tokens {token, killer, expires_at}`; require sender == issuer; TTL ~10 s; per-killer cooldown; expire `_used_tokens`.
- **[P1] F-05-01** [HEAD] `ArenaNet.gd:69-83` — **any broadcast with `killer == Supabase.user_id` triggers `register_kill(victim, token)`** — no local-hit match, no issuance, no rate limit. Attacker mints kills at firehouse rate; RAMPAGE SFX farm on innocent peers. Fix: `_my_recent_hits` matched ≤2 s; never more kills than hits.
- **[P1] F-05-02** [HEAD] `ArenaNet.gd:142-167` — remote `shot` ⇒ damaging projectile spawned at broadcast `o` with zero sender binding (TaloBackend forwards raw, `:500-501`), zero origin-vs-proxy distance check, zero rate/count cap. Attacker reads 15 Hz state echoes, fires once from inside the victim ⇒ near-guaranteed hit; then F-05-01 converts it to scored kills; + projectile-spam DoS. Fix: origin within ~2 m of sender's last position; per-sender 10/s; total cap; host-side filter ideal.
- **[P1] F-CC-06** [HEAD] `CombatController.gd:230,140-141,150-157` (+`ArenaNet.gd:142-163`) — victim relays `kill{killer: <unverified wire string>}`; killer auto-claims. Even honest victims attribute incorrectly under adversarial broadcast. Fix: refuse relay of unknown `attacker_id` (attribute to environment); kill RPC requires token→issuer binding (host-side).
- **[P2] F-01-13** [HEAD] `TaloBackend.gd:310-317` — `p_settings` non-Dictionary ⇒ `null.duplicate()` silent kill; no key whitelist (`match_seconds: 1e15` flows to props). Fix: type-check + whitelist + clamp + emit error.
- **[P3] F-01-10 / F-10-F-11** [HEAD] — `display_name`/`color` unvalidated on join (`substr` exists only on create path); 1 MB names ⇒ props bloat ⇒ permanent divergence. Fix: 32-char clamp + hex regex + roster cap.
- **[P3] F-UI-19** [HEAD] `LobbyMenu.gd:114-121,289-293` — room code unvalidated (arbitrary string into RPC). Fix: `^[A-Z0-9]{4,8}$`.
- **[P3] F-BUILD-11** [HEAD] `inject_talo_key.py:38-41` — prefix check can't distinguish game JWT from an arbitrary `eyJ…` pasted from elsewhere; if wrong, it ships in the public pck **permanently**. Fix: decode payload, assert issuer/claim once, keep `ta_` rejection.
- **Input hazards (no exploit path)**: `display_name()` → `Label` (no BBCode sink) — low risk, noted.
- **Verified**: admin key (`ta_…`) never referenced; `.env` gitignored, only `TALO_API_GAME` (by design) ships; `settings.cfg` gitignored/0600; `res://` carries no secrets; Talo game key in pck = the documented public token.
- **Kill feed**: `MatchHud.gd:387-426` interpolates peer `display_name` raw ⇒ layout inflation via embedded newlines (F-UI-17 [HEAD]) — no injection.

### Lens 7 — Reliability & Fault Tolerance

- **[P2] F-AUD-01** [HEAD] `Settings.gd:128-132` — `ConfigFile.save()` truncates `user://settings.cfg` **in place**; mid-write crash ⇒ zero-length cfg ⇒ every relaunch silently resets all player prefs. Fix: tmp + rename same-dir.
- **[P2] F-AUD-03** [HEAD] `Settings.gd:132` — save error discarded; on Web (user:// = IDBFS, private mode / quota / flush-on-crash) settings silently never persist. Fix: check `Error`, dirty flag + surface in Settings UI, flush on close-request.
- **[P2] F-TST-02** [HEAD] — **the offline gate `verify_settings.gd:36-44` persists then wipes `reset_defaults()` on the developer's real `user://settings.cfg`**. Fix: in-memory mutation + restore (`verify_vfx.gd:26-34` pattern).
- **[P2] F-TST-01** [HEAD] — **standalone gate invocations per AGENTS.md connect to the live backend** (Talo settings.cfg JWT is present in tree); backend-mutating RPCs (`join_auto/issue_shot/register_kill`) execute against production; the `use_mock` check at `verify_match_rules.gd:28` runs *after* the calls. Fix: pre-flight `if not use_mock: quit(2)` in every backend gate.
- **[P2] F-01-06** [HEAD] `TaloBackend.gd:184-202` — `join_auto`: `get_channels(0)` failure returns `[]` ⇒ falls through to **create a private orphan lobby**; hard-coded page 0 hides codes on page ≥ 1. Fix: distinguish list-fail vs no-match; never auto-create on failure; paginate.
- **[P3] F-AUD-02** [HEAD] `Settings.gd:124-125` — every boot rewrites cfg (unconditional `_save`); corrupt cfg silently replaced. Fix: save-on-diff; `.bad` quarantine.
- **[P2] F-AUD-04** [HEAD] `Settings.gd:172-179` — `apply_all()` never re-applies saved `resolution_scale` (and `glow`) at boot ⇒ Low preset silently dropped on relaunch. Fix: re-apply in `apply_all()`.
- **[P2] F-AUD-05** [HEAD] — `video.shadows` **dead key**; checkbox+presets promise GPU relief; suns hardcode `shadow_enabled=true` (`build_arena.gd:77-78`, `build_testride.gd:95-96`); gate asserts the bool flips, not an effect. Fix: wire or delete (see §7 doc-contract table).
- **[P2] F-001-01 / F-001-02 / F-001-04** [HEAD] `build_quad.py:265,205` `repair_and_verify.py:39-57` `qb_core.py:483-490` — failed modifiers discarded silently; engine hardcoded; `shade_auto_smooth` removed in Blender 4.1, swallowed ⇒ **flat-shaded shells ship unnoticed; minZ/non-manifold QA prints but never enforces**; all exported with exit 0. Fix: fail loud (`sys.exit(2)`), log-and-raise, assert in-pipeline.
- **[P3] F-001-13** [HEAD] `repair_and_verify.py:70` — unguarded `bike_meshes[0]`; `F-001-16` [HEAD] `build_quad.py:285-301` — missing Bike_Root ⇒ empty export; `F-001-03` EEVEE rename (5.x); `F-001-08` BIKE STATS measures the 30 m Ground plane instead of the bike.
- **[P2] F-CANN-04** [HEAD] `SideCannons.gd:95-113` — SFX/shake/heat/VFX spent **before** token returns; empty token ⇒ heat drained, no shot, no feedback. Fix: spend post-token or refund + `shot_failed`.
- **[P2] F-DEST-04** [HEAD] `DestructibleBuilding.gd:24-33` — non-box collider ⇒ `_body_size=Vector3.ONE`; warehouse trigger = 1.35 m pin; slam = nothing, no warning. Fix: push_warning or AABB fallback.
- **[P3] F-02-01 (fixed-note)** respawn_at — RESOLVED (see §7). **F-03-01/F-03-02** [HEAD] `MockBackend.gd:85-89,57-99` — mock never writes `started_at`, lacks `time_up` ⇒ timed matches cannot end offline; gates pass only because they run `match_seconds=0`. Fix: parity.

### Lens 8 — Type Systems & Contracts

- **[P2] F-AUD-07** [HEAD] `Settings.gd:185-203` — loaded values cast without validation: `resolution_scale=1e6` ⇒ `scaling_3d_scale` runaway (GPU hang); `bool("false")==true`; `master=100` ⇒ +40 dB. Fix: type+clamp vs `DEFAULTS`.
- **[P2] F-02-04 / F-01-13 / F-01-12** [HEAD] — unguarded `as Dictionary` across MatchState/TaloBackend/socket; `data:Dictionary` param vs addon's `null` payload ⇒ script error per malformed packet; hostile roster rows crash `scoreboard()`. Fix: `is` checks at all ingest points.
- **[P3] F-CC-10** [HEAD] `CombatController.gd:50-51` — `bike.set("player_id",…)`/`bike.get("engine_power")` untyped ⇒ silent no-op on rename ⇒ bike immovable + unattributable, zero diagnostics. Fix: `has_property` asserts or concrete cast.
- **[P3] F-FUEL-04** [HEAD] — drum blast path lacks practice bypass (F-CC-01 twin). See §2-L1.
- **[P3] F-CANN-01** [HEAD] `SideCannons.gd:46-53` — exactly-one-muzzle ⇒ **three** muzzle anchors ⇒ triple-fire, 1.5× damage, silent. Fix: per-side fallback. Runtime-verified 2026-11-17: losing `Muzzle_R`+`Cannon_Bore_R` yields 3 anchors (Appendix A).
- **[P3] F-PROJ-03** [HEAD] `Projectile.gd:6,153` — `signal hit` declared, zero consumers (Callable `on_hit` is the real path). Fix: delete or wire.
- **[P3] F-VFX-09** [HEAD] `VfxFactory.gd:231,250-265` — untyped `opts` Dictionary is the public API; typo'd keys fail silently. Fix: typed `VfxOpts` / const blocks.
- **[P3] F-DECOR-01** [HEAD] — `alpha=0.92` in opaque unshaded window material ⇒ misleading dead alpha. Fix: 1.0 or `TRANSPARENCY_ALPHA` deliberately.
- **[P3] F-FUEL-01 (typing)** [WT] `:97-109` — `(o as fuel_drum)` type-hostile guard pattern. Fix as blueprint.
- **Type hygiene positives**: `the hit/heat/scoreboard/zombie??` — specifically `is`-then-cast discipline is largely correct in `TouchControls`, `Hud`, `MatchHud`, `CombatController`; `player_color()` is the one raw string into `Color.html` without `is_valid_html_color()` (F-AUD-11 [HEAD]).

### Lens 9 — Platform, Viewport & Portability

- **[WT-P2] F-UI-01** [WT] `MatchHud.gd:196-202` — narrow branch bottom-anchors health cluster at fixed −390/−360/−330 px ⇒ **landscape phones <390px tall render the core health cluster above y=0 / off-screen** — exactly the device class the WT pass targets. Fix: offsets relative to `vp.y`; verify at 540×360 and 480×320.
- **[P3] F-UI-21** [WT∘HEAD] `MatchHud.gd:160-166` — short-mode scoreboard 110 px vs ~176–180 px needed; `scroll_active` false ⇒ standings clipped (WT-introduced: HEAD was fixed 240). Fix: terse rows / scroll / font.
- **[P3] F-UI-03** [WT] `MatchHud.gd:217-224` — result panel shrinks, children don't ⇒ buttons spill on <380 px tall. Fix: clamp height only or proportional children.
- **[P3] F-UI-02** [WT] — safe-area fix applied only to MainMenu; Lobby/Settings keep hardcoded padding (3 divergent copies). Fix: hoist into `UiTheme.gd` ("skin only" mandate).
- **[P3] F-CAND-05/F-BUILD-05** [HEAD/WT] — headless 64×64 viewport: `TouchControls` narrow-branch `pad_w` floor 168 px overflows (F-015 [WT]); gates rely on xvfb 1280×720 (correct, keep).
- **[P3] F-BUILD-08** [WT] `export_presets.cfg:33` — WT enables `experimental_virtual_keyboard=true`, but deployed `web/index.html` still ships `"experimentalVK":false` (no deploy since the edit). Fix: checklist — run `deploy_web.sh` after preset edits; verify VK flag in served HTML.
- **[P3] F-AUD-03/M** — Web `user://` persistence (IDBFS) is not guaranteed; treat saves as best-effort; surface dirty state.
- **[P2] F-TST-09** [HEAD] `run_gates.sh:117-127` — GdUnit4 leg rewrites 160 tracked `godot/reports/*.html` per run (WT now shows mass deletions + `report_49..52`); `git add -A` flows sweep stale HTML into commits. Fix: `git rm -r --cached` + `.gitignore` (or out-of-tree report dir).
- **[P3] F-TST-11 / F-TST-13** [HEAD] — gates "restore" settings to hardcoded defaults, not priors; no `timeout()` anywhere; frame-count loops flake under stall → infinite CI. Fix per entry.
- **[P3] F-BUILD-10** [P3] — `assets/pwa_icon_{192,512}.png` mode 600 ⇒ UID-mismatch CI export breaks PWA icon embed. Fix: `chmod 644`.
- **Godot-5 upgrade surface**: `BLENDER_EEVEE` rename (4.2), `shade_auto_smooth` removal (4.1), `BLEND_MIX` ok — two silent Breaks per F-001-03/04. Watch list.
- **Verified platform-clean**: GLB +Z forward; `focus_canvas_on_start`; PWA enabled; single-thread + sed-patched service worker; viewport `expand`; 44 px targets; reduced-motion respected in tweens/fuel (except casing() F-VFX-07 [HEAD]).

### Lens 10 — Cognitive Load & Maintainability

- **[P3] F-UI-15 / F-UI-18** [HEAD] `MatchHud.gd` — inconsistent autoload guarding (`Match != null` vs bare `Settings`); dead `_frame` counter. Fix: uniform contract or delete var.
- **[P3] F-CANN-03 (doc)** [HEAD] — broadcast-side auto-double glass cannon: mute comment needed at the broadcast site if double-token design persists.
- **[P3] F-UI-09** [HEAD] `MatchHud.gd:479-482` — **"PLAY AGAIN" calls `_on_leave_match`** (identical to LEAVE; no requeue). Fix: relabel or requeue-host flow.
- **[P3] F-UI-06** [WT] `UiTheme.gd:27` — `CROSSHAIR` added, referenced nowhere. Fix: delete.
- **[P3] F-BUILD-04** [WT] `build_testride.gd:12-50` — dead `_chip()`/`_button_style()`/`_style_button()` after UiTheme migration; editors WILL edit the dead one. Fix: delete.
- **[P3] F-BUILD-03** [WT] — `custom_minimum_size` on offset-anchored Labels is ignored; the "150px width lock" guarantees nothing. Fix: anchors or delete.
- **[P3] F-BUILD-07** [WT] `build_menus.gd:119,161,166,171` — row labels 96 px < strings at font 14 ⇒ text draws into control slots. Fix: 112–132 px or `clip_text`.
- **[P3] F-BUILD-06** [WT] — heat-locked red: `UI.DANGER` (Hud.gd:95) vs `UI.HEAT_LOCKED` (MatchHud.gd:100,357) — same gauge, two hues across scenes. Fix: single token.
- **[P3] F-ECHO-01 (cross-file)** — dead public signals: `Projectile.gd:6`, `DestructibleBuilding.gd:8` (`smashed`, HUD uses group-lookup), `_spawn_set` (`KiepieBike.gd:33,221`), `Settings` keys `network.auto_join`, `gameplay.kill_feed` (F-AUD-14) — all zero consumers. Fix: delete or wire, with a one-line justification each.
- **[P3] F-001-11 / F-001-12** [HEAD] `src/` — docstring lie (`build_wheel` "knuckle"), unused imports, no linter. Fix: trim + gate.
- **Naming positives**: groups (`destructible`, `hazard`, `local_combat`), `_q()`, `_static_cue`, geometry anchors (`Cannon_Bore_*`, `Model/Steer_*`), `QB_CAM/canon` conventions are all legible and consistent.

## 3. [WT] vs [HEAD] — What Is Your In-Flight Work vs What Was Already There

The uncommitted pass (audited as-is, defects tagged [WT]): `MatchHud.gd` (responsive relayout + heat fill → `UI.ACCENT` + safe-area), `Hud.gd` (relayout + smash_total doc tweaks), `TouchControls.gd` (fire-size scaling + narrow layout), `AnalogSteer.gd` (deadzone/knob drift (F-012)), `MainMenu.gd` (responsive safe-area), `LobbyMenu.gd/SettingsMenu.gd/UiTheme.gd` (responsive-propagation gaps (F-UI-02/04)), `build_arena.gd`/`build_testride.gd`/`build_menus.gd` (offset tweaks, builder re-ID churn, dead helpers, duplicated overlay (F-BUILD-02/04)), `FuelDrum.gd` (**respawn_delay dual-mode + WT race (F-FUEL-01/05)** — TestRide drums now respawn after 6 s; Arena stays 0.0), `CombatController.gd` (user hunks: practice spawn `(0, 0.6, 0)` + own-hazard `hit_confirmed`), `export_presets.cfg` (VK flag + desktop-only hints + reduced-motion CSS), scenes regenerated at 22:15 (`Smash_total`, offsets, ID churn), `docs/` created by this audit.

**WT defects attributable to your pass (fix before or in the same commit as its eventual merge):** F-UI-01 (health cluster off-screen on short landscape), F-UI-21 (clipped standings), F-UI-03/04/05 (result panel, resize storms, radar redraw), F-001-01-class [WT-aggravation] (untracked `reports/49..52` inside the export filter), F-FUEL-01/05 (respawn race), F-CANN-01-adjacent (WT did not touch SideCannons; listed for completeness), F-001-01 [WT] plus hygiene (F-BUILD-03/04/06/07). The FT-03 contract token: none of F-001/F-002 touch your files' *design*; they are interaction bugs in the WT code.

**Everything in net/, gates/, Blender/, VfxFactory/, Settings/, Sfx — [HEAD], yours to inherit.**

## 4. Surgical Refactoring Blueprints (Zero-Mutation Drafts)

> **R1 — Practice-mode parity (closes F-CC-01 + F-FUEL-04 + F-TST-08).** Scope: `godot/src/game/CombatController.gd:124`, `godot/tools/verify_practice.gd`. Current:
> ```gdscript
> func take_damage(amount: float, attacker_id: String, point: Vector3, token: String = "") -> void:
>     if not alive or not Match.is_playing():
>         return
> ```
> Target: `if not alive or (not practice_mode and not Match.is_playing()): return` · verify_practice.gd adds: stub `Supabase.broadcast`, call `Match.apply_lobby({"status":"playing"})`, fire a shot at a drum, assert `health < 100` and `broadcast_spy == 0`. ROI: restores the documented practice contract; 1 gate assert.

> **R2 — Forge-chain containment (closes F-01-02 + F-05-01 + F-05-02 + F-CC-06).** Scope: `TaloBackend.gd:340-359,488`, `ArenaNet.gd:69-83,142-167`, `CombatController.gd:230-255`. Target: (a) host `_issued_tokens: token → {killer, expires_at}` — issue in `issue_shot`, require `sender_id == issued.killer` in `_register_kill`, TTL 10 s, per-killer 1 s cooldown, `_used_tokens` TTL sweep; (b) `arenaNet` drops `shot` whose origin is >2 m from sender's last known position and rate-limits per owner (10/s, cap 12 remote projectiles); (c) `kill` broadcast processed only when it matches `_my_recent_hits` (≤2 s, ≤1 kill per hit); (d) victim refuses attacker_id not in roster (attribute environment). ROI: the documented trust model becomes honest; kill forgery collapses to the host's own client (which R2-a still gates). ~120 lines + 2 gates.

> **R3 — Gate-truthfulness (closes F-TST-01/02/03/04/05/06/07/08/11/12).** Scope: `godot/tools/verify_settings.gd`, `verify_match_rules.gd`, `verify_kill_flow.gd`, `verify_audit_regressions.gd`, `verify_vfx.gd`, `verify_dodge.gd`, `verify_touch*.gd`, `verify_controls.gd`, `run_gates.sh`, `verify_stability.gd`, `verify_smash_impact.gd`. Target: every backend-touching gate pre-flights `use_mock` (hard quit); every settings-mutating gate mutates in-memory + restores priors; scar/respawn/dodge-spin assertions complete; one-sided locks get their positive control; `quit(1)` on FAIL; `timeout 120` wrapper; xvfb-presence hard error; restore by captured priors. ROI: suite passes stop implying "safe to deploy" and start implying "checked". ~150 lines.

> **R4 — Export payload hygiene (closes F-BUILD-01/09 + F-BUILD-08 checklist).** Scope: `godot/export_presets.cfg:8-9` (+`.gitignore`). Target: `exclude_filter="addons/gdUnit4/*, addons/GDQuest_GDScript_formatter/*, tests/*, extension_api.json, reports/*, tools/*"`; `git rm -r --cached godot/reports`; `.gitignore += godot/reports/`; keep include `addons/talo/settings.cfg`; add a deploy pre-flight `expected_pck<4MB` warning; document the VK flag gotcha. ROI: prevents QA HTML/PNGs and gate internals shipping in the public Web bundle; ~20 lines + housekeeping.

> **R5 — Settings durability (closes F-AUD-01..07, F-AUD-12..15).** Scope: `Settings.gd`. Target: tmp+rename save, save-on-diff, type+clamp vs DEFAULTS, boot re-applies `resolution_scale`/`glow`, atomic `apply_quality`, wire or delete `video.shadows`, bus-index derived (`get_bus_index`), `player_color` validated, `VERSION` honoured. ROI: crash-loss, GPU-hang and phantom-preset failure classes eliminated. ~80 lines.

> **R6 — God-file decomposition (closes F-UI-07, F-01-16, F-VFX-09).** Scope: `MatchHud.gd`, `TaloBackend.gd`, `VfxFactory.gd`. Target: extract `RadarControl.gd`, `KillFeed.gd`, `RelayoutLayout.gd`; split `TaloBackend` into auth/props/scorer/router behind the existing facade; typed `VfxOpts` class + named tuning consts. No behaviour change; gates must stay green. ROI: reviewability of the two most-edited files in the repo; ~1–2 days, incremental commits (Author rule: builders after patch; keep `verify_*` semantics byte-identical).

## 5. Phased Roadmap & Copy-Paste Agent Prompts

1. **Phase 1 — Containment (\(P1\))** — R1 (practice parity, 3 lines), R2 (forge-chain), R3 (gate truthfulness), F-TST-02 (wipe), F-CC-02 (invisible wall), F-CANN-02 (freed-node shot loss).
2. **Phase 2 — Hardening (\(P2\))** — R4, R5, F-01-03/04/05 (props order, reconnect, host-leave), F-CANN-01/04, F-UI-01 (off-screen health), F-PICK-01, F-DEST-01 (remote smash — design decision), F-FUEL-01/05 (WT), F-TST-04..15, F-AUD-04/05/06/07.
3. **Phase 3 — Hygiene (\(P3\))** — R6, dead-code removal (F-PROJ-03/F-DEST-06/F-UI-18/F-BUILD-03/04/F-AUD-14), F-VFX-02/04/09 pooling, F-UI-17 kill-feed injection, F-UI-09 Play-Again, F-UI-12 ready-state reconciliation, F-BUILD-10/11 (PWA icons mode 600, JWT issuer check).

> **Prompt [P1-1] (`CombatController.gd` + `verify_practice.gd`):** "Scope strictly to `godot/src/game/CombatController.gd:124`, `godot/tools/verify_practice.gd`. Mirror the practice_mode bypass used at L73 so `take_damage()` returns only when `not alive` or (`not practice_mode and not Match.is_playing()`). In verify_practice.gd, after the existing projectile-spawn leg: stub `Supabase.broadcast` by direct call-interception or by spying signal, call `Match.apply_lobby({status:'playing', settings:{…}})`, spawn the drum fixture, assert the rider's health dropped and the spy recorded zero kill broadcasts. Run `bash godot/tools/run_gates.sh --no-build`; expect 21/21. Do not commit."

> **Prompt [P1-2] (`TaloBackend.gd` + `ArenaNet.gd` + `verify_audit_regressions.gd`):** "Scope to `godot/src/net/TaloBackend.gd` (issue_shot/\_register_kill/kill_request regions), `godot/src/game/ArenaNet.gd` (:142-167, :69-83), `godot/src/game/CombatController.gd` (:228-255, :150-157), `godot/tools/verify_audit_regressions.gd`. Implement issuance binding: remember `issue_shot` returns, reject `_register_kill` unless `sender_id == issued.killer`, TTL 10s, 1s per-killer cooldown. In ArenaNet, reject `shot` whose origin is >2m from the sender's last known proxy position; cap 12 remote projectiles; per-owner 10/s. In CombatController maintain `_my_recent_hits` and process only matching kill broadcasts. Extend the regression gate with: (a) forged join rejected (uid≠sender), (b) unknown token rejected, (c) hot-loop kills rejected after cooldown, (d) forged shot >2m rejected. Gates must stay green. Do not commit."

> **Prompt [P1-3] (gates):** "Scope to `godot/tools/verify_*.gd`, `run_gates.sh`. Pre-flight `use_mock` hard-exit in all backend gates; mutate-in-memory-and-restore for `verify_settings.gd`, `verify_touch.gd`, `verify_practice.gd`, `verify_controls.gd` (capture priors, not defaults); convert `verify_stability.gd`/`verify_smash_impact.gd` to `quit(1)`; add `timeout 120` around each gate; make a missing `xvfb-run` a loud failure in the multitouch leg; add scar-cap exercise (MAX_SCAR+5) and past-deadline respawn legs; keep GDUnit4 101 handling. Then `bash godot/tools/run_gates.sh --no-build` — all must pass. Do not commit."

> **Prompt [P2-1] (`export_presets.cfg` + `.gitignore`):** "Scope to `godot/export_presets.cfg` and root `.gitignore`. Add `reports/*, tools/*` to `exclude_filter`; preserve `include_filter=addons/talo/settings.cfg`; keep tests/formatter/extension_api exclusions. `git rm -r --cached godot/reports` (report dirs are untracked churn). Verify every `res://` path that ships in the pck contains no secrets (`grep -rE 'ta_|api_key|secret' godot/src godot/tools` — confirm only the by-design GAME key in settings.cfg). Do not commit."

## 6. Existing Test Suite Comparison, Mutation Truth Table & MVTH

**Test-to-code ratio:** 1 GdUnit4 test file (`tests/test_kiepie_pad.gd`) : 29 src files, but `tools/verify_*.gd` function as a behavioral harness — 21 gates, ~2,000 LOC, 42-assert touch_multitouch strongest. **Estimated suite-wide $M_kill ≈ 58%** (range 40–85%).

| Implementation Module | Pairing | Pathologies | M1–M4 Killed | Missing Assertions |
| :--- | :--- | :--- | :--- | :--- |
| `TouchControls`/`AnalogSteer` (WT) | `verify_touch_multitouch.gd` | state-coupled (scene offsets) | 80–85% (M1 partial-strength, M2, M3 subprocess, M4 focus-out) | wall-clock timeout |
| `VfxFactory` (caps/gradients/motion) | `verify_vfx.gd` + `verify_audit_regressions.gd` | No-Throw Theater (F-TST-17) | ~60% | scar cap (F-TST-04), async/unplugged |
| `KiepieBike` (dodge/control/sensitivity) | `verify_dodge.gd` `verify_controls.gd` | Time-Window Myopia, absf weakness (F-TST-05) | 55–65% | spin sign, rejection-not-reframe |
| `MockBackend`/`MatchState`/`TaloBackend` | `verify_match_rules.gd` `verify_talo_backend.gd` | Mock-Mirror (F-TST-10); one-sided (F-TST-03) | 40–65% | host auth path, props order, issuance |
| `Practice mode` (0dbfd44) | `verify_practice.gd` | Result-Only, absence-never-asserted (F-TST-08) | ~60% | broadcast spy, death, drums |
| `Settings` | `verify_settings.gd` | Happy-Path + Shared Mutable State (F-TST-02) | negative-quality | prior restore, atomic write failure modes |
| `ArenaNet` | — none | — | 0% | shot binding, kill auto-register |
| `SideCannons` | partial (indirect via combat) | — | partial | triple-fallback, frees, refund |

**Why tests missed the P1s:** mock-mirror extends to the whole pipeline — gates stage `use_mock=true` *because run_gates.sh exports it*, certifying `MockBackend` parity (which is a *superset* of live checks — F-03-04), while `verify_practice.gd` asserted presence ("shots spawn") rather than suppression ("no broadcast") or damage ("drums hurt") — the absence-of-effect class is exactly where all three one-sided P1 locks live. **The suite has no negative assertions against a networked opponent at all.**

**MVTH specifications.** (1) `net_forge_test.gd`: stub shot/kill broadcasts from an **unknown** sender; assert victim-side rejection at both layers. (2) `practice_contract.gd`: health decrease + zero-broadcast for drum kill; `Match.is_playing()` false-path table. (3) `gate_self_guard.gd`: assert every backend gate emits `quit(2)` when `use_mock` absent; assert settings restore uses captured priors. (4) Property tests: ISO↔unix round-trip (F-01-14), deadzone↔knob coupling (F-012), spawn-pick null safety (F-CC-08). (5) Export pre-flight: pck size accounting incl. git index for `reports/`.

## 7. Resolved Defects & Verified Contracts (Evidence In Audit)

- **respawn_at-as-deadline** (prior audit class): RESOLVED — writers (`TaloBackend.gd:362-365`, `MockBackend.gd:131-143`) and reader (`MatchState.gd:150-163`) all treat it as future deadline; emission semantics F-02-03 remain.
- **Dodge sign inversion** (476587a): **LOCKS** hop, **WEAK** spin (F-TST-05); gate asserts Q ⇒ +X. ✓ physics verified.
- **18→21 gate count** in `run_gates.sh` confirmed; exit 101=pass-or-orphan-warnings treated sanely; GdUnit4 101/100 handling correct.
- **Controls liveness**: `steer_sensitivity`, `touch_force`, `dodge_size`, `fire_size` all LIVE end-to-end with gates (F-AUD-04 exception: boot re-apply gap).
- **Combat token chain**: projectile→drum→`ignite`→`CombatController.take_damage(55,…)` attribute path intact for the local player.
- **Kill attribution by *victim* design** — inherited from client-authoritative scoring; R2 restores integrity.
- **GLB orientation** (+Z forward), spawn groups, muzzle anchors (`Cannon_Bore_*`), decal-textures-not-text: all intact (QA_debrief non_manifold=0, minZ=0.000, bbox matches manifest within ±2.5%).

## 8. Cross-Cutting Themes & Contract Drift Between Tool & Code

1. **Documented invariants unenforced.** minZ=0, non-manifold=0, rim/tyre ≈ 0.55: enforced nowhere in `src/` (F-001-07) — they rest on docs + the out-of-tree Blender QA skill.
2. **Mock ≥ live (superset).** MockBackend's checks exceed TaloBackend's at every layer; every prior sharp incident came from this asymmetry (b79f5ac class; the current chain is F-01-02/F-03-04).
3. **Two layout engines.** `_relayout()` vs builders vs `_apply_safe_area()` on three screens; they will drift (WT already documents: safe-area on one of three menus only).
4. **Dual-ownership.** `ExhaustFlames.emitting` (bike vs combat), `_frame`, offset idioms (F-005 mixed), `heater`/heat-lock hues, `_Reuse` of debounce timers.
5. **Silent catch-alls.** 5× in Blender, 2× in Godot (`Mid-rebuild mute CSI` is absent — but unguarded loads (F-013), silent `_migration` (F-AUD-13), no-backoff retry (F-02-01), uncounted lights (F-VFX-01), unchecked saves (F-AUD-03) are the same shape).
6. **Gates as documentation.** Where AGENTS.md states a contract ("practice death/respawn works"), the corresponding gate either doesn't exist (broadcast spy) or locks presence only (F-TST-08) or is false-confidence (`verify_settings` shadows). 21/21 green currently **over-states** shipped quality.
7. **Web delivery fragility.** Single-thread service-worker precache mismatch (`index.worker.js`), pck 4 MB abort, VK flag unverified in served HTML, deploy vs export preset drift.
8. **PWA icons mode 600** on local FS (F-BUILD-10).

## 9. Attribution & Drift Window (Read Before Quoting Findings)

**Audit periods (all times +07):** kickoff 22:09 · baseline & telemetry 22:10–22:15 · sections in flight 22:10–22:30 · report 22:30. **The user's own concurrent session modified the tree throughout**: source edits at 22:05–22:08 (14 files, pre-audit), builder/scene regeneration at **22:15–22:16** (6 scenes re-ID'd), gate outputs `report_50..52` (22:13–22:2x), **and mid-audit**: `godot/src/TouchControls.gd`, `godot/tools/build_arena.gd`, `godot/src/Hud.gd`, `godot/src/ui/MatchHud.gd`, `godot/src/ui/MainMenu.gd`, `godot/reports/report_52` rewritten; **new untracked files** `godot/tools/_postop_verify.gd` and `renders/postop_*.png` (22:2x) — **not audited** (appeared after section snapshots; named here so they are not blamed on the audit).

**Consequences:** line citations for those files are point-in-time; findings marked [WT∘HEAD] cite convergent locations stable through the window (all `git diff` hunks verified against `working-tree.diff` v3, 22:18:11 snapshot); [WT] tags are accurate; [HEAD] tags were verified byte-identical against `/tmp/opencode/audit/baseline/` (`diff -q` clean for every [HEAD] file). The audit **cannot** certify the current file contents — a re-run (or delta-re-scan of the 8 drifted files) is required after the in-flight pass settles.

**Zero-mutation evidence:** audit commands: `cat/sed/grep/find/git diff/git status/wc/stat/python3 -B preflight (read-only)`; subagents explicitly forbidden writes; no gate executed; no file edited. `git status --porcelain` at kickoff = 23 entries; at 22:25 = 44+ (user activity), with zero additions attributable to the audit. The **only** audit-created paths anywhere are `/tmp/opencode/audit/*` and this directory/file (`docs/plans/audit/opencode/inkling 2 small/`) — both requested.

## 10. Explicit N/A Items & Residual Risks

- **Lens 9 (runtime rendering probe):** Pass 2.5 browser probe N/A — no layout/canvas audit surface (game is 3D WASM); render sanity is gate-covered (`vfx_showcase`, stability/smash gates) + user device pass. Canvas-geometry probe not applicable to WebGL.
- **`web/` repo:** not audited (separate repo, 15 files, `index.pck` opaque blob — binary integrity checked only via deploy's HTTP 200 + pck guard).
- **`supabase/`:** retired migrations retained for history; not audited (no live path).
- **`addons/`:** vendored (GdUnit4, Talo 0.20); excluded per prerequisite; upstream issues out of scope (F-01-12's null-payload is the one pinned interaction, cited as-observed).
- **Scenes (`*.tscn`):** wiring-consistency spot-check only (builder↔scene node offsets, `practice_mode=true`, groups, `respawn_delay`, BtnFire — all verified coherent). Physics-classified behaviour not executed (zero-mutation).
- **Subagent confidence calibration:** findings F-01-02/F-05-01/F-05-02 (forge chain) are higher-sensitivity and were cross-validated against TaloBackend/MockBackend/ArenaNet source; F-CC-01 was re-verified in-session against the working file (line cited exactly). All other findings rely on single-pass static reading.
- **What could be wrong with this report:** (1) the WT drifted mid-audit — line numbers stale (checked mitigations in §9); (2) severity rubric is calibrated to the reference matrix, not to this repo's risk appetite — you may legitimately re-tier F-TST-03 (one-sided lock) below P1; (3) `$M_kill` figures are reviewer estimates, not coverage-tool output (no instrumented runner exists in-repo).
- **Follow-ups owned by the user:** (a) settle in-flight pass, then re-scan those 8 files (30 min) or accept [WT∘HEAD] staleness; (b) decide the owner of the kill-issuance contract (host vs Talo plugin); (c) decide `pwa_icon` mode 600 fix; (d) re-run `run_gates.sh` after P1-1..P1-3 land; (e) production deploy verification of VK flag after next `--apply`.

---

**Auditor sign-off.** Scope honored (read-only), baseline preserved, telemetry recorded, drift disclosed, findings tagged, mutations: none beyond this document. **Action required before merge of your in-flight pass:** read §1 (Triage), §3 (your WT defects), F-CC-01 (P1, three lines) and F-TST-02 (your dev config is being wiped by your own suite) — both are one-sitting fixes.

## Appendix A — Runtime Verification (post-audit, same evening, read-only)

Executed with `KIEPIE_MOCK_BACKEND=1 godot-4.3 --headless --path godot -s …` against the live working tree at ~22:31. No scenes rebuilt, no gates run, no files written (scratch probes live in `/tmp/opencode/audit/`; tree untouched).

**A1. F-CC-01 — practice-mode damage gate. PROVEN.** TestRide bike, `CombatController.practice_mode=true`, no lobby:
```
practice_mode = true
practice:   health 100.0 -> 100.0 after take_damage(30)
arena-like: health 100.0 -> 70.0 after take_damage(30) (is_playing=true)
PROBE VERDICT: F-CC-01 PROVEN — practice-mode damage is unreachable; arena path works
```

**A2. F-CANN-01 — single-muzzle fallback triple-fire. PROVEN.** KiepieBike.tscn with `Muzzle_R` + `Cannon_Bore_R` removed from the tree; `SideCannons.setup()` then reports:
```
removed: ["Muzzle_R", "Cannon_Bore_R"]
muzzle anchors after losing the entire right side: 3
```
One missing right-side anchor yields `Muzzle_L + 2 fallbacks` — every trigger pull spawns projectiles from three mounts and deals 1.5× damage, silently.

**A3. F-TST-02 NOT executed — deliberately.** `verify_settings.gd` persists then `reset_defaults()`-wipes the live user cfg (`~/.local/share/godot/app_userdata/KiepieBike/settings.cfg`, confirmed present with user values); running it *is* the defect, and would corrupt your real settings. Evidence is static-read only.

**What this append means.** Two of nine P1s are now engine-proven; the remaining seven (forge chain, gate-wipe, one-sided forged-state lock) remain static-read findings and are flagged as such. The audit's strongest claim — "this build ships a practice mode whose combat is decorative" — is now demonstrable in 1.2 s of engine time, not inference.
