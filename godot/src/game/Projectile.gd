extends Node3D
## Compact cannon projectile. Uses a swept ray each physics step so fast shots
## cannot tunnel through bikes or scenery. Visuals: stretched glowing tracer
## (capsule aligned to velocity), additive trail, and a flickering point light.

signal hit(target: Node, point: Vector3)

var owner_id := ""
var owner_node: Node
var velocity := Vector3.ZERO
var damage := 30.0
var token := ""
var hit_color := Color(1.0, 0.55, 0.15)
var on_hit: Callable

var _age := 0.0
var _life := 2.2
var _inert := true  # setup() re-arms; a never-configured bolt dies instantly
var _trail: GPUParticles3D
var _tracer: Node3D
var _light: OmniLight3D
var _ray_query: PhysicsRayQueryParameters3D

static var _nose_mesh: SphereMesh = null
static var _shaft_cache: Dictionary = {}
static var _trail_mesh_cache: Dictionary = {}
static var _trail_ramp_cache: Dictionary = {}


static func _get_nose_mesh() -> SphereMesh:
	if _nose_mesh == null:
		var sm := SphereMesh.new()
		sm.radius = 0.085
		sm.height = 0.17
		sm.radial_segments = 8
		sm.rings = 4
		var nose_mat := StandardMaterial3D.new()
		nose_mat.albedo_color = Color(1, 1, 0.92)
		nose_mat.emission_enabled = true
		nose_mat.emission = Color(1.0, 0.98, 0.88)
		nose_mat.emission_energy_multiplier = 9.0
		nose_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.material = nose_mat
		_nose_mesh = sm
	return _nose_mesh


static func _get_shaft_mesh(col: Color) -> CapsuleMesh:
	var key := col.to_html(false)
	if not _shaft_cache.has(key):
		var axis := CapsuleMesh.new()
		axis.radius = 0.062
		axis.height = 0.46
		axis.radial_segments = 8
		axis.rings = 4
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.96, 0.75)
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 6.5
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		axis.material = mat
		_shaft_cache[key] = axis
	return _shaft_cache[key]


static func _get_trail_mesh(col: Color) -> SphereMesh:
	var key := col.to_html(false)
	if not _trail_mesh_cache.has(key):
		var tm := SphereMesh.new()
		tm.radius = 0.11
		tm.height = 0.22
		tm.radial_segments = 5
		tm.rings = 3
		var trail_mat := StandardMaterial3D.new()
		trail_mat.albedo_color = col
		trail_mat.emission_enabled = true
		trail_mat.emission = col
		trail_mat.emission_energy_multiplier = 2.6
		trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		tm.material = trail_mat
		_trail_mesh_cache[key] = tm
	return _trail_mesh_cache[key]


static func _get_trail_ramp(col: Color) -> GradientTexture1D:
	var key := col.to_html(false)
	if not _trail_ramp_cache.has(key):
		var g := Gradient.new()
		g.set_color(0, Color(col.r, col.g, col.b, 0.95))
		g.set_color(1, Color(col.r * 0.5, col.g * 0.3, 0.02, 0.0))
		g.add_point(0.35, Color(1.0, 0.82, 0.35, 0.6))
		var ramp := GradientTexture1D.new()
		ramp.gradient = g
		_trail_ramp_cache[key] = ramp
	return _trail_ramp_cache[key]


func setup(p_owner_id: String, p_owner_node: Node, p_origin: Vector3,
		p_direction: Vector3, p_speed: float, p_damage: float,
		p_token: String, p_color: Color) -> void:
	owner_id = p_owner_id
	owner_node = p_owner_node
	global_position = p_origin
	# Defence in depth: every caller passes a valid direction today, but a
	# degenerate vector would otherwise yield an immortal zero-velocity bolt.
	if p_direction.length_squared() < 1e-8 or not is_finite(p_direction.x + p_direction.y + p_direction.z):
		velocity = Vector3.ZERO
		_inert = true
		_life = 0.05  # immortal zero-velocity bolt guard
	else:
		velocity = p_direction.normalized() * p_speed
		_inert = false
	damage = p_damage
	token = p_token
	hit_color = p_color
	_build_tracer()


func _build_tracer() -> void:
	if _inert:
		# No visuals for a degenerate bolt — it dies in 0.05 s.
		return
	# Tracer: elongated capsule stretched along the line of flight. The capsule
	# is rotationally symmetric about its long axis, so basis orientation
	# sign conventions can't flip the visual.
	_tracer = Node3D.new()
	_tracer.name = "Tracer"
	add_child(_tracer)
	var shaft := MeshInstance3D.new()
	shaft.mesh = _get_shaft_mesh(hit_color)
	# CapsuleMesh long axis is Y; rotate to lie along Z (the tracer basis).
	shaft.rotation_degrees.x = 90.0
	_tracer.add_child(shaft)
	# hot white-hot nose pellet for the leading edge
	var nose := MeshInstance3D.new()
	nose.mesh = _get_nose_mesh()
	nose.position.z = 0.22
	_tracer.add_child(nose)
	_tracer.basis = Basis.looking_at(velocity.normalized(), Vector3.UP)

	# Reuse a single ray query across all physics ticks of this projectile.
	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collide_with_areas = false
	_ray_query.collide_with_bodies = true
	if owner_node is CollisionObject3D:
		# Own chassis never blocks the frame-1 trace: intersect_ray returns only
		# the first hit, so a point-blank self-hit would otherwise teleport the
		# bolt past whatever it should have hit.
		_ray_query.exclude = [(owner_node as CollisionObject3D).get_rid()]

	# Dynamic OmniLight3D per bolt multiplies forward WebGL shader lights; skip on low/mobile-auto budgets.
	if Settings.quality_multiplier() >= 0.75:
		_light = OmniLight3D.new()
		_light.light_color = hit_color
		_light.light_energy = 3.2
		_light.omni_range = 3.2
		add_child(_light)

	_trail = GPUParticles3D.new()
	_trail.amount = maxi(4, int(30 * Settings.quality_multiplier()))
	_trail.lifetime = 0.32
	_trail.local_coords = false
	_trail.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	var pm := ParticleProcessMaterial.new()
	pm.direction = -velocity.normalized()
	pm.spread = 9.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.3
	pm.scale_min = 0.16
	pm.scale_max = 0.5
	pm.color_ramp = _get_trail_ramp(hit_color)
	_trail.process_material = pm
	_trail.draw_pass_1 = _get_trail_mesh(hit_color)
	add_child(_trail)
	_trail.emitting = true


func _physics_process(delta: float) -> void:
	_age += delta
	if _inert:
		if _age >= _life:
			queue_free()
		return
	if _age >= _life:
		queue_free()
		return
	# flicker the tracer light — cheap sin, no allocations
	if _light != null:
		_light.light_energy = 2.6 + sin(_age * 34.0) * 0.9
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
	# Bikes and hazards already spawn their own impact/death VFX via
	# CombatController — only scenery hits need a local spark and scar.
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
	_trail.emitting = false
	queue_free()
