extends Node3D
## Player weapon mount & 3-weapon arsenal manager:
## - "primary": Twin Machine Gun (Quad) / Dual Banana Cannon (Nardus) / F1 Autocannon (Big-Ben)
## - "rocket":  Rocket Launcher (1.5s cooldown). Direct hit = instant kill;
##              anything else inside 4.5m loses 90% health. NARDUS launches a
##              massive CIGAR; BIG-BEN launches a CASH BAG; Quad a normal rocket.
## - "meteor":  Meteor Shower (6.0s cooldown, practical ground aim reticle, 2.0s sky-fall delay, massive 3.5x AOE damage)

signal fired(token: String)
signal weapon_changed(weapon_id: String, label: String)
signal reload_changed(progress: float, remaining: float, is_ready: bool, label: String)

const PROJECTILE := preload("res://src/game/Projectile.gd")
const BANANA := preload("res://src/game/BananaProjectile.gd")
const ROCKET := preload("res://src/game/RocketProjectile.gd")
const METEOR := preload("res://src/game/MeteorStrike.gd")
const SOUNDWAVE := preload("res://src/game/SoundWaveProjectile.gd")
const BOOMERANG := preload("res://src/game/BoomerangGuitar.gd")
const DEVIL_HAND := preload("res://src/game/DevilHandStrike.gd")
const VFX := preload("res://src/game/VfxFactory.gd")

# Keep in sync with the remote-shot speed in ArenaNet._spawn_remote_shot.
const SHOT_SPEED := 52.0
const ROCKET_SPEED := 38.0
const SHOT_SPREAD := 0.055

const WEAPON_ORDER := ["primary", "rocket", "meteor"]
const ROCKET_COOLDOWN := 1.5
const ROCKET_BLAST_RADIUS := 4.5
const METEOR_COOLDOWN := 6.0
const METEOR_FALL_TIME := 2.0
const METEOR_DAMAGE_MULT := 3.5
const METEOR_BLAST_RADIUS := 7.5
const METEOR_AIM_MIN_DIST := 12.0
const METEOR_AIM_MAX_DIST := 44.0
const METEOR_AIM_DEFAULT_DIST := 25.0

# Per-vehicle primary firing profiles. Static geometry/color only; balance stats
# (cooldown, damage_mult, spread, sfx) are derived from VehicleRegistry as the
# single source of truth so SideCannons and ArenaNet never diverge.
const PROFILES := {
	"bike": {
		"muzzles": [["Muzzle_L", "Cannon_Bore_L", -0.62], ["Muzzle_R", "Cannon_Bore_R", 0.62]],
		"color": Color(1.0, 0.55, 0.15), "banana": false,
	},
	"pogo": {
		"muzzles": [["BananaMuzzle_L", "BananaMuzzle_L", -0.235], ["BananaMuzzle_R", "BananaMuzzle_R", 0.235]],
		"color": Color(1.0, 0.9, 0.25), "banana": true,
	},
	"aston": {
		"muzzles": [["AstonMuzzle_L", "Cannon_Bore_L", -0.46], ["AstonMuzzle_R", "Cannon_Bore_R", 0.46]],
		"color": Color(0.68, 1.0, 0.20), "banana": false,
	},
	"evan": {
		"muzzles": [["RiffMuzzle_L", "RiffMuzzle_L", -0.085], ["RiffMuzzle_R", "RiffMuzzle_R", 0.085]],
		"color": Color(0.95, 0.10, 0.46), "banana": false,
	},
}

var owner_node: Node3D
var owner_id := ""
var hit_callback: Callable
var weapon_profile := "bike"
var current_weapon := "primary"

var _cooldowns := {"primary": 0.0, "rocket": 0.0, "meteor": 0.0}
var _cooldown: float:
	get:
		return float(_cooldowns.get(current_weapon, 0.0))
	set(v):
		_cooldowns[current_weapon] = maxf(0.0, v)
