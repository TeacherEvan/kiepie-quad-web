extends Node3D
## NARDUS's pogo act (v2 — ballistic physics + sub-stepped secondary springs):
## Four tailored procedural animations driven by real vehicle state:
##   1. Idle_Breathe    — weighty low-Hz rest bob, breathing belly swell, relaxed sway
##   2. Locomotion_Hop  — two-phase ballistic pogo cycle (spring compression dwell +
##                        parabolic flight arc) with live telescoping stick & coil compression
##   3. Jump_Arc        — airborne ramp/dodge spring extension + heavy landing slam
##   4. Action_TurboFlap — counterbalance arm pump blending smoothly into symmetric
##                        turbo bird-wing flapping + banana-cannon recoil kick
##
## Purely cosmetic — physics stats remain identical to KiepieBike.
## Attach to the rider pivot (GLB "Rider" child).

const MAX_FRAME_DT := 0.1
const MAX_SUB_DT := 0.00833

@export var idle_bounce_hz := 1.22       ## weighty relaxed spring settle at rest
@export var move_bounce_base_hz := 1.78  ## natural athletic pogo cadence cruising
@export var bounce_speed_gain := 0.055   ## extra Hz per m/s — builds smoothly with speed
@export var hop_height_max := 0.185      ## peak ballistic hop clearance at speed (m)
@export var spring_stroke := 0.105       ## max telescoping compression stroke (m)
@export var compression_duty := 0.34     ## fraction of cycle spent compressing on ground

# Heavy, underdamped fat-belly spring (lower omega -> unmistakably weighty jiggle)
@export var belly_stiffness := 38.0
@export var belly_damping := 3.5
@export var belly_lag := 0.036
@export var belly_lateral_gain := 0.048

# Head inertia spring
@export var head_stiffness := 68.0
@export var head_damping := 7.2

@export var squash_amount := 0.13        ## volume-preserving torso compression on impact
@export var lean_amount := 0.11          ## visual cornering bank (rad)
@export var pitch_speed_gain := 0.011    ## forward lean into motion (rad per m/s)
@export var bounce_sway := 0.036         ## playful side-to-side hop swagger (rad)

@export var flap_hz := 9.5               ## bird wing-beats per second during turbo
@export var flap_amp_z := 1.08           ## vertical wing flap arc (rad)
@export var flap_amp_x := 0.32           ## wing-tip feather pitch twist (rad)
@export var flap_amp_y := 0.28           ## forward-back rowing wing sweep (rad)

var _belly: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _stick: Node3D
var _stick_upper: Node3D
var _spring_coil: Node3D

var _bike: VehicleBody3D
var _host_node: Node3D
var _settings: Node = null

var _base_y := 0.0
var _stick_base_y := 0.0
var _upper_base_y := 0.0
var _belly_base_pos := Vector3.ZERO
var _head_base_rot := Vector3.ZERO

var _cycle := 0.0          ## normalized hop cycle [0..1)
var _breathe_t := 0.0
var _flap_phase := 0.0
var _flap_blend := 0.0

# Sub-stepped secondary springs (position + velocity)
var _belly_y := 0.0
var _belly_vy := 0.0
var _belly_x := 0.0
var _belly_vx := 0.0
var _head_pitch := 0.0
var _head_vpitch := 0.0
var _head_yaw := 0.0
var _head_roll := 0.0

# Smoothed vehicle motion & airborne tracking
var _pitch := 0.0
var _roll := 0.0
var _move_blend := 0.0
var _air_blend := 0.0
var _air_time := 0.0
var _was_grounded := true
var _prev_vy := 0.0
var _prev_fwd_speed := 0.0
var _smooth_accel := 0.0
var _land_impact := 0.0
var _recoil := 0.0
var _prev_rider_y := 0.0
var _prev_rider_vy := 0.0

# Remote proxy motion estimator (for StaticBody3D NetworkedBike peers)
var _has_prev_host_pos := false
var _prev_host_pos := Vector3.ZERO
var _prev_host_yaw := 0.0
var _remote_speed := 0.0
var _remote_steer := 0.0
var _remote_vy := 0.0


