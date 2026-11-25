extends Node3D
## LEA UNICORN — 52-joint winged-equine animation driver.
##
## Drives the four baked NLA clips (Idle_Breathe, Locomotion_Gallop,
## Action_WingSpread, UnicornBoom_Flight) with speed-coupled gallop playback,
## reverse backpedalling, charge wing-expansion and a one-shot leap/flight for
## the Unicorn Boom special. Purely cosmetic: physics stats stay identical to
## KiepieBike, and the same driver works on local and remote proxies.
## Attach to the instantiated Lea_Unicorn.glb root.

const MAX_FRAME_DT := 0.1
const MAX_SUB_DT := 0.00833

const CLIP_IDLE := "Idle_Breathe"
const CLIP_GALLOP := "Locomotion_Gallop"
const CLIP_SPREAD := "Action_WingSpread"
const CLIP_BOOM := "UnicornBoom_Flight"

const VFX := preload("res://src/game/VfxFactory.gd")

var _anim: AnimationPlayer = null
var _host: Node3D = null
var _bike: VehicleBody3D = null
var _settings: Node = null
var _horn_anchor: Node3D = null

var _last_clip := ""
var _charge_cd := 0.0
var _boom_cd := 0.0
var _action_cd := 0.0
var _anim_rate := 1.0
var _reduced := false
var _is_galloping := false

var _base_pos := Vector3.ZERO
var _base_rot := Vector3.ZERO
var _base_scale := Vector3.ONE

var _pitch := 0.0
var _roll := 0.0
var _squash := 0.0
var _squash_v := 0.0
var _recoil := 0.0
var _recoil_v := 0.0

var _was_grounded := true
var _air_time := 0.0
var _prev_vy := 0.0
var _prev_fwd_speed := 0.0
var _smooth_accel := 0.0
var _gallop_phase := 0.0
var _last_beat := -1

# Remote proxies are StaticBody3D — estimate a bounded speed from tick deltas.
var _has_prev_pos := false
var _prev_pos := Vector3.ZERO
var _prev_yaw := 0.0
var _remote_speed := 0.0
var _remote_vy := 0.0
var _remote_steer := 0.0


func _ready() -> void:
	_host = get_parent() as Node3D
	_bike = _host as VehicleBody3D
	_settings = get_node_or_null("/root/Settings")
	_base_pos = position
	_base_rot = rotation
	_base_scale = scale
	_horn_anchor = find_child("HornTip", true, false) as Node3D
	for candidate in find_children("*", "AnimationPlayer", true, false):
		if candidate is AnimationPlayer:
			_anim = candidate as AnimationPlayer
			break
	if _anim == null:
		push_warning("LeaVisual: no AnimationPlayer found — GLB clips unavailable")
		return
	for loop_clip in [CLIP_IDLE, CLIP_GALLOP]:
		if _anim.has_animation(loop_clip):
			_anim.get_animation(loop_clip).loop_mode = Animation.LOOP_LINEAR
	for oneshot in [CLIP_SPREAD, CLIP_BOOM]:
		if _anim.has_animation(oneshot):
			_anim.get_animation(oneshot).loop_mode = Animation.LOOP_NONE
	if _anim.has_animation(CLIP_IDLE):
		_anim.play(CLIP_IDLE)
		_last_clip = CLIP_IDLE
	_anim.speed_scale = 1.0


func get_horn_world_pos() -> Vector3:
	if is_instance_valid(_horn_anchor):
		return _horn_anchor.global_position
	if is_instance_valid(_host):
		return _host.global_position + Vector3(0.0, 1.9, -0.6)
	return global_position + Vector3(0.0, 1.9, -0.6)


func trigger_charge(strength: float = 1.0) -> void:
	## HornBeam.setup() calls this for both the local rider and remote proxies.
	_recoil_v += 2.4 * clampf(strength, 0.0, 2.0)
	if _anim == null or not _anim.has_animation(CLIP_SPREAD):
		return
	_charge_cd = 0.72
	_action_cd = 0.72
	_anim_rate = 1.0 if not _reduced else 0.60
	_anim.speed_scale = _anim_rate
	_anim.play(CLIP_SPREAD, 0.05)
	_last_clip = CLIP_SPREAD


