# Task 5 report — Touch overlay (surgical-orchestration, Step 1a single-scope)

## Delivered
- `godot/src/TouchControls.gd` (new) — CanvasLayer overlay. Drive buttons
  (◀/▶ steer · BRAKE · GAS · TURBO) visible on `DisplayServer.is_touchscreen_available()`
  or via manual **TOUCH** toggle (`TOUCH: ON`); toggle itself always visible.
  Hold-to-drive via `button_down`/`button_up` → `Input.action_press/release`
  (same InputMap actions as keyboard — no game-side changes). Stuck-key
  reconcile in `_process` releases a held action only if the button stopped
  being pressed (finger slid off) AND only for actions this layer pressed.
  `_release_all` releases only this layer's own pressed actions; `_exit_tree`
  releases everything held. HUD Restart covers reset (tap-friendly already).
- `godot/tools/build_testride.gd` — `_add_touch_controls(root)`: `TouchHUD`
  CanvasLayer (layer=2), bottom-corner anchored, 44px+ targets (82–118px
  long edge), `FOCUS_NONE`, ASCII `<`/`>` steer glyphs (U+2190 rendered as
  hexbox tofu with Godot's default font — replaced), right cluster sized to
  clear the left cluster at 390px. Rebuilt scene via builder only.
- `godot/tools/verify_touch.gd` (new) — 43 assertions, exit 1 on failure:
  presence/script/visibility auto-detect, FOCUS_NONE + ≥44px targets, action
  wiring both edges, stuck-key reconcile frees unpressed-held actions,
  keyboard-held actions untouched, TOUCH toggle force-show/hide + labels,
  hide/exit release-all, externally-held action survives first frames.

## Root cause worth recording
Godot 4.3 `_ready` is deferred past `add_child()` in tool scripts. An early
`Input.action_press("move_forward")` (truth_test pattern) was wiped by
TouchControls' first-frame `_apply_visibility()` → global `_release_all()`.
Bike sat pinned at z=8, TURBO 0, SPEED 3 km/h. Diagnosed via A/B scene
rebuild + instrumented one-off diagnostics (since deleted). Fix: release
only `_touch_pressed`-marked actions, tracked by this layer. Recorded in
AGENTS.md ("Godot 4.3 _ready in tool scripts").

## Verification
- Gates (headless): truth_test vel_z 11.67 m/s, MIN_UP 1.000; verify_touch
  0 failures; verify_features turbo 1.00 / flames / camera / smash 1-2-3 /
  DEBRIS 43; diag2 HUD counter; verify_smash_impact 0.999.
- Browser: both URLs live at 1280×800 (TOUCH: AUTO chip, no HUD overlap)
  and 390×844 (drive buttons hidden, console = 2 engine logs). Drive-button
  layout verified clean at 390px via a local force-overlay export
  (`_force := true`, /tmp only — never shipped).
- Deployed: 6069dcd then c00d16a (always-visible toggle fix); pushed to
  `TeacherEvan/kiepie-quad-web` main.

## Notes / rulings
- TOUCH toggle moved OUT of the auto-hide group after live check: hidden
  layer ⇒ unreachable toggle (self-defeating). Now always visible.
- Drive buttons auto-hide on non-touch; desktop users can force-show and
  play with mouse.
- Step 1a: no WORKER/VERIFIER fan-out; implementation direct, gates, then
  Step-5 dual-lane read-only review.
- Local `_force` hack used only for the /tmp screenshot; source restored
  to `_force := false` before export/deploy.
