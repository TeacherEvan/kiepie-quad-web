extends SceneTree
## Offline control-feel gate. Locks the defect the original gates missed:
## anti-rollover damping in _physics_process cancelled all wheel-generated
## yaw, so the wheels reached full lock but the bike never turned.
## Also verifies the steer_sensitivity setting actually changes turn rate.

var _fail := 0
var _settings: Node

func _set_setting(key: String, value: Variant) -> void:
	# Tool scripts cannot reference autoloads at compile time (see AGENTS.md).
	if _settings == null or not is_instance_valid(_settings):
		_settings = get_root().get_node("Settings")
	_settings.call("set_value", "controls", key, value)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS ", label)
	else:
		printerr("FAIL ", label)
		_fail += 1

func _initialize() -> void:
	_run()

func _release_all() -> void:
	for a in ["move_forward", "move_back", "steer_left", "steer_right", "brake", "turbo"]:
		Input.action_release(a)

func _measure(sensitivity: float) -> Dictionary:
	_set_setting("steer_sensitivity", sensitivity)
	var scene := load("res://scenes/TestRide.tscn") as PackedScene
	var root := scene.instantiate() as Node3D
	get_root().add_child(root)
	await process_frame
	var bike := root.get_node("KiepieBike") as VehicleBody3D
	for i in range(30):
		await physics_frame
	Input.action_press("move_forward")
	for i in range(90):
		await physics_frame
	var h0 := bike.global_transform.basis.z.normalized()
	Input.action_press("steer_left")
	var min_up := 1.0
	for i in range(60):
		await physics_frame
		min_up = minf(min_up, bike.global_transform.basis.y.normalized().y)
	var h1 := bike.global_transform.basis.z.normalized()
	var heading := rad_to_deg(acos(clampf(h0.dot(h1), -1.0, 1.0)))
	_release_all()
	root.queue_free()
	await process_frame
	return {"heading": heading, "min_up": min_up}

func _measure_reverse() -> Dictionary:
	var scene := load("res://scenes/TestRide.tscn") as PackedScene
	var root := scene.instantiate() as Node3D
	get_root().add_child(root)
	await physics_frame
	var bike := root.get_node("KiepieBike") as VehicleBody3D
	for i in range(30):
		await physics_frame
	var p0 := bike.global_position
	var fwd0 := bike.global_transform.basis.z.normalized()
	Input.action_press("move_back")
	var peak_rev := 0.0
	for i in range(120):
		await physics_frame
		peak_rev = maxf(peak_rev, -bike.linear_velocity.dot(fwd0))
	var disp := (bike.global_position - p0).dot(fwd0)
	_release_all()
	root.queue_free()
	await process_frame
	return {"disp": disp, "peak_rev": peak_rev}

