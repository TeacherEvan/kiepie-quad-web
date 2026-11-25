extends Node3D
## Evan the Skeleton's Rocket/Projectile slot: a hot-pink electric guitar that
## flies out slicing through everything it touches, then curves back to its
## owner. Contacts damage once per target; the weapon never detonates mid-flight.

signal hit(target: Node, point: Vector3)

const SPEED := 34.0
const OUTBOUND_TIME := 0.95
const OUTBOUND_DIST := 30.0
const RETURN_ARRIVE := 1.5
const SPIN_RATE := 12.0
const SMASH_IMPULSE := 14.0
const PINK := Color(1.0, 0.10, 0.46)
const VFX := preload("res://src/game/VfxFactory.gd")

var owner_id := ""
var owner_node: Node
var velocity := Vector3.ZERO
var damage := 60.0
var token := ""
var hit_color := PINK
var blast_radius := 4.5
var visual_style := "boomerang"

var _age := 0.0
var _life := 3.5
var _inert := true
var _outbound := true
var _outbound_dist := 0.0
var _outbound_origin := Vector3.ZERO
var _base_speed := 0.0
var _hit_ids := {}
var _did_hit_any := false
var _first_target: Node = null
var _first_point := Vector3.ZERO
var _visual: Node3D
var _spinner: Node3D
var _trail: GPUParticles3D
var _light: OmniLight3D
var _ray_query: PhysicsRayQueryParameters3D

static var _body_mesh: BoxMesh = null
static var _wing_mesh: BoxMesh = null
static var _neck_mesh: BoxMesh = null
static var _head_mesh: BoxMesh = null
static var _bridge_mesh: BoxMesh = null
static var _pickup_mesh: BoxMesh = null
static var _peg_mesh: CylinderMesh = null
static var _bar_mesh: CylinderMesh = null
static var _trail_mesh: SphereMesh = null
static var _trail_ramp: GradientTexture1D = null


static func _ensure_meshes() -> void:
	if _body_mesh == null:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.20, 0.048, 0.25)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.90, 0.06, 0.38)
		mat.emission_enabled = true
		mat.emission = PINK
		mat.emission_energy_multiplier = 2.2
		mat.metallic = 0.25
		mat.roughness = 0.32
		bm.material = mat
		_body_mesh = bm
	if _wing_mesh == null:
		var wm := BoxMesh.new()
		wm.size = Vector3(0.13, 0.044, 0.12)
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(0.78, 0.05, 0.32)
		wmat.emission_enabled = true
		wmat.emission = PINK
		wmat.emission_energy_multiplier = 1.6
		wmat.metallic = 0.25
		wmat.roughness = 0.34
		wm.material = wmat
		_wing_mesh = wm
	if _neck_mesh == null:
		var nm := BoxMesh.new()
		nm.size = Vector3(0.055, 0.026, 0.26)
		var nmat := StandardMaterial3D.new()
		nmat.albedo_color = Color(0.20, 0.09, 0.09)
		nmat.roughness = 0.62
		nm.material = nmat
		_neck_mesh = nm
	if _head_mesh == null:
		var hm := BoxMesh.new()
		hm.size = Vector3(0.068, 0.020, 0.072)
		var hmat := StandardMaterial3D.new()
		hmat.albedo_color = Color(0.80, 0.05, 0.32)
		hmat.emission_enabled = true
		hmat.emission = PINK
		hmat.emission_energy_multiplier = 1.2
		hmat.roughness = 0.38
		hm.material = hmat
		_head_mesh = hm
	if _bridge_mesh == null:
		var br := BoxMesh.new()
		br.size = Vector3(0.10, 0.012, 0.022)
		_bridge_mesh = _chrome_mesh(br)
	if _pickup_mesh == null:
		var pk := BoxMesh.new()
		pk.size = Vector3(0.085, 0.014, 0.018)
		_pickup_mesh = _chrome_mesh(pk)
	if _peg_mesh == null:
		var pg := CylinderMesh.new()
		pg.top_radius = 0.011
		pg.bottom_radius = 0.011
		pg.height = 0.028
		pg.radial_segments = 8
		_peg_mesh = _chrome_mesh(pg)
	if _bar_mesh == null:
		var bar := CylinderMesh.new()
		bar.top_radius = 0.006
		bar.bottom_radius = 0.006
		bar.height = 0.10
		bar.radial_segments = 6
		_bar_mesh = _chrome_mesh(bar)
	if _trail_mesh == null:
		var tm := SphereMesh.new()
		tm.radius = 0.075
		tm.height = 0.15
		tm.radial_segments = 6
		tm.rings = 3
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color(1.0, 0.30, 0.68, 0.85)
		tmat.emission_enabled = true
		tmat.emission = PINK
		tmat.emission_energy_multiplier = 2.6
		tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		tm.material = tmat
		_trail_mesh = tm
	if _trail_ramp == null:
		_trail_ramp = VFX._ramp([
			Color(1.0, 0.62, 0.88, 0.95),
			Color(1.0, 0.10, 0.46, 0.68),
			Color(0.28, 0.02, 0.12, 0.0),
		])


