## Task 1 — Rebuild + fix the visual builder patch (implementer)

State: a Phase-3 patch was applied inline to `godot/tools/build_testride.gd` (tactile chips
for HUD labels, `_chip()/_button_style()/_style_button()` helpers, button min-height 44px,
window offsets updated, asphalt texture with `uv1_scale=(210,210,1)`, cone band texture,
building facades via `_facade_texture_for()` (Workshop→tex_facade_workshop.png,
Shed→tex_facade_shed.png, Store→tex_facade_store.png), awning box on each building,
ramp-stripe emissive, lighting: ambient energy 0.68, sky contribution 0.62, fog 0.00125,
exposure 1.18, sun energy 1.75, shadow distance 150). Textures already copied into
`godot/assets/` (`tex_asphalt.png`, `tex_cone.png`, `tex_facade_*.png`).

Do exactly this:
1. `cd "/home/leandi-duplessis/github/3D builds/Kiepie bike/godot"`
2. `timeout 180 godot-4.3 --headless --path . --script tools/build_bike.gd` — must print `saved`
3. `timeout 180 godot-4.3 --headless --path . --script tools/build_testride.gd` — must print `saved` or fail with a REAL parse error; if a parse error occurs, fix the offending lines minimally (do not redesign) and re-run.
4. `timeout 300 godot-4.3 --headless --path . --script tools/truth_test.gd` — expect vel_z growing to ≥ 9 by t=300.
5. `timeout 300 godot-4.3 --headless --path . --script tools/verify_features.gd` — turbo active, flames emitting, camera toggle works, no script errors.
6. `timeout 200 godot-4.3 --headless --path . --script tools/diag2.gd` — label cycles 1/3, 2/3, 3/3.
7. Report everything to the report file; on BLOCKED or failures, say exactly what failed.

