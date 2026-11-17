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

@onready var _flames: GPUParticles3D = get_node_or_null("ExhaustFlames")
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
	_build_flames()

func _build_flames() -> void:
	if _flames:
		_flames.queue_free()
	var p := GPUParticles3D.new()
	p.name = "ExhaustFlames"
	p.amount = 110
	p.lifetime = 0.34
	p.one_shot = false
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-1.5, -1.0, -1.5), Vector3(3.0, 3.0, 4.0))

	var pm := ParticleProcessMaterial.new()
	# The GLB's forward axis is local +Z; the silencer tip is at the REAR (-Z).
	# Emit backwards, slightly up, out of the can — not forward at the front wheels.
	pm.direction = Vector3(0.0, 0.16, -1.0)
	pm.spread = 13.0
	pm.flatness = 0.0
	pm.gravity = Vector3(0.0, -0.7, 0.0)
	pm.initial_velocity_min = 4.2
	pm.initial_velocity_max = 7.4
	pm.angular_velocity_min = -40.0
	pm.angular_velocity_max = 40.0
	pm.scale_min = 0.45
	pm.scale_max = 1.65
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.96, 0.62, 1.0))
	grad.set_offset(0, 0.0)
	grad.set_color(1, Color(1.0, 0.55, 0.08, 0.95))
	grad.set_offset(1, 0.28)
	grad.add_point(0.62, Color(0.88, 0.22, 0.04, 0.85))
	grad.add_point(1.0, Color(0.18, 0.03, 0.01, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp
	p.process_material = pm

	var sm := SphereMesh.new()
	sm.radius = 0.075
	sm.height = 0.15
	sm.radial_segments = 8
	sm.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.62, 0.12, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.06, 1.0)
	mat.emission_energy_multiplier = 3.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = mat
	p.draw_pass_1 = sm

	# Match the imported Silencer_Tip node: (-0.278, 0.487, -0.715) in the
	# bike's local frame (+Z is forward, so the exhaust sits at negative Z).
	p.position = Vector3(-0.278, 0.487, -0.715)
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

	var throttle := Input.get_axis("move_back", "move_forward")
	var steer_input := Input.get_axis("steer_right", "steer_left")

	# --- turbo: hold Shift while throttling ---
	var want_turbo := Input.is_action_pressed("turbo") and throttle > 0.1
	_turbo_blend = move_toward(_turbo_blend, 1.0 if want_turbo else 0.0, delta * 4.0)
	turbo_active = _turbo_blend > 0.35
	if _flames:
		_flames.emitting = turbo_active

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
	# Lift + sideways hop. Applying velocity (not impulse) keeps the leap
	# independent of mass and exactly reproducible for the regression gate.
	linear_velocity += Vector3.UP * dodge_lift
	linear_velocity += basis.x * (dir * dodge_side)
	# Cartwheel about the bike's forward axis. Rotating +Z takes local +Y
	# toward -X (left), so a left dodge (dir=-1) rolls positively.
	angular_velocity += basis.z * (-dir * dodge_spin)
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
