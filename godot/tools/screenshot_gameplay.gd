extends SceneTree
## Real-renderer gameplay screenshots for the practice track (TestRide.tscn).
## Not a gate — a capture tool. Run from the repo root:
##   KIEPIE_MOCK_BACKEND=1 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot-4.3 --resolution 1280x720 --path godot --script tools/screenshot_gameplay.gd
## Writes renders/game_practice_drive.png, renders/game_practice_jump.png and
## renders/game_practice_cannons.png into the repo-root renders/ dir (derived
## from res:// -> godot/ -> ../renders, absolute). Needs a real renderer
## (xvfb); the headless dummy renderer produces no pixels. Practice mode
## works fully offline.
##
## Note: under llvmpipe the renderer is slow, so Godot runs multiple physics
## steps per rendered frame — frame counts are NOT wall-clock. All captures
## are therefore driven by condition polling (speed / airborne), never by
## fixed frame counts alone.
## Shot 2 (jump) aims for mid-flight above RampBig's lip: the plank tops out
## at z ~= 27.75 with a ride height of ~1.3 m, so the trigger is simply
## y > 1.3 with z > 28.2 — works even though VehicleWheel3D.is_in_contact()
## lags a few physics steps behind actual liftoff. The chase camera follows
## automatically via the native FollowCam rig.

const ACTIONS := ["move_forward", "move_back", "steer_left", "steer_right",
		"brake", "turbo", "fire", "dodge_left", "dodge_right"]
## Absolute repo-root renders/ dir, derived from res:// (godot/ -> ../renders).
var _out_dir := ""


func _initialize() -> void:
	_run()


func _release_all() -> void:
	for a in ACTIONS:
		Input.action_release(a)


func _spawn_ride() -> Node3D:
	var ride := (load("res://scenes/TestRide.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(ride)
	return ride


func _snap(name: String) -> void:
	for i in range(3):
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var path := _out_dir + name
	var err := img.save_png(path)
	if err != OK:
		printerr("FAILED to save ", path, " err=", err)
	else:
		print("saved ", path, " ", img.get_width(), "x", img.get_height())


func _run() -> void:
	_out_dir = ProjectSettings.globalize_path("res://").path_join("..").path_join("renders") + "/"
	print("output dir: ", _out_dir)
	await process_frame

	# ---------- 1 — cruising from spawn: throttle held, native chase cam + HUD
	var ride := _spawn_ride()
	await process_frame
	var bike := ride.get_node("KiepieBike") as VehicleBody3D
	Input.action_press("move_forward")
	var got_drive := false
	for i in range(900):
		await process_frame
		if bike.linear_velocity.length() >= 6.0 and bike.global_position.z < 16.0:
			print("drive: speed=%.1f m/s z=%.1f (frame %d)" % [bike.linear_velocity.length(),
					bike.global_position.z, i])
			got_drive = true
			break
	if not got_drive:
		printerr("drive: speed condition never met; capturing anyway (speed=%.1f z=%.1f)" % [
				bike.linear_velocity.length(), bike.global_position.z])
	await _snap("game_practice_drive.png")
	_release_all()
	ride.free()
	for i in range(3):
		await process_frame

	# ---------- 2 — airborne off RampBig (bike starts at spawn, facing it)
	ride = _spawn_ride()
	await process_frame
	bike = ride.get_node("KiepieBike") as VehicleBody3D
	Input.action_press("move_forward")
	Input.action_press("turbo")
	var jumped := false
	for i in range(900):
		await process_frame
		if bike.global_position.y > 1.25 and bike.global_position.z > 28.0 \
				and bike.global_position.z < 35.0:
			print("jump: airborne at frame %d z=%.1f y=%.2f vy=%.2f" % [i,
					bike.global_position.z, bike.global_position.y, bike.linear_velocity.y])
			jumped = true
			break
	if not jumped:
		printerr("jump: airborne condition never met; capturing anyway ",
				"(z=%.1f y=%.2f vy=%.2f)" % [bike.global_position.z,
					bike.global_position.y, bike.linear_velocity.y])
	await _snap("game_practice_jump.png")
	_release_all()
	ride.free()
	for i in range(3):
		await process_frame

	# ---------- 3 — cannon fire: throttle + fire held through the capture
	ride = _spawn_ride()
	await process_frame
	bike = ride.get_node("KiepieBike") as VehicleBody3D
	Input.action_press("move_forward")
	Input.action_press("fire")
	var got_cannons := false
	for i in range(900):
		await process_frame
		if bike.linear_velocity.length() >= 9.0:
			print("cannons: speed=%.1f m/s z=%.1f (frame %d)" % [bike.linear_velocity.length(),
					bike.global_position.z, i])
			got_cannons = true
			break
	if not got_cannons:
		printerr("cannons: speed condition never met; capturing anyway")
	await _snap("game_practice_cannons.png")
	_release_all()
	ride.free()

	quit()
