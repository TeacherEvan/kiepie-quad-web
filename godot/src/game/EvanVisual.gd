extends Node3D
## EVAN THE SKELETON — 52-bone humanoid running & shredding animation driver.
##
## Drives four baked NLA clips (Idle_Sway, Play_Strum, Headbang_Riff,
## Action_BigFinish) with speed-coupled playback rate (including reverse
## backpedaling), sub-stepped landing squash & recoil springs, expDecay sprint
## lean / cornering bank, and alternating footstep dust kicks.
##
## Purely cosmetic — physics stats stay identical to KiepieBike, and the same
## driver works on both the local VehicleBody3D and remote StaticBody3D proxies.
## Attach to the instantiated Evan_Skeleton.glb root.

const MAX_FRAME_DT := 0.1
const MAX_SUB_DT := 0.00833

const CLIP_IDLE := "Idle_Sway"
const CLIP_STRUM := "Play_Strum"
const CLIP_HEADBANG := "Headbang_Riff"
const CLIP_FINISH := "Action_BigFinish"
const CLIP_RUN_NO_GUITAR := "Run_NoGuitar"
const CLIP_THROW := "Action_GuitarThrow"
const CLIP_CATCH := "Action_GuitarCatch"

const VFX := preload("res://src/game/VfxFactory.gd")

var _anim: AnimationPlayer = null
var _host: Node3D = null
var _bike: VehicleBody3D = null
var _settings: Node = null

var _last_clip := ""
var _finish_cd := 0.0
var _action_cd := 0.0
var _action_clip := ""
var _reduced := false
var _is_running := false
var _anim_rate := 1.0

var _guitar_meshes: Array[Node3D] = []
var _guitar_anchor: Node3D = null
var _guitar_out_count := 0
var _guitar_out_safety_t := 0.0

var _base_pos := Vector3.ZERO
var _base_rot := Vector3.ZERO
var _base_scale := Vector3.ONE

# Sub-stepped springs & expDecay dynamics
var _pitch := 0.0
var _roll := 0.0
var _yaw_lean := 0.0
var _squash := 0.0
var _squash_v := 0.0
var _recoil := 0.0
var _recoil_v := 0.0

# Stride phase & footstep dust tracking
var _run_phase := 0.0
var _last_step_half := -1

# Grounded / airborne state
var _was_grounded := true
var _air_time := 0.0
var _prev_vy := 0.0
var _prev_fwd_speed := 0.0
var _smooth_accel := 0.0

# Remote-proxy motion estimate (StaticBody3D peers have no linear_velocity).
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

	for mesh in find_children("*", "MeshInstance3D", true, false):
		var m := mesh as Node3D
		if m == null:
			continue
		var mname := str(m.name)
		if mname in ["GuitarBody", "GuitarStrap", "GuitarCable", "RiffMuzzle_L", "RiffMuzzle_R"] \
				or mname.begins_with("GuitarPart_"):
			_guitar_meshes.append(m)
		if mname == "GuitarBody":
			_guitar_anchor = m
	_set_guitar_visible(true)

	for candidate in find_children("*", "AnimationPlayer", true, false):
		if candidate is AnimationPlayer:
			_anim = candidate as AnimationPlayer
			break
	if _anim == null:
		push_warning("EvanVisual: no AnimationPlayer found — GLB animation clips unavailable")
		return
	for loop_clip in [CLIP_IDLE, CLIP_STRUM, CLIP_HEADBANG, CLIP_RUN_NO_GUITAR]:
		if _anim.has_animation(loop_clip):
			_anim.get_animation(loop_clip).loop_mode = Animation.LOOP_LINEAR
	for oneshot_clip in [CLIP_FINISH, CLIP_THROW, CLIP_CATCH]:
		if _anim.has_animation(oneshot_clip):
			_anim.get_animation(oneshot_clip).loop_mode = Animation.LOOP_NONE
	if _anim.has_animation(CLIP_IDLE):
		_anim.play(CLIP_IDLE)
		_last_clip = CLIP_IDLE
	_anim.speed_scale = 1.0


func _set_guitar_visible(vis: bool) -> void:
	for gm in _guitar_meshes:
		if is_instance_valid(gm):
			gm.visible = vis


func is_guitar_out() -> bool:
	return _guitar_out_count > 0


func get_guitar_world_pos() -> Vector3:
	if is_instance_valid(_guitar_anchor):
		return _guitar_anchor.global_position
	if is_instance_valid(_host):
		return _host.global_position + Vector3(0.0, 1.05, 0.0)
	return global_position + Vector3(0.0, 1.05, 0.0)


