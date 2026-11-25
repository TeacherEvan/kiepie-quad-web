extends SceneTree
## Gate: EVAN THE SKELETON — preference-only vehicle contract, 52-bone rig and
## 4 baked NLA clips, Draco GLB structure/ground datum/tri budget, RIFF BLASTER
## profile, MainMenu selector, and the runtime shell swap + animation driver.

const SAV := "user://settings.cfg"
const BAK := "user://settings.cfg.evan-gate-backup"

var _fail := 0
var _had_cfg := false
var _prior_user_id: Variant


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		printerr("FAIL ", label)
		_fail += 1


## glTF import nests skinned meshes under EvanRig/Skeleton3D; resolve by name
## exactly like KiepieBike._find_model_node() does at runtime.
func _find(root_node: Node, node_name: String) -> Node:
	if root_node == null:
		return null
	var direct := root_node.get_node_or_null(node_name)
	if direct != null:
		return direct
	return root_node.find_child(node_name, true, false)


func _backup() -> void:
	_had_cfg = FileAccess.file_exists(SAV)
	if not _had_cfg:
		return
	if FileAccess.file_exists(BAK):
		DirAccess.remove_absolute(BAK)
	if DirAccess.copy_absolute(SAV, BAK) != OK:
		_had_cfg = false


func _restore() -> void:
	var sb: Node = root.get_node_or_null("Supabase")
	if sb != null and _prior_user_id != null:
		sb.set("user_id", _prior_user_id)
	if _had_cfg:
		if DirAccess.copy_absolute(BAK, SAV) == OK:
			DirAccess.remove_absolute(BAK)
	elif FileAccess.file_exists(SAV):
		DirAccess.remove_absolute(SAV)


func _initialize() -> void:
	_backup()
	_run()


