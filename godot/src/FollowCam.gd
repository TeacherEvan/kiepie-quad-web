extends Node3D
## Camera rig for the Kiepie Bike demo.
## FOLLOW (default): eases behind and above the quad.
## FREE ( "C" or the View button): orbit the bike with the mouse (drag to
## rotate, scroll to zoom) - inspect it from any angle.

@export var target_path: NodePath
@export var height := 1.9
@export var distance := 4.6
@export var look_offset := Vector3(0.0, 0.72, 0.0)
@export var follow_speed := 4.0
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

func add_shake(amount: float) -> void:
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
	_target = get_node_or_null(target_path) as Node3D
	_cam = get_node_or_null("Camera3D") as Camera3D
	_radius = orbit_radius

func toggle_view() -> void:
	mode = "free" if mode == "follow" else "follow"
	if mode == "free" and _target:
		# seed the orbit from wherever the camera currently is
		var d := global_position - _target.global_position
		_radius = clampf(d.length(), 2.6, 15.0)
		_yaw = atan2(d.x, d.z)
		_pitch = clampf(asin(clampf(d.y / maxf(d.length(), 0.01), -1.0, 1.0)), 0.06, 1.25)

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
			look_at(_spectate_target.global_position + look_offset, Vector3.UP)
			_shake = move_toward(_shake, 0.0, delta * 3.0)
			return
	var turbo := bool(_target.get("turbo_active")) and not Settings.reduced_motion()
	var want_fov := fov_base + (fov_kick if turbo else 0.0)
	if _cam:
		_cam.fov = lerpf(_cam.fov, want_fov, clampf(delta * 6.0, 0.0, 1.0))

	if mode == "follow":
		var basis := _target.global_transform.basis.orthonormalized()
		var desired := _target.global_transform.origin - basis.z * distance + Vector3(0.0, height, 0.0)
		global_position = global_position.lerp(desired, clampf(delta * follow_speed, 0.0, 1.0))
	elif mode == "free":
		var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _radius
		global_position = _target.global_position + offset
	look_at(_target.global_transform.origin + look_offset, Vector3.UP)
	if _shake > 0.001:
		var s := _shake * Settings.shake_multiplier()
		global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * s
		_shake = move_toward(_shake, 0.0, delta * 2.5)

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
