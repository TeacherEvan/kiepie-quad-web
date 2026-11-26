extends Node3D
## LEA UNICORN ultimate — UNICORN BOOM.
## She spreads her angelic wings, launches skyward with a hoof shockwave burst,
## soars over the arena leaving an iridescent starlight/rainbow wake while a
## pulsing celestial rune telegraph locks the 7.5 m drop zone, then dives into
## a supernova touchdown impact (incandescent flash, multi-shell plasma/rainbow
## dome, towering 20 m energy sky-pillar, triple staggered Mach ground rings,
## fiery magenta-gold-cyan detonation cloud, starburst streaks, glitter plume,
## scorch crater, radial debris impulse, layered bass+chime audio, camera shake
## & crisp hitstop). Same kill rule as the other 3rd specials:
## CombatAoe.apply_lethal_blast() with fail-closed victim authority and 7.5 m
## zone. Wire kind stays "meteor".

signal impacted(point: Vector3)

const FALL_DURATION := 2.0
const BLAST_RADIUS := 7.5
const APEX_HEIGHT := 8.5
const VFX := preload("res://src/game/VfxFactory.gd")
const COMBAT_AOE := preload("res://src/game/CombatAoe.gd")
const KT := preload("res://src/core/KiepieTime.gd")

var owner_id := ""
var owner_node: Node
var target_pos := Vector3.ZERO
var damage := 105.0
var blast_radius := BLAST_RADIUS
var fall_duration := FALL_DURATION
var token := ""
var hit_color := Color(1.0, 0.55, 0.88)
var visual_style := "unicorn_boom"

var _age := 0.0
var _armed := false
var _detonated := false
var _carrying_owner := false
var _saved_layer := 1
var _saved_mask := 1
var _flight_dir := Vector3.FORWARD
var _start_pos := Vector3.ZERO
var _flight: Node3D = null
var _trail: GPUParticles3D = null
var _star_trail: GPUParticles3D = null
var _telegraph: Node3D = null
var _outer_ring: MeshInstance3D = null
var _countdown_ring: MeshInstance3D = null
var _rune_ring: Node3D = null
var _target_beacon: MeshInstance3D = null
var _light: OmniLight3D = null

static var _body_mesh: CapsuleMesh = null
static var _wing_mesh: BoxMesh = null
static var _horn_mesh: CylinderMesh = null
static var _spark_mesh: SphereMesh = null
static var _spark_ramp: GradientTexture1D = null
static var _star_ramp: GradientTexture1D = null
static var _outer_ring_mesh: TorusMesh = null
static var _countdown_mesh: CylinderMesh = null
static var _rune_seg_mesh: BoxMesh = null
static var _beacon_mesh: CylinderMesh = null
static var _dome_mesh: SphereMesh = null
static var _pillar_mesh: CylinderMesh = null
static var _pillar_core_mesh: CylinderMesh = null


