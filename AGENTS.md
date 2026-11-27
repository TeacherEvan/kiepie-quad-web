# AGENTS.md — Kiepie Bike / Kiepie Quad

Sport quad (Yamaha Blaster class) model + Godot 4.3 Web combat game.
This is a **Blender → Godot → Vercel** asset pipeline, not a normal code app.

## Boundaries (not what a first glance suggests)

- **Single repository: `TeacherEvan/kiepie-quad-web`** (merged 2026-11-18). It holds the
  source tree at the repo root (`src/`, `godot/`, `assets/` …) **and** the Vercel-served Web
  build at the root (`index.html` / `index.wasm` / `index.pck` / …). `web/` is now only a
  local export staging folder and is git-ignored. `TeacherEvan/kiepie-quad` was archived
  (read-only) after the merge. `.env` is ignored.
- `src/` — Blender `bpy` build scripts. `src/qb_spec.py` holds every master dimension;
  edit dimensions **only there**, then rebuild. Never hand-edit geometry in the Blender GUI.
  `src/qb_weapons.py` builds the side cannons; muzzle anchors are the `Cannon_Bore_*` meshes.
- `Kiepie_Bike.blend` is the source; `.glb` / `.stl` are exports. `QA_debrief*`, `renders/*`,
  `.blend1` and `spatial_manifest.json` are regenerable QA artifacts, never sources.
- `godot/` — Godot 4.3 project. All `.tscn` files are **generated** by `tools/build_*.gd`;
  never hand-edit a scene. A `.tscn` diff alongside its `build_*.gd` is a rebuild artifact —
  regenerate and commit them together, never patch one by hand. Main scene is `scenes/MainMenu.tscn`.
- `godot/assets/sfx/` — generated WAVs + `generate_sfx.py`; edit the generator, not the WAVs by hand.
- `supabase/` — **retired** migrations from the abandoned Supabase plan. Keep for history only;
  they are not applied anywhere and both connected Supabase MCP projects are unrelated apps.
- `docs/` — `index.md` (navigation), `project-plan.md` (canonical plan + the single constants
  table), `task-status.md` (audit-remediation ledger with commit evidence), `audits/` (source
  reports). Sync them with every behavior/dependency change; sweep constants across README,
  AGENTS.md and docs in the same commit. `docs/.scratch-audit/` is git-ignored run scratch.
- Backend is **Talo** (scratch Supabase/Convex). `godot/addons/talo/` is a vendored **0.20.0**
  plugin — the last release compatible with Godot 4.3 (1.x needs 4.4+ and crashes the 4.3 editor).
  Never upgrade it without upgrading Godot first.
- **Web build** lives at the repository root and is what Vercel serves. Re-exporting
  overwrites it in place; commit the refreshed `index.*` files and push to `main`.
  `web/` remains a local staging dir only (git-ignored). `godot/tools/deploy_web.sh`
  remains the gated full path (gates → key → staging export → bundle check → sync →
  push → live curl); pushes to `main` auto-deploy to Vercel (verified 2026-11-18).

## Commands that actually work

```bash
# Rebuild model + export .glb + previews
blender -b -noaudio -P src/build_quad.py

# EVAN THE SKELETON (52-bone vehicle stand-in): rebuild .blend, GLB, STL + manifest
blender -b -noaudio --threads 4 -P src/build_evan_skeleton.py
# QA: blender -b -noaudio -P <surgical-building>/scripts/blender_qa_reviewer.py -- \
#     Evan_Skeleton.stl evan_spatial_manifest.json QA_debrief_evan.json

# NARDUS (pogo man) vehicle sculpt: rebuild Pogo_Nardus.blend + godot/assets/Pogo_Nardus.glb
blender -b -noaudio -P src/build_pogo_nardus.py

# Aston Martin ("BIG-BEN") F1 vehicle sculpt: rebuild Aston_Martin.blend + godot/assets/Aston_Martin.glb
blender -b -noaudio -P src/build_aston_martin.py

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

# Web deploy helper: gates → key → staging export to web/ → bundle checks (dry run)
bash godot/tools/deploy_web.sh
# …then sync web/ → repo root, commit index.*, push (Vercel auto-deploys), curl check:
bash godot/tools/deploy_web.sh --apply

# Manual export only — the staging path MUST be absolute:
godot-4.3 --headless --path godot --export-release "Web" "$PWD/web/index.html"
# then copy the bundle to the repo root, commit index.* and push.
```

