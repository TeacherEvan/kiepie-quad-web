extends CanvasLayer
## Touch overlay for the Kiepie Bike pad: hold-to-drive buttons + analog steering.
## Shows itself on touchscreen devices; the "TOUCH" toggle forces it visible/hidden
## (needed on desktop and headless, harmless on phones). Reset lives on the HUD
## Restart button, which already works by tap.
##
## Multi-touch: the drive buttons are visual shells (MOUSE_FILTER_IGNORE); a
## full-rect TouchCapture child tracks every finger by InputEventScreenTouch.index,
## so steering, gas, boost and fire all work at the same time.
##
## Steering is analog: a wide thumb pad (see AnalogSteer.gd) feeds steer_left /
## steer_right with a strength proportional to the thumb offset, deadzoned and
## smooth-stepped for centre control. Buttons' button_down/up signals are still
## wired for tests/synthetic emitters.

const CAPTURE := "res://src/TouchCapture.gd"
const ANALOG := "res://src/AnalogSteer.gd"

const DEADZONE := 0.15

var _held: Dictionary = {}  # Input action -> Button (only actions this layer drives)
var _counts: Dictionary = {}  # Input action -> hold references (fingers + signal holds)
var _fingers: Dictionary = {}  # pointer index -> Input action
var _signal_hold: Dictionary = {}  # Input action -> bool (held via button_down signal)
var _analog: Dictionary = {}  # pointer index -> signed -1..1 thumb offset
var _analog_side := 0  # -1 = steer_left held by pad, +1 = steer_right, 0 = none
var _analog_pad: Control = null
var _touch_toggle: Button
var _force := false
var _drive_buttons: Array = []

# Thumb clusters where sliding between neighbours is the natural gesture; gas /
# brake / turbo / fire stay latched until their own finger lifts.
const SLIDE_PAIRS := [
	["dodge_left", "dodge_right"],
]

func _ready() -> void:
	# Persist the manual TOUCH override across scenes/restarts (the Settings
	# key existed but was never read).
	_force = bool(Settings.get_value("controls", "touch_force", false))
	_wire("BtnGas", "move_forward")
	_wire("BtnBrake", "move_back")  # same action as keyboard S/Down (brake, then reverse)
	_wire("BtnTurbo", "turbo")
	_wire("BtnFire", "fire")
	_wire("BtnDodgeLeft", "dodge_left")
	_wire("BtnDodgeRight", "dodge_right")
	for action in _held:
		var btn: Button = _held[action]
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fire_btn := get_node_or_null("BtnFire") as Button
	if fire_btn != null:
		var size := float(Settings.get_value("controls", "fire_size", 1.0))
		# Centre the scale so enlarging FIRE cannot grow it down over the
		# driving cluster below (its default pivot is the top-left corner).
		fire_btn.pivot_offset = Vector2(
				absf(fire_btn.offset_right - fire_btn.offset_left) * 0.5,
				absf(fire_btn.offset_bottom - fire_btn.offset_top) * 0.5)
		fire_btn.scale = Vector2(size, size)
	# Dodge buttons scale about their centre so growing them never eats the
	# steering cluster directly below.
	var dodge_size := clampf(float(Settings.get_value("controls", "dodge_size", 1.0)), 0.7, 1.6)
	for dodge_name in ["BtnDodgeLeft", "BtnDodgeRight"]:
		var btn := get_node_or_null(dodge_name) as Button
		if btn != null:
			btn.pivot_offset = Vector2(45.0, 45.0)
			btn.scale = Vector2(dodge_size, dodge_size)
	_touch_toggle = get_node_or_null("BtnTouchToggle") as Button
	if _touch_toggle:
		_touch_toggle.pressed.connect(_on_toggle)
	for action in _held:
		_drive_buttons.append(_held[action])
	# Analog steering pad — fills the space the old BtnLeft/BtnRight lived in.
	_analog_pad = Control.new()
	_analog_pad.name = "AnalogSteer"
	_analog_pad.set_script(load(ANALOG))
	_analog_pad.anchor_left = 0.0
	_analog_pad.anchor_right = 0.0
	_analog_pad.anchor_top = 1.0
	_analog_pad.anchor_bottom = 1.0
	_analog_pad.offset_left = 10.0
	_analog_pad.offset_right = 310.0
	_analog_pad.offset_top = -174.0
	_analog_pad.offset_bottom = -64.0  # above the Web shell hint strip
	add_child(_analog_pad)
	# Raw pointer capture: one handler for all fingers, independent of the
	# engine's single emulated mouse pointer.
	var capture := Control.new()
	capture.name = "TouchCapture"
	capture.set_script(load(CAPTURE))
	capture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(capture)
	capture.connect("pointer_down", _on_pointer_down)
	capture.connect("pointer_move", _on_pointer_move)
	capture.connect("pointer_up", _on_pointer_up)
	if _touch_toggle != null:
		_style_toggle(_touch_toggle)
	get_viewport().size_changed.connect(_relayout)
	_relayout()
	_sync_toggle_text()
	_apply_visibility()

