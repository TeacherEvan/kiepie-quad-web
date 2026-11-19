extends CanvasLayer
## Touch overlay for the Kiepie Bike pad: two analog pads + a TOUCH toggle.
## Shows itself on touchscreen devices; the "TOUCH" toggle forces it visible/hidden
## (needed on desktop and headless, harmless on phones). Reset lives on the HUD
## Restart button, which already works by tap.
##
## Multi-touch: a full-rect TouchCapture child tracks every finger by
## InputEventScreenTouch.index, so both pads work at the same time. Both pads
## are MOUSE_FILTER_IGNORE views (see AnalogSteer.gd / AnalogDrive.gd).
##
## LEFT pad (AnalogSteer): horizontal steering, push up = turbo, pull back =
## brake/reverse. RIGHT pad (AnalogDrive): a resting finger holds gas, push up
## holds fire (manual only — no auto-fire), push left/right triggers the dodge
## cartwheel. CombatController reads is_fire_held() instead of the "fire"
## InputAction because touch-to-mouse emulation is bound to MOUSE_BUTTON_LEFT.

const CAPTURE := "res://src/TouchCapture.gd"
const ANALOG := "res://src/AnalogSteer.gd"
const DRIVE := "res://src/AnalogDrive.gd"

signal weapon_switch_requested()

const DEADZONE := 0.15
const TURBO_ENGAGE := 0.48
const TURBO_RELEASE := 0.32
const REVERSE_ENGAGE := 0.40
const REVERSE_RELEASE := 0.25
# Right pad thresholds. Dodge uses a wider engagement band and hysteresis so a
# thumb can't chatter between left/right; fire mirrors the turbo band; pulling
# back (DOWN) cycles the active weapon once per gesture.
const FIRE_ENGAGE := 0.45
const FIRE_RELEASE := 0.30
const DODGE_ENGAGE := 0.55
const DODGE_RELEASE := 0.32
const WEAPON_ENGAGE := 0.48
const WEAPON_RELEASE := 0.28
# Mirrors TouchCapture.MOUSE_POINTER: the emulated mouse follows the primary
# finger but may stop emitting motion on some browsers, so a real touch must
# always win arbitration when both own the same pad.
const EMULATED_MOUSE := 100

var _counts: Dictionary = {}  # Input action -> hold references
var _analog: Dictionary = {}  # pointer index -> Vector2(left pad: x steer, y forward)
var _analog_latest := -1  # newest real touch on left pad
var _analog_mouse_latest := -1  # emulated/desktop mouse on left pad
var _analog_side := 0  # -1 = steer_left held by pad, +1 = steer_right, 0 = none
var _analog_turbo := false  # true while left pad forward deflection holds "turbo"
var _analog_reverse := false  # true while left pad back deflection holds "move_back"
var _analog_pad: Control = null
var _drive: Dictionary = {}  # pointer index -> Vector2(right pad: x dodge, y fire)
var _drive_latest := -1  # newest real touch on right pad
var _drive_mouse_latest := -1  # emulated/desktop mouse on right pad
var _drive_gas := false
var _drive_fire := false
var _drive_weapon_switch := false
var _weapon_switch_count := 0
var _drive_dodge := 0  # -1 = dodge_left, +1 = dodge_right, 0 = none
var _drive_pad: Control = null
var _touch_toggle: Button
var _force := false
var _overlay_active := false


func _init() -> void:
	add_to_group("touch_controls")


func is_overlay_active() -> bool:
	return _overlay_active


