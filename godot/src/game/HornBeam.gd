extends Node3D
## LEA UNICORN rocket slot — HORN BEAM.
## The unicorn charges a swirling particle vortex in front of her horn for
## 0.55 s, then fires a straight plasma/laser beam for 0.35 s. Every bike on
## the line takes the launcher's damage; a direct hit on a locally-controlled
## bike is lethal, exactly like the other rocket-slot weapons.
## Wire kind stays "rocket" (no protocol bump); victim authority is preserved.

signal hit(target: Node, point: Vector3)

const CHARGE_TIME := 0.55
const BEAM_TIME := 0.35
const MAX_LENGTH := 55.0
const MAX_TARGETS := 8
const VFX := preload("res://src/game/VfxFactory.gd")

var owner_id := ""
var owner_node: Node
var velocity := Vector3.FORWARD * 38.0
var damage := 90.0
var token := ""
var hit_color := Color(0.45, 0.92, 1.0)
var blast_radius := 4.5
var visual_style := "horn_beam"
var on_hit: Callable

var _age := 0.0
var _armed := false
var _beaming := false
var _done := false
var _inert := true
var _base_token := ""
var _direction := Vector3.FORWARD
var _charge: Node3D = null
var _vortex: GPUParticles3D = null
var _charge_ring: MeshInstance3D = null
var _beam: MeshInstance3D = null
var _beam_core: MeshInstance3D = null
var _light: OmniLight3D = null
var _hit_nodes: Array[Node] = []
var _ray: PhysicsRayQueryParameters3D = null

static var _beam_mesh: BoxMesh = null
static var _beam_mat: StandardMaterial3D = null
static var _beam_core_mesh: BoxMesh = null
static var _beam_core_mat: StandardMaterial3D = null
static var _spark_mesh: SphereMesh = null
static var _spark_ramp: GradientTexture1D = null
static var _ring_mesh: TorusMesh = null


static func _ensure_meshes() -> void:
	if _beam_mesh == null:
		_bm_setup()


static func _bm_setup() -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(0.36, 0.36, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.96, 1.0, 0.92)
	mat.emission_enabled = true
	mat.emission = Color(0.30, 0.84, 1.0)
	mat.emission_energy_multiplier = 6.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.material = mat
	_beam_mesh = bm
	_beam_mat = mat

	var bcm := BoxMesh.new()
	bcm.size = Vector3(0.14, 0.14, 1.0)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(1.0, 0.98, 0.90, 0.98)
	cmat.emission_enabled = true
	cmat.emission = Color(0.92, 0.98, 1.0)
	cmat.emission_energy_multiplier = 9.0
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bcm.material = cmat
	_beam_core_mesh = bcm
	_beam_core_mat = cmat

	var sm := SphereMesh.new()
	sm.radius = 0.055
	sm.height = 0.11
	sm.radial_segments = 6
	sm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(1.0, 0.96, 0.70, 0.95)
	smat.emission_enabled = true
	smat.emission = Color(1.0, 0.86, 0.40)
	smat.emission_energy_multiplier = 4.2
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.material = smat
	_spark_mesh = sm
	_spark_ramp = VFX._ramp([
		Color(1.0, 0.96, 0.72, 0.98),
		Color(0.42, 0.88, 1.0, 0.72),
		Color(0.20, 0.36, 0.90, 0.0),
	])
	var rm := TorusMesh.new()
	rm.inner_radius = 0.22
	rm.outer_radius = 0.30
	rm.rings = 16
	rm.ring_segments = 6
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.60, 0.92, 1.0, 0.72)
	rmat.emission_enabled = true
	rmat.emission = Color(0.40, 0.86, 1.0)
	rmat.emission_energy_multiplier = 3.4
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.material = rmat
	_ring_mesh = rm


func setup(p_owner_id: String, p_owner_node: Node, p_origin: Vector3,
		p_direction: Vector3, p_speed: float, p_damage: float,
		p_token: String, p_color: Color, p_blast_radius: float = 4.5,
		p_visual_style: String = "horn_beam") -> void:
	# Fail closed on every number that arrives from a socket or a bad frame.
	if not is_finite(p_damage) or not is_finite(p_speed) or p_speed <= 0.0:
		push_warning("HornBeam.setup: rejecting non-finite/invalid parameters")
		_inert = true
		queue_free()  # callers have already add_child()ed this node
		return
	if not is_finite(p_direction.x + p_direction.y + p_direction.z) \
			or p_direction.length_squared() < 1e-8:
		_inert = true
		queue_free()
		return
	owner_id = p_owner_id
	owner_node = p_owner_node
	global_position = p_origin
	_direction = p_direction.normalized()
	velocity = _direction * p_speed
	damage = clampf(p_damage, 0.0, 200.0)
	token = p_token
	_base_token = p_token
	hit_color = p_color
	blast_radius = clampf(p_blast_radius, 0.0, 4.5)
	visual_style = p_visual_style if p_visual_style != "" else "horn_beam"
	_age = 0.0
	_armed = true
	_beaming = false
	_done = false
	_inert = false
	_hit_nodes.clear()
	var model := p_owner_node.get_node_or_null("Model") if is_instance_valid(p_owner_node) else null
	if model != null and model.has_method("trigger_charge"):
		model.call("trigger_charge", 1.0)
	_ensure_meshes()
	_build_charge()


