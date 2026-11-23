extends Node3D
## Heavy Rocket Launcher projectile: fires once every 1.5 seconds. A direct hit
## is always lethal; anything else inside the 4.5 m blast radius loses 90% of
## its health (90 damage). NARDUS fires a massive cigar instead of a rocket.

signal hit(target: Node, point: Vector3)

const SPEED := 38.0
const BLAST_RADIUS := 4.5
## 90% of CombatController.MAX_HEALTH (100) — flat across the whole blast.
const BLAST_DAMAGE := 90.0
const VFX := preload("res://src/game/VfxFactory.gd")
const COMBAT_AOE := preload("res://src/game/CombatAoe.gd")

var owner_id := ""
var owner_node: Node
var velocity := Vector3.ZERO
var damage := 60.0
var blast_radius := BLAST_RADIUS
var token := ""
var hit_color := Color(1.0, 0.36, 0.10)
var visual_style := "rocket"

var _age := 0.0
var _life := 3.2
var _inert := true
var _visual: Node3D
var _trail: GPUParticles3D
var _light: OmniLight3D
var _ray_query: PhysicsRayQueryParameters3D

static var _body_mesh: CylinderMesh = null
static var _nose_mesh: CylinderMesh = null
static var _fin_mesh: BoxMesh = null
static var _plume_mesh: SphereMesh = null
static var _trail_mesh: SphereMesh = null
static var _trail_ramp: GradientTexture1D = null
static var _cash_trail_ramp: GradientTexture1D = null
static var _cigar_trail_ramp: GradientTexture1D = null
static var _cigar_body_mesh: CylinderMesh = null
static var _cigar_band_mesh: CylinderMesh = null
static var _cigar_ember_mesh: SphereMesh = null
static var _cigar_ash_mesh: SphereMesh = null