func _ready() -> void:
	# Persist the manual TOUCH override across scenes/restarts (the Settings
	# key existed but was never read).
	_force = bool(Settings.get_value("controls", "touch_force", false))
	_touch_toggle = get_node_or_null("BtnTouchToggle") as Button
	if _touch_toggle:
		_touch_toggle.pressed.connect(_on_toggle)
	# Left pad: steering + turbo/reverse.
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
	# Right pad: gas by touch, fire up, dodge left/right. Replaces BtnGas and
	# the L/R dodge buttons; created at runtime like the steering pad.
	_drive_pad = Control.new()
	_drive_pad.name = "AnalogDrive"
	_drive_pad.set_script(load(DRIVE))
	_drive_pad.anchor_left = 1.0
	_drive_pad.anchor_right = 1.0
	_drive_pad.anchor_top = 1.0
	_drive_pad.anchor_bottom = 1.0
	_drive_pad.offset_left = -172.0
	_drive_pad.offset_right = -14.0
	_drive_pad.offset_top = -172.0
	_drive_pad.offset_bottom = -14.0
	add_child(_drive_pad)
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


## Polled by CombatController: manual fire comes only from the right pad's UP
## gesture. Never use Input.is_action_pressed("fire") here — touch-to-mouse
## emulation presses MOUSE_BUTTON_LEFT, which is bound to that action.
func is_fire_held() -> bool:
	return _drive_fire

func is_weapon_switch_active() -> bool:
	return _drive_weapon_switch

func weapon_switch_count() -> int:
	return _weapon_switch_count

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

func _drive_rect() -> Rect2:
	if _drive_pad == null or not _drive_pad.visible:
		return Rect2()
	return _drive_pad.get_global_rect()


func _drive_value(at: Vector2) -> Vector2:
	var r := _drive_rect()
	if r.size.x <= 1.0 or r.size.y <= 1.0:
		return Vector2.ZERO
	var c := r.get_center()
	var x := clampf((at.x - c.x) / maxf(r.size.x * 0.5 - 22.0, 1.0), -1.0, 1.0)
	var y := clampf((c.y - at.y) / maxf(r.size.y * 0.5 - 22.0, 1.0), -1.0, 1.0)
	return Vector2(x, y)


func _track_latest(pointer: int, is_touch: bool, touch_slot: String, mouse_slot: String) -> void:
	# Real fingers always outrank the paired emulated mouse: some browsers stop
	# sending mouse-motion during a drag, which would otherwise freeze the pad
	# at the touch-down position and swallow fire/dodge.
	if is_touch:
		set(touch_slot, pointer)
	elif int(get(mouse_slot)) < 0 or int(get(touch_slot)) < 0:
		set(mouse_slot, pointer)


func _on_pointer_down(pointer: int, at: Vector2) -> void:
	var is_touch := pointer != EMULATED_MOUSE
	if _analog_rect().has_point(at):
		_analog[pointer] = _analog_value(at)
		_track_latest(pointer, is_touch, "_analog_latest", "_analog_mouse_latest")
		_sync_analog()
		return
	if _drive_rect().has_point(at):
		_drive[pointer] = _drive_value(at)
		_track_latest(pointer, is_touch, "_drive_latest", "_drive_mouse_latest")
		_sync_drive()
		return


func _on_pointer_move(pointer: int, at: Vector2) -> void:
	# Deadzone-resistant tracking: the knob stays live under the thumb even if
	# the finger wanders outside the pad rect.
	if _analog.has(pointer):
		_analog[pointer] = _analog_value(at)
		_sync_analog()
		return
	if _drive.has(pointer):
		_drive[pointer] = _drive_value(at)
		_sync_drive()


func _on_pointer_up(pointer: int, _at: Vector2) -> void:
	# A pointer can only own one pad; release each map independently. Under
	# paired touch->mouse emulation the shared MOUSE_POINTER may be the owning
	# pointer, so its release must always land here too.
	if _analog.has(pointer):
		_analog.erase(pointer)
		if _analog_latest == pointer:
			_analog_latest = _fallback_touch(_analog)
		if _analog_mouse_latest == pointer:
			_analog_mouse_latest = -1
		_sync_analog()
	if _drive.has(pointer):
		_drive.erase(pointer)
		if _drive_latest == pointer:
			_drive_latest = _fallback_touch(_drive)
		if _drive_mouse_latest == pointer:
			_drive_mouse_latest = -1
		_sync_drive()