func _ready() -> void:
	var node := get_parent()
	while node != null and not (node is VehicleBody3D) and not (node is StaticBody3D):
		node = node.get_parent()
	_host_node = node as Node3D
	_bike = node as VehicleBody3D
	_settings = get_node_or_null("/root/Settings")
	_base_y = position.y
	_prev_rider_y = _base_y

	_belly = get_node_or_null("Belly")
	if _belly != null:
		_belly_base_pos = _belly.position
	else:
		push_warning("PogoVisual: Belly node not found under %s" % name)
	_head = get_node_or_null("Head")
	if _head != null:
		_head_base_rot = _head.rotation
	_arm_l = get_node_or_null("Arm_L")
	_arm_r = get_node_or_null("Arm_R")

	var model := get_parent()
	if model != null:
		_stick = model.get_node_or_null("Stick") as Node3D
		if _stick != null:
			_stick_base_y = _stick.position.y
			_stick_upper = _stick.get_node_or_null("StickUpper") as Node3D
			if _stick_upper != null:
				_upper_base_y = _stick_upper.position.y
			_spring_coil = _stick.get_node_or_null("SpringCoil") as Node3D


func trigger_recoil(strength: float = 1.0) -> void:
	## Called by SideCannons when Nardus fires bananas/rockets for crisp physical kickback.
	_recoil = clampf(_recoil + 0.55 * strength, 0.0, 1.0)
	_belly_vy -= 0.45 * strength
	_head_vpitch -= 1.8 * strength


static func _exp_decay(current: float, target: float, rate: float, dt: float) -> float:
	var safe_dt := maxf(dt, 0.0)
	return target + (current - target) * exp(-rate * safe_dt)


static func _step_spring_substepped(pos: float, vel: float, target: float,
		stiffness: float, damping: float, dt: float) -> Vector2:
	## Dynamically sub-stepped Symplectic Euler spring solver (Plastic Surgery spec).
	## Clamps elapsed frame dt <= 0.1s (never step count) so sub_dt <= 8.33ms.
	var safe_dt := clampf(dt, 0.0, MAX_FRAME_DT)
	var steps := maxi(1, int(ceilf(safe_dt / MAX_SUB_DT)))
	var sub_dt := safe_dt / float(steps)
	var p := pos
	var v := vel
	for _i in range(steps):
		var accel := -stiffness * (p - target) - damping * v
		v += accel * sub_dt
		p += v * sub_dt
	return Vector2(p, v)


