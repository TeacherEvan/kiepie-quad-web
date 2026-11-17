# Task 1 Report — Rebuild + fix the visual builder patch

Date: 2026-11-16
Working dir for all Godot commands: `/home/leandi-duplessis/github/3D builds/Kiepie bike/godot`
All commands run under `timeout` as the brief specifies. RID-leak / "Pages in use" /
"resources still in use at exit" / "ObjectDB instances leaked" warnings are benign and
were ignored per the brief; verdicts are based on `saved` lines and gate output lines.

## Commands run (in order)

1. `timeout 180 godot-4.3 --headless --path . --script tools/build_bike.gd`
2. `timeout 180 godot-4.3 --headless --path . --script tools/build_testride.gd` (failed, fixed, re-run)
3. `timeout 180 godot-4.3 --headless --path . --import` (import pass to generate `.import` files for new textures)
4. `timeout 180 godot-4.3 --headless --path . --script tools/build_testride.gd` (re-run after import)
5. `timeout 300 godot-4.3 --headless --path . --script tools/truth_test.gd`
6. `timeout 300 godot-4.3 --headless --path . --script tools/verify_features.gd`
7. `timeout 200 godot-4.3 --headless --path . --script tools/diag2.gd`

## Fixes made

### Fix 1 — build_testride.gd parse error (line ~394)

`match node_name:` block in `_facade_texture_for()` ended with a bare `return null` at
pattern indentation, which GDScript rejects ("Expected expression for match pattern").
Minimal fix only (no redesign):

Before:
```
		"Store":
			return load("res://assets/tex_facade_store.png") as Texture2D
		return null
```

After:
```
		"Store":
			return load("res://assets/tex_facade_store.png") as Texture2D
		_:
			return null
```

### Fix 2 — textures not loadable (`No loader found for resource: res://assets/tex_*.png`)

The newly copied `assets/tex_asphalt.png`, `tex_cone.png`, `tex_facade_workshop.png`,
`tex_facade_shed.png`, `tex_facade_store.png` had no `.import` files, so headless `load()`
failed for every texture (asphalt, all 30+ cone loads, all 3 facades). Fixed by running the
standard headless import pass:
`timeout 180 godot-4.3 --headless --path . --import`
which generated `assets/tex_*.png.import` (plus `.godot/imported/` entries). No source files
were edited for this; it is the normal Godot import step. After the import pass, the
"No loader found" errors are gone and facades/asphalt/cone textures load.

### NOT fixed (pre-existing, out of scope, do not change behavior)

- `tools/build_testride.gd:471` — `building.connect("body_entered", Callable(building, "_on_body_entered"))`
  prints `ERROR: In Object of type 'StaticBody3D': Attempt to connect nonexistent signal 'body_entered' ...`
  (StaticBody3D has no `body_entered`; that signal belongs to Area3D). Non-fatal: the script
  still reaches `saved`, and smash detection/HUD counting works (see gates). This line is not
  part of the visual-overhaul patch description and removing/changing it could alter behavior,
  so it was left as-is. Smash reporting happens via the `destructible` group + `HUD.register_smash()`
  path in `DestructibleBuilding.gd`, which is why the counters still work.
- `ERROR: Condition "!is_inside_tree()" is true. Returning: Transform3D()` spam during
  verify_features/diag2 smash steps — non-fatal, appears in both runs, seemingly from
  debris/global-transform access after parts leave the tree. Not investigated further
  (read-only gates still print correct results).
- `ERROR: Parameter "m" is null. at: mesh_get_surface_count` at exit in truth_test /
  verify_features / diag2 — non-fatal shutdown noise.

## Command outputs (key lines)

### 1. build_bike.gd — EXIT=0
```
saved res://scenes/KiepieBike.tscn
```
(plus benign RID-leak / PagedAllocator exit spam)

### 2. build_testride.gd, first run — EXIT=1 (parse error)
```
SCRIPT ERROR: Parse Error: Expected expression for match pattern.
          at: GDScript::reload (res://tools/build_testride.gd:394)
ERROR: Failed to load script "res://tools/build_testride.gd" with error "Parse error".
```

### 3. import pass — EXIT=0 (dialog-parenting ERRORs are benign editor-import noise)
Generated `assets/tex_asphalt.png.import`, `tex_cone.png.import`,
`tex_facade_shed.png.import`, `tex_facade_store.png.import`, `tex_facade_workshop.png.import`.