var _rapid := false
var _muzzles: Array[Node3D] = []
var _color := Color(1.0, 0.55, 0.15)
var _fx_holder: Node3D = null
var _profile: Dictionary = PROFILES["bike"]
var _aim_reticle: Node3D = null
var _aim_mat: StandardMaterial3D = null
var _cached_meteor_target := Vector3.ZERO
var _has_cached_meteor := false
var _aim_ray_query: PhysicsRayQueryParameters3D = null
var _last_reload_progress := -1.0
var _last_reload_ready := true
var _last_weapon_emitted := ""
var _last_aim_state := ""
const PROJ_POOL_SIZE := 48
var _proj_pool: Array[Node3D] = []
var _proj_pool_idx := 0
var _muzzle_flashes: Array[GPUParticles3D] = []


static func _profile_for(profile_id: String) -> Dictionary:
	var key := profile_id if PROFILES.has(profile_id) else "bike"
	var base: Dictionary = (PROFILES[key] as Dictionary).duplicate(true)
	# Single source of truth for per-vehicle combat balance lives in VehicleRegistry.
	var veh := VehicleRegistry.from_profile(key)
	base["cooldown"] = VehicleRegistry.cooldown(veh)
	base["rapid_cooldown"] = VehicleRegistry.rapid_cooldown(veh)
	base["damage_mult"] = VehicleRegistry.damage_multiplier(veh)
	base["spread"] = VehicleRegistry.spread(veh)
	base["sfx"] = VehicleRegistry.fire_sfx(veh)
	base["speed"] = SHOT_SPEED
	return base


func reset_cooldowns() -> void:
	for k in _cooldowns.keys():
		_cooldowns[k] = 0.0


func setup(p_owner: Node3D, p_owner_id: String, p_hit_callback: Callable, p_color: Color,
		p_profile: String = "bike") -> void:
	owner_node = p_owner
	owner_id = p_owner_id
	hit_callback = p_hit_callback
	weapon_profile = p_profile if PROFILES.has(p_profile) else "bike"
	_profile = _profile_for(weapon_profile)
	_color = Color(_profile["color"]) if weapon_profile != "bike" else p_color
	# purge stale fallback mounts & muzzle flashes from an earlier setup on the same owner
	for mf in _muzzle_flashes:
		if is_instance_valid(mf):
			mf.queue_free()
	_muzzle_flashes.clear()
	for old_p in _proj_pool:
		if is_instance_valid(old_p):
			old_p.queue_free()
	_proj_pool.clear()
	_proj_pool_idx = 0
	for m in _muzzles:
		if is_instance_valid(m) and (bool(m.get_meta("fallback_muzzle", false)) or str(m.name).begins_with("MuzzleFallback")):
			m.queue_free()
	_muzzles.clear()
	# Prefer the authored muzzle empties/meshes, with a per-side fallback so one
	# missing anchor must not triple the mounts.
	for spec in _profile["muzzles"]:
		var found: Node3D = null
		for node_name in [spec[0], spec[1]]:
			found = _find_named(p_owner, node_name)
			if found != null:
				break
		if found != null:
			_muzzles.append(found)
		else:
			var anchor := Node3D.new()
			anchor.name = "MuzzleFallback"
			anchor.set_meta("fallback_muzzle", true)
			anchor.position = Vector3(spec[2], 0.62, 0.78)
			p_owner.add_child(anchor)
			_muzzles.append(anchor)
	_emit_reload_status(true)


func _find_named(root: Node, wanted: String) -> Node3D:
	if root.name == wanted and root is Node3D:
		return root as Node3D
	for c in root.get_children():
		var found := _find_named(c, wanted)
		if found != null:
			return found
	return null


func _exit_tree() -> void:
	for p in _proj_pool:
		if is_instance_valid(p):
			p.queue_free()
	_proj_pool.clear()
	for mf in _muzzle_flashes:
		if is_instance_valid(mf):
			mf.queue_free()
	_muzzle_flashes.clear()
	if _aim_reticle != null and is_instance_valid(_aim_reticle):
		_aim_reticle.queue_free()
	_aim_reticle = null
	if _fx_holder != null and is_instance_valid(_fx_holder):
		_fx_holder.queue_free()
	_fx_holder = null