func on_boomerang_thrown() -> void:
	## Called by BoomerangGuitar.setup() for both local player and remote proxies.
	_guitar_out_count += 1
	_guitar_out_safety_t = 3.5
	_set_guitar_visible(false)
	_recoil_v += 3.8
	if _anim != null and _anim.has_animation(CLIP_THROW):
		_action_cd = 0.42
		_action_clip = CLIP_THROW
		_anim_rate = 1.15 if not _reduced else 0.65
		_anim.speed_scale = _anim_rate
		_anim.play(CLIP_THROW, 0.06)
		_last_clip = CLIP_THROW


func on_boomerang_caught(was_caught: bool = true) -> void:
	## Called when BoomerangGuitar returns to Evan or expires/cleans up.
	_guitar_out_count = maxi(0, _guitar_out_count - 1)
	if _guitar_out_count > 0:
		return
	_guitar_out_safety_t = 0.0
	_set_guitar_visible(true)
	if not was_caught:
		return
	_recoil_v -= 3.2
	_squash_v += 1.2
	if _anim != null and _anim.has_animation(CLIP_CATCH):
		_action_cd = 0.28
		_action_clip = CLIP_CATCH
		_anim_rate = 1.15 if not _reduced else 0.65
		_anim.speed_scale = _anim_rate
		_anim.play(CLIP_CATCH, 0.06)
		_last_clip = CLIP_CATCH
	if not _reduced and is_inside_tree():
		var q := 1.0
		if _settings != null and _settings.has_method("quality_multiplier"):
			q = float(_settings.call("quality_multiplier"))
		if q > 0.0:
			VFX.impact(_fx_parent(), get_guitar_world_pos(), Color(1.0, 0.14, 0.52), Vector3.UP, "metal")
	if _bike != null and is_inside_tree():
		var sfx := get_node_or_null("/root/Sfx")
		if sfx != null and sfx.has_method("play"):
			sfx.call("play", "pop", 1.45, 0.42)


func trigger_recoil(strength: float = 1.0) -> void:
	## SideCannons hook: heavy special/jump triggers Action_BigFinish; light
	## primary shots add spring kick without hijacking the running stride.
	_recoil_v += 4.2 * strength
	if strength < 1.0 or _anim == null or not _anim.has_animation(CLIP_FINISH):
		return
	_finish_cd = 0.68
	_action_cd = 0.0
	_anim_rate = 1.0 if not _reduced else 0.55
	_anim.speed_scale = _anim_rate
	_anim.play(CLIP_FINISH, 0.10)
	_last_clip = CLIP_FINISH


static func _exp_decay(current: float, target: float, rate: float, dt: float) -> float:
	var safe_dt := maxf(dt, 0.0)
	return target + (current - target) * exp(-rate * safe_dt)


