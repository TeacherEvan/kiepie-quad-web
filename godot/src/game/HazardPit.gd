extends Area3D
## Glowing molten hazard pit on the Death Race track. Riders who miss a gap
## ramp and drop into the pit take rapid thermal damage + fiery splash VFX,
## wrecking and respawning back at their last cleared checkpoint.

const VFX := preload("res://src/game/VfxFactory.gd")

@export var pit_size := Vector3(10.0, 1.4, 8.0)
@export var tick_damage := 55.0
@export var tick_interval := 0.32

var _occupants: Array[Node3D] = []
var _tick_accum := 0.0


func _ready() -> void:
	add_to_group("hazard_pit", true)
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_visual()


func _build_visual() -> void:
	if get_node_or_null("Collider") == null:
		var col := CollisionShape3D.new()
		col.name = "Collider"
		var shape := BoxShape3D.new()
		shape.size = pit_size
		col.shape = shape
		col.position = Vector3(0.0, pit_size.y * 0.4, 0.0)
		add_child(col)

	if get_node_or_null("LavaSurface") == null:
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "LavaSurface"
		var bm := BoxMesh.new()
		bm.size = Vector3(pit_size.x, 0.12, pit_size.z)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.95, 0.22, 0.04, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.34, 0.05, 1.0)
		mat.emission_energy_multiplier = 2.8
		mat.roughness = 0.35
		bm.material = mat
		mesh_inst.mesh = bm
		mesh_inst.position = Vector3(0.0, 0.05, 0.0)
		add_child(mesh_inst)


func _on_body_entered(body: Node) -> void:
	if body is Node3D and body.is_in_group("bike"):
		var b := body as Node3D
		if not _occupants.has(b):
			_occupants.append(b)
		_damage_bike(b)


func _on_body_exited(body: Node) -> void:
	if body is Node3D and _occupants.has(body as Node3D):
		_occupants.erase(body as Node3D)


func _physics_process(delta: float) -> void:
	if _occupants.is_empty():
		_tick_accum = 0.0
		return
	_tick_accum += delta
	if _tick_accum < tick_interval:
		return
	_tick_accum = 0.0
	for i in range(_occupants.size() - 1, -1, -1):
		var b := _occupants[i]
		if not is_instance_valid(b) or not b.visible:
			_occupants.remove_at(i)
			continue
		_damage_bike(b)


func _damage_bike(bike_node: Node3D) -> void:
	var combat := bike_node.get_node_or_null("CombatController")
	if combat != null and combat.has_method("take_damage"):
		# Bypass shield/invuln if they fell deep into a pit
		combat.set("_invuln_until", 0.0)
		combat.call("take_damage", tick_damage, "hazard-pit", bike_node.global_position, "")
	var fx := get_tree().current_scene as Node3D if (get_tree() != null and get_tree().current_scene is Node3D) else get_parent() as Node3D
	VFX.explosion(fx, bike_node.global_position, Color(1.0, 0.32, 0.05), 0.95)
