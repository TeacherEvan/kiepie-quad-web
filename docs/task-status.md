# Task Status — Kiepie Quad

Concrete done-vs-pending ledger. Companion to [project-plan.md](project-plan.md);
navigation in [index.md](index.md). Statuses are evidence-backed: commit hashes,
gate names, or live checks — not assumptions.

**Last verified:** 2026-11-25 — full gate suite **29/29** green, `web_hygiene OK`, `_check_scripts.gd` **47/47** (`28651c2`, `983c0d0`, live web deploy `eee389a`).

## 2026-11-25 — EVAN THE SKELETON (new playable vehicle + bespoke arsenal)

- **Model:** `src/build_evan_skeleton.py` rebuilds `Evan_Skeleton.blend`, `godot/assets/Evan_Skeleton.glb`, `Evan_Skeleton.stl` and the authored `evan_spatial_manifest.json` (stylized brief — vanishing-point metrology skipped). 52-joint `SkeletonProfileHumanoid`, baked clips `Idle_Sway` / `Play_Strum` / `Headbang_Riff` / `Action_BigFinish`, minZ 0.000. QA reviewer verdict **APPROVED**: 4,062 verts, 7,354 faces, 0 non-manifold edges, 4 diagnostic renders. GLB is intentionally NOT Draco-compressed (Godot 4.3 here has no Draco importer).
- **Integration:** preference-only `VehicleRegistry.VEHICLE_EVAN` (kept out of the FNV deal pool so existing hash fixtures and `PROTOCOL_VERSION = 3` stay intact), `EvanVisual.gd` driver, recursive muzzle anchor lookup, MainMenu selector, runtime swap for local + remote proxies, and regenerated `MainMenu.tscn` / `LobbyMenu.tscn` / `SettingsMenu.tscn` / `KiepieBike.tscn`.
- **Weapons:** `SoundWaveProjectile.gd` (pink sound waves), `BoomerangGuitar.gd` (out-and-return damaging guitar; spherical return steering at constant speed), `DevilHandStrike.gd` + `CombatAoe.apply_lethal_blast()` (ground hand, instant kill, 2 s telegraph / 7.5 m zone). Wire kinds remain `primary` / `rocket` / `meteor` so no new net messages are needed.
- **Gates:** `verify_evan.gd` (0 failures) + `verify_evan_weapons.gd` (38 PASS / 0 FAIL); `run_gates.sh` grew 29 -> 31 gates.

## 2026-11-25 — Disappearing visuals fix & Death Race track upgrade (`28651c2`, `983c0d0`, live `eee389a`)

### Disappearing visuals (Death Race mobile: sky only, 0 km/h)
- **Root cause:** Freezing a `VehicleBody3D` in Godot 4.3 while its wheels and collision are active produces a `NaN` transform, and `FollowCam` then latches onto the `NaN` (rendering only sky/horizon and `0 km/h`), compounded by Godot 4.3 `gl_compatibility` mobile WebGL2 sub-FBO scaling drops.
- **Fixes:**
  - `FollowCam.gd`: `NaN` guards (`_vec_ok()`, `_ensure_clean_basis()`, `_safe_look_at()`, `_process()`), `snap_to_target()`, `_cam.current` & finite transform recovery, and `near`/`far` clamps.
  - `KiepieBike.gd`: `_is_pose_valid()` (including `y > 45.0` sky-launch bound), `_safe_spawn()`, recovery in `_integrate_forces()`, and velocity clamps.
  - `CombatController.gd`: in `_die()` / `_respawn()` / `reset_state()`, disable collision and zero velocities before freezing, plus post-unfreeze deferred `_notify_camera_snap`.
  - Finite-value guards in `LoopZone.gd` and the `MatchHud` radar.
  - `Settings.gd`: keep mobile WebGL2 auto `scaling_3d_scale` at `1.0` and disable `msaa_3d` on Web / sub-1.0 scale.
  - Regression tests in `verify_deathrace.gd` section 7.

### Death Race track upgrade
- **Circuit:** 550.6 m closed uniform cubic B-spline (29 control points, 180 arc-length samples), with dark-charcoal `TrackRibbon`, dashed `TrackCenterLine`, amber `TrackEdgeLines`, 3D beveled alternating red/white `TrackKerbs`, and `GridBox0..7`.
- **Features:** Serpent Esses, Furnace Bend, Canyon Switchback, and Victory Carousel with physical black-and-yellow `>>>` chevron turn boards, continuous mitered concrete jersey barriers (`BarrierConcrete` + `BarrierTopRail` + impact attenuators), curved split pit lane with `PitGantry`, `LoopApron0/1` and `LoopBackstop0/1`, tiered stadium grandstands, and high-contrast jump ramps.
- **Bounds:** 28 m collision-only containment walls on all four sides; desert-turf stadium floor expanded to 250×210 with a 560×560 horizon skirt.
- **Layout:** Checkpoints, loops, finish line (non-Z-fighting dark fascia + 5 start-light pods), spline-anchored pickups/drums, and spawns repositioned.
- **Gate result:** `run_gates.sh` passes **29/29** (`28651c2`, `983c0d0`); `index.pck` = 4,063,712 bytes (`eee389a`).

## Audit remediation — Surgical Audit Rev 2 (2026-11-24 · landed in `28651c2`)

Source report: [audits/kiepie-quad-surgical-audit-2026-11-24-rev2.md](audits/kiepie-quad-surgical-audit-2026-11-24-rev2.md) + [SARIF 2.1.0](audits/kiepie-quad-surgical-audit-2026-11-24-rev2.sarif).

