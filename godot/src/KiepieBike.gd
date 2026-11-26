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

const HANDLING := preload("res://src/game/VehicleHandling.gd")

@export var engine_power := 235.0
@export var turbo_boost := 1.24
@export var overdrive_boost := 1.38
@export var max_steer := 0.56
@export var steer_speed := 4.8
@export var brake_force := 18.0
@export var handbrake_force := 26.0
@export var coast_brake := 0.12      ## rolling drag fraction of brake_force when coasting (no throttle/brake) — keeps the bike gliding instead of scrubbing speed
@export var reverse_force := 265.0
@export var visual_steer_scale := 0.75
@export var wheel_radius := 0.280
## Per-vehicle visual + weapon profile (Cars stay identical — see
## VehicleRegistry). Baked scenes default to the bike; the assigned vehicle
## is applied at runtime in _ready so one .tscn serves every player.
@export var vehicle_profile := "bike"
## Dodge: Q/E leap + cartwheel. Tunable together for feel.
@export var dodge_lift := 7.2          ## upward velocity on dodge (m/s)
@export var dodge_side := 5.5          ## lateral velocity (m/s)
@export var dodge_spin := 8.5          ## cartwheel rate about local forward (rad/s)
@export var dodge_duration := 0.72     ## seconds the cartwheel is left undamped
@export var dodge_cooldown := 1.0      ## seconds before another dodge
## (Rollover immunity is enforced in _integrate_forces — see AGENTS.md.)

var turbo_active := false
var player_id := ""   ## set by CombatController for projectile hit attribution
var loop_up := Vector3.ZERO  ## non-zero inside a 360° LoopZone (local track normal pointing toward loop center)
var loop_tangent := Vector3.ZERO
var loop_center_pull := Vector3.ZERO
var _assigned_vehicle: StringName = &""

var _steer := 0.0
var _spawn := Transform3D.IDENTITY
var _fallback_spawn := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.6, 0.0))
var _bound_x := 145.0
var _bound_z := 145.0
var _turbo_blend := 0.0
var _steer_sensitivity := 1.0
var _dodge_time := 0.0
var _dodge_elapsed := 0.0
var _dodge_cd := 0.0
var _ground_coyote := 0.0   ## brief grace so suspension bounce can't eat a dodge
var _was_grounded := false   ## visual-only landing detector
var _roost_accum := 0.0
var _skid_smoke_accum := 0.0
var _pending_reset := false
var _throttle_in := 0.0
var _steer_in := 0.0
var _dink_cd := 0.0       ## rate-limit the landing ping (dink)
var _scrape_cd := 0.0     ## rate-limit the handbrake slide rumble (scrape)
var _was_turbo := false
var _turbo_sfx_cd := 0.0
var _engine_player: AudioStreamPlayer3D = null
## Set by CombatController while an overdrive pickup is live: counts as boost
## for the turbo blend/flames so the flame visual lasts the whole effect, not
## one physics frame.
var overdrive_active := false

@onready var _flames: GPUParticles3D = get_node_or_null("ExhaustFlames")
var _jet_plume: Node3D = null
var _jet_t := 0.0
@onready var _wheel_nodes := {
	"WheelFL": _find_model_node(get_node_or_null("Model"), "Wheel_FL"),
	"WheelFR": _find_model_node(get_node_or_null("Model"), "Wheel_FR"),
	"WheelRL": _find_model_node(get_node_or_null("Model"), "Wheel_RL"),
	"WheelRR": _find_model_node(get_node_or_null("Model"), "Wheel_RR"),
}
@onready var _steer_nodes := {
	"FL": _find_model_node(get_node_or_null("Model"), "Steer_FL"),
	"FR": _find_model_node(get_node_or_null("Model"), "Steer_FR"),
}
const POGO_VISUAL := preload("res://src/game/PogoVisual.gd")
const EVAN_VISUAL := preload("res://src/game/EvanVisual.gd")
const LEA_VISUAL := preload("res://src/game/LeaVisual.gd")
@onready var _wheels := {
	"FL": get_node("WheelFL"),
	"FR": get_node("WheelFR"),
	"RL": get_node("WheelRL"),
	"RR": get_node("WheelRR"),
}

