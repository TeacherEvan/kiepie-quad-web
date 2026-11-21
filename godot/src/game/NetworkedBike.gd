extends StaticBody3D
## Visual/interpolated proxy for a remote player. Collision is a simple box so
## projectiles can raycast against it; no driving physics runs locally.

const VFX := preload("res://src/game/VfxFactory.gd")
const POGO_VISUAL := preload("res://src/game/PogoVisual.gd")

var player_id := ""
var display_name := ""
var player_color := Color(1.0, 0.5, 0.2)
var is_respawning := false
var turbo_active := false
var _assigned_vehicle: StringName = &""

var _target_pos := Vector3.ZERO
var _target_basis := Basis.IDENTITY
var _last_tick := -1
var _initialised := false
var _kill_lock_until := 0.0
var _nameplate: Label3D
var _ring: MeshInstance3D


func setup(id: String, name_text: String, color_hex: String) -> void:
	player_id = id
	display_name = name_text
	player_color = Color.html(color_hex) if color_hex.is_valid_html_color() else Color(1, 0.5, 0.2)
	add_to_group("bike")
	set("player_id", id)
	# Stay hidden until the first live state snapshot places us at the peer's real transform.
	visible = false

	_apply_roster_vehicle(true)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.95, 0.7, 2.1)
	col.shape = box
	col.position = Vector3(0.0, 0.6, 0.0)
	add_child(col)
	# Unplaced proxy stays intangible until its first live state snapshot places it.
	collision_layer = 0
	collision_mask = 0

	_nameplate = Label3D.new()
	_nameplate.name = "Nameplate"
	_nameplate.text = name_text
	_nameplate.font_size = 42
	_nameplate.outline_size = 12
	_nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nameplate.modulate = player_color
	_nameplate.position = Vector3(0.0, 2.05, 0.0)
	add_child(_nameplate)


func _apply_roster_vehicle(force: bool = false) -> void:
	var roster_keys: Array = []
	var pref := ""
	if typeof(Match) != TYPE_NIL and Match != null and "players" in Match:
		var mp: Variant = Match.get("players")
		if mp is Dictionary and not (mp as Dictionary).is_empty():
			roster_keys = (mp as Dictionary).keys()
			if (mp as Dictionary).has(player_id) and (mp as Dictionary)[player_id] is Dictionary:
				pref = str(((mp as Dictionary)[player_id] as Dictionary).get("vehicle", ""))
	var vehicle := VehicleRegistry.resolve_for_player(player_id, roster_keys, pref)
	if not force and vehicle == _assigned_vehicle:
		return
	_assigned_vehicle = vehicle
	var pogo := VehicleRegistry.is_pogo(vehicle)
	var model_path := VehicleRegistry.model_path(vehicle)
	var glb: PackedScene = load(model_path)
	if glb == null:
		return
	var old := get_node_or_null("Model")
	if old != null:
		remove_child(old)
		old.queue_free()
	var model := glb.instantiate()
	model.name = "Model"
	if pogo:
		var rider := model.get_node_or_null("Rider")
		if rider != null:
			rider.set_script(POGO_VISUAL)
	add_child(model)
	# tint the body slightly so players are distinguishable at a glance
	var tinted_cache: Dictionary = {}
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.get_active_material(s)
			if mat is StandardMaterial3D:
				if str((mat as Material).resource_name) == "BigBenPlate":
					continue
				var tinted: StandardMaterial3D = tinted_cache.get(mat)
				if tinted == null:
					tinted = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					tinted.albedo_color = tinted.albedo_color.lerp(player_color, 0.28)
					tinted_cache[mat] = tinted
				mi.set_surface_override_material(s, tinted)


func update_identity(name_text: String, color_hex: String) -> void:
	if name_text != "" and name_text != display_name:
		display_name = name_text
		if _nameplate != null:
			_nameplate.text = name_text
	var color_changed := false
	if color_hex.is_valid_html_color():
		var col := Color.html(color_hex)
		if not col.is_equal_approx(player_color):
			player_color = col
			color_changed = true
			if _nameplate != null:
				_nameplate.modulate = player_color
	var prev_vehicle := _assigned_vehicle
	# Re-evaluate roster-aware Nardus promotion when peers join or leave, or force re-tint on color change.
	_apply_roster_vehicle(color_changed)


func apply_state(data: Dictionary) -> void:
	# Monotonic relay sequence: out-of-order or replayed snapshots would otherwise
	# snap a proxy backwards between 80–150 ms jitter windows. Peers without the
	# "n" field (older builds) are accepted unconditionally.
	var n := int(data.get("n", -1))
	if n >= 0:
		if n <= _last_tick:
			return
		_last_tick = n
	var p: Variant = data.get("p", null)
	if p is Array and (p as Array).size() >= 3:
		var cand := Vector3(float(p[0]), float(p[1]), float(p[2]))
		if is_finite(cand.x) and is_finite(cand.y) and is_finite(cand.z):
			_target_pos = cand
	var r: Variant = data.get("r", null)
	if r is Array and (r as Array).size() >= 4:
		var q := Quaternion(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		if is_finite(q.x) and is_finite(q.y) and is_finite(q.z) and is_finite(q.w) and q.length_squared() > 1e-8:
			_target_basis = Basis(q.normalized()).orthonormalized()
	var dead_now := bool(data.get("d", false))
	turbo_active = bool(data.get("t", false)) and not dead_now
	if not _initialised:
		is_respawning = dead_now
		visible = not dead_now
		collision_layer = 0 if dead_now else 1
		global_position = _target_pos
		global_transform.basis = _target_basis
		_initialised = true
		return
	if is_respawning and not dead_now:
		if (Time.get_ticks_msec() / 1000.0) < _kill_lock_until:
			return  # ignore stale pre-death in-flight packet
		# Snap immediately on respawn instead of lerping across the arena (and
		# place the respawn shield pulse at the new spawn point, not the death spot).
		global_position = _target_pos
		global_transform.basis = _target_basis
	set_respawning(dead_now)


func mark_killed(lock_sec: float = 0.55) -> void:
	_kill_lock_until = maxf(_kill_lock_until, Time.get_ticks_msec() / 1000.0 + lock_sec)
	set_respawning(true)


func set_respawning(value: bool) -> void:
	if value == is_respawning:
		return
	is_respawning = value
	visible = not value
	# A hidden respawning proxy must not eat projectiles mid-flight.
	set_deferred("collision_layer", 0 if value else 1)
	var fx_parent: Node3D = null
	if get_tree() != null and get_tree().current_scene is Node3D:
		fx_parent = get_tree().current_scene as Node3D
	elif get_parent() is Node3D:
		fx_parent = get_parent() as Node3D
	if fx_parent == null:
		return
	if value:
		var pogo := VehicleRegistry.is_pogo(_assigned_vehicle)
		VFX.dramatic_death_explosion(fx_parent, global_position, global_transform.basis,
				player_color, pogo, VehicleRegistry.profile(_assigned_vehicle))
	else:
		VFX.shield_pulse(fx_parent, global_position, player_color)


func _process(delta: float) -> void:
	if not _initialised:
		return
	var t := 1.0 - exp(-14.0 * minf(delta, 0.05))
	global_position = global_position.lerp(_target_pos, t)
	var q0 := Quaternion(global_transform.basis.orthonormalized())
	var q1 := Quaternion(_target_basis.orthonormalized())
	global_transform.basis = Basis(q0.slerp(q1, t).normalized()).orthonormalized()