### 4. build_testride.gd, after Fix 1 + Fix 2 — EXIT=0
```
ERROR: In Object of type 'StaticBody3D': Attempt to connect nonexistent signal 'body_entered' ...   (x3, pre-existing, non-fatal)
saved res://scenes/TestRide.tscn
```
No "No loader found" errors remain. RID-leak exit spam benign.

### 5. truth_test.gd — EXIT=0
```
has is_in_contact FL: true
wheel pos (-0.545, 0.5, 0.68) rest_len 0.22 travel 0.20 radius 0.28
t=0   pos=(0.00, 0.37, 8.00)  vel=(0.00,-1.14, 0.00) contact=false
t=60  pos=(0.00,-0.22, 8.19)  vel=(-0.00, 1.47, 1.64) contact=true
t=120 pos=(-0.00, 0.20, 9.67) vel=(0.00, 0.25, 3.47) contact=false
t=180 pos=(0.00, 0.16, 11.42) vel=(0.00,-0.32, 4.99) contact=false
t=240 pos=(0.00,-0.12, 13.61) vel=(0.00,-0.77, 6.94) contact=true
t=300 pos=(0.00,-0.01, 17.23) vel=(0.00, 0.17, 9.47) contact=false
```
PASS: vel_z grows monotonically overall to 9.47 ≥ 9.0 at t=300; motion is toward +Z (z 8.00 → 17.23).

### 6. verify_features.gd — EXIT=0
```
nodes ok: bike=true hud=true rig=true
TURBO: active=true blend=1.00 (expect true / ~1.0)
FLAMES: node=true emitting=true
TURBO OFF: active=false
CAMERA: mode after toggle = free (expect free)
CAMERA: mode after toggle = follow (expect follow)
SMASH Workshop -> HUD label: 'Buildings smashed: 1 / 3'
SMASH Shed     -> HUD label: 'Buildings smashed: 2 / 3'
SMASH Store    -> HUD label: 'Buildings smashed: 3 / 3'
DEBRIS: 43 rigid bodies loose in the scene (expect 42)
SPEED: bike speed_kmh = 1.5
```
PASS on turbo (active, blend 1.00), flames (emitting), turbo-off, camera toggle (free ↔ follow),
smash counter via HUD (1/3 → 2/3 → 3/3). No GDScript runtime/parse errors from the builder output.
NOTE: DEBRIS reports 43 loose rigid bodies vs the printed expectation of 42 — off by one;
not part of the brief's pass criteria and not investigated (no behavior changes allowed).
Flagging as a concern.

### 7. diag2.gd — EXIT=0
```
hud ready: true label starts: 'Buildings smashed: 0 / 3'
Workshop smashed -> label: 'Buildings smashed: 1 / 3'
Shed smashed     -> label: 'Buildings smashed: 2 / 3'
Store smashed    -> label: 'Buildings smashed: 3 / 3'
```
PASS: label cycles 0/3 → 1/3 → 2/3 → 3/3.

## Gate verdicts

- build_bike.gd: PASS (`saved res://scenes/KiepieBike.tscn`)
- build_testride.gd: PASS after minimal fix (`saved res://scenes/TestRide.tscn`)
- truth_test.gd: PASS (t=300 vel_z = 9.47 ≥ 9; +Z motion)
- verify_features.gd: PASS (turbo/flames/camera/smash 1-2-3 all as expected; debris count 43 vs 42 noted)
- diag2.gd: PASS (label 1/3 → 2/3 → 3/3)

## Concerns

1. DEBRIS count in verify_features is 43, tool prints "expect 42". Functional smash/HUD path
   is fine; worth a look in a later task (possibly one pre-existing loose body counted, or an
   off-by-one in the expectation). Left unchanged per "do not change behavior".
2. Pre-existing non-fatal `body_entered` connect error on StaticBody3D (build_testride.gd:471).
3. `!is_inside_tree()` Transform3D error spam during smash sequences (both verify_features and
   diag2) — noisy but non-fatal; not touched.
4. New `assets/tex_*.png.import` files now exist (generated by the import pass) — required for
   the textures to load at runtime; keep them.

No deploys, no web/ changes, no commits, no other files edited (only `tools/build_testride.gd`
line-394-area match-block fix).

---

# Task 1 — Resume fixes (2026-11-16, second pass)

## Changes made

