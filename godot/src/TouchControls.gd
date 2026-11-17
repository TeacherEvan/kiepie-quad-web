extends CanvasLayer
## Touch overlay for the Kiepie Bike pad: big hold-to-drive buttons.
## Shows itself on touchscreen devices; the "TOUCH" toggle forces it visible/hidden
## (needed on desktop and headless, harmless on phones). Reset lives on the HUD
## Restart button, which already works by tap.

var _held: Dictionary = {}  # Input action -> Button (only actions this layer pressed)
var _touch_pressed: Dictionary = {}  # Input action -> bool, this layer pressed it
var _touch_toggle: Button
var _force := false
var _drive_buttons: Array = []

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
	_touch_pressed[action] = true
	Input.action_press(action)

func _release(action: String) -> void:
	if not bool(_touch_pressed.get(action, false)):
		return  # idempotent: safe to call unconditionally from hide/exit/focus-out
	_touch_pressed[action] = false
	Input.action_release(action)

func _process(_delta: float) -> void:
	# Reconcile (defense-in-depth, not the primary guard): a real touch gesture
	# captures the press control, so a finger sliding off keeps is_pressed()
	# true (per Godot 4.3, Button press state clears on release / visibility
	# change / exit tree / disable). This loop only covers "button hidden,
	# disabled or removed mid-hold without button_up" -- cheap insurance; the
	# real stuck-throttle guards are the focus-out notification below and
	# _release_all() on hide/exit. Only actions THIS layer pressed are
	# touched here, so keyboard-held actions pass through untouched.
	for action in _held:
		if bool(_touch_pressed.get(action, false)):
			var btn: Button = _held[action]
			if not btn.is_pressed():
				_release(action)

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
	# Only actions THIS layer pressed are released - keyboard/test presses
	# are never wiped. _release() is idempotent, so repeat calls are free.
	for action in _held:
		_release(action)

func _notification(what: int) -> void:
	# OS-level interruption (phone call, notification shade, app backgrounded)
	# can swallow touch-up; the engine's synthetic focus-return only fires
	# later, so cut the held actions now rather than leave throttle pinned.
	if what == Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()

func _exit_tree() -> void:
	_release_all()
