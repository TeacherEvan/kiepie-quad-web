extends StaticBody3D
## Visual/interpolated proxy for a remote player. Collision is a simple box so
## projectiles can raycast against it; no driving physics runs locally.

const MODEL := "res://assets/Kiepie_Bike.glb"
const VFX := preload("res://src/game/VfxFactory.gd")

var player_id := ""
var display_name := ""
var player_color := Color(1.0, 0.5, 0.2)
var is_respawning := false

var _target_pos := Vector3.ZERO
var _target_basis := Basis.IDENTITY
var _initialised := false
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

	var glb: PackedScene = load(MODEL)
	if glb != null:
		var model := glb.instantiate()
		model.name = "Model"
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
					var tinted: StandardMaterial3D = tinted_cache.get(mat)
					if tinted == null:
						tinted = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
						tinted.albedo_color = tinted.albedo_color.lerp(player_color, 0.28)
						tinted_cache[mat] = tinted
					mi.set_surface_override_material(s, tinted)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.95, 0.7, 2.1)
	col.shape = box
	col.position = Vector3(0.0, 0.6, 0.0)
	add_child(col)
	collision_layer = 1
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


func update_identity(name_text: String, color_hex: String) -> void:
	if name_text != "" and name_text != display_name:
		display_name = name_text
		if _nameplate != null:
			_nameplate.text = name_text
	if color_hex.is_valid_html_color():
		var col := Color.html(color_hex)
		if not col.is_equal_approx(player_color):
			player_color = col
			if _nameplate != null:
				_nameplate.modulate = player_color


func apply_state(data: Dictionary) -> void:
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
	if not _initialised:
		is_respawning = dead_now
		visible = not dead_now
		global_position = _target_pos
		global_transform.basis = _target_basis
		_initialised = true
		return
	if is_respawning and not dead_now:
		# Snap immediately on respawn instead of lerping across the arena (and
		# place the respawn shield pulse at the new spawn point, not the death spot).
		global_position = _target_pos
		global_transform.basis = _target_basis
	set_respawning(dead_now)


func set_respawning(value: bool) -> void:
	if value == is_respawning:
		return
	is_respawning = value
	visible = not value
	var fx_parent: Node3D = null
	if get_tree() != null and get_tree().current_scene is Node3D:
		fx_parent = get_tree().current_scene as Node3D
	elif get_parent() is Node3D:
		fx_parent = get_parent() as Node3D
	if fx_parent == null:
		return
	if value:
		VFX.explosion(fx_parent, global_position, player_color, 1.1)
	else:
		VFX.shield_pulse(fx_parent, global_position, player_color)


func _process(delta: float) -> void:
	if not _initialised:
		return
	var t := clampf(delta * 14.0, 0.0, 1.0)
	global_position = global_position.lerp(_target_pos, t)
	var q0 := Quaternion(global_transform.basis.orthonormalized())
	var q1 := Quaternion(_target_basis.orthonormalized())
	global_transform.basis = Basis(q0.slerp(q1, t).normalized()).orthonormalized()