### A. `src/DestructibleBuilding.gd:17` — signature widened per instruction
Before: `func _on_body_entered(body: Node3D) -> void:`
After:  `func _on_body_entered(body: Node) -> void:`
`body.is_in_group("bike")`, `body is VehicleBody3D`, `body is RigidBody3D` all remain valid on `Node`.

IMPORTANT — the premise behind fix A does not hold in Godot 4.3: the connect error is
NOT caused by a signature mismatch, and the signature change does NOT make the connect in
`tools/build_testride.gd:471` succeed. Verified directly against the engine ClassDB
(headless throwaway script, /tmp/opencode/list_signals.gd):

```
StaticBody3D signals: []
Area3D signals: ["body_shape_entered", "body_shape_exited", "body_entered",
                 "body_exited", "area_shape_entered", "area_shape_exited",
                 "area_entered", "area_exited"]
Area3D.body_entered arg: name=body type=Object
```

StaticBody3D carries NO signals at all in Godot 4.3; `body_entered` exists only on Area3D.
The `build_testride.gd:471` connect (`building.connect("body_entered", ...)`) therefore
fails with "nonexistent signal 'body_entered'" on every run — before and after fix A.
Fix A was kept because it is correct and harmless (and required if an Area3D-based detector
is ever added), but the connect error is NOT gone. The connect line was left untouched
(outside this task's file scope; removing it or adding an Area3D child would change the
build/detection design and was not authorized). NOTE: the failure is build-time only and
no-op at runtime — gates call `building.smash()` directly, and `DestructibleBuilding.gd`
also registers via `_ready()`/`add_to_group("destructible")` + `HUD.register_smash()`, so
smash/HUD behavior is unaffected. Real fixes, if wanted: (a) delete/guard the dead connect
(`if building.has_signal("body_entered"):`), or (b) redesign detection as Area3D (out of scope).

### B. `src/DestructibleBuilding.gd` — debris fade timer queue_free guarded
Before:
```
			fade_tree.create_timer(9.0).timeout.connect(func() -> void:
				if is_instance_valid(chunk_capture):
					chunk_capture.queue_free())
```
After:
```
			fade_tree.create_timer(9.0).timeout.connect(func() -> void:
				if is_instance_valid(chunk_capture) and chunk_capture.is_inside_tree():
					chunk_capture.queue_free())
```
NOTE: this guard is correct as specified, but it does NOT silence the
`!is_inside_tree()` spam observed in the gates: that spam comes from
`get_global_transform` (scene/3d/node_3d.cpp:345), a different callsite, and the fade
timer fires at t=9.0 s — after the headless gates have already quit. Spam count after the
fix: verify_features.gd = 84 occurrences (unchanged in character), diag2.gd shows the same
pattern. Root-causing the get_global_transform callsite was not in scope.

### C. `tools/verify_features.gd:46` — misleading expectation text fixed
Before:
```
print("DEBRIS: %d rigid bodies loose in the scene (expect %d)" % [debris, 14 * 3])
```
After:
```
print("DEBRIS: %d rigid bodies loose in the scene (expect %d: 42 debris + 1 bike; VehicleBody3D is a RigidBody3D)" % [debris, 14 * 3 + 1])
```
Now prints `expect 43`, matching reality. Nothing else in the file was touched.

## Gates re-run (2026-11-16, after fixes)

- build_testride.gd — EXIT=0, prints `saved res://scenes/TestRide.tscn`. Still prints
  `ERROR: In Object of type 'StaticBody3D': Attempt to connect nonexistent signal
  'body_entered' ...` x3 (pre-existing, see Fix A above — NOT eliminated by the signature fix).
- diag2.gd — EXIT=0. Label cycles `0/3` (start) → `1/3` (Workshop) → `2/3` (Shed) → `3/3` (Store). PASS.
  (`!is_inside_tree()` spam unchanged; `Parameter "m" is null` at exit unchanged — benign.)