| ID | Finding (severity) | Fix | Evidence |
| --- | --- | --- | --- |
| P1-1..2 | `_join_gen` self-invalidation on zombie-room eviction; unprotected `join_lobby_channel()` | `leave_lobby_channel(bump_join_gen: bool = true)` + `false` at eviction sites; `_join_gen` + sequence reset in `join_lobby_channel()` | `TaloBackend.gd` + `verify_talo_backend.gd`, `verify_audit_regressions.gd` |
| P1-3 | Stale `LobbyService` cleanup cancels newer in-flight `create_lobby`/`join_*` | `_pending_requests` + `cleanup_gen == _session_gen` guard in `_enter_if_current()` | `LobbyService.gd` + `verify_match_rules.gd` |
| P1-4 | `patch_web_sw.py` silent-skip on 5/6 blocks + non-idempotent hash append | Fail-fast `RuntimeError` on all 8 markers + double-patch guard + `test_patch_web_sw.py` wired into `check_web_hygiene.py` | `patch_web_sw.py`, `test_patch_web_sw.py`, `check_web_hygiene.py` |
| P1-5 | Fresh-checkout / CI `talo_backend` failure when `addons/talo/settings.cfg` is absent | `run_gates.sh` writes offline-safe `settings.cfg` (`0600`) when absent; `verify_talo_backend.gd` also checks `inject_talo_key.py` template | `run_gates.sh`, `verify_talo_backend.gd` |
| P2-1..6 | `SideCannons` pool eviction (`24`→`48` + inactive-slot scan); `NetworkedBike` invalid first `"p"` guard; `TaloBackend` `max_players` cap; `Settings.reload()` in `_gate_settings_guard.gd`; 3 strengthened `verify_audit_regressions.gd` checks; `check_scene_sync.py` SubResource content hashing | All remediated and gated | `SideCannons.gd`, `NetworkedBike.gd`, `TaloBackend.gd`, `Settings.gd`, `_gate_settings_guard.gd`, `verify_audit_regressions.gd`, `check_scene_sync.py` |
| P3-1..7 | `JSON.parse_string()` + `_kill_last_base.erase(uid)`; `LoopZone.loop_half_width`; `CombatController` cold-boot `TestRide` attribution; `TouchControls` widen restore; `VfxCore`/`VfxHeavy` quality & `reduced_motion` guards; `build_testride.gd` persistent `"bike"` group; wildcard `Settings.changed` + `fmod` bounded `_jet_t`/`_breathe_t` | Cleaned up and verified | `TaloBackend.gd`, `LoopZone.gd`, `CombatController.gd`, `TouchControls.gd`, `VfxCore.gd`, `VfxHeavy.gd`, `build_testride.gd`, `AmbientVfx.gd`, `FollowCam.gd`, `KiepieBike.gd`, `PogoVisual.gd` |

## 2026-11-23 — Rocket contract + vehicle-specific launchers + BIG-BEN ground clearance

| Change | Detail | Evidence |
| --- | --- | --- |
| NARDUS cigar launcher | `RocketProjectile` `"cigar"` style — **1.9 m** fat wrapper (vs 0.52 m rocket), gold band, glowing cherry + ash cap, heavy smoke trail and 3.0-scale blast — wired only for `weapon_profile == "pogo"`; HUD reads `CIGAR LAUNCHER`. Visually proven side-by-side against the standard rocket under the real renderer | `SideCannons.gd`, `ArenaNet.gd`, `verify_pogo.gd`, `verify_deathrace.gd` |
| Distinct launcher identities | BIG-BEN keeps `CASH BAG LAUNCHER` / `CASH BAG DROP`; Quad keeps plain `ROCKET LAUNCHER` / `LIGHTNING STRIKE`; no cross-vehicle style bleed | `SideCannons.weapon_display_name()`, `verify_aston.gd` |
| Universal rocket damage | Direct hit → `CombatController.take_lethal_hit()` (bypasses shield/spawn invuln); near miss → flat `RocketProjectile.BLAST_DAMAGE = 90.0` (90% of 100 HP), no falloff; client-authoritative so remote rockets hit the local victim too | `RocketProjectile._detonate()`, `CombatAoe.apply_blast()`, `verify_deathrace.gd` |
| BIG-BEN ground drag | `src/build_aston_martin.py` lifts the body shell `BODY_LIFT = 0.06` (chassis min_y 0.016 → 0.076) while wheels/steer pivots stay at minZ 0.000; suspension rods excluded so they still bridge body↔hub | rebuilt `Aston_Martin.blend` / `Aston_Martin.glb` (177 KB, 0 non-manifold), `verify_aston.gd` |
| Independent review fixes | direct-hit token now `"<base>:v<victim>"` so a same-shot AOE kill cannot steal the host's 1 s rate-limit slot; shooter-side AOE skips the directly-hit proxy so the victim's authoritative `-100` number shows; `take_damage`/`take_lethal_hit` share `_commit_hit()` | code review, `verify_deathrace.gd` token + damage assertions |

## Audit remediation — Surgical Audit Rev 2 (2026-11-23)

Source report: [audits/kiepie-quad-surgical-audit-2026-11-23-rev2.md](audits/kiepie-quad-surgical-audit-2026-11-23-rev2.md) + [SARIF 2.1.0](audits/kiepie-quad-surgical-audit-2026-11-23-rev2.sarif).