func weapon_display_name(w_id: String = "") -> String:
	var w := current_weapon if w_id == "" else w_id
	match w:
		"rocket":
			# Three distinct launchers — do not mix their identities up.
			if weapon_profile == "pogo":
				return "CIGAR LAUNCHER"
			if weapon_profile == "aston":
				return "CASH BAG LAUNCHER"
			if weapon_profile == "evan":
				return "BOOMERANG GUITAR"
			return "ROCKET LAUNCHER"
		"meteor":
			if weapon_profile == "bike":
				return "LIGHTNING STRIKE"
			if weapon_profile == "aston":
				return "CASH BAG DROP"
			if weapon_profile == "evan":
				return "DEVIL HAND"
			return "METEOR SHOWER"
		_:
			if weapon_profile == "pogo":
				return "BANANA CANNON"
			if weapon_profile == "aston":
				return "F1 AUTOCANNON"
			if weapon_profile == "evan":
				return "RIFF BLASTER"
			return "MACHINE GUN"


func max_cooldown_for(w_id: String = "") -> float:
	var w := current_weapon if w_id == "" else w_id
	match w:
		"rocket":
			return ROCKET_COOLDOWN
		"meteor":
			return METEOR_COOLDOWN
		_:
			return float(_profile["rapid_cooldown"] if _rapid else _profile["cooldown"])


func reload_progress(w_id: String = "") -> float:
	var w := current_weapon if w_id == "" else w_id
	var rem := float(_cooldowns.get(w, 0.0))
	if rem <= 0.001:
		return 1.0
	var max_cd := maxf(0.01, max_cooldown_for(w))
	return clampf(1.0 - rem / max_cd, 0.0, 1.0)


func remaining_cooldown(w_id: String = "") -> float:
	var w := current_weapon if w_id == "" else w_id
	return maxf(0.0, float(_cooldowns.get(w, 0.0)))


func cycle_weapon(step: int = 1) -> String:
	var idx := WEAPON_ORDER.find(current_weapon)
	if idx < 0:
		idx = 0
	idx = posmod(idx + step, WEAPON_ORDER.size())
	select_weapon(WEAPON_ORDER[idx])
	return current_weapon


func select_weapon(weapon_or_idx: Variant) -> void:
	var next_w := "primary"
	if weapon_or_idx is int:
		var idx := clampi(int(weapon_or_idx), 0, WEAPON_ORDER.size() - 1)
		next_w = WEAPON_ORDER[idx]
	else:
		var s := str(weapon_or_idx)
		if WEAPON_ORDER.has(s):
			next_w = s
	var changed := next_w != current_weapon
	current_weapon = next_w
	if changed:
		var sfx := get_node_or_null("/root/Sfx")
		if sfx != null and sfx.has_method("play_ui"):
			sfx.call("play_ui", "ui_click")
		weapon_changed.emit(current_weapon, weapon_display_name(current_weapon))
	_has_cached_meteor = false
	_update_aim_reticle(0.0)
	_emit_reload_status(true)


func _physics_process(_delta: float) -> void:
	if current_weapon == "meteor" and owner_node != null \
			and is_instance_valid(owner_node) and owner_node.visible:
		_cached_meteor_target = compute_meteor_target()
		_has_cached_meteor = true


func _process(delta: float) -> void:
	for k in _cooldowns.keys():
		_cooldowns[k] = maxf(0.0, float(_cooldowns[k]) - delta)
	_update_aim_reticle(delta)
	_emit_reload_status(false)


func _emit_reload_status(force: bool) -> void:
	var prog := reload_progress(current_weapon)
	var rem := remaining_cooldown(current_weapon)
	var rdy := rem <= 0.001
	var lbl := weapon_display_name(current_weapon)
	if force or rdy != _last_reload_ready or _last_weapon_emitted != current_weapon \
			or absf(prog - _last_reload_progress) >= 0.015:
		_last_reload_progress = prog
		_last_reload_ready = rdy
		_last_weapon_emitted = current_weapon
		reload_changed.emit(prog, rem, rdy, lbl)


func set_rapid(value: bool) -> void:
	_rapid = value


func can_fire() -> bool:
	return owner_node != null and _cooldown <= 0.0 and float(_cooldowns.get(current_weapon, 0.0)) <= 0.0


