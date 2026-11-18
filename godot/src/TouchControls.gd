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
const TURBO_ENGAGE := 0.48
const TURBO_RELEASE := 0.32
const REVERSE_ENGAGE := 0.40
const REVERSE_RELEASE := 0.25

var _held: Dictionary = {}  # Input action -> Button (only actions this layer drives)
var _counts: Dictionary = {}  # Input action -> hold references (fingers + signal holds)
var _fingers: Dictionary = {}  # pointer index -> Input action
var _signal_hold: Dictionary = {}  # Input action -> bool (held via button_down signal)
var _analog: Dictionary = {}  # pointer index -> Vector2(x: -1..1 steer, y: -1..1 forward)
var _analog_side := 0  # -1 = steer_left held by pad, +1 = steer_right, 0 = none
var _analog_turbo := false  # true while analog forward deflection holds "turbo"
var _analog_reverse := false  # true while analog back deflection holds "move_back" (brake/reverse)
var _analog_pad: Control = null
var _touch_toggle: Button
var _force := false
var _overlay_active := false
var _drive_buttons: Array = []

# Thumb clusters where sliding between neighbours is the natural gesture; gas
# stays latched until its own finger lifts (fire is automatic, turbo pushes forward on analog).
const SLIDE_PAIRS := [
	["dodge_left", "dodge_right"],
]


func _init() -> void:
	add_to_group("touch_controls")


func is_overlay_active() -> bool:
	return _overlay_active


func _ready() -> void:
	# Persist the manual TOUCH override across scenes/restarts (the Settings
	# key existed but was never read).
	_force = bool(Settings.get_value("controls", "touch_force", false))
	_wire("BtnGas", "move_forward")
	_wire("BtnDodgeLeft", "dodge_left")
	_wire("BtnDodgeRight", "dodge_right")
	for action in _held:
		var btn: Button = _held[action]
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

func _analog_value(at: Vector2) -> Vector2:
	var r := _analog_rect()
	if r.size.x <= 1.0 or r.size.y <= 1.0:
		return Vector2.ZERO
	var c := r.get_center()
	var x := clampf((at.x - c.x) / maxf(r.size.x * 0.5 - 30.0, 1.0), -1.0, 1.0)
	# Up on screen is smaller Y; positive forward means pushed toward/above the top edge.
	var y := clampf((c.y - at.y) / maxf(r.size.y * 0.5 - 10.0, 1.0), -1.0, 1.0)
	return Vector2(x, y)

func _on_pointer_down(pointer: int, at: Vector2) -> void:
	if _analog_rect().has_point(at):
		_analog[pointer] = _analog_value(at)
		_sync_analog()
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
		_sync_analog()
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
	# Release both halves independently: under paired touch->mouse emulation the
	# shared MOUSE_POINTER can own a pad (analog) hold and a button hold at the
	# same time; dropping only analog and returning stranded the button half
	# (e.g. gas latched forever after a canceled primary touch).
	if _analog.has(pointer):
		_analog.erase(pointer)
		_sync_analog()
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
	_sync_analog()

func _sync_analog() -> void:
	# Analog steering + push-forward turbo + pull-back reverse: strongest
	# horizontal offset steers, forward deflection past TURBO_ENGAGE holds
	# "turbo" and backward deflection past REVERSE_ENGAGE holds "move_back"
	# (brake, then reverse once slow — same feel as keyboard S).
	var target := 0.0
	var best := 0.0
	var best_forward := -1.0
	var best_backward := 1.0
	for pointer in _analog:
		var v: Vector2 = _analog[pointer]
		if absf(v.x) > best:
			best = absf(v.x)
			target = v.x
		if v.y > best_forward:
			best_forward = v.y
		if v.y < best_backward:
			best_backward = v.y
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

	var want_turbo := false
	if not _analog.is_empty():
		var threshold := TURBO_RELEASE if _analog_turbo else TURBO_ENGAGE
		want_turbo = best_forward >= threshold
	_set_analog_turbo(want_turbo)
	var want_reverse := false
	if not _analog.is_empty():
		var threshold := REVERSE_RELEASE if _analog_reverse else REVERSE_ENGAGE
		want_reverse = -best_backward >= threshold
	_set_analog_reverse(want_reverse)
	var display_turbo := maxf(0.0, best_forward) if not _analog.is_empty() else 0.0
	var display_reverse := maxf(0.0, -best_backward) if not _analog.is_empty() else 0.0
	_update_pad_knob(steer, display_turbo, _analog_turbo, display_reverse, _analog_reverse)

func _set_analog_reverse(active: bool) -> void:
	if active == _analog_reverse:
		return
	_analog_reverse = active
	if active:
		_hold("move_back")
	else:
		_drop("move_back")

func _set_analog_turbo(active: bool) -> void:
	if active == _analog_turbo:
		return
	_analog_turbo = active
	if active:
		_hold("turbo")
	else:
		_drop("turbo")

func _release_analog_side() -> void:
	if _analog_side == -1:
		Input.action_release("steer_left")
	elif _analog_side == 1:
		Input.action_release("steer_right")
	_analog_side = 0

