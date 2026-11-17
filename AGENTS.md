# AGENTS.md — Kiepie Bike / Kiepie Quad

Sport quad (Yamaha Blaster class) model + Godot 4.3 Web combat game.
This is a **Blender → Godot → Vercel** asset pipeline, not a normal code app.

## Boundaries (not what a first glance suggests)

- **Root `Kiepie bike/` is a git repo** (`TeacherEvan/kiepie-quad`), pushed to `main`.
  `web/` is a separate repo with its own history and is pushed independently. `.env` is ignored.
- `src/` — Blender `bpy` build scripts. `src/qb_spec.py` holds every master dimension;
  edit dimensions **only there**, then rebuild. Never hand-edit geometry in the Blender GUI.
  `src/qb_weapons.py` builds the side cannons; muzzle anchors are the `Cannon_Bore_*` meshes.
- `Kiepie_Bike.blend` is the source; `.glb` / `.stl` are exports. `QA_debrief*`, `renders/*`,
  `.blend1` and `spatial_manifest.json` are regenerable QA artifacts, never sources.
- `godot/` — Godot 4.3 project. All `.tscn` files are **generated** by `tools/build_*.gd`;
  never hand-edit a scene. Main scene is `scenes/MainMenu.tscn`.
- `godot/assets/sfx/` — generated WAVs + `generate_sfx.py`; edit the generator, not the WAVs by hand.
- `supabase/` — **retired** migrations from the abandoned Supabase plan. Keep for history only;
  they are not applied anywhere and both connected Supabase MCP projects are unrelated apps.
- Backend is **Talo** (scratch Supabase/Convex). `godot/addons/talo/` is a vendored **0.20.0**
  plugin — the last release compatible with Godot 4.3 (1.x needs 4.4+ and crashes the 4.3 editor).
  Never upgrade it without upgrading Godot first.
