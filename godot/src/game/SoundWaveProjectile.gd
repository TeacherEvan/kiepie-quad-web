extends Node3D
## Evan the Skeleton's primary: pink sound waves rippling out of his guitar.
## Same swept-ray rules as Projectile.gd so a fast wave cannot tunnel through
## bikes or scenery. Visuals are concentric additive rings, a pink core streak,
## a gated particle trail and a capped, gated point light.

signal hit(target: Node, point: Vector3)

const VFX := preload("res://src/game/VfxFactory.gd")
const RING_COUNT := 4
const RIPPLE_HZ := 2.7
const RING_MIN_SCALE := 0.55
const RING_GROWTH := 1.05

var owner_id := ""
var owner_node: Node
var velocity := Vector3.ZERO
var damage := 30.0
var token := ""
var hit_color := Color(1.0, 0.12, 0.52)
var on_hit: Callable

var _age := 0.0
var _life := 2.2
var _inert := true  # setup() re-arms; a degenerate-direction wave stays inert
var pooled := false
var _wave: Node3D
var _rings: Array[MeshInstance3D] = []
var _core: MeshInstance3D
var _trail: GPUParticles3D
var _light: OmniLight3D
var _last_color := Color(-1, -1, -1, -1)
var _ray_query: PhysicsRayQueryParameters3D

static var _ring_mesh: TorusMesh = null
static var _ring_mat_cache: Dictionary = {}
static var _core_mesh_cache: Dictionary = {}
static var _trail_mesh_cache: Dictionary = {}
static var _trail_ramp_cache: Dictionary = {}


static func _get_ring_mesh() -> TorusMesh:
	if _ring_mesh == null:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.21
		tm.outer_radius = 0.27
		tm.rings = 20
		tm.ring_segments = 6
		_ring_mesh = tm
	return _ring_mesh


static func _get_ring_materials(col: Color) -> Array:
	var key := col.to_html(false)
	if not _ring_mat_cache.has(key):
		var mats: Array[StandardMaterial3D] = []
		for i in range(RING_COUNT):
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(col.r, col.g, col.b, 0.92 - float(i) * 0.13)
			mat.emission_enabled = true
			mat.emission = col
			mat.emission_energy_multiplier = 4.6 - float(i) * 0.65
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mats.append(mat)
		_ring_mat_cache[key] = mats
	return _ring_mat_cache[key]


static func _get_core_mesh(col: Color) -> CapsuleMesh:
	var key := col.to_html(false)
	if not _core_mesh_cache.has(key):
		var axis := CapsuleMesh.new()
		axis.radius = 0.045
		axis.height = 0.44
		axis.radial_segments = 8
		axis.rings = 4
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.85, 0.96)
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 9.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		axis.material = mat
		_core_mesh_cache[key] = axis
	return _core_mesh_cache[key]


static func _get_trail_mesh(col: Color) -> SphereMesh:
	var key := col.to_html(false)
	if not _trail_mesh_cache.has(key):
		var tm := SphereMesh.new()
		tm.radius = 0.075
		tm.height = 0.15
		tm.radial_segments = 5
		tm.rings = 3
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(col.r, col.g, col.b, 0.85)
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 2.8
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		tm.material = mat
		_trail_mesh_cache[key] = tm
	return _trail_mesh_cache[key]


static func _get_trail_ramp(col: Color) -> GradientTexture1D:
	var key := col.to_html(false)
	if not _trail_ramp_cache.has(key):
		_trail_ramp_cache[key] = VFX._ramp([
			Color(1.0, 0.82, 0.96, 0.95),
			Color(col.r, col.g, col.b, 0.7),
			Color(col.r * 0.5, col.g * 0.2, col.b * 0.4, 0.0),
		])
	return _trail_ramp_cache[key]


func setup(p_owner_id: String, p_owner_node: Node, p_origin: Vector3,
		p_direction: Vector3, p_speed: float, p_damage: float,
		p_token: String, p_color: Color) -> void:
	owner_id = p_owner_id
	owner_node = p_owner_node
	global_position = p_origin
	# A degenerate vector would otherwise yield an immortal zero-velocity wave.
	if p_direction.length_squared() < 1e-8 or not is_finite(p_direction.x + p_direction.y + p_direction.z) or not is_finite(p_speed) or p_speed <= 0.0:
		velocity = Vector3.ZERO
		_inert = true
		_life = 0.05
	else:
		velocity = p_direction.normalized() * p_speed
		_inert = false
		_life = 2.2
	damage = p_damage
	token = p_token
	hit_color = p_color
	_age = 0.0
	if _inert and pooled:
		_recycle()
		return
	if _wave == null:
		_build_wave()
	else:
		_rearm_wave()


func _apply_color() -> void:
	var mats: Array = _get_ring_materials(hit_color)
	for i in range(_rings.size()):
		_rings[i].material_override = mats[i]
	if _core != null:
		_core.mesh = _get_core_mesh(hit_color)
	_last_color = hit_color