func _physics_process(delta: float) -> void:
	var dt := clampf(delta, 0.0, MAX_FRAME_DT)
	if dt <= 0.00001:
		return

	var reduced := false
	if _settings != null and _settings.has_method("reduced_motion"):
		reduced = bool(_settings.call("reduced_motion"))
	var motion_scale := 0.30 if reduced else 1.0

	# ---- 1. Sample host motion (local VehicleBody3D OR remote NetworkedBike proxy)
	var speed := 0.0
	var fwd_speed := 0.0
	var steer := 0.0
	var vy := 0.0
	var grounded := true
	var dodging := false
	if _bike != null:
		var v := _bike.linear_velocity
		speed = Vector3(v.x, 0.0, v.z).length()
		fwd_speed = v.dot(_bike.global_transform.basis.z)
		vy = v.y
		var steer_v: Variant = _bike.get("_steer")
		steer = 0.0 if steer_v == null else float(steer_v)
		if _bike.has_method("_grounded"):
			grounded = bool(_bike.call("_grounded"))
		var dt_dodge: Variant = _bike.get("_dodge_time")
		dodging = dt_dodge != null and float(dt_dodge) > 0.0
	elif _host_node != null and _host_node.is_inside_tree():
		var cur_pos := _host_node.global_position
		var h_fwd := _host_node.global_transform.basis.z
		var has_h := Vector2(h_fwd.x, h_fwd.z).length_squared() > 0.04
		var cur_yaw := atan2(h_fwd.x, h_fwd.z) if has_h else _prev_host_yaw
		if _has_prev_host_pos:
			var disp := cur_pos - _prev_host_pos
			if disp.length() < 8.0:  # ignore respawn teleports
				var inst_speed := Vector3(disp.x, 0.0, disp.z).length() / dt
				var inst_vy := disp.y / dt
				var dyaw := wrapf(cur_yaw - _prev_host_yaw, -PI, PI) / dt
				_remote_speed = _exp_decay(_remote_speed, inst_speed, 10.0, dt)
				_remote_vy = _exp_decay(_remote_vy, inst_vy, 12.0, dt)
				_remote_steer = _exp_decay(_remote_steer, clampf(dyaw * 0.28, -0.62, 0.62), 10.0, dt)
		else:
			_has_prev_host_pos = true
		_prev_host_pos = cur_pos
		_prev_host_yaw = cur_yaw
		speed = _remote_speed
		fwd_speed = _remote_speed
		steer = _remote_steer
		vy = _remote_vy
		grounded = absf(vy) < 2.2

	var raw_accel := clampf((fwd_speed - _prev_fwd_speed) / dt, -18.0, 18.0)
	_prev_fwd_speed = fwd_speed
	_smooth_accel = _exp_decay(_smooth_accel, raw_accel, 7.5, dt)

	# Airborne & touchdown detection (Jump_Arc animation)
	if not grounded:
		_air_time += dt
	else:
		if not _was_grounded and _air_time > 0.16 and _prev_vy < -1.8:
			# Touchdown slam! Compress spring hard and send a shockwave into the belly & head
			var impact := clampf(-_prev_vy * 0.13, 0.35, 1.0) * motion_scale
			_land_impact = maxf(_land_impact, impact)
			_cycle = compression_duty * 0.38  # snap into downward compression stroke
			_belly_vy -= 1.65 * impact
			_head_vpitch += 3.2 * impact
		_air_time = 0.0
	_was_grounded = grounded
	_prev_vy = vy

	var target_air := 1.0 if (not grounded and _air_time > 0.09) else 0.0
	_air_blend = _exp_decay(_air_blend, target_air, 12.0, dt)
	_land_impact = _exp_decay(_land_impact, 0.0, 6.5, dt)
	_recoil = _exp_decay(_recoil, 0.0, 14.0, dt)

	var raw_move := clampf((speed - 0.35) / 3.2, 0.0, 1.0)
	raw_move = raw_move * raw_move * (3.0 - 2.0 * raw_move)  # smoothstep
	_move_blend = _exp_decay(_move_blend, raw_move, 6.5, dt)

	# ---- 2. Idle_Breathe + Locomotion_Hop (Two-phase ballistic pogo physics)
	_breathe_t += dt
	var rest_freq := idle_bounce_hz
	var move_freq := clampf(move_bounce_base_hz + speed * bounce_speed_gain, 1.65, 3.25)
	var freq := lerpf(rest_freq, move_freq, _move_blend)

	if _air_blend < 0.75:
		_cycle = fmod(_cycle + freq * dt, 1.0)
	else:
		# While airborne off a ramp, gently hold near apex posture until touchdown
		_cycle = _exp_decay(_cycle, 0.66, 5.0, dt)

	var spring_comp := 0.0     # meters downward compression of upper pogo tube
	var spring_stretch := 0.0  # slight extension rebound right after launch / in air
	var hop_lift := 0.0        # whole-pogo parabolic lift off the ground
	var rider_rebound := 0.0   # slight lively rider follow-through relative to footpegs
	var squash := 0.0

	if _cycle < compression_duty:
		# Phase A: Ground Contact & Spring Compression Dwell
		var tc := _cycle / compression_duty
		var comp_curve := sin(PI * tc)
		# Weighty idle rest dip vs energetic moving pogo compression
		var stroke := lerpf(0.026, spring_stroke, _move_blend) * motion_scale
		spring_comp = comp_curve * stroke
		squash = (lerpf(0.035, squash_amount, _move_blend) * comp_curve) * motion_scale
	else:
		# Phase B: Parabolic Ballistic Flight Arc (hang-time at apex!)
		var ta := (_cycle - compression_duty) / (1.0 - compression_duty)
		var parabola := 4.0 * ta * (1.0 - ta)  # 0 at launch -> 1 at apex -> 0 at touchdown
		# At idle, feet stay planted (tiny 0.008m spring lift); at speed, crisp visible hop arc!
		var peak_h := lerpf(0.008, hop_height_max, _move_blend) * motion_scale
		hop_lift = parabola * peak_h
		# Spring snaps slightly past neutral right after liftoff, then settles for landing
		spring_stretch = sin(PI * ta) * lerpf(0.005, 0.022, _move_blend) * motion_scale
		rider_rebound = parabola * lerpf(0.004, 0.018, _move_blend) * motion_scale
		# Subtle vertical stretch right at launch/fall
		squash = -0.045 * sin(PI * ta) * _move_blend * motion_scale

	# Layer in airborne Jump_Arc override & heavy landing compression slam
	spring_comp = lerpf(spring_comp, 0.0, _air_blend) + _land_impact * 0.085
	spring_stretch = lerpf(spring_stretch, 0.030 * motion_scale, _air_blend)
	hop_lift = lerpf(hop_lift, 0.04 * motion_scale, _air_blend)
	squash = lerpf(squash, -0.04 * motion_scale, _air_blend) + _land_impact * 0.14

	# Apply live telescoping physics to Stick (StickUpper + SpringCoil) AND Rider!
	# Because Stick and Rider share hop_lift and spring_comp, Nardus's sandals stay
	# solidly planted on the pogo foot-pegs the entire time!
	var upper_off := -spring_comp + spring_stretch
	if _stick != null:
		_stick.position.y = _stick_base_y + hop_lift
	if _stick_upper != null:
		_stick_upper.position.y = _upper_base_y + upper_off
	if _spring_coil != null:
		# Spring coil rest height is 0.45m; compress Y and bulge XZ for volume preservation
		var sy := clampf(1.0 + upper_off / 0.44, 0.56, 1.14)
		var sxz := clampf(1.0 + (1.0 - sy) * 0.42, 0.94, 1.22)
		_spring_coil.scale = Vector3(sxz, sy, sxz)

	var new_rider_y := _base_y + hop_lift + upper_off + rider_rebound
	position.y = new_rider_y
	var sq_xz := 1.0 + squash * 0.58
	var sq_y := 1.0 - squash
	scale = Vector3(sq_xz, sq_y, sq_xz)

	# Compute true vertical acceleration of Rider for physically authentic secondary jiggle!
	var rider_vy := (new_rider_y - _prev_rider_y) / dt
	var rider_ay := clampf((rider_vy - _prev_rider_vy) / dt, -45.0, 45.0)
	_prev_rider_y = new_rider_y
	_prev_rider_vy = rider_vy

	# ---- 3. Sub-Stepped Fat Belly 2-Axis Spring + Breathing Swell
	var breath := sin(_breathe_t * 2.65) * 0.018 * (1.0 - 0.5 * _move_blend) * motion_scale
	var target_by := clampf(-rider_ay * belly_lag * 0.14 - _land_impact * 0.08 + breath, -0.14, 0.13)
	var by_state := _step_spring_substepped(_belly_y, _belly_vy, target_by, belly_stiffness, belly_damping, dt)
	_belly_y = clampf(by_state.x, -0.15, 0.14)
	_belly_vy = by_state.y

	# Centrifugal cornering slosh: turning left (+steer) swings heavy belly right (-X)
	var turn_force := -steer * clampf(speed * 0.16, 0.15, 1.35) * belly_lateral_gain * motion_scale
	var sway_jiggle := -sin(_cycle * TAU * 0.5) * 0.016 * _move_blend * motion_scale
	var bx_state := _step_spring_substepped(_belly_x, _belly_vx, turn_force + sway_jiggle,
			belly_stiffness * 0.78, belly_damping * 0.95, dt)
	_belly_x = clampf(bx_state.x, -0.09, 0.09)
	_belly_vx = bx_state.y

	if _belly != null:
		_belly.position = Vector3(
			_belly_base_pos.x + _belly_x,
			_belly_base_pos.y + _belly_y,
			_belly_base_pos.z + breath * 0.55 - _recoil * 0.025
		)
		# Gelatinous squash-and-stretch + droop tilt on the belly itself!
		var b_stretch := clampf(_belly_vy * 0.11, -0.14, 0.14) * motion_scale
		var b_breath := 1.0 + breath * 1.4
		_belly.scale = Vector3(
			(1.0 - b_stretch * 0.55) * b_breath,
			1.0 + b_stretch,
			(1.0 - b_stretch * 0.45) * b_breath
		)
		_belly.rotation = Vector3(
			clampf(-_belly_y * 1.15 - _recoil * 0.18, -0.22, 0.22),
			0.0,
			clampf(_belly_x * 1.8, -0.18, 0.18)
		)

	# ---- 4. Organic Torso Pitch & Bank (expDecay, acceleration/braking/airborne responsive)
	var accel_pitch := clampf(-_smooth_accel * 0.0085, -0.10, 0.12)  # lean back on punch, forward on brake
	var speed_pitch := clampf(speed * pitch_speed_gain, 0.0, 0.16)
	var air_pitch := clampf(-vy * 0.028, -0.18, 0.18) * _air_blend
	var recoil_pitch := -_recoil * 0.12
	var target_pitch := (speed_pitch + accel_pitch + air_pitch + recoil_pitch) * motion_scale
	var hop_sway := sin(_cycle * PI) * bounce_sway * lerpf(0.25, 1.0, _move_blend) * motion_scale
	var target_roll := clampf((-steer * lean_amount * clampf(0.35 + speed * 0.10, 0.35, 1.35) + hop_sway) * motion_scale, -0.18, 0.18)

	_pitch = _exp_decay(_pitch, target_pitch, 10.5, dt)
	_roll = _exp_decay(_roll, target_roll, 11.0, dt)
	rotation.x = _pitch
	rotation.z = _roll
	if _stick != null:
		# Subtle stick tilt follows Rider's cornering bank & forward hop drive
		_stick.rotation.x = _pitch * 0.65
		_stick.rotation.z = _roll * 0.72

	# ---- 5. Expressive Head Follow-Through (turn-look + bounce nod + swagger tilt)
	if _head != null:
		var target_hpitch := clampf(-rider_ay * 0.0085 - _recoil * 0.20 + air_pitch * 0.45, -0.24, 0.24) * motion_scale
		var hp_state := _step_spring_substepped(_head_pitch, _head_vpitch, target_hpitch, head_stiffness, head_damping, dt)
		_head_pitch = clampf(hp_state.x, -0.32, 0.32)
		_head_vpitch = hp_state.y
		var look_yaw := clampf(steer * 0.48, -0.38, 0.38) * motion_scale
		_head_yaw = _exp_decay(_head_yaw, look_yaw, 9.0, dt)
		var head_tilt := clampf(-_roll * 0.65 + sin(_breathe_t * 1.9) * 0.025 * (1.0 - _move_blend), -0.18, 0.18) * motion_scale
		_head_roll = _exp_decay(_head_roll, head_tilt, 9.5, dt)
		_head.rotation = _head_base_rot + Vector3(_head_pitch, _head_yaw, _head_roll)

	# ---- 6. Action_TurboFlap + Natural Counterbalance Arm Pumping
	# Symmetric Z guarantees Arm_L.rotation.z == -Arm_R.rotation.z on every frame
	# (both during normal pogo hops AND during turbo/overdrive bird-flapping).
	var turbo := false
	if _host_node != null:
		var t_val: Variant = _host_node.get("turbo_active")
		var o_val: Variant = _host_node.get("overdrive_active")
		turbo = (t_val != null and bool(t_val)) or (o_val != null and bool(o_val))
	_flap_blend = move_toward(_flap_blend, 1.0 if turbo else 0.0, dt * 8.5)

	# Natural arm counterbalance: raises arms slightly during compression & airborne hang-time
	var pump_wave := sin((_cycle - 0.12) * TAU)
	var idle_arm_z := (0.045 * sin(_breathe_t * 2.65) + 0.14 * pump_wave * _move_blend
			+ 0.22 * _air_blend + 0.16 * _land_impact) * motion_scale
	var idle_arm_x := (-0.08 * pump_wave * _move_blend - 0.18 * _recoil
			+ (0.18 if dodging else 0.0)) * motion_scale
	var idle_arm_y := (0.06 * _move_blend * cos(_cycle * TAU)) * motion_scale

	var flap_z := 0.0
	var flap_x := 0.0
	var flap_y := 0.0
	var wing_scale := 0.0
	if _flap_blend > 0.001:
		_flap_phase += TAU * flap_hz * dt
		wing_scale = (0.45 if reduced else 1.0) * _flap_blend
		flap_z = sin(_flap_phase) * flap_amp_z * wing_scale
		flap_y = cos(_flap_phase) * flap_amp_y * wing_scale
		flap_x = cos(_flap_phase) * flap_amp_x * wing_scale
	else:
		_flap_phase = 0.0

	var final_z := lerpf(idle_arm_z, flap_z, _flap_blend)
	var final_x := lerpf(idle_arm_x, flap_x, _flap_blend)
	var final_y := lerpf(idle_arm_y, flap_y, _flap_blend)
	var span := Vector3(1.0 + 0.14 * wing_scale, 1.0, 1.0)
	if _arm_l != null:
		_arm_l.rotation = Vector3(final_x, final_y, -final_z)
		_arm_l.scale = span
	if _arm_r != null:
		_arm_r.rotation = Vector3(final_x, -final_y, final_z)
		_arm_r.scale = span
