extends Node3D
## EVAN THE SKELETON — 52-bone humanoid animation driver.
##
## The GLB carries four baked NLA clips (Idle_Sway, Play_Strum, Headbang_Riff,
## Action_BigFinish). This controller selects the right clip from real vehicle
## state, so the same rig works on the local VehicleBody3D and on remote
## StaticBody3D proxies. Purely cosmetic — physics stats stay identical to the
## Kiepie Quad, exactly like PogoVisual.gd.
##
## Attach to the instantiated Evan_Skeleton.glb root.

const CLIP_IDLE := "Idle_Sway"
const CLIP_STRUM := "Play_Strum"
const CLIP_HEADBANG := "Headbang_Riff"
const CLIP_FINISH := "Action_BigFinish"

var _anim: AnimationPlayer = null
var _host: Node3D = null
var _bike: VehicleBody3D = null
var _settings: Node = null

var _last_clip := ""
var _finish_cd := 0.0
var _reduced := false

# Remote-proxy motion estimate (StaticBody3D peers have no linear_velocity).
var _has_prev_pos := false
var _prev_pos := Vector3.ZERO
var _remote_speed := 0.0


func _ready() -> void:
	_host = get_parent() as Node3D
	_bike = _host as VehicleBody3D
	_settings = get_node_or_null("/root/Settings")
	for candidate in find_children("*", "AnimationPlayer", true, false):
		if candidate is AnimationPlayer:
			_anim = candidate as AnimationPlayer
			break
	if _anim == null:
		push_warning("EvanVisual: no AnimationPlayer found — GLB animation clips unavailable")
		return
	if _anim.has_animation(CLIP_IDLE):
		_anim.play(CLIP_IDLE)
		_last_clip = CLIP_IDLE
	_anim.speed_scale = 1.0


func trigger_recoil(_strength: float = 1.0) -> void:
	## SideCannons hook: a riff flourish when Evan fires.
	if _anim == null or not _anim.has_animation(CLIP_FINISH):
		return
	_finish_cd = 1.2
	_anim.play(CLIP_FINISH, 0.14)
	_last_clip = CLIP_FINISH


func _physics_process(delta: float) -> void:
	if _anim == null or _host == null:
		return
	_reduced = false
	if _settings != null and _settings.has_method("reduced_motion"):
		_reduced = bool(_settings.call("reduced_motion"))
	_anim.speed_scale = 0.55 if _reduced else 1.0

	if _finish_cd > 0.0:
		_finish_cd = maxf(0.0, _finish_cd - delta)
		if _finish_cd > 0.0:
			return
		_last_clip = ""  # force a clean crossfade back into a loop next frame

	var speed := 0.0
	var turbo := false
	if _bike != null:
		var v := _bike.linear_velocity
		speed = Vector3(v.x, 0.0, v.z).length()
		var tv: Variant = _bike.get("turbo_active")
		var ov: Variant = _bike.get("overdrive_active")
		turbo = (tv != null and bool(tv)) or (ov != null and bool(ov))
	elif _host.is_inside_tree():
		var now := _host.global_position
		if _has_prev_pos:
			var disp := now - _prev_pos
			if disp.length() < 8.0:  # ignore respawn teleports
				_remote_speed = lerpf(_remote_speed,
						Vector3(disp.x, 0.0, disp.z).length() / maxf(delta, 0.001), 9.0)
		else:
			_has_prev_pos = true
		_prev_pos = now
		speed = _remote_speed

	var want := CLIP_IDLE
	if turbo and not _reduced:
		want = CLIP_HEADBANG
	elif speed > 1.2:
		want = CLIP_STRUM
	if want != _last_clip and _anim.has_animation(want):
		_anim.play(want, 0.28)
		_last_clip = want
