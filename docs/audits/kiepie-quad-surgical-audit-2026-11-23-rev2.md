# Surgical Audit Remediation Report (Rev 2) — Kiepie Quad

**Date:** 2026-11-23  
**Baseline:** `1950439` (`79 / 100 MODERATE`, `P0=0, P1=6, P2=9, P3=5`, `M_kill=64.29% (36/56)`)  
**Post-Remediation:** `100 / 100` (`P0=0, P1=0, P2=0, P3=0`, `M_kill=100.00% (56/56)`)

## Strictly-Green Commit Series (`origin/main..HEAD`)
1. `c9c423f` — `refactor(core): split VfxFactory and add CombatAoe, TaloProtocol, UiTheme.apply_safe_area`
   - Split `godot/src/game/VfxFactory.gd` (1,681 LOC → 205-line facade) into acyclic `VfxSprites.gd` → `VfxCore.gd` → `VfxHeavy.gd`.
   - Extracted `CombatAoe.gd`, `TaloProtocol.gd`, and `UiTheme.apply_safe_area()`.
2. `04ccd5a` — `fix(audit): remediate Rev 2 P1/P2/P3 defects, wire shared helpers & add MVTH gates`
   - Closed all P1/P2/P3 defects, wired `FuelDrum.gd` to `CombatAoe.apply_blast()` and `TaloBackend.gd` to `TaloProtocol` (`sanitize_join_row`, `build_prop_array`, `prune_rate_window`), removed dead `_arena_net`/`_note_local_damage_shown` helpers.
   - Added MVTH regression tests for `P1-3` (channel/lobby swap), `P1-5` (reduced-motion ring-sprite & `MegaBolt` teardown), `P2-3` (`particles=0.0` across `RocketProjectile`, `MeteorStrike`, `DestructibleBuilding`), `P2-4` (`MatchHud.compute_fps_pos` across `667×375`, `844×390`, `390×844`, `1280×720`), and `P2-5` (`last_auth_error` on `MainMenu`).
3. `099bddb` — `perf(web): compress splash video (<1.9 MiB), cache-bust assets & bound victory video`
   - Re-encoded `web-assets/kiepie-quad-splash.mp4` from `1950439` at `-crf 28 -preset slow` (`3,637,270` B → `1,817,879` B / `1.73 MiB`, `-50.0%`).
   - Verified `index.pck = 3,740,304` bytes (`< 4,194,304` B cap) and `web_hygiene OK`.

## Verification Ledger
- `bash godot/tools/run_gates.sh`: **PASS — all 29 gates green** (`scene_sync OK`, `web_hygiene OK`, `touch_multitouch` xvfb `0 failure(s)`, `gdunit` `6/6` passed, `_check_scripts.gd` `47/47` loaded).
- `bash godot/tools/deploy_web.sh` (dry-run): **`web bundle complete`**, `index.pck: 3740304 bytes`.
