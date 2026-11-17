extends StaticBody3D
## A cheap, satisfying destructible building for the test track.
## Solid box shell; when the quad slams into it hard enough it bursts into
## physics debris (boxes) plus a dust puff, and reports via `smashed`.

signal smashed(building_name: String)

@export var hit_speed := 3.2           ## minimum bike speed (m/s) to smash
@export var debris_pieces := 14
@export var building_name := "Building"

var _intact := true

func _ready() -> void:
	add_to_group("destructible")
	# StaticBody3D has no signals, so impact detection is done with a child Area3D
	# trigger that wraps the building volume. The StaticBody3D itself stays solid
	# so intact buildings still block the bike.
	var box_size := Vector3(1.0, 1.0, 1.0)
	var box_pos := Vector3(0.0, 1.0, 0.0)
	for child in get_children():
		if child is CollisionShape3D:
			var shape := (child as CollisionShape3D).shape
			if shape is BoxShape3D:
				box_size = (shape as BoxShape3D).size
				box_pos = (child as CollisionShape3D).position
				break
	var area := Area3D.new()
	area.name = "SmashTrigger"
	area.monitoring = true
	area.monitorable = false
	area.collision_layer = 0
	area.collision_mask = 1 # bike is on layer 1
	var trigger_shape := CollisionShape3D.new()
	trigger_shape.name = "SmashTriggerShape"
	var box := BoxShape3D.new()
	box.size = box_size + Vector3(0.35, 0.6, 0.35)
	trigger_shape.shape = box
	trigger_shape.position = box_pos
	area.add_child(trigger_shape)
	area.body_entered.connect(_on_body_entered)
	add_child(area)

func _on_body_entered(body: Node) -> void:
	if not _intact:
		return
	if not body.is_in_group("bike"):
		return
	var speed := 0.0
	if body is VehicleBody3D:
		speed = (body as VehicleBody3D).linear_velocity.length()
	elif body is RigidBody3D:
		speed = (body as RigidBody3D).linear_velocity.length()
	if speed >= hit_speed:
		smash()

func smash() -> void:
	_intact = false
	# report the smash first, so the HUD counts it even if debris code fails
	var hud := get_tree().get_first_node_in_group("hud") if get_tree() != null else null
	if hud == null and get_parent() != null:
		hud = get_parent().get_node_or_null("HUD")
	if hud != null and hud.has_method("register_smash"):
		hud.register_smash()
	var origin := global_position

	# hide the intact shell and disable its collider
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = false
		elif child is CollisionShape3D:
			# smash() can run inside a physics flush; defer the shape change
			(child as CollisionShape3D).set_deferred("disabled", true)
		elif child is Area3D and child.name == "SmashTrigger":
			# stop the impact trigger firing after the building has smashed
			# (smash() can run inside a physics in/out signal; defer the change)
			(child as Area3D).set_deferred("monitoring", false)

	# spawn debris boxes
	var parent := get_parent()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(building_name) + int(abs(origin.x * 1000.0)) + int(abs(origin.z * 977.0))
	for i in range(debris_pieces):
		var size := Vector3(rng.randf_range(0.28, 0.95), rng.randf_range(0.22, 0.80),
				rng.randf_range(0.28, 0.95))
		var chunk := RigidBody3D.new()
		chunk.mass = rng.randf_range(18.0, 55.0)
		chunk.collision_layer = 1
		chunk.collision_mask = 1
		chunk.continuous_cd = true
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		col.shape = box
		chunk.add_child(col)
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		var mat := StandardMaterial3D.new()
		var shade := rng.randf_range(0.55, 1.0)
		mat.albedo_color = Color(0.46 * shade, 0.36 * shade, 0.30 * shade, 1.0)
		mat.roughness = 0.9
		bm.material = mat
		mesh.mesh = bm
		chunk.add_child(mesh)
		parent.add_child(chunk)
		# scatter within the building volume (chunk must be in the tree first)
		chunk.global_position = origin + Vector3(
			rng.randf_range(-1.6, 1.6), rng.randf_range(0.3, 2.6), rng.randf_range(-1.6, 1.6))
		# burst outward, slightly up
		var outward := (chunk.global_position - origin)
		outward.y = 0.0
		if outward.length() < 0.1:
			outward = Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
		outward = outward.normalized()
		chunk.linear_velocity = (outward * rng.randf_range(2.5, 7.0)
				+ Vector3(0.0, rng.randf_range(2.2, 5.2), 0.0))
		chunk.angular_velocity = Vector3(rng.randf_range(-6.0, 6.0),
				rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
		# fade debris away after a while to keep the pad tidy
		var fade_tree := Engine.get_main_loop() as SceneTree
		if fade_tree != null:
			var chunk_capture: RigidBody3D = chunk
			fade_tree.create_timer(9.0).timeout.connect(func() -> void:
				if is_instance_valid(chunk_capture) and chunk_capture.is_inside_tree():
					chunk_capture.queue_free())

	# dust puff
	var puff := GPUParticles3D.new()
	puff.name = "DustPuff"
	puff.amount = 70
	puff.lifetime = 1.15
	puff.one_shot = true
	puff.explosiveness = 0.9
	puff.local_coords = false
	puff.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 7, 8))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 78.0
	pm.gravity = Vector3(0.0, -2.4, 0.0)
	pm.initial_velocity_min = 2.2
	pm.initial_velocity_max = 5.4
	pm.scale_min = 0.9
	pm.scale_max = 2.4
	var grad := Gradient.new()
	grad.set_color(0, Color(0.72, 0.66, 0.58, 0.95))
	grad.set_offset(0, 0.0)
	grad.set_color(1, Color(0.55, 0.50, 0.44, 0.0))
	grad.set_offset(1, 1.0)
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp
	puff.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.30
	sm.height = 0.60
	sm.radial_segments = 7
	sm.rings = 4
	var mat2 := StandardMaterial3D.new()
	mat2.albedo_color = Color(0.68, 0.62, 0.54, 0.9)
	mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = mat2
	puff.draw_pass_1 = sm
	puff.position = Vector3(0.0, 1.2, 0.0)
	add_child(puff)
	puff.emitting = true
	puff.finished.connect(puff.queue_free)

	emit_signal("smashed", building_name)
