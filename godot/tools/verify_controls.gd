extends SceneTree
## Offline control-feel gate. Locks the defect the original gates missed:
## anti-rollover damping in _physics_process cancelled all wheel-generated
## yaw, so the wheels reached full lock but the bike never turned.
## Also verifies the steer_sensitivity setting actually changes turn rate.

var _fail := 0
var _settings: Node

func _set_setting(key: String, value: Variant) -> void:
	# Tool scripts cannot reference autoloads at compile time (see AGENTS.md).
	if _settings == null or not is_instance_valid(_settings):
		_settings = get_root().get_node("Settings")
	_settings.call("set_value", "controls", key, value)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS ", label)
	else:
		printerr("FAIL ", label)
		_fail += 1

func _initialize() -> void:
	_run()

func _release_all() -> void:
	for a in ["move_forward", "move_back", "steer_left", "steer_right", "brake", "turbo"]:
		Input.action_release(a)

func _measure(sensitivity: float) -> Dictionary:
	_set_setting("steer_sensitivity", sensitivity)
	var scene := load("res://scenes/TestRide.tscn") as PackedScene
	var root := scene.instantiate() as Node3D
	get_root().add_child(root)
	await process_frame
	var bike := root.get_node("KiepieBike") as VehicleBody3D
	for i in range(30):
		await process_frame
	Input.action_press("move_forward")
	for i in range(120):
		await process_frame
	var h0 := bike.global_transform.basis.z.normalized()
	Input.action_press("steer_left")
	var min_up := 1.0
	for i in range(90):
		await process_frame
		min_up = minf(min_up, bike.global_transform.basis.y.normalized().y)
	var h1 := bike.global_transform.basis.z.normalized()
	var heading := rad_to_deg(acos(clampf(h0.dot(h1), -1.0, 1.0)))
	_release_all()
	root.queue_free()
	await process_frame
	return {"heading": heading, "min_up": min_up}

func _run() -> void:
	await process_frame
	var normal: Dictionary = await _measure(1.0)
	_check(float(normal["heading"]) > 15.0,
			"steering yaws the bike (heading %.1f deg)" % float(normal["heading"]))
	_check(float(normal["min_up"]) > 0.80,
			"bike stays upright while steering (min_up %.3f)" % float(normal["min_up"]))
	var low: Dictionary = await _measure(0.4)
	var high: Dictionary = await _measure(1.8)
	_check(float(high["heading"]) > float(low["heading"]) * 1.15,
			"steer sensitivity changes turn rate (low %.1f vs high %.1f deg)" % [
					float(low["heading"]), float(high["heading"])])
	_set_setting("steer_sensitivity", 1.0)
	print("CONTROLS: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
