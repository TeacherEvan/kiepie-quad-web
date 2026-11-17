extends Node3D
## Compact cannon projectile. Uses a swept ray each physics step so fast shots
## cannot tunnel through bikes or scenery. Visuals are a glowing core + trail.

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
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.095
	sm.height = 0.19
	sm.radial_segments = 8
	sm.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.95, 0.7)
	mat.emission_enabled = true
	mat.emission = hit_color
	mat.emission_energy_multiplier = 6.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = mat
	core.mesh = sm
	add_child(core)

	var light := OmniLight3D.new()
	light.light_color = hit_color
	light.light_energy = 3.0
	light.omni_range = 3.0
	add_child(light)

	_trail = GPUParticles3D.new()
	_trail.amount = maxi(4, int(24 * Settings.quality_multiplier()))
	_trail.lifetime = 0.28
	_trail.local_coords = false
	_trail.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	var pm := ParticleProcessMaterial.new()
	pm.direction = -velocity.normalized()
	pm.spread = 7.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.1
	pm.scale_min = 0.18
	pm.scale_max = 0.5
	var g := Gradient.new()
	g.set_color(0, Color(hit_color.r, hit_color.g, hit_color.b, 0.9))
	g.set_color(1, Color(hit_color.r * 0.5, hit_color.g * 0.3, 0.02, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = g
	pm.color_ramp = ramp
	_trail.process_material = pm
	var tm := SphereMesh.new()
	tm.radius = 0.11
	tm.height = 0.22
	tm.radial_segments = 5
	tm.rings = 3
	tm.material = mat
	_trail.draw_pass_1 = tm
	add_child(_trail)
	_trail.emitting = true


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= _life:
		queue_free()
		return
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
	_trail.emitting = false
	queue_free()