func _fallback_touch(entries: Dictionary) -> int:
	for p in entries.keys():
		if int(p) != EMULATED_MOUSE:
			return int(p)
	return -1


func _primary(entries: Dictionary, touch_latest: int, mouse_latest: int) -> int:
	if touch_latest >= 0 and entries.has(touch_latest):
		return touch_latest
	if mouse_latest >= 0 and entries.has(mouse_latest):
		return mouse_latest
	return -1


func _hold(action: String) -> void:
	var count := int(_counts.get(action, 0)) + 1
	_counts[action] = count
	if count == 1:
		Input.action_press(action)


func _drop(action: String) -> void:
	var count := int(_counts.get(action, 0))
	if count <= 0:
		return
	count -= 1
	_counts[action] = count
	if count == 0:
		Input.action_release(action)

static func _curve(t: float) -> float:
	# deadzone, then smoothstep so the centre of the pad is a fine-control band
	var a := maxf(0.0, (absf(t) - DEADZONE) / (1.0 - DEADZONE))
	return signf(t) * a * a * (3.0 - 2.0 * a)

func _process(_delta: float) -> void:
	if not _analog.is_empty() or _analog_side != 0 or _analog_turbo or _analog_reverse:
		_sync_analog()
	if not _drive.is_empty() or _drive_gas or _drive_fire or _drive_weapon_switch or _drive_dodge != 0:
		_sync_drive()

func _sync_analog() -> void:
	# Analog steering + push-forward turbo + pull-back reverse: strongest
	# horizontal offset steers, forward deflection past TURBO_ENGAGE holds
	# "turbo" and backward deflection past REVERSE_ENGAGE holds "move_back"
	# (brake, then reverse once slow — same feel as keyboard S).
	var target := 0.0
	var best := 0.0
	var best_forward := -1.0
	var best_backward := 1.0
	# Priority arbitration: the newest pad finger owns steering/throttle. Two
	# thumbs pushing opposite ends of the pad used to latch turbo AND move_back;
	# with gas held that made Input.get_axis(move_back, move_forward) resolve to
	# zero and stall the bike mid-maneuver (audit INP-3).
	var sources: Array = []
	var primary := _primary(_analog, _analog_latest, _analog_mouse_latest)
	if primary >= 0:
		sources.append(primary)
	else:
		sources = _analog.keys()
	for pointer in sources:
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
	if not sources.is_empty():
		var threshold := TURBO_RELEASE if _analog_turbo else TURBO_ENGAGE
		want_turbo = best_forward >= threshold
	_set_analog_turbo(want_turbo)
	var want_reverse := false
	if not sources.is_empty():
		var threshold := REVERSE_RELEASE if _analog_reverse else REVERSE_ENGAGE
		want_reverse = -best_backward >= threshold
	_set_analog_reverse(want_reverse)
	var display_turbo := maxf(0.0, best_forward) if not sources.is_empty() else 0.0
	var display_reverse := maxf(0.0, -best_backward) if not sources.is_empty() else 0.0
	_update_pad_knob(steer, display_turbo, _analog_turbo, display_reverse, _analog_reverse)