- `web/` — **separate git repo** `TeacherEvan/kiepie-quad-web` (now **public**, changed at the
  user's request on 2026-11-17). Contains only the Godot Web export + README.

## Commands that actually work

```bash
# Rebuild model + export .glb + previews
blender -b -noaudio -P src/build_quad.py

# Full model pipeline: rebuild → ground-seat → export .glb/.stl/.blend → round-trip verify
blender -b -noaudio -P src/repair_and_verify.py

# QA reviewer (reads .stl, emits sha256 debrief + 4-angle diagnostics)
blender -b -noaudio -P /home/leandi-duplessis/.config/opencode/skills/surgical-building/scripts/blender_qa_reviewer.py -- \
    Kiepie_Bike.stl spatial_manifest.json QA_debrief_stl.json
# Target: status APPROVED, non_manifold_edges == 0, minZ == 0.000

# All headless gates + GdUnit4; rebuilds all four scenes by default
bash godot/tools/run_gates.sh              # --no-build reuses scenes

# Compile-check every new script inside a real project run (autoload-aware)
godot-4.3 --headless --path godot -s tools/_check_scripts.gd

# Inject the Talo GAME key from repo-root .env into addons/talo/settings.cfg
python3 godot/tools/inject_talo_key.py

# Web deploy helper: gates → key → export → bundle checks (dry run)
bash godot/tools/deploy_web.sh
# …then commit/push web/, vercel deploy --prod, live curl check:
bash godot/tools/deploy_web.sh --apply

# Manual export only — the output path MUST be absolute:
godot-4.3 --headless --path godot --export-release "Web" "$PWD/web/index.html"
```

## Verification quirks

- `gdlint` / `gdtoolkit` are **not installed** in this environment — do not rely on them.
  `godot-4.3 --check-only --script <file>` reports false "Identifier not found" for autoloads;
  use `tools/_check_scripts.gd` instead.
- `run_gates.sh` runs **19 gates**: truth, stability, touch, features, smash_impact, diag2,
  cannons, settings, match_rules, combat, kill_flow, appeal, accessibility, talo_backend,
  audit_regressions, controls, dodge, vfx + GdUnit4. `audit_regressions` locks the surgical-audit
  defects: forged `state` events, 3-stop VFX gradients, exhaust axis, malformed shot arrays and
  `respawn_at` as a future deadline. `controls` locks the steering defect (see below) and the
  `steer_sensitivity` setting; `dodge` locks the Q/E leap/cartwheel contract. `vfx` locks the
  effect contracts (reduced motion, quality scaling, scorch/scar caps, flat hit normals) and
  level counts: Arena = 10 ramps / 7 buildings, TestRide = 6 ramps / 4 buildings, with spawn
  and ramp clearances. Keep all green.
  Exit 101 from GdUnit4 = pass with benign dummy-renderer orphan warnings; 100 = failure.
- `run_gates.sh` exports `KIEPIE_MOCK_BACKEND=1` — gates must never touch the live Talo account.
- Headless dummy-renderer RID/leak `ERROR:` lines at exit are benign; gates judge PASS/FAIL lines
  and script errors, not those.
- `verify_appeal.gd` tests the drum chain with a **wall-clock timer**, not frame counts —
  frame-count loops are flaky in headless runs.
- VFX live in `src/game/VfxFactory.gd`; the four VFX consumers are `CombatController`,
  `Projectile` (scenery impacts only — bikes/hazards already emit their own), `Pickup` and
  `DestructibleBuilding`. `KiepieBike.gd` adds landing/roost dust as visual-only hooks. The
  five sprite textures are generated at runtime by `prewarm()` — do not add image assets for
  effects; keep bursts inside `_q()` and reduced-motion guards. Scorch (`MAX_SCORCH = 12`) and
  bullet scars (`MAX_SCAR = 24`) leave their groups before `queue_free()` or the next frame
  still counts them against the cap. `-s` tool scripts must `load()` VfxFactory at runtime
  (a top-level `preload` fails autoload resolution — see `tools/verify_vfx.gd`).
- `godot/tools/gen_arena_textures.py` regenerates the three extra facades (garage, warehouse,
  depot); after changing it run `godot-4.3 --headless --path godot --import`, **not**
  `--editor --quit` (the latter crashes on the GdUnit4 plugin in this environment). Kerb
  walls are one striped mesh each (4 draw calls total) — do not revert them to 20 boxes.
  `tools/vfx_showcase.gd` renders five proof PNGs with `xvfb-run` under the real renderer.
- Blender MCP was connected on 2026-11-17 (Blender 5.3, add-on 1.8) — check `get_addon_status`
  before using it, but generate geometry through `src/` scripts. A GUI
  `read_factory_settings(use_empty=True)` unloads the add-on.

## Deploy / Web gotchas

- `web/` pushes do **not** auto-deploy (no Vercel hook). `deploy_web.sh --apply` does the
  commit + push + `vercel deploy --prod --yes --scope teacher-evans-projects` + live `curl`.
- The generated `index.service.worker.js` precaches a non-existent `index.worker.js` on
  single-threaded exports; `deploy_web.sh` patches it with `sed` after every export. Keep that.
- `export_presets.cfg` excludes `addons/gdUnit4/*, addons/GDQuest_GDScript_formatter/*, tests/*,
  extension_api.json` and **includes `addons/talo/settings.cfg`** — the export filter is
  `all_resources`, so a plain `.cfg` is otherwise dropped and the plugin silently falls back to
  MockBackend. Expect `web/index.pck` ≈ **3.8 MB** (~3.94 MB after the VFX pass); deploy
  aborts above 4 MB, so leave ~150 KB of headroom for new assets.
- The Talo **game** key (JWT, `eyJ…`) is injected from root `.env` `TALO_API_GAME` and ships in the
  public pck by design. `TALO_API_ADMIN` (`ta_…`) is rejected by the v1 API — never use it here.
- Vercel project `kiepie-quad-web` (team `teacher-evans-projects`, Hobby). Auth/password
  protection was disabled on purpose — don't re-enable.
- **Trademarks:** "BLASTER"/"GAMING" are Yamaha marks. The repo/site is now public for personal
  portfolio use; replace `assets/decal_*.png` before any commercial use.

## Model rules an agent will miss

- Scale is **photo-anchored, not factory** (±5–10 %): 22 in tyres, rim/tyre ratio ≈ 0.55,
  12 in steel rims w/ beadlock. Don't "fix" these from Yamaha spec sheets.
- `spatial_manifest.json` accuracy verdicts come from photo-derived RANSAC telemetry; the QA
  bbox tolerance (±2.5 %) is measured against them. Manifest width was recalibrated 1.66 → 1.48 m.
- Collections: `KiepieBike` → `KB_Body/KB_Frame/KB_Wheels/KB_Engine/KB_Controls/KB_Weapons`.
  Wheels roll on `Model/Wheel_*`, steering yaws `Model/Steer_FL|FR`; tooling breaks if renamed.
- Ground datum: `repair_and_verify.py` shifts the AABB bottom to `z = 0.000`. A raw
  `build_bike()` output fails `|minZ| <= 0.005` — always re-run `repair_and_verify.py`.
- Decals are **image textures**, never text geometry (text geometry caused 2,463 non-manifold
  edges). Swap `assets/decal_*.png` and rebuild.
- Muzzle anchors: use the `Cannon_Bore_L/R` meshes. The authored `Muzzle_L/R` empties also
  survive the glTF import (both are present in `KiepieBike.tscn`), but the bore meshes carry the
  exact barrel transforms and are the authoritative anchors.

## Godot architecture / conventions

- Autoload order matters: `Settings → Talo → Sfx → Supabase → Match → Lobby` (`project.godot`).
  The autoload is still **named `Supabase`** for callers/gates, but its script is now a facade over
  `TaloBackend.gd`; don't rename it without updating every `Supabase.*` call and gate.
- Main scene `MainMenu.tscn`; quick-join lands in `LobbyMenu.tscn`, and only the host pressing
  START calls `start_match`. Arena gameplay (firing + net sync) is gated on `Match.is_playing()`.
- `TaloBackend.gd` maps the old RPC names onto Talo: one **channel per lobby**, lobby state and
  roster JSON stored in **channel props** (only the host may `update` them), shots/kills/joins as
  `v1.channels.message` socket events. Scoring is **host-authoritative client logic** — Talo has
  no SQL RPC, so the old server-side anti-cheat validation is gone. Don't claim otherwise.
- Talo 0.20's `channels.update()` sends `props` as a Dictionary but the v1 API wants an **array**
  of `{key,value}`; `TaloBackend._apply_props()` bypasses it via `channels.client.make_request`.
- If `TALO_API_GAME` is absent or `KIEPIE_MOCK_BACKEND=1`, the facade uses `MockBackend`. Gates
  always take this path; the live Web build does not. The old Settings → Network URL/key fields
  were removed from the UI; the key comes from `.env` at build time. Lobby READY now goes through
  the `set_ready` RPC to the host-owned roster.
- Scene builders: `build_bike.gd`, `build_testride.gd`, `build_menus.gd`, `build_arena.gd`.
  Groups only persist through `PackedScene.pack()` with `add_to_group(name, true)`, and a child
  added to an instanced sub-scene must be owned by the **outer** root or it is dropped on pack.
- Control-UI skin lives in `src/ui/UiTheme.gd` (used by both `build_menus.gd` and `build_arena.gd`);
  add colours/styleboxes there, then rebuild the scenes. Godot 4.3 gotchas: `StyleBoxFlat` has no
  `detail_*` props, HSlider grabbers are ICONS not styleboxes, and a flat track needs content
  margins or the slider collapses to a bare dot.
- Local bike declares `player_id` (set by `CombatController`) — projectiles need it for hit
  attribution. `take_damage` lives on the `CombatController` **child**, not the bike body;
  `FuelDrum.ignite()` looks up that child and forwards the shot token so drum kills can score.
- Adding visual/audio nodes during a parent's `_ready` triggers "Parent node is busy setting up
  children"; `CombatController` defers underglow + engine audio with `call_deferred`.
- Tool/gate scripts run with `-s` cannot use autoload identifiers at compile time — fetch them
  with `root.get_node("Supabase")` and call via `.call()`/`.get()`.
- `add_child()` does not run `_ready` synchronously in tool scripts. A gate that calls
  `Input.action_press` right after `add_child` can have that press wiped by a deferred
  `_ready` calling `Input.action_release`. Game scripts must release **only actions they own**;
  `tools/verify_touch.gd` guards this ordering trap — keep it.

## Vehicle / gameplay conventions

- Forward axis is local **+Z** (positive `engine_force` drives +Z; GLB import already flips the
  Blender nose to +Z). FL/FR wheels at z = +0.68, rear at -0.66; chase camera is at
  `origin - basis.z * distance`. Don't re-flip without re-running `tools/truth_test.gd`.
- Anti-rollover damping MUST live in `KiepieBike._integrate_forces()` and damp only the
  roll/pitch part of `state.angular_velocity` (world-Y yaw about the bike's local up is left
  intact). Writing `angular_velocity` in `_physics_process()` clobbers the wheel-generated yaw
  before the solver step: the wheels reach full lock but the bike slides sideways without
  turning. `verify_controls.gd` locks this — keep it green.
- Steering respects `controls/steer_sensitivity` (0.3–2.0, slider in Settings → Controls);
  it scales both the max steer angle and the rate. The settings key was dead before it was wired.
- Q / E dodge: ground-only lateral leap + cartwheel (exports `dodge_lift/side/spin/duration/cooldown`
  on `KiepieBike.gd`). Anti-rollover damping is suspended for `dodge_duration` so the spin reads;
  a 0.12 s coyote timer stops suspension bounce from eating the input. No new net message is
  needed: `ArenaNet._send_state()` already broadcasts position + quaternion at 15 Hz, so remote
  proxies reproduce the cartwheel. `verify_dodge.gd` locks direction, lift, cooldown, recovery.
- Touch/mobile: `TouchControls.gd` wires every overlay button to its InputMap action, including
  `BtnDodgeLeft`/`BtnDodgeRight` → `dodge_left`/`dodge_right` (same leap as Q/E). Both builders
  add the dodge pair above the steering cluster; `verify_touch.gd` enforces >=44px targets and
  pairwise non-overlap (it caught an old 30px TURBO/BRAKE overlap in `build_arena.gd`).
  `controls/dodge_size` scales the dodge buttons (centred pivot) and `controls/touch_force`
  persists the manual TOUCH override; both are live in Settings → Controls. FIRE also scales
  from its centre so enlarging it cannot grow over the driving cluster.
- Headless physics proof: `godot-4.3 --headless --path godot --script tools/truth_test.gd`
  (0 → 9+ m/s, wheel contact). Feature checks: `verify_features.gd`, `diag2.gd`,
  `verify_controls.gd`, `verify_dodge.gd`.
- Buildings self-register in group `destructible` and call `HUD.register_smash()` directly
  (group lookup, `../HUD` fallback). Runtime `signal.connect()` in a builder is **not** persisted
  into `.tscn`. Emit `smashed` and update the HUD **before** spawning debris.
- Ramps: bike travels +Z, so the low edge faces -Z; plank tilt and stand stay on the high (+Z)
  side — see `_add_ramp` in `build_testride.gd`.
