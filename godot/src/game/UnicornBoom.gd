extends Node3D
## LEA UNICORN ultimate — UNICORN BOOM.
## She spreads her wings, leaps into the air and flies along an arc into the
## target zone, then lands with a rainbow shockwave. Same kill rule as the
## other specials (meteor / devil hand): CombatAoe.apply_lethal_blast() with
## fail-closed victim authority and a 7.5 m zone. Wire kind stays "meteor".

signal impacted(point: Vector3)

const FALL_DURATION := 2.0
const BLAST_RADIUS := 7.5
const APEX_HEIGHT := 6.2
const VFX := preload("res://src/game/VfxFactory.gd")
const COMBAT_AOE := preload("res://src/game/CombatAoe.gd")

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
var _start_pos := Vector3.ZERO
var _flight: Node3D = null
var _trail: GPUParticles3D = null
var _telegraph: MeshInstance3D = null
var _light: OmniLight3D = null

static var _body_mesh: CapsuleMesh = null
static var _wing_mesh: BoxMesh = null
static var _horn_mesh: CylinderMesh = null
static var _spark_mesh: SphereMesh = null
static var _spark_ramp: GradientTexture1D = null
static var _ring_mesh: CylinderMesh = null


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
	sm.radius = 0.075
	sm.height = 0.15
	sm.radial_segments = 6
	sm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(1.0, 0.78, 0.94, 0.92)
	smat.emission_enabled = true
	smat.emission = Color(0.92, 0.42, 0.94)
	smat.emission_energy_multiplier = 3.2
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.material = smat
	_spark_mesh = sm
	_spark_ramp = VFX._ramp([
		Color(1.0, 0.92, 0.70, 0.98),
		Color(0.98, 0.48, 0.86, 0.72),
		Color(0.32, 0.42, 0.90, 0.0),
	])
	var rm := CylinderMesh.new()
	rm.top_radius = 1.0
	rm.bottom_radius = 1.0
	rm.height = 0.035
	rm.radial_segments = 28
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(1.0, 0.46, 0.82, 0.65)
	rmat.emission_enabled = true
	rmat.emission = Color(0.94, 0.32, 0.78)
	rmat.emission_energy_multiplier = 2.8
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.material = rmat
	_ring_mesh = rm


func setup(p_owner_id: String, p_owner_node: Node, p_target_pos: Vector3,
		p_damage: float, p_token: String, p_color: Color = Color(1.0, 0.55, 0.88),
		p_fall_duration: float = 2.0, p_blast_radius: float = 7.5,
		p_visual_style: String = "unicorn_boom") -> void:
	if not is_finite(p_damage) or not is_finite(p_blast_radius) or p_blast_radius <= 0.0 \
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
	_start_pos = (p_owner_node as Node3D).global_position if p_owner_node is Node3D else target_pos
	global_position = _start_pos
	global_position.y = maxf(0.0, _start_pos.y) + 0.6
	var model := p_owner_node.get_node_or_null("Model") if is_instance_valid(p_owner_node) else null
	if model != null and model.has_method("trigger_boom"):
		model.call("trigger_boom")
	_ensure_meshes()
	_build_flight()
	add_to_group("meteor_strike")


func _build_flight() -> void:
	_telegraph = MeshInstance3D.new()
	_telegraph.name = "BoomTelegraph"
	_telegraph.mesh = _ring_mesh
	_telegraph.global_position = Vector3(target_pos.x, maxf(0.0, target_pos.y) + 0.04, target_pos.z)
	if get_tree() != null and get_tree().current_scene is Node3D:
		(get_tree().current_scene as Node3D).add_child(_telegraph)
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
		_trail = GPUParticles3D.new()
		_trail.name = "RainbowTrail"
		_trail.amount = maxi(10, int(36 * Settings.quality_multiplier()))
		_trail.lifetime = 0.55
		_trail.local_coords = false
		_trail.visibility_aabb = AABB(Vector3(-2.0, -2.0, -2.0), Vector3(4.0, 4.0, 4.0))
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3.UP
		pm.spread = 36.0
		pm.gravity = Vector3(0.0, -1.5, 0.0)
		pm.initial_velocity_min = 0.4
		pm.initial_velocity_max = 1.8
		pm.scale_min = 0.25
		pm.scale_max = 0.85
		pm.color_ramp = _spark_ramp
		_trail.process_material = pm
		_trail.draw_pass_1 = _spark_mesh
		add_child(_trail)
		_trail.emitting = true
	if Settings.quality_multiplier() >= 0.5:
		_light = OmniLight3D.new()
		_light.name = "BoomLight"
		_light.light_color = Color(1.0, 0.52, 0.86)
		_light.light_energy = 2.8
		_light.omni_range = 5.5
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
	if is_instance_valid(_telegraph):
		_telegraph.queue_free()