- verify_features.gd — EXIT=0. Output:
  ```
  nodes ok: bike=true hud=true rig=true
  TURBO: active=true blend=1.00 (expect true / ~1.0)
  FLAMES: node=true emitting=true
  TURBO OFF: active=false
  CAMERA: mode after toggle = free (expect free)
  CAMERA: mode after toggle = follow (expect follow)
  SMASH Workshop -> HUD label: 'Buildings smashed: 1 / 3'
  SMASH Shed     -> HUD label: 'Buildings smashed: 2 / 3'
  SMASH Store    -> HUD label: 'Buildings smashed: 3 / 3'
  DEBRIS: 43 rigid bodies loose in the scene (expect 43: 42 debris + 1 bike; VehicleBody3D is a RigidBody3D)
  SPEED: bike speed_kmh = 1.6
  ```
  PASS on turbo / flames / camera / smash counter / debris expectation (43 == 43).
  No GDScript runtime or parse errors. The only errors are the benign RID/allocator exit
  noise, `Parameter "m" is null` at exit, and 84x `!is_inside_tree()` get_global_transform
  spam (see Fix B note). The `body_entered` connect error does NOT appear in gate runtime
  output (it is build-time only, in the builder process).

## Verdict summary

- build_testride.gd: PASS (`saved`, exit 0) — but connect error still present (see Fix A).
- diag2.gd: PASS (1/3 → 2/3 → 3/3)
- verify_features.gd: PASS (all feature lines correct, DEBRIS 43/43, no script errors)
- Connect error: NOT gone. The task's assumption (StaticBody3D has a `body_entered` signal
  emitting `Node`) is incorrect for Godot 4.3 — StaticBody3D has no signals; `body_entered`
  is Area3D-only (arg typed `Object`). The signature fix was applied as instructed but
  cannot satisfy the stated goal. Needs either removal/guard of the dead connect line, or an
  Area3D-based detection redesign — both left to the parent session to decide.

Files edited in this pass: `src/DestructibleBuilding.gd` (A, B), `tools/verify_features.gd` (C).
`tools/build_testride.gd` untouched in this pass. No deploys, no web/ changes, no commits.

---

# Task 1 — Round 3: Area3D impact-trigger redesign (2026-11-16)

## What changed and why

StaticBody3D has NO signals in Godot 4.3 (verified via ClassDB last round), so the old
`body_entered` connect could never work and player impact could never smash a building.
Redesigned impact detection as a child Area3D trigger, keeping the StaticBody3D solid.

### 1. `src/DestructibleBuilding.gd` — `_ready()` now builds a "SmashTrigger" Area3D
```
func _ready() -> void:
	add_to_group("destructible")
	# ... comment explaining StaticBody3D has no signals ...
	var box_size := Vector3(1.0, 1.0, 1.0)
	var box_pos := Vector3(0.0, 1.0, 0.0)
	for child in get_children():
		if child is CollisionShape3D:
			var shape := (child as CollisionShape3D).shape
			if shape is BoxShape3D:
				box_size = (shape as BoxShape3D).size
				box_pos = (child as CollisionShape3D).position
				break
	var area := Area3D.new()
	area.name = "SmashTrigger"
	area.monitoring = true
	area.monitorable = false
	area.collision_layer = 0
	area.collision_mask = 1 # bike is on layer 1
	var trigger_shape := CollisionShape3D.new()
	trigger_shape.name = "SmashTriggerShape"
	var box := BoxShape3D.new()
	box.size = box_size + Vector3(0.35, 0.6, 0.35)
	trigger_shape.shape = box
	trigger_shape.position = box_pos
	area.add_child(trigger_shape)
	area.body_entered.connect(_on_body_entered)
	add_child(area)
```
The trigger box wraps the building collider (read from the existing BoxShape3D child and its
local position) expanded by (0.35, 0.6, 0.35). `_on_body_entered(body: Node)` is unchanged:
group check `body.is_in_group("bike")`, linear_velocity length >= `hit_speed` (3.2) for
VehicleBody3D/RigidBody3D, then `smash()`.

### 2. `tools/build_testride.gd` — removed the bogus connect
Deleted `building.connect("body_entered", Callable(building, "_on_body_entered"))`
(replaced with the comment: smash detection is handled by a SmashTrigger Area3D inside
DestructibleBuilding._ready()). Result: ZERO `body_entered` connect errors on build.

### 3. `src/KiepieBike.gd` — bike registers its group at runtime (REQUIRED for impacts)
Discovery while testing: `bike.add_to_group("bike")` in the builder does NOT persist into the
baked `scenes/TestRide.tscn` (no `groups=` in the file — same class of builder-time loss as
runtime signal connects, per AGENTS.md). Without the group, the SmashTrigger fires but
`_on_body_entered` rejects the bike and NOTHING could ever smash. One-line runtime fix:
```
func _ready() -> void:
	add_to_group("bike") # group is not persisted in the baked .tscn; register at runtime
	...
```

