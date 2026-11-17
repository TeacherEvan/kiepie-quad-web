# Kiepie Bike — Sport Quad (ATV)

A fully procedural, game-ready 3D model of a blue **sport quad** (Yamaha Blaster class),
modelled from reference photographs in this folder, and packaged for **Godot 4.3** as a
physics-driven vehicle, alongside the original Blender scene for editing.

Procedural means every part is an organised, named object built from a small dimension
spec (`src/qb_spec.py`) — there is nothing sculpted-by-hand to drift out of alignment, and
the whole bike can be rebuilt from scratch with one script.

| Reference photos | |
| --- | --- |
| `photo_2026-11-16_12-17-03.jpg` | rear 3/4 view, left side |
| `photo_2026-11-16_12-17-16.jpg` | front 3/4 view, left side |

---

## Quick facts

| | |
| --- | --- |
| Type | Yamaha Blaster-class sport quad (ATV) |
| Length (with bumper) | 2.14 m |
| Width (across fenders) | 1.48 m (slim photo-matched fenders) |
| Height (to handlebar) | 1.08 m |
| Wheelbase | 1.34 m |
| Track, front / rear | 1.09 / 1.15 m |
| Tyres | 22 in all four, rim / tyre ratio ≈ 0.55 (12 in steel, beadlock ring) |
| Built by | procedural Blender 5.3 `bpy` scripts, Blender 5.3.0 |
| QA status | **APPROVED** (surgical-building QA reviewer, see below) |
| Godot | 4.3, `VehicleBody3D` + 4 `VehicleWheel3D` (rollover-immune) |

---

## Package contents

| File / folder | Purpose |
| --- | --- |
| `Kiepie_Bike.blend` | The full Blender scene (bike + studio lighting + camera) |
| `Kiepie_Bike.glb` | glTF export for engines — 1.50 MB |
| `Kiepie_Bike_draco.glb` | Draco-compressed export — ~465 KB |
| `Kiepie_Bike.stl` | STL (proves watertightness; used by QA) |
| `spatial_manifest.json` | QA manifest (photo-derived camera telemetry + target dims) |
| `QA_debrief_stl.json` | Official QA reviewer report — **APPROVED** |
| `src/` | Reproducible Python build scripts (`qb_spec.py` holds master dimensions) |
| `godot/` | Godot 4.3 project: `MainMenu.tscn` (boot) + `Arena.tscn`, `TestRide.tscn`, `KiepieBike.tscn` |
| `assets/` | Decal + facade/asphalt/cone textures baked into the export |
| `renders/` | Preview renders (Blender workbench/EEVEE + Godot screenshots) |
| `README.md` | This file |

---

## Opening the Godot project

Requirements: **Godot 4.3** (`godot-4.3`).

1. `File ▸ Open Project…` → select the `godot/` folder.
2. Press **F5**. (Main scene is `scenes/MainMenu.tscn`; choose **Practice** to drive the
   `TestRide.tscn` demo pad.)

Controls:

| Key | Action |
| --- | --- |
| `W` / `↑` | Throttle (4-wheel drive) |
| `S` / `↓` | Brake → reverse |
| `A` / `D` (or `←`/`→`) | Steer |
| `Space` | Handbrake |
| `Shift` | **Turbo** — hold while throttling: +30 % power, flames from the silencer, "TURBO" flash on the HUD |
| `C` | Camera — chase ↔ free orbit (drag mouse / wheel to zoom) |
| `Q` / `E` | Dodge left / right — lateral leap + cartwheel to evade attacks (ground-only, 1 s cooldown) |
| `R` | Reset to spawn (also the on-screen **Restart** button) |
| Touch | On-screen overlay (◀ ▶ steer · **DODGE L/R** · BRAKE · GAS · TURBO · FIRE) auto-appears on touch devices; the **TOUCH** button (top-right) force-shows/hides it anywhere. Dodge/FIRE button sizes and steering sensitivity are adjustable in Settings → Controls |

`TestRide.tscn` is the playable practice pad: asphalt, cone ring, start line, six **ramps**
(including a cone-clearing jump line with a landing slope), four **smashable buildings**
(drive into them at speed — they burst into debris and an on-screen counter tracks it),
a follow camera, working **practice cannons** (F / Fire button — no lobby required, no
network kill broadcasts) and a HUD with speed readout, smash counter,
turbo indicator and Restart / View buttons. Rollover-immune physics (lowered center of
mass + angular damping) — the quad cannot flip. It is a placeholder — build your real
track in it or as a sibling scene.

