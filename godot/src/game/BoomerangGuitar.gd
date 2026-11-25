extends Node3D
## Evan the Skeleton's Rocket/Projectile slot: a hot-pink electric guitar that
## flies out slicing through everything it touches, then curves back to its
## owner. Contacts damage once per target; the weapon never detonates mid-flight.

signal hit(target: Node, point: Vector3)
signal returned(was_caught: bool)

const SPEED := 34.0
const OUTBOUND_TIME := 0.72
const OUTBOUND_DIST := 26.0
const RETURN_ARRIVE := 1.75
const SPIN_RATE := 16.0
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
var _life := 2.9
var _inert := true
var _outbound := true
var _return_age := 0.0
var _outbound_dist := 0.0
var _outbound_origin := Vector3.ZERO
var _base_speed := 0.0
var _hit_ids := {}
var _hit_outbound := {}
var _did_hit_any := false
var _first_target: Node = null
var _first_point := Vector3.ZERO
var _notified_throw := false
var _notified_return := false
var _finished := false
var _visual: Node3D
var _spinner: Node3D
var _trail: GPUParticles3D
var _light: OmniLight3D
var _ray_query: PhysicsRayQueryParameters3D

static var _body_mesh: ArrayMesh = null
static var _neck_mesh: BoxMesh = null
static var _head_mesh: BoxMesh = null
static var _bridge_mesh: BoxMesh = null
static var _pickup_mesh: BoxMesh = null
static var _peg_mesh: CylinderMesh = null
static var _slash_ring_mesh: TorusMesh = null
static var _trail_mesh: SphereMesh = null
static var _trail_ramp: GradientTexture1D = null


static func _build_guitar_body_mesh() -> ArrayMesh:
	var outline := PackedVector2Array([
		Vector2(-0.165, -0.175), Vector2(-0.095, -0.225), Vector2(0.000, -0.235),
		Vector2(0.085, -0.205), Vector2(0.145, -0.145), Vector2(0.175, -0.070),
		Vector2(0.145, -0.010), Vector2(0.090, 0.035), Vector2(0.135, 0.085),
		Vector2(0.155, 0.140), Vector2(0.115, 0.160), Vector2(0.055, 0.115),
		Vector2(0.028, 0.085), Vector2(-0.028, 0.085), Vector2(-0.055, 0.155),
		Vector2(-0.110, 0.215), Vector2(-0.165, 0.195), Vector2(-0.185, 0.125),
		Vector2(-0.145, 0.045), Vector2(-0.165, -0.030), Vector2(-0.190, -0.105),
	])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_h := 0.026
	var n := outline.size()
	var c_top := Vector3(0.0, half_h, 0.02)
	var c_bot := Vector3(0.0, -half_h, 0.02)
	for i in range(n):
		var a2 := outline[i]
		var b2 := outline[(i + 1) % n]
		# Map 2D guitar contour (x=width, y=length toward -Z neck) into XZ plane
		var at := Vector3(a2.x, half_h, -a2.y)
		var bt := Vector3(b2.x, half_h, -b2.y)
		var ab := Vector3(a2.x, -half_h, -a2.y)
		var bb := Vector3(b2.x, -half_h, -b2.y)
		st.add_vertex(c_top); st.add_vertex(bt); st.add_vertex(at)
		st.add_vertex(c_bot); st.add_vertex(ab); st.add_vertex(bb)
		st.add_vertex(ab); st.add_vertex(at); st.add_vertex(bt)
		st.add_vertex(ab); st.add_vertex(bt); st.add_vertex(bb)
	st.generate_normals()
	var am := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.96, 0.05, 0.42)
	mat.emission_enabled = true
	mat.emission = PINK
	mat.emission_energy_multiplier = 2.4
	mat.metallic = 0.22
	mat.roughness = 0.24
	am.surface_set_material(0, mat)
	return am


