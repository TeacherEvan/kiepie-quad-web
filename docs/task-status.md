# Task Status — Kiepie Quad

Concrete done-vs-pending ledger. Companion to [project-plan.md](project-plan.md);
navigation in [index.md](index.md). Statuses are evidence-backed: commit hashes,
gate names, or live checks — not assumptions.

**Last verified:** 2026-11-22 — `scene_sync OK`, `web_hygiene OK`, full gate suite **29/29** green after completing the 2026-11-22 Rev 2 Surgical Audit remediation.

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
