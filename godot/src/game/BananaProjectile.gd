extends Node3D
## NARDUS's favorite ammunition: little flying bananas. Same swept-ray rules
## as Projectile.gd so fast fruit cannot tunnel through bikes or scenery.

signal hit(target: Node, point: Vector3)

var owner_id := ""
var owner_node: Node
var velocity := Vector3.ZERO
var damage := 60.0
var token := ""
var hit_color := Color(1.0, 0.9, 0.25)
var on_hit: Callable

var _age := 0.0
var _life := 2.2
var _inert := true  # setup() re-arms; a never-configured fruit dies instantly
var _tracer: Node3D
var _ray_query: PhysicsRayQueryParameters3D

static var _banana_mesh: ArrayMesh = null
static var _tip_mesh: SphereMesh = null
static var _trail_puff_mesh: SphereMesh = null
static var _trail_ramp: GradientTexture1D = null


static func _quad_bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var a := p0.lerp(p1, t)
	var b := p1.lerp(p2, t)
	return a.lerp(b, t)


static func _build_banana_mesh() -> ArrayMesh:
	# A crescent tube, sampled by hand (QuadraticBezierCurve3/TubeMesh are
	# Godot 4.4+ — this project pins 4.3).
	var p0 := Vector3(0.0, -0.085, -0.02)
	var p1 := Vector3(0.0, 0.0, 0.115)
	var p2 := Vector3(0.0, 0.085, -0.02)
	const RINGS := 10
	const RADIAL := 6
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in range(RINGS):
		var t := float(i) / float(RINGS - 1)
		var pos := _quad_bezier(p0, p1, p2, t)
		var t2 := minf(1.0, t + 0.01)
		var tangent := (_quad_bezier(p0, p1, p2, t2) - pos).normalized()
		if tangent.length_squared() < 1e-6:
			tangent = Vector3.BACK
		var ref := Vector3.RIGHT if absf(tangent.dot(Vector3.RIGHT)) < 0.9 else Vector3.UP
		var n := ref.cross(tangent).normalized()
		var b := tangent.cross(n).normalized()
		for j in range(RADIAL):
			var ang := TAU * float(j) / float(RADIAL)
			var dir := n * cos(ang) + b * sin(ang)
			verts.append(pos + dir * 0.042)
			normals.append(dir)
			uvs.append(Vector2(float(j) / float(RADIAL), t))
	for i in range(RINGS - 1):
		for j in range(RADIAL):
			var a := i * RADIAL + j
			var b := i * RADIAL + (j + 1) % RADIAL
			var c := (i + 1) * RADIAL + j
			var d := (i + 1) * RADIAL + (j + 1) % RADIAL
			indices.append(a); indices.append(c); indices.append(b)
			indices.append(b); indices.append(c); indices.append(d)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.83, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.78, 0.08)
	mat.emission_energy_multiplier = 1.9
	mat.roughness = 0.45
	mesh.surface_set_material(0, mat)
	return mesh


static func _get_banana_mesh() -> ArrayMesh:
	if _banana_mesh == null:
		_banana_mesh = _build_banana_mesh()
	return _banana_mesh


static func _get_tip_mesh() -> SphereMesh:
	if _tip_mesh == null:
		var sm := SphereMesh.new()
		sm.radius = 0.030
		sm.height = 0.060
		sm.radial_segments = 6
		sm.rings = 4
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.35, 0.22, 0.08)
		m.roughness = 0.6
		sm.material = m
		_tip_mesh = sm
	return _tip_mesh


static func _get_trail_puff_mesh() -> SphereMesh:
	if _trail_puff_mesh == null:
		var puff := SphereMesh.new()
		puff.radius = 0.06
		puff.height = 0.12
		puff.radial_segments = 5
		puff.rings = 3
		var tm := StandardMaterial3D.new()
		tm.albedo_color = Color(1.0, 0.9, 0.3)
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		puff.material = tm
		_trail_puff_mesh = puff
	return _trail_puff_mesh


static func _get_trail_ramp() -> GradientTexture1D:
	if _trail_ramp == null:
		var ramp := GradientTexture1D.new()
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.9, 0.25, 0.9))
		g.set_color(1, Color(1.0, 0.75, 0.1, 0.0))
		ramp.gradient = g
		_trail_ramp = ramp
	return _trail_ramp


