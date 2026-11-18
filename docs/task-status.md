# Task Status — Kiepie Quad

Concrete done-vs-pending ledger. Companion to [project-plan.md](project-plan.md);
navigation in [index.md](index.md). Statuses are evidence-backed: commit hashes,
gate names, or live checks — not assumptions.

**Last verified:** 2026-11-19 — `scene_sync OK (6 scenes match HEAD)`, full gate suite
25/25 green after the INP-3 touch-arbitration fix (including three new assertions in
`verify_touch_multitouch.gd`); live site HTTP 200 on the `a3ec39c` auto-deploy, which
ships that fix. Previous deploy: `f09c80e`.

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
| `verify_practice.gd` | real synthetic touch + mouse pairing; aim-away ⇒ 0 shots, re-aim ⇒ auto-fire | `1494b0d` |
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
- [x] Documentation sync (plan / index / task-status / README / AGENTS constants sweep) — this commit