## Task 4 — Rollover immunity (implementer)

Goal: the bike must not be able to roll over in normal play. Physics-only change, no input/UI.

Binding definition of done:
- `tools/truth_test.gd` prints min body-up.y and it stays > 0.80 across the whole run, and
  the run still reaches vel_z >= 9 at t=300.
- New `tools/verify_stability.gd`: instantiate TestRide, hold move_forward via Input.action_press
  for ~360 frames while alternating steer_left/steer_right every ~45 frames, then release, and hold
  nothing — requires min up.y > 0.80 and final up.y > 0.95 (self-rights). Print both values.
- `tools/verify_smash_impact.gd` rerun — after the smash, up.y > 0.80.
- Physics feel kept sane: do not raise suspension stiffness (would undo the pogo fix); lowering COM
  + inertia + angular damping are the sanctioned levers. No new input actions, no HUD removals.

Implementation guidance (not binding): build_bike.gd already sets center_of_mass_mode = 0 (Custom) —
add `bike.center_of_mass = Vector3(0, -0.32, 0)` and bump roll inertia (e.g. inertia Vector3(70, 120, 150));
in KiepieBike.gd add to _physics_process: compute up := basis.y.normalized(); yaw_w :=
angular_velocity.dot(Vector3.UP); transverse := angular_velocity - Vector3.UP*yaw_w; strength scales with
(1 - up.y) clamped to [0.15, 0.92]; angular_velocity = UP*yaw_w + transverse*(1-strength); ALSO hard-clamp
transverse magnitude <= 1.5 rad/s. Do not touch yaw response, steering, or wheel params.
Rebuild, gates, append report to task-4-report.md. Do not deploy/commit/spawn subagents.
