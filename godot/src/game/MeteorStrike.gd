extends Node3D
## Meteor Shower strike: locks a glowing target warning zone on the ground at
## the aimed position while a flaming meteor boulder falls from the sky for
## exactly 2.0 seconds before impacting with massive AOE damage (6.0s cooldown).

signal impacted(point: Vector3)

const FALL_DURATION := 2.0
const BLAST_RADIUS := 7.5
const SKY_HEIGHT := 36.0
const VFX := preload("res://src/game/VfxFactory.gd")
const COMBAT_AOE := preload("res://src/game/CombatAoe.gd")

var owner_id := ""
var owner_node: Node
var target_pos := Vector3.ZERO
var sky_origin := Vector3.ZERO
var damage := 105.0
var blast_radius := BLAST_RADIUS
var fall_duration := FALL_DURATION
var token := ""
var hit_color := Color(1.0, 0.28, 0.06)
var visual_style := "meteor"

var _age := 0.0
var _armed := false
var _detonated := false
var _boulder: Node3D
var _outer_ring: MeshInstance3D
var _inner_ring: MeshInstance3D
var _ion_shaft: MeshInstance3D
var _trail: GPUParticles3D
var _light: OmniLight3D

static var _boulder_mesh: SphereMesh = null
static var _core_mesh: SphereMesh = null
static var _ring_mesh: CylinderMesh = null
static var _disc_mesh: CylinderMesh = null
static var _trail_mesh: SphereMesh = null
static var _trail_ramp: GradientTexture1D = null
static var _cloud_mesh: CylinderMesh = null
static var _shaft_mesh: CylinderMesh = null


static func _ensure_meshes() -> void:
	if _boulder_mesh == null:
		var sm := SphereMesh.new()
		sm.radius = 1.25
		sm.height = 2.40
		sm.radial_segments = 10
		sm.rings = 6
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.28, 0.12, 0.06)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.34, 0.05)
		mat.emission_energy_multiplier = 3.6
		mat.roughness = 0.85
		sm.material = mat
		_boulder_mesh = sm
	if _core_mesh == null:
		var cm := SphereMesh.new()
		cm.radius = 1.42
		cm.height = 2.84
		cm.radial_segments = 10
		cm.rings = 6
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(1.0, 0.52, 0.12, 0.36)
		cmat.emission_enabled = true
		cmat.emission = Color(1.0, 0.45, 0.08)
		cmat.emission_energy_multiplier = 4.2
		cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		cm.material = cmat
		_core_mesh = cm
	if _ring_mesh == null:
		var rm := CylinderMesh.new()
		rm.top_radius = 1.0
		rm.bottom_radius = 1.0
		rm.height = 0.04
		rm.radial_segments = 28
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(1.0, 0.24, 0.06, 0.42)
		rmat.emission_enabled = true
		rmat.emission = Color(1.0, 0.28, 0.05)
		rmat.emission_energy_multiplier = 3.2
		rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		rm.material = rmat
		_ring_mesh = rm
	if _disc_mesh == null:
		var dm := CylinderMesh.new()
		dm.top_radius = 1.0
		dm.bottom_radius = 1.0
		dm.height = 0.05
		dm.radial_segments = 24
		var dmat := StandardMaterial3D.new()
		dmat.albedo_color = Color(1.0, 0.72, 0.18, 0.55)
		dmat.emission_enabled = true
		dmat.emission = Color(1.0, 0.65, 0.12)
		dmat.emission_energy_multiplier = 4.5
		dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		dm.material = dmat
		_disc_mesh = dm
	if _trail_mesh == null:
		var tm := SphereMesh.new()
		tm.radius = 0.42
		tm.height = 0.84
		tm.radial_segments = 6
		tm.rings = 4
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color(1.0, 0.48, 0.12, 0.9)
		tmat.emission_enabled = true
		tmat.emission = Color(1.0, 0.36, 0.06)
		tmat.emission_energy_multiplier = 3.4
		tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		tm.material = tmat
		_trail_mesh = tm
	if _trail_ramp == null:
		_trail_ramp = VFX._ramp([
			Color(1.0, 0.94, 0.62, 0.98),
			Color(1.0, 0.38, 0.08, 0.78),
			Color(0.22, 0.14, 0.12, 0.0),
		])
	if _cloud_mesh == null:
		var cm2 := CylinderMesh.new()
		cm2.top_radius = 5.5
		cm2.bottom_radius = 3.2
		cm2.height = 2.2
		cm2.radial_segments = 16
		var cmat2 := StandardMaterial3D.new()
		cmat2.albedo_color = Color(0.14, 0.20, 0.30, 0.88)
		cmat2.emission_enabled = true
		cmat2.emission = Color(0.28, 0.72, 1.0)
		cmat2.emission_energy_multiplier = 1.8
		cmat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cm2.material = cmat2
		_cloud_mesh = cm2
	if _shaft_mesh == null:
		var sm2 := CylinderMesh.new()
		sm2.top_radius = 0.65
		sm2.bottom_radius = 0.22
		sm2.height = 32.0
		sm2.radial_segments = 10
		sm2.material = VFX._additive(Color(0.45, 0.88, 1.0, 0.35), 3.2)
		_shaft_mesh = sm2


