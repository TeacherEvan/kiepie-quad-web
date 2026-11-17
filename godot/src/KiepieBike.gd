extends VehicleBody3D
## Kiepie Bike - sport quad (ATV) vehicle controller for Godot 4.3.
## Controls (keyboard, arrows or WASD):
##   W / Up    throttle
##   S / Down  brake, then reverse
##   A / Left  steer left
##   D / Right steer right
##   Space     handbrake
##   Shift     turbo (hold while throttling) +30% power, flames from the exhaust
##   Q / E     dodge left / right: leap into a cartwheel to evade attacks
##   R         reset to spawn

@export var engine_power := 420.0
@export var turbo_boost := 1.30
@export var max_steer := 0.62
@export var steer_speed := 5.0
@export var brake_force := 2600.0
@export var reverse_force := 180.0
@export var visual_steer_scale := 0.75
@export var wheel_radius := 0.280
## Dodge: Q/E leap + cartwheel. Tunable together for feel.
@export var dodge_lift := 7.2          ## upward velocity on dodge (m/s)
@export var dodge_side := 5.5          ## lateral velocity (m/s)
@export var dodge_spin := 8.5          ## cartwheel rate about local forward (rad/s)
@export var dodge_duration := 0.72     ## seconds the cartwheel is left undamped
@export var dodge_cooldown := 1.0      ## seconds before another dodge

var turbo_active := false
var player_id := ""   ## set by CombatController for projectile hit attribution

var _steer := 0.0
var _spawn := Transform3D.IDENTITY
var _spawn_set := false
var _turbo_blend := 0.0
var _steer_sensitivity := 1.0
var _dodge_time := 0.0
var _dodge_cd := 0.0
var _ground_coyote := 0.0   ## brief grace so suspension bounce can't eat a dodge
var _was_grounded := false   ## visual-only landing detector
var _roost_accum := 0.0

@onready var _flames: GPUParticles3D = get_node_or_null("ExhaustFlames")
var _jet_plume: Node3D = null
var _jet_t := 0.0
@onready var _wheel_nodes := {
	"WheelFL": get_node_or_null("Model/Wheel_FL"),
	"WheelFR": get_node_or_null("Model/Wheel_FR"),
	"WheelRL": get_node_or_null("Model/Wheel_RL"),
	"WheelRR": get_node_or_null("Model/Wheel_RR"),
}
@onready var _steer_nodes := {
	"FL": get_node_or_null("Model/Steer_FL"),
	"FR": get_node_or_null("Model/Steer_FR"),
}
@onready var _wheels := {
	"FL": get_node("WheelFL"),
	"FR": get_node("WheelFR"),
	"RL": get_node("WheelRL"),
	"RR": get_node("WheelRR"),
}

func _ready() -> void:
	add_to_group("bike") # group is not persisted in the baked .tscn; register at runtime
	_spawn = global_transform
	_spawn_set = true
	_steer_sensitivity = clampf(float(Settings.get_value("controls", "steer_sensitivity", 1.0)), 0.3, 2.0)
	Settings.changed.connect(_on_settings_changed)
	VfxFactory.prewarm()
	_build_flames()

