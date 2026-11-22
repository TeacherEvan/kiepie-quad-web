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

func _ready() -> void:
	add_to_group("camera_rig")
	fov_base = float(Settings.get_value("video", "fov", 62.0))
	if Settings.has_signal("changed") and not Settings.is_connected("changed", _on_settings_changed):
		Settings.connect("changed", _on_settings_changed)
	_target = get_node_or_null(target_path) as Node3D
	_cam = get_node_or_null("Camera3D") as Camera3D
	_radius = orbit_radius


func _exit_tree() -> void:
	if Settings != null and Settings.has_signal("changed") and Settings.is_connected("changed", _on_settings_changed):
		Settings.disconnect("changed", _on_settings_changed)


func _on_settings_changed(section: String, key: String, value: Variant) -> void:
	if section == "video" and key == "fov":
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
	var to_target := look_target - global_position
	if to_target.length_squared() <= 1e-4:
		return
	var look_dir := to_target.normalized()
	var up_vec := desired_up.normalized() if desired_up.length_squared() > 1e-4 else Vector3.UP
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
	if _target == null:
		return
	if _spectate_target != null:
		if Time.get_ticks_msec() / 1000.0 >= _spectate_until or not is_instance_valid(_spectate_target):
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
	var dt := minf(delta, 0.05)
	var turbo := bool(_target.get("turbo_active")) and not Settings.reduced_motion()
	var spd := (_target as RigidBody3D).linear_velocity.length() if _target is RigidBody3D else 0.0
	var speed_fov := clampf((spd - 10.0) / 26.0, 0.0, 1.0) * 5.0 if not Settings.reduced_motion() else 0.0
	var want_fov := fov_base + speed_fov + (fov_kick if turbo else 0.0)
	if _cam:
		_cam.fov = lerpf(_cam.fov, want_fov, 1.0 - exp(-6.0 * dt))

	var target_up := Vector3.UP
	if "loop_up" in _target:
		var lup: Vector3 = _target.get("loop_up")
		if lup.length_squared() > 0.25:
			target_up = lup.normalized()
	_cam_up = _cam_up.lerp(target_up, 1.0 - exp(-8.0 * dt))
	if _cam_up.length_squared() < 1e-4:
		_cam_up = Vector3.UP
	else:
		_cam_up = _cam_up.normalized()

	if mode == "follow":
		var basis := _target.global_transform.basis.orthonormalized()
		var fwd := basis.z
		if _target is RigidBody3D:
			var lv := (_target as RigidBody3D).linear_velocity
			var horiz_v := Vector3(lv.x, 0.0, lv.z)
			if horiz_v.length() > 8.0 and _cam_up.dot(Vector3.UP) > 0.85:
				var vel_dir := horiz_v.normalized()
				if fwd.dot(vel_dir) > 0.25:
					fwd = fwd.lerp(vel_dir, 0.45).normalized()
		if _follow_dir.length_squared() < 0.01:
			_follow_dir = fwd
		else:
			_follow_dir = _follow_dir.lerp(fwd, 1.0 - exp(-14.5 * dt)).normalized()
		var desired := _target.global_transform.origin - _follow_dir * distance + _cam_up * height
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