func setup(p_owner_id: String, p_owner_node: Node, p_target_pos: Vector3,
		p_damage: float, p_token: String, p_color: Color = Color(1.0, 0.28, 0.06),
		p_fall_duration: float = FALL_DURATION, p_blast_radius: float = BLAST_RADIUS,
		p_visual_style: String = "meteor") -> void:
	owner_id = p_owner_id
	owner_node = p_owner_node
	target_pos = p_target_pos
	damage = p_damage
	token = p_token
	hit_color = p_color
	visual_style = p_visual_style if p_visual_style in ["meteor", "lightning", "cash_bag"] else "meteor"
	fall_duration = maxf(0.1, p_fall_duration)
	blast_radius = p_blast_radius
	global_position = target_pos
	sky_origin = target_pos + Vector3(3.8, SKY_HEIGHT, -3.8)
	_age = 0.0
	_armed = true
	_detonated = false
	add_to_group("meteor_strike")
	_build_visual()


func _build_visual() -> void:
	_ensure_meshes()
	# Ground target danger ring + shrinking countdown core
	_outer_ring = MeshInstance3D.new()
	_outer_ring.name = "WarningRing"
	_outer_ring.mesh = _ring_mesh
	_outer_ring.position = Vector3(0.0, 0.06, 0.0)
	_outer_ring.scale = Vector3(blast_radius, 1.0, blast_radius)
	add_child(_outer_ring)

	_inner_ring = MeshInstance3D.new()
	_inner_ring.name = "CountdownRing"
	_inner_ring.mesh = _disc_mesh
	_inner_ring.position = Vector3(0.0, 0.08, 0.0)
	_inner_ring.scale = Vector3(blast_radius * 0.95, 1.0, blast_radius * 0.95)
	add_child(_inner_ring)

	if visual_style == "lightning":
		_outer_ring.material_override = VFX._additive(Color(0.32, 0.85, 1.0, 0.48), 3.6)
		_inner_ring.material_override = VFX._additive(Color(0.85, 0.97, 1.0, 0.60), 4.5)
	elif visual_style == "cash_bag":
		_outer_ring.material_override = VFX._additive(Color(0.18, 0.88, 0.42, 0.46), 3.4)
		_inner_ring.material_override = VFX._additive(Color(1.0, 0.84, 0.22, 0.58), 4.2)

	if visual_style == "lightning":
		# Overhead Storm Vortex Cloud at y+32m with narrowing ionized shaft
		_boulder = Node3D.new()
		_boulder.name = "StormVortex"
		add_child(_boulder)
		_boulder.position = Vector3(0.0, 32.0, 0.0)

		var cloud := MeshInstance3D.new()
		cloud.mesh = _cloud_mesh
		_boulder.add_child(cloud)

		_ion_shaft = MeshInstance3D.new()
		_ion_shaft.mesh = _shaft_mesh
		_ion_shaft.position = Vector3(0.0, 16.0, 0.0)
		add_child(_ion_shaft)

		if Settings.quality_multiplier() >= 0.5:
			_light = OmniLight3D.new()
			_light.light_color = Color(0.45, 0.88, 1.0)
			_light.light_energy = 5.5
			_light.omni_range = 14.0
			_light.add_to_group("vfx_light")
			_boulder.add_child(_light)
			VFX._cap_group(_boulder, "vfx_light", VFX.MAX_IMPACT_LIGHTS)

		if not Settings.reduced_motion() and Settings.quality_multiplier() > 0.0:
			_trail = GPUParticles3D.new()
			_trail.amount = maxi(8, int(36 * Settings.quality_multiplier()))
			_trail.lifetime = 0.65
			_trail.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 36, 12))
			var pm := ParticleProcessMaterial.new()
			pm.direction = Vector3.UP
			pm.spread = 14.0
			pm.initial_velocity_min = 6.0
			pm.initial_velocity_max = 14.0
			pm.scale_min = 0.2
			pm.scale_max = 0.45
			pm.color_ramp = VFX._ramp([
				Color(0.90, 0.98, 1.0, 0.95),
				Color(0.32, 0.82, 1.0, 0.70),
				Color(0.35, 0.35, 0.95, 0.0),
			])
			_trail.process_material = pm
			_trail.draw_pass_1 = VFX._sprite_quad(true, "streak", 0.35)
			add_child(_trail)
			_trail.emitting = true
	elif visual_style == "cash_bag":
		_boulder = CashBagVisual.build_bag(4.6)
		add_child(_boulder)
		_boulder.global_position = sky_origin

		if Settings.quality_multiplier() >= 0.5:
			_light = OmniLight3D.new()
			_light.light_color = Color(0.95, 0.84, 0.24)
			_light.light_energy = 7.0
			_light.omni_range = 12.0
			_light.add_to_group("vfx_light")
			_boulder.add_child(_light)
			VFX._cap_group(_boulder, "vfx_light", VFX.MAX_IMPACT_LIGHTS)

		if not Settings.reduced_motion() and Settings.quality_multiplier() > 0.0:
			_trail = GPUParticles3D.new()
			_trail.amount = maxi(8, int(38 * Settings.quality_multiplier()))
			_trail.lifetime = 0.75
			_trail.local_coords = false
			_trail.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 44, 16))
			var pm := ParticleProcessMaterial.new()
			pm.direction = Vector3(0.1, 1.0, -0.1).normalized()
			pm.spread = 28.0
			pm.initial_velocity_min = 2.5
			pm.initial_velocity_max = 6.5
			pm.angular_velocity_min = -180.0
			pm.angular_velocity_max = 180.0
			pm.scale_min = 1.2
			pm.scale_max = 1.8
			_trail.process_material = pm
			_trail.draw_pass_1 = CashBagVisual.get_bill_mesh()
			_boulder.add_child(_trail)
			_trail.emitting = true
	else:
		# Falling meteor boulder in the sky
		_boulder = Node3D.new()
		_boulder.name = "MeteorBoulder"
		add_child(_boulder)
		_boulder.global_position = sky_origin

		var rock := MeshInstance3D.new()
		rock.mesh = _boulder_mesh
		_boulder.add_child(rock)

		var corona := MeshInstance3D.new()
		corona.mesh = _core_mesh
		_boulder.add_child(corona)

		if Settings.quality_multiplier() >= 0.5:
			_light = OmniLight3D.new()
			_light.light_color = Color(1.0, 0.42, 0.10)
			_light.light_energy = 7.5
			_light.omni_range = 12.0
			_light.add_to_group("vfx_light")
			_boulder.add_child(_light)
			VFX._cap_group(_boulder, "vfx_light", VFX.MAX_IMPACT_LIGHTS)

		if not Settings.reduced_motion() and Settings.quality_multiplier() > 0.0:
			_trail = GPUParticles3D.new()
			_trail.amount = maxi(8, int(44 * Settings.quality_multiplier()))
			_trail.lifetime = 0.55
			_trail.local_coords = false
			_trail.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 44, 16))
			var pm := ParticleProcessMaterial.new()
			pm.direction = Vector3(0.1, 1.0, -0.1).normalized()
			pm.spread = 18.0
			pm.initial_velocity_min = 2.0
			pm.initial_velocity_max = 5.5
			pm.scale_min = 0.55
			pm.scale_max = 1.45
			pm.color_ramp = _trail_ramp
			_trail.process_material = pm
			_trail.draw_pass_1 = _trail_mesh
			_boulder.add_child(_trail)
			_trail.emitting = true


