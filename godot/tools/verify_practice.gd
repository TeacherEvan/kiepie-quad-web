extends SceneTree
## Offline gate for practice mode (TestRide): the local bike carries
## CombatController in practice_mode, mobile uses target-locked auto-fire,
## shots fire continuously on cooldown without overheat, and Restart works.
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


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	root.get_viewport().push_input(ev)


func _mouse(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = pos
	ev.pressed = pressed
	root.get_viewport().push_input(ev)


func _btn_centre(layer: CanvasLayer, btn_name: String) -> Vector2:
	var btn := layer.get_node_or_null(btn_name) as Button
	return btn.get_global_rect().get_center() if btn != null else Vector2.ZERO


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
		# Start with the overlay OFF so the desktop hold-to-fire path is exercised;
		# the mobile section flips it on (as the TOUCH toggle does in-game).
		settings_node.call("set_value", "controls", "touch_force", false)

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

	# ---- firing through the desktop input path spawns projectiles continuously (hold-to-fire)
	var before := _count_projectiles(ride)
	var cannons_ref := combat.get("cannons") as Node if combat != null else null
	var shot_cycles := [0]
	if cannons_ref != null and cannons_ref.has_signal("fired"):
		cannons_ref.connect("fired", func(_tok: String) -> void: shot_cycles[0] += 1)
	Input.action_press("fire")
	for i in range(22):
		await physics_frame
		await process_frame
	Input.action_release("fire")
	for i in range(2):
		await process_frame
	var after := _count_projectiles(ride)
	_check(after > before, "practice fire spawns a projectile (%d -> %d)" % [before, after])
	_check(shot_cycles[0] >= 2, "holding desktop fire continuously fires across cooldown (%d cycles)" % shot_cycles[0])

	# ---- mobile touch overlay auto-fires at a forward drum target without manual fire input
	if layer != null and combat != null and bike != null:
		var toggle := layer.get_node_or_null("BtnTouchToggle") as Button
		if toggle != null and not bool(layer.call("is_overlay_active")):
			toggle.pressed.emit()
		var drum := ride.get_node_or_null("FuelDrum0") as Node3D
		if drum != null:
			var look := Vector3(drum.global_position.x, bike.global_position.y, drum.global_position.z)
			# (A) gas finger held while aiming AWAY from every target: the emulated
			# mouse pair must not free-fire the cannons and auto-fire must stay
			# silent without a target. This is the regression the desktop-only
			# hold-to-fire test could not see.
			var away_dir := Vector3(bike.global_position.x - drum.global_position.x, 0.0,
					bike.global_position.z - drum.global_position.z)
			if away_dir.length_squared() < 0.01:
				away_dir = Vector3(0.0, 0.0, 1.0)
			bike.look_at(bike.global_position + away_dir, Vector3.UP, true)
			combat.set("_auto_fire_cd", 0.0)
			combat.get("cannons").set("_cooldown", 0.0)
			var un_aimed_before := _count_projectiles(ride)
			_touch(0, _btn_centre(layer, "BtnGas"), true)
			_mouse(_btn_centre(layer, "BtnGas"), true)   # paired emulated mouse press
			for i in range(6):
				await process_frame
			var un_aimed_after := _count_projectiles(ride)
			_check(un_aimed_after == un_aimed_before,
					"gas held away from target fires nothing (%d -> %d)" % [un_aimed_before, un_aimed_after])
			# (B) same finger still held, now aimed at FuelDrum0 inside the
			# forward auto-fire cone: auto-fire must trigger.
			bike.look_at(look, Vector3.UP, true)
			combat.set("_auto_fire_cd", 0.0)
			combat.get("cannons").set("_cooldown", 0.0)
			var auto_before := _count_projectiles(ride)
			for i in range(6):
				await process_frame
			var auto_after := _count_projectiles(ride)
			_check(auto_after > auto_before, "mobile overlay auto-fires at forward target (%d -> %d)" % [auto_before, auto_after])
			_touch(0, _btn_centre(layer, "BtnGas"), false)
			_mouse(_btn_centre(layer, "BtnGas"), false)
			# Repeated shots never overheat or lock out automatic firing, and heat signals/props are absent.
			var cannons_node := combat.get("cannons") as Node
			if cannons_node != null:
				for _s in range(8):
					cannons_node.set("_cooldown", 0.0)
					cannons_node.call("fire")
				cannons_node.set("_cooldown", 0.0)
				_check(not ("overheated" in cannons_node) and not ("heat" in cannons_node)
						and not cannons_node.has_signal("heat_changed")
						and not combat.has_signal("heat_changed")
						and bool(cannons_node.call("can_fire")),
						"cannons have no overheat state and keep can_fire after repeated shots")
		if toggle != null and bool(layer.call("is_overlay_active")):
			toggle.pressed.emit()  # leave touch overlay off
	_check(ride.get_node_or_null("HUD/HeatBar") == null and ride.get_node_or_null("HUD/HeatLabel") == null,
			"HeatBar and HeatLabel removed from HUD")

	# ---- practice damage actually lands (drums can kill the rider) & Restart recovers cleanly
	if combat != null and bike != null:
		var hp_before := float(combat.get("health"))
		combat.call("take_damage", 30.0, "audit-practice", Vector3.ZERO)
		var hp_after := float(combat.get("health"))
		_check(hp_after == hp_before - 30.0,
				"practice take_damage applies (%.0f -> %.0f)" % [hp_before, hp_after])
		var spawn_origin: Vector3 = (bike.get("_spawn") as Transform3D).origin
		bike.global_position = spawn_origin + Vector3(8.0, 0.0, 10.0)
		combat.call("take_damage", 150.0, "audit-practice", Vector3.ZERO)
		_check(not bool(combat.get("alive")) and not bike.visible,
				"lethal damage kills and hides practice bike")
		var rbtn := ride.get_node_or_null("HUD/RestartBtn") as Button
		if rbtn != null:
			rbtn.pressed.emit()
		for _f in range(4):
			await physics_frame
			await process_frame
		_check(bool(combat.get("alive")) and float(combat.get("health")) == 100.0 and bike.visible
				and bike.global_position.distance_to(spawn_origin) < 1.5,
				"RestartBtn revives dead practice rider and resets bike to spawn")

	# ---- cleanup (restore the developer's actual touch_force prior)
	if settings_node != null:
		settings_node.call("set_value", "controls", "touch_force", _touch_force_prior)
	Input.action_release("fire")

	print("PRACTICE: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