| ID | Finding (severity) | Fix | Evidence |
| --- | --- | --- | --- |
| P1-1..3 | Guest `12 s` lap throttle vs `3 s` retry; `RaceTracker` non-final lap recovery; missing post-`await` channel/lobby guards | `GUEST_LAP_RETRY_S = 2.5`; `_arm_lap_recovery()` on all pending laps; `op_channel`/`expected_id` guards | `TaloBackend.gd`, `MatchState.gd`, `RaceTracker.gd` + `verify_talo_backend.gd`, `verify_deathrace.gd` |
| P1-4 | `ArenaNet._on_broadcast("kill")` lacks token dedupe, roster check, `Match.is_playing()` gate | Token dedupe (`MAX_SEEN_KILL_TOKENS=128`), victim cooldown, roster & playing gates | `ArenaNet.gd` + `verify_multiplayer.gd` |
| P1-5..6 | `VfxFactory.cash_explosion` animated `_ring_quad` under `reduced_motion`; `repair_and_verify.py` skips `EMPTY` anchors/front wheels | `_static_cue` + `bolt_root` cleanup; shift all `parent is None` roots in collection | `VfxFactory.gd`, `repair_and_verify.py` + `verify_vfx.gd` |
| P2-1..9 | `BananaProjectile._build_tracer` visibility/process reset; 36-VBO lightning & unwarmed `CashBagVisual`; `Particles=0.0` bypass; `MatchHud._fps_label` overlap; `last_auth_error` unset; freed `owner_node`; late `"join"`; `3.47 MiB` splash; `CombatAoe` & `UiTheme.apply_safe_area` extraction | All remediated and gated; splash re-encoded at `-crf 25` | `BananaProjectile.gd`, `CashBagVisual.gd`, `VfxFactory.gd`, `MatchHud.gd`, `MainMenu.gd`, `CombatAoe.gd`, `UiTheme.gd`, `build_intro_splash.py` |
| P3-1..5 | `#victory-splash` 10 s timeout; `build_intro_splash.py` portability/cleanup; `verify_talo_backend.gd` `"roster"` key; `SideCannons` `_aim_mat` cache; docs sync | Cleaned up and verified | `index.html`, `export_presets.cfg`, `build_intro_splash.py`, `SideCannons.gd`, `verify_talo_backend.gd`, docs |

## Audit remediation — Surgical Audit Rev 2 (2026-11-22)

Source report: [audits/kiepie-quad-surgical-audit-2026-11-22.md](audits/kiepie-quad-surgical-audit-2026-11-22.md) + [SARIF 2.1.0](audits/kiepie-quad-surgical-audit-2026-11-22.sarif).

| ID | Finding (severity) | Fix | Evidence |
| --- | --- | --- | --- |
| P0-1 | `2.5 s` cold-boot Talo socket timeout permanently bricks multiplayer | `10 s` timeout, late `v1.players.identify.success` promotion, `Supabase.reconnect()`, `MainMenu` `BtnRetry` | `TaloBackend.gd`, `SupabaseClient.gd`, `MainMenu.gd` + `verify_talo_backend.gd` |
| P1-1..2 | Host self-echo `"state"` rollback; `LobbyService` ghost-lobby leak on cancel | `_state_seq` monotonic sequence + host echo skip; `_session_gen` bumped unconditionally in `LobbyService.leave()` + `_enter_if_current()` | `TaloBackend.gd`, `LobbyService.gd` + `verify_audit_regressions.gd` |
| P1-3..6 | `5.0 m` muzzle lag drop; unfrozen dead bike free-fall; `RaceTracker` guest rollback; `NetworkedBike` pre-`_kill_lock_until` mutation | `16.0 m` lag window; `bike.freeze = true` in `_die()`; `current_lap` recomputed + 3 s final-lap recovery; `_kill_lock_until` checked before mutation | `ArenaNet.gd`, `CombatController.gd`, `RaceTracker.gd`, `NetworkedBike.gd` + gates |
| P1-7..10 | 5 hollow gate checks; `auto_connect_socket=true` live `401`s in offline gates; waiting-lobby host-loss soft-lock; `MainMenu` mobile clipping | Repaired all 5 gate blocks; `auto_connect_socket=false` in `settings.cfg`; waiting-lobby `_poll_host_alive` + `LobbyMenu._on_host_lost`; `MainMenu` `ScrollContainer` | `settings.cfg`, `LobbyMenu.gd`, `build_menus.gd` + `verify_*.gd` |
| P2-1..13 | `join_lobby_channel` missing `"vehicle"`, solo Death Race banner & PlayAgain DOM leak, inverted radar, `SettingsMenu` preset flush, `LoopZone` stall/leak, `KiepieTime` `NaN`, `PogoVisual` Euler yaw, `SideCannons`/`Projectile` pooling, `TestRide` `Cone#24` impaling `RampRight` + HUD contrast/gaps, `FollowCam` 180° reverse snap, world-anchored dodge dust, `qb_core._cap_holes` `used_edges`, doc sync | All remediated and gated | `MatchHud.gd`, `SettingsMenu.gd`, `LoopZone.gd`, `KiepieTime.gd`, `PogoVisual.gd`, `SideCannons.gd`, `Projectile.gd`, `build_testride.gd`, `TouchOverlayKit.gd`, `FollowCam.gd`, `KiepieBike.gd`, `qb_core.py`, docs |
| P3-1..6 | Dead fields, `FuelDrum` `_ignited` skip, `scorch` elevated `pos.y`, `TouchControls` `touch_force` reactivity & StyleBox cache, `Hud` click SFX, `check_web_hygiene.py` outside `.git`, `build_menus._verify` full paths | Cleaned up and verified | `FuelDrum.gd`, `VfxFactory.gd`, `TouchControls.gd`, `Hud.gd`, `check_web_hygiene.py`, `build_menus.gd` |

## Audit remediation — Surgical Audit v3.0 (2026-11-21)