func _update_pad_knob(steer: float, turbo_val: float = 0.0, turbo_on: bool = false,
		rev_val: float = 0.0, rev_on: bool = false) -> void:
	if _analog_pad == null:
		return
	var changed := false
	if not is_equal_approx(_analog_pad.get("value"), steer):
		_analog_pad.set("value", steer)
		changed = true
	if not is_equal_approx(_analog_pad.get("turbo_value"), turbo_val):
		_analog_pad.set("turbo_value", turbo_val)
		changed = true
	if bool(_analog_pad.get("turbo_active")) != turbo_on:
		_analog_pad.set("turbo_active", turbo_on)
		changed = true
	if not is_equal_approx(_analog_pad.get("reverse_value"), rev_val):
		_analog_pad.set("reverse_value", rev_val)
		changed = true
	if bool(_analog_pad.get("reverse_active")) != rev_on:
		_analog_pad.set("reverse_active", rev_on)
		changed = true
	if changed:
		_analog_pad.queue_redraw()

func _apply_visibility() -> void:
	# The layer itself always stays visible (it hosts the always-on TOUCH
	# toggle); only the driving controls come and go with touch auto-detect
	# or the manual override.
	var show_drive := _force or DisplayServer.is_touchscreen_available()
	_overlay_active = show_drive
	for btn in _drive_buttons:
		(btn as Button).visible = show_drive
	if _analog_pad != null:
		_analog_pad.visible = show_drive
	# Hiding the driving controls must not leave a stuck throttle behind.
	if not show_drive:
		_release_all()
		_release_analog_side()
		_update_pad_knob(0.0, 0.0, false, 0.0, false)

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
	# are never wiped. Iterate _counts (not just _held) so analog-held
	# "turbo" releases even with BtnTurbo removed.
	_analog_turbo = false
	_analog_reverse = false
	for action in _counts.keys().duplicate():
		var count := int(_counts.get(action, 0))
		for i in range(count):
			_drop(action)
		_signal_hold[action] = false
	_fingers.clear()
	_analog.clear()
	_analog_turbo = false
	_analog_reverse = false

func _notification(what: int) -> void:
	# OS-level interruption (phone call, notification shade, app backgrounded)
	# can swallow touch-up; cut the held actions now rather than leave
	# throttle pinned.
	if what == Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()
		_release_analog_side()
		_update_pad_knob(0.0, 0.0, false, 0.0, false)

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
	var in_arena := get_node_or_null("../HUD/ScoreToggle") != null

	var dodge_size := clampf(float(Settings.get_value("controls", "dodge_size", 1.0)), 0.7, 1.6)
	var eff_dodge := dodge_size

	if vp.x < 700.0:
		# Narrow / Portrait (e.g. 390x844): compact left cluster, ~1/3rd compact GAS pad on right
		var pad_w := clampf(vp.x * 0.44, 168.0, 250.0)
		_set_rect(_analog_pad, 10.0, -140.0, 10.0 + pad_w, -20.0, 0.0)
		_set_rect(dodge_l, 16.0, -202.0, 64.0, -158.0, 0.0)
		_set_rect(dodge_r, 80.0, -202.0, 128.0, -158.0, 0.0)
		_set_rect(gas, -82.0, -90.0, -14.0, -22.0, 1.0)
		_set_btn_compact(gas, 16, 4.0)
		_set_btn_compact(dodge_l, 14, 4.0)
		_set_btn_compact(dodge_r, 14, 4.0)
		eff_dodge = minf(dodge_size, 1.25)
	elif vp.y < 520.0:
		# Mobile Landscape (e.g. 844x390): streamlined analog + dodge on left, compact GAS on right
		_set_rect(_analog_pad, 12.0, -118.0, 252.0, -14.0, 0.0)
		_set_rect(dodge_l, 24.0, -180.0, 72.0, -136.0, 0.0)
		_set_rect(dodge_r, 92.0, -180.0, 140.0, -136.0, 0.0)
		_set_rect(gas, -86.0, -88.0, -14.0, -16.0, 1.0)
		_set_btn_compact(gas, 17, 6.0)
		_set_btn_compact(dodge_l, 14, 4.0)
		_set_btn_compact(dodge_r, 14, 4.0)
		eff_dodge = minf(dodge_size, 1.28)
	else:
		# Standard (e.g. 1280x720)
		_set_rect(_analog_pad, 12.0, -156.0, 312.0, -16.0, 0.0)
		_set_rect(dodge_l, 32.0, -230.0, 84.0, -184.0, 0.0)
		_set_rect(dodge_r, 108.0, -230.0, 160.0, -184.0, 0.0)
		_set_rect(gas, -92.0, -96.0, -14.0, -18.0, 1.0)
		_set_btn_compact(gas, 18, 6.0)
		_set_btn_compact(dodge_l, 15, 6.0)
		_set_btn_compact(dodge_r, 15, 6.0)

	if _touch_toggle != null and in_arena:
		_touch_toggle.anchor_left = 1.0
		_touch_toggle.anchor_right = 1.0
		_touch_toggle.anchor_top = 0.0
		_touch_toggle.anchor_bottom = 0.0
		_touch_toggle.offset_left = -104.0 if vp.x <= 640.0 else -108.0
		_touch_toggle.offset_right = -10.0
		_touch_toggle.offset_top = 10.0 if vp.x <= 640.0 else 12.0
		_touch_toggle.offset_bottom = 54.0 if vp.x <= 640.0 else 56.0
		_set_btn_compact(_touch_toggle, 11, 4.0)

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
