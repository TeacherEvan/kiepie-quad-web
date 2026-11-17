extends SceneTree
# Headless gate for the touch overlay (Task 5).
# Checks: TouchHUD exists, buttons focus NONE with >=44px touch targets,
# button_down/up drive the right InputMap actions, the TOUCH toggle forces
# visibility, the stuck-key reconcile releases unpressed-but-held actions
# without touching keyboard-held actions, hiding releases everything, and the
# focus-out notification releases this layer's held actions.
# NOTE (known limitation): button_down/up are emitted synthetically, so the
# reconcile branch (is_pressed()==false mid-hold) passes trivially; a real
# gesture keeps press state until button_up by engine design. The focus-out
# leg and the toggle-hide leg cover the genuine stuck-throttle vectors.
# Exits 1 on any failure.

var _failures := 0

func _check(cond: bool, label: String) -> void:
	print(("  PASS  " if cond else "  FAIL  "), label)
	if not cond:
		_failures += 1

func _btn_size(b: Button) -> Vector2:
	return Vector2(absf(b.offset_right - b.offset_left), absf(b.offset_bottom - b.offset_top))

func _initialize() -> void:
	# The overlay now persists the TOUCH override, so clear it BEFORE the
	# scene's TouchControls._ready() reads it — otherwise a previous run
	# leaving it ON would change this gate's assumptions.
	await process_frame
	var settings_node := get_root().get_node_or_null("Settings")
	if settings_node != null:
		settings_node.call("set_value", "controls", "touch_force", false)

	var scene: PackedScene = load("res://scenes/TestRide.tscn")
	var root_node := scene.instantiate() as Node3D
	get_root().add_child(root_node)
	await process_frame

	# ---- regression: an action held BEFORE the overlay's deferred _ready fires
	# (keyboard, tests, or a parent scene) must survive untouched
	Input.action_press("move_forward")
	await process_frame
	await process_frame
	_check(Input.is_action_pressed("move_forward"),
			"externally-held action survives overlay first frames")
	Input.action_release("move_forward")

	# ---- presence + wiring
	var layer := root_node.get_node_or_null("TouchHUD")
	_check(layer != null, "TouchHUD node exists")
	if layer == null:
		quit(1)
		return
	_check(layer is CanvasLayer, "TouchHUD is a CanvasLayer")
	_check(layer.get_script() != null
				and str(layer.get_script().resource_path).ends_with("TouchControls.gd"),
			"TouchHUD runs TouchControls.gd")
	var gas_visible: bool = (layer.get_node("BtnGas") as Button).visible
	print("  info  touchscreen_available=%s drive_visible=%s (headless expects false/false)"
			% [DisplayServer.is_touchscreen_available(), gas_visible])
	var toggle_btn := layer.get_node_or_null("BtnTouchToggle") as Button
	_check(toggle_btn != null and toggle_btn.visible,
			"TOUCH toggle stays visible when drive buttons are hidden")

	# ---- buttons: presence, focus mode, touch-target size
	var names := ["BtnGas", "BtnBrake", "BtnTurbo",
			"BtnFire", "BtnDodgeLeft", "BtnDodgeRight", "BtnTouchToggle"]
	var btns := {}
	for n in names:
		var b := layer.get_node_or_null(n) as Button
		_check(b != null, "%s exists" % n)
		if b:
			btns[n] = b
			_check(b.focus_mode == Control.FOCUS_NONE, "%s focus_mode == FOCUS_NONE" % n)
			var s := _btn_size(b)
			_check(s.x >= 44.0 and s.y >= 44.0, "%s target >= 44x44 (got %.0fx%.0f)" % [n, s.x, s.y])

	# ---- analog steering pad: present, >=44x44, does not overlap dodge pair
	var pad := layer.get_node_or_null("AnalogSteer") as Control
	_check(pad != null and pad is Control, "AnalogSteer pad exists")
	if pad != null:
		_check(pad.focus_mode == Control.FOCUS_NONE, "AnalogSteer focus_mode == FOCUS_NONE")
	if pad != null:
		var pr := pad.get_global_rect()
		_check(pr.size.x >= 44.0 and pr.size.y >= 44.0,
				"AnalogSteer target >= 44x44 (got %.0fx%.0f)" % [pr.size.x, pr.size.y])
		for dn in ["BtnDodgeLeft", "BtnDodgeRight"]:
			var d := btns.get(dn) as Button
			if d != null:
				var drect := Rect2(d.get_global_rect())
				_check(not pr.intersects(drect), "AnalogSteer does not overlap %s" % dn)

	# ---- no two drive buttons may overlap (the Arena TURBO/BRAKE pair once did)
	var rects := {}
	for n in btns:
		if n == "BtnTouchToggle":
			continue
		var b: Button = btns[n]
		rects[n] = Rect2(Vector2(b.offset_left, b.offset_top), _btn_size(b))
	var keys := rects.keys()
	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			var a: String = keys[i]
			var c: String = keys[j]
			_check(not rects[a].intersects(rects[c]),
					"%s and %s touch targets do not overlap" % [a, c])

	# ---- action wiring: button_down/up -> InputMap actions
	var pairs := {"BtnGas": "move_forward", "BtnBrake": "move_back",
			"BtnTurbo": "turbo", "BtnFire": "fire",
			"BtnDodgeLeft": "dodge_left", "BtnDodgeRight": "dodge_right"}
	for n in pairs:
		var action: String = pairs[n]
		var b: Button = btns.get(n)
		if b == null:
			continue
		b.button_down.emit()
		_check(Input.is_action_pressed(action), "%s button_down holds '%s'" % [n, action])
		b.button_up.emit()
		_check(not Input.is_action_pressed(action), "%s button_up releases '%s'" % [n, action])

	# ---- stuck-key reconcile: touch pressed, button never released -> action freed
	var gas: Button = btns.get("BtnGas")
	if gas:
		gas.button_down.emit()  # deliberately no button_up (finger slid off)
		for i in range(3):
			await process_frame
		_check(not Input.is_action_pressed("move_forward"),
				"stuck-key reconcile frees unpressed-held action")

	# ---- reconcile must not touch keyboard-held actions
	Input.action_press("steer_left")
	for i in range(3):
		await process_frame
	_check(Input.is_action_pressed("steer_left"), "keyboard-held action survives reconcile")
	Input.action_release("steer_left")

	# ---- TOUCH toggle forces visibility and hiding releases held actions
	var toggle: Button = btns.get("BtnTouchToggle")
	if toggle:
		toggle.pressed.emit()
		_check((layer.get_node("BtnGas") as Button).visible, "toggle ON shows drive buttons")
		_check((layer.get_node("BtnDodgeLeft") as Button).visible,
				"toggle ON shows dodge buttons")
		_check(toggle.text == "TOUCH: ON", "toggle label reads TOUCH: ON")
		gas = btns.get("BtnGas")
		if gas:
			gas.button_down.emit()
		toggle.pressed.emit()  # hide again
		_check(not (layer.get_node("BtnGas") as Button).visible, "toggle OFF hides drive buttons")
		_check(toggle.text == "TOUCH: AUTO", "toggle label returns to TOUCH: AUTO")
		_check(not Input.is_action_pressed("move_forward"), "hiding overlay releases held actions")

	# ---- focus-out releases this layer's held actions (phone call / shade pull)
	gas = btns.get("BtnGas")
	if gas:
		gas.button_down.emit()
		layer._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		_check(not Input.is_action_pressed("move_forward"), "focus-out releases held action")

	# ---- exit-tree safety
	toggle = btns.get("BtnTouchToggle")
	if toggle and not (layer.get_node("BtnGas") as Button).visible:
		toggle.pressed.emit()  # force drive buttons visible again
	gas = btns.get("BtnGas")
	if gas:
		gas.button_down.emit()
	layer.queue_free()
	for i in range(3):
		await process_frame
	_check(not Input.is_action_pressed("move_forward"), "overlay exit releases held actions")

	# ---- cleanup any stray action state
	for a in ["move_forward", "move_back", "steer_left", "steer_right", "turbo",
			"dodge_left", "dodge_right", "reset_bike"]:
		Input.action_release(a)

	print("TOUCH VERIFY: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)