static func _ensure_meshes() -> void:
	if _body_mesh == null:
		var bm := CylinderMesh.new()
		bm.top_radius = 0.068
		bm.bottom_radius = 0.074
		bm.height = 0.52
		bm.radial_segments = 10
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.22, 0.25, 0.30)
		bmat.metallic = 0.72
		bmat.roughness = 0.34
		bm.material = bmat
		_body_mesh = bm
	if _nose_mesh == null:
		var nm := CylinderMesh.new()
		nm.top_radius = 0.004
		nm.bottom_radius = 0.070
		nm.height = 0.22
		nm.radial_segments = 10
		var nmat := StandardMaterial3D.new()
		nmat.albedo_color = Color(0.88, 0.14, 0.08)
		nmat.emission_enabled = true
		nmat.emission = Color(1.0, 0.28, 0.08)
		nmat.emission_energy_multiplier = 1.8
		nmat.roughness = 0.38
		nm.material = nmat
		_nose_mesh = nm
	if _fin_mesh == null:
		var fm := BoxMesh.new()
		fm.size = Vector3(0.24, 0.022, 0.14)
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color(0.75, 0.16, 0.08)
		fmat.metallic = 0.45
		fmat.roughness = 0.45
		fm.material = fmat
		_fin_mesh = fm
	if _plume_mesh == null:
		var pm := SphereMesh.new()
		pm.radius = 0.082
		pm.height = 0.22
		pm.radial_segments = 8
		pm.rings = 4
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(1.0, 0.92, 0.65)
		pmat.emission_enabled = true
		pmat.emission = Color(1.0, 0.62, 0.16)
		pmat.emission_energy_multiplier = 7.5
		pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.material = pmat
		_plume_mesh = pm
	if _trail_mesh == null:
		var tm := SphereMesh.new()
		tm.radius = 0.15
		tm.height = 0.30
		tm.radial_segments = 6
		tm.rings = 3
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color(1.0, 0.58, 0.18, 0.85)
		tmat.emission_enabled = true
		tmat.emission = Color(1.0, 0.42, 0.10)
		tmat.emission_energy_multiplier = 2.4
		tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		tm.material = tmat
		_trail_mesh = tm
	if _trail_ramp == null:
		_trail_ramp = VFX._ramp([
			Color(1.0, 0.92, 0.58, 0.95),
			Color(1.0, 0.44, 0.10, 0.68),
			Color(0.28, 0.24, 0.22, 0.0),
		])
	if _cash_trail_ramp == null:
		_cash_trail_ramp = VFX._ramp([
			Color(1.0, 0.90, 0.32, 0.95),
			Color(0.18, 0.85, 0.42, 0.72),
			Color(0.08, 0.42, 0.18, 0.0),
		])
	if _cigar_trail_ramp == null:
		_cigar_trail_ramp = VFX._ramp([
			Color(0.96, 0.80, 0.54, 0.92),
			Color(0.44, 0.27, 0.16, 0.62),
			Color(0.12, 0.10, 0.10, 0.0),
		])
	if _cigar_body_mesh == null:
		var cb := CylinderMesh.new()
		cb.top_radius = 0.20
		cb.bottom_radius = 0.22
		cb.height = 1.90
		cb.radial_segments = 20
		cb.rings = 6
		var cbm := StandardMaterial3D.new()
		cbm.albedo_color = Color(0.37, 0.19, 0.09)
		cbm.roughness = 0.74
		cb.material = cbm
		_cigar_body_mesh = cb
	if _cigar_band_mesh == null:
		var bd := CylinderMesh.new()
		bd.top_radius = 0.226
		bd.bottom_radius = 0.226
		bd.height = 0.15
		bd.radial_segments = 20
		var bdm := StandardMaterial3D.new()
		bdm.albedo_color = Color(0.88, 0.63, 0.14)
		bdm.metallic = 0.68
		bdm.roughness = 0.30
		bd.material = bdm
		_cigar_band_mesh = bd
	if _cigar_ember_mesh == null:
		var em := SphereMesh.new()
		em.radius = 0.175
		em.height = 0.13
		em.radial_segments = 14
		em.rings = 5
		var emm := StandardMaterial3D.new()
		emm.albedo_color = Color(1.0, 0.44, 0.10)
		emm.emission_enabled = true
		emm.emission = Color(1.0, 0.30, 0.06)
		emm.emission_energy_multiplier = 5.0
		emm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		em.material = emm
		_cigar_ember_mesh = em
	if _cigar_ash_mesh == null:
		var ash := SphereMesh.new()
		ash.radius = 0.100
		ash.height = 0.07
		ash.radial_segments = 14
		ash.rings = 4
		var am := StandardMaterial3D.new()
		am.albedo_color = Color(0.28, 0.26, 0.25)
		am.roughness = 0.95
		ash.material = am
		_cigar_ash_mesh = ash


func setup(p_owner_id: String, p_owner_node: Node, p_origin: Vector3,
		p_direction: Vector3, p_speed: float, p_damage: float,
		p_token: String, p_color: Color, p_blast_radius: float = BLAST_RADIUS,
		p_visual_style: String = "rocket") -> void:
	owner_id = p_owner_id
	owner_node = p_owner_node
	global_position = p_origin
	blast_radius = p_blast_radius
	visual_style = p_visual_style if p_visual_style in ["rocket", "cash_bag", "cigar"] else "rocket"
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
	_build_visual()