func _physics_process(delta: float) -> void:
	if not _armed or _detonated:
		return
	_age += delta
	var t := clampf(_age / fall_duration, 0.0, 1.0)
	var flat := _start_pos.lerp(target_pos, t)
	var arc := sin(t * PI) * APEX_HEIGHT
	var y := lerpf(maxf(0.0, _start_pos.y) + 0.6, maxf(0.0, target_pos.y) + 0.5, t) + arc
	var next := Vector3(flat.x, y, flat.z)
	var dir := next - global_position
	if dir.length_squared() > 1e-6:
		global_position = next
		if _flight != null:
			var up := Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.FORWARD
			_flight.basis = Basis.looking_at(dir.normalized(), up)
			var flap := 1.0 + 0.28 * sin(_age * 14.0)
			for wing in _flight.get_children():
				if str(wing.name).begins_with("FlightWing"):
					(wing as Node3D).scale.y = flap
	if is_instance_valid(_telegraph):
		var s := 1.0 + 0.22 * sin(_age * 7.0)
		_telegraph.scale = Vector3(s, 1.0, s)
	if t >= 1.0:
		_detonate()


func _detonate() -> void:
	if _detonated:
		return
	_detonated = true
	if is_in_group("meteor_strike"):
		remove_from_group("meteor_strike")
	_release_light()
	if is_instance_valid(_telegraph):
		_telegraph.queue_free()
		_telegraph = null
	var reduced := Settings.reduced_motion()
	var quality := Settings.quality_multiplier()
	var fx := get_parent() as Node3D
	if fx == null and get_tree() != null:
		fx = get_tree().current_scene as Node3D
	if fx != null:
		_impact_vfx(fx, reduced, quality)
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		if sfx.has_method("play_3d"):
			sfx.call("play_3d", "explosion", target_pos, 2.0, 0.72)
		elif sfx.has_method("play"):
			sfx.call("play", "explosion", 2.0, 0.72)
	var cam := get_tree().get_first_node_in_group("camera_rig") if get_tree() != null else null
	if cam != null and cam.has_method("add_shake"):
		var cam_dist := (cam as Node3D).global_position.distance_to(target_pos) if cam is Node3D else 0.0
		cam.call("add_shake", 0.75 * clampf(1.0 - cam_dist / 65.0, 0.15, 1.0))
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
	kill_tween.tween_interval(0.12)
	kill_tween.tween_callback(queue_free)


func _impact_vfx(fx: Node3D, reduced: bool, quality: float) -> void:
	var ground_y := maxf(0.0, target_pos.y)
	if reduced:
		VFX._static_cue(fx, Vector3(target_pos.x, ground_y + 0.40, target_pos.z),
				Color(0.98, 0.42, 0.82), blast_radius * 0.90, 0.24)
		return
	var ground_pos := Vector3(target_pos.x, ground_y + 0.06, target_pos.z)
	VFX._ring_quad(fx, ground_pos, blast_radius * 0.72,
			Color(1.0, 0.48, 0.86, 0.94), 1.90, 0.34)
	VFX._ring_quad(fx, Vector3(target_pos.x, ground_y + 0.15, target_pos.z),
			blast_radius * 0.45, Color(0.52, 0.88, 1.0, 0.82), 2.15, 0.26)
	if quality > 0.0:
		VFX._particle(fx, Vector3(target_pos.x, ground_y + 0.35, target_pos.z),
				maxi(18, int(64 * quality)), 0.78, Vector3.UP, 64.0,
				3.5, 13.5, [
					Color(1.0, 0.62, 0.90, 0.96),
					Color(0.58, 0.48, 1.0, 0.80),
					Color(0.12, 0.18, 0.60, 0.0),
				], 0.85, Vector3(0.0, -5.0, 0.0), true,
				{"tex": "fire", "quad": 0.58, "explosiveness": 0.95})