static func _ensure_meshes() -> void:
	if _body_mesh != null:
		return
	var bm := CapsuleMesh.new()
	bm.radius = 0.22
	bm.height = 0.92
	bm.radial_segments = 10
	bm.rings = 5
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.97, 0.96, 0.94)
	bmat.emission_enabled = true
	bmat.emission = Color(0.72, 0.80, 1.0)
	bmat.emission_energy_multiplier = 0.8
	bm.material = bmat
	_body_mesh = bm

	var wm := BoxMesh.new()
	wm.size = Vector3(1.35, 0.03, 0.55)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.85, 0.55, 0.98, 0.92)
	wmat.emission_enabled = true
	wmat.emission = Color(0.68, 0.42, 1.0)
	wmat.emission_energy_multiplier = 2.4
	wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	wmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wm.material = wmat
	_wing_mesh = wm

	var hm := CylinderMesh.new()
	hm.top_radius = 0.001
	hm.bottom_radius = 0.048
	hm.height = 0.44
	hm.radial_segments = 8
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(1.0, 0.86, 0.34)
	hmat.emission_enabled = true
	hmat.emission = Color(1.0, 0.78, 0.24)
	hmat.emission_energy_multiplier = 3.6
	hm.material = hmat
	_horn_mesh = hm

	var sm := SphereMesh.new()
	sm.radius = 0.085
	sm.height = 0.17
	sm.radial_segments = 6
	sm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(1.0, 0.92, 0.98, 0.95)
	smat.emission_enabled = true
	smat.emission = Color(1.0, 0.55, 0.92)
	smat.emission_energy_multiplier = 3.6
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	smat.vertex_color_use_as_albedo = true
	sm.material = smat
	_spark_mesh = sm

	_spark_ramp = VFX._ramp([
		Color(1.0, 0.95, 0.62, 1.0),
		Color(1.0, 0.38, 0.86, 0.92),
		Color(0.58, 0.36, 1.0, 0.72),
		Color(0.32, 0.92, 1.0, 0.0),
	])
	_star_ramp = VFX._ramp([
		Color(1.0, 0.99, 0.86, 1.0),
		Color(1.0, 0.76, 0.32, 0.92),
		Color(1.0, 0.44, 0.90, 0.65),
		Color(0.45, 0.92, 1.0, 0.0),
	])

	var orm := TorusMesh.new()
	orm.inner_radius = 0.94
	orm.outer_radius = 1.0
	orm.rings = 32
	orm.ring_segments = 8
	var ormat := StandardMaterial3D.new()
	ormat.albedo_color = Color(1.0, 0.44, 0.86, 0.78)
	ormat.emission_enabled = true
	ormat.emission = Color(1.0, 0.36, 0.82)
	ormat.emission_energy_multiplier = 3.4
	ormat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ormat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ormat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	orm.material = ormat
	_outer_ring_mesh = orm

	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.035
	cm.radial_segments = 28
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(1.0, 0.82, 0.44, 0.42)
	cmat.emission_enabled = true
	cmat.emission = Color(1.0, 0.56, 0.88)
	cmat.emission_energy_multiplier = 3.8
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cm.material = cmat
	_countdown_mesh = cm

	var rsm := BoxMesh.new()
	rsm.size = Vector3(0.55, 0.035, 0.16)
	var rsmat := StandardMaterial3D.new()
	rsmat.albedo_color = Color(0.52, 0.92, 1.0, 0.90)
	rsmat.emission_enabled = true
	rsmat.emission = Color(1.0, 0.84, 0.38)
	rsmat.emission_energy_multiplier = 4.0
	rsmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rsmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rsmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rsm.material = rsmat
	_rune_seg_mesh = rsm

	var bcm := CylinderMesh.new()
	bcm.top_radius = 0.14
	bcm.bottom_radius = 0.42
	bcm.height = 9.0
	bcm.radial_segments = 12
	var bcmat := StandardMaterial3D.new()
	bcmat.albedo_color = Color(1.0, 0.60, 0.94, 0.24)
	bcmat.emission_enabled = true
	bcmat.emission = Color(1.0, 0.52, 0.92)
	bcmat.emission_energy_multiplier = 3.0
	bcmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bcmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bcmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bcmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bcm.material = bcmat
	_beacon_mesh = bcm

	var dm := SphereMesh.new()
	dm.radius = 1.0
	dm.height = 2.0
	dm.radial_segments = 20
	dm.rings = 10
	_dome_mesh = dm

	var pm := CylinderMesh.new()
	pm.top_radius = 1.55
	pm.bottom_radius = 2.10
	pm.height = 20.0
	pm.radial_segments = 16
	_pillar_mesh = pm

	var pcm := CylinderMesh.new()
	pcm.top_radius = 0.55
	pcm.bottom_radius = 0.85
	pcm.height = 21.0
	pcm.radial_segments = 12
	_pillar_core_mesh = pcm


func setup(p_owner_id: String, p_owner_node: Node, p_target_pos: Vector3,
		p_damage: float, p_token: String, p_color: Color = Color(1.0, 0.55, 0.88),
		p_fall_duration: float = 2.0, p_blast_radius: float = 7.5,
		p_visual_style: String = "unicorn_boom") -> void:
	if not is_finite(p_damage) or not is_finite(p_blast_radius) or p_blast_radius <= 0.0 \
			or not is_finite(p_fall_duration) \
			or not is_finite(p_target_pos.x + p_target_pos.y + p_target_pos.z):
		push_warning("UnicornBoom.setup: rejecting non-finite/invalid strike parameters")
		queue_free()  # callers have already add_child()ed this node
		return
	owner_id = p_owner_id
	owner_node = p_owner_node
	target_pos = p_target_pos
	damage = maxf(0.0, p_damage)
	token = p_token
	hit_color = p_color
	visual_style = p_visual_style if p_visual_style != "" else "unicorn_boom"
	fall_duration = clampf(p_fall_duration, 0.1, 6.0)
	blast_radius = minf(p_blast_radius, 7.5)
	_age = 0.0
	_armed = true
	_detonated = false
	_carrying_owner = false
	_start_pos = (p_owner_node as Node3D).global_position if p_owner_node is Node3D else target_pos
	var flat_delta := Vector3(target_pos.x - _start_pos.x, 0.0, target_pos.z - _start_pos.z)
	if flat_delta.length_squared() > 1e-4:
		_flight_dir = flat_delta.normalized()
	elif p_owner_node is Node3D:
		var fwd := (p_owner_node as Node3D).global_transform.basis.z
		fwd.y = 0.0
		_flight_dir = fwd.normalized() if fwd.length_squared() > 1e-4 else Vector3.FORWARD
	else:
		_flight_dir = Vector3.FORWARD
	global_position = _start_pos
	global_position.y = maxf(0.55, _start_pos.y)
	var model := p_owner_node.get_node_or_null("Model") if is_instance_valid(p_owner_node) else null
	if model != null and model.has_method("trigger_boom"):
		model.call("trigger_boom", fall_duration + 0.15)
	if p_owner_node is VehicleBody3D:
		_begin_owner_flight()
	_ensure_meshes()
	_build_flight()
	_spawn_takeoff_vfx()
	add_to_group("meteor_strike")


func _resolve_fx_parent() -> Node3D:
	var fx := get_parent() as Node3D
	if fx == null and get_tree() != null and get_tree().current_scene is Node3D:
		fx = get_tree().current_scene as Node3D
	return fx