func _build_visual() -> void:
	_ensure_meshes()
	if visual_style == "cigar":
		# NARDUS's "massive cigar": a fat tobacco-brown cylinder with a gold
		# band and a glowing cherry at the forward (-Z) tip.
		_visual = Node3D.new()
		_visual.name = "Cigar"
		add_child(_visual)
		var body := MeshInstance3D.new()
		body.mesh = _cigar_body_mesh
		body.rotation_degrees.x = 90.0
		_visual.add_child(body)
		var band := MeshInstance3D.new()
		band.mesh = _cigar_band_mesh
		band.rotation_degrees.x = 90.0
		band.position.z = -0.58
		_visual.add_child(band)
		var ember := MeshInstance3D.new()
		ember.mesh = _cigar_ember_mesh
		ember.position.z = -0.96
		_visual.add_child(ember)
		var ash := MeshInstance3D.new()
		ash.mesh = _cigar_ash_mesh
		ash.position.z = -1.04
		_visual.add_child(ash)
	elif visual_style == "cash_bag":
		_visual = CashBagVisual.build_bag(1.15)
		add_child(_visual)
	else:
		_visual = Node3D.new()
		_visual.name = "Rocket"
		add_child(_visual)

		var body := MeshInstance3D.new()
		body.mesh = _body_mesh
		body.rotation_degrees.x = 90.0
		_visual.add_child(body)

		var nose := MeshInstance3D.new()
		nose.mesh = _nose_mesh
		nose.rotation_degrees.x = -90.0
		nose.position.z = -0.36
		_visual.add_child(nose)

		for rot_z in [0.0, 90.0]:
			var fin := MeshInstance3D.new()
			fin.mesh = _fin_mesh
			fin.position.z = 0.20
			fin.rotation_degrees.z = float(rot_z)
			_visual.add_child(fin)

		var plume := MeshInstance3D.new()
		plume.mesh = _plume_mesh
		plume.position.z = 0.30
		_visual.add_child(plume)

	var dir := velocity.normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	_visual.basis = Basis.looking_at(dir, up)

	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collide_with_areas = false
	_ray_query.collide_with_bodies = true
	if is_instance_valid(owner_node) and owner_node is CollisionObject3D:
		_ray_query.exclude = [(owner_node as CollisionObject3D).get_rid()]

	if Settings.quality_multiplier() >= 0.5:
		_light = OmniLight3D.new()
		_light.light_color = Color(0.32, 0.92, 0.48) if visual_style == "cash_bag" \
				else (Color(1.0, 0.38, 0.10) if visual_style == "cigar" else Color(1.0, 0.52, 0.14))
		_light.light_energy = 4.2
		_light.omni_range = 8.0 if visual_style == "cigar" else 4.5
		_light.add_to_group("vfx_light")
		add_child(_light)
		VFX._cap_group(self, "vfx_light", VFX.MAX_IMPACT_LIGHTS)

	if not Settings.reduced_motion() and Settings.quality_multiplier() > 0.0:
		_trail = GPUParticles3D.new()
		_trail.amount = maxi(6, int(36 * Settings.quality_multiplier()))
		_trail.lifetime = 0.44
		_trail.local_coords = false
		_trail.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
		var pm := ParticleProcessMaterial.new()
		pm.direction = -velocity.normalized()
		pm.spread = 11.0
		pm.initial_velocity_min = 0.8
		pm.initial_velocity_max = 2.6
		pm.scale_min = 0.24
		pm.scale_max = 0.65
		pm.color_ramp = _cash_trail_ramp if visual_style == "cash_bag" \
				else (_cigar_trail_ramp if visual_style == "cigar" else _trail_ramp)
		if visual_style == "cigar":
			pm.scale_min = 0.8
			pm.scale_max = 1.6
		_trail.process_material = pm
		_trail.draw_pass_1 = _trail_mesh
		add_child(_trail)
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
	_age += delta
	if _inert or _age >= _life:
		_release_light()
		queue_free()
		return
	if _visual != null and not Settings.reduced_motion():
		if visual_style == "cash_bag":
			_visual.rotate_object_local(Vector3(1.0, 0.7, 0.4).normalized(), delta * 10.0)
		else:
			# A massive cigar tumbles lazily; a rocket spins fast.
			_visual.rotate_object_local(Vector3(0.0, 0.0, 1.0),
					delta * (5.0 if visual_style == "cigar" else 12.0))
	var world := get_world_3d()
	if world == null:
		return
	var from := global_position
	var to := from + velocity * delta
	_ray_query.from = from
	_ray_query.to = to
	var result := world.direct_space_state.intersect_ray(_ray_query)
	if result.is_empty():
		global_position = to
		return
	var collider: Object = result.get("collider", null)
	var point: Vector3 = result.get("position", to)
	if is_instance_valid(owner_node) and collider == owner_node:
		global_position = to
		return
	global_position = point
	_detonate(point, collider)
	queue_free()