static func _chrome_mesh(mesh: Mesh) -> Mesh:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.81, 0.86)
	mat.metallic = 0.90
	mat.roughness = 0.22
	mesh.material = mat
	return mesh


func setup(p_owner_id: String, p_owner_node: Node, p_origin: Vector3,
		p_direction: Vector3, p_speed: float, p_damage: float,
		p_token: String, p_color: Color,
		p_blast_radius: float = 4.5, p_visual_style: String = "boomerang") -> void:
	owner_id = p_owner_id
	owner_node = p_owner_node
	global_position = p_origin
	blast_radius = p_blast_radius
	visual_style = p_visual_style
	_age = 0.0
	_outbound = true
	_outbound_dist = 0.0
	_outbound_origin = p_origin
	_hit_ids.clear()
	_did_hit_any = false
	_first_target = null
	_first_point = p_origin
	damage = p_damage
	token = p_token
	hit_color = p_color
	if p_direction.length_squared() < 1e-8 or not is_finite(p_direction.x + p_direction.y + p_direction.z) \
			or not is_finite(p_speed) or p_speed <= 0.0:
		velocity = Vector3.ZERO
		_inert = true
		_life = 0.05
		return
	_base_speed = p_speed
	velocity = p_direction.normalized() * p_speed
	_inert = false
	_life = 3.5
	_build_visual()


func _build_visual() -> void:
	_ensure_meshes()
	_visual = Node3D.new()
	_visual.name = "BoomerangGuitar"
	add_child(_visual)
	_spinner = Node3D.new()
	_spinner.name = "GuitarSpinner"
	_visual.add_child(_spinner)

	var body := MeshInstance3D.new()
	body.mesh = _body_mesh
	body.position.z = 0.045
	_spinner.add_child(body)
	var wing := MeshInstance3D.new()
	wing.mesh = _wing_mesh
	wing.position = Vector3(0.045, -0.004, 0.11)
	_spinner.add_child(wing)
	var neck := MeshInstance3D.new()
	neck.mesh = _neck_mesh
	neck.position = Vector3(0.0, 0.008, -0.15)
	_spinner.add_child(neck)
	var head := MeshInstance3D.new()
	head.mesh = _head_mesh
	head.position = Vector3(0.0, 0.008, -0.29)
	head.rotation_degrees.z = -8.0
	_spinner.add_child(head)

	for z_pos in [0.01, 0.09]:
		var pickup := MeshInstance3D.new()
		pickup.mesh = _pickup_mesh
		pickup.position = Vector3(0.0, 0.032, z_pos)
		_spinner.add_child(pickup)
	var bridge := MeshInstance3D.new()
	bridge.mesh = _bridge_mesh
	bridge.position = Vector3(0.0, 0.032, 0.16)
	_spinner.add_child(bridge)

	for side in [-1.0, 1.0]:
		for z_pos in [-0.27, -0.31]:
			var peg := MeshInstance3D.new()
			peg.mesh = _peg_mesh
			peg.position = Vector3(0.045 * side, 0.010, z_pos)
			peg.rotation_degrees.z = 90.0
			_spinner.add_child(peg)

	var bar := MeshInstance3D.new()
	bar.mesh = _bar_mesh
	bar.position = Vector3(0.10, 0.030, 0.16)
	bar.rotation_degrees.x = 22.0
	_spinner.add_child(bar)

	var dir := velocity.normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	_visual.basis = Basis.looking_at(dir, up)

	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collide_with_areas = false
	_ray_query.collide_with_bodies = true
	_ray_query.exclude = [(owner_node as CollisionObject3D).get_rid()] \
			if is_instance_valid(owner_node) and owner_node is CollisionObject3D else []

	if Settings.quality_multiplier() >= 0.5:
		_light = OmniLight3D.new()
		_light.light_color = PINK
		_light.light_energy = 3.6
		_light.omni_range = 4.2
		_light.add_to_group("vfx_light")
		add_child(_light)
		VFX._cap_group(self, "vfx_light", VFX.MAX_IMPACT_LIGHTS)

	if not Settings.reduced_motion() and Settings.quality_multiplier() > 0.0:
		_trail = GPUParticles3D.new()
		_trail.amount = maxi(6, int(26 * Settings.quality_multiplier()))
		_trail.lifetime = 0.36
		_trail.local_coords = false
		_trail.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
		var pm := ParticleProcessMaterial.new()
		pm.direction = -dir
		pm.spread = 9.0
		pm.initial_velocity_min = 0.3
		pm.initial_velocity_max = 1.4
		pm.scale_min = 0.16
		pm.scale_max = 0.42
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


static func _resolve_bike(node: Node) -> Node3D:
	var walk: Object = node
	while walk is Node:
		var n := walk as Node
		if n.is_in_group("bike"):
			return n as Node3D
		walk = n.get_parent()
	return null


func _local_uid() -> String:
	var tree := get_tree()
	if tree == null:
		return ""
	var sb := tree.root.get_node_or_null("Supabase")
	if sb != null and "user_id" in sb:
		return str(sb.get("user_id"))
	return ""