func _spawn_takeoff_vfx() -> void:
	var reduced := Settings.reduced_motion()
	var quality := Settings.quality_multiplier()
	var fx := _resolve_fx_parent()
	if fx == null:
		return
	var takeoff_ground := Vector3(_start_pos.x, maxf(0.0, _start_pos.y) + 0.08, _start_pos.z)
	if not reduced:
		VFX._ring_quad(fx, takeoff_ground, 1.15, Color(1.0, 0.72, 0.96, 0.92), 3.6, 0.36)
		VFX.dust_ring(fx, Vector3(_start_pos.x, maxf(0.0, _start_pos.y), _start_pos.z), 1.05, 4.2)
		VFX.S._flash_billboard(fx, _start_pos + Vector3(0.0, 0.65, 0.0), 2.4, Color(1.0, 0.88, 0.62, 0.95), 0.16)
		if quality > 0.0:
			VFX._particle(fx, _start_pos + Vector3(0.0, 0.35, 0.0),
					maxi(10, int(28 * quality)), 0.58, Vector3.UP, 52.0,
					4.5, 11.5, [
						Color(1.0, 0.96, 0.72, 1.0),
						Color(1.0, 0.44, 0.88, 0.88),
						Color(0.45, 0.90, 1.0, 0.0),
					], 0.24, Vector3(0.0, -5.0, 0.0), true,
					{"tex": "streak", "align": true, "explosiveness": 0.94})
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		if sfx.has_method("play_3d"):
			sfx.call("play_3d", "pickup", _start_pos, 1.2, 1.32)
		elif sfx.has_method("play"):
			sfx.call("play", "pickup", 1.2, 1.32)


