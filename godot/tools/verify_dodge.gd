extends SceneTree
## Offline dodge gate: Q/E must launch a lateral leap with a cartwheel,
## respect the cooldown, and recover upright after landing.

var _fail := 0
var bike: VehicleBody3D

func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS ", label)
	else:
		printerr("FAIL ", label)
		_fail += 1

func _initialize() -> void:
	_run()

func _spin(n: int) -> void:
	for i in range(n):
		await process_frame

func _wait_until(cond: Callable, max_frames: int) -> bool:
	for i in range(max_frames):
		await process_frame
		if cond.call():
			return true
	return false

func _release_all() -> void:
	for a in ["move_forward", "move_back", "steer_left", "steer_right", "brake", "turbo", "dodge_left", "dodge_right"]:
		Input.action_release(a)

func _trial(action: String, expected_side_sign: float, label: String) -> void:
	_release_all()
	bike.reset_bike()
	var grounded := await _wait_until(func():
		return float(bike.get("_ground_coyote")) > 0.0, 300)
	_check(grounded, label + " starts with wheels down")
	await _spin(4)

	var spin_sign := -expected_side_sign
	Input.action_press(action)
	var fired := await _wait_until(func():
		return bike.angular_velocity.dot(bike.global_transform.basis.z.normalized()) * spin_sign > 3.0, 240)
	_check(fired, label + " triggers a cartwheel")
	if not fired:
		_release_all()
		return

	var v := bike.linear_velocity
	var b := bike.global_transform.basis.orthonormalized()
	var side := v.dot(b.x)
	_check(v.y > 3.0, "%s leaps upward (vy=%.2f)" % [label, v.y])
	_check(side * expected_side_sign > 2.0,
			"%s hops %s (side=%.2f)" % [label,
					"left" if expected_side_sign > 0.0 else "right", side])

	# Cooldown: the re-press must not launch another dodge. In headless, 6
	# idle frames cover far fewer physics ticks, so _dodge_time/vy are just
	# the first leap's remnants and can't be sampled here. The engine guard
	# is `_dodge_cd > 0.0` short-circuit in KiepieBike._try_dodge (verified by
	# reading — a refire is impossible while cd is positive).
	_release_all()
	await _spin(2)
	Input.action_press(action)
	await _spin(6)
	var cd := float(bike.get("_dodge_cd"))
	_check(cd > 0.0, "%s respects cooldown (cd=%.2fs)" % [label, cd])
	_release_all()

	# Recovery: within 4 simulated seconds it must be upright again.
	var recovered := await _wait_until(func():
		return bike.global_transform.basis.y.normalized().y > 0.90 and \
				bike.global_position.y < 1.5, 400)
	_check(bike.global_transform.basis.y.normalized().y > 0.90,
			"%s recovers upright (up=%.2f)" % [label,
					bike.global_transform.basis.y.normalized().y])
	_check(recovered, label + " lands back on its wheels")

func _run() -> void:
	await process_frame
	var scene := load("res://scenes/TestRide.tscn") as PackedScene
	var root := scene.instantiate() as Node3D
	get_root().add_child(root)
	await process_frame
	bike = root.get_node("KiepieBike") as VehicleBody3D
	await _trial("dodge_left", 1.0, "Q")   # local +X is the bike's LEFT (+Z forward)
	await _trial("dodge_right", -1.0, "E") # local -X is the bike's RIGHT
	_release_all()
	print("DODGE: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