func _wire(node_name: String, action: String) -> void:
	var btn := get_node_or_null(node_name) as Button
	if btn == null:
		return
	_held[action] = btn
	btn.button_down.connect(func(): _press(action))
	btn.button_up.connect(func(): _release(action))

func _press(action: String) -> void:
	# Signal/synthetic path (tests, scripted emitters).
	_signal_hold[action] = true
	_hold(action)

func _release(action: String) -> void:
	_signal_hold[action] = false
	_drop(action)

func _analog_rect() -> Rect2:
	# Hidden pad (touch auto-detect OFF) must not capture fingers either.
	if _analog_pad == null or not _analog_pad.visible:
		return Rect2()
	return _analog_pad.get_global_rect()

func _analog_value(at: Vector2) -> float:
	var r := _analog_rect()
	if r.size.x <= 1.0:
		return 0.0
	return clampf((at.x - r.get_center().x) / (r.size.x * 0.5 - 30.0), -1.0, 1.0)

func _on_pointer_down(pointer: int, at: Vector2) -> void:
	if _analog_rect().has_point(at):
		_analog[pointer] = _analog_value(at)
		return
	var action := _hit_action(at)
	if action == "" or _fingers.has(pointer):
		return
	_fingers[pointer] = action
	_hold(action)

func _on_pointer_move(pointer: int, at: Vector2) -> void:
	if _analog.has(pointer):
		# Deadzone-resistant tracking: the knob stays live under the thumb even
		# if the finger wanders outside the pad vertically.
		_analog[pointer] = _analog_value(at)
		return
	if not _fingers.has(pointer):
		return
	var current: String = _fingers[pointer]
	var hovered := _hit_action(at)
	if hovered == "" or hovered == current or not _slide_ok(current, hovered):
		return
	_fingers[pointer] = hovered
	_drop(current)
	_hold(hovered)

func _on_pointer_up(pointer: int, _at: Vector2) -> void:
	if _analog.has(pointer):
		_analog.erase(pointer)
		return
	if not _fingers.has(pointer):
		return
	var action: String = _fingers[pointer]
	_fingers.erase(pointer)
	_drop(action)

func _slide_ok(from: String, to: String) -> bool:
	for pair in SLIDE_PAIRS:
		if (pair[0] == from and pair[1] == to) or (pair[1] == from and pair[0] == to):
			return true
	return false

func _hit_action(at: Vector2) -> String:
	for action in _held:
		var btn: Button = _held[action]
		if btn.visible and btn.get_global_rect().has_point(at):
			return action
	return ""

func _hold(action: String) -> void:
	var count := int(_counts.get(action, 0)) + 1
	_counts[action] = count
	if count == 1:
		Input.action_press(action)
		if _held.has(action):
			var btn := _held[action] as Button
			btn.set_pressed_no_signal(true)
			btn.self_modulate = Color(1.18, 1.12, 1.0, 1.0)

func _drop(action: String) -> void:
	var count := int(_counts.get(action, 0))
	if count <= 0:
		return
	count -= 1
	_counts[action] = count
	if count == 0:
		Input.action_release(action)
		if _held.has(action):
			var btn := _held[action] as Button
			btn.set_pressed_no_signal(false)
			btn.self_modulate = Color.WHITE

static func _curve(t: float) -> float:
	# deadzone, then smoothstep so the centre of the pad is a fine-control band
	var a := maxf(0.0, (absf(t) - DEADZONE) / (1.0 - DEADZONE))
	return signf(t) * a * a * (3.0 - 2.0 * a)

