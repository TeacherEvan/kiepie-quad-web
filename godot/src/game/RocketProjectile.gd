extends Node3D
## Heavy Rocket Launcher projectile: fires once every 1.5 seconds, deals 2x
## machine-gun damage, and detonates on impact with a small blast radius (4.5 m).

signal hit(target: Node, point: Vector3)

const SPEED := 38.0
const BLAST_RADIUS := 4.5
const VFX := preload("res://src/game/VfxFactory.gd")

var owner_id := ""
var owner_node: Node
var velocity := Vector3.ZERO
var damage := 60.0
var blast_radius := BLAST_RADIUS
var token := ""
var hit_color := Color(1.0, 0.36, 0.10)

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


func _arena_net() -> Node:
	var tree := get_tree()
	if tree == null or not (tree.current_scene is Node):
		return null
	return tree.current_scene.get_node_or_null("ArenaNet")


func _note_local_damage_shown(target_id: String) -> void:
	var net := _arena_net()
	if net != null and net.has_method("note_local_damage_shown"):
		net.call("note_local_damage_shown", target_id)


func setup(p_owner_id: String, p_owner_node: Node, p_origin: Vector3,
		p_direction: Vector3, p_speed: float, p_damage: float,
		p_token: String, p_color: Color, p_blast_radius: float = BLAST_RADIUS) -> void:
	owner_id = p_owner_id
	owner_node = p_owner_node
	global_position = p_origin
	blast_radius = p_blast_radius
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
	if owner_node is CollisionObject3D:
		_ray_query.exclude = [(owner_node as CollisionObject3D).get_rid()]

	if Settings.quality_multiplier() >= 0.5:
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.52, 0.14)
		_light.light_energy = 4.2
		_light.omni_range = 4.5
		_light.add_to_group("vfx_light")
		add_child(_light)
		VFX._cap_group(self, "vfx_light", VFX.MAX_IMPACT_LIGHTS)

	if not Settings.reduced_motion():
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
		pm.color_ramp = _trail_ramp
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
		_visual.rotate_object_local(Vector3(0.0, 0.0, 1.0), delta * 12.0)
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
	if collider == owner_node:
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
	VFX.particle_explosion(fx, point, Color(1.0, 0.42, 0.10), 1.55, false)
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", "explosion")
	var cam := get_tree().get_first_node_in_group("camera_rig") if get_tree() != null else null
	if cam != null and cam.has_method("add_shake"):
		cam.call("add_shake", 0.36)

	hit.emit(direct_collider as Node, point)

	# Direct destructible building hit
	if direct_collider is Node and (direct_collider as Node).is_in_group("destructible"):
		if (direct_collider as Node).has_method("smash"):
			(direct_collider as Node).call("smash", velocity.normalized() * 14.0)

	var tree := get_tree()
	if tree == null:
		return

	var local_uid := ""
	var sb := tree.root.get_node_or_null("Supabase")
	if sb != null and "user_id" in sb:
		local_uid = str(sb.get("user_id"))

	var hit_any_enemy := false
	for b in tree.get_nodes_in_group("bike"):
		if not is_instance_valid(b) or not (b is Node3D):
			continue
		var bike_node := b as Node3D
		if not bike_node.visible or bike_node.get("is_respawning") == true:
			continue
		var dist := bike_node.global_position.distance_to(point)
		if dist > blast_radius:
			continue
		if bike_node == owner_node:
			continue
		var target_id := str(bike_node.get("player_id")) if "player_id" in bike_node else ""
		# Slight radial falloff only near the very edge; full 2x damage inside 65% radius
		var falloff := 1.0 if dist <= blast_radius * 0.65 else lerpf(1.0, 0.75, (dist - blast_radius * 0.65) / maxf(0.01, blast_radius * 0.35))
		var applied_dmg := roundf(damage * falloff)
		var controller := bike_node.get_node_or_null("CombatController")
		if controller != null and controller.has_method("take_damage"):
			controller.call("take_damage", applied_dmg, owner_id, bike_node.global_position, token)
		elif owner_id != "" and owner_id == local_uid and target_id != local_uid:
			# Remote proxy or practice dummy: no local CombatController exists to
			# pop a number — give the shooter immediate zero-latency feedback.
			VFX.damage_number(fx, bike_node.global_position + Vector3(0.0, 0.55, 0.0),
					float(applied_dmg), Color(1.0, 0.85, 0.22))
			_note_local_damage_shown(target_id)
		if owner_id != "" and owner_id == local_uid and target_id != local_uid:
			hit_any_enemy = true

	for h in tree.get_nodes_in_group("hazard"):
		if not is_instance_valid(h) or not (h is Node3D):
			continue
		var hz := h as Node3D
		if hz.global_position.distance_to(point) <= blast_radius and hz.has_method("ignite"):
			hz.call("ignite", owner_id, token)
			if owner_id != "" and owner_id == local_uid:
				hit_any_enemy = true

	for d in tree.get_nodes_in_group("destructible"):
		if not is_instance_valid(d) or not (d is Node3D):
			continue
		var db := d as Node3D
		if db.global_position.distance_to(point) <= blast_radius and db.has_method("smash"):
			db.call("smash", (db.global_position - point).normalized() * 12.0)

	if hit_any_enemy:
		var local_combat := tree.get_first_node_in_group("local_combat")
		if local_combat != null and local_combat.has_signal("hit_confirmed"):
			local_combat.emit_signal("hit_confirmed")