func _rearm_wave() -> void:
	visible = true
	set_physics_process(true)
	_age = 0.0
	if _inert:
		_recycle()
		return
	var dir := velocity.normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	if _wave != null:
		_wave.basis = Basis.looking_at(dir, up)
	if _ray_query != null:
		_ray_query.exclude = [(owner_node as CollisionObject3D).get_rid()] if (is_instance_valid(owner_node) and owner_node is CollisionObject3D) else []
	var color_changed := hit_color != _last_color
	if color_changed:
		_apply_color()
	if not Settings.reduced_motion() and Settings.quality_multiplier() > 0.0 and _trail == null:
		_ensure_trail(dir)
	if _trail != null:
		if _trail.process_material is ParticleProcessMaterial:
			var pm := _trail.process_material as ParticleProcessMaterial
			pm.direction = -dir
			if color_changed:
				pm.color_ramp = _get_trail_ramp(hit_color)
		if color_changed:
			_trail.draw_pass_1 = _get_trail_mesh(hit_color)
		_trail.restart()
		_trail.emitting = not Settings.reduced_motion() and Settings.quality_multiplier() > 0.0
	_ensure_light()
	_animate_rings()


func _recycle() -> void:
	_inert = true
	visible = false
	set_physics_process(false)
	on_hit = Callable()
	owner_node = null
	if _trail != null:
		_trail.emitting = false
	_release_light()
	if not pooled:
		queue_free()


func _build_wave() -> void:
	visible = true
	set_physics_process(true)
	_age = 0.0
	if _inert:
		return
	_wave = Node3D.new()
	_wave.name = "SoundWave"
	add_child(_wave)
	var mats: Array = _get_ring_materials(hit_color)
	for i in range(RING_COUNT):
		var ring := MeshInstance3D.new()
		ring.name = "Ripple%d" % i
		ring.mesh = _get_ring_mesh()
		ring.material_override = mats[i]
		ring.rotation_degrees.x = 90.0
		ring.position.z = -0.30 + float(i) * 0.18
		_wave.add_child(ring)
		_rings.append(ring)
	_core = MeshInstance3D.new()
	_core.name = "CoreStreak"
	_core.mesh = _get_core_mesh(hit_color)
	_core.rotation_degrees.x = 90.0
	_wave.add_child(_core)
	_last_color = hit_color
	var dir := velocity.normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	_wave.basis = Basis.looking_at(dir, up)

	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collide_with_areas = false
	_ray_query.collide_with_bodies = true
	# Own chassis never blocks the frame-1 trace: intersect_ray returns only
	# the first hit, so a point-blank self-hit would hide the real target.
	_ray_query.exclude = [(owner_node as CollisionObject3D).get_rid()] if (is_instance_valid(owner_node) and owner_node is CollisionObject3D) else []

	_animate_rings()
	if not Settings.reduced_motion() and Settings.quality_multiplier() > 0.0:
		_ensure_trail(dir)
	_ensure_light()


func _animate_rings() -> void:
	var reduced := Settings.reduced_motion()
	for i in range(_rings.size()):
		var ring := _rings[i]
		if reduced:
			ring.scale = Vector3.ONE
			continue
		var phase := fposmod(_age * RIPPLE_HZ + float(i) / float(RING_COUNT), 1.0)
		var s := RING_MIN_SCALE + phase * RING_GROWTH
		ring.scale = Vector3(s, 1.0, s)


func _ensure_trail(dir: Vector3) -> void:
	if _trail != null:
		return
	_trail = GPUParticles3D.new()
	_trail.amount = maxi(4, int(20 * Settings.quality_multiplier()))
	_trail.lifetime = 0.30
	_trail.local_coords = false
	_trail.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	var pm := ParticleProcessMaterial.new()
	pm.direction = -dir
	pm.spread = 8.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.2
	pm.scale_min = 0.12
	pm.scale_max = 0.35
	pm.color_ramp = _get_trail_ramp(hit_color)
	_trail.process_material = pm
	_trail.draw_pass_1 = _get_trail_mesh(hit_color)
	add_child(_trail)
	_trail.emitting = true


func _ensure_light() -> void:
	if Settings.quality_multiplier() < 0.5:
		_release_light()
		return
	if is_instance_valid(_light) and _light.is_in_group("vfx_light"):
		return
	_release_light()
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.16, 0.56)
	_light.light_energy = 2.0
	_light.omni_range = 3.4
	_light.add_to_group("vfx_light")
	add_child(_light)
	VFX._cap_group(self, "vfx_light", VFX.MAX_IMPACT_LIGHTS)


func _release_light() -> void:
	if is_instance_valid(_light):
		if _light.is_in_group("vfx_light"):
			_light.remove_from_group("vfx_light")
		_light.queue_free()
	_light = null


func _exit_tree() -> void:
	_release_light()


func _physics_process(delta: float) -> void:
	_age += delta
	if _inert:
		if _age >= _life:
			_recycle()
		return
	if _age >= _life:
		_recycle()
		return
	_animate_rings()
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
	if is_instance_valid(owner_node) and collider == owner_node:
		global_position = to
		return
	global_position = point
	# Damage stays in on_hit so no remote proxy is ever mutated from here.
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
	if _trail != null:
		_trail.emitting = false
	_release_light()
	_recycle()