### 4. Debris spawn order bug fixed (same root cause as the `!is_inside_tree()` spam)
The 84x `!is_inside_tree()` `get_global_transform` spam came from `smash()` setting
`chunk.global_position` (and reading it back) BEFORE `parent.add_child(chunk)` — the nodes were
not in the tree yet, the transform writes/reads failed (and debris would have spawned at the
world origin instead of the building volume). Fix: `parent.add_child(chunk)` moved BEFORE the
position scattering; the now-duplicate trailing `add_child` was removed. Spam went from 84 -> 0
in verify_features and diag2.

### 5. Physics-flush error fixed
`smash()` disables the intact collider; when called from the Area3D `body_entered` (physics
flush) that raised `Can't change this state while flushing queries`. Fix:
`(child as CollisionShape3D).set_deferred("disabled", true)` plus an explanatory comment.

### 6. New tool `tools/verify_smash_impact.gd` (end-to-end impact test)
Instantiates TestRide.tscn, awaits 1 frame (children are not in the tree until the tree flushes
enter-tree notifications — immediate `global_position` reads return identity + error), teleports
KiepieBike onto the Workshop doorway axis (position = Workshop pos + direction toward pad centre
* 5.5 m, aimed at the facade via rotation.y = atan2 of the forward vector), presses
`move_forward`, awaits 300 frames, releases, then prints bike end pos/vel,
`Workshop _intact=<value>`, and the RigidBody3D child count, and PASSes iff `_intact == false`
and debris >= 15 (14 debris + 1 bike).

## Gates re-run (all after the above changes)

- build_testride.gd — EXIT=0, `saved res://scenes/TestRide.tscn`, **ZERO `body_entered` connect errors**. PASS.
- truth_test.gd — EXIT=0. t=0 z=8.00 → t=300 z=17.23, vel_z 0 → 9.47 (≥ 9.0) at t=300. Physics intact. PASS.
- verify_features.gd — EXIT=0. All lines pass: nodes ok, TURBO active blend=1.00, FLAMES emitting,
  TURBO OFF, CAMERA free↔follow, SMASH labels 1/3 → 2/3 → 3/3, DEBRIS 43 (expect 43),
  SPEED 1.6 km/h. ZERO `!is_inside_tree()` errors (was 84). No script errors. PASS.
- diag2.gd — EXIT=0. Label: `0 / 3` → `1 / 3` (Workshop) → `2 / 3` (Shed) → `3 / 3` (Store).
  ZERO `!is_inside_tree()` errors (was ~90). PASS.
- verify_smash_impact.gd — EXIT=0. Output:
  ```
  bike end pos=(11.49, 0.98, 21.90) vel=(0.10, -0.90, 2.46)
  Workshop _intact=false
  DEBRIS: 15 RigidBody3D children in root (1 is the bike; 14 new debris expected)
  SMASH_IMPACT: PASS
  ```
  (An earlier run failed with bike stuck at world origin because transforms were read before the
  tree flushed; fixed by awaiting one frame. The debris-reorder + deferred-disable removed the
  physics-flush error; final output is clean.)

## Verdicts

- build_testride.gd: PASS (saved, no connect errors)
- truth_test.gd: PASS
- verify_features.gd: PASS
- diag2.gd: PASS
- verify_smash_impact.gd: PASS — the quad DOES smash the Workshop purely by driving into it.
- `body_entered` connect errors remaining: NONE.

Known benign remnants (unchanged, acceptable): RID-leak / PagedAllocator / "resources still in
use" / ObjectDB exit spam, and `Parameter "m" is null` (mesh_get_surface_count) at exit in
headless dummy rendering. The fade-timer `queue_free` 9 s guard (round 2, fix B) is unchanged and
harmless; the smash-time collider disable is now properly deferred.

Files edited this round: `src/DestructibleBuilding.gd`, `src/KiepieBike.gd`,
`tools/build_testride.gd`, `tools/verify_smash_impact.gd` (new). No deploys, no web/ changes,
no commits.

---

# Task 1 — Round 4: reviewer findings F1 / F3 / F4 / F6 (2026-11-16)