### Wiring the bike into your own track

1. Build your track into a scene.
2. Instance `scenes/KiepieBike.tscn`.
3. Give the track `StaticBody3D` colliders (your track meshes) — the wheels are raycasts,
   so they grip any physics surface.
4. For custom sound/HUD/AI, edit `godot/src/KiepieBike.gd` (throttle, brake, steering) and
   `godot/src/FollowCam.gd` (chase camera).

### How the bike is wired for driving

`scenes/KiepieBike.tscn` is a `VehicleBody3D`:

- **Model:** instanced GLB — `Model/Bike_Root/...`, materials preserved.
- **Wheels:** `VehicleWheel3D` node per wheel (`WheelFL`…`WheelRR`), positioned on the real
  axle lines; front pair steers, all four drive.
- **Visual steering:** `Model/Steer_FL` / `Model/Steer_FR` pivots yaw the front wheel
  meshes; `Model/Wheel_*` meshes roll about their axle.
- **Suspension & stability:** raycast suspension tuned for a 185 kg quad; center of mass pulled down + inertia/angular damping — rollover impossible (verified: up.y stays 1.0000 through full-throttle weaving and exits the building smash at 0.998).
- **Decals:** image-textured quads, not geometry text.

Physics is verified headless: `godot-4.3 --headless --path godot --script tools/truth_test.gd` — settles on its tyres and accelerates 0 → 9.5 m/s in 5 s; `tools/verify_features.gd`, `tools/verify_stability.gd` and `tools/verify_smash_impact.gd` cover turbo, camera, rollover immunity and smash.

---

## Rebuilding the bike from source

Requirements: Blender 5.3 (`/snap/bin/blender`) or a Blender 5.3 with the MCP add-on;
Python 3.11+ for the venv helper you choose.

```bash
blender -b -noaudio -P src/build_quad.py           # rebuild, .blend, .glb and preview renders
blender -b -noaudio -P src/repair_and_verify.py    # full pipeline: .blend, .glb, .stl, round-trip verify
```

- `src/qb_spec.py` — every master dimension (tyre radius, rim radius, axle heights…)
- `src/qb_wheels.py` — tyres (knobby block tread), rims, beadlock rings, brakes, suspension
- `src/qb_body.py` — frame, fenders, seat, lights, controls, image-textured decals
- `src/qb_engine.py` — engine, cylinder + fins, CVT, belt, sprocket, exhaust, radiator
- `src/qb_core.py`  — scene purge, materials, mesh builders, decal-plane helper
- `src/build_quad.py` — assembly, studio lighting/camera, export, previews

To change a dimension: edit `qb_spec.py`, re-run, re-export.

---

## Model integrity / QA

Run through the `surgical-building` QA reviewer (headless Blender, `-b -noaudio`):

```
status: APPROVED
non_manifold_edges: 0
measured_bounds: 1.477 m (w) × 2.144 m (d) × 1.077 m (h)   (slim photo-matched fenders)
ground datum: minZ = 0.000 m (gate |minZ| ≤ 0.005 m)
payload_sha256: 14475f6dfd44e5e315126ff7342813681588c56526278863102ada896bc48f40
```

Every mesh is a closed (watertight) 2-manifold. The QA STL has ~22 k vertices / ~44 k triangles.

Re-run it yourself:

```bash
blender -b -noaudio -P /home/leandi-duplessis/.config/opencode/skills/surgical-building/scripts/blender_qa_reviewer.py -- \
  Kiepie_Bike.stl spatial_manifest.json QA_debrief_stl.json
```

Diagnostics: `QA_debrief_stl_front_0.png`, `…_right_90.png`, `…_top_ortho.png`, `…_iso_45.png`.

---

## Accuracy — where it's solid, where it's approximate

**Solid (anchored to the photos / object class):**

- Rim / tyre ratio measured from both photos ≈ **0.55** → 12 in rims, **22 in** tyres, both axles
- Tyre geometry: tall sidewalls, staggered block tread, shoulder lugs
- Silhouette, stance, fender arcs, handlebar sweep, seat shape — visually verified against both photos
- Beadlock bolt-ring count and wheel material match the reference (dark steel + alloy ring)

**Approximate:**

- Absolute dimensions are **class-anchored, not photogrammetrically triangulated** —
  the two photos are oblique 3/4 views, insufficient for SfM reconstruction. The photos were not
  shot for measurement. Treat overall length/width/height and wheelbase as **≈ ±5–10 %**.