func _fx_parent() -> Node3D:
	var fx := get_parent() as Node3D
	if fx == null and get_tree() != null:
		fx = get_tree().current_scene as Node3D
	return fx


func _damage_bike(bike_node: Node, point: Vector3) -> void:
	var root := _resolve_bike(bike_node)
	if root == null or root == owner_node:
		return
	var victim_id := str(root.get("player_id")) if "player_id" in root else ""
	# The shooter must never mutate a remote proxy — the victim's own client
	# resolves its damage against its authoritative local bike.
	var local_uid := _local_uid()
	# Fail closed: an unidentified bike (or any peer id other than ours) is a
	# remote proxy and must never be mutated from the shooter's client.
	if local_uid == "" or victim_id == "" or victim_id != local_uid:
		return
	var controller: Node = root.get_node_or_null("CombatController")
	if controller == null or not controller.has_method("take_damage"):
		for child in root.get_children():
			if child.has_method("take_damage"):
				controller = child
				break
	if controller == null or not controller.has_method("take_damage"):
		return
	var sub := ("%s:v%s" % [token, victim_id]) if token != "" else ""
	controller.call("take_damage", damage, owner_id, root.global_position, sub)


func _on_contact(collider: Object, point: Vector3, normal: Vector3) -> void:
	if not (collider is Node):
		return
	var node := collider as Node
	if _resolve_bike(node) == owner_node:
		return
	var id := node.get_instance_id()
	if _hit_ids.has(id):
		return
	_hit_ids[id] = true
	_did_hit_any = true
	if _first_target == null:
		_first_target = node
		_first_point = point

	var dir := velocity.normalized()
	var surface := "metal"
	if node.name == "Ground":
		surface = "ground"
	if node.is_in_group("bike"):
		_damage_bike(node, point)
	elif node.is_in_group("destructible"):
		if node.has_method("smash"):
			node.call("smash", dir * SMASH_IMPULSE)
	elif node.is_in_group("hazard"):
		if node.has_method("ignite"):
			var sub := ("%s:d%d" % [token, id]) if token != "" else ""
			node.call("ignite", owner_id, sub)
	VFX.impact(_fx_parent(), point, PINK, dir, surface, normal)


func _finish() -> void:
	if _did_hit_any:
		hit.emit(_first_target, _first_point)
	_release_light()
	queue_free()


func _steer_return(delta: float) -> void:
	var target := _outbound_origin
	if is_instance_valid(owner_node) and owner_node is Node3D:
		target = (owner_node as Node3D).global_position + Vector3(0.0, 0.7, 0.0)
	var to_target := target - global_position
	if to_target.length_squared() < 1e-8:
		return
	# Rotate the heading along the great-circle arc rather than lerping the
	# velocity vector: a lerp between opposite directions passes through ~zero
	# and the guitar stalls instead of coming home.
	var dir_now := velocity.normalized() if velocity.length_squared() > 1e-8 else -to_target.normalized()
	var dir_target := to_target.normalized()
	var dot := clampf(dir_now.dot(dir_target), -1.0, 1.0)
	var angle := acos(dot)
	var blend := clampf(delta * 5.5, 0.0, 1.0)
	if angle > 1e-4:
		var axis := dir_now.cross(dir_target)
		if axis.length_squared() < 1e-8:
			axis = dir_now.cross(Vector3.UP)
			if axis.length_squared() < 1e-8:
				axis = dir_now.cross(Vector3.RIGHT)
		dir_now = dir_now.rotated(axis.normalized(), minf(angle * blend, angle))
	# Keep a brisk, constant homing speed so the return always completes
	# inside the hard life cap even after a long outbound leg.
	var home_speed := maxf(_base_speed * 0.85, 12.0)
	velocity = dir_now.normalized() * home_speed


func _physics_process(delta: float) -> void:
	_age += delta
	if _inert or _age >= _life:
		_finish()
		return
	if _visual != null and not Settings.reduced_motion():
		_spinner.rotate_object_local(Vector3(0.0, 0.0, 1.0), delta * SPIN_RATE)

	if _outbound and (_age >= OUTBOUND_TIME or _outbound_dist >= OUTBOUND_DIST):
		_outbound = false
	if not _outbound:
		if is_instance_valid(owner_node) and owner_node is Node3D \
				and global_position.distance_to((owner_node as Node3D).global_position) <= RETURN_ARRIVE:
			_finish()
			return
		_steer_return(delta)

	var world := get_world_3d()
	if world == null:
		return
	if _visual != null:
		var dir := velocity.normalized()
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
		_visual.basis = Basis.looking_at(dir, up)
	if _trail != null and _trail.process_material is ParticleProcessMaterial:
		(_trail.process_material as ParticleProcessMaterial).direction = -velocity.normalized()

	var from := global_position
	var step := velocity * delta
	var to := from + step
	_outbound_dist += step.length()
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
	_on_contact(collider, point, result.get("normal", Vector3.UP))
	global_position = point + velocity.normalized() * 0.06
