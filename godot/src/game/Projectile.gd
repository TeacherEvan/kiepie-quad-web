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
var _trail: GPUParticles3D
var _tracer: Node3D
var _light: OmniLight3D


func setup(p_owner_id: String, p_owner_node: Node, p_origin: Vector3,
		p_direction: Vector3, p_speed: float, p_damage: float,
		p_token: String, p_color: Color) -> void:
	owner_id = p_owner_id
	owner_node = p_owner_node
	global_position = p_origin
	velocity = p_direction.normalized() * p_speed
	damage = p_damage
	token = p_token
	hit_color = p_color


func _ready() -> void:
	# Tracer: elongated capsule stretched along the line of flight. The capsule
	# is rotationally symmetric about its long axis, so basis orientation
	# sign conventions can't flip the visual.
	_tracer = Node3D.new()
	_tracer.name = "Tracer"
	add_child(_tracer)
	var axis := CapsuleMesh.new()
	axis.radius = 0.062
	axis.height = 0.46
	axis.radial_segments = 8
	axis.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.96, 0.75)
	mat.emission_enabled = true
	mat.emission = hit_color
	mat.emission_energy_multiplier = 6.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	axis.material = mat
	var shaft := MeshInstance3D.new()
	shaft.mesh = axis
	# CapsuleMesh long axis is Y; rotate to lie along Z (the tracer basis).
	shaft.rotation_degrees.x = 90.0
	_tracer.add_child(shaft)
	# hot white-hot nose pellet for the leading edge
	var nose := MeshInstance3D.new()
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
	nose.mesh = sm
	nose.position.z = 0.22
	_tracer.add_child(nose)
	_tracer.basis = Basis.looking_at(velocity.normalized(), Vector3.UP)

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
	var g := Gradient.new()
	g.set_color(0, Color(hit_color.r, hit_color.g, hit_color.b, 0.95))
	g.set_color(1, Color(hit_color.r * 0.5, hit_color.g * 0.3, 0.02, 0.0))
	g.add_point(0.35, Color(1.0, 0.82, 0.35, 0.6))
	var ramp := GradientTexture1D.new()
	ramp.gradient = g
	pm.color_ramp = ramp
	_trail.process_material = pm
	var tm := SphereMesh.new()
	tm.radius = 0.11
	tm.height = 0.22
	tm.radial_segments = 5
	tm.rings = 3
	var trail_mat := StandardMaterial3D.new()
	trail_mat.albedo_color = hit_color
	trail_mat.emission_enabled = true
	trail_mat.emission = hit_color
	trail_mat.emission_energy_multiplier = 2.6
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.material = trail_mat
	_trail.draw_pass_1 = tm
	add_child(_trail)
	_trail.emitting = true


func _physics_process(delta: float) -> void:
	_age += delta
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
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# Bodies only: Pickup/SmashTrigger Area3Ds must not swallow shots.
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var space := world.direct_space_state
	var result := space.intersect_ray(query)
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