func _begin_owner_flight() -> void:
	var bike := owner_node as VehicleBody3D
	if bike == null or not is_instance_valid(bike):
		return
	var combat := bike.get_node_or_null("CombatController")
	if combat != null and "alive" in combat and not bool(combat.get("alive")):
		return
	_carrying_owner = true
	_saved_layer = bike.collision_layer
	_saved_mask = bike.collision_mask
	# Zero wheel forces and disable collision BEFORE freeze=true to avoid VehicleBody3D NaN.
	var wheels_v: Variant = bike.get("_wheels")
	if wheels_v is Dictionary:
		for w in (wheels_v as Dictionary).values():
			if w is VehicleWheel3D and is_instance_valid(w):
				(w as VehicleWheel3D).engine_force = 0.0
				(w as VehicleWheel3D).brake = 0.0
				(w as VehicleWheel3D).steering = 0.0
	bike.collision_layer = 0
	bike.collision_mask = 0
	bike.linear_velocity = Vector3.ZERO
	bike.angular_velocity = Vector3.ZERO
	if bike.get_rid().is_valid():
		PhysicsServer3D.body_set_state(bike.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(bike.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	bike.set_physics_process(false)
	bike.freeze = true


func _end_owner_flight(land_at_target: bool) -> void:
	if not _carrying_owner:
		return
	_carrying_owner = false
	var bike := owner_node as VehicleBody3D
	if bike == null or not is_instance_valid(bike):
		return
	var combat := bike.get_node_or_null("CombatController")
	if combat != null and "alive" in combat and not bool(combat.get("alive")):
		return
	var land_pos := Vector3(target_pos.x, maxf(0.0, target_pos.y) + 0.55, target_pos.z) \
			if land_at_target else Vector3(bike.global_position.x, maxf(0.55, bike.global_position.y), bike.global_position.z)
	var fwd := _flight_dir
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-4 else Vector3.FORWARD
	var land_basis := Basis.looking_at(-fwd, Vector3.UP).orthonormalized()
	var land_xf := Transform3D(land_basis, land_pos)
	bike.global_transform = land_xf
	bike.linear_velocity = Vector3.ZERO
	bike.angular_velocity = Vector3.ZERO
	if bike.get_rid().is_valid():
		PhysicsServer3D.body_set_state(bike.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, land_xf)
		PhysicsServer3D.body_set_state(bike.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(bike.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(bike.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, false)
	# Unfreeze BEFORE re-enabling collision so VehicleBody3D never steps frozen with active contacts.
	bike.freeze = false
	bike.collision_layer = _saved_layer
	bike.collision_mask = _saved_mask
	bike.set_physics_process(true)
	var tree := get_tree()
	if tree != null:
		var cam := tree.get_first_node_in_group("camera_rig")
		if cam != null and cam.has_method("snap_to_target"):
			cam.call_deferred("snap_to_target")


func _build_flight() -> void:
	var fx := _resolve_fx_parent()
	if fx != null:
		_telegraph = Node3D.new()
		_telegraph.name = "BoomTelegraph"
		_telegraph.position = Vector3(target_pos.x, maxf(0.0, target_pos.y) + 0.05, target_pos.z)
		fx.add_child(_telegraph)

		_outer_ring = MeshInstance3D.new()
		_outer_ring.name = "OuterRing"
		_outer_ring.mesh = _outer_ring_mesh
		_outer_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_outer_ring.scale = Vector3(blast_radius, 1.0, blast_radius)
		_telegraph.add_child(_outer_ring)

		_countdown_ring = MeshInstance3D.new()
		_countdown_ring.name = "CountdownRing"
		_countdown_ring.mesh = _countdown_mesh
		_countdown_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_countdown_ring.position.y = 0.03
		_countdown_ring.scale = Vector3(blast_radius * 0.94, 1.0, blast_radius * 0.94)
		_telegraph.add_child(_countdown_ring)

		_rune_ring = Node3D.new()
		_rune_ring.name = "RuneRing"
		_rune_ring.position.y = 0.06
		_telegraph.add_child(_rune_ring)
		for ri in range(8):
			var seg := MeshInstance3D.new()
			seg.mesh = _rune_seg_mesh
			seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var ang := TAU * float(ri) / 8.0
			var r_rad := blast_radius * 0.62
			seg.position = Vector3(sin(ang) * r_rad, 0.0, cos(ang) * r_rad)
			seg.rotation.y = ang
			_rune_ring.add_child(seg)

		_target_beacon = MeshInstance3D.new()
		_target_beacon.name = "TargetBeacon"
		_target_beacon.mesh = _beacon_mesh
		_target_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_target_beacon.position.y = 4.5
		_telegraph.add_child(_target_beacon)

	# Only spawn a fallback proxy glider when there is no real unicorn owner_node;
	# when owner_node exists, the actual Lea Unicorn flies through the air!
	if not is_instance_valid(owner_node):
		_flight = Node3D.new()
		_flight.name = "FlightUnicorn"
		add_child(_flight)
		var body := MeshInstance3D.new()
		body.name = "FlightBody"
		body.mesh = _body_mesh
		body.rotation_degrees.x = 90.0
		_flight.add_child(body)
		for side in [-1.0, 1.0]:
			var wing := MeshInstance3D.new()
			wing.name = "FlightWing%s" % ("L" if side > 0.0 else "R")
			wing.mesh = _wing_mesh
			wing.position = Vector3(side * 0.68, 0.10, -0.08)
			wing.rotation_degrees.z = side * -12.0
			_flight.add_child(wing)
		var horn := MeshInstance3D.new()
		horn.name = "FlightHorn"
		horn.mesh = _horn_mesh
		horn.rotation_degrees.x = -90.0
		horn.position = Vector3(0.0, 0.02, -0.72)
		_flight.add_child(horn)

	if not Settings.reduced_motion() and Settings.quality_multiplier() > 0.0:
		var q := Settings.quality_multiplier()
		_trail = GPUParticles3D.new()
		_trail.name = "RainbowTrail"
		_trail.amount = maxi(14, int(52 * q))
		_trail.lifetime = 0.68
		_trail.local_coords = false
		_trail.visibility_aabb = AABB(Vector3(-14.0, -12.0, -14.0), Vector3(28.0, 26.0, 28.0))
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3.UP
		pm.spread = 42.0
		pm.gravity = Vector3(0.0, -1.2, 0.0)
		pm.initial_velocity_min = 0.5
		pm.initial_velocity_max = 2.4
		pm.scale_min = 0.35
		pm.scale_max = 1.15
		pm.hue_variation_min = -0.14
		pm.hue_variation_max = 0.14
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.45
		pm.color_ramp = _spark_ramp
		_trail.process_material = pm
		_trail.draw_pass_1 = _spark_mesh
		add_child(_trail)
		_trail.emitting = true

		_star_trail = GPUParticles3D.new()
		_star_trail.name = "StarlightWake"
		_star_trail.amount = maxi(10, int(36 * q))
		_star_trail.lifetime = 0.78
		_star_trail.local_coords = false
		_star_trail.visibility_aabb = AABB(Vector3(-14.0, -12.0, -14.0), Vector3(28.0, 26.0, 28.0))
		var spm := ParticleProcessMaterial.new()
		spm.direction = Vector3.UP
		spm.spread = 65.0
		spm.gravity = Vector3(0.0, 0.4, 0.0)
		spm.initial_velocity_min = 0.8
		spm.initial_velocity_max = 3.2
		spm.scale_min = 0.30
		spm.scale_max = 0.95
		spm.hue_variation_min = -0.18
		spm.hue_variation_max = 0.18
		spm.color_ramp = _star_ramp
		_star_trail.process_material = spm
		_star_trail.draw_pass_1 = VFX._sprite_quad(true, "flare", 0.52)
		add_child(_star_trail)
		_star_trail.emitting = true

	if Settings.quality_multiplier() >= 0.5:
		_light = OmniLight3D.new()
		_light.name = "BoomLight"
		_light.light_color = Color(1.0, 0.56, 0.90)
		_light.light_energy = 3.4
		_light.omni_range = 7.5
		_light.add_to_group("vfx_light")
		add_child(_light)
		VFX._cap_group(self, "vfx_light", VFX.MAX_IMPACT_LIGHTS)


func _release_light() -> void:
	if is_instance_valid(_light):
		if _light.is_in_group("vfx_light"):
			_light.remove_from_group("vfx_light")
		_light.queue_free()
	_light = null


func _release_telegraph() -> void:
	if is_instance_valid(_telegraph):
		_telegraph.queue_free()
	_telegraph = null
	_outer_ring = null
	_countdown_ring = null
	_rune_ring = null
	_target_beacon = null


func _exit_tree() -> void:
	if not _detonated:
		var model := owner_node.get_node_or_null("Model") if is_instance_valid(owner_node) else null
		if model != null and model.has_method("on_boom_land"):
			model.call("on_boom_land")
	_end_owner_flight(false)
	_release_light()
	_release_telegraph()


func _physics_process(delta: float) -> void:
	if not _armed or _detonated:
		return
	_age += delta
	var t := clampf(_age / fall_duration, 0.0, 1.0)
	var reduced := Settings.reduced_motion()
	# Heroic swift takeoff -> soaring apex -> accelerating diving plunge into target_pos.
	var t_smooth := t * t * (3.0 - 2.0 * t)
	var t_horiz := lerpf(t_smooth, pow(t, 1.18), 0.38)
	var flat := _start_pos.lerp(target_pos, t_horiz)
	var arc := sin(pow(t, 0.82) * PI) * APEX_HEIGHT
	var y := lerpf(maxf(0.55, _start_pos.y), maxf(0.0, target_pos.y) + 0.55, t) + arc
	var next := Vector3(flat.x, y, flat.z)
	var dir := next - global_position
	if dir.length_squared() > 1e-6:
		global_position = next
		var dn := dir.normalized()
		if _carrying_owner:
			var bike := owner_node as VehicleBody3D
			if not is_instance_valid(bike):
				_carrying_owner = false
			else:
				var combat := bike.get_node_or_null("CombatController")
				if combat != null and "alive" in combat and not bool(combat.get("alive")):
					_carrying_owner = false
				else:
					var horiz := Vector3(dn.x, 0.0, dn.z)
					var fwd_h := horiz.normalized() if horiz.length_squared() > 1e-4 else _flight_dir
					var pitch_y := clampf(dn.y, -0.78, 0.72)
					var orient_dir := (fwd_h + Vector3(0.0, pitch_y, 0.0)).normalized()
					# VehicleBody3D / Lea_Unicorn.glb faces +Z forward: Basis.looking_at(-dir) aims +Z along orient_dir.
					var xf := Transform3D(Basis.looking_at(-orient_dir, Vector3.UP).orthonormalized(), next)
					bike.global_transform = xf
					if bike.get_rid().is_valid():
						PhysicsServer3D.body_set_state(bike.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
		if _flight != null:
			var up := Vector3.UP if absf(dn.y) < 0.99 else Vector3.FORWARD
			_flight.basis = Basis.looking_at(dn, up)
			var flap := 1.0 + 0.30 * sin(_age * 15.0)
			for wing in _flight.get_children():
				if str(wing.name).begins_with("FlightWing"):
					(wing as Node3D).scale.y = flap

	if is_instance_valid(_light):
		var dive_boost := clampf((t - 0.62) / 0.38, 0.0, 1.0)
		_light.light_energy = lerpf(3.4, 8.2, dive_boost)
		_light.omni_range = lerpf(7.5, 13.0, dive_boost)

	if is_instance_valid(_telegraph):
		if is_instance_valid(_outer_ring):
			var pulse := 1.0 if reduced else (1.0 + 0.045 * sin(_age * 16.0))
			_outer_ring.scale = Vector3(blast_radius * pulse, 1.0, blast_radius * pulse)
		if is_instance_valid(_countdown_ring):
			var cr := lerpf(blast_radius * 0.94, 0.45, t)
			_countdown_ring.scale = Vector3(cr, 1.0, cr)
		if is_instance_valid(_rune_ring) and not reduced:
			_rune_ring.rotation.y += delta * (1.8 + t * 5.2)
		if is_instance_valid(_target_beacon):
			var bw := lerpf(1.25, 0.22, t)
			_target_beacon.scale = Vector3(bw, 1.0, bw)

	if t >= 1.0:
		_detonate()


func _detonate() -> void:
	if _detonated:
		return
	_detonated = true
	_end_owner_flight(true)
	var model := owner_node.get_node_or_null("Model") if is_instance_valid(owner_node) else null
	if model != null and model.has_method("on_boom_land"):
		model.call("on_boom_land")
	if is_in_group("meteor_strike"):
		remove_from_group("meteor_strike")
	_release_light()
	_release_telegraph()
	if is_instance_valid(_trail):
		_trail.emitting = false
	if is_instance_valid(_star_trail):
		_star_trail.emitting = false

	var reduced := Settings.reduced_motion()
	var quality := Settings.quality_multiplier()
	var fx := _resolve_fx_parent()
	if fx != null:
		_spawn_impact_vfx(fx, target_pos, blast_radius, reduced, quality)
		# Radial blast impulse on nearby loose RigidBody3D debris.
		var blast_r := blast_radius * 1.5
		var blast_r_sq := blast_r * blast_r
		for ch in fx.get_children():
			if ch is RigidBody3D and not (ch is VehicleBody3D):
				var rb := ch as RigidBody3D
				var diff := rb.global_position - target_pos
				var d2 := diff.length_squared()
				if d2 <= blast_r_sq and d2 > 1e-4:
					var dir := (diff.normalized() + Vector3(0.0, 0.62, 0.0)).normalized()
					rb.apply_central_impulse(dir * (22.0 * (1.0 - sqrt(d2) / blast_r)))

	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		if sfx.has_method("play_3d"):
			# Heavy layered touchdown bang: sub-bass boom + crack + crunch + twin celestial chimes.
			sfx.call("play_3d", "explosion", target_pos, 6.5, 0.40)
			sfx.call("play_3d", "explosion", target_pos, 4.2, 0.94)
			sfx.call("play_3d", "impact", target_pos, 3.0, 0.56)
			sfx.call("play_3d", "pickup", target_pos, 2.2, 1.42)
			sfx.call("play_3d", "pickup", target_pos, 1.5, 1.85)
		elif sfx.has_method("play"):
			sfx.call("play", "explosion", 6.5, 0.40)
			sfx.call("play", "explosion", 4.2, 0.94)
			sfx.call("play", "pickup", 2.2, 1.42)

	var cam := get_tree().get_first_node_in_group("camera_rig") if get_tree() != null else null
	if cam != null and cam.has_method("add_shake"):
		var cam_dist := (cam as Node3D).global_position.distance_to(target_pos) if cam is Node3D else 0.0
		cam.call("add_shake", 1.45 * clampf(1.0 - cam_dist / 90.0, 0.25, 1.0))

	if not reduced and get_tree() != null:
		KT.trigger_hitstop(get_tree(), 0.20, 0.070)

	impacted.emit(target_pos)
	var tree := get_tree()
	if tree == null:
		queue_free()
		return
	COMBAT_AOE.apply_lethal_blast(tree, fx, target_pos, blast_radius,
			owner_id, owner_node, token, true)
	if not reduced and _flight != null:
		_flight.visible = false
	var kill_tween := create_tween()
	kill_tween.tween_interval(0.14)
	kill_tween.tween_callback(queue_free)


static func _spawn_impact_vfx(fx: Node3D, p_target_pos: Vector3, p_blast_radius: float,
		reduced: bool, quality: float) -> void:
	## Static so tween cleanup lambdas never bind to the short-lived UnicornBoom
	## instance (which frees at 0.14 s while impact lights & rings live ~0.72 s).
	_ensure_meshes()
	var ground_y := maxf(0.0, p_target_pos.y)
	var ground_pos := Vector3(p_target_pos.x, ground_y + 0.06, p_target_pos.z)
	VFX.scorch(fx, ground_pos, 2.55)

	if reduced:
		VFX._static_cue(fx, Vector3(p_target_pos.x, ground_y + 0.45, p_target_pos.z),
				Color(1.0, 0.46, 0.86), p_blast_radius * 0.95, 0.28)
		VFX._static_cue(fx, Vector3(p_target_pos.x, ground_y + 0.60, p_target_pos.z),
				Color(1.0, 0.94, 0.72), p_blast_radius * 0.45, 0.22)
		if quality >= 0.5:
			var rlight := OmniLight3D.new()
			rlight.name = "BoomImpactLight"
			rlight.light_color = Color(1.0, 0.64, 0.92)
			rlight.light_energy = 10.0
			rlight.omni_range = 16.0
			rlight.position = Vector3(p_target_pos.x, ground_y + 1.8, p_target_pos.z)
			rlight.add_to_group("vfx_light")
			fx.add_child(rlight)
			VFX._cap_group(fx, "vfx_light", VFX.MAX_IMPACT_LIGHTS)
			var w_rlight: WeakRef = weakref(rlight)
			var rlt := rlight.create_tween()
			rlt.tween_interval(0.28)
			rlt.tween_callback(func() -> void:
				var rl := w_rlight.get_ref() as Node
				if rl != null:
					if rl.is_in_group("vfx_light"):
						rl.remove_from_group("vfx_light")
					rl.queue_free())
		return

	# 1. Dynamic supernova impact light (vfx_light capped & auto-cleaned).
	if quality >= 0.5:
		var imp_light := OmniLight3D.new()
		imp_light.name = "BoomImpactLight"
		imp_light.light_color = Color(1.0, 0.72, 0.94)
		imp_light.light_energy = 52.0
		imp_light.omni_range = 30.0
		imp_light.position = Vector3(p_target_pos.x, ground_y + 2.0, p_target_pos.z)
		imp_light.add_to_group("vfx_light")
		fx.add_child(imp_light)
		VFX._cap_group(fx, "vfx_light", VFX.MAX_IMPACT_LIGHTS)
		var w_light: WeakRef = weakref(imp_light)
		var lt := imp_light.create_tween()
		lt.tween_property(imp_light, "light_color", Color(1.0, 0.42, 0.84), 0.24)
		lt.parallel().tween_property(imp_light, "light_energy", 18.0, 0.24)
		lt.tween_property(imp_light, "light_energy", 0.0, 0.48)
		lt.tween_callback(func() -> void:
			var l := w_light.get_ref() as Node
			if l != null:
				if l.is_in_group("vfx_light"):
					l.remove_from_group("vfx_light")
				l.queue_free())

	# 2. Blinding incandescent supernova core flash (billboards + 3D white-hot core).
	VFX.S._flash_billboard(fx, Vector3(p_target_pos.x, ground_y + 0.95, p_target_pos.z),
			6.4, Color(1.0, 0.98, 0.88, 1.0), 0.22)
	VFX.S._flash_billboard(fx, Vector3(p_target_pos.x, ground_y + 1.25, p_target_pos.z),
			8.8, Color(1.0, 0.44, 0.88, 0.94), 0.34)
	var core_mat := VFX._additive(Color(1.0, 0.98, 0.88, 0.98), 6.2)
	core_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var core := MeshInstance3D.new()
	core.name = "BoomCoreFlash"
	core.mesh = _dome_mesh
	core.material_override = core_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.position = Vector3(p_target_pos.x, ground_y + 0.55, p_target_pos.z)
	core.scale = Vector3.ONE * 0.55
	fx.add_child(core)
	var ct := core.create_tween()
	ct.tween_property(core, "scale", Vector3.ONE * (p_blast_radius * 0.56), 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	ct.parallel().tween_property(core_mat, "albedo_color", Color(1.0, 0.84, 0.40, 0.0), 0.22)
	ct.tween_callback(core.queue_free)

	# 3. Volumetric expanding multi-shell plasma / rainbow shockwave dome.
	var dome_mat := VFX._additive(Color(1.0, 0.86, 0.56, 0.90), 3.8)
	dome_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dome := MeshInstance3D.new()
	dome.name = "BoomShockwaveDome"
	dome.mesh = _dome_mesh
	dome.material_override = dome_mat
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dome.position = Vector3(p_target_pos.x, ground_y + 0.25, p_target_pos.z)
	dome.scale = Vector3.ONE * 0.65
	fx.add_child(dome)
	var dt := dome.create_tween()
	dt.tween_property(dome, "scale", Vector3.ONE * (p_blast_radius * 1.25), 0.42).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	dt.parallel().tween_property(dome_mat, "albedo_color", Color(1.0, 0.32, 0.84, 0.0), 0.42)
	dt.tween_callback(dome.queue_free)

	var shell_mat := VFX._additive(Color(0.42, 0.92, 1.0, 0.78), 3.4)
	shell_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shell := MeshInstance3D.new()
	shell.name = "BoomRainbowShell"
	shell.mesh = _dome_mesh
	shell.material_override = shell_mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.position = Vector3(p_target_pos.x, ground_y + 0.30, p_target_pos.z)
	shell.scale = Vector3.ONE * 0.40
	fx.add_child(shell)
	var st := shell.create_tween()
	st.tween_property(shell, "scale", Vector3.ONE * (p_blast_radius * 1.02), 0.52).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	st.parallel().tween_property(shell_mat, "albedo_color", Color(0.66, 0.30, 1.0, 0.0), 0.52)
	st.tween_callback(shell.queue_free)

	# 4. Towering 20 m radiant energy sky-pillar + incandescent core shaft.
	var pil_mat := VFX._additive(Color(1.0, 0.52, 0.90, 0.90), 3.8)
	pil_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pillar := MeshInstance3D.new()
	pillar.name = "BoomSkyPillar"
	pillar.mesh = _pillar_mesh
	pillar.material_override = pil_mat
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pillar.position = Vector3(p_target_pos.x, ground_y + 10.0, p_target_pos.z)
	pillar.scale = Vector3(1.55, 1.0, 1.55)
	fx.add_child(pillar)
	var pt := pillar.create_tween()
	pt.tween_property(pillar, "scale", Vector3(0.12, 1.12, 0.12), 0.60).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pt.parallel().tween_property(pil_mat, "albedo_color", Color(1.0, 0.86, 0.42, 0.0), 0.60)
	pt.tween_callback(pillar.queue_free)

	var pcore_mat := VFX._additive(Color(1.0, 0.98, 0.86, 0.96), 6.0)
	pcore_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pcore := MeshInstance3D.new()
	pcore.name = "BoomSkyPillarCore"
	pcore.mesh = _pillar_core_mesh
	pcore.material_override = pcore_mat
	pcore.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pcore.position = Vector3(p_target_pos.x, ground_y + 10.5, p_target_pos.z)
	pcore.scale = Vector3(1.25, 1.0, 1.25)
	fx.add_child(pcore)
	var pct := pcore.create_tween()
	pct.tween_property(pcore, "scale", Vector3(0.06, 1.15, 0.06), 0.44).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	pct.parallel().tween_property(pcore_mat, "albedo_color", Color(0.55, 0.92, 1.0, 0.0), 0.44)
	pct.tween_callback(pcore.queue_free)

	# 5. Three staggered Mach ground shockwave rings + elevated sky-pillar halo.
	VFX._ring_quad(fx, ground_pos, p_blast_radius * 0.48,
			Color(1.0, 0.96, 0.74, 0.98), 2.55, 0.30)
	var ring_pos2 := Vector3(p_target_pos.x, ground_y + 0.16, p_target_pos.z)
	var ring_pos3 := Vector3(p_target_pos.x, ground_y + 0.24, p_target_pos.z)
	var halo_pos := Vector3(p_target_pos.x, ground_y + 3.4, p_target_pos.z)
	var w_fx: WeakRef = weakref(fx)
	var rt := fx.create_tween()
	rt.tween_interval(0.05)
	rt.tween_callback(func() -> void:
		var p := w_fx.get_ref() as Node3D
		if p != null and p.is_inside_tree():
			VFX._ring_quad(p, ring_pos2, p_blast_radius * 0.72, Color(1.0, 0.38, 0.84, 0.95), 2.35, 0.50)
			VFX._ring_quad(p, halo_pos, p_blast_radius * 0.38, Color(0.95, 0.88, 1.0, 0.80), 2.8, 0.46))
	rt.tween_interval(0.06)
	rt.tween_callback(func() -> void:
		var p := w_fx.get_ref() as Node3D
		if p != null and p.is_inside_tree():
			VFX._ring_quad(p, ring_pos3, p_blast_radius * 0.96, Color(0.42, 0.92, 1.0, 0.90), 2.25, 0.72))

	if quality > 0.0:
		var blast_aabb := AABB(Vector3(-16.0, -4.0, -16.0), Vector3(32.0, 26.0, 32.0))
		# 6a. Daylight-readable alpha-blended magenta-gold-violet fireball billows.
		VFX._particle(fx, Vector3(p_target_pos.x, ground_y + 0.35, p_target_pos.z),
				maxi(24, int(68 * quality)), 1.05, Vector3.UP, 66.0,
				3.2, 11.5, [
					Color(1.0, 0.90, 0.52, 0.98),
					Color(1.0, 0.34, 0.80, 0.92),
					Color(0.46, 0.16, 0.68, 0.68),
					Color(0.14, 0.10, 0.22, 0.0),
				], 1.45, Vector3(0.0, 2.4, 0.0), false,
				{"tex": "fire", "quad": 1.25, "curve": [[0, 0.45], [0.28, 1.45], [0.75, 1.15], [1, 0.25]],
				 "hue": 0.06, "damping": 2.9, "angular": 2.8, "explosiveness": 0.96, "aabb": blast_aabb})
		# 6b. Incandescent additive plasma heart burning inside the detonation.
		VFX._particle(fx, Vector3(p_target_pos.x, ground_y + 0.42, p_target_pos.z),
				maxi(20, int(54 * quality)), 0.72, Vector3.UP, 70.0,
				4.5, 15.0, [
					Color(1.0, 0.98, 0.82, 1.0),
					Color(1.0, 0.44, 0.88, 0.94),
					Color(0.42, 0.90, 1.0, 0.0),
				], 1.12, Vector3(0.0, -2.5, 0.0), true,
				{"tex": "fire", "quad": 0.96, "curve": [[0, 0.50], [0.26, 1.40], [1, 0.08]],
				 "hue": 0.08, "damping": 2.6, "angular": 3.4, "explosiveness": 0.98, "aabb": blast_aabb})
		# 7. 360-degree ground dust blast wave anchoring the shock to the arena floor.
		VFX._particle(fx, Vector3(p_target_pos.x, ground_y + 0.22, p_target_pos.z),
				maxi(18, int(48 * quality)), 1.38, Vector3(0.0, 0.16, 1.0), 89.0,
				7.5, 17.0, [
					Color(0.78, 0.62, 0.82, 0.84),
					Color(0.38, 0.30, 0.46, 0.50),
					Color(0.18, 0.16, 0.22, 0.0),
				], 1.50, Vector3(0.0, 0.65, 0.0), false,
				{"tex": "smoke", "quad": 1.42, "curve": [[0, 0.42], [0.35, 1.25], [1, 2.05]],
				 "damping": 2.3, "angular": 2.2, "explosiveness": 0.97, "aabb": blast_aabb})
		# 8. High-velocity radial starburst streaks.
		VFX._particle(fx, Vector3(p_target_pos.x, ground_y + 0.45, p_target_pos.z),
				maxi(24, int(68 * quality)), 1.05, Vector3.UP, 86.0,
				13.0, 30.0, [
					Color(1.0, 0.98, 0.78, 1.0),
					Color(1.0, 0.46, 0.88, 0.94),
					Color(0.45, 0.92, 1.0, 0.0),
				], 0.28, Vector3(0.0, -11.5, 0.0), true,
				{"tex": "streak", "align": true, "curve": [[0, 1.0], [0.55, 0.85], [1, 0.0]],
				 "hue": 0.10, "explosiveness": 0.98, "aabb": blast_aabb})
		# 9. Rising iridescent rainbow glitter plume.
		VFX._particle(fx, Vector3(p_target_pos.x, ground_y + 0.50, p_target_pos.z),
				maxi(16, int(44 * quality)), 1.65, Vector3.UP, 46.0,
				2.8, 9.5, [
					Color(1.0, 0.92, 0.52, 1.0),
					Color(1.0, 0.48, 0.90, 0.84),
					Color(0.50, 0.92, 1.0, 0.0),
				], 0.30, Vector3(0.0, 1.8, 0.0), true,
				{"tex": "flare", "quad": 0.54, "curve": [[0, 0.65], [0.40, 1.15], [1, 0.0]],
				 "hue": 0.14, "damping": 0.65, "explosiveness": 0.82, "aabb": blast_aabb})
