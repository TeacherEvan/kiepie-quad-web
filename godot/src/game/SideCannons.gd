extends Node3D
## Twin side cannons. One FIRE input fires both barrels forward with a slight
## outward spread. Heat prevents infinite spam; the shot token is minted locally
## by the Talo facade. Scoring is host-authoritative client logic — no server-side validation.

signal fired(token: String)
signal heat_changed(value: float, locked: bool)

const PROJECTILE := preload("res://src/game/Projectile.gd")
const VFX := preload("res://src/game/VfxFactory.gd")
# Keep in sync with the remote-shot speed in ArenaNet._spawn_remote_shot.
const SHOT_SPEED := 52.0
const SHOT_SPREAD := 0.055
const HEAT_PER_SHOT := 0.24
const HEAT_DECAY := 0.42
const OVERHEAT_RESUME := 0.35

var owner_node: Node3D
var owner_id := ""
var hit_callback: Callable
var heat := 0.0
var overheated := false

var _cooldown := 0.0
var _rapid := false
var _muzzles: Array[Node3D] = []
var _color := Color(1.0, 0.55, 0.15)
var _fx_holder: Node3D = null


func setup(p_owner: Node3D, p_owner_id: String, p_hit_callback: Callable, p_color: Color) -> void:
	owner_node = p_owner
	owner_id = p_owner_id
	hit_callback = p_hit_callback
	_color = p_color
	# purge stale fallback mounts from an earlier setup on the same owner
	for m in _muzzles:
		if is_instance_valid(m) and m.name == "MuzzleFallback":
			m.queue_free()
	_muzzles.clear()
	# Prefer the authored muzzle empties, falling back to the bore meshes which
	# also sit exactly at each barrel tip (and are the authoritative anchors).
	for spec in [["Muzzle_L", "Cannon_Bore_L", -0.62], ["Muzzle_R", "Cannon_Bore_R", 0.62]]:
		var found: Node3D = null
		for node_name in [spec[0], spec[1]]:
			found = _find_named(p_owner, node_name)
			if found != null:
				break
		if found != null:
			_muzzles.append(found)
		else:
			# per-side fallback: one missing muzzle must not triple the mounts
			var anchor := Node3D.new()
			anchor.name = "MuzzleFallback"
			anchor.position = Vector3(spec[2], 0.62, 0.78)
			p_owner.add_child(anchor)
			_muzzles.append(anchor)


func _find_named(root: Node, wanted: String) -> Node3D:
	if root.name == wanted and root is Node3D:
		return root as Node3D
	for c in root.get_children():
		var found := _find_named(c, wanted)
		if found != null:
			return found
	return null


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	var before := heat
	heat = maxf(0.0, heat - HEAT_DECAY * delta)
	if overheated and heat <= OVERHEAT_RESUME:
		overheated = false
		heat_changed.emit(heat, overheated)
	elif absf(before - heat) > 0.01:
		heat_changed.emit(heat, overheated)


func set_rapid(value: bool) -> void:
	_rapid = value


func can_fire() -> bool:
	return owner_node != null and not overheated and _cooldown <= 0.0


func fire() -> void:
	if not can_fire():
		return
	_cooldown = 0.09 if _rapid else 0.20
	var added := HEAT_PER_SHOT * (0.55 if _rapid else 1.0)
	heat = minf(1.0, heat + added)
	if heat >= 1.0:
		overheated = true
	heat_changed.emit(heat, overheated)

	# muzzle flash is instant; the token arrives a fraction of a second later
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", "fire")
	var cam := get_tree().get_first_node_in_group("camera_rig") if get_tree() != null else null
	if cam != null and cam.has_method("add_shake"):
		cam.call("add_shake", 0.10)
	var fx_parent: Node3D = null
	if get_tree() != null:
		var cs := get_tree().current_scene
		if cs is Node3D:
			fx_parent = cs as Node3D
		elif owner_node.get_parent() is Node3D:
			fx_parent = owner_node.get_parent() as Node3D
		else:
			# headless/tool contexts have no current scene and a Window root:
			# mount effects on a dedicated holder instead of a non-Node3D parent
			if _fx_holder == null or not is_instance_valid(_fx_holder):
				_fx_holder = Node3D.new()
				_fx_holder.name = "CannonFX"
				get_tree().root.add_child(_fx_holder)
			fx_parent = _fx_holder
	var right_vec := owner_node.global_transform.basis.x.normalized()
	for i in range(_muzzles.size()):
		var muzzle: Node3D = _muzzles[i]
		VFX.muzzle_flash(fx_parent, muzzle.global_position,
				owner_node.global_transform.basis.z, _color)
		# eject a brass casing out of the breech, opposite the barrel's side
		var side := -1.0 if i == 0 else 1.0
		VFX.casing(fx_parent, muzzle.global_position, right_vec * side + Vector3(0, 0.35, 0))
	if heat >= 1.0:
		# overheated: both barrels vent steam as the lockout engages
		for muzzle in _muzzles:
			VFX.steam_vent(fx_parent, muzzle.global_position)

	var res: Dictionary = await Match.issue_shot()
	var token := str(res.get("token", ""))
	if token == "":
		# dry-fire: refund the heat this shot spent; no resources burned for nothing
		heat = maxf(0.0, heat - added)
		if heat < 1.0:
			overheated = false
		heat_changed.emit(heat, overheated)
		push_warning("SideCannons: backend issued no shot token — heat refunded")
		return
	for i in range(_muzzles.size()):
		var muzzle: Node3D = _muzzles[i]
		if not is_instance_valid(muzzle) or not is_instance_valid(owner_node) or not is_instance_valid(fx_parent):
			# scene change / bike teardown across the issue_shot round-trip
			continue
		var forward := owner_node.global_transform.basis.z.normalized()
		var right := owner_node.global_transform.basis.x.normalized()
		var side := -1.0 if i == 0 else 1.0
		var dir := (forward + right * side * SHOT_SPREAD).normalized()
		var proj := Node3D.new()
		proj.set_script(PROJECTILE)
		fx_parent.add_child(proj)
		proj.setup(owner_id, owner_node, muzzle.global_position, dir,
				SHOT_SPEED, Match.damage(), token, _color)
		if hit_callback.is_valid():
			proj.on_hit = hit_callback
		Supabase.broadcast("shot", {
			"id": owner_id,
			"o": [muzzle.global_position.x, muzzle.global_position.y, muzzle.global_position.z],
			"d": [dir.x, dir.y, dir.z],
			"token": token,
		})
	fired.emit(token)
