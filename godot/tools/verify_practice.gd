extends SceneTree
## Offline gate for practice mode (TestRide): the local bike carries
## CombatController in practice_mode, a FIRE touch button is wired, and shots
## leave the barrel without any match lobby being on.
## Exits 1 on any failure.

var _fail := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS ", label)
	else:
		printerr("FAIL ", label)
		_fail += 1


func _initialize() -> void:
	_run()


func _count_projectiles(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		var s: Script = child.get_script()
		if s != null and str(s.resource_path).ends_with("Projectile.gd"):
			count += 1
		count += _count_projectiles(child)
	return count


func _run() -> void:
	await process_frame
	var settings_node := root.get_node_or_null("Settings")
	var sb: Node = root.get_node_or_null("Supabase")
	if sb != null and not bool(sb.get("use_mock")):
		printerr("LIVE BACKEND — refusing to run gate (KIEPIE_MOCK_BACKEND=1 not effective)")
		quit(2)
		return
	var _touch_force_prior: Variant = null
	if settings_node != null:
		_touch_force_prior = settings_node.call("get_value", "controls", "touch_force", false)
		settings_node.call("set_value", "controls", "touch_force", true)

	var match_state: Node = root.get_node("Match")
	_check(not match_state.call("is_playing"),
			"practice mode does not fake an arena lobby")

	var scene := load("res://scenes/TestRide.tscn") as PackedScene
	_check(scene != null, "TestRide scene loads")
	if scene == null:
		quit(1)
		return
	var ride := scene.instantiate() as Node3D
	root.add_child(ride)
	for i in range(6):
		await process_frame

	# ---- streamlined touch overlay removes manual FIRE / TURBO / BRAKE buttons
	var layer := ride.get_node_or_null("TouchHUD") as CanvasLayer
	_check(layer != null, "TouchHUD exists")
	if layer != null:
		for removed in ["BtnFire", "BtnTurbo", "BtnBrake"]:
			_check(layer.get_node_or_null(removed) == null, "%s omitted from streamlined touch overlay" % removed)
	var menu_btn := ride.get_node_or_null("HUD/MenuBtn") as Button
	_check(menu_btn != null and menu_btn.focus_mode == Control.FOCUS_NONE, "TestRide MenuBtn exists with FOCUS_NONE")

	# ---- bike carries practice-mode combat with cannons wired
	var bike := ride.get_node_or_null("KiepieBike") as Node3D
	_check(bike != null, "KiepieBike exists")
	var combat := bike.get_node_or_null("CombatController") if bike != null else null
	_check(combat != null, "bike carries CombatController")
	if combat != null:
		_check(bool(combat.get("practice_mode")), "combat runs in practice mode")
		_check(combat.get("cannons") != null, "SideCannons created for practice cannons")

	# ---- firing through the desktop input path spawns a projectile
	var before := _count_projectiles(ride)
	Input.action_press("fire")
	for i in range(4):
		await process_frame
	Input.action_release("fire")
	for i in range(2):
		await process_frame
	var after := _count_projectiles(ride)
	_check(after > before, "practice fire spawns a projectile (%d -> %d)" % [before, after])

	# ---- mobile touch overlay auto-fires at a forward drum target without manual fire input
	if layer != null and combat != null and bike != null:
		var toggle := layer.get_node_or_null("BtnTouchToggle") as Button
		if toggle != null and not bool(layer.call("is_overlay_active")):
			toggle.pressed.emit()
		var drum := ride.get_node_or_null("FuelDrum0") as Node3D
		if drum != null:
			# Aim the bike toward FuelDrum0 inside forward auto-fire cone
			var look := Vector3(drum.global_position.x, bike.global_position.y, drum.global_position.z)
			bike.look_at(look, Vector3.UP, true)
			combat.set("_auto_fire_cd", 0.0)
			combat.get("cannons").set("_cooldown", 0.0)
			var auto_before := _count_projectiles(ride)
			for i in range(6):
				await process_frame
			var auto_after := _count_projectiles(ride)
			_check(auto_after > auto_before, "mobile overlay auto-fires at forward target (%d -> %d)" % [auto_before, auto_after])
		if toggle != null and bool(layer.call("is_overlay_active")):
			toggle.pressed.emit()  # leave touch overlay off

	# ---- practice damage actually lands (drums can kill the rider)
	if combat != null:
		var hp_before := float(combat.get("health"))
		combat.call("take_damage", 30.0, "audit-practice", Vector3.ZERO)
		var hp_after := float(combat.get("health"))
		_check(hp_after == hp_before - 30.0,
				"practice take_damage applies (%.0f -> %.0f)" % [hp_before, hp_after])

	# ---- cleanup (restore the developer's actual touch_force prior)
	if settings_node != null:
		settings_node.call("set_value", "controls", "touch_force", _touch_force_prior)
	Input.action_release("fire")

	print("PRACTICE: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