func compute_meteor_target() -> Vector3:
	if owner_node == null or not is_instance_valid(owner_node):
		return Vector3.ZERO
	var forward := owner_node.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 1e-6:
		forward = Vector3.BACK
	else:
		forward = forward.normalized()

	# Blend with camera look direction if a camera rig is active so players can steer aim naturally
	var tree := get_tree()
	if tree != null:
		var cam_rig := tree.get_first_node_in_group("camera_rig") as Node3D
		if cam_rig != null and is_instance_valid(cam_rig):
			var cam_fwd := -cam_rig.global_transform.basis.z
			cam_fwd.y = 0.0
			if cam_fwd.length_squared() > 1e-4:
				cam_fwd = cam_fwd.normalized()
				if cam_fwd.dot(forward) > 0.15:
					forward = (forward * 0.45 + cam_fwd * 0.55).normalized()

	var speed := 0.0
	if "linear_velocity" in owner_node:
		var lv: Vector3 = owner_node.get("linear_velocity")
		speed = Vector3(lv.x, 0.0, lv.z).length()
	var aim_dist := clampf(METEOR_AIM_DEFAULT_DIST + speed * 0.45, METEOR_AIM_MIN_DIST, METEOR_AIM_MAX_DIST)
	var cand := owner_node.global_position + forward * aim_dist
	cand.y = owner_node.global_position.y

	# Practical Aim Assist: if a visible enemy bike is inside a 22° forward cone (10m..46m),
	# gently bias the target point toward that enemy's predicted ground position.
	if tree != null:
		var best_enemy: Node3D = null
		var best_score := 1e9
		for b in tree.get_nodes_in_group("bike"):
			if b == owner_node or not is_instance_valid(b) or not (b is Node3D):
				continue
			var bn := b as Node3D
			if not bn.visible:
				continue
			var to_enemy := bn.global_position - owner_node.global_position
			var dist := Vector3(to_enemy.x, 0.0, to_enemy.z).length()
			if dist < 8.0 or dist > METEOR_AIM_MAX_DIST + 4.0:
				continue
			var dir_2d := Vector3(to_enemy.x, 0.0, to_enemy.z).normalized()
			var align := forward.dot(dir_2d)
			if align < 0.91:  # ~24 deg half-cone
				continue
			var score := dist * (1.15 - align)
			if score < best_score:
				best_score = score
				best_enemy = bn
		if best_enemy != null:
			var lead := Vector3.ZERO
			if "linear_velocity" in best_enemy:
				var ev: Vector3 = best_enemy.get("linear_velocity")
				lead = Vector3(ev.x, 0.0, ev.z) * 0.55
			cand = cand.lerp(best_enemy.global_position + lead, 0.72)

	# Snap to the ground / track surface via downward physics raycast.
	# Start at +2.6m above the bike (below overhead loop roofs at 10-17m and
	# finish banners at 6m!) so the reticle always hugs the drivable road surface.
	var world := owner_node.get_world_3d()
	if world != null:
		if _aim_ray_query == null:
			_aim_ray_query = PhysicsRayQueryParameters3D.new()
			_aim_ray_query.collide_with_areas = false
			_aim_ray_query.collide_with_bodies = true
		_aim_ray_query.from = Vector3(cand.x, owner_node.global_position.y + 2.6, cand.z)
		_aim_ray_query.to = Vector3(cand.x, owner_node.global_position.y - 12.0, cand.z)
		if owner_node is CollisionObject3D:
			_aim_ray_query.exclude = [(owner_node as CollisionObject3D).get_rid()]
		else:
			_aim_ray_query.exclude = []
		var hit_res := world.direct_space_state.intersect_ray(_aim_ray_query)
		if not hit_res.is_empty():
			cand = hit_res.get("position", cand)
		else:
			cand.y = 0.02
	else:
		cand.y = 0.02
	return cand


