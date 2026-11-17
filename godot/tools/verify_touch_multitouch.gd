extends SceneTree
## Offline gate for two-thumb driving: raw InputEventScreenTouch injection proves
## every finger owns its own action, steering slides work, and refcounted holds
## don't leak when two fingers land on the same button.
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
	ev.pressed = true if pressed else false
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


func _cancel(index: int, pos: Vector2) -> void:
	# OS edge gesture cancels a finger with no paired pressed=false.
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = true
	ev.canceled = true
	root.get_viewport().push_input(ev)


func _centre(layer: CanvasLayer, btn_name: String) -> Vector2:
	var btn := layer.get_node_or_null(btn_name) as Button
	return btn.get_global_rect().get_center() if btn != null else Vector2.ZERO


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var settings_node := root.get_node_or_null("Settings")
	if settings_node != null:
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
	_check(layer.get_node_or_null("TouchCapture") != null, "raw pointer capture layer built")
	_check((layer.get_node("BtnGas") as Button).mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"drive buttons do not ride the single emulated mouse pointer")

	# ---- one finger on GAS + another on STEER-RIGHT at the same time
	_touch(0, _centre(layer, "BtnGas"), true)
	_touch(1, _centre(layer, "BtnRight"), true)
	await process_frame
	_check(Input.is_action_pressed("move_forward"), "finger 0 holds move_forward")
	_check(Input.is_action_pressed("steer_right"), "finger 1 holds steer_right")
	# ---- lifting one finger leaves the other untouched
	_touch(0, _centre(layer, "BtnGas"), false)
	await process_frame
	_check(not Input.is_action_pressed("move_forward"), "finger 0 release only drops move_forward")
	_check(Input.is_action_pressed("steer_right"), "finger 1 still holds steer_right")
	_touch(1, _centre(layer, "BtnRight"), false)
	await process_frame
	_check(not Input.is_action_pressed("steer_right"), "finger 1 release drops steer_right")

	# ---- two fingers on the same button: refcounted, one lift keeps the hold
	_touch(0, _centre(layer, "BtnTurbo"), true)
	_touch(1, _centre(layer, "BtnTurbo"), true)
	await process_frame
	_touch(0, _centre(layer, "BtnTurbo"), false)
	await process_frame
	_check(Input.is_action_pressed("turbo"), "second finger keeps turbo held")
	_touch(1, _centre(layer, "BtnTurbo"), false)
	await process_frame
	_check(not Input.is_action_pressed("turbo"), "both fingers lifted drops turbo")

	# ---- steering slide: finger on LEFT slides onto RIGHT, swaps actions
	_touch(2, _centre(layer, "BtnLeft"), true)
	await process_frame
	_check(Input.is_action_pressed("steer_left"), "slide starts on steer_left")
	_drag(2, _centre(layer, "BtnRight"))
	await process_frame
	_check(not Input.is_action_pressed("steer_left"), "slide off steer_left releases it")
	_check(Input.is_action_pressed("steer_right"), "slide onto steer_right engages it")
	_touch(2, _centre(layer, "BtnRight"), false)
	await process_frame

	# ---- dodge slide pair works the same way
	_touch(3, _centre(layer, "BtnDodgeLeft"), true)
	await process_frame
	_drag(3, _centre(layer, "BtnDodgeRight"))
	await process_frame
	_check(not Input.is_action_pressed("dodge_left"), "dodge slide leaves dodge_left")
	_check(Input.is_action_pressed("dodge_right"), "dodge slide engages dodge_right")
	_touch(3, _centre(layer, "BtnDodgeRight"), false)
	await process_frame

	# ---- gas does NOT swap to brake/turbo on a stray vertical slide
	_touch(4, _centre(layer, "BtnGas"), true)
	await process_frame
	_drag(4, _centre(layer, "BtnBrake"))
	await process_frame
	_check(Input.is_action_pressed("move_forward"), "gas is slide-latched, not swap-prone")
	_check(not Input.is_action_pressed("move_back"), "gas slide does not engage brake")
	_touch(4, _centre(layer, "BtnBrake"), false)
	await process_frame
	_check(not Input.is_action_pressed("move_forward"), "gas finger released")

	# ---- paired emulated mouse stream must not leak or double-drop
	_touch(0, _centre(layer, "BtnGas"), true)
	_mouse(_centre(layer, "BtnGas"), true)   # emulated pair
	_touch(0, _centre(layer, "BtnGas"), false)
	_mouse(_centre(layer, "BtnGas"), false)
	_touch(1, _centre(layer, "BtnTurbo"), true)  # left holding turbo while pair completes
	await process_frame
	_check(not Input.is_action_pressed("move_forward"), "gas released after touch+emulated pair")
	_check(Input.is_action_pressed("turbo"), "other finger unaffected by pair completion")
	_touch(1, _centre(layer, "BtnTurbo"), false)
	await process_frame
	_check(not Input.is_action_pressed("turbo"), "turbo released cleanly")

	# ---- desktop mouse click drives the button with no touch at all
	_mouse(_centre(layer, "BtnGas"), true)
	await process_frame
	_check(Input.is_action_pressed("move_forward"), "desktop mouse holds GAS")
	_mouse(_centre(layer, "BtnGas"), false)
	await process_frame
	_check(not Input.is_action_pressed("move_forward"), "desktop mouse release drops GAS")

	# ---- canceled touch (OS edge gesture) releases a held finger
	_touch(5, _centre(layer, "BtnGas"), true)
	_touch(6, _centre(layer, "BtnRight"), true)
	await process_frame
	_check(Input.is_action_pressed("move_forward"), "cancel test: gas held before cancel")
	_cancel(5, _centre(layer, "BtnGas"))
	await process_frame
	_check(not Input.is_action_pressed("move_forward"), "canceled gas finger releases move_forward")
	_check(Input.is_action_pressed("steer_right"), "canceled other finger unaffected")
	_touch(6, _centre(layer, "BtnRight"), false)
	await process_frame

	# ---- focus-out in the middle of a steering slide
	_touch(7, _centre(layer, "BtnLeft"), true)
	_drag(7, _centre(layer, "BtnRight"))
	await process_frame
	_check(Input.is_action_pressed("steer_right"), "slide in place before interruption")
	layer._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await process_frame
	_check(not Input.is_action_pressed("steer_left"), "focus-out mid-slide releases steer_left")
	_check(not Input.is_action_pressed("steer_right"), "focus-out mid-slide releases steer_right")

	# ---- four fingers at once: gas + steer + turbo + brake
	_touch(8, _centre(layer, "BtnGas"), true)
	_touch(9, _centre(layer, "BtnRight"), true)
	_touch(10, _centre(layer, "BtnTurbo"), true)
	_touch(11, _centre(layer, "BtnBrake"), true)
	await process_frame
	_check(Input.is_action_pressed("move_forward") and Input.is_action_pressed("steer_right")
			and Input.is_action_pressed("turbo") and Input.is_action_pressed("move_back"),
			"four simultaneous fingers all held")
	for i in [8, 9, 10, 11]:
		var names := {8: "BtnGas", 9: "BtnRight", 10: "BtnTurbo", 11: "BtnBrake"}
		_touch(i, _centre(layer, names[i]), false)
	await process_frame
	_check(not Input.is_action_pressed("move_forward") and not Input.is_action_pressed("steer_right")
			and not Input.is_action_pressed("turbo") and not Input.is_action_pressed("move_back"),
			"all four released")

	# ---- OS interruption drops everything this layer holds
	_touch(0, _centre(layer, "BtnGas"), true)
	_touch(1, _centre(layer, "BtnRight"), true)
	layer._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await process_frame
	_check(not Input.is_action_pressed("move_forward"), "focus-out releases gas")
	_check(not Input.is_action_pressed("steer_right"), "focus-out releases steer")

	# ---- cleanup: never leak state into other gates
	for a in ["move_forward", "move_back", "steer_left", "steer_right", "turbo",
			"dodge_left", "dodge_right", "fire"]:
		Input.action_release(a)
	if settings_node != null:
		settings_node.call("set_value", "controls", "touch_force", false)
	Input.action_release("reset_bike")

	print("TOUCH MULTITOUCH: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)