## Verification quirks

- `gdlint` / `gdtoolkit` are **not installed** in this environment — do not rely on them.
  `godot-4.3 --check-only --script <file>` reports false "Identifier not found" for autoloads;
  use `tools/_check_scripts.gd` instead.
- `run_gates.sh` runs **33 gates**: truth, stability, touch, features, smash_impact, diag2,
  cannons, settings, match_rules, combat, kill_flow, appeal, accessibility, talo_backend,
  audit_regressions, controls, dodge, rollover, vfx, practice, multiplayer, pogo, aston, evan, evan_weapons, deathrace, check_scripts + `touch_multitouch` (runs under xvfb, not headless —
  synthesized touch needs a real window) + GdUnit4 + `scene_sync` (tracked `.tscn` must equal
  the builders' output modulo resource-id churn; hand edits to generated scenes fail loudly) + `web_hygiene` (`check_web_hygiene.py`). `audit_regressions` locks the surgical-audit
  defects: forged `state` events, 3-stop VFX gradients, exhaust axis, malformed shot arrays and
  `respawn_at` as a future deadline. `settings` locks `Settings` v2 defaults (`video/fullscreen = true`),
  persistence, quality presets, reset, `v1 -> v2` fullscreen migration, and `SettingsMenu.tscn`'s
  default toggle state. `controls` locks the steering defect (see below) and the
  `steer_sensitivity` setting; `dodge` locks the Q/E leap/cartwheel contract. `vfx` locks the
  effect contracts (reduced motion, quality scaling, scorch/scar caps, flat hit normals) and
  level counts: Arena = 10 ramps / 7 buildings, TestRide = 6 ramps / 4 buildings, with spawn
  and ramp clearances. `touch_multitouch` locks two-thumb driving (raw screen-touch indices
  own independent actions, refcounted holds, paired emulated-mouse double-handling, desktop mouse
  clicks, and real touches outranking the emulated mouse on the same pad) plus `TouchCapture`
  `MOUSE_FILTER_IGNORE` pass-through so `HUD/RestartBtn`, `HUD/ViewBtn`,
  `TouchHUD/BtnTouchToggle`, and keyboard `R` resets work cleanly.
  `practice` locks practice-mode cannons: TestRide's bike continuously fires via desktop hold-to-fire
  AND the mobile right-analog UP gesture with zero overheat and NO auto-fire (`overheated`/`heat_changed`
  & `HUD/HeatBar`/`HUD/HeatLabel` removed), `MenuBtn` exists, `RestartBtn` recovers dead riders, and
  no network kill broadcast happens in practice. `multiplayer` locks remote-player proxy spawning,
  visibility, and streamlined Arena HUD layout (`ArenaNet._create_remote()` uses `StaticBody3D`/`NetworkedBike.gd`,
  surface-override mesh tinting, `CollisionShape3D` + `Label3D` Nameplate, distinct per-peer
  `SpawnPoint` spreading, `TaloBackend` `"bike_state"` wire separation, 50%-smaller corner
  `HealthBar`, subtle `"x/y"` corner `Banner`, collapsible `ScoreToggle`->`Scoreboard` dropdown, and
  both analog pads). Keep all green.
  Exit 101 from GdUnit4 = pass with benign dummy-renderer orphan warnings; 100 = failure.
- `run_gates.sh` exports `KIEPIE_MOCK_BACKEND=1` — gates must never touch the live Talo account.
  Backend-touching gates additionally hard-abort (`quit(2)`) if the mock is not active, instead of
  relying on this env export alone; gate timeouts are enforced via `timeout` (150/240 s) and the
  xvfb leg fails loudly when `xvfb-run` is missing. `verify_settings.gd` wraps itself in a
  `user://settings.cfg` backup/restore; other gates restore captured priors rather than hardcoded
  defaults. `godot/reports/` is gitignored (untrack with `git rm -r --cached godot/reports`).
- Combat scoring hardening (post-audit): TaloBackend applies a per-killer 1 s cooldown and a
  20/min window to `register_kill` (client-minted shot tokens cannot be issuance-bound on Talo v1;
  rate is the only server-side lever), and `join`/`leave` socket messages are bound to the sender's
  alias with score/row clamping. ArenaNet drops non-finite, far-off-origin, oversized-direction and
  >24/s shot payloads, and CombatController never names an attacker the lobby doesn't know.
- Headless dummy-renderer RID/leak `ERROR:` lines at exit are benign; gates judge PASS/FAIL lines
  and script errors, not those.
- `verify_appeal.gd` tests the drum chain with a **wall-clock timer**, not frame counts —
  frame-count loops are flaky in headless runs.
- VFX live in `src/game/VfxFactory.gd` and are used broadly: `CombatController`, `SideCannons`
  (muzzle flash/casings), `Projectile` (scenery impacts only — bikes/hazards already emit their
  own), `Pickup`, `DestructibleBuilding`, `FuelDrum`, `NetworkedBike` and `KiepieBike.gd`
  (landing/roost dust hooks). The seven sprite textures (`soft`, `streak`, `flare`, `ring`,
  `smoke`, `fire`, `scorch`) are generated at runtime by `prewarm()` — do not add image assets for
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

- Pushes to `main` DO auto-deploy (verified 2026-11-18: each merge to `main` triggered a
  Production deployment in ~5 s). `deploy_web.sh --apply` remains the full/gated path
  (export → bundle check → push → deploy → live curl).
- `patch_web_sw.py` patches `index.service.worker.js` after every export: strips the
  non-existent `index.worker.js`, stores `index.wasm` in a content-hashed `ENGINE_CACHE`
  that survives `.pck` updates, uses Cache-First within each content-hashed `CACHE_NAME` for
  `index.pck`, and Network-First with a 2.5 s timeout fallback for `index.html`/`index.js`.
- `export_presets.cfg` excludes `addons/gdUnit4/*, addons/GDQuest_GDScript_formatter/*, tests/*,
  extension_api.json, reports/*, tools/*, docs/*, .env*` and **includes `addons/talo/settings.cfg`** — the export filter is
  `all_resources`, so a plain `.cfg` is otherwise dropped and the plugin silently falls back to
  MockBackend. `html/head_include` carries the fullscreen-on-launch bridge
  and the web-shell splash: inline CSS/JS injecting `#splash` (autoplay-muted
  `web-assets/kiepie-quad-splash.mp4` (desktop, 1280x720) or
  `web-assets/kiepie-quad-splash-portrait.mp4` (portrait, 720x1280), selected before loading by
  screen orientation; click/touch/`Esc`/`Space`/`Enter` skip,
  plays on every launch (no localStorage suppression or query-param override), instant removal under
  `prefers-reduced-motion`). Root `index.html` ships the identical markup and the preset
  embeds it, so re-exports keep it. `web-assets/` (dashboard background + splash) lives
  **outside** `godot/` so the pck stays small — do not move those files into `godot/assets/`.
  (`window.__kiepieSetFullscreen`) that `Settings.gd` drives via `JavaScriptBridge` on Web
  (fullscreen is now default-on; `Settings` schema v2 migrates v1 configs) — don't clobber it
  when editing the preset. Expect root `index.pck` ≈ **4.5–4.7 MiB** (after Evan's biomechanical running GLB + Lea Unicorn's non-Draco GLB) (`web-assets/kiepie-quad-splash.mp4` ≈ **1.82 MiB** and `web-assets/kiepie-quad-splash-portrait.mp4` ≈ **1.38 MiB**, 15-second editions; ≈ **3.20 MiB** combined); `deploy_web.sh` aborts above **5.0 MiB** (raised from 4.5 MiB on 2026-11-25),
  so check the printed size after adding assets (and update the script's expected-size note if it changes).
  Root `.vercelignore` uses a strict allowlist (`*`, `!index.*`, `!favicon.ico`, `!web-assets/`,
  `!web-assets/**`) so only Web runtime assets ship to Vercel (never `docs/`, `src/`, `godot/`,
  `renders/`, `.blend`/`.stl`, or `vercel.json`). Root `vercel.json` supplies edge security +
  native `COOP`/`COEP`/`CORP` headers (`same-origin` / `require-corp`) and immutable `/web-assets/*`
  caching; `patch_web_html.py` consolidates exported `index.html` to a single accessible viewport
  meta (no `user-scalable=no`); `check_web_hygiene.py` locks all four checks (including every-launch splash) in CI.
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
  Every lobby is stamped with a **`protocol_version` channel prop** (`PROTOCOL_VERSION`,
  wire protocol `3`). Peers mismatched on the version are never mixed into a lobby:
  `join_auto` skips those channels (`is_channel_joinable`), `join_by_code` reports a version
  error. Bump `PROTOCOL_VERSION` only on a wire-breaking change (message kinds, prop keys,
  token semantics) — it is not a content semver.
- Talo 0.20's `channels.update()` sends `props` as a Dictionary but the v1 API wants an **array**
  of `{key,value}`; `TaloBackend._apply_props()` bypasses it via `channels.client.make_request`.
- If `TALO_API_GAME` is absent or `KIEPIE_MOCK_BACKEND=1`, the facade uses `MockBackend`. Gates
  always take this path; the live Web build does not. The old Settings → Network URL/key fields
  were removed from the UI; the key comes from `.env` at build time. Lobby READY now goes through
  the `set_ready` RPC to the host-owned roster.
- Scene builders: `build_bike.gd`, `build_testride.gd`, `build_menus.gd`, `build_arena.gd`, `build_deathrace.gd`.
  Groups only persist through `PackedScene.pack()` with `add_to_group(name, true)`, and a child
  added to an instanced sub-scene must be owned by the **outer** root or it is dropped on pack.
  But do **not** re-own the nodes *inside* an imported GLB instance (`find_children` + `owner=`):
  that serializes ~200 duplicate meshes + inline `ArrayMesh` data into the scene (was 2.87 MB of
  ASCII in `KiepieBike.tscn`, double geometry at runtime). Runtime lookups (`Model/Wheel_*`)
  resolve through the instance — see the NOTE in `tools/build_bike.gd`.
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

- **Aston Martin ("BIG-BEN") F1 vehicle** — third playable vehicle in `VehicleRegistry.gd` (`VEHICLE_ASTON = &"AstonMartin"`, `"BIG-BEN F1"`, `res://assets/Aston_Martin.glb`). Players can either let `VehicleRegistry` deal from the 3-vehicle FNV-1a-32 hash pool (`AUTO (DEAL)`) or pick their preferred ride in `MainMenu` (`VehicleSelect`, persisted in `Settings` `gameplay/vehicle` and synced in lobby `join`/roster rows). `src/gen_plate_bigben.py` → `assets/plate_bigben.png` + `src/build_aston_martin.py` → `Aston_Martin.blend` + `godot/assets/Aston_Martin.glb` (177 KB, `minZ = 0.000`, `non_manifold_edges = 0`). Uses `Steer_FL/Wheel_FL`, `Steer_FR/Wheel_FR`, `Wheel_RL`, `Wheel_RR`, `AstonMuzzle_L/R` (`"F1 AUTOCANNON"`), and `Exhaust_Tip`. **The body shell is lifted `BODY_LIFT = 0.06` in `src/build_aston_martin.py`** (chassis min_y ≈ 0.076, wheels stay at 0.000) — its old diffuser sat ~0.016 m off the deck and visibly dragged under braking; never lower it back or re-home the wheels. Suspension rods are deliberately excluded from the lift. `verify_aston.gd` locks the GLB, this clearance, runtime swap, steering/wheel pivots, `CASH BAG LAUNCHER` (NARDUS alone uses `CIGAR LAUNCHER`), and MainMenu selector.
- **NARDUS pogo vehicle** — second playable vehicle in `VehicleRegistry.gd` (`VEHICLE_POGO = &"PogoNardus"`, `"NARDUS"`, `res://assets/Pogo_Nardus.glb`). Players can either let `VehicleRegistry` deal from the 3-vehicle FNV-1a-32 hash pool (`AUTO (DEAL)`, with roster-level guaranteed Nardus assignment via `VehicleRegistry.for_player_in_roster`) or pick their preferred ride in `MainMenu` (`VehicleSelect`). `KiepieBike.gd` swaps the visual shell in `_enter_tree` (parent-first, so CombatController caches the post-swap muzzle anchors); physics, wheels, mass and collision are identical to the bike. `SideCannons` `PROFILES` is keyed `bike` / `pogo` / `aston`.
  - `Pogo_Nardus.blend` → `src/build_pogo_nardus.py` → `godot/assets/Pogo_Nardus.glb`
    (never hand-edit; the back-print decal is generated via `src/gen_decal_nardus.py` →
    `assets/decal_nardus.png`). NARDUS wears a hot-pink Borat mankini with cute, plump,
    slightly red butt cheeks flanking the rear thong strap; the back-print is framed by the
    mankini Y-back. GLB layout uses modular articulated pivots: `Rider/` (`RiderBody`,
    `Belly`, `Head`, `Arm_L`, `Arm_R`, `NardusDecal`) and `Stick/` (`StickLower`, `SpringCoil`,
    `StickUpper`, `BananaMuzzle_L`, `BananaMuzzle_R`). `src/game/PogoVisual.gd` drives 4 procedural
    animations (`Idle_Breathe`, two-phase ballistic `Locomotion_Hop` with live spring compression &
    telescoping upper stick, airborne `Jump_Arc` + heavy touchdown slam, and `Action_TurboFlap`
    symmetric wing-flap + banana recoil) using sub-stepped secondary springs (`MAX_FRAME_DT = 0.1`,
    `MAX_SUB_DT = 0.00833`) and `expDecay`. Weapon is bananas (`BananaProjectile.gd`, procedural
    crescent; 60 dmg, 0.40 s / 0.18 s rapid, `pop` SFX) — twice the cannon damage at half the rate.
    `vehicle_profile` on `KiepieBike.gd` carries `bike|pogo|aston`; `SideCannons` PROFILES is
    keyed `bike`/`pogo`/`aston`.
  - `verify_pogo.gd` locks assignment determinism, roster-level guaranteed Nardus assignment (`VehicleRegistry.for_player_in_roster`), identical vehicle stats, the runtime swap, modular pivots (`Rider/Head`, `Stick/StickLower|SpringCoil|StickUpper`), live `SpringCoil` compression & `Head` follow-through, shoulder-pivoted `Rider/Arm_L` & `Rider/Arm_R` bird-wing flapping during turbo, weapon profile and the pogo ground datum (minZ = 0.000).
  - `verify_deathrace.gd` locks Dashboard Battle Royale (default) & Death Race mode selection, `DeathRace.tscn` 550.6 m B-spline circuit with Serpent Esses, Furnace Bend, Canyon Switchback, and Victory Carousel physical chevron turn boards, continuous mitered jersey barriers (`BarrierConcrete` + `BarrierTopRail`), curved split pit lane, 2 loops with aprons/backstops, collision walls plus containment walls, 250×210 ground (with `LoopZone` centripetal adhesion, 3 molten hazard pits, 8 jump ramps, pickups, 4 ordered checkpoints, checkered `FinishLine`, `RaceTracker` lap counter, and `web-assets/kiepie-victory-splash.mp4` victory splash), NaN-basis/void-fall/sky-launch/respawn-order regressions, plus Rocket Launcher (1.5s cooldown, **instant kill on direct hit via `CombatController.take_lethal_hit()`, flat 90% health loss across the 4.5m blast — no falloff**; NARDUS launches a massive `Cigar` mesh, BIG-BEN a cash bag, Quad a finned rocket; `RocketProjectile.BLAST_DAMAGE = 90.0`), Meteor Shower (6.0s cooldown, 3D ground aiming reticle, 2.0s sky-fall delay, massive 3.5× AOE damage), `HUD/ReloadBar` & `HUD/WeaponLabel` reload status, and mobile right-analog-back weapon switching. **Known limitation (victim authority):** a direct hit is resolved by the victim's own client raycast into its local bike; the shooter's raycast hits a lagged `NetworkedBike` proxy. At long range/interpolation skew the two can disagree and the victim survives at 10 HP. An attacker-asserted lethal wire event was deliberately rejected — it would let a forged packet kill any player. The direct-hit token uses the `"<base>:v<victim>"` sub-token form so a same-shot AOE multi-kill cannot lose the lethal kill to the host's 1 s rate limiter.
- **EVAN THE SKELETON** — fourth playable vehicle, **preference-only**: `VehicleRegistry.VEHICLE_EVAN = &"EvanSkeleton"` is selected in MainMenu and synced via the lobby row but is NOT in `VEHICLES`. Do not add him to the FNV deal pool: `(h >> 12) % N` would change the `mock-host`/`peer-N`/`user-42` fixtures locked by `verify_pogo.gd` and `verify_aston.gd`. Source `src/build_evan_skeleton.py` -> `Evan_Skeleton.blend` + `godot/assets/Evan_Skeleton.glb` + `Evan_Skeleton.stl` + `evan_spatial_manifest.json`. **Export without Draco** — this Godot 4.3 build has no `KHR_draco_mesh_compression` importer (all other vehicle GLBs are plain too). Runs **purely on foot** (no tyres or quad chassis) with anatomical flared bones, open laughing mandible, two-tone magenta/dark punk mohawk, double-cutaway hot-pink guitar, leather strap, and trailing cable. The GLB has 52 joints + 7 NLA clips (`Idle_Sway`, `Play_Strum` biomechanical running stride, `Headbang_Riff` turbo sprint, `Action_BigFinish` mid-air scissor-kick leap, `Run_NoGuitar` sprinter arm-pumping while guitar is thrown, `Action_GuitarThrow`, `Action_GuitarCatch`); glTF import nests meshes under `EvanRig/Skeleton3D`, so resolve anchors with recursive `find_child()` (already done by `KiepieBike._find_model_node()`). `EvanVisual.gd` is attached to the GLB root and drives speed-coupled running playback (including reverse backpedaling), sub-stepped landing squash/recoil springs, `expDecay` sprint lean/bank, footstep dust kicks, `on_boomerang_thrown()`/`on_boomerang_caught()` held-guitar visibility + throw/catch animation sync, and `trigger_recoil()` (heavy specials only, never hijacking primary fire). Finger phalanx cylinders are deliberately shortened 10% — coincident cap rings weld into non-manifold edges on STL round-trip. Weapons: `SoundWaveProjectile.gd` (pink sound-wave primary), `BoomerangGuitar.gd` (horizontal frisbee-spinning double-cutaway out-and-return guitar with 3-ray blade sweep, owner throw/catch sync, and early-catch cooldown refund), `DevilHandStrike.gd` (towering vertical ground-erupting 3-joint clawed demonic hand with hell-portal, pulsing glowing veins, curved obsidian fingernails with crimson cuticles, dorsal tendons, palm pads, and crushing fist yank) + `CombatAoe.apply_lethal_blast()` (instant-kill ground hand). Wire kinds stay `"primary"`/`"rocket"`/`"meteor"` so `PROTOCOL_VERSION` remains 3; only the visuals and Evan's resolver differ.
- **LEA UNICORN** — fifth playable vehicle, **preference-only** like Evan: `VehicleRegistry.VEHICLE_LEA = &"LeaUnicorn"` is selectable in MainMenu and synced in lobby rows, but NOT in `VEHICLES` (the FNV deal pool must stay at three vehicles or every locked hash fixture changes). Source `src/build_lea_unicorn.py` → `Lea_Unicorn.blend`, `godot/assets/Lea_Unicorn.glb`, `Lea_Unicorn.stl`, `lea_spatial_manifest.json`; 52-joint winged-equine rig, 4 clips (`Idle_Breathe`, `Locomotion_Gallop`, `Action_WingSpread`, `UnicornBoom_Flight`), plain non-Draco GLB, minZ 0.000. Landmarks `HornTip`, `HornBase`, `HornMuzzle_L/R`, `Wing_L/R`, `ManeForelock`, `TailRoot`, `Eye_L/R`, `Hoof_FL/FR/RL/RR` are resolved recursively (skinned meshes nest under `LeaRig/Skeleton3D`). `LeaVisual.gd` drives speed-coupled gallop, reverse backpedal, charge wing-spread and the boom flight clip. Weapons: `HornBoltProjectile.gd` (rapid gold horn sparks), `HornBeam.gd` (0.55 s particle vortex then a 0.35 s straight plasma/laser beam with lethal direct hits via victim authority), `UnicornBoom.gd` (wing-spread + leaping flight, `CombatAoe.apply_lethal_blast()` kill zone). Wire kinds remain `primary`/`rocket`/`meteor`, so `PROTOCOL_VERSION` stays 3. `verify_lea_unicorn.gd` + `verify_lea_unicorn_weapons.gd` lock the contract.
- Forward axis is local **+Z** (positive `engine_force` drives +Z; GLB import already flips the
  Blender nose to +Z). FL/FR wheels at z = +0.68, rear at -0.66; chase camera is at
  `origin - basis.z * distance`. Don't re-flip without re-running `tools/truth_test.gd`.
- Anti-rollover damping MUST live in `KiepieBike._integrate_forces()` and damp only the
  roll/pitch part of `state.angular_velocity` (world-Y yaw about the bike's local up is left
  intact). Writing `angular_velocity` in `_physics_process()` clobbers the wheel-generated yaw
  before the solver step: the wheels reach full lock but the bike slides sideways without
  turning. `verify_controls.gd` locks this — keep it green.
- Rollover immunity lives there too (merged from the live branch): a near-total roll/pitch
  angular-velocity lockout (yaw untouched) plus an active righting spring — rotates the chassis
  about the tilt axis (y × world-UP) toward level, ~3° deadzone, effort scales with lean and is
  capped per physics step; fully-inverted antiparallel fallback rotates about a horizontal
  side/forward projection. Both are suspended mid-dodge (the cartwheel IS roll).
  `verify_rollover.gd` locks it — keep it green.
- Steering respects `controls/steer_sensitivity` (0.3–2.0, slider in Settings → Controls);
  it scales both the max steer angle and the rate. The settings key was dead before it was wired.
- Q / E dodge: ground-only lateral leap + cartwheel (exports `dodge_lift/side/spin/duration/cooldown`
  on `KiepieBike.gd`). Anti-rollover damping is suspended for `dodge_duration` so the spin reads;
  a 0.12 s coyote timer stops suspension bounce from eating the input. No new net message is
  needed: `ArenaNet._send_state()` already broadcasts position + quaternion at 15 Hz, so remote
  proxies reproduce the cartwheel. `verify_dodge.gd` locks direction, lift, cooldown, recovery.
- Practice mode (TestRide) carries the full combat kit: the bike gets a `CombatController`
  child with `practice_mode = true` (works without an arena lobby; desktop continuous hold-to-fire,
  skipped while hovering a HUD `BaseButton`, and mobile right-analog UP manual fire work standalone,
  while network kill broadcasts and the match gate are skipped — the local death/respawn flow still
  works). `verify_practice.gd` locks streamlined touch controls (no
  `BtnFire`/`BtnTurbo`/`BtnBrake`/`BtnGas`/L-R dodge buttons), `MenuBtn`, desktop hold-to-fire,
  mobile UP-to-fire with NO auto-fire, no overheat/HUD heat bar, offline drum/rider damage, and
  `RestartBtn` recovery from death.
- Cannon cooldown & restart: `SideCannons.gd` has **no overheat mechanic or `HeatBar`** (shots
  are strictly cooldown-gated at `0.20s` normal / `0.09s` rapid; `heat_changed` and `HUD/HeatBar`
  were removed). `KiepieBike.reset_bike()` (called by `HUD/RestartBtn`, `R` / `reset_bike`, and
  `Hud._unhandled_key_input`) uses `PhysicsServer3D.body_set_state(...)` plus an
  `_integrate_forces` `_pending_reset` latch because writing `VehicleBody3D.global_transform` from
  GUI button callbacks gets overwritten on the next physics sync step; `Hud._on_restart()` also
  calls `CombatController.reset_state()`.
- Touch/mobile: `TouchControls.gd` + `TouchCapture.gd` implement real two-thumb multi-touch with
  **two runtime-created analog pads** — `AnalogSteer.gd` (left: steer, push-forward turbo,
  pull-back brake/reverse) and `AnalogDrive.gd` (right: a resting finger holds `move_forward`,
  push-UP holds fire, push L/R triggers a one-shot dodge with return-to-centre re-arm).
  The old `BtnGas` and `BtnDodgeLeft/Right` ("L"/"R") buttons are GONE from both builders.
  The capture is a full-rect `MOUSE_FILTER_IGNORE` `Control` reading `_input()` (with
  `make_input_local`) so it never swallows HUD buttons on lower CanvasLayers or earlier
  siblings (`BtnTouchToggle`, `MenuBtn`, `RestartBtn`); both pads are `MOUSE_FILTER_IGNORE`
  views hit-tested per `InputEventScreenTouch.index` — mouse emulation is a shared pointer and
  cannot drive two actions at once, which is why this layer exists. Holds are refcounted
  (touch + the deterministically paired emulated-mouse stream share symmetrical +1/-1), and
  a real touch always outranks the emulated mouse on the same pad (browsers that stop emitting
  mouse-motion during a drag would otherwise freeze the pad). **Auto-fire is removed**:
  `CombatController` polls `TouchControls.is_fire_held()` rather than the `fire` InputAction
  (emulated `MOUSE_BUTTON_LEFT` is bound to it and would free-fire). Physical F still works;
  plain left-mouse fire is only available when the overlay is OFF (on a touch-capable laptop
  where it auto-shows, use F or the right pad's UP gesture).
  Both builders add `MenuBtn` (`Main Menu`) on `HUD` (`FOCUS_NONE`), paired with Android/Web Back
  (`NOTIFICATION_WM_GO_BACK_REQUEST` + `popstate`) + Esc handling.
  `verify_touch.gd` enforces >=44px non-overlapping pads and the gas/fire/dodge gestures, and
  `verify_touch_multitouch.gd` (runs under xvfb) locks the multi-touch contract, including
  newest-real-touch arbitration (no stuck turbo+move_back or fire+dodge pairs).
  `controls/dodge_size` (now scales the right pad), `steer_sensitivity` and `controls/touch_force`
  are live in Settings → Controls.
- Headless physics proof: `godot-4.3 --headless --path godot --script tools/truth_test.gd`
  (0 → 9+ m/s, wheel contact). Feature checks: `verify_features.gd`, `diag2.gd`,
  `verify_controls.gd`, `verify_dodge.gd`.
- Buildings self-register in group `destructible` and call `HUD.register_smash()` directly
  (group lookup, `../HUD` fallback). Runtime `signal.connect()` in a builder is **not** persisted
  into `.tscn`. Emit `smashed` and update the HUD **before** spawning debris.
- Ramps: bike travels +Z, so the low edge faces -Z; plank tilt and stand stay on the high (+Z)
  side — see `_add_ramp` in `build_testride.gd`.