func _update_aim_reticle(delta: float = 0.0) -> void:
	var show_reticle := current_weapon == "meteor" and owner_node != null \
			and is_instance_valid(owner_node) and owner_node.visible
	if not show_reticle:
		if _aim_reticle != null and is_instance_valid(_aim_reticle):
			_aim_reticle.visible = false
		return
	var fx_parent := _resolve_fx_parent()
	if fx_parent == null:
		return
	if _aim_reticle == null or not is_instance_valid(_aim_reticle):
		_aim_reticle = Node3D.new()
		_aim_reticle.name = "MeteorAimReticle"
		_aim_mat = StandardMaterial3D.new()
		_aim_mat.albedo_color = Color(0.28, 1.0, 0.52, 0.55)
		_aim_mat.emission_enabled = true
		_aim_mat.emission = Color(0.32, 1.0, 0.55)
		_aim_mat.emission_energy_multiplier = 2.8
		_aim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_aim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_aim_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

		# Outer bullseye ring (torus lying flat on ground)
		var outer := MeshInstance3D.new()
		var ot := TorusMesh.new()
		ot.outer_radius = 3.8
		ot.inner_radius = 3.45
		ot.rings = 28
		ot.ring_segments = 8
		ot.material = _aim_mat
		outer.mesh = ot
		_aim_reticle.add_child(outer)

		# Inner bullseye ring
		var inner := MeshInstance3D.new()
		var it := TorusMesh.new()
		it.outer_radius = 1.45
		it.inner_radius = 1.20
		it.rings = 24
		it.ring_segments = 8
		it.material = _aim_mat
		inner.mesh = it
		_aim_reticle.add_child(inner)

		# Crosshair bars
		for ang in [0.0, 90.0]:
			var bar := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(6.8, 0.03, 0.16)
			bm.material = _aim_mat
			bar.mesh = bm
			bar.rotation_degrees.y = float(ang)
			_aim_reticle.add_child(bar)

		# Subtle vertical sky-laser beacon so aim depth reads clearly at any distance
		var beacon := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.08
		cm.bottom_radius = 0.22
		cm.height = 12.0
		cm.radial_segments = 12
		cm.material = _aim_mat
		beacon.mesh = cm
		beacon.position = Vector3(0.0, 6.0, 0.0)
		_aim_reticle.add_child(beacon)

		fx_parent.add_child(_aim_reticle)
	_aim_reticle.visible = true
	var tgt := _cached_meteor_target
	if not _has_cached_meteor:
		# Pure math fallback until the next physics step runs the raycast —
		# never query direct_space_state from _process().
		var fwd_f := owner_node.global_transform.basis.z
		fwd_f.y = 0.0
		fwd_f = fwd_f.normalized() if fwd_f.length_squared() > 1e-4 else Vector3.BACK
		tgt = owner_node.global_position + fwd_f * METEOR_AIM_DEFAULT_DIST
		tgt.y = 0.02
	_aim_reticle.global_position = tgt + Vector3(0.0, 0.06, 0.0)
	if delta > 0.0 and not Settings.reduced_motion():
		_aim_reticle.rotate_y(2.1 * minf(delta, 0.05))
	if _aim_mat != null:
		var rdy := can_fire()
		var aim_key := "%s:%s" % [weapon_profile, str(rdy)]
		if aim_key != _last_aim_state:
			_last_aim_state = aim_key
			if weapon_profile == "bike":
				_aim_mat.albedo_color = Color(0.32, 0.88, 1.0, 0.58) if rdy else Color(0.28, 0.45, 0.65, 0.30)
				_aim_mat.emission = Color(0.45, 0.92, 1.0) if rdy else Color(0.30, 0.50, 0.72)
			elif weapon_profile == "aston":
				_aim_mat.albedo_color = Color(0.18, 0.88, 0.42, 0.58) if rdy else Color(0.75, 0.62, 0.16, 0.30)
				_aim_mat.emission = Color(0.95, 0.84, 0.24) if rdy else Color(0.68, 0.55, 0.14)
			elif weapon_profile == "evan":
				_aim_mat.albedo_color = Color(0.95, 0.08, 0.28, 0.60) if rdy else Color(0.42, 0.10, 0.16, 0.30)
				_aim_mat.emission = Color(1.0, 0.12, 0.32) if rdy else Color(0.60, 0.16, 0.20)
			else:
				_aim_mat.albedo_color = Color(0.28, 1.0, 0.52, 0.55) if rdy else Color(1.0, 0.42, 0.10, 0.30)
				_aim_mat.emission = Color(0.32, 1.0, 0.55) if rdy else Color(1.0, 0.38, 0.10)


