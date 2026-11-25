extends SceneTree
## Gate: LEA UNICORN — preference-only registry contract, 52-joint winged rig
## with 4 baked clips, landmark anchors, ground datum/tri budget, MainMenu
## selector, runtime shell swap + LeaVisual hooks, and bounded remote speed.

const SAV := "user://settings.cfg"
const BAK := "user://settings.cfg.lea-gate-backup"

var _fail := 0
var _had_cfg := false
var _prior_user_id: Variant


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		printerr("FAIL ", label)
		_fail += 1


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

	# ---- 1. Preference-only registry. Deal fixtures must remain unchanged.
	_check(str(registry.call("profile", &"LeaUnicorn")) == "lea", "profile(LeaUnicorn) == 'lea'")
	_check(str(registry.call("from_profile", "lea")) == "LeaUnicorn", "from_profile('lea') == LeaUnicorn")
	_check(str(registry.call("display_name", &"LeaUnicorn")) == "LEA UNICORN", "display_name")
	_check(str(registry.call("model_path", &"LeaUnicorn")) == "res://assets/Lea_Unicorn.glb", "model_path")
	_check(bool(registry.call("is_valid", &"LeaUnicorn")), "is_valid(LeaUnicorn)")
	_check(bool(registry.call("is_lea", &"LeaUnicorn")) and not bool(registry.call("is_evan", &"LeaUnicorn")),
			"is_lea true and is_evan false")
	_check(str(registry.call("sanitize_preference", "LeaUnicorn")) == "LeaUnicorn",
			"sanitize_preference accepts LeaUnicorn")
	_check(str(registry.call("sanitize_preference", "ForgedUnicorn")) == "",
			"sanitize_preference rejects an unknown id")
	_check(str(registry.call("resolve_for_player", "lea-test", [], "LeaUnicorn")) == "LeaUnicorn",
			"resolve_for_player honors an explicit Lea preference")
	_check(str(registry.call("for_player", "mock-host")) == "KiepieBike",
			"deal pool unchanged — mock-host still KiepieBike")
	_check(str(registry.call("for_player", "peer-1")) == "PogoNardus",
			"deal pool unchanged — peer-1 still PogoNardus")
	_check(str(registry.call("for_player", "user-42")) == "KiepieBike",
			"deal pool unchanged — user-42 still KiepieBike")
	_check(float(registry.call("cooldown", &"LeaUnicorn")) == 0.16
			and float(registry.call("rapid_cooldown", &"LeaUnicorn")) == 0.08,
			"horn rapid-fire cooldowns 0.16 / 0.08")

	# ---- 2. GLB: 52 joints, 4 real clips, landmarks, ground datum, budget.
	var glb: PackedScene = load("res://assets/Lea_Unicorn.glb")
	_check(glb != null, "Lea GLB loads")
	if glb == null:
		_restore()
		quit(1)
		return
	var model := glb.instantiate() as Node3D
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	_check(skeletons.size() >= 1, "Skeleton3D present")
	if skeletons.size() >= 1:
		_check((skeletons[0] as Skeleton3D).get_bone_count() == 52,
				"creature rig has 52 joints (%d)" % (skeletons[0] as Skeleton3D).get_bone_count())
	var players := model.find_children("*", "AnimationPlayer", true, false)
	_check(players.size() >= 1, "AnimationPlayer present")
	if players.size() >= 1:
		var ap := players[0] as AnimationPlayer
		for clip in ["Idle_Breathe", "Locomotion_Gallop", "Action_WingSpread", "UnicornBoom_Flight"]:
			_check(ap.has_animation(clip), "NLA clip %s baked" % clip)
			var anim: Animation = ap.get_animation(clip)
			_check(anim != null and anim.get_track_count() > 0 and anim.length > 0.0,
					"NLA clip %s has real tracks and duration" % clip)
		var gallop: Animation = ap.get_animation("Locomotion_Gallop")
		if gallop != null:
			var has_fore := false
			var has_hind := false
			for ti in range(gallop.get_track_count()):
				var tp := str(gallop.track_get_path(ti))
				if tp.find("ForeUpper") >= 0:
					has_fore = true
				elif tp.find("HindThigh") >= 0:
					has_hind = true
			_check(has_fore and has_hind, "gallop clip animates fore and hind leg chains")
	for landmark in ["HornTip", "HornBase", "HornMuzzle_L", "HornMuzzle_R", "Wing_L", "Wing_R",
			"ManeForelock", "TailRoot", "Eye_L", "Eye_R", "Hoof_FL", "Hoof_FR", "Hoof_RL", "Hoof_RR",
			"LeaBrand"]:
		_check(_find(model, landmark) != null, "landmark %s present" % landmark)
	var brand_mi := _find(model, "LeaBrand") as MeshInstance3D
	_check(brand_mi != null and brand_mi.get_aabb().get_center().x < 0.0,
			"LeaBrand sits on Lea's right butt cheek")
	_check(_find(model, "Tyre_F_L") == null and _find(model, "Seat") == null,
			"no quad tyres or seat — Lea flies on horseback")
	var horn := _find(model, "HornTip") as MeshInstance3D
	var has_gold := false
	if horn != null and horn.mesh != null:
		for s in range(horn.mesh.get_surface_count()):
			var sm: Variant = horn.get_active_material(s)
			if sm is StandardMaterial3D and str((sm as Material).resource_name) == "HornGlow":
				has_gold = true
	_check(has_gold, "HornTip carries the emissive HornGlow material")
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
		for ci in range(8):
			min_y = minf(min_y, (xf * aabb.get_endpoint(ci)).y)
		for s in range(mi.mesh.get_surface_count()):
			tri_count += int(mi.mesh.surface_get_array_index_len(s) / 3.0)
	_check(min_y >= -0.02 and min_y < 0.06, "ground datum (min_y=%.3f)" % min_y)
	_check(tri_count > 0 and tri_count < 10000, "under 10k tris (%d)" % tri_count)
	model.free()

	# ---- 3. SideCannons lea profile (balance comes from VehicleRegistry).
	var cannon_script: GDScript = load("res://src/game/SideCannons.gd")
	_check(cannon_script != null, "SideCannons loads")
	if cannon_script != null:
		var profiles: Variant = cannon_script.get("PROFILES")
		_check(profiles is Dictionary and (profiles as Dictionary).has("lea"),
				"SideCannons has a 'lea' profile")
		var probe := Node3D.new()
		probe.set_script(cannon_script)
		probe.call("setup", probe, "lea-gate", Callable(), Color.WHITE, "lea")
		_check(str(probe.call("weapon_display_name", "primary")) == "HORN RAPID FIRE",
				"primary weapon reads HORN RAPID FIRE")
		_check(str(probe.call("weapon_display_name", "rocket")) == "HORN BEAM",
				"rocket weapon reads HORN BEAM")
		_check(str(probe.call("weapon_display_name", "meteor")) == "UNICORN BOOM",
				"meteor weapon reads UNICORN BOOM")
		var prof: Variant = probe.get("_profile")
		_check(prof is Dictionary and float((prof as Dictionary).get("cooldown", 0.0)) == 0.16,
				"lea cooldown 0.16s")
		probe.free()

	# ---- 4. MainMenu selector and Settings persistence.
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
			_check(vs.item_count == 6 and vs.get_item_text(5) == "LEA UNICORN",
					"VehicleSelect has LEA UNICORN option (6 options)")
			vs.select(5)
			vs.item_selected.emit(5)
			await process_frame
			_check(str(settings.call("preferred_vehicle")) == "LeaUnicorn",
					"selecting LEA persists LeaUnicorn preference")
		mm.queue_free()
		await process_frame

	# ---- 5. Runtime swap + animation hooks in a fresh scene.
	settings.call("set_value", "gameplay", "vehicle", "LeaUnicorn")
	var scene: PackedScene = load("res://scenes/TestRide.tscn")
	var ride := scene.instantiate() as Node3D
	root.add_child(ride)
	for _i in range(5):
		await physics_frame
	var bike := ride.get_node_or_null("KiepieBike") as Node3D
	_check(bike != null, "bike node exists after swap")
	if bike != null:
		_check(str(bike.get("vehicle_profile")) == "lea", "vehicle_profile == lea after swap")
		var lea_model: Node = bike.get_node_or_null("Model")
		_check(lea_model != null and _find(lea_model, "HornTip") != null,
				"Model swapped to the Lea GLB")
		if lea_model != null:
			var script: Variant = lea_model.get_script()
			_check(script != null and str(script.resource_path).ends_with("LeaVisual.gd"),
					"Model carries LeaVisual.gd")
			var horn_pos: Vector3 = lea_model.call("get_horn_world_pos")
			_check(is_finite(horn_pos.x + horn_pos.y + horn_pos.z),
					"get_horn_world_pos is finite")
			lea_model.call("trigger_charge", 1.0)
			_check(float(lea_model.get("_charge_cd")) > 0.0
					and str(lea_model.get("_last_clip")) == "Action_WingSpread",
					"trigger_charge arms wing-spread clip and lockout")
			lea_model.call("trigger_boom")
			_check(float(lea_model.get("_boom_cd")) > 0.0
					and str(lea_model.get("_last_clip")) == "UnicornBoom_Flight",
					"trigger_boom arms the flight clip and lockout")
		var combat: Node = bike.get_node_or_null("CombatController")
		var cannons: Node = combat.get("cannons") if combat != null else null
		_check(cannons != null and str(cannons.get("weapon_profile")) == "lea",
				"SideCannons switched to the lea profile")
	ride.queue_free()
	await process_frame

	# ---- 6. Remote-proxy speed estimator must stay finite and bounded.
	var remote_host := StaticBody3D.new()
	root.add_child(remote_host)
	var remote_model := (load("res://assets/Lea_Unicorn.glb") as PackedScene).instantiate() as Node3D
	remote_model.set_script(load("res://src/game/LeaVisual.gd"))
	remote_host.add_child(remote_model)
	await process_frame
	for _i in range(120):
		remote_host.global_position.x += 0.5
		await physics_frame
	var remote_speed := float(remote_model.get("_remote_speed"))
	_check(is_finite(remote_speed) and remote_speed >= 0.0 and remote_speed <= 60.0,
			"remote Lea speed estimate stays finite and bounded (%.3f)" % remote_speed)
	remote_host.queue_free()
	await process_frame

	settings.call("set_value", "gameplay", "vehicle", "auto")
	_restore()
	print("LEA VERIFY: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