static func _step_spring_substepped(pos: float, vel: float, target: float,
		stiffness: float, damping: float, dt: float) -> Vector2:
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

	# ---- 1. Sample host motion (local VehicleBody3D OR remote StaticBody3D)
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
		var steer_v: Variant = _bike.get("_steer")
		steer = 0.0 if steer_v == null else float(steer_v)
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
				var target := clampf(Vector3(disp.x, 0.0, disp.z).length() / maxf(dt, 0.001), 0.0, 60.0)
				_remote_speed = clampf(_exp_decay(_remote_speed, target, 9.0, dt), 0.0, 60.0)
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
		var tv_r: Variant = _host.get("turbo_active")
		turbo = tv_r != null and bool(tv_r)

	var raw_accel := clampf((fwd_speed - _prev_fwd_speed) / dt, -20.0, 20.0)
	_prev_fwd_speed = fwd_speed
	_smooth_accel = _exp_decay(_smooth_accel, raw_accel, 7.5, dt)

	# Airborne & touchdown squash detection
	if not grounded:
		_air_time += dt
	else:
		if not _was_grounded and _air_time > 0.16 and _prev_vy < -2.0:
			var impact := clampf(-_prev_vy * 0.08, 0.20, 0.75) * motion_scale
			_squash_v += 2.6 * impact
			if not _reduced and _settings != null:
				var q := float(_settings.call("quality_multiplier")) if _settings.has_method("quality_multiplier") else 1.0
				if q > 0.0:
					VFX.dust_ring(_fx_parent(), _host.global_position, 0.85, 3.2)
		_air_time = 0.0
	_was_grounded = grounded
	_prev_vy = vy

	# ---- 2. Sub-stepped springs & procedural sprinter lean / bank
	var sq_state := _step_spring_substepped(_squash, _squash_v, 0.0, 140.0, 11.5, dt)
	_squash = clampf(sq_state.x, -0.18, 0.22)
	_squash_v = sq_state.y

	var rec_state := _step_spring_substepped(_recoil, _recoil_v, 0.0, 120.0, 10.0, dt)
	_recoil = clampf(rec_state.x, -0.20, 0.24)
	_recoil_v = rec_state.y

	var speed_lean := clampf(speed * 0.011, 0.0, 0.20) * (-0.5 if (_bike != null and fwd_speed < -0.75) else 1.0)
	var accel_lean := clampf(-_smooth_accel * 0.008, -0.09, 0.11)
	var air_lean := clampf(-vy * 0.025, -0.16, 0.16) * (1.0 if not grounded else 0.0)
	var target_pitch := (speed_lean + accel_lean + air_lean - _recoil * 0.45) * motion_scale
	var target_roll := clampf(-steer * clampf(0.25 + speed * 0.022, 0.20, 0.42), -0.22, 0.22) * motion_scale

	if _guitar_out_count > 0:
		if not _host.visible:
			_guitar_out_count = 0
			_guitar_out_safety_t = 0.0
			_set_guitar_visible(true)
		else:
			_guitar_out_safety_t -= dt
			if _guitar_out_safety_t <= 0.0:
				_guitar_out_count = 0
				_set_guitar_visible(true)

	var target_yaw := clampf(-steer * 0.22, -0.14, 0.14) * motion_scale
	_pitch = _exp_decay(_pitch, target_pitch, 10.0, dt)
	_roll = _exp_decay(_roll, target_roll, 11.0, dt)
	_yaw_lean = _exp_decay(_yaw_lean, target_yaw, 10.0, dt)
	rotation = _base_rot + Vector3(_pitch, _yaw_lean, _roll)
	var sq_xz := 1.0 + _squash * 0.55
	var sq_y := 1.0 - _squash
	scale = Vector3(_base_scale.x * sq_xz, _base_scale.y * sq_y, _base_scale.z * sq_xz)
	position = _base_pos - Vector3(0.0, maxf(0.0, _squash) * 0.18, 0.0)

	# ---- 3. Alternating footstep dust kicks synced to stride cadence
	if grounded and speed > 0.55:
		_run_phase += absf(_anim_rate) * dt * 1.05
		if _run_phase >= 100.0:
			_run_phase = fmod(_run_phase, 100.0)
			_last_step_half = int(floorf(_run_phase * 2.0))
		var step_half := int(floorf(_run_phase * 2.0))
		if step_half != _last_step_half:
			_last_step_half = step_half
			if speed > 3.5 and not _reduced and _settings != null:
				var q := float(_settings.call("quality_multiplier")) if _settings.has_method("quality_multiplier") else 1.0
				if q >= 0.4 and _host.is_inside_tree():
					var side := -0.15 if (step_half % 2 == 0) else 0.15
					var foot_pos := _host.global_position + _host.global_transform.basis.x * side \
							- _host.global_transform.basis.z * 0.18 + Vector3(0.0, 0.06, 0.0)
					VFX.roost(_fx_parent(), foot_pos, _host.global_transform.basis.z)

	# ---- 4. Speed-coupled NLA clip selection
	if _finish_cd > 0.0:
		_finish_cd = maxf(0.0, _finish_cd - dt)
		if _finish_cd > 0.0:
			return
		_last_clip = ""  # force a clean crossfade back into a loop next frame
	if _action_cd > 0.0:
		_action_cd = maxf(0.0, _action_cd - dt)
		if _action_cd > 0.0:
			return
		_action_clip = ""
		_last_clip = ""

	if _is_running and speed < 0.35:
		_is_running = false
	elif not _is_running and speed > 0.55:
		_is_running = true

	var reversing := _bike != null and fwd_speed < -0.55
	var want := CLIP_IDLE
	var rate := 1.0
	if _guitar_out_count > 0:
		if not grounded and _air_time > 0.14 and not _reduced:
			want = CLIP_FINISH
			rate = 1.0
		elif _is_running and _anim.has_animation(CLIP_RUN_NO_GUITAR):
			want = CLIP_RUN_NO_GUITAR
			rate = clampf(0.55 + speed * 0.125, 0.55, 2.75) * (-1.0 if reversing else 1.0)
	elif turbo and not _reduced:
		want = CLIP_HEADBANG
		rate = clampf(1.25 + speed * 0.09, 1.25, 2.65)
	elif not grounded and _air_time > 0.14 and not _reduced:
		want = CLIP_FINISH
		rate = 1.0
	elif _is_running:
		want = CLIP_STRUM
		rate = clampf(0.50 + speed * 0.125, 0.50, 2.70) * (-1.0 if reversing else 1.0)

	_anim_rate = _exp_decay(_anim_rate, rate * (0.55 if _reduced else 1.0), 12.0, dt)
	_anim.speed_scale = _anim_rate
	if want != _last_clip and _anim.has_animation(want):
		_anim.play(want, 0.22)
		_last_clip = want
