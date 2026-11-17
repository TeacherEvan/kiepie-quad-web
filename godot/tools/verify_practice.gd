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
	if settings_node != null:
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

	# ---- touch overlay exposes FIRE
	var layer := ride.get_node_or_null("TouchHUD") as CanvasLayer
	_check(layer != null, "TouchHUD exists")
	var fire := layer.get_node_or_null("BtnFire") as Button if layer != null else null
	_check(fire != null, "BtnFire exists for touch players")
	if fire != null:
		_check(fire.focus_mode == Control.FOCUS_NONE, "BtnFire focus_mode == FOCUS_NONE")
		var s := Vector2(absf(fire.offset_right - fire.offset_left), absf(fire.offset_bottom - fire.offset_top))
		_check(s.x >= 44.0 and s.y >= 44.0, "BtnFire target >= 44x44 (got %.0fx%.0f)" % [s.x, s.y])
		# wired to the fire action by the overlay
		fire.button_down.emit()
		_check(Input.is_action_pressed("fire"), "BtnFire button_down holds 'fire'")
		fire.button_up.emit()
		_check(not Input.is_action_pressed("fire"), "BtnFire button_up releases 'fire'")

	# ---- bike carries practice-mode combat with cannons wired
	var bike := ride.get_node_or_null("KiepieBike") as Node3D
	_check(bike != null, "KiepieBike exists")
	var combat := bike.get_node_or_null("CombatController") if bike != null else null
	_check(combat != null, "bike carries CombatController")
	if combat != null:
		_check(bool(combat.get("practice_mode")), "combat runs in practice mode")
		_check(combat.get("cannons") != null, "SideCannons created for practice cannons")

	# ---- firing through the real input path spawns a projectile
	var before := _count_projectiles(ride)
	Input.action_press("fire")
	for i in range(4):
		await process_frame
	Input.action_release("fire")
	for i in range(2):
		await process_frame
	var after := _count_projectiles(ride)
	_check(after > before, "practice fire spawns a projectile (%d -> %d)" % [before, after])

	# ---- cleanup
	if settings_node != null:
		settings_node.call("set_value", "controls", "touch_force", false)
	Input.action_release("fire")

	print("PRACTICE: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
