extends SceneTree
# Headless gate for the two-pad touch overlay (Task 5).
# Locks: TouchHUD with both runtime analog pads (AnalogSteer left, AnalogDrive
# right), no legacy GAS / L-R dodge buttons, >=44px non-overlapping FOCUS_NONE
# pads, right-pad gas-on-touch / UP-to-fire / L-R-to-dodge, left-pad steering,
# the TOUCH toggle, keyboard-press survival, and focus-out / exit-tree release.
# Exits 1 on any failure.

var _failures := 0
var _layer: CanvasLayer

func _check(cond: bool, label: String) -> void:
	print(("  PASS  " if cond else "  FAIL  "), label)
	if not cond:
		_failures += 1


# Headless has no window, so viewport-pushed InputEventScreenTouch is not
# delivered (that is why verify_touch_multitouch runs under xvfb). Drive the
# overlay's pointer handlers directly to test the same mapping logic.
func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		_layer.call("_on_pointer_down", index, pos)
	else:
		_layer.call("_on_pointer_up", index, pos)


func _drag(index: int, pos: Vector2) -> void:
	_layer.call("_on_pointer_move", index, pos)


func _pad_rect(layer: CanvasLayer, name: String) -> Rect2:
	var pad := layer.get_node_or_null(name) as Control
	return pad.get_global_rect() if pad != null else Rect2()


func _pad_at(layer: CanvasLayer, name: String, x_frac: float, y_forward: float,
		x_margin: float, y_margin: float) -> Vector2:
	var r := _pad_rect(layer, name)
	return Vector2(
			r.get_center().x + x_frac * (r.size.x * 0.5 - x_margin),
			r.get_center().y - y_forward * (r.size.y * 0.5 - y_margin))


func _steer_at(layer: CanvasLayer, x: float, y: float) -> Vector2:
	return _pad_at(layer, "AnalogSteer", x, y, 30.0, 10.0)


func _drive_at(layer: CanvasLayer, x: float, y: float) -> Vector2:
	return _pad_at(layer, "AnalogDrive", x, y, 22.0, 22.0)


func _fire_held(layer: CanvasLayer) -> bool:
	return bool(layer.call("is_fire_held"))