func _detonate(point: Vector3, direct_collider: Object) -> void:
	_release_light()
	var fx := get_parent() as Node3D
	if fx == null and get_tree() != null:
		fx = get_tree().current_scene as Node3D
	if visual_style == "cigar":
		VFX.particle_explosion(fx, point, Color(0.58, 0.34, 0.14), 3.0, false)
	elif visual_style == "cash_bag":
		VFX.cash_explosion(fx, point, false)
	else:
		VFX.particle_explosion(fx, point, Color(1.0, 0.42, 0.10), 1.55, false)
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		if sfx.has_method("play_3d"):
			sfx.call("play_3d", "explosion", point)
		elif sfx.has_method("play"):
			sfx.call("play", "explosion")
	var cam := get_tree().get_first_node_in_group("camera_rig") if get_tree() != null else null
	if cam != null and cam.has_method("add_shake"):
		var cam_dist := (cam as Node3D).global_position.distance_to(point) if cam is Node3D else 0.0
		var shake := 0.36 * clampf(1.0 - cam_dist / 55.0, 0.15, 1.0)
		cam.call("add_shake", shake)

	hit.emit(direct_collider as Node, point)

	# Direct destructible building hit
	if direct_collider is Node and (direct_collider as Node).is_in_group("destructible"):
		if (direct_collider as Node).has_method("smash"):
			(direct_collider as Node).call("smash", velocity.normalized() * 14.0)

	# A direct hit is an instant kill, for every launcher and every vehicle.
	# Resolve through parents so a collider that is a wheel/child still maps to
	# the bike root, then let the victim's own controller apply the lethal hit
	# (we never mutate a remote proxy from the shooter's client).
	var direct_bike: Node3D = null
	var lethal_controller: Node = null
	var walk: Object = direct_collider
	while walk is Node:
		var n := walk as Node
		if n.is_in_group("bike"):
			direct_bike = n as Node3D
			break
		walk = n.get_parent()
	if direct_bike != null and direct_bike != owner_node:
		lethal_controller = direct_bike.get_node_or_null("CombatController")
		if lethal_controller == null or not lethal_controller.has_method("take_lethal_hit"):
			lethal_controller = null
			for child in direct_bike.get_children():
				if child.has_method("take_lethal_hit"):
					lethal_controller = child
					break
		if lethal_controller != null:
			# Same-shot multi-kill token contract as CombatAoe: the host's rate
			# limiter only grants the burst exemption for "<base>:<suffix>" tokens.
			# A raw token here would lose the guaranteed kill if an AOE victim's
			# sub-token kill is processed first.
			var vid_variant: Variant = direct_bike.get("player_id")
			var victim_id := str(vid_variant) if vid_variant != null else ""
			var lethal_tok := ("%s:v%s" % [token, victim_id]) if token != "" and victim_id != "" else token
			lethal_controller.call("take_lethal_hit", owner_id, point, lethal_tok)

	var tree := get_tree()
	if tree == null:
		return
	# Flat 90% health loss for everyone else inside the blast — no falloff.
	# Skip a directly-hit remote proxy (identified by its player_id): its
	# authoritative 100-damage number comes from the victim's own client via
	# the "hurt" event. Controller-bearing local/dummy bikes still take the 90.
	var proxy_id_variant: Variant = direct_bike.get("player_id") if direct_bike != null else null
	var is_remote_proxy := proxy_id_variant != null and str(proxy_id_variant) != ""
	var skip_proxy: Node = direct_bike if (is_remote_proxy and lethal_controller == null) else null
	COMBAT_AOE.apply_blast(tree, fx, point, blast_radius, BLAST_DAMAGE, 1.0, 1.0,
			owner_id, owner_node, token, true, 12.0, true, true, skip_proxy)