func _run() -> void:
	await process_frame
	# capture the developer's prior before any _set_setting mutates it
	var _steer_prior: Variant = 1.0
	var _node: Node = get_root().get_node_or_null("Settings")
	if _node != null:
		_steer_prior = _node.call("get_value", "controls", "steer_sensitivity", 1.0)
	var normal: Dictionary = await _measure(1.0)
	_check(float(normal["heading"]) > 15.0,
			"steering yaws the bike (heading %.1f deg)" % float(normal["heading"]))
	_check(float(normal["min_up"]) > 0.80,
			"bike stays upright while steering (min_up %.3f)" % float(normal["min_up"]))
	var low: Dictionary = await _measure(0.4)
	var high: Dictionary = await _measure(1.8)
	_check(float(high["heading"]) > float(low["heading"]) * 1.15,
			"steer sensitivity changes turn rate (low %.1f vs high %.1f deg)" % [
					float(low["heading"]), float(high["heading"])])
	var rev: Dictionary = await _measure_reverse()
	_check(float(rev["disp"]) < -6.0 and float(rev["peak_rev"]) > 5.0,
			"reverse driving accelerates past 2 m/s without braking against itself (disp %.2f m, peak %.2f m/s)" % [
					float(rev["disp"]), float(rev["peak_rev"])])
	_set_setting("steer_sensitivity", _steer_prior)

	# Engine RPM pitch rise check (TestRide includes CombatController + _engine_player)
	var ride_ps := load("res://scenes/TestRide.tscn") as PackedScene
	if ride_ps != null:
		var ride := ride_ps.instantiate() as Node3D
		get_root().add_child(ride)
		await process_frame
		await process_frame
		var b := ride.get_node_or_null("KiepieBike") as Node3D
		var eng: AudioStreamPlayer3D = b.get("_engine_player") as AudioStreamPlayer3D if b != null else null
		if eng == null and b != null:
			eng = b.find_child("*Engine*", true, false) as AudioStreamPlayer3D
		var idle_pitch: float = eng.pitch_scale if eng != null else 0.78
		Input.action_press("move_forward")
		Input.action_press("turbo")
		for _f in range(45):
			await physics_frame
		var rev_pitch: float = eng.pitch_scale if eng != null else 0.0
		Input.action_release("move_forward")
		Input.action_release("turbo")
		_check(eng != null and rev_pitch > idle_pitch,
				"KiepieBike engine RPM pitch rises on throttle+turbo (idle=%.2f -> rev=%.2f)" % [idle_pitch, rev_pitch])
		ride.queue_free()
		await process_frame

	# Tier-1 pure VehicleHandling math invariants
	var vh := load("res://src/game/VehicleHandling.gd") as GDScript
	_check(vh != null, "VehicleHandling.gd loads")
	if vh != null:
		var cap_low := float(vh.call("effective_steer_cap", 6.0, 0.56, 1.0))
		var cap_hi := float(vh.call("effective_steer_cap", 35.0, 0.56, 1.0))
		var cap_sens2 := float(vh.call("effective_steer_cap", 25.0, 0.56, 2.0))
		var cap_nan := float(vh.call("effective_steer_cap", NAN, 0.56, NAN))
		_check(cap_hi < cap_low * 0.5, "VehicleHandling tapers steer cap at 35 m/s (%.3f < %.3f)" % [cap_hi, cap_low])
		_check(cap_sens2 <= 0.62, "VehicleHandling clamps sens=2.0 below snowplow lock (%.3f <= 0.62)" % cap_sens2)
		_check(is_finite(cap_nan) and cap_nan > 0.0, "VehicleHandling handles NaN safely")
		_check(is_equal_approx(float(vh.call("top_speed_cap", 1.0, true)), 36.0),
				"VehicleHandling Overdrive+Turbo does not stack past 36 m/s")
		var drag_low: Vector3 = vh.call("aero_drag_accel", Vector3(0, 0, 26.0), 28.0)
		var drag_hi: Vector3 = vh.call("aero_drag_accel", Vector3(0, 0, 34.0), 28.0)
		_check(drag_hi.length() > drag_low.length(), "VehicleHandling aero drag scales monotonically past soft cap")

	# Tier-2 drop settle (0 bounces, 0 airborne ticks after landing) on clean flat ground
	var drop_root := Node3D.new()
	var flat_g := StaticBody3D.new()
	var flat_c := CollisionShape3D.new()
	var flat_b := BoxShape3D.new()
	flat_b.size = Vector3(2000.0, 1.0, 2000.0)
	flat_c.shape = flat_b
	flat_g.add_child(flat_c)
	flat_g.position = Vector3(0.0, -0.5, 0.0)
	drop_root.add_child(flat_g)
	var drop_bike := (load("res://scenes/KiepieBike.tscn") as PackedScene).instantiate() as VehicleBody3D
	drop_bike.position = Vector3(0.0, 0.6, 0.0)
	drop_root.add_child(drop_bike)
	get_root().add_child(drop_root)
	await process_frame
	drop_bike.set_spawn(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.6, 0.0)))
	drop_bike.call("reset_bike")
	var drop_min_y := 10.0
	var drop_bounces := 0
	var prev_c := false
	var landed := false
	var air_after_land := 0
	for _t in range(90):
		await physics_frame
		var ic := (drop_bike.get_node("WheelFL") as VehicleWheel3D).is_in_contact()
		if ic:
			landed = true
		if landed and not ic:
			air_after_land += 1
		if prev_c and not ic:
			drop_bounces += 1
		prev_c = ic
		drop_min_y = minf(drop_min_y, drop_bike.global_position.y)
	_check(drop_bounces == 0 and air_after_land == 0 and drop_min_y > -0.26,
			"drop settle has 0 bounces & 0 airborne ticks (bounces=%d air=%d min_y=%.3f)" % [drop_bounces, air_after_land, drop_min_y])

	# Tier-2 high-speed 30 m/s steering stability matrix (no 180 spinout)
	var yaw_by_sf := {}
	for sf in [0.15, 0.50, 1.00]:
		drop_bike.set_spawn(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 0.0)))
		drop_bike.call("reset_bike")
		for _s in range(30):
			await physics_frame
		drop_bike.linear_velocity = Vector3(0.0, 0.0, 30.0)
		Input.action_press("move_forward")
		Input.action_press("steer_left", sf)
		var py := rad_to_deg(atan2(drop_bike.global_transform.basis.z.x, drop_bike.global_transform.basis.z.z))
		var tot := 0.0
		var max_w := 0.0
		var max_slip := 0.0
		var air_t := 0
		for _t in range(90):
			if _t == 60:
				Input.action_release("steer_left")
			await physics_frame
			var b := drop_bike.global_transform.basis.orthonormalized()
			var ny := rad_to_deg(atan2(b.z.x, b.z.z))
			tot += fmod(ny - py + 540.0, 360.0) - 180.0
			py = ny
			max_w = maxf(max_w, absf(drop_bike.angular_velocity.y))
			var vf := drop_bike.linear_velocity.dot(b.z)
			var vl := drop_bike.linear_velocity.dot(b.x)
			if Vector2(vf, vl).length() > 0.5:
				max_slip = maxf(max_slip, absf(rad_to_deg(atan2(vl, vf))))
			if not (drop_bike.get_node("WheelFL") as VehicleWheel3D).is_in_contact():
				air_t += 1
		_release_all()
		yaw_by_sf[sf] = absf(tot)
		_check(absf(tot) <= 125.0 and max_w <= 2.8 and max_slip <= 22.0 and air_t == 0,
				"30 m/s steer sf=%.2f stable (yaw=%.1f° w=%.2f slip=%.1f° air=%d)" % [sf, tot, max_w, max_slip, air_t])
	_check(float(yaw_by_sf[1.00]) >= float(yaw_by_sf[0.15]),
			"30 m/s steering scales proportionally (sf=1.0 %.1f° >= sf=0.15 %.1f°)" % [float(yaw_by_sf[1.00]), float(yaw_by_sf[0.15])])

	# Tier-2 service brake + steer at 30 m/s turns requested direction
	drop_bike.set_spawn(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 0.0)))
	drop_bike.call("reset_bike")
	for _s in range(30):
		await physics_frame
	drop_bike.linear_velocity = Vector3(0.0, 0.0, 30.0)
	Input.action_press("move_back")
	Input.action_press("steer_left")
	var bpy := rad_to_deg(atan2(drop_bike.global_transform.basis.z.x, drop_bike.global_transform.basis.z.z))
	var btot := 0.0
	var bslip := 0.0
	for _t in range(45):
		await physics_frame
		var b := drop_bike.global_transform.basis.orthonormalized()
		var ny := rad_to_deg(atan2(b.z.x, b.z.z))
		btot += fmod(ny - bpy + 540.0, 360.0) - 180.0
		bpy = ny
		bslip = maxf(bslip, absf(rad_to_deg(atan2(drop_bike.linear_velocity.dot(b.x), maxf(drop_bike.linear_velocity.dot(b.z), 0.5)))))
	_release_all()
	_check(btot > 10.0 and bslip < 20.0 and drop_bike.linear_velocity.length() < 24.0,
			"brake+steer @30m/s turns left cleanly (yaw=%.1f° slip=%.1f° end_v=%.1f)" % [btot, bslip, drop_bike.linear_velocity.length()])

	# Tier-2 Overdrive+Turbo top-speed cap
	drop_bike.set_spawn(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 0.0)))
	drop_bike.call("reset_bike")
	for _s in range(15):
		await physics_frame
	drop_bike.linear_velocity = Vector3(0.0, 0.0, 26.0)
	drop_bike.set("overdrive_active", true)
	Input.action_press("move_forward")
	Input.action_press("turbo")
	for _t in range(180):
		await physics_frame
	var top_od := drop_bike.linear_velocity.length()
	_release_all()
	_check(top_od <= 39.0, "Overdrive+Turbo top speed capped <= 39.0 m/s (got %.1f m/s)" % top_od)
	drop_root.free()
	await process_frame

	print("CONTROLS: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