| ID | Finding (severity) | Fix | Evidence |
| --- | --- | --- | --- |
| P1-1..2 | Invalid `COEP: "none"` in `vercel.json`, flattened `check_web_hygiene.py`, missing `web_hygiene` gate, stale `index.pck` | Removed invalid COEP, route-scoped `check_web_hygiene.py`, added `web_hygiene` to `run_gates.sh` (28 gates), re-exported `index.*` | `vercel.json`, `check_web_hygiene.py`, `run_gates.sh`, `index.pck` |
| P1-3..6 | `TaloBackend` `_apply_props` drain, `leaving_id` host handoff, `_poll_host_alive`/`_on_socket_closed` gen guards, guest `_register_lap` & `RaceTracker` roster sync | `_apply_drained` signal, `leaving_id` URL binding, gen/channel checks, guest `MIN_LAP_SECONDS` + `RaceTracker._on_roster_changed()` | `TaloBackend.gd`, `RaceTracker.gd` + `verify_talo_backend.gd` |
| P1-7 | `KiepieTime.trigger_hitstop()` ignores `Node` callers & leaks expired `_scales` | Unwrap `Node.get_tree()`, remove expired `scale` from `_scales` | `KiepieTime.gd` + `verify_combat.gd` |
| P1-8 | `SettingsMenu._refresh_all()` clobbers 350 ms debounced writes | `_effective_val()` consulting `_pending_writes`; clear on quality preset | `SettingsMenu.gd` + `verify_settings.gd` |
| P1-9 | `ArenaNet` & `SideCannons` projectile pool thrash on Quad/Nardus swap | Script-matched pool reuse in `ArenaNet._acquire_remote_proj()`; clear `_proj_pool` in `SideCannons.setup()` | `ArenaNet.gd`, `SideCannons.gd` + `verify_vfx.gd` |
| P1-10 | Inverted `one_pole_lp()` in `generate_sfx.py` | Fixed to `prev + (1.0 - a) * (value - prev)` | `generate_sfx.py` |
| P2-1..11 | `res is Dictionary` guards, `HazardPit` remote proxy filter, AOE ignited drum skip, `VfxFactory`/`DestructibleBuilding` debris caps & natural group removal, `NetworkedBike.update_identity()` re-tint + `"t"` turbo, `SideCannons.fire()` post-`await` VFX/SFX, `Hud`/`TouchControls`/`FollowCam`/`AmbientVfx` lifecycle & live `Settings.changed`, `repair_and_verify.py` GLB sync, `verify_smash_impact`/`verify_stability` `_check()` + `free()`, `Sfx.play_ui()` menu wiring (`MatchHud`, `FuelDrum`/`DestructibleBuilding` `play_3d`, `deploy_web.sh` SW md5 verified already clean) | All fixes landed and gated | `HazardPit.gd`, `RocketProjectile.gd`, `MeteorStrike.gd`, `VfxFactory.gd`, `DestructibleBuilding.gd`, `NetworkedBike.gd`, `SideCannons.gd`, `Hud.gd`, `TouchControls.gd`, `FollowCam.gd`, `AmbientVfx.gd`, `MainMenu.gd`, `LobbyMenu.gd`, `repair_and_verify.py` + `verify_deathrace.gd`, `verify_multiplayer.gd`, `verify_vfx.gd`, `verify_smash_impact.gd`, `verify_stability.gd` |
| P3-1..5 | `VfxFactory` `MUSHROOM_AABB` / duplicate `wreck.transform`, dead `_chip`/`_button_style` in builders, `qb_core.apply_modifiers` + `build_quad.finalize`, `build_pogo_nardus` `blend_method` + `main()` guard, atomic `patch_web_html.py` (`P3-6` `docs/plans/review_plan.md` intentionally untouched) | Cleaned up | `VfxFactory.gd`, `build_*.gd`, `qb_core.py`, `build_quad.py`, `build_pogo_nardus.py`, `patch_web_html.py` |

## Audit remediation — 10 Principal Engineer Surgical Audit (2026-11-20)

Source report: [audits/kiepie-quad-surgical-audit-2026-11-20.md](audits/kiepie-quad-surgical-audit-2026-11-20.md) + [SARIF 2.1.0](audits/kiepie-quad-surgical-audit-2026-11-20.sarif) (`4d3c049`, health score 64/100 → ≥ 92/100).