func trigger_boom(duration: float = 2.05) -> void:
	## UnicornBoom.setup() calls this for the local rider and remote proxies.
	_recoil_v += 3.2
	if _anim == null or not _anim.has_animation(CLIP_BOOM):
		return
	_boom_cd = maxf(1.35, duration)
	_action_cd = _boom_cd
	var boom_anim := _anim.get_animation(CLIP_BOOM)
	if boom_anim != null:
		boom_anim.loop_mode = Animation.LOOP_LINEAR
	_anim_rate = 1.0 if not _reduced else 0.55
	_anim.speed_scale = _anim_rate
	_anim.play(CLIP_BOOM, 0.04)
	_last_clip = CLIP_BOOM


static func _exp_decay(current: float, target: float, rate: float, dt: float) -> float:
	return target + (current - target) * exp(-rate * maxf(dt, 0.0))


static func _spring(pos: float, vel: float, target: float, stiffness: float,
		damping: float, dt: float) -> Vector2:
	var safe_dt := clampf(dt, 0.0, MAX_FRAME_DT)
	var steps := maxi(1, int(ceilf(safe_dt / MAX_SUB_DT)))
	var sub_dt := safe_dt / float(steps)
	var p := pos
	var v := vel
	for _i in range(steps):
		v += (-stiffness * (p - target) - damping * v) * sub_dt
		p += v * sub_dt
	return Vector2(p, v)


func _fx_parent() -> Node3D:
	if get_tree() != null and get_tree().current_scene is Node3D:
		return get_tree().current_scene as Node3D
	return _host


