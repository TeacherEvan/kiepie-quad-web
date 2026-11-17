extends SceneTree
## Renderer-only visual proof for the VFX/content pass. Not a gate.
##   xvfb-run -a godot-4.3 --path godot --script tools/vfx_showcase.gd
## Writes four PNGs to renders/ for before/after inspection.

const OUT := "/home/leandi-duplessis/github/3D builds/Kiepie bike/renders/"
var vf: GDScript


func _camera(scene: Node3D, pos: Vector3, look: Vector3, fov: float = 62.0) -> Camera3D:
	var rig := scene.get_node_or_null("CameraRig")
	if rig != null:
		rig.set_script(null)
		rig.global_position = pos
	else:
		var holder := Node3D.new()
		holder.global_position = pos
		scene.add_child(holder)
		rig = holder
	var cam := rig.get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		cam = Camera3D.new()
		rig.add_child(cam)
	cam.current = true
	cam.fov = fov
	cam.look_at(look, Vector3.UP)
	return cam


func _shot(name: String) -> void:
	for i in range(3):
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var path := OUT + name
	img.save_png(path)
	print("saved ", path, " ", img.get_width(), "x", img.get_height())


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	vf = load("res://src/game/VfxFactory.gd") as GDScript
	# 1 — arena layout from above: confirms ramps/buildings placement
	var arena := (load("res://scenes/Arena.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(arena)
	_camera(arena, Vector3(0, 92, 0.1), Vector3.ZERO, 72.0)
	await _shot("vfx_arena_layout.png")
	_camera(arena, Vector3(0, 7, 42), Vector3(0, 10, -30), 72.0)
	await _shot("vfx_arena_venue.png")
	arena.free()
	for i in range(3):
		await process_frame

	# 2 — explosion staged in front of a static camera
	var ride := (load("res://scenes/TestRide.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(ride)
	_camera(ride, Vector3(0, 3.2, 9.0), Vector3(0, 1.1, 0), 62.0)
	for i in range(3):
		await process_frame
	vf.explosion(ride, Vector3(0, 1.0, 0), Color(1, 0.5, 0.2), 1.1)
	await create_timer(0.24).timeout
	await _shot("vfx_explosion_new.png")

	# 3 — building smash: dust wave, glass, staggered puffs
	var workshop := ride.get_node_or_null("Workshop") as Node3D
	_camera(ride, Vector3(13, 6.5, 33), Vector3(13, 1.8, 22), 62.0)
	for i in range(3):
		await process_frame
	if workshop != null:
		workshop.call("smash")
	await create_timer(0.30).timeout
	await _shot("vfx_smash_new.png")

	# 4 — muzzle flashes + impacts against a wall
	_camera(ride, Vector3(-2.0, 2.0, 10.0), Vector3(0, 1.2, 0), 60.0)
	for i in range(3):
		await process_frame
	vf.muzzle_flash(ride, Vector3(0, 1.2, 0), Vector3.FORWARD, Color(1, 0.6, 0.2))
	vf.impact(ride, Vector3(1.5, 1.3, 0), Color(1, 0.6, 0.2), Vector3.FORWARD,
			"concrete", Vector3.FORWARD)
	await create_timer(0.08).timeout
	await _shot("vfx_muzzle_new.png")
	# 5 — touch overlay with the analog pad deflected (render proof)
	var settings_node := root.get_node_or_null("Settings")
	if settings_node != null:
		settings_node.call("set_value", "controls", "touch_force", true)
	var ride2 := (load("res://scenes/TestRide.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(ride2)
	for i in range(6):
		await process_frame
	var touch_hud := ride2.get_node_or_null("TouchHUD") as CanvasLayer
	if touch_hud != null:
		var pad := touch_hud.get_node_or_null("AnalogSteer") as Control
		print("analog pad rect: ", pad.get_global_rect() if pad != null else "MISSING")
		var r := pad.get_global_rect()
		var at := Vector2(r.get_center().x + r.size.x * 0.5 - 42.0, r.get_center().y)
		touch_hud.call("_on_pointer_down", 0, at)
		touch_hud.call("_on_pointer_move", 0, at)
		for i in range(4):
			await process_frame
		print("steer_right strength: ", Input.get_action_strength("steer_right"))
		await _shot("vfx_touch_analog.png")
		touch_hud.call("_on_pointer_up", 0, at)
		for i in range(3):
			await process_frame
	if settings_node != null:
		settings_node.call("set_value", "controls", "touch_force", false)
	ride2.free()

	quit()