func _build_flames() -> void:
	if _flames:
		_flames.queue_free()
	var p := GPUParticles3D.new()
	p.name = "ExhaustFlames"
	p.amount = 72
	p.lifetime = 0.10
	p.one_shot = false
	p.emitting = false
	p.local_coords = true
	p.visibility_aabb = AABB(Vector3(-0.8, -0.8, -2.5), Vector3(1.6, 1.6, 3.0))

	var pm := ParticleProcessMaterial.new()
	# Jet afterburner core: focused supersonic exhaust aft (-Z) with razor spread
	# and zero gravity drop so it reads as a jet thrust plume, not a flamethrower.
	pm.direction = Vector3(0.0, 0.03, -1.0)
	pm.spread = 2.6
	pm.flatness = 0.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 26.0
	pm.scale_min = 0.55
	pm.scale_max = 1.15
	pm.particle_flag_align_y = true
	pm.color_ramp = VfxFactory._ramp([
		Color(1.0, 0.99, 0.94, 1.0),
		Color(0.36, 0.84, 1.0, 0.96),
		Color(0.22, 0.48, 1.0, 0.72),
		Color(1.0, 0.52, 0.14, 0.0),
	])
	pm.scale_curve = VfxFactory._curve([[0.0, 1.0], [0.35, 0.72], [1.0, 0.06]])
	p.process_material = pm

	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.030
	flame_mesh.height = 0.24
	flame_mesh.radial_segments = 6
	flame_mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	flame_mesh.material = mat
	p.draw_pass_1 = flame_mesh

	# Match the imported Silencer_Tip node: (-0.278, 0.487, -0.715) in the
	# bike's local frame (+Z is forward, so the exhaust sits at negative Z).
	p.position = Vector3(-0.278, 0.487, -0.715)

	# Inner afterburner jet cone + Mach shock diamonds for unmistakable turbine thrust.
	var plume := Node3D.new()
	plume.name = "JetPlume"
	plume.visible = false

	var outer_mesh := CylinderMesh.new()
	outer_mesh.top_radius = 0.002
	outer_mesh.bottom_radius = 0.062
	outer_mesh.height = 0.88
	outer_mesh.radial_segments = 12
	var outer_mat := StandardMaterial3D.new()
	outer_mat.albedo_color = Color(0.28, 0.76, 1.0, 0.48)
	outer_mat.emission_enabled = true
	outer_mat.emission = Color(0.25, 0.72, 1.0)
	outer_mat.emission_energy_multiplier = 3.6
	outer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	outer_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	outer_mesh.material = outer_mat
	var outer := MeshInstance3D.new()
	outer.name = "OuterCone"
	outer.mesh = outer_mesh
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	outer.rotation_degrees.x = -90.0
	outer.position = Vector3(0.0, 0.0, -0.44)
	plume.add_child(outer)

	var inner_mesh := CylinderMesh.new()
	inner_mesh.top_radius = 0.001
	inner_mesh.bottom_radius = 0.032
	inner_mesh.height = 0.48
	inner_mesh.radial_segments = 10
	var inner_mat := StandardMaterial3D.new()
	inner_mat.albedo_color = Color(0.92, 0.98, 1.0, 0.88)
	inner_mat.emission_enabled = true
	inner_mat.emission = Color(0.75, 0.95, 1.0)
	inner_mat.emission_energy_multiplier = 5.2
	inner_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	inner_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inner_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	inner_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	inner_mesh.material = inner_mat
	var inner := MeshInstance3D.new()
	inner.name = "InnerCore"
	inner.mesh = inner_mesh
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inner.rotation_degrees.x = -90.0
	inner.position = Vector3(0.0, 0.0, -0.24)
	plume.add_child(inner)

	var shock_mesh := SphereMesh.new()
	shock_mesh.radius = 0.036
	shock_mesh.height = 0.09
	shock_mesh.radial_segments = 8
	shock_mesh.rings = 4
	shock_mesh.material = inner_mat
	for idx in range(2):
		var ring := MeshInstance3D.new()
		ring.name = "MachDiamond%d" % idx
		ring.mesh = shock_mesh
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.rotation_degrees.x = 90.0
		ring.position = Vector3(0.0, 0.0, -0.22 - float(idx) * 0.24)
		ring.scale = Vector3.ONE * (1.0 - float(idx) * 0.26)
		plume.add_child(ring)

	p.add_child(plume)
	_jet_plume = plume
	add_child(p)
	_flames = p

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("reset_bike"):
		reset_bike()

	_dodge_time = maxf(0.0, _dodge_time - delta)
	_dodge_cd = maxf(0.0, _dodge_cd - delta)
	if _grounded():
		_ground_coyote = 0.12
	else:
		_ground_coyote = maxf(0.0, _ground_coyote - delta)
	if Input.is_action_just_pressed("dodge_left"):
		_try_dodge(-1.0)
	if Input.is_action_just_pressed("dodge_right"):
		_try_dodge(1.0)

	# Anti-rollover lives in _integrate_forces — see there.

	# Visual feedback only: hard landing throws a ground dust ring, fast
	# cornering kicks a rooster tail off the rear wheels. No physics is touched.
	var grounded := _grounded()
	var vy := linear_velocity.y
	if grounded and not _was_grounded and vy < -3.5:
		var rear: Vector3 = global_position - global_transform.basis.z * 0.66
		VfxFactory.dust_ring(self, Vector3(rear.x, 0.0, rear.z), 1.1, 4.5)
		_shake(0.08)
	_was_grounded = grounded
	if grounded and speed_kmh() > 42.0:
		_roost_accum += delta
		if _roost_accum >= 0.12:
			_roost_accum = 0.0
			for sx in [-0.55, 0.55]:
				var at: Vector3 = global_position + global_transform.basis.x * sx \
						- global_transform.basis.z * 0.66
				VfxFactory.roost(self, at, global_transform.basis.z)
	else:
		_roost_accum = 0.0

	var throttle := Input.get_axis("move_back", "move_forward")
	var steer_input := Input.get_axis("steer_right", "steer_left")

	# --- turbo: hold Shift while throttling ---
	var want_turbo := Input.is_action_pressed("turbo") and throttle > 0.1
	_turbo_blend = move_toward(_turbo_blend, 1.0 if want_turbo else 0.0, delta * 4.0)
	turbo_active = _turbo_blend > 0.35
	if _flames:
		_flames.emitting = turbo_active
	if _jet_plume != null:
		var jet_strength := _turbo_blend if turbo_active else (0.55 if (_flames and _flames.emitting) else 0.0)
		_jet_plume.visible = jet_strength > 0.04
		if _jet_plume.visible:
			_jet_t += delta
			var pulse := 0.92 + 0.12 * sin(_jet_t * 68.0)
			var w := lerpf(0.75, 1.15, jet_strength) * pulse
			_jet_plume.scale = Vector3(w, w, lerpf(0.45, 1.25, jet_strength) * pulse)

	var steer_cap := max_steer * _steer_sensitivity
	_steer = move_toward(_steer, steer_input * steer_cap, steer_speed * _steer_sensitivity * delta)
	_steer = clamp(_steer, -steer_cap, steer_cap)

	var braking := Input.is_action_pressed("brake")
	var power := engine_power * lerpf(1.0, turbo_boost, _turbo_blend)

	for key in _wheels.keys():
		var w: VehicleWheel3D = _wheels[key]
		if w == null or not is_instance_valid(w):
			continue  # test harnesses may strip/free wheel nodes mid-run
		w.engine_force = 0.0
		w.brake = 0.0
		if throttle > 0.0:
			w.engine_force = power * throttle
		elif throttle < 0.0:
			if linear_velocity.length() < 2.0:
				w.engine_force = -reverse_force * -throttle
			else:
				w.brake = brake_force
		if braking:
			w.brake = brake_force
		elif throttle == 0.0:
			w.brake = brake_force * 0.08

		if key == "FL" or key == "FR":
			w.steering = _steer

	# visual feedback: yaw the steering pivots and roll the wheel meshes
	for side in ["FL", "FR"]:
		var node: Node3D = _steer_nodes[side]
		if node:
			var target := _steer * visual_steer_scale
			node.rotation.y = lerp_angle(node.rotation.y, target, clamp(delta * 10.0, 0.0, 1.0))

	var speed := linear_velocity.length()
	var roll := (speed / maxf(wheel_radius, 0.01)) * delta
	if speed > 0.2:
		# Forward is local +Z (see AGENTS.md), so dotting with +basis.z keeps
		# the wheels rolling the right way under acceleration.
		var forward := linear_velocity.dot(global_transform.basis.z)
		if forward < 0.0:
			roll = -roll
	for key in _wheel_nodes.keys():
		var node: Node3D = _wheel_nodes[key]
		if node:
			node.rotate_x(roll)