func _initialize() -> void:
	# The overlay persists the TOUCH override, so clear it BEFORE the scene's
	# TouchControls._ready() reads it.
	await process_frame
	var settings_node := get_root().get_node_or_null("Settings")
	var _touch_force_prior: Variant = null
	if settings_node != null:
		_touch_force_prior = settings_node.call("get_value", "controls", "touch_force", false)
		settings_node.call("set_value", "controls", "touch_force", true)

	var scene: PackedScene = load("res://scenes/TestRide.tscn")
	var root_node := scene.instantiate() as Node3D
	get_root().add_child(root_node)
	await process_frame
	await process_frame

	# ---- presence + wiring
	var layer := root_node.get_node_or_null("TouchHUD") as CanvasLayer
	_check(layer != null, "TouchHUD node exists")
	if layer == null:
		quit(1)
		return
	_layer = layer
	_check(layer is CanvasLayer, "TouchHUD is a CanvasLayer")
	_check(layer.get_script() != null
				and str(layer.get_script().resource_path).ends_with("TouchControls.gd"),
			"TouchHUD runs TouchControls.gd")
	_check(bool(layer.call("is_overlay_active")), "TOUCH override shows the drive pads")

	# ---- legacy controls are gone
	for removed in ["BtnFire", "BtnTurbo", "BtnBrake", "BtnGas", "BtnDodgeLeft", "BtnDodgeRight"]:
		_check(layer.get_node_or_null(removed) == null, "%s removed from touch overlay" % removed)

	var toggle_btn := layer.get_node_or_null("BtnTouchToggle") as Button
	_check(toggle_btn != null and toggle_btn.visible,
			"TOUCH toggle stays visible when drive pads are hidden")

	# ---- both analog pads: present, >=44x44, FOCUS_NONE, non-overlapping
	var left := layer.get_node_or_null("AnalogSteer") as Control
	var right := layer.get_node_or_null("AnalogDrive") as Control
	for pad in [left, right]:
		_check(pad != null and pad is Control, "analog pad exists")
		if pad != null:
			_check(pad.focus_mode == Control.FOCUS_NONE, "analog pad focus_mode == FOCUS_NONE")
			var pr: Rect2 = pad.get_global_rect()
			_check(pr.size.x >= 44.0 and pr.size.y >= 44.0,
					"analog pad target >= 44x44 (got %.0fx%.0f)" % [pr.size.x, pr.size.y])
	if left != null and right != null:
		_check(not left.get_global_rect().intersects(right.get_global_rect()),
				"AnalogSteer and AnalogDrive do not overlap")

	# ---- right pad: touching holds GAS; releasing drops it
	_touch(0, _drive_at(layer, 0.0, 0.0), true)
	await process_frame
	_check(Input.is_action_pressed("move_forward"), "right-pad touch holds move_forward (gas)")
	_touch(0, _drive_at(layer, 0.0, 0.0), false)
	await process_frame
	_check(not Input.is_action_pressed("move_forward"), "right-pad release drops gas")

	# ---- right pad: UP holds manual fire (no auto-fire), DOWN does not fire
	_touch(1, _drive_at(layer, 0.0, 0.0), true)
	await process_frame
	_check(not _fire_held(layer), "right-pad centre does not fire")
	_drag(1, _drive_at(layer, 0.0, 1.0))
	await process_frame
	_check(_fire_held(layer), "right-pad UP holds manual fire")
	_check(Input.is_action_pressed("move_forward"), "pushing UP keeps gas held")
	_drag(1, _drive_at(layer, 0.0, 0.0))
	await process_frame
	_check(not _fire_held(layer), "right-pad centre releases fire")
	_drag(1, _drive_at(layer, 0.0, -1.0))
	await process_frame
	_check(not _fire_held(layer), "right-pad DOWN never fires")
	_touch(1, _drive_at(layer, 0.0, -1.0), false)
	await process_frame

	# ---- right pad: LEFT/RIGHT trigger dodge; centre re-arms
	_touch(2, _drive_at(layer, -1.0, 0.0), true)
	await process_frame
	_check(Input.is_action_pressed("dodge_left"), "right-pad LEFT engages dodge_left")
	_drag(2, _drive_at(layer, 0.0, 0.0))
	await process_frame
	_check(not Input.is_action_pressed("dodge_left"), "returning to centre releases dodge_left")
	_drag(2, _drive_at(layer, 1.0, 0.0))
	await process_frame
	_check(Input.is_action_pressed("dodge_right"), "right-pad RIGHT engages dodge_right")
	_touch(2, _drive_at(layer, 1.0, 0.0), false)
	await process_frame
	_check(not Input.is_action_pressed("dodge_right"), "right-pad release drops dodge_right")

	# ---- left pad still steers
	_touch(3, _steer_at(layer, -1.0, 0.0), true)
	await process_frame
	_check(Input.is_action_pressed("steer_left"), "left-pad LEFT steers left")
	_touch(3, _steer_at(layer, -1.0, 0.0), false)
	await process_frame
	_check(not Input.is_action_pressed("steer_left"), "left-pad release centres steering")

	# ---- a keyboard-held action must never be wiped by the overlay
	Input.action_press("steer_left")
	for i in range(3):
		await process_frame
	_check(Input.is_action_pressed("steer_left"), "keyboard-held action survives overlay frames")
	Input.action_release("steer_left")

	# ---- TOUCH toggle hides both pads and releases every held action
	var toggle: Button = btns_toggle(layer)
	if toggle:
		_touch(4, _drive_at(layer, 0.0, 1.0), true)
		await process_frame
		_check(_fire_held(layer), "fire held before hide")
		toggle.pressed.emit()
		await process_frame
		_check(not left.visible and not right.visible, "toggle OFF hides both drive pads")
		_check(toggle.text == "TOUCH: AUTO", "toggle label returns to TOUCH: AUTO")
		_check(not Input.is_action_pressed("move_forward"), "hiding overlay releases held gas")
		_check(not _fire_held(layer), "hiding overlay releases held fire")
		toggle.pressed.emit()
		await process_frame
		_check(left.visible and right.visible, "toggle ON shows both drive pads")
		_check(toggle.text == "TOUCH: ON", "toggle label reads TOUCH: ON")

	# ---- focus-out releases this layer's held actions
	_touch(5, _drive_at(layer, 0.0, 1.0), true)
	await process_frame
	layer._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_check(not Input.is_action_pressed("move_forward"), "focus-out releases gas")
	_check(not _fire_held(layer), "focus-out releases fire")

	# ---- exit-tree safety
	_touch(6, _drive_at(layer, -1.0, 0.0), true)
	await process_frame
	_check(Input.is_action_pressed("dodge_left"), "dodge held before exit")
	layer.queue_free()
	for i in range(3):
		await process_frame
	_check(not Input.is_action_pressed("dodge_left"), "overlay exit releases held dodge")

	# ---- cleanup; restore developer's touch_force prior
	for a in ["move_forward", "move_back", "steer_left", "steer_right", "turbo",
			"dodge_left", "dodge_right", "reset_bike"]:
		Input.action_release(a)
	if settings_node != null:
		settings_node.call("set_value", "controls", "touch_force", _touch_force_prior)

	print("TOUCH VERIFY: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func btns_toggle(layer: CanvasLayer) -> Button:
	return layer.get_node_or_null("BtnTouchToggle") as Button