func _process(_delta: float) -> void:
	# Reconcile (defense-in-depth, not the primary guard): only covers holds
	# that came in via the button_down signal; genuine touch holds are owned by
	# the finger map and are released by pointer_up, visibility change,
	# focus-out or _exit_tree. Keyboard-held actions are never touched.
	for action in _signal_hold:
		if bool(_signal_hold[action]):
			var btn: Button = _held[action]
			if not btn.is_pressed():
				_signal_hold[action] = false
				_drop(action)
	# Analog steering: strongest offset wins (two thumbs on the pad can't orchestrate
	# a fight the vehicle feel can't read anyway).
	var target := 0.0
	var best := 0.0
	for pointer in _analog:
		var t: float = _analog[pointer]
		if absf(t) > best:
			best = absf(t)
			target = t
	var steer := _curve(target)
	if steer < -0.001:
		Input.action_press("steer_left", -steer)
		if _analog_side == 1:
			Input.action_release("steer_right")
		_analog_side = -1
	elif steer > 0.001:
		Input.action_press("steer_right", steer)
		if _analog_side == -1:
			Input.action_release("steer_left")
		_analog_side = 1
	else:
		_release_analog_side()
	_update_pad_knob(steer)

func _release_analog_side() -> void:
	if _analog_side == -1:
		Input.action_release("steer_left")
	elif _analog_side == 1:
		Input.action_release("steer_right")
	_analog_side = 0

func _update_pad_knob(steer: float) -> void:
	if _analog_pad == null:
		return
	if not is_equal_approx(_analog_pad.get("value"), steer):
		_analog_pad.set("value", steer)
		_analog_pad.queue_redraw()

func _apply_visibility() -> void:
	# The layer itself always stays visible (it hosts the always-on TOUCH
	# toggle); only the driving controls come and go with touch auto-detect
	# or the manual override.
	var show_drive := _force or DisplayServer.is_touchscreen_available()
	for btn in _drive_buttons:
		(btn as Button).visible = show_drive
	if _analog_pad != null:
		_analog_pad.visible = show_drive
	# Hiding the driving controls must not leave a stuck throttle behind.
	if not show_drive:
		_release_all()
		_release_analog_side()

func _on_toggle() -> void:
	_force = not _force
	Settings.set_value("controls", "touch_force", _force)
	_sync_toggle_text()
	_apply_visibility()

func _sync_toggle_text() -> void:
	if _touch_toggle == null:
		return
	_touch_toggle.text = "TOUCH: ON" if _force else "TOUCH: AUTO"

func _release_all() -> void:
	# Only actions THIS layer holds are released - keyboard/test presses
	# are never wiped. _drop() is idempotent, so repeat calls are free.
	for action in _held:
		var count := int(_counts.get(action, 0))
		for i in range(count):
			_drop(action)
		_signal_hold[action] = false
	_fingers.clear()
	_analog.clear()

func _notification(what: int) -> void:
	# OS-level interruption (phone call, notification shade, app backgrounded)
	# can swallow touch-up; cut the held actions now rather than leave
	# throttle pinned.
	if what == Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()
		_release_analog_side()
		_update_pad_knob(0.0)

func _exit_tree() -> void:
	_release_all()
	_release_analog_side()


func _set_rect(ctrl: Control, left: float, top: float, right: float, bottom: float, anchor_x: float) -> void:
	if ctrl == null:
		return
	ctrl.anchor_left = anchor_x
	ctrl.anchor_right = anchor_x
	ctrl.anchor_top = 1.0
	ctrl.anchor_bottom = 1.0
	ctrl.offset_left = left
	ctrl.offset_top = top
	ctrl.offset_right = right
	ctrl.offset_bottom = bottom


func _set_btn_compact(btn: Button, font_sz: int, h_margin: float) -> void:
	if btn == null:
		return
	btn.add_theme_font_size_override("font_size", font_sz)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := btn.get_theme_stylebox(state)
		if sb is StyleBoxFlat:
			var dup := sb.duplicate() as StyleBoxFlat
			dup.content_margin_left = h_margin
			dup.content_margin_right = h_margin
			btn.add_theme_stylebox_override(state, dup)


