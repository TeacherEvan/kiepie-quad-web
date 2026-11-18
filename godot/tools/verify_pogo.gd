extends SceneTree
## Gate: the PRINCESS pogo vehicle — deterministic assignment, weapon profile,
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

	# ---- 1. deterministic assignment: known hashes (FNV-1a-32 / UTF-8 bytes)
	# mock-host must resolve to the bike so every other gate sees the bike.
	_check(str(registry.call("for_player", "mock-host")) == "KiepieBike",
			"registry: mock-host -> KiepieBike (gate determinism)")
	_check(str(registry.call("for_player", "peer-1")) == "PogoPrincess",
			"registry: peer-1 -> PogoPrincess")
	_check(str(registry.call("for_player", "peer-3")) == "PogoPrincess",
			"registry: peer-3 -> PogoPrincess")
	_check(str(registry.call("profile", &"PogoPrincess")) == "pogo",
			"profile: PogoPrincess -> pogo")
	_check(str(registry.call("profile", &"KiepieBike")) == "bike",
			"profile: KiepieBike -> bike")

	# ---- 2. the GLB itself
	var glb: PackedScene = load("res://assets/Pogo_Princess.glb")
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
	var decal := model.get_node_or_null("Rider/PrincessDecal")
	_check(rider != null, "Rider pivot present")
	_check(stick != null, "Stick (pogo) present")
	_check(belly != null, "Belly present under Rider")
	_check(muzzle_l != null and muzzle_r != null, "banana muzzle anchors present")
	_check(decal != null, "PRINCESS decal present")
	# ground datum: pogo tip on z == 0 in Blender -> y == 0 in Godot (Y up)
	var min_y := 1.0e9
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		var aabb := mi.get_aabb()
		var origin: Vector3 = mi.global_position
		# world-space bottom of this mesh instance (axis-aligned approximation)
		var bottom := origin.y + mi.global_transform.basis.y.dot(aabb.position)
		var ex := absf(mi.global_transform.basis.x.length()) * aabb.size.x
		var ey := absf(mi.global_transform.basis.y.length()) * aabb.size.y
		var ez := absf(mi.global_transform.basis.z.length()) * aabb.size.z
		bottom = origin.y - ey / 2.0
		min_y = minf(min_y, bottom)
	_check(min_y < 0.06, "pogo footprint at the ground (min_y=%.3f)" % min_y)
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

	# ---- 4. and the default scene host gets the bike
	if sb != null:
		sb.set("user_id", "mock-host")
	var ride2 := scene.instantiate() as Node3D
	root.add_child(ride2)
	for i in range(2):
		await physics_frame
	var bike2 := ride2.get_node_or_null("KiepieBike") as Node3D
	_check(bike2 != null and str(bike2.get("vehicle_profile")) == "bike",
			"mock-host keeps the bike")
	var sil: Array = bike2.find_children("Silencer_Tip", "", true, false) if bike2 != null else []
	_check(bike2 != null and sil.size() > 0, "bike GLB still carries Silencer_Tip anchor")

	if sb != null:
		sb.set("user_id", _prior_user_id)
	print("POGO VERIFY: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)


func _restore() -> void:
	var sb: Node = root.get_node_or_null("Supabase")
	if sb != null and _prior_user_id != null:
		sb.set("user_id", _prior_user_id)
