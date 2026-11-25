extends Node3D
## Camera rig for the Kiepie Bike demo.
## FOLLOW (default): eases behind and above the quad.
## FREE ( "C" or the View button): orbit the bike with the mouse (drag to
## rotate, scroll to zoom) - inspect it from any angle.

@export var target_path: NodePath
@export var height := 1.9
@export var distance := 4.6
@export var look_offset := Vector3(0.0, 0.72, 0.0)
@export var follow_speed := 20.0
@export var orbit_radius := 6.4
@export var orbit_height := 2.4
@export var fov_base := 62.0
@export var fov_kick := 9.0

var mode := "follow"
var _target: Node3D
var _cam: Camera3D
var _yaw := 0.7
var _pitch := 0.42
var _radius := 6.4
var _dragging := false
var _shake := 0.0
var _spectate_target: Node3D
var _spectate_until := 0.0
var _saved_mode := "follow"
var _cam_up := Vector3.UP
var _follow_dir := Vector3.ZERO

func add_shake(amount: float) -> void:
	# Single reduced-motion sink: every caller (CombatController, SideCannons,
	# DestructibleBuilding) funnels through here.
	if Settings.reduced_motion():
		return
	_shake = maxf(_shake, amount)


func spectate(target: Node3D, seconds: float) -> void:
	if target == null:
		return
	_spectate_target = target
	_spectate_until = Time.get_ticks_msec() / 1000.0 + seconds
	if mode != "free":
		_saved_mode = mode
		mode = "free"

static func _vec_ok(v: Vector3) -> bool:
	return v.is_finite() and v.length_squared() < 1e6


func _ensure_clean_basis() -> void:
	if not global_transform.basis.is_finite() or absf(global_transform.basis.determinant()) < 0.01:
		var pos := global_position if _vec_ok(global_position) else Vector3.ZERO
		global_transform = Transform3D(Basis.IDENTITY, pos)


func _ready() -> void:
	add_to_group("camera_rig")
	fov_base = float(Settings.get_value("video", "fov", 62.0))
	if Settings.has_signal("changed") and not Settings.is_connected("changed", _on_settings_changed):
		Settings.connect("changed", _on_settings_changed)
	_target = get_node_or_null(target_path) as Node3D
	_cam = get_node_or_null("Camera3D") as Camera3D
	if _cam != null:
		_cam.near = maxf(_cam.near, 0.1)
		_cam.far = minf(_cam.far, 600.0)
	_radius = orbit_radius


func snap_to_target() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if not _vec_ok(_target.global_position) or not _target.global_transform.basis.is_finite():
		return
	_ensure_clean_basis()
	_spectate_target = null
	mode = "follow"
	_shake = 0.0
	_cam_up = Vector3.UP
	var basis := _target.global_transform.basis.orthonormalized()
	var fwd := basis.z
	if not _vec_ok(fwd) or fwd.length_squared() < 0.01:
		fwd = Vector3.BACK
	_follow_dir = fwd.normalized()
	global_position = _target.global_transform.origin - _follow_dir * distance + Vector3.UP * height
	if _cam != null:
		if not _cam.transform.is_finite():
			_cam.transform = Transform3D.IDENTITY
		_cam.position = Vector3.ZERO
		if not _cam.current:
			_cam.current = true
		_cam.fov = clampf(fov_base, 30.0, 110.0)
	_safe_look_at(_target.global_transform.origin + Vector3.UP * look_offset.y, Vector3.UP)


func _exit_tree() -> void:
	if Settings != null and Settings.has_signal("changed") and Settings.is_connected("changed", _on_settings_changed):
		Settings.disconnect("changed", _on_settings_changed)


func _on_settings_changed(section: String, key: String, value: Variant) -> void:
	if section == "*":
		fov_base = float(Settings.get_value("video", "fov", 62.0))
	elif section == "video" and key == "fov":
		fov_base = float(value)

func toggle_view() -> void:
	mode = "free" if mode == "follow" else "follow"
	if mode == "free" and _target:
		# seed the orbit from wherever the camera currently is
		var d := global_position - _target.global_position
		_radius = clampf(d.length(), 2.6, 15.0)
		_yaw = atan2(d.x, d.z)
		_pitch = clampf(asin(clampf(d.y / maxf(d.length(), 0.01), -1.0, 1.0)), 0.06, 1.25)

func _safe_look_at(look_target: Vector3, desired_up: Vector3) -> void:
	_ensure_clean_basis()
	if not _vec_ok(look_target) or not _vec_ok(global_position):
		return
	var to_target := look_target - global_position
	if to_target.length_squared() <= 1e-4:
		return
	var look_dir := to_target.normalized()
	var up_vec := desired_up.normalized() if (_vec_ok(desired_up) and desired_up.length_squared() > 1e-4) else Vector3.UP
	if absf(look_dir.dot(up_vec)) > 0.96:
		if _target != null and is_instance_valid(_target):
			var bike_up := _target.global_transform.basis.y.normalized()
			if bike_up.length_squared() > 0.5 and absf(look_dir.dot(bike_up)) <= 0.96:
				up_vec = bike_up
			elif absf(look_dir.dot(Vector3.FORWARD)) <= 0.96:
				up_vec = Vector3.FORWARD
			else:
				up_vec = Vector3.RIGHT
		elif absf(look_dir.dot(Vector3.FORWARD)) <= 0.96:
			up_vec = Vector3.FORWARD
		else:
			up_vec = Vector3.RIGHT
	look_at(look_target, up_vec)