| ID | Finding (severity) | Fix | Evidence |
| --- | --- | --- | --- |
| P0-1 | Forged `"join"` frame injects `laps`/`kills`/`score`/`is_ready` | Strict allowlist on `"join"` preserving trusted prior stats | `c64759f`, `dcacfe9` · `TaloBackend.gd` + `verify_audit_regressions.gd` |
| P0-2 | `.vercelignore` absent — repo sources & audits published on Vercel | Runtime-only allowlist (`.vercelignore`: `index.*`, `favicon.ico`, `web-assets/**`) | Deploy commit · `.vercelignore` |
| P1-1 | Overlapping hitstop freezes `Engine.time_scale = 0.25` | Refcounted `KiepieTime.trigger_hitstop()` / `reset_hitstop()` + `_exit_tree()` cleanup | `29f42e0` · `KiepieTime.gd`, `ArenaNet.gd`, `CombatController.gd` + `verify_combat.gd` |
| P1-2 | `Lobby.leave()` leaves `Match.lobby` stale (`is_playing() == true`) | Synchronous `Match.clear_lobby()` in `LobbyService.leave()` + `time_up` race guard | `29f42e0` · `MatchState.gd`, `LobbyService.gd` + `verify_match_rules.gd` |
| P1-3 | `TaloBackend` drops only partial frames after `leave_lobby_channel()` | Guard `leave_lobby_channel()` `_channel != null`, drop ALL frames when `_channel_id <= 0`, reconnect channel resync | `c64759f`, `1c133fd` · `TaloBackend.gd` + `verify_talo_backend.gd` |
| P1-4 | `MatchHud._name_for()` parse error (`Dictionary.new()`) + 60 Hz polling + unclosed victory splash | O(1) `Match.players.get()` lookup, `Settings.changed`-cached `_show_fps`, `__kiepieDropVictory()` on leave | `1c133fd` · `MatchHud.gd` |
| P1-5 | AOE weapons hit hidden/respawning bikes; unplaced `NetworkedBike` sits at origin on layer 1 | `not visible or get("is_respawning") == true` in Rocket/Meteor/FuelDrum; `NetworkedBike` starts on layer 0 until first live state | `a4cd1ea` · `RocketProjectile.gd`, `MeteorStrike.gd`, `FuelDrum.gd`, `NetworkedBike.gd` + `verify_deathrace.gd`, `verify_multiplayer.gd` |
| P1-6 | `RaceTracker` fails open when `issue_shot()` returns empty token | Explicit `if tok == "": _finishing_lap = false; return` before `register_lap` | `1c133fd` · `RaceTracker.gd` + `verify_deathrace.gd` |
| P1-7 | `VfxFactory` mushroom AABB clipping, Wilson ring & `smash_burst` reduced-motion leaks, uncapped damage numbers, orphan lights/casings | `mushroom_aabb`, reduced-motion guards, `MAX_DAMAGE_NUMBERS = 18` + outline fade, `_release_light()`, `casing` `queue_free()`, quality-scaled wreck/exhaust plumes | `a4cd1ea` · `VfxFactory.gd`, `RocketProjectile.gd`, `MeteorStrike.gd`, `Projectile.gd`, `BananaProjectile.gd`, `KiepieBike.gd`, `Pickup.gd` + `verify_vfx.gd` |
| P1-8 | `ArenaNet` non-orthonormal quaternion + unbounded per-peer rate maps | `.orthonormalized()` basis in `_send_state()`; erase departed peer IDs from all 5 tracking dicts in `_sync_roster()` | `1c133fd` · `ArenaNet.gd` |
| P2-1..5 | `SideCannons`/`VehicleRegistry` drift & `_process` raycast; desktop `AnalogSteer` hint overlap; `MobileTextInput` keyboard focus; `Settings` first-visit reduced-motion & reset timer race; unpinned CI | Unified `_profile_for()` + `_cooldown` getter/setter + pure-math reticle fallback; desktop `AnalogSteer` `-56px`; JS `input.blur()`; Web `matchMedia` seed; `_pending_writes.clear()` on defaults; `MainMenu._exit_tree()`; `FollowCam` `_safe_look_at` + child-cam shake; `PogoVisual` cached `_settings`; CI SHA-512 + commit SHA pin | `8b61c52` · `verify_accessibility.gd`, `verify_controls.gd`, `.github/workflows/gates.yml` |
| LIVE-1 | Live Chrome DevTools elevation pass: Web tofu boxes (`⚔`/`🏁`/`✓`/`▴`/`▾`/`■`), stretched & mobile-overflowing `MainMenu` card, `VfxFactory` freed-lambda errors, duplicate `self_respawn_at` connect, unpooled `Sfx` voices, chained drum cooldown, `qb_core.py` silent catches, missing `vercel.json` headers & duplicate viewport meta | Replaced all 6 unsupported glyphs + 6-scene fallback-font & `390px` mobile-fit gate in `verify_accessibility.gd`; centered `MainMenu` `Card` + wrapped `Subtitle`; `WeakRef` VFX timers; guarded `CombatController` signal; pooled 16×2D / 8×3D `Sfx` voices; chained `:c` drum burst in `TaloBackend`; `warnings.warn()` in `qb_core.py`; `vercel.json` COOP/COEP/security headers; `patch_web_html.py` + `check_web_hygiene.py` CI check | `61dacf2`, `acd44e2`, `baeee4a` + this commit |

## Audit remediation — 10 Principal Engineer (2026-11-18)

Source report: [audits/10 Principal Engineer.txt](audits/10%20Principal%20Engineer.txt)
(81 files audited, health score 78/100 at audit time).
Remediation commits: **`1494b0d`** (P0/P1 pass) + **`60a8b82`** (remaining verified
findings). Web re-export + deploy: **`f09c80e`**. Earlier surgical audit:
[kiepie-quad-surgical-audit-2026-11-18.md](audits/kiepie-quad-surgical-audit-2026-11-18.md)
(its regressions are locked by `verify_audit_regressions.gd`).

### Fixed — CI / deploy / PWA

| ID | Finding (severity) | Fix | Evidence |
| --- | --- | --- | --- |
| CI-1 | `mktemp -d` without parent dir crashes fresh runners (P0) | `mkdir -p "${TMPDIR:-/tmp}/opencode"` first | `1494b0d` · `run_gates.sh` |
| CI-2 | ubuntu-24.04 xvfb missing `xauth`/X11 libs (P0/P2) | apt install `xauth libgl1 libegl1 libxcursor1 libxinerama1 libxrandr2 libxi6` | `1494b0d` · `.github/workflows/gates.yml` |
| SW-1 | 70.8 MB double WASM download (P0) | `index.wasm` stripped from `CACHED_FILES`; `ENGINE_CACHE` seeded only when missing | `1494b0d` · `patch_web_sw.py` |
| DEP-1 | Unscoped git staging, no branch assert, staging races, live key left on disk (P0) | `flock`, clean `web/` staging, `main`-branch assert, `commit --only`, `settings.cfg` backup/restore trap | `1494b0d` · `deploy_web.sh` |
| BLD-1 | Awning material typo drops `awning_mat` on 4 TestRide buildings (P2) | `awning_mesh.material = awning_mat` | `1494b0d` · `build_testride.gd` |
| BLD-2 | Arena `HUD/Turbo` label baked but never updated (P1) | `MatchHud` drives visibility from `turbo_active` | `1494b0d` · `MatchHud.gd` |
| DX-1 | `_check_scripts.gd` orphaned; `screenshot.gd` hardcoded machine path (P2) | `check_scripts` gate added (24 → 25 gates); `res://`-derived renders path | `1494b0d` / `60a8b82` |

