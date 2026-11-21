extends SceneTree
## Gate: the NARDUS pogo vehicle — deterministic assignment, weapon profile,
## runtime model swap, belly-wobble script attach, and ground datum.

var _fail := 0
var _prior_user_id: Variant


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		printerr("FAIL ", label)
		_fail += 1


func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	var sb: Node = root.get_node_or_null("Supabase")
	if sb != null and not bool(sb.get("use_mock")):
		printerr("LIVE BACKEND — refusing to run gate (KIEPIE_MOCK_BACKEND=1 not effective)")
		quit(2)
		return
	_prior_user_id = sb.get("user_id") if sb != null else null

	var registry: GDScript = load("res://src/game/VehicleRegistry.gd")
	_check(registry != null, "VehicleRegistry loads")
	if registry == null:
		quit(1)
		return

	# ---- 1. deterministic assignment (FNV-1a-32, 3-vehicle shift=12 mixer)
	_check(str(registry.call("for_player", "mock-host")) == "KiepieBike",
			"registry: mock-host -> KiepieBike (gate determinism)")
	_check(str(registry.call("for_player", "peer-1")) == "PogoNardus",
			"registry: peer-1 -> PogoNardus")
	_check(str(registry.call("for_player", "peer-2")) == "AstonMartin",
			"registry: peer-2 -> AstonMartin")
	_check(str(registry.call("for_player", "peer-3")) == "KiepieBike",
			"registry: peer-3 -> KiepieBike")
	_check(str(registry.call("for_player", "peer-4")) == "PogoNardus",
			"registry: peer-4 -> PogoNardus")
	_check(str(registry.call("for_player", "peer-5")) == "AstonMartin",
			"registry: peer-5 -> AstonMartin")
	_check(str(registry.call("for_player", "user-42")) == "KiepieBike",
			"registry: user-42 -> KiepieBike")
	_check(str(registry.call("profile", &"PogoNardus")) == "pogo",
			"profile: PogoNardus -> pogo")
	_check(str(registry.call("display_name", &"PogoNardus")) == "NARDUS",
			"display_name: PogoNardus -> NARDUS")
	_check(str(registry.call("profile", &"KiepieBike")) == "bike",
			"profile: KiepieBike -> bike")

	# Roster guarantee: even when every player in a roster individually hashes to
	# KiepieBike (e.g. ["mock-host", "user-42"]), at least one player is promoted to PogoNardus!
	var bike_only_roster := ["mock-host", "user-42"]
	var r0 := str(registry.call("for_player_in_roster", "mock-host", bike_only_roster))
	var r1 := str(registry.call("for_player_in_roster", "user-42", bike_only_roster))
	_check(r0 == "PogoNardus" or r1 == "PogoNardus",
			"for_player_in_roster guarantees at least one PogoNardus in all-bike roster (%s, %s)" % [r0, r1])
	var solo_roster := ["mock-host"]
	_check(str(registry.call("for_player_in_roster", "mock-host", solo_roster)) == "PogoNardus",
			"for_player_in_roster guarantees PogoNardus in a 1-player match roster")

	# ---- 2. the GLB itself
	var glb: PackedScene = load("res://assets/Pogo_Nardus.glb")
	_check(glb != null, "Pogo GLB loaded")
	if glb == null:
		_restore()
		quit(1)
		return
	var model := glb.instantiate()
	var rider := model.get_node_or_null("Rider")
	var stick := model.get_node_or_null("Stick")
	var belly := model.get_node_or_null("Rider/Belly")
	var muzzle_l := model.get_node_or_null("Stick/BananaMuzzle_L")
	var muzzle_r := model.get_node_or_null("Stick/BananaMuzzle_R")
	var decal := model.get_node_or_null("Rider/NardusDecal")
	var arm_l := model.get_node_or_null("Rider/Arm_L") as Node3D
	var arm_r := model.get_node_or_null("Rider/Arm_R") as Node3D
	var head := model.get_node_or_null("Rider/Head") as Node3D
	var stick_lower := model.get_node_or_null("Stick/StickLower") as Node3D
	var spring_coil := model.get_node_or_null("Stick/SpringCoil") as Node3D
	var stick_upper := model.get_node_or_null("Stick/StickUpper") as Node3D
	_check(rider != null, "Rider pivot present")
	_check(stick != null, "Stick (pogo) present")
	_check(belly != null, "Belly present under Rider")
	_check(head != null, "Head neck-pivot present under Rider")
	_check(muzzle_l != null and muzzle_r != null, "banana muzzle anchors present")
	_check(decal != null, "NARDUS decal present")
	_check(arm_l != null and arm_r != null, "shoulder-pivoted Arm_L and Arm_R present under Rider")
	_check(stick_lower != null and spring_coil != null and stick_upper != null,
			"telescoping StickLower / SpringCoil / StickUpper pivots present under Stick")
	# Mankini outfit: RiderBody must carry the MankiniPink and ButtCheekRed materials
	var rider_body := model.get_node_or_null("Rider/RiderBody") as MeshInstance3D
	var has_mankini := false
	var has_butt_blush := false
	if rider_body != null and rider_body.mesh != null:
		for s in range(rider_body.mesh.get_surface_count()):
			var mat_s: Variant = rider_body.get_active_material(s)
			if mat_s is Material:
				var nm := str((mat_s as Material).resource_name)
				if nm == "MankiniPink":
					has_mankini = true
				elif nm == "ButtCheekRed":
					has_butt_blush = true
	_check(has_mankini, "Rider/RiderBody carries the MankiniPink Borat-mankini material")
	_check(has_butt_blush, "Rider/RiderBody carries the ButtCheekRed butt-cheek material")
	# ground datum: pogo tip on z == 0 in Blender -> y == 0 in Godot (Y up)
	# compute in model-local space so unparented model never triggers !is_inside_tree()
	var min_y := 1.0e9
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		var aabb := mi.get_aabb()
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != null and cur != model:
			if cur is Node3D:
				xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		for corner_i in range(8):
			var pt := xf * aabb.get_endpoint(corner_i)
			min_y = minf(min_y, pt.y)
	_check(min_y >= -0.02 and min_y < 0.06, "pogo footprint at the ground (min_y=%.3f)" % min_y)
	var tri_count := 0
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			tri_count += int(mi.mesh.surface_get_array_len(s) / 3.0) if mi.mesh.surface_get_array_len(s) > 0 else 0
	_check(tri_count > 0 and tri_count <= 9000, "triangle budget sane (%d tris)" % tri_count)
	model.free()

	# ---- 3. runtime swap in a fresh scene: force the pogo assignment
	if sb != null:
		sb.set("user_id", "peer-1")
	var scene: PackedScene = load("res://scenes/TestRide.tscn")
	if sb != null:
		sb.set("user_id", "mock-host")  # keep the scene load itself neutral
	var ride := scene.instantiate() as Node3D
	if sb != null:
		sb.set("user_id", "peer-1")    # and flip back before _ready runs
	root.add_child(ride)
	for i in range(4):
		await physics_frame
	var bike := ride.get_node_or_null("KiepieBike") as Node3D
	_check(bike != null, "bike node exists after swap")
	if bike != null:
		_check(str(bike.get("vehicle_profile")) == "pogo", "vehicle_profile == pogo after swap")
		_check(float(bike.get("reverse_force")) >= 250.0,
				"reverse_force >= 250.0 (%.1f)" % float(bike.get("reverse_force")))
		_check(bike.get_node_or_null("Model/Rider") != null, "Model swapped to pogo GLB (Rider present)")
		var rider_node: Node = bike.get_node_or_null("Model/Rider") if bike != null else null
		if rider_node != null:
			var script: Variant = rider_node.get_script()
			_check(script != null and str(script.resource_path).ends_with("PogoVisual.gd"),
					"Rider carries PogoVisual.gd")
		var combat: Node = bike.get_node_or_null("CombatController") if bike != null else null
		var cannons: Node = combat.get("cannons") if combat != null else null
		_check(cannons != null, "cannons exist for pogo")
		if cannons != null:
			_check(str(cannons.get("weapon_profile")) == "pogo", "weapon_profile == pogo")
			var prof: Variant = cannons.get("_profile")
			_check(prof is Dictionary and float((prof as Dictionary).get("cooldown", 0.0)) == 0.40,
					"pogo cooldown is 0.40s (twice the bike's 0.20s)")
			_check(prof is Dictionary and float((prof as Dictionary).get("rapid_cooldown", 0.0)) == 0.18,
					"pogo rapid cooldown is 0.18s")
			_check(prof is Dictionary and float((prof as Dictionary).get("damage_mult", 0.0)) == 2.0,
					"pogo does 2x damage")
			_check(prof is Dictionary and str((prof as Dictionary).get("sfx", "")) == "pop",
					"pogo fires banana pop sfx")
		var muzzle_count: int = 0
		if cannons != null:
			var mu: Variant = cannons.get("_muzzles")
			if mu is Array:
				muzzle_count = mu.size()
		_check(muzzle_count == 2, "two banana muzzles mounted (%d)" % muzzle_count)

		# Turbo bird-arm flapping check: engaging turbo/overdrive flaps Arm_L and Arm_R like a bird!
		var live_arm_l := bike.get_node_or_null("Model/Rider/Arm_L") as Node3D
		var live_arm_r := bike.get_node_or_null("Model/Rider/Arm_R") as Node3D
		if combat != null and combat.has_method("apply_pickup"):
			combat.call("apply_pickup", "overdrive")
		for _f in range(6):
			await physics_frame
		_check(live_arm_l != null and live_arm_r != null
				and absf(live_arm_l.rotation.z) > 0.02
				and is_equal_approx(live_arm_l.rotation.z, -live_arm_r.rotation.z),
				"Nardus flaps Arm_L and Arm_R symmetrically like a bird during turbo (z=%.3f / %.3f)" % [
					live_arm_l.rotation.z if live_arm_l else 0.0,
					live_arm_r.rotation.z if live_arm_r else 0.0])
		if combat != null and combat.has_method("reset_state"):
			combat.call("reset_state")

		# Live ballistic pogo mechanics: SpringCoil compresses & telescopes, Head reacts to recoil!
		var live_coil := bike.get_node_or_null("Model/Stick/SpringCoil") as Node3D
		var live_head := bike.get_node_or_null("Model/Rider/Head") as Node3D
		var min_coil_y := 10.0
		var max_coil_y := 0.0
		if rider_node != null and rider_node.has_method("trigger_recoil"):
			rider_node.call("trigger_recoil", 1.0)
		var head_moved := false
		for _f in range(28):
			await physics_frame
			if live_coil != null:
				min_coil_y = minf(min_coil_y, live_coil.scale.y)
				max_coil_y = maxf(max_coil_y, live_coil.scale.y)
			if live_head != null and absf(live_head.rotation.x) > 0.005:
				head_moved = true
		_check(live_coil != null and (max_coil_y - min_coil_y) > 0.015,
				"SpringCoil compresses and rebounds live during pogo bounce (scale.y range %.3f..%.3f)" % [min_coil_y, max_coil_y])
		_check(live_head != null and head_moved,
				"Rider/Head follows through dynamically with pogo bounce & recoil")

	# ---- 4. and a peer whose hash lands on the bike gets the bike (with identical physics stats!)
	if sb != null:
		sb.set("user_id", "user-42")
	var ride2 := scene.instantiate() as Node3D
	root.add_child(ride2)
	for i in range(2):
		await physics_frame
	var bike2 := ride2.get_node_or_null("KiepieBike") as Node3D
	_check(bike2 != null and str(bike2.get("vehicle_profile")) == "bike",
			"user-42 gets the bike")
	var sil: Array = bike2.find_children("Silencer_Tip", "", true, false) if bike2 != null else []
	_check(bike2 != null and sil.size() > 0, "bike GLB still carries Silencer_Tip anchor")
	if bike != null and bike2 != null:
		var same_stats := is_equal_approx(float(bike.get("engine_power")), float(bike2.get("engine_power"))) \
				and is_equal_approx(float(bike.get("turbo_boost")), float(bike2.get("turbo_boost"))) \
				and is_equal_approx(float(bike.get("max_steer")), float(bike2.get("max_steer"))) \
				and is_equal_approx(float(bike.get("steer_speed")), float(bike2.get("steer_speed"))) \
				and is_equal_approx(float(bike.get("dodge_lift")), float(bike2.get("dodge_lift"))) \
				and is_equal_approx(float(bike.get("dodge_side")), float(bike2.get("dodge_side"))) \
				and is_equal_approx(float(bike.get("dodge_spin")), float(bike2.get("dodge_spin")))
		_check(same_stats, "Nardus and KiepieBike have identical speed, steering, and cartwheel jump stats")

	if sb != null:
		sb.set("user_id", _prior_user_id)
	print("POGO VERIFY: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)


func _restore() -> void:
	var sb: Node = root.get_node_or_null("Supabase")
	if sb != null and _prior_user_id != null:
		sb.set("user_id", _prior_user_id)