static func _add_tip(tracer: Node3D, offset: Vector3) -> void:
	var tip := MeshInstance3D.new()
	tip.mesh = _get_tip_mesh()
	tip.position = offset
	tracer.add_child(tip)


func setup(p_owner_id: String, p_owner_node: Node, p_origin: Vector3,
		p_direction: Vector3, p_speed: float, p_damage: float,
		p_token: String, p_color: Color) -> void:
	owner_id = p_owner_id
	owner_node = p_owner_node
	global_position = p_origin
	if p_direction.length_squared() < 1e-8 or not is_finite(p_direction.x + p_direction.y + p_direction.z):
		velocity = Vector3.ZERO
		_inert = true
		_life = 0.05
	else:
		velocity = p_direction.normalized() * p_speed
		_inert = false
	damage = p_damage
	token = p_token
	hit_color = p_color
	if _inert:
		return
	_build_tracer()


func _build_tracer() -> void:
	_tracer = Node3D.new()
	_tracer.name = "Banana"
	add_child(_tracer)
	var body := MeshInstance3D.new()
	body.mesh = _get_banana_mesh()
	_tracer.add_child(body)
	_add_tip(_tracer, Vector3(0.0, -0.085, -0.02))
	_add_tip(_tracer, Vector3(0.0, 0.085, -0.02))
	var dir := velocity.normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	_tracer.basis = Basis.looking_at(dir, up)

	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collide_with_areas = false
	_ray_query.collide_with_bodies = true
	if owner_node is CollisionObject3D:
		_ray_query.exclude = [(owner_node as CollisionObject3D).get_rid()]

	# Bananas rely on emissive material + bloom rather than per-shot OmniLight3D
	# nodes so WebGL2 stays within its 8-light-per-surface budget.

	if not Settings.reduced_motion():
		var trail := GPUParticles3D.new()
		trail.amount = maxi(3, int(14 * Settings.quality_multiplier()))
		trail.lifetime = 0.26
		trail.local_coords = false
		trail.visibility_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3.0, 3.0, 3.0))
		var pm := ParticleProcessMaterial.new()
		pm.direction = -velocity.normalized()
		pm.spread = 7.0
		pm.initial_velocity_min = 0.2
		pm.initial_velocity_max = 0.9
		pm.scale_min = 0.10
		pm.scale_max = 0.26
		pm.color_ramp = _get_trail_ramp()
		trail.process_material = pm
		trail.draw_pass_1 = _get_trail_puff_mesh()
		_tracer.add_child(trail)
		trail.emitting = true


func _physics_process(delta: float) -> void:
	_age += delta
	if _inert:
		if _age >= _life:
			queue_free()
		return
	if _age >= _life:
		queue_free()
		return
	# tumble: spin the banana around its flight axis every tick
	if _tracer != null and not Settings.reduced_motion():
		_tracer.rotate_object_local(Vector3(0.0, 0.0, 1.0), delta * 9.0)
	var world := get_world_3d()
	if world == null:
		return
	var from := global_position
	var to := from + velocity * delta
	_ray_query.from = from
	_ray_query.to = to
	var space := world.direct_space_state
	var result := space.intersect_ray(_ray_query)
	if result.is_empty():
		global_position = to
		return
	var collider: Object = result.get("collider", null)
	var point: Vector3 = result.get("position", to)
	if collider == owner_node:
		global_position = to
		return
	global_position = point
	hit.emit(collider as Node, point)
	if on_hit.is_valid():
		on_hit.call(collider, point, self)
	# Bikes and hazards run their own impact/death VFX via CombatController;
	# scenery hits get a banana-friendly splash.
	if collider is Node:
		var node := collider as Node
		if not node.is_in_group("bike") and not node.is_in_group("hazard"):
			var surface := "concrete"
			if node.name == "Ground":
				surface = "ground"
			elif not node.is_in_group("destructible"):
				surface = "metal"
			var n: Vector3 = result.get("normal", Vector3.UP)
			var fx := get_parent() as Node3D
			if fx == null and get_tree() != null:
				fx = get_tree().current_scene as Node3D
			VfxFactory.impact(fx, point, hit_color, velocity.normalized(), surface, n)
	queue_free()