### Fixed — physics / vehicle

| ID | Finding (severity) | Fix | Evidence |
| --- | --- | --- | --- |
| PHY-1 | `center_of_mass_mode = AUTO` strips CoM −0.32 m from scene (P0) | `CENTER_OF_MASS_MODE_CUSTOM` serialized | `1494b0d` · `build_bike.gd` + `KiepieBike.tscn` |
| PHY-2 | Reverse-gear self-braking oscillation > 2.0 m/s (P0) | signed forward speed `dot(basis.z)` | `1494b0d` · `KiepieBike.gd` |
| PHY-1b | Frame-rate-dependent damping / righting step (P1) | `state.step`-scaled, frame-rate invariant | `1494b0d` · `KiepieBike.gd` |

### Fixed — netcode / backend

| ID | Finding (severity) | Fix | Evidence |
| --- | --- | --- | --- |
| NET-1 | Every kill re-emits `match_started`, wiping respawn countdown (P0) | transitions-only emission in `apply_lobby` | `1494b0d` · `MatchState.gd` |
| NET-2 | Dead bikes never broadcast `d:true` (P0) | visible early-return dropped | `1494b0d` · `ArenaNet.gd` |
| NET-3 | Twin-barrel rapid fire trips 12/s shot cap (P1) | cap raised to **24/s** (legit ≈ 22/s) | `1494b0d` · `ArenaNet.gd` |
| GAM-4 | Self-kill via drum grants killer rewards (P1) | `victim != own id` guard | `1494b0d` · `ArenaNet.gd` |
| NET-4 | Mid-match host leave strands guests 90–105 s (P1) | host-leave voids guests immediately | `60a8b82` · `TaloBackend.gd` |
| NET-5 | `join_by_code` skips liveness handshake; reconnect skips re-identify (P2) | fresh heartbeat + host ack; socket identification before "connected" | `60a8b82` · `TaloBackend.gd` |
| NET-6 | Transform relay out-of-order drift (P2) | monotonic tick, stale snapshots dropped (tolerates old peers). Residual: interpolation clamp → TS-005 | `60a8b82` · `ArenaNet.gd` / `NetworkedBike.gd` |

### Fixed — input / touch

| ID | Finding (severity) | Fix | Evidence |
| --- | --- | --- | --- |
| INP-1 | Emulated `MOUSE_LEFT` on `MOUSE_FILTER_IGNORE` fires cannons / starves auto-fire (P0) | physical-key-only manual fire while auto-fire enabled | `1494b0d` · `CombatController.gd` |
| INP-2 | Canceled touch leaks emulated pointer hold (P0) | `touch.canceled` releases paired pointer; `pointer_up` releases analog **and** button halves | `1494b0d` · `TouchCapture.gd` / `TouchControls.gd` |
| INP-3 | Opposing analog pad vectors latch turbo + move_back, cancelling drive (P1) | newest pad finger owns arbitration; stale opposing vector ignored; dual-touch regression assertions | `b35bae7` · `TouchControls.gd` + `verify_touch_multitouch.gd`; shipped in `a3ec39c` |
| INP-4 | Feature change: mobile GAS button + L/R dodge buttons + auto-fire replaced by a right analog | `AnalogDrive.gd` right pad: touch=gas, UP=manual fire, L/R=cartwheel; auto-fire + target scan deleted; real touch outranks emulated mouse | `this commit` · `AnalogDrive.gd` / `TouchControls.gd` / `CombatController.gd` / `TouchOverlayKit.gd` |

### Fixed — HUD / UI / lifecycle

| ID | Finding (severity) | Fix | Evidence |
| --- | --- | --- | --- |
| UI-1 | `announce()` tween snaps faded banner back forever (P0) | in-flight tween killed, text cleared | `1494b0d` · `MatchHud.gd` |
| UI-2 | `window.__kiepieVk.close()` missing (Back gesture) (P0) | `close()` exported | `1494b0d` · `MobileTextInput.gd` |
| MEM-1 | Dangling inline lambdas on persistent singletons (P1) | named handlers, disconnect in `_exit_tree` | `1494b0d` · `LobbyMenu.gd` / `SettingsMenu.gd` |
| GAM-2 | Dead bike stays a layer-1 obstacle; respawn skips physics reset (P1) | layers 0 while dead; upright `reset_bike()` respawn | `1494b0d` · `CombatController.gd` |
| GAM-3 | Projectile raycast self-hit tunneling (P1) | owner rid excluded | `1494b0d` · `Projectile.gd` |
| GAM-1a | Auto-fire spams indestructible buildings (P1) | `destructible` dropped from target list | `1494b0d` · `CombatController.gd` |
| GAM-1b | Lobby "Pickups" toggle never honored (P1) | `Match.pickups_enabled()` + `lobby_changed` re-apply | `1494b0d` · `Pickup.gd` |
| GAM-5 | Overdrive exhaust flames overwritten next frame (P2) | bike `overdrive_active` mirrors CombatController for full duration | `60a8b82` · `KiepieBike.gd` |
| VFX-1 | Muzzle holder freed at 0.14 s kills 0.75 s smoke (P1) | holder outlives smoke (0.9 s tree) | `1494b0d` · `VfxFactory.gd` |
| VFX-2 | Per-burst gradient/curve GPU uploads (P2) | ramps/curves cached by content | `60a8b82` · `VfxFactory.gd` |
| VFX-3 | Inconsistent `reduced_motion` shake guards (P3) | guarded at the sink: `FollowCam.add_shake` | `60a8b82` · `FollowCam.gd` |
| GAM-6 | World-space tire smoke ignores heading (P2) | smoke offset in bike space | `1494b0d` · `CombatController.gd` |