func set_spawn(t: Transform3D) -> void:
	## Used by the multiplayer respawn system to move the reset point.
	_spawn = t


func reset_bike() -> void:
	global_transform = _spawn
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_steer = 0.0
	_turbo_blend = 0.0
	turbo_active = false
	_dodge_time = 0.0
	_dodge_cd = 0.0
	_ground_coyote = 0.0
	if _flames:
		_flames.emitting = false

func speed_kmh() -> float:
	return linear_velocity.length() * 3.6


func _shake(amount: float) -> void:
	if Settings.reduced_motion():
		return
	var cam := get_tree().get_first_node_in_group("camera_rig") if get_tree() != null else null
	if cam != null and cam.has_method("add_shake"):
		cam.call("add_shake", amount)


func _grounded() -> bool:
	for key in _wheels:
		var w: VehicleWheel3D = _wheels[key]
		if w != null and is_instance_valid(w) and w.is_in_contact():
			return true
	return false


func _try_dodge(dir: float) -> void:
	## Q = -1 (left), E = +1 (right). Ground-only, with a cooldown so it
	## cannot be spammed into infinite airtime.
	if _dodge_cd > 0.0 or _ground_coyote <= 0.0:
		return
	_dodge_cd = dodge_cooldown
	_dodge_time = dodge_duration

	var basis := global_transform.basis.orthonormalized()
	# The GLB's forward is local +Z; with Y up that makes local +X the bike's
	# LEFT. So dodge_left (Q, dir=-1) must hop toward +X. Applying velocity
	# (not impulse) keeps the leap independent of mass and reproducible.
	linear_velocity += Vector3.UP * dodge_lift
	linear_velocity += basis.x * (-dir * dodge_side)
	# Cartwheel about the forward axis, top rolling INTO the leap. Positive
	# rotation about +Z sends +Y toward -X; negate for a left (+X) roll.
	angular_velocity += basis.z * (dir * dodge_spin)
	VfxFactory.dust_puff(self, Vector3.ZERO, 28)


func _on_settings_changed(section: String, key: String, _value: Variant) -> void:
	if section == "controls" and key == "steer_sensitivity":
		_steer_sensitivity = clampf(float(Settings.get_value("controls", "steer_sensitivity", 1.0)), 0.3, 2.0)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Damp roll/pitch only, leaving yaw (steering) untouched. Must run here,
	# not in _physics_process: writing angular_velocity there clobbers the
	# wheel-generated yaw before the next solver step.
	var up := global_transform.basis.y.normalized()
	var av := state.angular_velocity
	var yaw := av.dot(up) * up
	var trans := av - yaw
	var lean := clampf(1.0 - up.dot(Vector3.UP), 0.0, 1.0)
	var damp := lerpf(0.80, 0.96, lean)
	if _dodge_time > 0.0:
		# Mid-cartwheel: the spin IS roll, so leave transverse angular
		# velocity undamped until the dodge window closes.
		damp = 0.0
	state.angular_velocity = yaw + trans * (1.0 - damp)
