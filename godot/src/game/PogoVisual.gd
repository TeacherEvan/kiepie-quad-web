extends Node3D
## NARDUS's pogo act: the rider bobs on the stick, the belly sloshes, the
## whole man squeezes a bit on landing. Purely cosmetic — physics stats are
## identical to the bike. Attach to the rider pivot (GLB "Rider" child).

@export var bounce_base_hz := 2.15      ## hops per second at rest
@export var bounce_speed_gain := 0.05   ## extra Hz per m/s — pogo gets cheekier with speed
@export var bounce_amp := 0.085         ## peak rider height (m)
@export var belly_stiffness := 58.0     ## underdamped → J-E-L-L-O
@export var belly_damping := 5.2
@export var belly_lag := 0.055          ## how hard the belly trails the rider
@export var squash_amount := 0.16       ## landing squash (fraction of Y scale)
@export var lean_amount := 0.065        ## cornering lean (visual only)
@export var pitch_speed_gain := 0.012   ## forward tilt into motion (rad per m/s)
@export var bounce_sway := 0.032        ## rhythmic side-to-side hop swagger (rad)
@export var flap_hz := 9.5              ## bird wing-beats per second during turbo
@export var flap_amp_z := 1.05          ## vertical wing flap arc (rad, ~60 deg full bird flap)
@export var flap_amp_x := 0.32          ## wing-tip feather pitch twist on up/downstroke (rad)
@export var flap_amp_y := 0.28          ## forward-back rowing wing sweep (rad)

var _belly: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _phase := 0.0
var _flap_phase := 0.0
var _flap_blend := 0.0
var _belly_off := 0.0
var _belly_vel := 0.0
var _bike: VehicleBody3D
var _host_node: Node3D
var _base_y := 0.0
var _pitch := 0.0
var _roll := 0.0


func _ready() -> void:
	# Rider pivot is a child of the GLB root ("Model"), which is a child of the
	# VehicleBody3D (local) or StaticBody3D (NetworkedBike remote proxy).
	var node := get_parent()
	while node != null and not (node is VehicleBody3D) and not (node is StaticBody3D):
		node = node.get_parent()
	_host_node = node as Node3D
	_bike = node as VehicleBody3D
	_base_y = position.y
	_belly = get_node_or_null("Belly")
	_arm_l = get_node_or_null("Arm_L")
	_arm_r = get_node_or_null("Arm_R")
	if _belly == null:
		push_warning("PogoVisual: Belly node not found under %s" % name)


func _physics_process(delta: float) -> void:
	var dt := minf(maxf(delta, 0.0), 0.1)
	var speed := 0.0
	var steer := 0.0
	if _bike != null:
		var v := _bike.linear_velocity
		speed = Vector3(v.x, 0.0, v.z).length()
		var steer_v: Variant = _bike.get("_steer")   # cross-script read; no input duplication
		steer = 0.0 if steer_v == null else float(steer_v)
	# advance the bounce
	var reduced := false
	var settings := get_node_or_null("/root/Settings")
	if settings != null and settings.has_method("reduced_motion"):
		reduced = bool(settings.call("reduced_motion"))
	var motion_scale := 0.35 if reduced else 1.0

	var freq := bounce_base_hz + speed * bounce_speed_gain
	_phase += TAU * freq * dt

	# rider height: 0 .. bounce_amp, smooth cos arc, hits the stick at phase 0
	var lift := (1.0 - cos(_phase)) * 0.5 * bounce_amp * motion_scale
	position.y = _base_y + lift

	# landing squash: strongest at the bottom of the arc (cos(_phase) == 1)
	var bottom := maxf(0.0, cos(_phase))
	var squash := squash_amount * motion_scale * pow(bottom, 3.0)
	scale = Vector3(1.0 + squash * 0.7, 1.0 - squash, 1.0 + squash * 0.7)

	# belly slosh: spring the belly against the rider's vertical acceleration
	var rider_accel := cos(_phase) * bounce_amp * motion_scale * pow(TAU * freq, 2.0)
	var target := clampf(-rider_accel * belly_lag, -0.16, 0.16)
	_belly_vel += (target - _belly_off) * belly_stiffness * dt
	_belly_vel *= exp(-belly_damping * dt)
	_belly_off += _belly_vel * dt
	if _belly != null:
		_belly.position.y = _belly_base_y() + _belly_off

	# exponential-decay pitch (forward lean with speed) & roll (cornering + playful hop sway)
	var decay := 1.0 - exp(-10.0 * dt)
	var target_pitch := clampf(speed * pitch_speed_gain, 0.0, 0.16) * motion_scale
	var sway := sin(_phase * 0.5) * bounce_sway * motion_scale * clampf(0.35 + speed * 0.08, 0.35, 1.0)
	var target_roll := clampf(-steer * lean_amount + sway, -0.11, 0.11)
	_pitch = lerpf(_pitch, target_pitch, decay)
	_roll = lerpf(_roll, target_roll, decay)
	rotation.x = _pitch
	rotation.z = _roll

	# Turbo bird-flap: Nardus flaps both arms like a bird whenever turbo or overdrive is active!
	var turbo := false
	if _host_node != null:
		var t_val: Variant = _host_node.get("turbo_active")
		var o_val: Variant = _host_node.get("overdrive_active")
		turbo = (t_val != null and bool(t_val)) or (o_val != null and bool(o_val))
	_flap_blend = move_toward(_flap_blend, 1.0 if turbo else 0.0, dt * 8.5)
	if _flap_blend > 0.001:
		_flap_phase += TAU * flap_hz * dt
		var wing_scale := (0.45 if reduced else 1.0) * _flap_blend
		var flap_z := sin(_flap_phase) * flap_amp_z * wing_scale
		var sweep_y := cos(_flap_phase) * flap_amp_y * wing_scale
		var twist_x := cos(_flap_phase) * flap_amp_x * wing_scale
		var span := Vector3(1.0 + 0.14 * wing_scale, 1.0, 1.0)
		if _arm_l != null:
			_arm_l.rotation = Vector3(twist_x, sweep_y, -flap_z)
			_arm_l.scale = span
		if _arm_r != null:
			_arm_r.rotation = Vector3(twist_x, -sweep_y, flap_z)
			_arm_r.scale = span
	else:
		_flap_phase = 0.0
		if _arm_l != null:
			_arm_l.rotation = Vector3.ZERO
			_arm_l.scale = Vector3.ONE
		if _arm_r != null:
			_arm_r.rotation = Vector3.ZERO
			_arm_r.scale = Vector3.ONE


var _belly_base_cached := INF
func _belly_base_y() -> float:
	if _belly_base_cached == INF:
		_belly_base_cached = _belly.position.y if _belly != null else 1.39
	return _belly_base_cached