func _release_light() -> void:
	if is_instance_valid(_light):
		if _light.is_in_group("vfx_light"):
			_light.remove_from_group("vfx_light")
		_light.queue_free()
	_light = null


func _exit_tree() -> void:
	_release_light()


func _physics_process(delta: float) -> void:
	if not _armed or _detonated:
		return
	_age += delta
	var t := clampf(_age / fall_duration, 0.0, 1.0)
	var reduced := Settings.reduced_motion()
	if _boulder != null:
		if visual_style == "lightning":
			if not reduced:
				_boulder.rotate_y(delta * 2.6)
			if _ion_shaft != null:
				var w := lerpf(1.4, 0.25, t)
				_ion_shaft.scale = Vector3(w, 1.0, w)
		else:
			_boulder.global_position = sky_origin.lerp(target_pos, t)
			if not reduced:
				_boulder.rotate_x(delta * 4.2)
				_boulder.rotate_z(delta * 3.1)
	if _inner_ring != null:
		var r := lerpf(blast_radius * 0.95, 0.35, t)
		_inner_ring.scale = Vector3(r, 1.0, r)
	if _outer_ring != null:
		var pulse := 1.0 if reduced else (1.0 + 0.04 * sin(_age * 24.0))
		_outer_ring.scale = Vector3(blast_radius * pulse, 1.0, blast_radius * pulse)
	if _age >= fall_duration:
		_detonate()
		queue_free()