func _release_light() -> void:
	if is_instance_valid(_light):
		if _light.is_in_group("vfx_light"):
			_light.remove_from_group("vfx_light")
		_light.queue_free()
	_light = null


func _ensure_light() -> void:
	if get_tree() == null or Settings.quality_multiplier() < 0.5:
		return
	if is_instance_valid(_light) and _light.is_in_group("vfx_light"):
		return
	_release_light()
	_light = OmniLight3D.new()
	_light.name = "BeamLight"
	_light.light_color = Color(0.40, 0.88, 1.0)
	_light.light_energy = 2.6
	_light.omni_range = 5.0
	_light.add_to_group("vfx_light")
	add_child(_light)
	VFX._cap_group(self, "vfx_light", VFX.MAX_IMPACT_LIGHTS)


func _build_charge() -> void:
	_charge = Node3D.new()
	_charge.name = "ChargeVortex"
	add_child(_charge)
	_charge.basis = Basis.looking_at(_direction, Vector3.UP if absf(_direction.y) < 0.99 else Vector3.FORWARD)
	_charge_ring = MeshInstance3D.new()
	_charge_ring.name = "ChargeRing"
	_charge_ring.mesh = _ring_mesh
	_charge_ring.rotation_degrees.x = 90.0
	_charge_ring.position.z = -0.55
	_charge.add_child(_charge_ring)
	if not Settings.reduced_motion() and Settings.quality_multiplier() > 0.0:
		_vortex = GPUParticles3D.new()
		_vortex.name = "ChargeSparks"
		_vortex.amount = maxi(8, int(30 * Settings.quality_multiplier()))
		_vortex.lifetime = 0.34
		_vortex.local_coords = true
		_vortex.visibility_aabb = AABB(Vector3(-1.4, -1.4, -1.4), Vector3(2.8, 2.8, 2.8))
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0.0, 0.0, -1.0)
		pm.spread = 0.0
		pm.gravity = Vector3.ZERO
		pm.initial_velocity_min = 0.8
		pm.initial_velocity_max = 2.2
		pm.scale_min = 0.35
		pm.scale_max = 0.95
		pm.color_ramp = _spark_ramp
		pm.tangential_accel = Vector2(16.0, 0.0)
		_vortex.process_material = pm
		_vortex.draw_pass_1 = _spark_mesh
		_charge.add_child(_vortex)
		_vortex.emitting = true
	_ensure_light()


func _start_beam() -> void:
	_beaming = true
	if _charge != null:
		_charge.queue_free()
		_charge = null
		_charge_ring = null
		_vortex = null
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true
	_ray.exclude = [(owner_node as CollisionObject3D).get_rid()] \
			if (is_instance_valid(owner_node) and owner_node is CollisionObject3D) else []
	# The visual beam leaves the horn tip (~1.8-1.9 m) but a horizontal ray at that
	# height sails over every bike hitbox (top ~0.95 m). Trace at chassis height
	# while the additive beam mesh stays anchored at the horn. The same -1.05 m
	# correction is derived from the broadcast origin on remote proxies.
	var trace_origin := global_position + Vector3(0.0, -1.05, 0.0)
	var endpoint := trace_origin + _direction * MAX_LENGTH
	# Probe the whole line once (up to MAX_TARGETS) so every bike on it is hit,
	# and advance past each collider to avoid hitting the same body twice.
	var cursor := trace_origin
	var direct_bike: Node = null
	for _i in range(MAX_TARGETS):
		_ray.from = cursor
		_ray.to = endpoint
		var space := get_world_3d()
		if space == null:
			break
		var result := space.direct_space_state.intersect_ray(_ray)
		if result.is_empty():
			break
		var collider: Object = result.get("collider", null)
		var point: Vector3 = result.get("position", endpoint)
		if collider is Node and not _hit_nodes.has(collider as Node):
			_hit_nodes.append(collider as Node)
			var is_bike := (collider as Node).is_in_group("bike")
			var is_direct := is_bike and direct_bike == null
			if is_direct:
				direct_bike = collider as Node
			# Only the FIRST rider on the line is a lethal direct hit. Everyone
			# else takes the launcher's flat 90 damage through on_hit — the same
			# rule as the other rocket-slot weapons, not a multi-kill laser.
			_apply_hit(collider as Node, point, is_direct)
		cursor = point + _direction * 0.12
		if cursor.distance_to(trace_origin) >= MAX_LENGTH:
			break
	var end_point := cursor if cursor != trace_origin else endpoint
	var span: float = clampf(end_point.distance_to(global_position), 0.5, MAX_LENGTH)
	_beam = MeshInstance3D.new()
	_beam.name = "PlasmaBeam"
	_beam.mesh = _beam_mesh
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.basis = Basis.looking_at(_direction, Vector3.UP if absf(_direction.y) < 0.99 else Vector3.FORWARD)
	# Basis.looking_at aims local -Z at the firing direction, so a box scaled on
	# local Z extends toward -_direction from its centre. Centre it FORWARD of
	# the horn (+_direction) so the additive glow travels with the damage ray
	# instead of shooting out the rear of the unicorn.
	_beam.position = _direction * (span * 0.5)
	# The supplied blast radius governs the beam's visible width (and therefore
	# its readability); damage itself uses the launcher's flat blast damage.
	var width_scale := maxf(0.25, blast_radius / 4.5)
	_beam.scale = Vector3(width_scale, width_scale, span)
	add_child(_beam)

	_beam_core = MeshInstance3D.new()
	_beam_core.name = "BeamCore"
	_beam_core.mesh = _beam_core_mesh
	_beam_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.add_child(_beam_core)

	_ensure_light()
	if is_instance_valid(_light):
		_light.light_energy = 7.2
		_light.omni_range = 9.0
	if not Settings.reduced_motion():
		var fx := get_parent() as Node3D
		if fx == null and get_tree() != null:
			fx = get_tree().current_scene as Node3D
		if fx != null:
			VFX.S._flash_billboard(fx, global_position + _direction * 0.25, 1.85,
					Color(0.82, 0.98, 1.0, 0.96), 0.14)
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		if sfx.has_method("play_3d"):
			sfx.call("play_3d", "fire", global_position, 2.0, 1.38)
		elif sfx.has_method("play"):
			sfx.call("play", "fire", 2.0, 1.38)