func _process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if _spectate_target != null:
		if not is_instance_valid(_spectate_target) or not _vec_ok(_spectate_target.global_position) or Time.get_ticks_msec() / 1000.0 >= _spectate_until:
			_spectate_target = null
			mode = _saved_mode
		else:
			var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _radius
			global_position = _spectate_target.global_position + offset
			_safe_look_at(_spectate_target.global_position + look_offset, Vector3.UP)
			if _cam != null:
				_cam.position = Vector3.ZERO
			_shake = move_toward(_shake, 0.0, delta * 3.0)
			return
	if not _vec_ok(_target.global_position) or not _target.global_transform.basis.is_finite():
		if _target.has_method("reset_bike"):
			_target.call("reset_bike")
		return
	var dt := minf(delta, 0.05)
	var turbo := bool(_target.get("turbo_active")) and not Settings.reduced_motion()
	var spd := (_target as RigidBody3D).linear_velocity.length() if _target is RigidBody3D else 0.0
	if not is_finite(spd):
		spd = 0.0
	var speed_fov := clampf((spd - 10.0) / 26.0, 0.0, 1.0) * 5.0 if not Settings.reduced_motion() else 0.0
	var want_fov := fov_base + speed_fov + (fov_kick if turbo else 0.0)
	if _cam:
		if not _cam.transform.is_finite():
			_cam.transform = Transform3D.IDENTITY
		if not _cam.current:
			_cam.current = true
		if not is_finite(_cam.fov) or _cam.fov < 20.0 or _cam.fov > 140.0:
			_cam.fov = clampf(fov_base, 30.0, 110.0)
		_cam.fov = lerpf(_cam.fov, want_fov, 1.0 - exp(-6.0 * dt))

	var target_up := Vector3.UP
	if "loop_up" in _target:
		var lup: Vector3 = _target.get("loop_up")
		if lup.is_finite() and lup.length_squared() > 0.25:
			target_up = lup.normalized()
	if not _vec_ok(_cam_up) or _cam_up.length_squared() < 1e-4:
		_cam_up = Vector3.UP
	_cam_up = _cam_up.lerp(target_up, 1.0 - exp(-8.0 * dt))
	if not _vec_ok(_cam_up) or _cam_up.length_squared() < 1e-4:
		_cam_up = Vector3.UP
	else:
		_cam_up = _cam_up.normalized()

	if mode == "follow":
		var basis := _target.global_transform.basis.orthonormalized()
		var fwd := basis.z
		if not _vec_ok(fwd) or fwd.length_squared() < 0.01:
			fwd = Vector3.BACK
		if _target is RigidBody3D:
			var lv := (_target as RigidBody3D).linear_velocity
			if lv.is_finite():
				var horiz_v := Vector3(lv.x, 0.0, lv.z)
				if horiz_v.length() > 8.0 and _cam_up.dot(Vector3.UP) > 0.85:
					var vel_dir := horiz_v.normalized()
					if fwd.dot(vel_dir) > 0.25:
						fwd = fwd.lerp(vel_dir, 0.45).normalized()
		if not _vec_ok(_follow_dir) or _follow_dir.length_squared() < 0.01:
			_follow_dir = fwd.normalized()
		else:
			if _follow_dir.dot(fwd) < -0.999:
				var perp := Vector3(-fwd.z, 0.0, fwd.x)
				if perp.length_squared() < 1e-4:
					perp = Vector3.RIGHT
				_follow_dir = (_follow_dir + perp.normalized() * 0.05).normalized()
			_follow_dir = _follow_dir.lerp(fwd, 1.0 - exp(-14.5 * dt)).normalized()
			if not _vec_ok(_follow_dir) or _follow_dir.length_squared() < 0.01:
				_follow_dir = fwd.normalized()
		var desired := _target.global_transform.origin - _follow_dir * distance + _cam_up * height
		if not _vec_ok(global_position) or global_position.distance_to(desired) > 80.0:
			global_position = desired
		else:
			global_position = global_position.lerp(desired, 1.0 - exp(-maxf(follow_speed, 20.0) * dt))
	elif mode == "free":
		var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _radius
		global_position = _target.global_position + offset
	var look_target := _target.global_transform.origin + _cam_up * look_offset.y
	_safe_look_at(look_target, _cam_up if mode == "follow" else Vector3.UP)
	if _shake > 0.001:
		var s := _shake * Settings.shake_multiplier()
		var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * s
		if _cam != null:
			_cam.position = jitter
		else:
			global_position += jitter
		_shake = move_toward(_shake, 0.0, delta * 2.5)
	elif _cam != null and _cam.position != Vector3.ZERO:
		_cam.position = Vector3.ZERO

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_toggle") and event is InputEventKey:
		toggle_view()
		return
	if mode != "free":
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_radius = clampf(_radius - 0.7, 2.6, 15.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_radius = clampf(_radius + 0.7, 2.6, 15.0)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.0085
		_pitch = clampf(_pitch + mm.relative.y * 0.0065, 0.06, 1.25)