func _detonate() -> void:
	if _detonated:
		return
	_detonated = true
	if is_in_group("meteor_strike"):
		remove_from_group("meteor_strike")
	_release_light()
	var fx := get_parent() as Node3D
	if fx == null and get_tree() != null:
		fx = get_tree().current_scene as Node3D
	var sfx := get_node_or_null("/root/Sfx")
	if visual_style == "lightning":
		VFX.lightning_strike_explosion(fx, target_pos, 1.35)
		if sfx != null:
			if sfx.has_method("play_3d"):
				sfx.call("play_3d", "explosion", target_pos, 2.2, 0.58)
			elif sfx.has_method("play"):
				sfx.call("play", "explosion", 2.2, 0.58)
	elif visual_style == "cash_bag":
		VFX.cash_explosion(fx, target_pos, true)
		if sfx != null:
			if sfx.has_method("play_3d"):
				sfx.call("play_3d", "explosion", target_pos, 1.8, 0.92)
				sfx.call("play_3d", "pickup", target_pos, 1.6, 0.85)
			elif sfx.has_method("play"):
				sfx.call("play", "explosion", 1.8, 0.92)
	else:
		VFX.mushroom_cloud_explosion(fx, target_pos, Color(1.0, 0.26, 0.04), 2.65)
		VFX.dust_ring(fx, Vector3(target_pos.x, maxf(0.0, target_pos.y), target_pos.z), 2.8, 11.0)
		if sfx != null:
			if sfx.has_method("play_3d"):
				sfx.call("play_3d", "explosion", target_pos, 2.0, 0.78)
			elif sfx.has_method("play"):
				sfx.call("play", "explosion", 2.0, 0.78)
	var cam := get_tree().get_first_node_in_group("camera_rig") if get_tree() != null else null
	if cam != null and cam.has_method("add_shake"):
		var cam_dist := (cam as Node3D).global_position.distance_to(target_pos) if cam is Node3D else 0.0
		var shake := 0.68 * clampf(1.0 - cam_dist / 65.0, 0.15, 1.0)
		cam.call("add_shake", shake)

	impacted.emit(target_pos)

	var tree := get_tree()
	if tree == null:
		return
	COMBAT_AOE.apply_blast(tree, fx, target_pos, blast_radius, damage, 0.60, 0.72,
			owner_id, owner_node, token, true, 16.0, true)