### Fixed — gate hardening (false-confidence gates)

| Gate | Fix | Evidence |
| --- | --- | --- |
| `verify_practice.gd` | real synthetic touch + mouse pairing; gas-only ⇒ 0 shots (no auto-fire), right-pad UP ⇒ continuous shots | `1494b0d` / `this commit` |
| `verify_settings.gd` | `reset_defaults` before default assertions | `1494b0d` |
| `verify_smash_impact.gd` | `up_after > 0.80` now asserted, not just printed | `1494b0d` |
| `verify_touch_multitouch.gd` | cancel tests include the paired emulated mouse; opposing-vector arbitration assertions (INP-3) | `1494b0d` / `this commit` |
| `check_scene_sync.py` | resource ids mapped to path/type identity, not collapsed to `X` | `1494b0d` |

### Verified not-applicable / historical

| Finding | Disposition | Evidence |
| --- | --- | --- |
| Showcase `.glb` duplication inflating pck (P3) | Root showcase files live **outside** the Godot project; `godot/assets/` holds exactly one runtime `Kiepie_Bike.glb` | `ls godot/assets/*.glb` (2026-11-19) |
| Monolithic merge diffs bypass review (P1) | Historical: PR #6 merge completed; keep future PRs under the review ceiling | process note |
| Client-authoritative scoring spoofing (P2) | Design constraint of Talo v1 (no SQL RPC). Mitigations: per-killer 1 s / 20 min caps, join/leave alias binding, score clamping, shot-payload validation | AGENTS.md · `TaloBackend.gd` |


## Feature — NARDUS pogo vehicle (renamed from PRINCESS) + TURBO banner removal (2026-11-19)

New vehicle, dealt randomly to every rider (nobody picks), plus removal of the TURBO
flash banner from both HUDs.

| ID | Change | Evidence |
| --- | --- | --- |
| POG-1 | `VehicleRegistry.gd`: deterministic vehicle draw (FNV-1a-32 hash of player id; high-middle-bit mixer — exact-integer audit: raw low bit ~50/50 over sequential Talo alias ids, so bit 15 is the robust bin; measured ~53% pogo over sequential ids, ~49% over random/uuid); mock-host, user-42 → QUAD; peer-1/2/3/5 → NARDUS; zero wire traffic; future vehicles extend the table | `godot/src/game/VehicleRegistry.gd` · `verify_pogo.gd` |
| POG-2 | Blender sculpt `src/build_pogo_nardus.py` + `src/gen_decal_nardus.py`: NARDUS — stylized smooth-shaded pogo brawler in a tight crimson-magenta athletic shirt with curved conformal gold **NARDUS** decal on the shirt back (image-texture, never text geometry), sporty shorts, symmetric arms, expressive face, consolidated multi-material meshes (47 → 18 draw calls), belly split into a `Belly` pivot | `Pogo_Nardus.blend` · `godot/assets/Pogo_Nardus.glb` (6.4 k verts, minZ = 0.000, 0 non-manifold) |
| POG-3 | Runtime swap in `KiepieBike._enter_tree` (parent-first): model shell swap, physics/wheels/mass/collision byte-identical to the bike; `PogoVisual.gd` cosmetic bounce + belly slosh + landing squash | `KiepieBike.gd` · gates unchanged (bike default under mock backend) |
| POG-4 | Weapons: profile-based `SideCannons` (`bike`/`pogo`) — banana projectile (`BananaProjectile.gd`, procedural crescent), 60 dmg (2× cannon), 0.40 s / 0.18 s rapid cooldown, `pop` SFX; remote/ArenaNet path applies the same profile by hash | `SideCannons.gd` · `BananaProjectile.gd` · `ArenaNet.gd` · `Sfx.gd` · `verify_practice/pogo` green |
| POG-5 | Remote proxies (`NetworkedBike.gd`) load the GLB for the peer's hashed vehicle (deterministic mix across peers) | `NetworkedBike.gd` · `verify_multiplayer` green |
| POG-6 | TURBO HUD flash banner removed from Arena + TestRide builders and runtime toggles in `Hud.gd`/`MatchHud.gd`; turbo mechanic, flames and FOV kick unchanged; scenes rebuilt (`.tscn` committed with builders) | `build_arena.gd` · `build_testride.gd` · rebuilt scenes · gates stay green |
| POG-7 | New gate `verify_pogo.gd` (26th gate): hash determinism, runtime swap, weapon profile, GLB integrity, ground datum | `godot/tools/verify_pogo.gd` · `.github/workflows/gates.yml` (via run_gates.sh) |

| Docs | Synced: README, SOURCE.md, AGENTS.md, project-plan constants (26 gates; QUAD/PRINCESS cooldowns) | this commit |

## Pending and blocked