func _run() -> void:
	await process_frame
	var sb: Node = root.get_node_or_null("Supabase")
	if sb == null or not bool(sb.get("use_mock")):
		printerr("LIVE BACKEND — refusing to run gate (KIEPIE_MOCK_BACKEND=1 not effective)")
		_restore()
		quit(2)
		return
	_prior_user_id = sb.get("user_id")

	var registry: GDScript = load("res://src/game/VehicleRegistry.gd")
	_check(registry != null, "VehicleRegistry loads")
	if registry == null:
		_restore()
		quit(1)
		return

	# ---- 1. Registry contract. EVAN is preference-only: the 3-vehicle deal
	# pool and every existing hash fixture must stay byte-for-byte unchanged.
	_check(str(registry.call("profile", &"EvanSkeleton")) == "evan", "profile(EvanSkeleton) == 'evan'")
	_check(str(registry.call("from_profile", "evan")) == "EvanSkeleton", "from_profile('evan') == EvanSkeleton")
	_check(str(registry.call("display_name", &"EvanSkeleton")) == "EVAN THE SKELETON", "display_name")
	_check(str(registry.call("model_path", &"EvanSkeleton")) == "res://assets/Evan_Skeleton.glb", "model_path")
	_check(bool(registry.call("is_valid", &"EvanSkeleton")), "is_valid(EvanSkeleton)")
	_check(bool(registry.call("is_evan", &"EvanSkeleton")), "is_evan(EvanSkeleton)")
	_check(str(registry.call("sanitize_preference", "EvanSkeleton")) == "EvanSkeleton",
			"sanitize_preference accepts EvanSkeleton")
	_check(str(registry.call("sanitize_preference", "ForgedSkeleton")) == "",
			"sanitize_preference rejects an unknown id")
	_check(str(registry.call("resolve_for_player", "mock-host", [], "EvanSkeleton")) == "EvanSkeleton",
			"resolve_for_player honors an explicit Evan preference")
	_check(str(registry.call("for_player", "mock-host")) == "KiepieBike",
			"deal pool unchanged — mock-host still KiepieBike")
	_check(str(registry.call("for_player", "peer-1")) == "PogoNardus",
			"deal pool unchanged — peer-1 still PogoNardus")
	_check(str(registry.call("for_player", "user-42")) == "KiepieBike",
			"deal pool unchanged — user-42 still KiepieBike")

	# ---- 2. The GLB: 52-bone humanoid, 4 clips, muzzles, ground datum, budget
	var glb: PackedScene = load("res://assets/Evan_Skeleton.glb")
	_check(glb != null, "Evan GLB loads")
	if glb == null:
		_restore()
		quit(1)
		return
	var model := glb.instantiate() as Node3D

	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	_check(skeletons.size() >= 1, "Skeleton3D present")
	if skeletons.size() >= 1:
		_check((skeletons[0] as Skeleton3D).get_bone_count() == 52,
				"SkeletonProfileHumanoid 52 bones (%d)" % (skeletons[0] as Skeleton3D).get_bone_count())

	var players := model.find_children("*", "AnimationPlayer", true, false)
	_check(players.size() >= 1, "AnimationPlayer present")
	if players.size() >= 1:
		var ap := players[0] as AnimationPlayer
		for clip in ["Idle_Sway", "Play_Strum", "Headbang_Riff", "Action_BigFinish"]:
			_check(ap.has_animation(clip), "NLA clip %s baked" % clip)

	_check(_find(model, "Skull_Cranium") != null, "skull mesh present")
	_check(_find(model, "GuitarBody") != null, "hot-pink guitar body present")
	_check(_find(model, "RiffMuzzle_L") != null and _find(model, "RiffMuzzle_R") != null,
			"RiffMuzzle_L/R muzzle anchors present")
	var has_pink := false
	var guitar := _find(model, "GuitarBody") as MeshInstance3D
	if guitar != null and guitar.mesh != null:
		for s in range(guitar.mesh.get_surface_count()):
			var sm: Variant = guitar.get_active_material(s)
			if sm is StandardMaterial3D and str((sm as Material).resource_name) == "GuitarHotPink":
				has_pink = true
	_check(has_pink, "GuitarBody carries the GuitarHotPink material")
	_check(_find(model, "Tyre_F_L") != null and _find(model, "Tyre_R_R") != null,
			"four quad tyres present (vehicle stand-in)")

	# ground datum computed in model-local space so the unparented instance is safe
	var min_y := 1.0e9
	var tri_count := 0
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != null and cur != model:
			if cur is Node3D:
				xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var aabb := mi.get_aabb()
		for corner_i in range(8):
			min_y = minf(min_y, (xf * aabb.get_endpoint(corner_i)).y)
		for s in range(mi.mesh.get_surface_count()):
			tri_count += int(mi.mesh.surface_get_array_index_len(s) / 3.0)
	_check(min_y >= -0.02 and min_y < 0.06, "ground datum (min_y=%.3f)" % min_y)
	_check(tri_count > 0 and tri_count < 10000, "under 10k tris (%d)" % tri_count)
	model.free()

	# ---- 3. Weapon profile (derived stats come from VehicleRegistry)
	var cannon_script: GDScript = load("res://src/game/SideCannons.gd")
	_check(cannon_script != null and (cannon_script.get_script_method_list() != null),
			"SideCannons loads")
	if cannon_script != null:
		var profiles: Variant = cannon_script.get("PROFILES")
		_check(profiles is Dictionary and (profiles as Dictionary).has("evan"),
				"SideCannons has an 'evan' profile")
		var probe := Node3D.new()
		probe.set_script(cannon_script)
		probe.call("setup", probe, "evan-gate", Callable(), Color.WHITE, "evan")
		_check(str(probe.call("weapon_display_name", "primary")) == "RIFF BLASTER",
				"primary weapon reads RIFF BLASTER")
		var prof: Variant = probe.get("_profile")
		_check(prof is Dictionary and float((prof as Dictionary).get("cooldown", 0.0)) == 0.22,
				"evan cooldown 0.22s")
		probe.free()

	# ---- 4. MainMenu selector & Settings persistence
	var settings: Node = root.get_node("Settings")
	settings.call("set_value", "gameplay", "vehicle", "auto")
	var mm_ps: PackedScene = load("res://scenes/MainMenu.tscn")
	if mm_ps != null:
		var mm := mm_ps.instantiate() as Control
		root.add_child(mm)
		await process_frame
		var vs := mm.get_node_or_null("SafeMargin/Scroll/ScrollBox/Card/VBox/VehicleRow/VehicleSelect") as OptionButton
		_check(vs != null, "VehicleSelect exists")
		if vs != null:
			_check(vs.item_count == 5 and vs.get_item_text(4) == "EVAN THE SKELETON",
					"VehicleSelect has EVAN THE SKELETON option")
			vs.select(4)
			vs.item_selected.emit(4)
			await process_frame
			_check(str(settings.call("preferred_vehicle")) == "EvanSkeleton",
					"selecting EVAN persists EvanSkeleton preference")
		mm.queue_free()
		await process_frame

	# ---- 5. Runtime shell swap in a fresh scene (preference drives the swap)
	settings.call("set_value", "gameplay", "vehicle", "EvanSkeleton")
	var scene: PackedScene = load("res://scenes/TestRide.tscn")
	var ride := scene.instantiate() as Node3D
	root.add_child(ride)
	for i in range(5):
		await physics_frame
	var bike := ride.get_node_or_null("KiepieBike") as Node3D
	_check(bike != null, "bike node exists after swap")
	if bike != null:
		_check(str(bike.get("vehicle_profile")) == "evan", "vehicle_profile == evan after swap")
		var evan_model: Node = bike.get_node_or_null("Model")
		_check(evan_model != null and _find(evan_model, "GuitarBody") != null,
				"Model swapped to the Evan GLB")
		_check(evan_model != null and evan_model.has_method("trigger_recoil"),
				"Model carries the EvanVisual recoil hook")
		if evan_model != null:
			var script: Variant = evan_model.get_script()
			_check(script != null and str(script.resource_path).ends_with("EvanVisual.gd"),
					"Model carries EvanVisual.gd")
		var combat: Node = bike.get_node_or_null("CombatController")
		var cannons: Node = combat.get("cannons") if combat != null else null
		_check(cannons != null and str(cannons.get("weapon_profile")) == "evan",
				"SideCannons switched to the evan profile")
	ride.queue_free()
	await process_frame

	# ---- 6. Remote-proxy motion estimate must stay finite (AUD P2). A remote
	# StaticBody3D has no linear_velocity, so EvanVisual derives speed from
	# consecutive positions; an unclamped lerp weight diverges to ±inf here.
	var remote_host := StaticBody3D.new()
	root.add_child(remote_host)
	var remote_model := (load("res://assets/Evan_Skeleton.glb") as PackedScene).instantiate() as Node3D
	remote_model.set_script(load("res://src/game/EvanVisual.gd"))
	remote_host.add_child(remote_model)
	await process_frame
	for _i in range(120):
		remote_host.global_position.x += 0.5
		await physics_frame
	var remote_speed: float = float(remote_model.get("_remote_speed"))
	_check(is_finite(remote_speed) and remote_speed >= 0.0 and remote_speed <= 60.0,
			"remote Evan speed estimate stays finite and bounded (%.3f)" % remote_speed)
	remote_host.queue_free()
	await process_frame

	settings.call("set_value", "gameplay", "vehicle", "auto")
	_restore()
	print("EVAN VERIFY: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