func _resolve_fx_parent() -> Node3D:
	if get_tree() != null:
		var cs := get_tree().current_scene
		if cs is Node3D:
			return cs as Node3D
		elif owner_node != null and owner_node.get_parent() is Node3D:
			return owner_node.get_parent() as Node3D
		else:
			if _fx_holder == null or not is_instance_valid(_fx_holder):
				_fx_holder = Node3D.new()
				_fx_holder.name = "CannonFX"
				get_tree().root.add_child(_fx_holder)
			return _fx_holder
	return null


func fire() -> void:
	if not can_fire():
		return
	var active_weapon := current_weapon
	var cd := max_cooldown_for(active_weapon)
	_cooldowns[active_weapon] = cd
	_cooldown = cd
	_emit_reload_status(true)

	var meteor_target := compute_meteor_target() if active_weapon == "meteor" else Vector3.ZERO

	var res: Dictionary = await Match.issue_shot()
	if not is_inside_tree() or not is_instance_valid(owner_node) or not owner_node.visible:
		return
	var combat := get_parent()
	if combat != null and "alive" in combat and not bool(combat.get("alive")):
		return
	var practice := combat != null and "practice_mode" in combat and bool(combat.get("practice_mode"))
	if not practice and not Match.is_playing():
		return
	var token := str(res.get("token", ""))
	if token == "":
		push_warning("SideCannons: backend issued no shot token")
		_cooldowns[active_weapon] = 0.25
		if current_weapon == active_weapon:
			_cooldown = 0.25
		_emit_reload_status(true)
		return
	var fx_parent := _resolve_fx_parent()
	if fx_parent == null:
		return

	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		match active_weapon:
			"rocket":
				sfx.call("play", "fire", 1.5, 0.65)
			"meteor":
				sfx.call("play", "turbo", 1.5, 0.72)
			_:
				sfx.call("play", str(_profile["sfx"]))
	var cam := get_tree().get_first_node_in_group("camera_rig") if get_tree() != null else null
	if cam != null and cam.has_method("add_shake"):
		cam.call("add_shake", 0.22 if active_weapon != "primary" else 0.10)
	var pogo_rider := owner_node.get_node_or_null("Model/Rider") if owner_node != null else null
	if pogo_rider != null and pogo_rider.has_method("trigger_recoil"):
		pogo_rider.call("trigger_recoil", 1.35 if active_weapon != "primary" else 0.75)
	# EvanVisual lives on the GLB root itself; fire the one-shot riff flourish.
	var evan_model := owner_node.get_node_or_null("Model") if owner_node != null else null
	if evan_model != null and evan_model.has_method("trigger_recoil"):
		evan_model.call("trigger_recoil", 1.35 if active_weapon != "primary" else 0.75)

	var right_vec := owner_node.global_transform.basis.x.normalized()
	_ensure_muzzle_flashes()
	for i in range(_muzzles.size()):
		var muzzle: Node3D = _muzzles[i]
		if not is_instance_valid(muzzle):
			continue
		if i < _muzzle_flashes.size() and is_instance_valid(_muzzle_flashes[i]) and not Settings.reduced_motion() and Settings.quality_multiplier() > 0.0:
			_muzzle_flashes[i].position = owner_node.to_local(muzzle.global_position)
			_muzzle_flashes[i].restart()
			_muzzle_flashes[i].emitting = true
		if active_weapon == "primary" and not bool(_profile["banana"]):
			var side := -1.0 if i == 0 else 1.0
			VFX.casing(fx_parent, muzzle.global_position, right_vec * side + Vector3(0, 0.35, 0))

	if active_weapon == "rocket":
		# Rocket Launcher: NARDUS = massive cigar, BIG-BEN = cash bag, Quad =
		# finned rocket. All three share the lethal-direct / 90%-blast rules.
		var muzzle_pos := owner_node.global_position + Vector3(0.0, 0.68, 0.0) \
				+ owner_node.global_transform.basis.z.normalized() * 0.85
		if not _muzzles.is_empty() and is_instance_valid(_muzzles[0]):
			muzzle_pos = _muzzles[0].global_position
			if _muzzles.size() >= 2 and is_instance_valid(_muzzles[1]):
				muzzle_pos = (_muzzles[0].global_position + _muzzles[1].global_position) * 0.5
		var dir := owner_node.global_transform.basis.z.normalized()
		# Flat 90% health loss in the blast; direct hits are handled lethally in
		# RocketProjectile._detonate(). Match.damage() does not scale rockets.
		var rocket_dmg := ROCKET.BLAST_DAMAGE
		# EVAN throws his guitar instead: it damages everything it touches and
		# boomerangs back. Wire kind stays "rocket" so the existing multiplayer
		# protocol, token and anti-cheat validation are unchanged.
		var is_boomerang := weapon_profile == "evan"
		var rocket := Node3D.new()
		rocket.set_script(BOOMERANG if is_boomerang else ROCKET)
		fx_parent.add_child(rocket)
		var rocket_style := "boomerang" if is_boomerang \
				else ("cigar" if weapon_profile == "pogo" \
				else ("cash_bag" if weapon_profile == "aston" else "rocket"))
		var rocket_color := Color(0.95, 0.10, 0.46) if is_boomerang else Color(1.0, 0.38, 0.10)
		rocket.setup(owner_id, owner_node, muzzle_pos, dir, ROCKET_SPEED,
				rocket_dmg, token, rocket_color, ROCKET_BLAST_RADIUS, rocket_style)
		if not practice:
			Supabase.broadcast("shot", {
				"id": owner_id,
				"w": "rocket",
				"o": [muzzle_pos.x, muzzle_pos.y, muzzle_pos.z],
				"d": [dir.x, dir.y, dir.z],
				"token": token,
			})
		fired.emit(token)
		return

	if active_weapon == "meteor":
		# Meteor Shower: single meteor from the sky falling onto meteor_target over 2.0s
		var anchor_origin := owner_node.global_position + Vector3(0.0, 0.65, 0.0)
		if not _muzzles.is_empty() and is_instance_valid(_muzzles[0]):
			anchor_origin = _muzzles[0].global_position
		var offset := meteor_target - anchor_origin
		if offset.length() > 60.0:
			offset = offset.normalized() * 60.0
			meteor_target = anchor_origin + offset
		elif offset.length_squared() < 1e-4:
			offset = owner_node.global_transform.basis.z.normalized() * METEOR_AIM_DEFAULT_DIST
			meteor_target = anchor_origin + offset
		var meteor_dmg := Match.damage() * METEOR_DAMAGE_MULT
		# EVAN's encore special is the DEVIL HAND — same 2s telegraph / 7.5m
		# kill zone / wire kind, but it drags victims underground for a kill.
		var is_devil_hand := weapon_profile == "evan"
		var strike := Node3D.new()
		strike.set_script(DEVIL_HAND if is_devil_hand else METEOR)
		fx_parent.add_child(strike)
		var meteor_style := "devil_hand" if is_devil_hand \
				else ("lightning" if weapon_profile == "bike" \
				else ("cash_bag" if weapon_profile == "aston" else "meteor"))
		var strike_color := Color(0.85, 0.06, 0.20) if is_devil_hand else Color(1.0, 0.28, 0.06)
		strike.setup(owner_id, owner_node, meteor_target, meteor_dmg, token,
				strike_color, METEOR_FALL_TIME, METEOR_BLAST_RADIUS, meteor_style)
		# Keep 'o' at the bike muzzle (<= 5m from sender) and encode target offset in 'd' (<= 60m)
		# so ArenaNet._spawn_remote_shot's anti-cheat validation accepts and reconstructs it!
		if not practice:
			Supabase.broadcast("shot", {
				"id": owner_id,
				"w": "meteor",
				"o": [anchor_origin.x, anchor_origin.y, anchor_origin.z],
				"d": [offset.x, offset.y, offset.z],
				"token": token,
			})
		fired.emit(token)
		return

	# Primary weapon: Machine Gun (Quad) or Banana Cannon (Nardus)
	var spread := float(_profile["spread"])
	var speed := float(_profile["speed"])
	var proj_script: GDScript = BANANA if bool(_profile["banana"]) else PROJECTILE
	if weapon_profile == "evan":
		proj_script = SOUNDWAVE
	var dmg := Match.damage() * float(_profile["damage_mult"])
	for i in range(_muzzles.size()):
		var muzzle: Node3D = _muzzles[i]
		if not is_instance_valid(muzzle) or not is_instance_valid(owner_node) or not is_instance_valid(fx_parent):
			continue
		var forward := owner_node.global_transform.basis.z.normalized()
		var right := owner_node.global_transform.basis.x.normalized()
		var side := -1.0 if i == 0 else 1.0
		var dir := (forward + right * side * spread).normalized()
		# Evan's sound waves are short-lived and script-specific: never recycle
		# a pooled bolt whose script belongs to another vehicle profile.
		var proj: Node3D
		if weapon_profile == "evan":
			proj = Node3D.new()
			proj.set_script(SOUNDWAVE)
			fx_parent.add_child(proj)
		else:
			proj = _acquire_pooled_proj(proj_script, fx_parent)
		var barrel_tok := ("%s:b%d" % [token, i]) if token != "" else ""
		proj.setup(owner_id, owner_node, muzzle.global_position, dir,
				speed, dmg, barrel_tok, _color)
		if hit_callback.is_valid():
			proj.on_hit = hit_callback
		if not practice:
			Supabase.broadcast("shot", {
				"id": owner_id,
				"w": "primary",
				"o": [muzzle.global_position.x, muzzle.global_position.y, muzzle.global_position.z],
				"d": [dir.x, dir.y, dir.z],
				"token": barrel_tok,
			})
	fired.emit(token)