| ID | Item | Status | Owner | Action needed |
| --- | --- | --- | --- | --- |
| TS-001 | **GitHub Actions billing lock** — every CI run fails at startup: "The job was not started because your account is locked due to a billing issue" (run [44373734263](https://github.com/TeacherEvan/kiepie-quad-web/actions/runs/44373734263), verified 2026-11-19). Code-side CI fixes (CI-1/CI-2) are already landed. | **BLOCKED — human action** | Evan | Resolve billing at github.com/settings/billing, then re-run the `gates` workflow (`workflow_dispatch`) and confirm 25/25 green on CI. |
| TS-002 | VFX ring-buffer pooling (audit P1) | Deferred — needs dedicated plan + Web frame-time profiling; pooling bugs are worse than allocation. Content-cache mitigation landed (`60a8b82`). | Evan / future plan | Profile WebGL frame times during sustained combat first. |
| TS-003 | HUD single signal bus (audit P2) | Deferred — no proven defect after UI-1/BLD-2; redesign, not a fix. | — | Revisit only if a desync is demonstrated. |
| TS-004 | Typed DTO wrappers for net/backend payloads (audit P2) | Partial — malformed shapes locked by `verify_audit_regressions.gd`; static typing refactor open. | — | Optional refactor; keep validation gates green. |
| TS-005 | Velocity-clamped dead reckoning / 250 ms interpolation buffer (audit P2 residual) | Partial — monotonic ticks + stale-drop landed (`60a8b82`); clamp not implemented. | — | Implement if rubber-banding is observed at 80–150 ms jitter. |
| TS-006 | Cannons vs destructible buildings | **Design decision** — auto-fire no longer targets indestructible shells (GAM-1a); whether cannons should smash buildings belongs to the owner. | Evan / Lea | Decide; then wire damage + gate. |
| TS-007 | Replace Yamaha-mark decals before commercial use | Standing constraint (portfolio use only meanwhile). | Lea | Swap `assets/decal_*.png`, rebuild, re-export. |

## Completed milestones

- [x] Single-repo merge (archived `kiepie-quad` → `kiepie-quad-web`), PR #6 — `839b21e`
- [x] Rollover immunity (lockout + righting spring), dodge Q/E, steering sensitivity — locked by `verify_rollover/dodge/controls`
- [x] Talo backend cutover + `protocol_version` handshake — `8d94cbb`
- [x] Surgical audit 2026-11-18 regressions locked — `verify_audit_regressions.gd`
- [x] 10-Principal-Engineer audit remediation — `1494b0d` + `60a8b82` + INP-3 arbitration (`b35bae7`), 25/25 gates
- [x] Web re-export + auto-deploy of remediated build — `f09c80e`, live HTTP 200
- [x] INP-3 arbitration re-export + auto-deploy — `a3ec39c`, live HTTP 200
- [x] Documentation sync (plan / index / task-status / README / AGENTS constants sweep) — prior milestone
- [x] Separate Backend & Frontend Principal-10 surgical audits + SARIF 2.1.0 — `0fe330a`
- [x] Backend surgical audit remediation (B-P0-1..2, B-P1-1..7, B-P2-1..5, B-P3-1; `PROTOCOL_VERSION = 2`, `MIN_LAP_SECONDS = 12.0`, separated `kills`/`laps`, heavy-weapon remote rate limits, SW timer/206 fix) — `a933f20`
- [x] Frontend surgical audit remediation (F-P0-1..2, F-P1-1..8, F-P2-1..9, F-P3-1..4; `DestructibleBuilding.smash(impulse)`, Death Race pit-launcher ramp rotations + outer loop aprons, checkpoint respawn preservation, zero-overlap HUD relayout, WebGL2 OmniLight budget `<= 8`, vertical-loop `FollowCam`, Victory Splash audio fallback/grace/a11y) — `f357883` + deploy `8046001`
- [x] Explosion VFX overhaul + Nardus v4.2 plastic-surgery sculpt & ballistic pogo animation (`VfxFactory.gd` turbulent fire/crater sprites, 3D plasma core, daylight alpha-blended fireball, velocity-aligned spark streaks, irregular shrapnel; `build_pogo_nardus.py` fuller fat silhouette + modular `Head`/`SpringCoil`/`StickUpper`/`StickLower` pivots; `PogoVisual.gd` 4 procedural animations with sub-stepped springs & `expDecay`) — this commit
- [x] Implementation plan: faster reversing (265.0), 1.5 s Rocket Launcher reload, victim-authoritative cross-player floating damage numbers (`"hurt"` wire event + attacker-side gold numbers + 280 ms dedup), rocket/meteor/death VFX upgrades (`particle_explosion` with 6-stage meteor mushroom cloud: Mach ground rings, 34-billow dust skirt, buoyant 3.2 s stem, delayed toroidal cap beats t=0.14/0.30 s, Wilson condensation ring at t=0.10 s; `dramatic_death_explosion`: 1.65× kill detonation + launch shockwave + tumbling cosmetic wreck `MAX_WRECKS=6` + two staggered cook-offs t=0.24/0.52 s), Nardus hot-pink Borat mankini sculpt (`MankiniPink` pouch/V-straps/shoulder straps/Y-back/gold O-ring/rear thong; `ButtCheekRed` cheeks; bare skin pelvis/torso/arms; 15 materials, 0 non-manifold, minZ = 0.000) — `66a1cf5`
- [x] WebGL/mobile polish, pooling & review-corrective hardening (`551c7ef..HEAD`): AOE/twin-barrel multi-kill sub-tokens, `NetworkedBike` death-lock, meteor/enemy-safe inward respawns, `844×390` landscape `MainMenu` fit, global `WeakRef` timer hygiene, local+remote primary projectile & muzzle flash pooling, mobile auto-glow disable, 3D spatial explosions, dynamic engine RPM pitch, elevated `dust_ring` landing dust, and regression gates (`ec1c69c..645058f`, `ff21fd3`)