static func _ensure_meshes() -> void:
	if _body_mesh == null:
		_body_mesh = _build_guitar_body_mesh()
	if _neck_mesh == null:
		var nm := BoxMesh.new()
		nm.size = Vector3(0.054, 0.026, 0.34)
		var nmat := StandardMaterial3D.new()
		nmat.albedo_color = Color(0.18, 0.09, 0.07)
		nmat.roughness = 0.58
		nm.material = nmat
		_neck_mesh = nm
	if _head_mesh == null:
		var hm := BoxMesh.new()
		hm.size = Vector3(0.068, 0.022, 0.11)
		var hmat := StandardMaterial3D.new()
		hmat.albedo_color = Color(0.94, 0.05, 0.40)
		hmat.emission_enabled = true
		hmat.emission = PINK
		hmat.emission_energy_multiplier = 1.6
		hmat.roughness = 0.28
		hm.material = hmat
		_head_mesh = hm
	if _bridge_mesh == null:
		var br := BoxMesh.new()
		br.size = Vector3(0.095, 0.012, 0.022)
		_bridge_mesh = _chrome_mesh(br)
	if _pickup_mesh == null:
		var pk := BoxMesh.new()
		pk.size = Vector3(0.092, 0.014, 0.032)
		var pkmat := StandardMaterial3D.new()
		pkmat.albedo_color = Color(0.96, 0.94, 0.88)
		pkmat.roughness = 0.36
		pk.material = pkmat
		_pickup_mesh = pk
	if _peg_mesh == null:
		var pg := CylinderMesh.new()
		pg.top_radius = 0.008
		pg.bottom_radius = 0.008
		pg.height = 0.024
		pg.radial_segments = 6
		_peg_mesh = _chrome_mesh(pg)
	if _slash_ring_mesh == null:
		var sr := TorusMesh.new()
		sr.inner_radius = 0.42
		sr.outer_radius = 0.48
		sr.rings = 24
		sr.ring_segments = 6
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(1.0, 0.22, 0.60, 0.55)
		smat.emission_enabled = true
		smat.emission = PINK
		smat.emission_energy_multiplier = 3.6
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		sr.material = smat
		_slash_ring_mesh = sr
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
	_return_age = 0.0
	_outbound_dist = 0.0
	_outbound_origin = p_origin
	_hit_ids.clear()
	_hit_outbound.clear()
	_did_hit_any = false
	_first_target = null
	_first_point = p_origin
	_notified_throw = false
	_notified_return = false
	_finished = false
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
	_life = 2.9
	_build_visual()
	var ev := _owner_evan_visual()
	if ev != null:
		ev.call("on_boomerang_thrown")
		_notified_throw = true


func _owner_evan_visual() -> Node:
	if is_instance_valid(owner_node):
		var model := owner_node.get_node_or_null("Model")
		if model != null and model.has_method("on_boomerang_thrown"):
			return model
	return null


func _build_visual() -> void:
	_ensure_meshes()
	_visual = Node3D.new()
	_visual.name = "BoomerangGuitar"
	_visual.scale = Vector3.ONE * 1.18
	add_child(_visual)
	var tilt := Node3D.new()
	tilt.name = "GuitarTilt"
	tilt.rotation_degrees.z = 14.0
	_visual.add_child(tilt)
	_spinner = Node3D.new()
	_spinner.name = "GuitarSpinner"
	tilt.add_child(_spinner)

	var body := MeshInstance3D.new()
	body.mesh = _body_mesh
	body.position.z = 0.06
	_spinner.add_child(body)
	var neck := MeshInstance3D.new()
	neck.mesh = _neck_mesh
	neck.position = Vector3(0.0, 0.008, -0.19)
	_spinner.add_child(neck)
	var head := MeshInstance3D.new()
	head.mesh = _head_mesh
	head.position = Vector3(0.0, 0.008, -0.40)
	head.rotation_degrees.z = -8.0
	_spinner.add_child(head)

	var pickup := MeshInstance3D.new()
	pickup.mesh = _pickup_mesh
	pickup.position = Vector3(0.0, 0.032, 0.02)
	_spinner.add_child(pickup)
	var bridge := MeshInstance3D.new()
	bridge.mesh = _bridge_mesh
	bridge.position = Vector3(0.0, 0.032, 0.14)
	_spinner.add_child(bridge)

	for pi in range(6):
		var peg := MeshInstance3D.new()
		peg.mesh = _peg_mesh
		peg.position = Vector3(-0.044, 0.010, -0.36 - float(pi) * 0.015)
		peg.rotation_degrees.z = 90.0
		_spinner.add_child(peg)

	if not Settings.reduced_motion():
		var slash := MeshInstance3D.new()
		slash.mesh = _slash_ring_mesh
		_spinner.add_child(slash)

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
	if _notified_throw and not _notified_return:
		_notified_return = true
		var ev := _owner_evan_visual()
		if ev != null:
			ev.call("on_boomerang_caught", false)
		returned.emit(false)


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


func _damage_bike(bike_node: Node, point: Vector3, dmg_amount: float, sub_suffix: String) -> void:
	var root := _resolve_bike(bike_node)
	if root == null or root == owner_node:
		return
	var victim_id := str(root.get("player_id")) if "player_id" in root else ""
	# The shooter must never mutate a remote proxy — the victim's own client
	# resolves its damage against its authoritative local bike.
	var local_uid := _local_uid()
	if local_uid != "" and owner_id == local_uid and victim_id != "" and victim_id != local_uid:
		var tree := get_tree()
		if tree != null:
			var combat := tree.get_first_node_in_group("local_combat")
			if combat != null:
				combat.emit_signal("hit_confirmed")
			if tree.current_scene != null:
				var net := tree.current_scene.get_node_or_null("ArenaNet")
				if net != null and net.has_method("note_local_damage_shown"):
					net.call("note_local_damage_shown", victim_id)
		VFX.damage_number(_fx_parent(), point + Vector3(0.0, 0.45, 0.0),
				dmg_amount, Color(1.0, 0.88, 0.26))
		return
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
	var sub := ("%s:v%s%s" % [token, victim_id, sub_suffix]) if token != "" else ""
	controller.call("take_damage", dmg_amount, owner_id, root.global_position, sub)


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
	var dmg_amount := damage * 0.55 if (not _outbound and _hit_outbound.has(id)) else damage
	var sub_suffix := ":o" if _outbound else ":r"
	# `hit` is an enemy-hit confirmation, so scenery contact must not latch it.
	# Only a bike / destructible / hazard that actually took an action counts.
	var actionable := false
	var dir := velocity.normalized()
	var surface := "metal"
	if node.name == "Ground":
		surface = "ground"
	if node.is_in_group("bike"):
		actionable = true
		_damage_bike(node, point, dmg_amount, sub_suffix)
	elif node.is_in_group("destructible"):
		if node.has_method("smash"):
			actionable = true
			node.call("smash", dir * SMASH_IMPULSE)
	elif node.is_in_group("hazard"):
		if node.has_method("ignite"):
			actionable = true
			var sub := ("%s:d%d" % [token, id]) if token != "" else ""
			node.call("ignite", owner_id, sub)
	if actionable:
		_did_hit_any = true
		if _first_target == null:
			_first_target = node
			_first_point = point
	VFX.impact(_fx_parent(), point, PINK, dir, surface, normal)


