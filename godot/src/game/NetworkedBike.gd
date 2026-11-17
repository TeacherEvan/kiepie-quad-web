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

	var glb: PackedScene = load(MODEL)
	if glb != null:
		var model := glb.instantiate()
		model.name = "Model"
		add_child(model)
		# tint the body slightly so players are distinguishable at a glance
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			var mi := mesh as MeshInstance3D
			if mi.material is StandardMaterial3D:
				var m := (mi.material as StandardMaterial3D).duplicate()
				m.albedo_color = m.albedo_color.lerp(player_color, 0.28)
				mi.material = m

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


func apply_state(data: Dictionary) -> void:
	var p: Variant = data.get("p", null)
	if p is Array and (p as Array).size() >= 3:
		_target_pos = Vector3(float(p[0]), float(p[1]), float(p[2]))
	var r: Variant = data.get("r", null)
	if r is Array and (r as Array).size() >= 4:
		var q := Quaternion(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		_target_basis = Basis(q)
	if not _initialised:
		global_position = _target_pos
		global_transform.basis = _target_basis
		_initialised = true
	set_respawning(bool(data.get("d", false)))


func set_respawning(value: bool) -> void:
	if value == is_respawning:
		return
	is_respawning = value
	visible = not value
	if value:
		VFX.explosion(get_tree().current_scene, global_position, player_color, 1.1)
	else:
		VFX.shield_pulse(get_tree().current_scene, global_position, player_color)


func _process(delta: float) -> void:
	if not _initialised:
		return
	var t := clampf(delta * 14.0, 0.0, 1.0)
	global_position = global_position.lerp(_target_pos, t)
	var q0 := Quaternion(global_transform.basis)
	var q1 := Quaternion(_target_basis)
	global_transform.basis = Basis(q0.slerp(q1, t)).orthonormalized()