func _relayout() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var dodge_l := get_node_or_null("BtnDodgeLeft") as Button
	var dodge_r := get_node_or_null("BtnDodgeRight") as Button
	var gas := get_node_or_null("BtnGas") as Button
	var brake := get_node_or_null("BtnBrake") as Button
	var turbo := get_node_or_null("BtnTurbo") as Button
	var fire := get_node_or_null("BtnFire") as Button

	var fire_size := float(Settings.get_value("controls", "fire_size", 1.0))
	var dodge_size := clampf(float(Settings.get_value("controls", "dodge_size", 1.0)), 0.7, 1.6)
	var eff_fire := fire_size
	var eff_dodge := dodge_size

	if vp.x < 700.0:
		# Narrow / Portrait (e.g. 390x844): compact both clusters <= 44% width each
		var pad_w := clampf(vp.x * 0.44, 168.0, 250.0)
		_set_rect(_analog_pad, 10.0, -140.0, 10.0 + pad_w, -20.0, 0.0)
		_set_rect(dodge_l, 14.0, -238.0, 86.0, -184.0, 0.0)
		_set_rect(dodge_r, 114.0, -238.0, 186.0, -184.0, 0.0)
		_set_rect(gas, -84.0, -156.0, -10.0, -20.0, 1.0)
		_set_rect(brake, -170.0, -86.0, -96.0, -20.0, 1.0)
		_set_rect(turbo, -170.0, -156.0, -96.0, -96.0, 1.0)
		_set_rect(fire, -126.0, -288.0, -22.0, -196.0, 1.0)
		_set_btn_compact(gas, 20, 6.0)
		_set_btn_compact(fire, 20, 6.0)
		_set_btn_compact(turbo, 12, 6.0)
		_set_btn_compact(brake, 12, 6.0)
		_set_btn_compact(dodge_l, 12, 6.0)
		_set_btn_compact(dodge_r, 12, 6.0)
		eff_dodge = minf(dodge_size, 1.25)
		eff_fire = minf(fire_size, 1.25)
	elif vp.y < 520.0:
		# Mobile Landscape (e.g. 844x390): compact vertically, Fire beside Brake/Turbo
		_set_rect(_analog_pad, 12.0, -118.0, 252.0, -14.0, 0.0)
		_set_rect(dodge_l, 28.0, -194.0, 112.0, -134.0, 0.0)
		_set_rect(dodge_r, 150.0, -194.0, 234.0, -134.0, 0.0)
		_set_rect(gas, -116.0, -144.0, -12.0, -14.0, 1.0)
		_set_rect(brake, -222.0, -88.0, -128.0, -14.0, 1.0)
		_set_rect(turbo, -222.0, -158.0, -128.0, -98.0, 1.0)
		_set_rect(fire, -362.0, -140.0, -258.0, -36.0, 1.0)
		_set_btn_compact(gas, 36, 14.0)
		_set_btn_compact(fire, 30, 14.0)
		_set_btn_compact(turbo, 18, 14.0)
		_set_btn_compact(brake, 20, 14.0)
		_set_btn_compact(dodge_l, 13, 6.0)
		_set_btn_compact(dodge_r, 13, 6.0)
		eff_dodge = minf(dodge_size, 1.28)
		eff_fire = minf(fire_size, 1.3)
	else:
		# Standard (e.g. 1280x720)
		_set_rect(_analog_pad, 12.0, -156.0, 312.0, -16.0, 0.0)
		_set_rect(dodge_l, 36.0, -280.0, 126.0, -200.0, 0.0)
		_set_rect(dodge_r, 196.0, -280.0, 286.0, -200.0, 0.0)
		_set_rect(brake, -258.0, -112.0, -148.0, -16.0, 1.0)
		_set_rect(turbo, -258.0, -202.0, -148.0, -122.0, 1.0)
		_set_rect(gas, -138.0, -176.0, -12.0, -16.0, 1.0)
		_set_rect(fire, -164.0, -352.0, -38.0, -232.0, 1.0)
		_set_btn_compact(gas, 36, 14.0)
		_set_btn_compact(fire, 30, 14.0)
		_set_btn_compact(turbo, 18, 14.0)
		_set_btn_compact(brake, 20, 14.0)
		_set_btn_compact(dodge_l, 15, 14.0)
		_set_btn_compact(dodge_r, 15, 14.0)

	if fire != null:
		fire.pivot_offset = Vector2(
				absf(fire.offset_right - fire.offset_left) * 0.5,
				absf(fire.offset_bottom - fire.offset_top) * 0.5)
		fire.scale = Vector2(eff_fire, eff_fire)
	for btn in [dodge_l, dodge_r]:
		if btn != null:
			btn.pivot_offset = Vector2(
					absf(btn.offset_right - btn.offset_left) * 0.5,
					absf(btn.offset_bottom - btn.offset_top) * 0.5)
			btn.scale = Vector2(eff_dodge, eff_dodge)


func _style_toggle(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.10, 0.14, 0.90)
	normal.border_color = Color(0.55, 0.65, 0.78, 0.85)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