func _physics_process(delta: float) -> void:
	var dt := clampf(delta, 0.0, MAX_FRAME_DT)
	if dt <= 0.00001 or _anim == null or _host == null:
		return
	_reduced = false
	if _settings != null and _settings.has_method("reduced_motion"):
		_reduced = bool(_settings.call("reduced_motion"))
	var motion_scale := 0.30 if _reduced else 1.0

	var speed := 0.0
	var fwd_speed := 0.0
	var steer := 0.0
	var vy := 0.0
	var grounded := true
	var turbo := false
	if _bike != null:
		var v := _bike.linear_velocity
		speed = Vector3(v.x, 0.0, v.z).length()
		fwd_speed = v.dot(_bike.global_transform.basis.z)
		vy = v.y
		var sv: Variant = _bike.get("_steer")
		steer = 0.0 if sv == null else float(sv)
		if _bike.has_method("_grounded"):
			grounded = bool(_bike.call("_grounded"))
		var tv: Variant = _bike.get("turbo_active")
		var ov: Variant = _bike.get("overdrive_active")
		turbo = (tv != null and bool(tv)) or (ov != null and bool(ov))
	elif _host.is_inside_tree():
		var now := _host.global_position
		var h_fwd := _host.global_transform.basis.z
		var has_h := Vector2(h_fwd.x, h_fwd.z).length_squared() > 0.04
		var cur_yaw := atan2(h_fwd.x, h_fwd.z) if has_h else _prev_yaw
		if _has_prev_pos:
			var disp := now - _prev_pos
			if disp.length() < 8.0:  # ignore respawn teleports
				_remote_speed = clampf(_exp_decay(_remote_speed,
						clampf(Vector3(disp.x, 0.0, disp.z).length() / maxf(dt, 0.001), 0.0, 60.0), 9.0, dt), 0.0, 60.0)
				_remote_vy = _exp_decay(_remote_vy, disp.y / maxf(dt, 0.001), 12.0, dt)
				var dyaw := wrapf(cur_yaw - _prev_yaw, -PI, PI) / maxf(dt, 0.001)
				_remote_steer = _exp_decay(_remote_steer, clampf(dyaw * 0.25, -0.60, 0.60), 10.0, dt)
		else:
			_has_prev_pos = true
		_prev_pos = now
		_prev_yaw = cur_yaw
		speed = _remote_speed
		fwd_speed = _remote_speed
		steer = _remote_steer
		vy = _remote_vy
		grounded = absf(vy) < 2.2
		var tr: Variant = _host.get("turbo_active")
		turbo = tr != null and bool(tr)

	var raw_accel := clampf((fwd_speed - _prev_fwd_speed) / dt, -20.0, 20.0)
	_prev_fwd_speed = fwd_speed
	_smooth_accel = _exp_decay(_smooth_accel, raw_accel, 7.5, dt)

	if not grounded:
		_air_time += dt
	else:
		if not _was_grounded and _air_time > 0.16 and _prev_vy < -2.0:
			var impact := clampf(-_prev_vy * 0.08, 0.20, 0.75) * motion_scale
			_squash_v += 2.6 * impact
			if not _reduced and _settings != null and _settings.has_method("quality_multiplier"):
				var q := float(_settings.call("quality_multiplier"))
				if q > 0.0:
					VFX.dust_ring(_fx_parent(), _host.global_position, 0.85, 3.2)
		_air_time = 0.0
	_was_grounded = grounded
	_prev_vy = vy

	var sq := _spring(_squash, _squash_v, 0.0, 140.0, 11.5, dt)
	_squash = clampf(sq.x, -0.18, 0.22)
	_squash_v = sq.y
	var rec := _spring(_recoil, _recoil_v, 0.0, 120.0, 10.0, dt)
	_recoil = clampf(rec.x, -0.20, 0.24)
	_recoil_v = rec.y

	var speed_lean := clampf(speed * 0.010, 0.0, 0.18) * (-0.5 if (_bike != null and fwd_speed < -0.75) else 1.0)
	var accel_lean := clampf(-_smooth_accel * 0.008, -0.09, 0.11)
	var air_lean := clampf(-vy * 0.025, -0.16, 0.16) * (1.0 if not grounded else 0.0)
	var target_pitch := (speed_lean + accel_lean + air_lean - _recoil * 0.45) * motion_scale
	var target_roll := clampf(-steer * clampf(0.25 + speed * 0.022, 0.20, 0.42), -0.22, 0.22) * motion_scale
	var target_yaw := clampf(-steer * 0.22, -0.14, 0.14) * motion_scale
	_pitch = _exp_decay(_pitch, target_pitch, 10.0, dt)
	_roll = _exp_decay(_roll, target_roll, 11.0, dt)
	rotation = _base_rot + Vector3(_pitch, target_yaw, _roll)
	var sq_xz := 1.0 + _squash * 0.55
	scale = Vector3(_base_scale.x * sq_xz, _base_scale.y * (1.0 - _squash), _base_scale.z * sq_xz)
	position = _base_pos - Vector3(0.0, maxf(0.0, _squash) * 0.18, 0.0)

	if grounded and speed > 0.55:
		_gallop_phase += absf(_anim_rate) * dt * 1.25
		if _gallop_phase >= 100.0:
			_gallop_phase = fmod(_gallop_phase, 100.0)
			_last_beat = int(floorf(_gallop_phase * 4.0))
		var beat := int(floorf(_gallop_phase * 4.0))
		if beat != _last_beat:
			_last_beat = beat
			if speed > 3.5 and not _reduced and _settings != null and _settings.has_method("quality_multiplier"):
				var q := float(_settings.call("quality_multiplier"))
				if q >= 0.4 and _host.is_inside_tree():
					var side := -0.16 if (beat % 2 == 0) else 0.16
					var hoof_pos := _host.global_position + _host.global_transform.basis.x * side \
							- _host.global_transform.basis.z * 0.20 + Vector3(0.0, 0.06, 0.0)
					VFX.roost(_fx_parent(), hoof_pos, _host.global_transform.basis.z)

	if _charge_cd > 0.0:
		_charge_cd = maxf(0.0, _charge_cd - dt)
		if _charge_cd > 0.0:
			return
	if _boom_cd > 0.0:
		_boom_cd = maxf(0.0, _boom_cd - dt)
		if _boom_cd > 0.0:
			return
	if _action_cd > 0.0:
		_action_cd = maxf(0.0, _action_cd - dt)
		if _action_cd > 0.0:
			return
		_last_clip = ""

	if _is_galloping and speed < 0.35:
		_is_galloping = false
	elif not _is_galloping and speed > 0.55:
		_is_galloping = true
	var reversing := _bike != null and fwd_speed < -0.55
	var want := CLIP_IDLE
	var rate := 1.0
	if turbo and not _reduced:
		want = CLIP_BOOM
		rate = clampf(1.10 + speed * 0.06, 1.10, 2.20)
	elif not grounded and _air_time > 0.14 and not _reduced:
		want = CLIP_BOOM
		rate = 1.0
	elif _is_galloping:
		want = CLIP_GALLOP
		rate = clampf(0.50 + speed * 0.115, 0.50, 2.65) * (-1.0 if reversing else 1.0)
	_anim_rate = _exp_decay(_anim_rate, rate * (0.55 if _reduced else 1.0), 12.0, dt)
	_anim.speed_scale = _anim_rate
	if want != _last_clip and _anim.has_animation(want):
		_anim.play(want, 0.22)
		_last_clip = want