func _finish(was_caught: bool = false) -> void:
	if _finished:
		return
	_finished = true
	if _did_hit_any and _first_target != null:
		hit.emit(_first_target, _first_point)
	if _notified_throw and not _notified_return:
		_notified_return = true
		var ev := _owner_evan_visual()
		if ev != null:
			ev.call("on_boomerang_caught", was_caught)
	returned.emit(was_caught)
	_release_light()
	queue_free()


func _steer_return(delta: float) -> void:
	var target := _outbound_origin
	if is_instance_valid(owner_node) and owner_node is Node3D:
		var ev := _owner_evan_visual()
		if ev != null and ev.has_method("get_guitar_world_pos"):
			target = ev.call("get_guitar_world_pos")
		else:
			target = (owner_node as Node3D).global_position + Vector3(0.0, 1.05, 0.0)
	var to_target := target - global_position
	var dist_to_owner := to_target.length()
	if dist_to_owner < 1e-4:
		return
	# Rotate the heading along the great-circle arc rather than lerping the
	# velocity vector: a lerp between opposite directions passes through ~zero
	# and the guitar stalls instead of coming home.
	var dir_now := velocity.normalized() if velocity.length_squared() > 1e-8 else -to_target.normalized()
	var dir_target := to_target.normalized()
	var dot := clampf(dir_now.dot(dir_target), -1.0, 1.0)
	var angle := acos(dot)
	var blend := clampf(delta * (6.8 + _return_age * 6.0), 0.0, 1.0)
	if angle > 1e-4:
		var axis := dir_now.cross(dir_target)
		if axis.length_squared() < 1e-8:
			axis = dir_now.cross(Vector3.UP)
			if axis.length_squared() < 1e-8:
				axis = dir_now.cross(Vector3.RIGHT)
		dir_now = dir_now.rotated(axis.normalized(), minf(angle * blend, angle))
	# Keep a brisk homing speed with a close-range catch boost so it snaps right into Evan's hands.
	var home_speed := maxf(_base_speed * 0.96, 18.0) + (8.0 if dist_to_owner < 10.0 else 0.0)
	velocity = dir_now.normalized() * home_speed


func _physics_process(delta: float) -> void:
	_age += delta
	if _inert or _age >= _life:
		_finish(false)
		return
	if _visual != null and not Settings.reduced_motion():
		_spinner.rotate_object_local(Vector3.UP, delta * SPIN_RATE)

	if _outbound:
		if _age >= OUTBOUND_TIME * 0.78 or _outbound_dist >= OUTBOUND_DIST * 0.78:
			var cur_dir := velocity.normalized() if velocity.length_squared() > 1e-6 else Vector3.FORWARD
			var right := cur_dir.cross(Vector3.UP)
			right = right.normalized() if right.length_squared() > 1e-6 else Vector3.RIGHT
			var curved_dir := (cur_dir + right * (0.30 * delta)).normalized()
			velocity = curved_dir * maxf(_base_speed * 0.65, velocity.length() * (1.0 - 1.5 * delta))
		if _age >= OUTBOUND_TIME or _outbound_dist >= OUTBOUND_DIST:
			_outbound = false
			_return_age = 0.0
			_hit_outbound = _hit_ids.duplicate()
			_hit_ids.clear()
	if not _outbound:
		_return_age += delta
		if is_instance_valid(owner_node) and owner_node is Node3D \
				and global_position.distance_to((owner_node as Node3D).global_position + Vector3(0.0, 0.9, 0.0)) <= RETURN_ARRIVE:
			_finish(true)
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
	var sweep_dir := velocity.normalized() if velocity.length_squared() > 1e-8 else Vector3.FORWARD
	var sweep_right := sweep_dir.cross(Vector3.UP)
	sweep_right = sweep_right.normalized() if sweep_right.length_squared() > 1e-6 else Vector3.RIGHT
	var result: Dictionary = {}
	for offset_x in [0.0, 0.38, -0.38]:
		var off := sweep_right * float(offset_x)
		_ray_query.from = from + off
		_ray_query.to = to + off
		result = world.direct_space_state.intersect_ray(_ray_query)
		if not result.is_empty():
			break
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