func _enter_tree() -> void:
	# Swap the visual shell BEFORE children _ready (parent enters first) so
	# CombatController caches the post-swap muzzle anchors. Physics, wheels and
	# collision are untouched — only Model (and hence the anchors) changes.
	_assign_vehicle()

func _ready() -> void:
	add_to_group("bike") # group is not persisted in the baked .tscn; register at runtime
	_init_world_bounds()
	if _is_pose_valid(global_transform):
		var clean_init := Transform3D(global_transform.basis.orthonormalized(), global_transform.origin)
		_spawn = clean_init
		_fallback_spawn = clean_init
	else:
		_spawn = _fallback_spawn
	_steer_sensitivity = clampf(float(Settings.get_value("controls", "steer_sensitivity", 1.0)), 0.3, 2.0)
	Settings.changed.connect(_on_settings_changed)
	if typeof(Match) != TYPE_NIL and Match != null and Match.has_signal("roster_changed"):
		if not Match.roster_changed.is_connected(refresh_vehicle_assignment):
			Match.roster_changed.connect(refresh_vehicle_assignment)
	VfxFactory.prewarm()
	_build_flames()

func _exit_tree() -> void:
	if Settings != null and Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.disconnect(_on_settings_changed)
	if typeof(Match) != TYPE_NIL and Match != null and Match.has_signal("roster_changed"):
		if Match.roster_changed.is_connected(refresh_vehicle_assignment):
			Match.roster_changed.disconnect(refresh_vehicle_assignment)

