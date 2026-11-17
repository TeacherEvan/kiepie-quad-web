extends SceneTree

var _failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		push_error("FAIL: " + msg)
		_failures += 1

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/TestRide.tscn")
	var root_node := scene.instantiate() as Node3D
	get_root().add_child(root_node)
	var bike := root_node.get_node("KiepieBike") as VehicleBody3D
	var hud := root_node.get_node("HUD")
	var rig := root_node.get_node("CameraRig")
	print("nodes ok: bike=%s hud=%s rig=%s" % [bike != null, hud != null, rig != null])
	_check(bike != null and hud != null and rig != null, "bike/HUD/CameraRig instantiated")

	# ---- turbo: hold throttle + Shift
	Input.action_press("move_forward")
	Input.action_press("turbo")
	for i in range(120):
		await process_frame
	print("TURBO: active=%s blend=%.2f (expect true / ~1.0)" % [bike.turbo_active, bike._turbo_blend])
	_check(bike.turbo_active, "turbo engages while Shift is held")
	var flames := bike.get_node_or_null("ExhaustFlames")
	print("FLAMES: node=%s emitting=%s" % [flames != null, flames.emitting if flames else "n/a"])
	_check(flames != null and flames.emitting, "exhaust flames emit while turbo is active")
	Input.action_release("turbo")
	Input.action_release("move_forward")
	for i in range(30):
		await process_frame
	print("TURBO OFF: active=%s" % bike.turbo_active)
	_check(not bike.turbo_active, "turbo deactivates when Shift is released")

	# ---- camera toggle
	var mode0: Variant = rig.get("mode")
	rig.toggle_view()
	print("CAMERA: mode after toggle = %s (expect free)" % rig.get("mode"))
	_check(rig.get("mode") != mode0, "camera view toggles away from initial mode")
	rig.toggle_view()
	print("CAMERA: mode after toggle = %s (expect follow)" % rig.get("mode"))
	_check(rig.get("mode") == mode0, "camera view toggles back to initial mode")

	# ---- smash each building and check the HUD counter
	var prev_label := ""
	for name in ["Workshop", "Shed", "Store"]:
		var b := root_node.get_node(name)
		_check(b != null, "%s building exists" % name)
		b.smash()
		for i in range(10):
			await process_frame
		var smashed_label := hud.get_node_or_null("Smashed") as Label
		print("SMASH %s -> HUD label: '%s'" % [name, smashed_label.text])
		_check(smashed_label != null, "Smashed label exists after %s" % name)
		_check(smashed_label.text != prev_label, "HUD counter advanced after %s" % name)
		prev_label = smashed_label.text
	var debris := 0
	for child in root_node.get_children():
		if child is RigidBody3D:
			debris += 1
	print(("DEBRIS: %d rigid bodies loose in the scene (expect %d: 42 debris + 1 bike; "
			+ "VehicleBody3D is a RigidBody3D)") % [debris, 14 * 3 + 1])
	_check(debris >= 14 * 3 + 1, "all three buildings spawned 14 debris bodies each")

	# ---- hud speed readout sanity (uses bike.speed_kmh)
	print("SPEED: bike speed_kmh = %.1f" % bike.speed_kmh())
	quit(1 if _failures > 0 else 0)