func _apply_hit(collider: Node, point: Vector3, is_direct: bool) -> void:
	hit.emit(collider, point)
	# Per-victim sub-token keeps the host's same-shot kill burst exemption.
	var target_id := ""
	if collider.is_in_group("bike"):
		var vv: Variant = collider.get("player_id")
		target_id = str(vv) if vv != null else ""
	token = ("%s:v%s" % [_base_token, target_id]) if (_base_token != "" and target_id != "") else _base_token
	if on_hit.is_valid():
		on_hit.call(collider, point, self)
	token = _base_token
	# Fail-closed victim authority, identical to CombatAoe.apply_lethal_blast:
	# only THIS client's own bike may be killed from a direct-hit ray. A remote
	# proxy never receives a lethal call from the shooter's client, even if it
	# later gains a controller-like child.
	var local_uid := str(Supabase.user_id) if Supabase != null else ""
	if is_direct and collider != owner_node and target_id != "" and local_uid != "" \
			and target_id == local_uid:
		var controller: Node = collider.get_node_or_null("CombatController")
		if controller == null or not controller.has_method("take_lethal_hit"):
			for child in collider.get_children():
				if child.has_method("take_lethal_hit"):
					controller = child
					break
		if controller != null and controller.has_method("take_lethal_hit"):
			var lethal_tok := ("%s:v%s" % [_base_token, target_id]) if _base_token != "" else ""
			controller.call("take_lethal_hit", owner_id, point, lethal_tok)
	if not collider.is_in_group("bike") and not collider.is_in_group("hazard"):
		var fx := get_parent() as Node3D
		if fx == null and get_tree() != null:
			fx = get_tree().current_scene as Node3D
		if fx != null:
			VFX.impact(fx, point, hit_color, _direction, "metal")


func _finish() -> void:
	if _done:
		return
	_done = true
	if is_in_group("rocket_beam"):
		remove_from_group("rocket_beam")
	_release_light()
	if not Settings.reduced_motion():
		var fx := get_parent() as Node3D
		if fx == null and get_tree() != null:
			fx = get_tree().current_scene as Node3D
		if fx != null and _beam != null:
			VFX.impact(fx, global_position + _direction * 1.0, hit_color, _direction, "metal")
	if _beam != null:
		_beam.queue_free()
		_beam = null
		_beam_core = null
	queue_free()


func _exit_tree() -> void:
	_release_light()


func _physics_process(delta: float) -> void:
	if _inert or not _armed:
		return
	_age += delta
	if not _beaming:
		if _charge_ring != null:
			var t := clampf(_age / CHARGE_TIME, 0.0, 1.0)
			var s := 0.45 + t * 1.55
			_charge_ring.scale = Vector3(s, s, 1.0)
			if not Settings.reduced_motion():
				_charge_ring.rotation.z += delta * 6.0
		if _age >= CHARGE_TIME:
			_start_beam()
		return
	if _beam != null:
		var t := clampf((_age - CHARGE_TIME) / BEAM_TIME, 0.0, 1.0)
		var mat := _beam.material_override as StandardMaterial3D
		if mat == null:
			mat = _beam_mat.duplicate() as StandardMaterial3D
			_beam.material_override = mat
		mat.albedo_color.a = 0.92 * (1.0 - t)
		if _beam_core != null:
			var cmat := _beam_core.material_override as StandardMaterial3D
			if cmat == null:
				cmat = _beam_core_mat.duplicate() as StandardMaterial3D
				_beam_core.material_override = cmat
			cmat.albedo_color.a = 0.98 * (1.0 - t)
		if is_instance_valid(_light):
			_light.light_energy = 7.2 * (1.0 - t)
	if _age >= CHARGE_TIME + BEAM_TIME:
		_finish()