func _sync_drive() -> void:
	# Right pad: a resting finger is GAS; UP is manual FIRE; horizontal
	# deflection pulses a dodge cartwheel. The newest pad pointer owns the
	# deflection so a paired emulated mouse can't double-trigger the edge.
	var sources: Array = []
	var primary := _primary(_drive, _drive_latest, _drive_mouse_latest)
	if primary >= 0:
		sources.append(primary)
	else:
		sources = _drive.keys()

	var target := 0.0
	var best_abs := 0.0
	var best_up := -1.0
	var best_down := 1.0
	for pointer in sources:
		var v: Vector2 = _drive[pointer]
		if absf(v.x) > best_abs:
			best_abs = absf(v.x)
			target = v.x
		if v.y > best_up:
			best_up = v.y
		if v.y < best_down:
			best_down = v.y

	# Gas: any finger (or paired emulated mouse hold) resting on the pad.
	var want_gas := not _drive.is_empty()
	if want_gas != _drive_gas:
		_drive_gas = want_gas
		if want_gas:
			_hold("move_forward")
		else:
			_drop("move_forward")

	# Fire: held UP with hysteresis, exposed via is_fire_held() (never the
	# "fire" InputAction — emulated MOUSE_BUTTON_LEFT would free-fire).
	var want_fire := false
	if not sources.is_empty():
		var threshold := FIRE_RELEASE if _drive_fire else FIRE_ENGAGE
		want_fire = best_up >= threshold
	_drive_fire = want_fire

	# Weapon switch: pulling the right analog BACK (downward) cycles the active
	# weapon once per pull-back gesture (must return above -WEAPON_RELEASE to re-arm).
	# Axis dominance (1.15x) stops diagonal dodges from accidentally swapping weapons.
	var want_switch := false
	if not sources.is_empty():
		var sw_thresh := WEAPON_RELEASE if _drive_weapon_switch else WEAPON_ENGAGE
		var down_dom := _drive_weapon_switch or (-best_down > absf(target) * 1.15)
		want_switch = -best_down >= sw_thresh and down_dom
	if want_switch and not _drive_weapon_switch:
		_drive_weapon_switch = true
		_weapon_switch_count += 1
		weapon_switch_requested.emit()
	elif not want_switch:
		_drive_weapon_switch = false

	# Dodge: one cartwheel per deflection. Hold the action until the thumb
	# returns below DODGE_RELEASE so KiepieBike.is_action_just_pressed() sees
	# exactly one rising edge per gesture. Axis dominance stops off-axis fire
	# or weapon-switch drags from unintentionally firing a cartwheel.
	var dodge_dir := 0
	if not sources.is_empty():
		var threshold := DODGE_RELEASE if _drive_dodge != 0 else DODGE_ENGAGE
		var horiz_dom := _drive_dodge != 0 or absf(target) > maxf(best_up, -best_down) * 1.15
		if absf(target) >= threshold and horiz_dom:
			dodge_dir = -1 if target < 0.0 else 1
	if dodge_dir != _drive_dodge:
		if _drive_dodge == -1:
			_drop("dodge_left")
		elif _drive_dodge == 1:
			_drop("dodge_right")
		if dodge_dir == -1:
			_hold("dodge_left")
		elif dodge_dir == 1:
			_hold("dodge_right")
		_drive_dodge = dodge_dir

	_update_drive_pad(target, maxf(0.0, best_up) if not sources.is_empty() else 0.0,
			_drive_fire, dodge_dir == -1, dodge_dir == 1, want_gas,
			maxf(0.0, -best_down) if not sources.is_empty() else 0.0, _drive_weapon_switch)


