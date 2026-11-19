extends StaticBody3D
## Explosive fuel drum placed in clusters by tools/build_arena.gd. Bullets
## raycast against this StaticBody3D; whoever handles the projectile hit calls
## ignite(attacker_id, token). Ignition damages nearby bikes and chains to
## neighbouring drums in group "hazard" after a short delay. The _ignited
## guard makes the chain terminate even when drums are adjacent.

const VFX := preload("res://src/game/VfxFactory.gd")

@export var blast_radius := 4.6
@export var blast_damage := 55.0
@export var respawn_delay := 0.0

var _ignited := false


func _ready() -> void:
	add_to_group("hazard", true)  # persistent, survives scene packing
	_build_body()


func _build_body() -> void:
	# Cylinder collider is what projectiles raycast against.
	var col := CollisionShape3D.new()
	col.name = "Collider"
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.32
	cyl.height = 0.9
	col.shape = cyl
	add_child(col)

	# Red/orange emissive body.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.18, 0.06, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.00, 0.32, 0.05, 1.0)
	mat.emission_energy_multiplier = 1.4
	mat.roughness = 0.55
	var drum := CylinderMesh.new()
	drum.top_radius = 0.32
	drum.bottom_radius = 0.32
	drum.height = 0.9
	drum.radial_segments = 16
	drum.rings = 3
	drum.material = mat
	var inst := MeshInstance3D.new()
	inst.name = "Drum"
	inst.mesh = drum
	add_child(inst)

	# Dark banding near the top and bottom.
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = Color(0.16, 0.16, 0.18, 1.0)
	band_mat.roughness = 0.7
	for y in [0.28, -0.28]:
		var band := CylinderMesh.new()
		band.top_radius = 0.335
		band.bottom_radius = 0.335
		band.height = 0.10
		band.radial_segments = 16
		band.material = band_mat
		var band_inst := MeshInstance3D.new()
		band_inst.name = "Band"
		band_inst.mesh = band
		band_inst.position.y = float(y)
		add_child(band_inst)


func ignite(attacker_id: String, token: String = "") -> void:
	if _ignited:
		return
	_ignited = true

	var pos := global_position
	VFX.explosion(_fx_parent(), pos, Color(1.0, 0.35, 0.06, 1.0), 1.2)
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", "explosion")

	var tree := get_tree()
	if tree != null:
		# Damage every bike inside the blast radius.
		for bike in tree.get_nodes_in_group("bike"):
			if not is_instance_valid(bike) or not (bike is Node3D):
				continue
			var b := bike as Node3D
			if b.global_position.distance_to(pos) > blast_radius:
				continue
			# take_damage lives on the CombatController child, not on the bike body.
			var controller: Node = b.get_node_or_null("CombatController")
			if controller == null:
				for child in b.get_children():
					if child.has_method("take_damage"):
						controller = child
						break
			if controller != null and controller.has_method("take_damage"):
				controller.call("take_damage", blast_damage, attacker_id, b.global_position, token)
			else:
				# Remote proxy: no local CombatController — pop an immediate gold
				# number for the attacker instead of nothing.
				var target_id := str(b.get("player_id")) if "player_id" in b else ""
				var sb := tree.root.get_node_or_null("Supabase") if tree != null else null
				var local_uid := str(sb.get("user_id")) if sb != null and "user_id" in sb else ""
				if attacker_id != "" and attacker_id == local_uid and target_id != "" and target_id != local_uid:
					VFX.damage_number(_fx_parent(), b.global_position + Vector3(0.0, 0.55, 0.0),
							float(blast_damage), Color(1.0, 0.85, 0.22))
					_note_local_damage_shown(target_id)

		# Chain to other drums inside the blast radius, slightly staggered.
		for other in tree.get_nodes_in_group("hazard"):
			if other == self or not is_instance_valid(other) or not (other is Node3D):
				continue
			var o := other as Node3D
			if o.global_position.distance_to(pos) > blast_radius:
				continue
			if not o.has_method("ignite"):
				continue
			var wo: WeakRef = weakref(o)
			var timer := tree.create_timer(0.18)
			timer.timeout.connect(func() -> void:
				var target := wo.get_ref() as Node
				if target != null and target.has_method("ignite"):
					target.call("ignite", attacker_id, token)
			)

	if respawn_delay <= 0.0 or tree == null:
		queue_free()
		return

	visible = false
	var col := get_node_or_null("Collider") as CollisionShape3D
	if col != null:
		col.set_deferred("disabled", true)
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = respawn_delay
	t.timeout.connect(_on_respawn_timer.bind(t))
	add_child(t)
	t.start()


func _on_respawn_timer(t: Timer) -> void:
	if is_instance_valid(t):
		t.queue_free()
	if not is_inside_tree():
		return
	_ignited = false
	visible = true
	var c := get_node_or_null("Collider") as CollisionShape3D
	if c != null:
		c.set_deferred("disabled", false)
	VFX.shield_pulse(_fx_parent(), global_position, Color(1.0, 0.45, 0.12, 1.0))


func _arena_net() -> Node:
	var tree := get_tree()
	if tree == null or not (tree.current_scene is Node):
		return null
	return tree.current_scene.get_node_or_null("ArenaNet")


func _note_local_damage_shown(target_id: String) -> void:
	var net := _arena_net()
	if net != null and net.has_method("note_local_damage_shown"):
		net.call("note_local_damage_shown", target_id)


func _fx_parent() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene is Node3D:
		return scene as Node3D
	var parent := get_parent()
	if parent is Node3D:
		return parent as Node3D
	return null