- Engine internals (cam cover, carb position, intake routing) are stylized, not a copy of the
  real part-number assembly; the real Blaster's cylinder leans forward and intake snorkel rises
  on the right side — both are represented, though not to factory dimensions.
- Decals are original-ish graphics approximating the reference photos; they are not the
  manufacturer's actual trade dress.
- Suspension travel/spring rate are tuned for driving feel, not measured from the photo.

If you want metrology-grade reference, you need a 3/4 set of orthographic-elevation photos, or a
turntable video — the current photos can't give it.

---

## Development

```bash
bash godot/tools/run_gates.sh              # rebuild all scenes + all headless gates + GdUnit4
bash godot/tools/run_gates.sh --no-build   # reuse generated scenes

# Compile-check scripts inside a real project run (autoload-aware):
godot-4.3 --headless --path godot -s tools/_check_scripts.gd
```

`gdlint` / `gdtoolkit` are not installed here — do not rely on them. `godot-4.3 --check-only`
also reports false "Identifier not found" errors for autoloads; use `_check_scripts.gd`.

GdUnit4 v5.1.1 (Godot 4.3-compatible) unit tests live in `godot/tests/`.
See `AGENTS.md` for toolchain details and exporter gotchas.

## Known limitations / roadmap

- Front suspension is fixed; steering rotates the wheel meshes only (no tie-rod articulation).
- No rider, no saddle animation, no engine sound, no swingarm animation.
- Buildings restack as static decor — demolition is once per run (no respawn).
- No factory Yamaha dimensions were used (none were provided); everything stays within
  ±10 % of the photos.
- Draco `.glb` exports retain normal-buffer sizes to stay cheap; re-baking texture compression
  (KHR_texture_basisu) would shrink further.
- The STL QA export removes ~24 degenerate triangles on import (an STL artifact; the
  `.blend` itself is clean — 0 non-manifold edges).

---

## Editing the bike

- **Materials:** all on the `Paint_*` / `Engine_*` / `Chrome` / `Matte` / `Tyre_*` nodes in
  `src/qb_core.py`.
- **Pivots:** wheels roll on `Model/Wheel_*` about local X; steering yaws `Model/Steer_FL`,
  `Model/Steer_FR` about local Y. Do not parent them to each other — parent them to
  `Model/Bike_Root` (or `KiepieBike`).
- **Decals:** image quads (`Decal_BLASTER_*`, `Decal_GAMING_*`). Swap in `assets/decal_*.png`
  and re-export.

---

## Trademarks / licence

`BLASTER`, `GAMING` and the Yamaha motorcycle/ATV trade dress belong to Yamaha Motor Co., Ltd.
This asset is for **private / portfolio** use and as a placeholder for your own branded vehicle.
Do not distribute commercially without replacing the decals and renaming the vehicle.

---

## File map

```
Kiepie bike/
├─ Kiepie_Bike.blend        # Blender scene (bike + studio)
├─ Kiepie_Bike.glb          # glTF 2.0, ready for engines (~1.50 MB)
├─ Kiepie_Bike_draco.glb    # Draco-compressed (~0.48 MB)
├─ Kiepie_Bike.stl          # for QA / 3D-print proofing (~2.2 MB)
├─ spatial_manifest.json    # QA manifest
├─ QA_debrief_stl.json      # QA reviewer verdict (APPROVED)
├─ assets/                  # decal textures baked into the export
├─ src/                     # Python build scripts (bpy)
├─ godot/                   # Godot 4.3 project (open this to drive it)
│  ├─ scenes/               # generated by tools/build_*.gd — never hand-edit
│  │  ├─ MainMenu.tscn      # boot scene
│  │  ├─ LobbyMenu.tscn, SettingsMenu.tscn, Arena.tscn
│  │  └─ TestRide.tscn, KiepieBike.tscn
│  ├─ src/                  # gameplay GDScript (core/, game/, net/, audio/, ui/)
│  └─ tools/                # scene builders + 17 gates + GdUnit4
└─ renders/                 # all preview renders
```

---

Built procedurally with Blender 5.3 + Godot 4.3. Rebuilt from scratch on every release.

---

## Multiplayer combat + mobile Web (new)

The game now boots into a **Main Menu** with `Practice` (the original free-ride/smash track),
`Create Lobby`, `Join Auto`, `Join by code` and `Settings`. `Join Auto` finds a waiting lobby
with a free slot and creates one if none exists.

