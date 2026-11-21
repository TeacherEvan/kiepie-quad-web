# Surgical Audit Report: Kiepie Quad — Vehicle Controls, Steering & Death Race Handling

| Audit Metadata | Specification |
| :--- | :--- |
| **Audit Date** | 2026-11-22 |
| **Audited Scope** | Vehicle physics, steering, suspension, camera, touch input & Death Race track (`16` impl files, `4,700` effective LOC; `8` test files, `1,194` effective LOC; baseline `HEAD` `ba977bb`) |
| **Tech Stack & Runtime** | GDScript / Godot 4.3 (`gl_compatibility`, GodotPhysics3D 60 Hz `VehicleBody3D` + `VehicleWheel3D`), Web/Desktop/Mobile |
| **Baseline Audit SHA-256** | `ee75f863d0b77bc2` (verified zero-mutation prior to remediation) |
| **Pre-Fix Health Score** | **`51 / 100`** (`D_raw = 90`, `P_test = 7.97`, `M_kill = 46.9%`, **`CRITICAL`**) |

## Before / After Verified Telemetry (Godot 4.3, 60 Hz Physics)

| Probe Scenario | Before (`ba977bb`) | After (Remediated) |
| :--- | :--- | :--- |
| Flat ground `30 m/s`, gentle `5.3°` steer (`0.15`) `1.0 s` | `yaw = 254.8°`, `w = 7.55 rad/s`, `slip = 180.0°` | **`yaw = 22.3°`, `w = 0.38 rad/s`, `slip = 0.2°`, `air = 0`** |
| Flat ground `30 m/s`, `0.50` / `1.00` steer `1.0 s` | `231°–285°` spinout, `143°–180°` slip | **`68.3°` / `73.9°`, `w = 1.17 / 1.30`, `slip = 0.7° / 0.9°`** |
| `DeathRace.tscn` Turn 1 @ `26 m/s` (release at `85°`) | `yaw = -216.3°`, `slip = 180.0°` | **`yaw = -101.8°`, `slip = 11.9°`, `max_x = 51.1 m`** |
| `DeathRace.tscn` `TrackLoop0` @ `24–30 m/s` | Stalls at `10.3 m`, `end_up = -0.20` (flipped!) | **`max_y = 19.3 m`, `min_up = -1.00`, `end_up = 1.00`** |
| Stalled loop bailout (inverted at top, `1 m/s`) | Held upside-down (`up = -0.20`) | **Rights upright (`up = 0.99`)** |
| `move_back` + `steer_left` @ `30 m/s` (`0.75 s`) | Wrong-way `yaw = -16.1°`, `slip = 160.5°` | **`yaw = +43.7°` (turns left!), `slip = 1.5°`, `end_v = 17.1 m/s`** |
| Static spawn drop settle (`y = 0.6 -> 0.0`) | `2` bounces, `23` airborne ticks, `min_y = -0.303` | **`0` bounces, `0` airborne ticks, `min_y = -0.229`** |
| Overdrive + Turbo top speed | `48.7 m/s (175 km/h)` uncapped | **Capped `33.0 m/s` (`<= 39.0 m/s`)** |
| `FollowCam` @ `35 m/s` turn | `max_dist = 8.97 m`, `lag = 56.7°` | **`max_dist = 5.68 m`, `lag = 15.3°`** |

## Remediated Files

- `godot/src/game/VehicleHandling.gd` — Pure static handling, speed-steer taper, yaw/slip stability, progressive ABS braking & aero drag math.
- `godot/tools/build_bike.gd` (+ regenerated `godot/scenes/KiepieBike.tscn`) — Positive understeer CoM `(0, -0.28, 0.10)`, rear-biased grip (`3.8` F / `5.8` R), `2.2 / 2.8` suspension damping, `0.06` roll influence.
- `godot/src/KiepieBike.gd` & `godot/src/game/CombatController.gd` — Speed-sensitive steering, yaw/slip stabilizer, aero speed cap, non-stacking Overdrive, progressive ABS service brake (`S`) vs rear handbrake (`Space`), real `get_skidinfo()` tire smoke/SFX, early dodge landing recovery, loop stall bailout.
- `godot/src/game/LoopZone.gd` & `godot/tools/build_deathrace.gd` (+ regenerated `godot/scenes/DeathRace.tscn`) — Relocated `TrackLoop0`/`TrackLoop1` to `z = ±58.2` (zero straightaway intrusion), `40` low-friction `0.02` chords, helical guidance, moved `Ramp6`/`Ramp7` off corner apexes, widened pit ramps & double-sided landing ramps, added `SpeedLabel`.
- `godot/src/FollowCam.gd`, `godot/src/TouchControls.gd`, `godot/src/ui/MatchHud.gd`, `godot/project.godot` — Velocity-blended heading camera (`20/s`), `DODGE_ENGAGE = 0.66`, Death Race `SpeedLabel`, `0.15` input deadzones.
- `godot/tools/verify_controls.gd`, `verify_deathrace.gd`, `verify_stability.gd`, `truth_test.gd` — Tier-0/1/2 MVTH regressions locking all above invariants.