func _build_flames() -> void:
	if _flames:
		_flames.queue_free()
	var p := GPUParticles3D.new()
	p.name = "ExhaustFlames"
	p.amount = maxi(8, int(72 * Settings.quality_multiplier()))
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
	var is_evan := vehicle_profile == "evan"
	pm.color_ramp = VfxFactory._ramp([
		Color(1.0, 0.92, 0.96, 1.0),
		Color(1.0, 0.12, 0.50, 0.96),
		Color(0.75, 0.04, 0.25, 0.72),
		Color(0.45, 0.02, 0.14, 0.0),
	] if is_evan else [
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

	# Match the imported rim: (-0.278, 0.487, -0.715) for the bike's exhaust,
	# the pogo spring for NARDUS, and Exhaust_Tip for Aston Martin.
	p.position = _exhaust_position()

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
	outer_mat.albedo_color = Color(1.0, 0.10, 0.48, 0.48) if is_evan else Color(0.28, 0.76, 1.0, 0.48)
	outer_mat.emission_enabled = true
	outer_mat.emission = Color(1.0, 0.12, 0.46) if is_evan else Color(0.25, 0.72, 1.0)
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
	inner_mat.albedo_color = Color(1.0, 0.82, 0.94, 0.88) if is_evan else Color(0.92, 0.98, 1.0, 0.88)
	inner_mat.emission_enabled = true
	inner_mat.emission = Color(1.0, 0.36, 0.70) if is_evan else Color(0.75, 0.95, 1.0)
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

func _find_model_node(model: Node, node_name: String) -> Node3D:
	if model == null:
		return null
	var direct := model.get_node_or_null(node_name) as Node3D
	if direct != null:
		return direct
	return model.find_child(node_name, true, false) as Node3D


func _resolve_vehicle_pref(lookup_id: String) -> String:
	if typeof(Match) != TYPE_NIL and Match != null and "players" in Match:
		var mp: Variant = Match.get("players")
		if mp is Dictionary and (mp as Dictionary).has(lookup_id):
			var row: Variant = (mp as Dictionary)[lookup_id]
			if row is Dictionary and (row as Dictionary).has("vehicle"):
				return VehicleRegistry.sanitize_preference(str((row as Dictionary).get("vehicle", "")))
	if typeof(Settings) != TYPE_NIL and Settings != null and Settings.has_method("preferred_vehicle"):
		return str(Settings.call("preferred_vehicle"))
	return ""


func _exhaust_position() -> Vector3:
	var model := get_node_or_null("Model")
	var tip := _find_model_node(model, "Exhaust_Tip")
	if tip != null and model != null:
		var pos := tip.position
		var cur: Node = tip.get_parent()
		while cur != null and cur != model:
			if cur is Node3D:
				pos = (cur as Node3D).transform * pos
			cur = cur.get_parent()
		if model is Node3D:
			pos = (model as Node3D).transform * pos
		return pos
	if vehicle_profile == "pogo":
		return Vector3(0.0, 0.30, -0.18)
	if vehicle_profile == "evan":
		return Vector3(0.0, 0.18, -0.34)
	if vehicle_profile == "lea":
		return Vector3(0.0, 0.52, -0.42)
	if vehicle_profile == "aston":
		return Vector3(0.0, 0.39, -1.35)
	return Vector3(-0.278, 0.487, -0.715)


func _assign_vehicle() -> StringName:
	## Remote-player identity rule: the vehicle is a deterministic hash of the
	## player id (with roster-level guarantee that at least one player in any
	## active match roster is assigned NARDUS), so a baked shared .tscn picks
	## the right model for every peer with zero extra network traffic.
	var id := ""
	if typeof(Supabase) != TYPE_NIL and Supabase != null and "user_id" in Supabase:
		id = str(Supabase.user_id)
	var lookup_id := id if id != "" else "anonymous"
	var roster_keys: Array = []
	if typeof(Match) != TYPE_NIL and Match != null and "players" in Match:
		var mp: Variant = Match.get("players")
		if mp is Dictionary and not (mp as Dictionary).is_empty():
			roster_keys = (mp as Dictionary).keys()
	var assigned := VehicleRegistry.resolve_for_player(lookup_id, roster_keys, _resolve_vehicle_pref(lookup_id))
	# Fail safe: never commit an identity whose model cannot be loaded, or the
	# bike keeps an Evan/Pogo profile with the previous vehicle's visible shell.
	if assigned != VehicleRegistry.VEHICLE_BIKE and load(VehicleRegistry.model_path(assigned)) == null:
		push_warning("VehicleRegistry: could not load %s; keeping previous assignment" % VehicleRegistry.model_path(assigned))
		return _assigned_vehicle
	_assigned_vehicle = assigned
	vehicle_profile = VehicleRegistry.profile(assigned)
	if assigned != VehicleRegistry.VEHICLE_BIKE:
		_swap_model(assigned, VehicleRegistry.model_path(assigned))
	return assigned


func refresh_vehicle_assignment() -> void:
	var id := ""
	if typeof(Supabase) != TYPE_NIL and Supabase != null and "user_id" in Supabase:
		id = str(Supabase.user_id)
	var lookup_id := id if id != "" else "anonymous"
	var roster_keys: Array = []
	if typeof(Match) != TYPE_NIL and Match != null and "players" in Match:
		var mp: Variant = Match.get("players")
		if mp is Dictionary and not (mp as Dictionary).is_empty():
			roster_keys = (mp as Dictionary).keys()
	var assigned := VehicleRegistry.resolve_for_player(lookup_id, roster_keys, _resolve_vehicle_pref(lookup_id))
	if assigned == _assigned_vehicle:
		return
	var glb_path := VehicleRegistry.model_path(assigned)
	if assigned != VehicleRegistry.VEHICLE_BIKE and load(glb_path) == null:
		push_warning("VehicleRegistry: could not load %s; retrying on next roster sync" % glb_path)
		return
	_assigned_vehicle = assigned
	vehicle_profile = VehicleRegistry.profile(assigned)
	_swap_model(assigned, glb_path)
	if _flames != null:
		_build_flames()
	var combat := get_node_or_null("CombatController")
	if combat != null:
		var cannons := combat.get_node_or_null("SideCannons")
		if cannons != null and cannons.has_method("setup"):
			var pcol: Color = combat.get("player_color") if "player_color" in combat else Color(1.0, 0.48, 0.12)
			cannons.call("setup", self, lookup_id, Callable(combat, "_on_projectile_hit"), pcol, vehicle_profile)


func _swap_model(assigned: StringName, glb_path: String) -> void:
	## Swap the baked bike GLB for the assigned vehicle's model (same runtime
	## pattern the remote proxies use). Physics (wheels, mass, collision) is
	## identical — only the visual shell changes.
	var scene: PackedScene = load(glb_path)
	if scene == null:
		push_warning("VehicleRegistry: could not load %s" % glb_path)
		return
	var new_model := scene.instantiate()
	new_model.name = "Model"
	# give the rider its bounce personality BEFORE add_child so Godot runs _ready() and _physics_process()!
	if VehicleRegistry.is_pogo(assigned):
		var rider := new_model.get_node_or_null("Rider")
		if rider != null:
			rider.set_script(POGO_VISUAL)
	# Evan's animation driver sits on the GLB root (the skinned model itself).
	if VehicleRegistry.is_evan(assigned):
		new_model.set_script(EVAN_VISUAL)
	# Lea's animation driver also sits on the GLB root (skinned creature model).
	if VehicleRegistry.is_lea(assigned):
		new_model.set_script(LEA_VISUAL)
	var old := get_node_or_null("Model")
	if old != null:
		remove_child(old)
		old.queue_free()
	add_child(new_model)
	# refresh runtime visual lookups — supports both top-level (KiepieBike) and
	# nested (Aston_Martin Steer_FL/Wheel_FL) wheel hierarchies.
	_wheel_nodes = {
		"WheelFL": _find_model_node(new_model, "Wheel_FL"),
		"WheelFR": _find_model_node(new_model, "Wheel_FR"),
		"WheelRL": _find_model_node(new_model, "Wheel_RL"),
		"WheelRR": _find_model_node(new_model, "Wheel_RR"),
	}
	_steer_nodes = {
		"FL": _find_model_node(new_model, "Steer_FL"),
		"FR": _find_model_node(new_model, "Steer_FR"),
	}


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("reset_bike"):
		var combat := get_node_or_null("CombatController")
		var is_practice := combat != null and bool(combat.get("practice_mode"))
		if Match == null or not Match.is_playing() or is_practice:
			reset_bike()
	if not _is_pose_valid(global_transform) or not linear_velocity.is_finite() or not angular_velocity.is_finite():
		reset_bike()
		return

	var grounded := _grounded()
	if _dodge_time > 0.0:
		_dodge_elapsed += delta
		_dodge_time = maxf(0.0, _dodge_time - delta)
		if _dodge_elapsed > 0.35 and grounded:
			_dodge_time = 0.0
	_dodge_cd = maxf(0.0, _dodge_cd - delta)
	_dink_cd = maxf(0.0, _dink_cd - delta)
	_scrape_cd = maxf(0.0, _scrape_cd - delta)
	_turbo_sfx_cd = maxf(0.0, _turbo_sfx_cd - delta)
	if grounded:
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
	var vy := linear_velocity.y
	if grounded and not _was_grounded and vy < -3.5:
		var rear: Vector3 = global_position - global_transform.basis.z * 0.66
		VfxFactory.dust_ring(_fx_parent(), Vector3(rear.x, maxf(0.0, rear.y - 0.25), rear.z), 1.1, 4.5)
		_shake(0.08)
		if not Settings.reduced_motion() and DisplayServer.get_name() != "headless" \
				and (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")):
			Input.vibrate_handheld(28)
		if _dink_cd <= 0.0:
			_dink_cd = 0.45
			_play_sfx("impact", -2.0)
	elif grounded and not _was_grounded and vy < -1.5 and _dink_cd <= 0.0:
		# Soft landing (no dust ring): wheels give a light metallic ping.
		_dink_cd = 0.45
		_play_sfx("dink")
	_was_grounded = grounded
	if grounded and speed_kmh() > 42.0:
		_roost_accum += delta
		if _roost_accum >= 0.12:
			_roost_accum = 0.0
			for sx in [-0.55, 0.55]:
				var at: Vector3 = global_position + global_transform.basis.x * sx \
						- global_transform.basis.z * 0.66
				VfxFactory.roost(_fx_parent(), at, global_transform.basis.z)
	else:
		_roost_accum = 0.0

	var throttle := Input.get_axis("move_back", "move_forward")
	var steer_input := Input.get_axis("steer_right", "steer_left")
	_throttle_in = throttle
	_steer_in = steer_input

	# --- turbo: hold Shift while throttling ---
	var want_turbo := (Input.is_action_pressed("turbo") and throttle > 0.1) or overdrive_active
	_turbo_blend = move_toward(_turbo_blend, 1.0 if want_turbo else 0.0, delta * 4.0)
	turbo_active = _turbo_blend > 0.35
	if turbo_active and not _was_turbo and _turbo_sfx_cd <= 0.0:
		_turbo_sfx_cd = 0.6
		_play_sfx("turbo")
	_was_turbo = turbo_active
	if is_instance_valid(_engine_player):
		var speed_ratio := clampf(speed_kmh() / 125.0, 0.0, 1.0)
		var target_pitch := 0.78 + speed_ratio * 0.65 + (0.18 if turbo_active else 0.0)
		_engine_player.pitch_scale = lerpf(_engine_player.pitch_scale, target_pitch, 1.0 - exp(-8.0 * delta))
	var reduced := Settings.reduced_motion()
	if _flames:
		_flames.emitting = turbo_active and not reduced and Settings.quality_multiplier() > 0.0
	if _jet_plume != null:
		var jet_strength := _turbo_blend if turbo_active else (0.55 if (_flames and _flames.emitting) else 0.0)
		_jet_plume.visible = jet_strength > 0.04 and not reduced
		if _jet_plume.visible:
			_jet_t = fmod(_jet_t + delta, TAU)
			var pulse := 0.92 + 0.12 * sin(_jet_t * 68.0)
			var w := lerpf(0.75, 1.15, jet_strength) * pulse
			_jet_plume.scale = Vector3(w, w, lerpf(0.45, 1.25, jet_strength) * pulse)

	var spd := linear_velocity.length()
	var steer_cap := HANDLING.effective_steer_cap(spd, max_steer, _steer_sensitivity)
	var target_steer := steer_input * steer_cap
	var rate := HANDLING.effective_steer_rate(steer_speed, _steer_sensitivity, absf(target_steer) < absf(_steer))
	_steer = clampf(move_toward(_steer, target_steer, rate * delta), -steer_cap, steer_cap)

	var braking := Input.is_action_pressed("brake")
	var boost_mult := overdrive_boost if overdrive_active else lerpf(1.0, turbo_boost, _turbo_blend)
	var max_spd := HANDLING.top_speed_cap(_turbo_blend, overdrive_active)
	var forward_speed := linear_velocity.dot(global_transform.basis.z)
	var power := engine_power * boost_mult * HANDLING.power_taper(forward_speed, max_spd)
	var min_skid := 1.0

	for key in _wheels.keys():
		var ks := str(key)
		var is_front: bool = (ks == "FL" or ks == "FR")
		var w: VehicleWheel3D = _wheels[key]
		if w == null or not is_instance_valid(w):
			continue  # test harnesses may strip/free wheel nodes mid-run
		w.engine_force = 0.0
		w.brake = 0.0
		if throttle > 0.0:
			w.engine_force = power * throttle
		elif throttle < 0.0:
			# Signed forward speed, not length(): reversing past 2 m/s must keep
			# driving in reverse, not slam brake against the motion.
			if forward_speed < 2.5:
				w.engine_force = -reverse_force * -throttle
			else:
				w.brake = HANDLING.service_brake_for_wheel(brake_force, is_front, w.get_skidinfo(), -throttle)
		if braking:
			w.brake = (brake_force * 0.20) if is_front else handbrake_force
		elif throttle == 0.0:
			w.brake = brake_force * coast_brake
		if w.is_in_contact():
			min_skid = minf(min_skid, w.get_skidinfo())

		if is_front:
			w.steering = _steer

	# Real skid / handbrake feedback: tire smoke + scrape SFX when wheels break traction.
	var slip_angle := absf(atan2(linear_velocity.dot(global_transform.basis.x), maxf(absf(forward_speed), 1.0)))
	if grounded and spd > 6.0 and (min_skid < 0.45 or slip_angle > 0.22 or braking):
		if _scrape_cd <= 0.0:
			_scrape_cd = 1.2
			_play_sfx("scrape", -3.0)
		if not reduced:
			_skid_smoke_accum += delta
			if _skid_smoke_accum >= 0.07:
				_skid_smoke_accum = 0.0
				var b := global_transform.basis
				for x in [-0.55, 0.55]:
					VfxFactory.tire_smoke(_fx_parent(),
							global_position + b.x * x + Vector3(0.0, 0.15, 0.0) - b.z * 0.6)
	else:
		_skid_smoke_accum = 0.0

	# visual feedback: yaw the steering pivots and roll the wheel meshes
	var steer_alpha := 1.0 - exp(-10.0 * minf(delta, 0.05))
	for side in ["FL", "FR"]:
		var node: Node3D = _steer_nodes[side]
		if node:
			var target := _steer * visual_steer_scale
			node.rotation.y = lerp_angle(node.rotation.y, target, steer_alpha)

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
		if node and is_finite(roll):
			node.rotate_x(clampf(roll, -2.0, 2.0))
			if not node.basis.is_finite() or absf(node.basis.determinant()) <= 0.01:
				node.basis = Basis.IDENTITY
			else:
				var scl := node.scale
				node.basis = node.basis.orthonormalized()
				if scl.is_finite() and not scl.is_equal_approx(Vector3.ONE) and scl.length_squared() > 1e-4:
					node.scale = scl

func _init_world_bounds() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var ground := parent.get_node_or_null("Ground")
	if ground == null:
		return
	for child in ground.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			var sz := ((child as CollisionShape3D).shape as BoxShape3D).size
			if sz.is_finite() and sz.x > 10.0 and sz.z > 10.0:
				_bound_x = clampf(sz.x * 0.5 + 10.0, 60.0, 215.0)
				_bound_z = clampf(sz.z * 0.5 + 10.0, 60.0, 215.0)
				return


func _safe_spawn() -> Transform3D:
	if _is_pose_valid(_spawn) and _spawn.basis.y.normalized().dot(Vector3.UP) >= 0.3:
		return Transform3D(_spawn.basis.orthonormalized(), _spawn.origin)
	if _is_pose_valid(_fallback_spawn):
		return Transform3D(_fallback_spawn.basis.orthonormalized(), _fallback_spawn.origin)
	return Transform3D(Basis.IDENTITY, Vector3(0.0, 0.6, 0.0))


func _is_pose_valid(xf: Transform3D) -> bool:
	if not xf.origin.is_finite() or not xf.basis.is_finite():
		return false
	if absf(xf.basis.determinant()) <= 0.01:
		return false
	if xf.origin.y < -10.0 or xf.origin.y > 38.0:
		return false
	if absf(xf.origin.x) > _bound_x or absf(xf.origin.z) > _bound_z:
		return false
	return true


func _notify_camera_snap() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var cam := tree.get_first_node_in_group("camera_rig")
	if cam != null and cam.has_method("snap_to_target"):
		cam.call("snap_to_target")


func set_spawn(t: Transform3D) -> void:
	## Used by the multiplayer respawn system and Death Race checkpoints to move
	## the reset point. Rejects non-finite, singular, inverted, or OOB poses.
	if not _is_pose_valid(t):
		return
	var b := t.basis.orthonormalized()
	if not b.is_finite() or absf(b.determinant()) <= 0.5 or b.y.dot(Vector3.UP) < 0.3:
		return
	_spawn = Transform3D(b, t.origin)


func reset_bike() -> void:
	_pending_reset = true
	var sp := _safe_spawn()
	global_transform = sp
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_steer = 0.0
	_turbo_blend = 0.0
	turbo_active = false
	overdrive_active = false
	loop_up = Vector3.ZERO
	loop_tangent = Vector3.ZERO
	loop_center_pull = Vector3.ZERO
	_was_turbo = false
	_turbo_sfx_cd = 0.0
	_dodge_time = 0.0
	_dodge_elapsed = 0.0
	_dodge_cd = 0.0
	_ground_coyote = 0.0
	_throttle_in = 0.0
	_steer_in = 0.0
	_skid_smoke_accum = 0.0
	for key in _wheels.keys():
		var w: VehicleWheel3D = _wheels[key]
		if w != null and is_instance_valid(w):
			w.engine_force = 0.0
			w.brake = 0.0
			w.steering = 0.0
	if get_rid().is_valid():
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, sp)
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, false)
	if _flames:
		_flames.emitting = false
	if _jet_plume != null:
		_jet_plume.visible = false
	_notify_camera_snap()

func speed_kmh() -> float:
	if not linear_velocity.is_finite():
		return 0.0
	return linear_velocity.length() * 3.6


func _shake(amount: float) -> void:
	if Settings.reduced_motion():
		return
	var cam := get_tree().get_first_node_in_group("camera_rig") if get_tree() != null else null
	if cam != null and cam.has_method("add_shake"):
		cam.call("add_shake", amount)


func _fx_parent() -> Node3D:
	var tree := get_tree()
	if tree != null and tree.current_scene is Node3D:
		return tree.current_scene as Node3D
	return get_parent() as Node3D


func _play_sfx(name: String, volume_db: float = 0.0) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", name, volume_db)


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
	_dodge_elapsed = 0.0

	var basis := global_transform.basis.orthonormalized()
	# The GLB's forward is local +Z; with Y up that makes local +X the bike's
	# LEFT. So dodge_left (Q, dir=-1) must hop toward +X. Applying velocity
	# (not impulse) keeps the leap independent of mass and reproducible.
	linear_velocity += Vector3.UP * dodge_lift
	linear_velocity += basis.x * (-dir * dodge_side)
	# Cartwheel about the forward axis, top rolling INTO the leap. Positive
	# rotation about +Z sends +Y toward -X; negate for a left (+X) roll.
	angular_velocity += basis.z * (dir * dodge_spin)
	VfxFactory.dust_puff(_fx_parent(), global_position, 28)
	if not Settings.reduced_motion():
		Input.vibrate_handheld(15)


func _on_settings_changed(section: String, key: String, _value: Variant) -> void:
	if section == "*" or (section == "controls" and key == "steer_sensitivity"):
		_steer_sensitivity = clampf(float(Settings.get_value("controls", "steer_sensitivity", 1.0)), 0.3, 2.0)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _pending_reset:
		state.transform = _safe_spawn()
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_pending_reset = false
	if not _is_pose_valid(state.transform) or not state.linear_velocity.is_finite() or not state.angular_velocity.is_finite():
		state.transform = _safe_spawn()
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		loop_up = Vector3.ZERO
		loop_tangent = Vector3.ZERO
		loop_center_pull = Vector3.ZERO
		_dodge_time = 0.0
		call_deferred("_notify_camera_snap")
		return
	if state.linear_velocity.length() > 85.0:
		state.linear_velocity = state.linear_velocity.normalized() * 85.0
	if state.angular_velocity.length() > 25.0:
		state.angular_velocity = state.angular_velocity.normalized() * 25.0
	# Rollover immunity — the quad cannot tip over. This MUST live in
	# _integrate_forces() and must damp/rotate only the roll/pitch part
	# (world-Y yaw about the bike's local up is left intact): writing
	# angular_velocity in _physics_process() clobbers the wheel-generated
	# yaw before the solver step and the bike slides sideways without
	# turning. Two mechanisms, both suspended mid-dodge (the cartwheel
	# IS roll):
	# (1) near-total angular-velocity lockout on roll/pitch (yaw untouched)
	# (2) an active righting spring rotating the chassis back toward level
	var basis := state.transform.basis.orthonormalized()
	var up := basis.y.normalized()
	var spd := state.linear_velocity.length()
	var raw_step := state.step if is_finite(state.step) else (1.0 / 60.0)
	var dt_scale := clampf(raw_step * 60.0, 0.25, 4.0)
	var safe_step := clampf(raw_step, 0.001, 0.05)
	var in_loop_zone := loop_up.is_finite() and loop_up.length_squared() > 0.25
	var loop_active := in_loop_zone and spd > 8.0
	if not loop_active:
		var max_spd := HANDLING.top_speed_cap(_turbo_blend, overdrive_active)
		var drag_dv := HANDLING.aero_drag_accel(state.linear_velocity, max_spd) * safe_step
		if drag_dv.length() > spd:
			drag_dv = drag_dv.normalized() * spd
		state.linear_velocity += drag_dv
	var ref_up := loop_up.normalized() if loop_active else Vector3.UP
	if loop_active:
		# Centripetal track adhesion + gravity compensation + helical climb assist inside 360° loops.
		var pull := loop_center_pull if loop_center_pull.is_finite() else Vector3.ZERO
		state.linear_velocity += (Vector3(0.0, 9.81, 0.0) - ref_up * 12.0 + pull) * safe_step
		if _throttle_in > 0.1 and loop_tangent.is_finite() and loop_tangent.length_squared() > 0.25:
			var t_dir := loop_tangent.normalized()
			var t_spd := state.linear_velocity.dot(t_dir)
			if t_spd < 24.0:
				state.linear_velocity += t_dir * ((24.0 - t_spd) * 2.5 * safe_step)
	var av := state.angular_velocity
	var yaw_mag := av.dot(up)
	var yaw := yaw_mag * up
	var trans := av - yaw
	var v_fwd := state.linear_velocity.dot(basis.z)
	var v_lat := state.linear_velocity.dot(basis.x)
	if spd > 10.0 and not loop_active:
		var lim := HANDLING.high_speed_yaw_limits(spd, absf(_steer_in) >= 0.05)
		yaw_mag = clampf(yaw_mag * pow(lim.y, dt_scale), -lim.x, lim.x)
		yaw = yaw_mag * up
		if _grounded() and v_fwd > 4.0:
			var slip := atan2(v_lat, maxf(v_fwd, 1.0))
			var lat_k := HANDLING.lateral_slip_keep(spd, slip)
			if lat_k < 0.999:
				state.linear_velocity -= basis.x * (v_lat * (1.0 - pow(lat_k, dt_scale)))
	var lean := clampf(1.0 - up.dot(ref_up), 0.0, 1.0)
	if _dodge_time > 0.0:
		# Mid-cartwheel: keep yaw stabilized, leave roll spin completely undamped.
		state.angular_velocity = yaw + trans
		return
	var keep := lerpf(0.10, 0.003, lean)
	state.angular_velocity = yaw + trans * pow(keep, dt_scale)
	# (2) righting spring: rotate about the tilt axis (y × ref_up) —
	# frame-free, so it works at any yaw (and follows 360° loop normals).
	var axis := basis.y.cross(ref_up)
	var tilt := basis.y.angle_to(ref_up)
	if axis.length() <= 0.0001:
		axis = Vector3(basis.x.x, 0.0, basis.x.z)
		if axis.length() <= 0.0001:
			axis = Vector3(basis.z.x, 0.0, basis.z.z)
	if tilt > 0.055 and axis.length() > 0.0001 and is_finite(tilt):
		var max_step := 0.30 if loop_active else 0.14
		var effort := minf(minf(tilt * (0.22 + lean * 1.6 if loop_active else 0.10 + lean * 1.5), max_step) * dt_scale, tilt)
		if is_finite(effort):
			basis = Basis(Quaternion(axis.normalized(), effort)) * basis
			basis = basis.orthonormalized()
			if basis.is_finite() and absf(basis.determinant()) > 0.5:
				state.transform = Transform3D(basis, state.transform.origin)
	# Final post-integration velocity sanity clamp: loop/drag/damping must never
	# leave non-finite or runaway velocities for the C++ VehicleWheel3D solver.
	if not state.linear_velocity.is_finite() or not state.angular_velocity.is_finite():
		state.transform = _safe_spawn()
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		loop_up = Vector3.ZERO
		loop_tangent = Vector3.ZERO
		loop_center_pull = Vector3.ZERO
		call_deferred("_notify_camera_snap")
		return
	if state.linear_velocity.length() > 85.0:
		state.linear_velocity = state.linear_velocity.normalized() * 85.0
	if state.angular_velocity.length() > 25.0:
		state.angular_velocity = state.angular_velocity.normalized() * 25.0
