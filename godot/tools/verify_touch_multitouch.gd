extends SceneTree
## Offline gate for two-thumb driving with the new dual analog pads: raw
## InputEventScreenTouch injection proves each finger owns its action, left-pad
## steering/turbo/reverse still work, right-pad gas/fire/dodge work, refcounted
## holds don't leak, and HUD buttons remain clickable.
## TestRide.tscn must NOT be rebuilt — this reads the checked-in scene.

var _failures := 0


func _check(cond: bool, label: String) -> void:
	print(("  PASS  " if cond else "  FAIL  "), label)
	if not cond:
		_failures += 1


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	root.get_viewport().push_input(ev)


func _drag(index: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	root.get_viewport().push_input(ev)


func _mouse(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = pos
	ev.pressed = pressed
	root.get_viewport().push_input(ev)


func _mouse_move(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.get_viewport().push_input(ev)


func _cancel(index: int, pos: Vector2) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = true
	ev.canceled = true
	root.get_viewport().push_input(ev)


func _pad_rect(layer: CanvasLayer, name: String) -> Rect2:
	var pad := layer.get_node_or_null(name) as Control
	return pad.get_global_rect() if pad != null else Rect2()


func _at(layer: CanvasLayer, name: String, x: float, y: float,
		xm: float, ym: float) -> Vector2:
	var r := _pad_rect(layer, name)
	return Vector2(
			r.get_center().x + x * (r.size.x * 0.5 - xm),
			r.get_center().y - y * (r.size.y * 0.5 - ym))


func _steer(layer: CanvasLayer, x: float, y: float) -> Vector2:
	return _at(layer, "AnalogSteer", x, y, 30.0, 10.0)


func _drive(layer: CanvasLayer, x: float, y: float) -> Vector2:
	return _at(layer, "AnalogDrive", x, y, 22.0, 22.0)


func _fire_held(layer: CanvasLayer) -> bool:
	return bool(layer.call("is_fire_held"))


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var settings_node := root.get_node_or_null("Settings")
	var _touch_force_prior: Variant = null
	if settings_node != null:
		_touch_force_prior = settings_node.call("get_value", "controls", "touch_force", false)
		settings_node.call("set_value", "controls", "touch_force", true)

	var scene := load("res://scenes/TestRide.tscn") as PackedScene
	var root_node := scene.instantiate() as Node3D
	root.add_child(root_node)
	for i in range(5):
		await process_frame

	var layer := root_node.get_node_or_null("TouchHUD") as CanvasLayer
	_check(layer != null, "TouchHUD exists")
	if layer == null:
		quit(1)
		return
	_check((layer.get_node("TouchCapture") as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"raw pointer capture layer built with MOUSE_FILTER_IGNORE")
	var right := layer.get_node_or_null("AnalogDrive") as Control
	_check(right != null and right.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"right analog pad does not ride the emulated mouse pointer")

	# ---- one finger on GAS (right pad) + another steering left pad at the same time
	_touch(0, _drive(layer, 0.0, 0.0), true)
	_touch(1, _steer(layer, 1.0, 0.0), true)
	await process_frame
	_check(Input.is_action_pressed("move_forward"), "finger 0 holds gas")
	_check(Input.is_action_pressed("steer_right"), "finger 1 steers right")
	_check(Input.get_action_strength("steer_right") > 0.5, "analog strength flows to get_axis")
	_touch(0, _drive(layer, 0.0, 0.0), false)
	await process_frame
	_check(not Input.is_action_pressed("move_forward"), "finger 0 release only drops gas")
	_check(Input.is_action_pressed("steer_right"), "finger 1 still steering right")
	_touch(1, _steer(layer, 1.0, 0.0), false)
	await process_frame
	_check(not Input.is_action_pressed("steer_right"), "finger 1 release drops steer_right")

	# ---- left pad: half-left, deadzone, sweep left->right
	_touch(2, _steer(layer, -0.5, 0.0), true)
	await process_frame
	_check(Input.is_action_pressed("steer_left"), "pad half-left steers left")
	var half_left := Input.get_action_strength("steer_left")
	_check(half_left > 0.10 and half_left < 0.60, "analog midpoint gives partial strength (%.2f)" % half_left)
	_drag(2, _steer(layer, 0.0, 0.0))
	await process_frame
	_check(not Input.is_action_pressed("steer_left") and not Input.is_action_pressed("steer_right"),
			"pad centre sits inside the deadzone")
	_drag(2, _steer(layer, 1.0, 0.0))
	await process_frame
	_check(Input.is_action_pressed("steer_right"), "sweep to full right engages steer_right")
	_check(not Input.is_action_pressed("steer_left"), "sweep off steer_left releases it")
	_check(Input.get_action_strength("steer_right") > 0.5, "full-right gives near-full strength")
	_touch(2, _steer(layer, 1.0, 0.0), false)
	await process_frame
	_check(not Input.is_action_pressed("steer_right"), "pad release centres the steering")

	# ---- deadzone: resting near the centre never steers
	_touch(2, _steer(layer, 0.05, 0.0), true)
	await process_frame
	_check(not Input.is_action_pressed("steer_left") and not Input.is_action_pressed("steer_right"),
			"touch inside deadzone produces no steer")
	_touch(2, _steer(layer, 0.05, 0.0), false)
	await process_frame

	# ---- left pad push-forward turbo / pull-back reverse (unchanged contract)
	var pad := layer.get_node_or_null("AnalogSteer") as Control
	_touch(2, _steer(layer, 0.0, 0.20), true)
	await process_frame
	_check(not Input.is_action_pressed("turbo"), "slight vertical offset inside band does not engage turbo")
	_drag(2, _steer(layer, 0.85, 0.90))
	await process_frame
	_check(Input.is_action_pressed("turbo"), "pushing left pad forward engages turbo")
	_check(Input.is_action_pressed("steer_right"), "pushing forward-right still steers right")
	_check(pad != null and bool(pad.get("turbo_active")), "AnalogSteer view reflects turbo_active=true")
	_drag(2, _steer(layer, 0.85, 0.0))
	await process_frame
	_check(not Input.is_action_pressed("turbo"), "returning to vertical centre drops turbo")
	_check(Input.is_action_pressed("steer_right"), "returning to centre keeps horizontal steer_right")
	_check(pad != null and not bool(pad.get("turbo_active")), "AnalogSteer view reflects turbo_active=false")
	_drag(2, _steer(layer, 0.0, -0.90))
	await process_frame
	_check(Input.is_action_pressed("move_back"), "pulling left pad back engages move_back (brake/reverse)")
	_check(right != null and bool(right.get("gas_active")) == false, "right pad gas not latched by left pad")
	_check(pad != null and bool(pad.get("reverse_active")), "AnalogSteer view reflects reverse_active=true")
	_drag(2, _steer(layer, 0.0, 0.0))
	await process_frame
	_check(not Input.is_action_pressed("move_back"), "returning left pad to centre drops move_back")
	_touch(2, _steer(layer, 0.0, 0.0), false)
	await process_frame

	# ---- right pad: UP holds fire, DOWN never fires, release stops
	_touch(3, _drive(layer, 0.0, 0.0), true)
	await process_frame
	_check(not _fire_held(layer), "right pad centre fires nothing")
	_drag(3, _drive(layer, 0.0, 1.0))
	await process_frame
	_check(_fire_held(layer), "right pad UP holds fire")
	_check(right != null and bool(right.get("fire_active")), "AnalogDrive view reflects fire_active=true")
	_drag(3, _drive(layer, 0.0, 0.0))
	await process_frame
	_check(not _fire_held(layer), "right pad centre releases fire")
	_drag(3, _drive(layer, 0.0, -1.0))
	await process_frame
	_check(not _fire_held(layer), "right pad DOWN does not fire")
	_touch(3, _drive(layer, 0.0, -1.0), false)
	await process_frame

	# ---- right pad dodge: one edge per deflection, re-arm on centre
	_touch(4, _drive(layer, -1.0, 0.0), true)
	await process_frame
	_check(Input.is_action_pressed("dodge_left"), "right pad LEFT engages dodge_left")
	_check(right != null and bool(right.get("dodge_left_active")), "AnalogDrive view reflects dodge_left_active")
	_drag(4, _drive(layer, 0.0, 0.0))
	await process_frame
	_check(not Input.is_action_pressed("dodge_left"), "centring releases dodge_left (re-arms)")
	_drag(4, _drive(layer, 1.0, 0.0))
	await process_frame
	_check(Input.is_action_pressed("dodge_right"), "right pad RIGHT engages dodge_right")
	_check(not Input.is_action_pressed("dodge_left"), "sweep off dodge_left releases it")
	_touch(4, _drive(layer, 1.0, 0.0), false)
	await process_frame
	_check(not Input.is_action_pressed("dodge_right"), "right pad release drops dodge_right")

	# ---- the gesture must reach KiepieBike's cartwheel, not just set an action
	var dodge_bike := root_node.get_node_or_null("KiepieBike") as VehicleBody3D
	if dodge_bike != null:
		dodge_bike.call("reset_bike")
		var grounded := false
		for _f in range(150):
			await physics_frame
			if float(dodge_bike.get("_ground_coyote")) > 0.0:
				grounded = true
				break
		_check(grounded, "right-pad dodge test starts with wheels down")
		if grounded:
			_touch(14, _drive(layer, -1.0, 0.0), true)
			for _f in range(6):
				await physics_frame
				await process_frame
			_check(float(dodge_bike.get("_dodge_time")) > 0.0 or float(dodge_bike.get("_dodge_cd")) > 0.0,
					"right-pad LEFT launches the bike's cartwheel dodge")
			_touch(14, _drive(layer, -1.0, 0.0), false)
			for _f in range(2):
				await process_frame

	# ---- two fingers on the right pad: gas is refcounted; one lift keeps hold
	_touch(0, _drive(layer, 0.0, 0.0), true)
	_touch(1, _drive(layer, 0.0, 0.0), true)
	await process_frame
	_touch(0, _drive(layer, 0.0, 0.0), false)
	await process_frame
	_check(Input.is_action_pressed("move_forward"), "second finger keeps GAS held")
	_touch(1, _drive(layer, 0.0, 0.0), false)
	await process_frame
	_check(not Input.is_action_pressed("move_forward"), "both fingers lifted drops GAS")

	# ---- paired emulated mouse must not double-trigger dodge or leak gas
	_touch(0, _drive(layer, -1.0, 0.0), true)
	_mouse(_drive(layer, -1.0, 0.0), true)
	await process_frame
	_touch(0, _drive(layer, -1.0, 0.0), false)
	_mouse(_drive(layer, -1.0, 0.0), false)
	await process_frame
	_check(not Input.is_action_pressed("dodge_left"), "dodge released after touch+emulated pair")
	_check(not Input.is_action_pressed("move_forward"), "gas released after touch+emulated pair")
	_touch(1, _steer(layer, 1.0, 0.0), true)
	await process_frame
	_check(Input.is_action_pressed("steer_right"), "other finger unaffected by pair completion")
	_touch(1, _steer(layer, 1.0, 0.0), false)
	await process_frame

	# ---- desktop mouse drives the right pad with no touch at all
	_mouse(_drive(layer, 0.0, 0.0), true)
	await process_frame
	_check(Input.is_action_pressed("move_forward"), "desktop mouse holds GAS on right pad")
	_mouse_move(_drive(layer, 0.0, 1.0))
	await process_frame
	_check(_fire_held(layer), "desktop mouse push-up holds fire")
	_mouse(_drive(layer, 0.0, 1.0), false)
	await process_frame
	_check(not Input.is_action_pressed("move_forward") and not _fire_held(layer),
			"desktop mouse release drops GAS and fire")

	# ---- canceled touch releases a held finger
	_touch(5, _drive(layer, 0.0, 0.0), true)
	_mouse(_drive(layer, 0.0, 0.0), true)
	_touch(6, _steer(layer, 1.0, 0.0), true)
	_mouse(_steer(layer, 1.0, 0.0), true)
	await process_frame
	_check(Input.is_action_pressed("move_forward"), "cancel test: gas held before cancel")
	_cancel(5, _drive(layer, 0.0, 0.0))
	await process_frame
	_check(not Input.is_action_pressed("move_forward"), "canceled gas finger releases gas")
	_check(Input.is_action_pressed("steer_right"), "canceled other finger unaffected")
	_touch(6, _steer(layer, 1.0, 0.0), false)
	_mouse(_steer(layer, 1.0, 0.0), false)
	await process_frame
	# cancel on the right pad while firing
	_touch(7, _drive(layer, 0.0, 1.0), true)
	_mouse(_drive(layer, 0.0, 1.0), true)
	await process_frame
	_check(_fire_held(layer), "right pad fire held before cancel")
	_cancel(7, _drive(layer, 0.0, 1.0))
	await process_frame
	_check(not _fire_held(layer), "canceled right-pad finger releases fire")

	# ---- focus-out during a right-pad sweep
	_touch(8, _drive(layer, -1.0, 0.0), true)
	_drag(8, _drive(layer, 1.0, 0.0))
	await process_frame
	_check(Input.is_action_pressed("dodge_right"), "right-pad sweep in place before interruption")
	layer._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await process_frame
	_check(not Input.is_action_pressed("dodge_left") and not Input.is_action_pressed("dodge_right"),
			"focus-out releases dodge actions")
	_check(not Input.is_action_pressed("move_forward") and not _fire_held(layer),
			"focus-out releases gas and fire")
	_touch(8, _drive(layer, 1.0, 0.0), false)
	await process_frame

	# ---- multi-finger simultaneous: gas + fire (right pad) + steer/turbo (left pad)
	_touch(9, _drive(layer, 0.0, 0.0), true)   # gas owner
	_touch(10, _drive(layer, 0.0, 1.0), true)  # newest right-pad finger owns fire
	_touch(11, _steer(layer, 1.0, 0.90), true)
	await process_frame
	_check(Input.is_action_pressed("move_forward") and _fire_held(layer)
			and Input.is_action_pressed("steer_right") and Input.is_action_pressed("turbo"),
			"simultaneous gas + fire + analog steer/turbo all held")
	for i in [9, 10, 11]:
		var spots := {9: func() -> Vector2: return _drive(layer, 0.0, 0.0),
					10: func() -> Vector2: return _drive(layer, 0.0, 1.0),
					11: func() -> Vector2: return _steer(layer, 1.0, 0.90)}
		_touch(i, spots[i].call(), false)
	await process_frame
	_check(not Input.is_action_pressed("move_forward") and not _fire_held(layer)
			and not Input.is_action_pressed("steer_right") and not Input.is_action_pressed("turbo"),
			"all simultaneous fingers released")

	# ---- opposing right-pad vectors: newest finger owns fire/dodge, no stuck pair
	_touch(12, _drive(layer, 0.0, 1.0), true)
	await process_frame
	_check(_fire_held(layer) and not Input.is_action_pressed("dodge_left"),
			"right pad UP holds fire, not dodge")
	_touch(13, _drive(layer, -1.0, 0.0), true)
	await process_frame
	_check(Input.is_action_pressed("dodge_left") and not _fire_held(layer),
			"newest opposing pad vector wins (no stuck fire+dodge)")
	_touch(13, _drive(layer, -1.0, 0.0), false)
	await process_frame
	_check(_fire_held(layer) and not Input.is_action_pressed("dodge_left"),
			"remaining finger resumes when newest lifts")
	_touch(12, _drive(layer, 0.0, 1.0), false)
	await process_frame

	# ---- OS interruption drops everything this layer holds
	_touch(0, _drive(layer, 0.0, 0.0), true)
	_touch(1, _steer(layer, 1.0, 0.0), true)
	layer._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await process_frame
	_check(not Input.is_action_pressed("move_forward"), "focus-out releases gas")
	_check(not Input.is_action_pressed("steer_right"), "focus-out releases steer")

	# ---- HUD & toggle buttons are never blocked by TouchCapture (mouse click + touch tap)
	var hud := root_node.get_node_or_null("HUD") as CanvasLayer
	var bike := root_node.get_node_or_null("KiepieBike") as VehicleBody3D
	var rig := root_node.get_node_or_null("CameraRig")
	if hud != null and bike != null:
		var rbtn := hud.get_node_or_null("RestartBtn") as Button
		var vbtn := hud.get_node_or_null("ViewBtn") as Button
		var tbtn := layer.get_node_or_null("BtnTouchToggle") as Button
		if rbtn != null:
			var spawn_pos: Vector3 = (bike.get("_spawn") as Transform3D).origin
			bike.global_position = spawn_pos + Vector3(12.0, 1.5, 16.0)
			for _f in range(3):
				await physics_frame
				await process_frame
			var rc := rbtn.get_global_rect().get_center()
			_mouse(rc, true)
			await process_frame
			_mouse(rc, false)
			for _f in range(4):
				await physics_frame
				await process_frame
			_check(bike.global_position.distance_to(spawn_pos) < 1.5,
					"RestartBtn mouse click resets bike back to spawn (dist=%.2f)" % bike.global_position.distance_to(spawn_pos))
			bike.global_position = spawn_pos + Vector3(-10.0, 1.5, 14.0)
			for _f in range(3):
				await physics_frame
				await process_frame
			var rkey := InputEventKey.new()
			rkey.keycode = KEY_R
			rkey.physical_keycode = KEY_R
			rkey.pressed = true
			root.get_viewport().push_input(rkey)
			await physics_frame
			await process_frame
			rkey.pressed = false
			root.get_viewport().push_input(rkey)
			for _f in range(4):
				await physics_frame
				await process_frame
			_check(bike.global_position.distance_to(spawn_pos) < 1.5,
					"R key reset returns bike back to spawn (dist=%.2f)" % bike.global_position.distance_to(spawn_pos))
		if vbtn != null and rig != null:
			var mode_before := str(rig.get("mode"))
			var vc := vbtn.get_global_rect().get_center()
			_mouse(vc, true)
			await process_frame
			_mouse(vc, false)
			await process_frame
			_check(str(rig.get("mode")) != mode_before, "ViewBtn mouse click toggles camera mode")
		if tbtn != null:
			var was_on := bool(layer.call("is_overlay_active"))
			var tc := tbtn.get_global_rect().get_center()
			_mouse(tc, true)
			await process_frame
			_mouse(tc, false)
			await process_frame
			_check(bool(layer.call("is_overlay_active")) != was_on, "BtnTouchToggle click toggles overlay")

	# ---- cleanup: never leak state into other gates
	for a in ["move_forward", "move_back", "steer_left", "steer_right", "turbo",
			"dodge_left", "dodge_right", "fire"]:
		Input.action_release(a)
	if settings_node != null:
		settings_node.call("set_value", "controls", "touch_force", _touch_force_prior)
	Input.action_release("reset_bike")

	print("TOUCH MULTITOUCH: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)