func _update_drive_pad(steer: float, fire_val: float, fire_on: bool,
		left_on: bool, right_on: bool, gas_on: bool,
		swap_val: float = 0.0, swap_on: bool = false) -> void:
	if _drive_pad == null:
		return
	var changed := false
	if not is_equal_approx(float(_drive_pad.get("value")), steer):
		_drive_pad.set("value", steer)
		changed = true
	if not is_equal_approx(float(_drive_pad.get("fire_value")), fire_val):
		_drive_pad.set("fire_value", fire_val)
		changed = true
	if bool(_drive_pad.get("fire_active")) != fire_on:
		_drive_pad.set("fire_active", fire_on)
		changed = true
	if not is_equal_approx(float(_drive_pad.get("swap_value")), swap_val):
		_drive_pad.set("swap_value", swap_val)
		changed = true
	if bool(_drive_pad.get("swap_active")) != swap_on:
		_drive_pad.set("swap_active", swap_on)
		changed = true
	if bool(_drive_pad.get("dodge_left_active")) != left_on:
		_drive_pad.set("dodge_left_active", left_on)
		changed = true
	if bool(_drive_pad.get("dodge_right_active")) != right_on:
		_drive_pad.set("dodge_right_active", right_on)
		changed = true
	if bool(_drive_pad.get("gas_active")) != gas_on:
		_drive_pad.set("gas_active", gas_on)
		changed = true
	if changed:
		_drive_pad.queue_redraw()


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
	# toggle); only the two pads come and go with touch auto-detect or the
	# manual override.
	var show_drive := _force or DisplayServer.is_touchscreen_available()
	_overlay_active = show_drive
	if _analog_pad != null:
		_analog_pad.visible = show_drive
	if _drive_pad != null:
		_drive_pad.visible = show_drive
	# Hiding the pads must not leave a stuck throttle/fire/dodge behind.
	if not show_drive:
		_release_all()
		_release_analog_side()
		_update_pad_knob(0.0, 0.0, false, 0.0, false)
		_update_drive_pad(0.0, 0.0, false, false, false, false)

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
	# Only actions THIS layer holds are released - keyboard/test presses are
	# never wiped. Iterate _counts so analog-held turbo/reverse, right-pad gas
	# and dodge all release even though no Buttons remain.
	for action in _counts.keys().duplicate():
		var count := int(_counts.get(action, 0))
		for i in range(count):
			_drop(action)
	_analog.clear()
	_drive.clear()
	_analog_turbo = false
	_analog_reverse = false
	_drive_gas = false
	_drive_fire = false
	_drive_weapon_switch = false
	_drive_dodge = 0
	_analog_latest = -1
	_analog_mouse_latest = -1
	_drive_latest = -1
	_drive_mouse_latest = -1

func _notification(what: int) -> void:
	# OS-level interruption (phone call, notification shade, app backgrounded)
	# can swallow touch-up; cut the held actions now rather than leave
	# throttle, fire or a dodge pinned.
	if what == Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()
		_release_analog_side()
		_update_pad_knob(0.0, 0.0, false, 0.0, false)
		_update_drive_pad(0.0, 0.0, false, false, false, false)

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
	var in_arena := get_node_or_null("../HUD/ScoreToggle") != null
	# The old DODGE button-size setting now scales the right analog pad: a
	# larger pad means larger, easier-to-hit fire/dodge deflection zones.
	var pad_scale := clampf(float(Settings.get_value("controls", "dodge_size", 1.0)), 0.7, 1.6)

	if vp.x < 700.0:
		# Narrow / Portrait (e.g. 390x844): left steer pad, right drive pad.
		var pad_w := clampf(vp.x * 0.44, 168.0, 250.0)
		_set_rect(_analog_pad, 10.0, -140.0, 10.0 + pad_w, -20.0, 0.0)
		var max_rw := maxf(110.0, vp.x - 10.0 - pad_w - 16.0 - 14.0)
		var rw := clampf(148.0 * pad_scale, 110.0, minf(210.0, max_rw))
		var rh := clampf(148.0 * pad_scale, 110.0, 210.0)
		_set_rect(_drive_pad, -14.0 - rw, -16.0 - rh, -14.0, -16.0, 1.0)
	elif vp.y < 520.0:
		# Mobile Landscape (e.g. 844x390): keep both pads above the hint strip.
		_set_rect(_analog_pad, 12.0, -118.0, 252.0, -14.0, 0.0)
		var rw := clampf(128.0 * pad_scale, 100.0, 170.0)
		var rh := clampf(114.0 * pad_scale, 96.0, 150.0)
		_set_rect(_drive_pad, -12.0 - rw, -12.0 - rh, -12.0, -12.0, 1.0)
	else:
		# Standard (e.g. 1280x720): clear the Web shell's bottom-left desktop hint strip.
		_set_rect(_analog_pad, 12.0, -196.0, 312.0, -56.0, 0.0)
		var rw := clampf(158.0 * pad_scale, 112.0, 210.0)
		var rh := clampf(158.0 * pad_scale, 112.0, 210.0)
		_set_rect(_drive_pad, -14.0 - rw, -14.0 - rh, -14.0, -14.0, 1.0)

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


func _style_toggle(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.10, 0.14, 0.90)
	normal.border_color = Color(0.55, 0.65, 0.78, 0.85)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
