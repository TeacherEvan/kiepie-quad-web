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
static var _lava_tex: ImageTexture = null


static func _get_lava_tex() -> ImageTexture:
	if _lava_tex == null:
		var noise := FastNoiseLite.new()
		noise.seed = 4242
		noise.frequency = 0.09
		noise.fractal_octaves = 3
		var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
		for y in range(64):
			for x in range(64):
				var n := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
				var col: Color
				if n < 0.42:
					# Dark cooled basalt crust island
					col = Color(0.14, 0.08, 0.06).lerp(Color(0.32, 0.11, 0.05), n / 0.42)
				elif n < 0.72:
					# Molten crimson-orange magma vein
					col = Color(0.85, 0.22, 0.04).lerp(Color(1.0, 0.54, 0.08), (n - 0.42) / 0.30)
				else:
					# White-hot fissure core
					col = Color(1.0, 0.78, 0.22)
				img.set_pixel(x, y, col)
		_lava_tex = ImageTexture.create_from_image(img)
	return _lava_tex


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
		var tex := _get_lava_tex()
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "LavaSurface"
		var bm := BoxMesh.new()
		bm.size = Vector3(pit_size.x - 0.5, 0.08, pit_size.z - 0.5)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.albedo_color = Color(0.95, 0.85, 0.78)
		mat.emission_enabled = true
		mat.emission_texture = tex
		mat.emission = Color(1.0, 0.32, 0.04)
		mat.emission_energy_multiplier = 0.62
		mat.roughness = 0.65
		mat.uv1_scale = Vector3(2.5, 2.5, 1.0)
		bm.material = mat
		mesh_inst.mesh = bm
		mesh_inst.position = Vector3(0.0, 0.04, 0.0)
		add_child(mesh_inst)

		# Industrial dark-steel containment curb around the lava vat
		var rim_mat := StandardMaterial3D.new()
		rim_mat.albedo_color = Color(0.15, 0.16, 0.19)
		rim_mat.metallic = 0.65
		rim_mat.roughness = 0.42
		var rim_specs := [
			[Vector3(0.0, 0.11, -pit_size.z * 0.5), Vector3(pit_size.x + 0.3, 0.22, 0.35)],
			[Vector3(0.0, 0.11, pit_size.z * 0.5), Vector3(pit_size.x + 0.3, 0.22, 0.35)],
			[Vector3(-pit_size.x * 0.5, 0.11, 0.0), Vector3(0.35, 0.22, pit_size.z)],
			[Vector3(pit_size.x * 0.5, 0.11, 0.0), Vector3(0.35, 0.22, pit_size.z)],
		]
		for rs in rim_specs:
			var rmi := MeshInstance3D.new()
			var rbm := BoxMesh.new()
			rbm.size = rs[1]
			rbm.material = rim_mat
			rmi.mesh = rbm
			rmi.position = rs[0]
			add_child(rmi)


func _on_body_entered(body: Node) -> void:
	if body is Node3D and body.is_in_group("bike"):
		var b := body as Node3D
		var combat := b.get_node_or_null("CombatController")
		if combat == null or not combat.has_method("take_damage"):
			return
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
	if combat == null or not combat.has_method("take_damage"):
		return
	if "alive" in combat and not bool(combat.get("alive")):
		return
	combat.call("take_damage", tick_damage, "hazard-pit", bike_node.global_position, "", true)
	if "alive" in combat and not bool(combat.get("alive")):
		return
	var fx := get_tree().current_scene as Node3D if (get_tree() != null and get_tree().current_scene is Node3D) else get_parent() as Node3D
	VFX.explosion(fx, bike_node.global_position, Color(1.0, 0.32, 0.05), 0.95)