## F1 (Critical claimed) — NOT PRESENT, not invented
Reviewer claimed `tools/build_testride.gd` (~line 380) contains a line
`ramp.rotation = Vector3(pos.x, 0.0, pos.z)` (position fed into orientation).
Actual file (lines 370-385) contains:
```
	stripe.rotation_degrees = Vector3(rot_x, 0.0, 0.0)
	ramp.add_child(stripe)

	ramp.position = Vector3(pos.x, 0.0, pos.z)
	ramp.rotation_degrees.y = rot_deg.y
	root.add_child(ramp)
```
No `ramp.rotation` assignment exists anywhere in the file (grep `ramp\.rotation` → single
hit: `ramp.rotation_degrees.y = rot_deg.y`, line 382). `ramp.position` carries the position
as intended and yaw is applied only via the Y component on a fresh node (default
rotation_degrees is (0,0,0), so setting `.y` leaves x/z at 0 — equivalent to the requested
`Vector3(0.0, rot_deg.y, 0.0)` form; no change made per "do not invent"). F1 required no edit.

## F3 (Warning) — DONE
`src/KiepieBike.gd:138`: `elif throttle == 0.0 and throttle >= 0.0:` → `elif throttle == 0.0:`
(semantics unchanged; `throttle == 0.0` already implies `throttle >= 0.0`).

## F4 (Warning) — DONE, with one engine-mandated deviation
`src/DestructibleBuilding.gd` smash() children loop now also disables the SmashTrigger:
```
		elif child is Area3D and child.name == "SmashTrigger":
			# stop the impact trigger firing after the building has smashed
			# (smash() can run inside a physics in/out signal; defer the change)
			(child as Area3D).set_deferred("monitoring", false)
```
Deviation from the literal instruction (`area.monitoring = false`): the direct assignment
was implemented first and verify_smash_impact showed
`ERROR: Function blocked during in/out signal. Use set_deferred("monitoring", true/false).
  at: set_monitoring (scene/3d/physics/area_3d.cpp:379)` — i.e. smash() runs inside the
physics in/out signal and Area3D refuses direct monitoring changes there. Switched to
`set_deferred("monitoring", false)`, which is exactly what the engine demands (same pattern as
the existing collider `set_deferred("disabled", true)`). Post-defer, monitoring=false, so the
trigger no longer fires after smash. Grandchildren untouched; existing MeshInstance3D /
CollisionShape3D logic untouched.

## F6 (Suggestion) — PARTIAL, one item refused per its own condition
- `tools/build_testride.gd`: removed `var hud_holder: Node = null` (was line 142) and the
  dead `hud_holder = layer` (was line 250). Verified `hud_holder` had exactly those 2 refs
  (declared + assigned, never read; HUD is parented via `root.add_child(layer)` directly).
- `src/FollowCam.gd` `@export var orbit_height := 2.4` NOT removed: grep shows a second
  reference — `scenes/TestRide.tscn:1196` serializes `orbit_height = 2.4` on the CameraRig
  node. The finding said to remove it ONLY if `grep -n orbit_height` shows no other refs;
  there ARE other refs, so per the finding's own condition it stays. (Removing the export
  while the .tscn sets it would also produce a "property not found" scene-load error.)

## Gates re-run (after F3/F4/F6 changes — F1 made no edits)

- build_testride.gd — EXIT=0, `saved res://scenes/TestRide.tscn`, no connect errors. PASS.
- truth_test.gd — EXIT=0. t=0 z=8.00 → t=300 z=17.23, vel_z 0 → 9.47 (≥ 9.0). PASS.
- verify_features.gd — EXIT=0. nodes ok; TURBO active blend=1.00; FLAMES emitting; TURBO OFF;
  CAMERA free↔follow; SMASH 1/3 → 2/3 → 3/3; DEBRIS 43 (expect 43); 0 flush/monitoring errors;
  0 is_inside_tree errors. PASS.
- diag2.gd — EXIT=0. Label `0 / 3` → `1 / 3` → `2 / 3` → `3 / 3`. 0 flush/monitoring errors. PASS.
- verify_smash_impact.gd — EXIT=0. Final output:
  ```
  bike end pos=(11.49, 0.98, 21.90) vel=(0.10, -0.90, 2.46)
  Workshop _intact=false
  DEBRIS: 15 RigidBody3D children in root (1 is the bike; 14 new debris expected)
  SMASH_IMPACT: PASS
  ```
  Zero monitoring/physics errors after the deferred fix. PASS.

No lighting/HUD/physics/verify-tool/Area3D-design changes. No deploys, no web/ changes, no commits.