func _ensure_muzzle_flashes() -> void:
	if _muzzle_flashes.size() == _muzzles.size() and not _muzzle_flashes.is_empty():
		var all_valid := true
		for mf in _muzzle_flashes:
			if not is_instance_valid(mf):
				all_valid = false
				break
		if all_valid:
			return
	for mf in _muzzle_flashes:
		if is_instance_valid(mf):
			mf.queue_free()
	_muzzle_flashes.clear()
	if owner_node == null or not is_instance_valid(owner_node):
		return
	for muzzle in _muzzles:
		if not is_instance_valid(muzzle):
			_muzzle_flashes.append(null)
			continue
		var p := GPUParticles3D.new()
		p.name = "MuzzleFlashPool"
		p.amount = maxi(4, int(10 * Settings.quality_multiplier()))
		p.lifetime = 0.12
		p.one_shot = true
		p.emitting = false
		p.local_coords = true
		p.explosiveness = 0.95
		p.visibility_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3.0, 3.0, 3.0))
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0.0, 0.0, 1.0)
		pm.spread = 18.0
		pm.initial_velocity_min = 6.0
		pm.initial_velocity_max = 14.0
		pm.scale_min = 0.22
		pm.scale_max = 0.45
		pm.color_ramp = VFX._ramp([Color(1, 0.94, 0.65, 1.0), VFX.COL_AMBER, Color(VFX.COL_EMBER.r, VFX.COL_EMBER.g, VFX.COL_EMBER.b, 0.0)])
		p.process_material = pm
		p.draw_pass_1 = VFX._sprite_quad(true, "flare", 0.45)
		p.position = owner_node.to_local(muzzle.global_position)
		owner_node.add_child(p)
		_muzzle_flashes.append(p)


