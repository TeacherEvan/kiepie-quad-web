## Task 2 — Code review of the visual diff (reviewer)

Review the plastic-surgery visual-overhaul diff across:
- `godot/tools/build_testride.gd` (builder patch + helper funcs)
- `godot/tools/build_bike.gd` (no changes this phase — check nothing broke)
- `src/qb_body.py` (fender reshape, number plates — from earlier phase, unchanged now)
- `godot/src/Hud.gd`, `godot/src/FollowCam.gd`, `godot/src/DestructibleBuilding.gd`
- `godot/assets/tex_*.png` (only verify they exist; do not judge binary)

Focus: spec compliance (Global Constraints above), GDScript parse safety, Godot 4.3 API
correctness (StyleBoxFlat/theme override calls, `uv1_scale`, `load()` in SceneTree tools),
material/geometry sanity (no unbounded repeats, no black faces), HUD built-node names still
matching `Hud.gd` (`Speed`, `Smashed`, `Turbo`, `RestartBtn`, `ViewBtn`, `Help`), no scene
node renames, no behavior changes. Flag anything that would crash, misrender, or regress play.

