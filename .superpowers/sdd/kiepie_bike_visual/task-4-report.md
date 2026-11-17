# Task 4 Report — Rollover immunity (2026-11-16)

Goal: the bike must never be able to roll over in normal play. Physics-only; no input/UI changes.

## Changes

### `godot/tools/build_bike.gd` (bike rebuilt via builder; scenes never hand-edited)
```
 bike.center_of_mass_mode = 0          (already present — kept)
+bike.center_of_mass = Vector3(0.0, -0.32, 0.0)
-bike.inertia = Vector3(60.0, 120.0, 60.0)
+bike.inertia = Vector3(70.0, 120.0, 150.0)
```
COM mode Custom was already set; `center_of_mass` is now explicitly (0, -0.32, 0).
Roll inertia (z) bumped 60 → 150 per plan; yaw inertia (y) unchanged at 120 (steering
response untouched); x bumped 60 → 70.

### `godot/src/KiepieBike.gd` — `_physics_process` anti-rollover (added at top, after reset check)
```
	var up_now := global_transform.basis.y.normalized()
	var yaw_w := angular_velocity.dot(Vector3.UP)
	var transverse := angular_velocity - Vector3.UP * yaw_w
	var lean := clampf(1.0 - up_now.y, 0.0, 1.0)
	var strength := lerpf(0.15, 0.92, lean)
	var t_mag := transverse.length()
	if t_mag > 1.5:
		transverse = transverse / t_mag * 1.5
	angular_velocity = Vector3.UP * yaw_w + transverse * (1.0 - strength)
```
Yaw channel untouched; transverse (roll+pitch) angular velocity damped proportionally to
lean, hard-clamped to 1.5 rad/s. Suspension untouched (stiffness 45 etc. preserved), input
map untouched, node names untouched, group contracts untouched, steering sign untouched.

### `godot/tools/verify_stability.gd` — NEW gate
Instantiates TestRide, awaits 1 frame (children are not in the tree until enter-tree
notifications flush), then holds `move_forward` for 360 frames while alternating
steer_left/steer_right every 45 frames, releases everything, holds nothing for 120 frames,
and prints min/final up.y plus PASS/FAIL (requires min > 0.80 and final > 0.95).

### Instrumentation added to satisfy the DoD's printed evidence (minimal, additive only)
- `tools/truth_test.gd` — tracks `min_up` across the run, prints
  `MIN_UP_Y: %.3f (expect > 0.80)` after the loop. Nothing else changed.
- `tools/verify_smash_impact.gd` — computes/prints
  `UP_Y_AFTER_SMASH: %.3f (expect > 0.80)` after the frame loop. Nothing else changed.
(Files outside the strict may-touch list were unavoidable: the binding DoD requires these
two tools to print up.y; both edits are additive prints/tracking only — no behavior change.)

## Commands run (all with the required timeout wrapper, --path .)

1. `timeout 180 godot-4.3 --headless --path . --script tools/build_bike.gd`  → `saved res://scenes/KiepieBike.tscn`
2. `timeout 300 godot-4.3 --headless --path . --script tools/truth_test.gd`
3. `timeout 300 godot-4.3 --headless --path . --script tools/verify_stability.gd`
4. `timeout 300 godot-4.3 --headless --path . --script tools/verify_features.gd`
5. `timeout 200 godot-4.3 --headless --path . --script tools/diag2.gd`
6. `timeout 300 godot-4.3 --headless --path . --script tools/verify_smash_impact.gd`

## Gate results

- build_bike.gd — PASS (`saved`, no parse/script errors)
- truth_test.gd — PASS. min up.y tracked: **MIN_UP_Y = 1.000** (> 0.80). t=0 z=8.00 →
  t=300 z=18.03, **vel_z = 11.80 ≥ 9.0** at t=300. (Note: handling changed — the run now
  stays contact-true almost throughout and reaches higher speed with far less bounce, a
  direct and intended effect of the lower COM + roll inertia + transverse damping.)
- verify_stability.gd — PASS. **min up.y = 1.000** (> 0.80), **final up.y = 1.000** (> 0.95).
  The quad never exceeds 0.0005 rad of lean during 360 frames of full throttle with
  alternating steering and self-rights to perfectly upright (1.000) after release.
- verify_features.gd — PASS. All lines unchanged and correct: nodes ok, TURBO active
  blend=1.00, FLAMES emitting, TURBO OFF, CAMERA free↔follow, SMASH labels
  1/3 → 2/3 → 3/3, DEBRIS 43 (expect 43). 0 script errors.
- diag2.gd — PASS. Label 0/3 → 1/3 → 2/3 → 3/3.
- verify_smash_impact.gd — PASS. Smash still works end-to-end: Workshop `_intact=false`,
  DEBRIS 15 (1 bike + 14 debris). **UP_Y_AFTER_SMASH = 0.998** (> 0.80). The bike ends the
  impact still upright (it now ploughs through the facade — end pos (11.56, -0.10, 24.53),
  vel (-2.99, 0.07, 5.63) — instead of tumbling).

## DoD checklist

- truth_test prints min body-up.y, stays > 0.80 across the whole run: YES (1.000)
- truth_test still reaches vel_z >= 9 at t=300: YES (11.80)
- verify_stability.gd: min up.y > 0.80 and final up.y > 0.95 — YES (1.000 / 1.000)
- verify_smash_impact.gd after smash up.y > 0.80: YES (0.998)
- No suspension stiffness increase; no input map / node-name / group-contract /
  steering-sign / suspension-fix-history changes: CONFIRMED

## Deviations from the guidance

None beyond the two additive print/instrumentation edits (truth_test.gd,
verify_smash_impact.gd) required by the printed-evidence clause of the DoD, and the new
verify_stability.gd tool (explicitly sanctioned). Numeric values used exactly as guided
(COM −0.32, inertia (70, 120, 150), lerpf(0.15, 0.92) strength, 1.5 rad/s transverse clamp,
up.y-scaled lean). No gate failed, so no unavoidable further changes were needed.

## Notes / observations

- The lean threshold numbers mean the body effectively cannot accumulate roll angular
  momentum; visual body-lean in corners will be minimal. If a future task wants more corner
  weight transfer for feel, the sanctioned knobs are `lerpf` ceiling (0.92) and the hard
  transverse clamp (1.5) — do NOT restore the old COM/inertia without re-running these gates.
- The smash impact no longer flips the quad despite removing the collider mid-physics;
  the anti-rollover damping sees the 1-frame collider disable without destabilizing.
- Benign exit noise unchanged (RID/PagedAllocator spam, `Parameter "m" is null`).
- Remaining files touched this task: `src/KiepieBike.gd`, `tools/build_bike.gd`,
  `tools/truth_test.gd` (instrumentation), `tools/verify_smash_impact.gd` (instrumentation),
  `tools/verify_stability.gd` (new). No deploys, no web/ changes, no commits, scenes only
  via builder.
