extends StaticBody3D
## Explosive fuel drum placed in clusters by tools/build_arena.gd. Bullets
## raycast against this StaticBody3D; whoever handles the projectile hit calls
## ignite(attacker_id, token). Ignition damages nearby bikes and chains to
## neighbouring drums in group "hazard" after a short delay. The _ignited
## guard makes the chain terminate even when drums are adjacent.

const VFX := preload("res://src/game/VfxFactory.gd")
const AOE := preload("res://src/game/CombatAoe.gd")

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
	if sfx != null:
		if sfx.has_method("play_3d"):
			sfx.call("play_3d", "explosion", pos)
		elif sfx.has_method("play"):
			sfx.call("play", "explosion")

	var tree := get_tree()
	if tree != null:
		AOE.apply_blast(tree, _fx_parent(), pos, blast_radius, blast_damage,
				1.0, 1.0, attacker_id, self, token, false, 12.0, false, false)

		# Chain to other drums inside the blast radius, slightly staggered.
		for other in tree.get_nodes_in_group("hazard"):
			if other == self or not is_instance_valid(other) or not (other is Node3D):
				continue
			var o := other as Node3D
			if bool(o.get("_ignited")):
				continue
			if o.global_position.distance_to(pos) > blast_radius:
				continue
			if not o.has_method("ignite"):
				continue
			var wo: WeakRef = weakref(o)
			var timer := tree.create_timer(0.18)
			timer.timeout.connect(func() -> void:
				var target := wo.get_ref() as Node
				if target != null and target.has_method("ignite"):
					var chain_tok := "%s:c%d" % [token, target.get_instance_id()] if token != "" else ""
					target.call("ignite", attacker_id, chain_tok)
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