**Combat:** the Blender-authored twin side cannons fire with **F / left mouse / the touch FIRE
button**. Each bike has 100 armour; the host-configured damage default is 30 per hit, cannons
overheat if held down, and a destroyed bike explodes and respawns at a random spawn point after
the lobby's respawn delay. The shooter scores the kill; first to the lobby's kill target wins.
The arena (~100 m) has cover, ten ramps (two designed gap-jump lines plus two cover hops),
seven destructible buildings, an outside-the-walls venue silhouette with floodlights, a radar
and an off-screen-free scoreboard/kill feed.

**Backend:** **Talo** (Supabase/Convex were dropped). A free Talo game key is injected at build
time from `TALO_API_GAME` in the repo-root `.env` via `godot/tools/inject_talo_key.py`; the
deploy helper does this automatically. The Web build ships that key inside the public pck by
design — use a disposable, scoped dev key, never `TALO_API_ADMIN`. Lobbies are Talo channels,
state lives in host-owned channel props, and shots/kills flow over channel socket messages.
Scoring is host-authoritative client logic (no server-side validation). Without a key the client
uses a full offline `MockBackend`, so all 21 gates run without credentials. The old `supabase/`
migrations are retained for history only and are not deployed.

**VFX pass:** effects are built by `godot/src/game/VfxFactory.gd` from five tiny sprites
generated once at runtime (soft puff, spark streak, flare star, ground ring, noise smoke),
so the Web pck does not grow. Explosions are staged (core flash → fireball → ember streaks →
rising smoke, with cooling debris and a soft scorch), shots that hit scenery leave sparks and
fading scars, and building smashes combine a glass flash, ground dust wave and staggered
collapse puffs. Ramp landings and fast cornering kick up dust; shields, pickups and landed
hits all have their own read. Everything scales with the particle-quality setting and
collapses to static cues under reduced motion. Decal counts are capped so long fights cannot
leak nodes. The three extra facades are deterministic: re-run
`python3 godot/tools/gen_arena_textures.py` and `godot-4.3 --headless --path godot --import`
after changing them.

**Appeal pass:** 8 rotating pickups (shield / rapid-fire / repair / overdrive), 10
chain-exploding fuel drums, a full procedurally synthesised sound pack (cannon,
impacts, explosion, pickups, turbo, kill sting, engine loop), camera shake and
recoil, 60 ms hit-stop on kills, kill-cam spectating of your killer, floating
damage numbers, hurt vignette, tyre smoke, scorch decals, coloured underglow on
every bike, streak callouts ("RAMPAGE x3") and host-authoritative match time limits.

**Mobile Web:** responsive landscape layout, safe-area-aware HTML shell, installable PWA,
real two-thumb multi-touch (gas/boost/steer work simultaneously via per-finger input
tracking — not the single emulated mouse pointer) and an analog steering pad feeding
proportional steer strength, large touch controls and quality presets
(low/medium/high) that scale particles, shadows and resolution. Settings persist in
`user://settings.cfg` and can be restored to defaults.

**New gates:** `verify_cannons.gd`, `verify_settings.gd`, `verify_match_rules.gd`,
`verify_combat.gd`, `verify_kill_flow.gd`, `verify_appeal.gd`, `verify_talo_backend.gd` and
`verify_audit_regressions.gd`, `verify_controls.gd` and `verify_dodge.gd` join the existing
suite — `godot/tools/run_gates.sh` now runs 21 gates offline (19 headless gates plus GdUnit4
and one xvfb-windowed multi-touch gate, `verify_touch_multitouch.gd`).
The new `verify_practice.gd` locks practice-mode cannons (no lobby required, FIRE
wired for touch, real input-driven projectile spawn).
The new `verify_vfx.gd` locks effect contracts (reduced motion, quality scaling, decal caps,
flat-normal safety) and the new arena/test-track ramp and building counts with spawn clearance.
The new gates exercise `TaloBackend` directly with no live account, lock the surgical-audit
regressions (forged state, VFX gradient stops, exhaust axis, malformed shot payloads, respawn
deadline), prove that steering actually yaws the bike while keeping it upright, and lock the
Q/E dodge (direction, lift, cooldown, recovery). `godot/tools/deploy_web.sh` runs the gates, exports, checks the bundle,
then (with `--apply`) commits, pushes and deploys to Vercel.
`xvfb-run -a godot-4.3 --path godot --script tools/vfx_showcase.gd` re-renders five VFX/layout
proof images into `renders/` under the real Web renderer (not a gate).

Web export produces `web/index.pck` (~3.8 MB; the bundle check aborts above 4 MB) plus PWA
manifest/service worker; deploy with the documented `vercel deploy --prod` command (pushes to
`web/` do **not** auto-deploy).