func _acquire_pooled_proj(proj_script: GDScript, fx_parent: Node3D) -> Node3D:
	if _proj_pool.size() < PROJ_POOL_SIZE:
		var p := Node3D.new()
		p.set_script(proj_script)
		p.set("pooled", true)
		fx_parent.add_child(p)
		_proj_pool.append(p)
		return p
	var idx := _proj_pool_idx
	for offset in range(PROJ_POOL_SIZE):
		var cand_idx := (_proj_pool_idx + offset) % PROJ_POOL_SIZE
		var cand := _proj_pool[cand_idx]
		if not is_instance_valid(cand) or not cand.is_physics_processing():
			idx = cand_idx
			break
	_proj_pool_idx = (idx + 1) % PROJ_POOL_SIZE
	var slot := _proj_pool[idx]
	if not is_instance_valid(slot) or slot.get_script() != proj_script:
		if is_instance_valid(slot):
			slot.queue_free()
		slot = Node3D.new()
		slot.set_script(proj_script)
		slot.set("pooled", true)
		fx_parent.add_child(slot)
		_proj_pool[idx] = slot
	elif slot.get_parent() != fx_parent:
		if slot.get_parent() != null:
			slot.get_parent().remove_child(slot)
		fx_parent.add_child(slot)
	return slot
