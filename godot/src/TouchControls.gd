extends CanvasLayer
## Touch overlay for the Kiepie Bike pad: big hold-to-drive buttons.
## Shows itself on touchscreen devices; the "TOUCH" toggle forces it visible/hidden
## (needed on desktop and headless, harmless on phones). Reset lives on the HUD
## Restart button, which already works by tap.
##
## Multi-touch: the drive buttons are visual shells (MOUSE_FILTER_IGNORE); a
## full-rect TouchCapture child tracks every finger by InputEventScreenTouch.index,
## so steering, gas, boost and fire all work at the same time. Buttons'
## button_down/up signals are still wired for tests/synthetic emitters.

const CAPTURE := "res://src/TouchCapture.gd"

var _held: Dictionary = {}  # Input action -> Button (only actions this layer drives)
var _counts: Dictionary = {}  # Input action -> hold references (fingers + signal holds)
var _fingers: Dictionary = {}  # pointer index -> Input action
var _signal_hold: Dictionary = {}  # Input action -> bool (held via button_down signal)
var _touch_toggle: Button
var _force := false
var _drive_buttons: Array = []

# Thumb clusters where sliding between neighbours is the natural gesture; gas /
# brake / turbo / fire stay latched until their own finger lifts.
const SLIDE_PAIRS := [
	["steer_left", "steer_right"],
	["dodge_left", "dodge_right"],
]

func _ready() -> void:
	# Persist the manual TOUCH override across scenes/restarts (the Settings
	# key existed but was never read).
	_force = bool(Settings.get_value("controls", "touch_force", false))
	_wire("BtnLeft", "steer_left")
	_wire("BtnRight", "steer_right")
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

func _on_pointer_down(pointer: int, at: Vector2) -> void:
	var action := _hit_action(at)
	if action == "" or _fingers.has(pointer):
		return
	_fingers[pointer] = action
	_hold(action)

func _on_pointer_move(pointer: int, at: Vector2) -> void:
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
			(_held[action] as Button).set_pressed_no_signal(true)

func _drop(action: String) -> void:
	var count := int(_counts.get(action, 0))
	if count <= 0:
		return
	count -= 1
	_counts[action] = count
	if count == 0:
		Input.action_release(action)
		if _held.has(action):
			(_held[action] as Button).set_pressed_no_signal(false)

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

func _apply_visibility() -> void:
	# The layer itself always stays visible (it hosts the always-on TOUCH
	# toggle); only the driving buttons come and go with touch auto-detect
	# or the manual override.
	var show_drive := _force or DisplayServer.is_touchscreen_available()
	for btn in _drive_buttons:
		(btn as Button).visible = show_drive
	# Hiding the driving controls must not leave a stuck throttle behind.
	if not show_drive:
		_release_all()

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

func _notification(what: int) -> void:
	# OS-level interruption (phone call, notification shade, app backgrounded)
	# can swallow touch-up; cut the held actions now rather than leave
	# throttle pinned.
	if what == Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()

func _exit_tree() -> void:
	_release_all()
