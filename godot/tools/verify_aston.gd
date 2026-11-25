extends SceneTree
## Gate: Aston Martin ("BIG-BEN") F1 vehicle — GLB quality/size/datum/plate,
## VehicleRegistry 3-way hash & preference override, runtime model/wheel/steer
## swap, F1 AUTOCANNON profile, and MainMenu VehicleSelect.

const SAV := "user://settings.cfg"
const BAK := "user://settings.cfg.aston-gate-backup"

var _fail := 0
var _had_cfg := false
var _prior_user_id: Variant


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		printerr("FAIL ", label)
		_fail += 1


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

	# ---- 1. VehicleRegistry 3-vehicle contract
	_check(str(registry.call("for_player", "peer-2")) == "AstonMartin", "for_player('peer-2') == AstonMartin")
	_check(str(registry.call("profile", &"AstonMartin")) == "aston", "profile(AstonMartin) == 'aston'")
	_check(str(registry.call("display_name", &"AstonMartin")) == "BIG-BEN F1", "display_name(AstonMartin) == 'BIG-BEN F1'")
	_check(str(registry.call("model_path", &"AstonMartin")) == "res://assets/Aston_Martin.glb", "model_path(AstonMartin)")
	_check(str(registry.call("sanitize_preference", "AstonMartin")) == "AstonMartin", "sanitize_preference accepts AstonMartin")
	_check(str(registry.call("sanitize_preference", "ForgedTank")) == "", "sanitize_preference rejects ForgedTank")
	_check(str(registry.call("resolve_for_player", "mock-host", ["mock-host"], "AstonMartin")) == "AstonMartin",
			"resolve_for_player honors explicit AstonMartin preference")

	# ---- 2. Aston_Martin.glb structure, size, datum, plate material, tri budget
	var glb_abs := ProjectSettings.globalize_path("res://assets/Aston_Martin.glb")
	_check(FileAccess.file_exists(glb_abs), "Aston_Martin.glb exists")
	var f := FileAccess.open(glb_abs, FileAccess.READ)
	var glb_bytes := f.get_length() if f != null else 0
	if f != null:
		f.close()
	_check(glb_bytes > 0 and glb_bytes <= 460800, "Aston_Martin.glb size <= 450 KB (%d bytes)" % glb_bytes)

	var glb: PackedScene = load("res://assets/Aston_Martin.glb")
	_check(glb != null, "Aston_Martin.glb PackedScene loads")
	if glb != null:
		var model := glb.instantiate()
		for req in ["Chassis", "RearPlate_BigBen", "Steer_FL", "Steer_FR", "Steer_FL/Wheel_FL", "Steer_FR/Wheel_FR",
				"Wheel_RL", "Wheel_RR", "AstonMuzzle_L", "AstonMuzzle_R", "Exhaust_Tip"]:
			_check(model.get_node_or_null(req) != null, "Aston_Martin.glb has node %s" % req)

		var plate := model.get_node_or_null("RearPlate_BigBen") as MeshInstance3D
		var has_plate_tex := false
		if plate != null and plate.mesh != null:
			for s in range(plate.mesh.get_surface_count()):
				var mat := plate.get_active_material(s)
				if mat is StandardMaterial3D and str(mat.resource_name) == "BigBenPlate" and mat.albedo_texture != null:
					has_plate_tex = true
		_check(has_plate_tex, "RearPlate_BigBen carries BigBenPlate material with albedo_texture")

		var min_y := 1.0e9
		var max_y := -1.0e9
		var min_x := 1.0e9
		var max_x := -1.0e9
		var min_z := 1.0e9
		var max_z := -1.0e9
		var tri_count := 0
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			var mi := mesh as MeshInstance3D
			if mi.mesh != null:
				for s in range(mi.mesh.get_surface_count()):
					var alen: int = int(mi.mesh.surface_get_array_len(s))
					tri_count += int(alen / 3.0) if alen > 0 else 0
			var aabb := mi.get_aabb()
			var xf := Transform3D.IDENTITY
			var cur: Node = mi
			while cur != null and cur != model:
				if cur is Node3D:
					xf = (cur as Node3D).transform * xf
				cur = cur.get_parent()
			for ci in range(8):
				var pt := xf * aabb.get_endpoint(ci)
				min_x = minf(min_x, pt.x); max_x = maxf(max_x, pt.x)
				min_y = minf(min_y, pt.y); max_y = maxf(max_y, pt.y)
				min_z = minf(min_z, pt.z); max_z = maxf(max_z, pt.z)
		_check(min_y >= -0.02 and min_y <= 0.06, "Aston Martin ground datum min_y=%.3f" % min_y)
		# BIG-BEN used to drag its diffuser (~0.016 m). The body shell is lifted
		# slightly while the wheels stay on the datum — lock that clearance.
		var chassis_min_y := 1.0e9
		for mesh2 in model.find_children("*", "MeshInstance3D", true, false):
			var mi2 := mesh2 as MeshInstance3D
			if mi2.name != "Chassis" or mi2.mesh == null:
				continue
			var aabb2 := mi2.get_aabb()
			var xf2 := Transform3D.IDENTITY
			var cur2: Node = mi2
			while cur2 != null and cur2 != model:
				if cur2 is Node3D:
					xf2 = (cur2 as Node3D).transform * xf2
				cur2 = cur2.get_parent()
			for ci2 in range(8):
				chassis_min_y = minf(chassis_min_y, (xf2 * aabb2.get_endpoint(ci2)).y)
		_check(chassis_min_y >= 0.06 and chassis_min_y <= 0.10,
				"BIG-BEN body lifted clear of the deck (chassis min_y=%.3f)" % chassis_min_y)
		_check((max_x - min_x) >= 1.2 and (max_x - min_x) <= 2.2, "Aston width in [1.2, 2.2] (%.2f)" % (max_x - min_x))
		_check((max_z - min_z) >= 2.5 and (max_z - min_z) <= 3.3, "Aston length in [2.5, 3.3] (%.2f)" % (max_z - min_z))
		_check((max_y - min_y) >= 0.65 and (max_y - min_y) <= 1.05, "Aston height in [0.65, 1.05] (%.2f)" % (max_y - min_y))
		_check(tri_count >= 1000 and tri_count <= 12000, "Aston triangle budget sane (%d tris)" % tri_count)
		model.free()

	# ---- 3. Runtime swap in TestRide.tscn (peer-2 hash)
	sb.set("user_id", "peer-2")
	var ride_ps: PackedScene = load("res://scenes/TestRide.tscn")
	var ride := ride_ps.instantiate() as Node3D
	root.add_child(ride)
	for _i in range(4):
		await physics_frame
	var bike := ride.get_node_or_null("KiepieBike") as VehicleBody3D
	_check(bike != null and str(bike.get("vehicle_profile")) == "aston", "peer-2 spawns as AstonMartin ('aston')")
	if bike != null:
		_check(bike.get_node_or_null("Model/RearPlate_BigBen") != null, "Live Aston model has RearPlate_BigBen")
		var steer_nodes: Variant = bike.get("_steer_nodes")
		var wheel_nodes: Variant = bike.get("_wheel_nodes")
		_check(steer_nodes is Dictionary and (steer_nodes as Dictionary).get("FL") != null and (steer_nodes as Dictionary).get("FR") != null,
				"Aston _steer_nodes FL/FR populated")
		_check(wheel_nodes is Dictionary and (wheel_nodes as Dictionary).get("WheelFL") != null and (wheel_nodes as Dictionary).get("WheelRR") != null,
				"Aston _wheel_nodes populated")
		var combat := bike.get_node_or_null("CombatController")
		var cannons: Node = combat.get("cannons") if combat != null else null
		_check(cannons != null and str(cannons.call("weapon_display_name")) == "F1 AUTOCANNON",
				"Aston primary weapon is F1 AUTOCANNON")
		_check(cannons != null and str(cannons.call("weapon_display_name", "rocket")) == "CASH BAG LAUNCHER",
				"BIG-BEN rocket stays CASH BAG LAUNCHER (NARDUS alone uses CIGAR LAUNCHER)")
		var flames := bike.get_node_or_null("ExhaustFlames") as Node3D
		_check(flames != null and absf(flames.position.x) < 0.05 and flames.position.z < -1.0,
				"Aston ExhaustFlames positioned at center rear tailpipe (%.2f, %.2f, %.2f)" % [
					flames.position.x if flames else 99.0,
					flames.position.y if flames else 99.0,
					flames.position.z if flames else 99.0])
	ride.queue_free()
	await process_frame

	# ---- 4. MainMenu VehicleSelect UI & Settings persistence
	var mm_ps: PackedScene = load("res://scenes/MainMenu.tscn")
	if mm_ps != null:
		var mm := mm_ps.instantiate() as Control
		root.add_child(mm)
		await process_frame
		var vs := mm.get_node_or_null("SafeMargin/Scroll/ScrollBox/Card/VBox/VehicleRow/VehicleSelect") as OptionButton
		_check(vs != null and vs.focus_mode == Control.FOCUS_ALL, "MainMenu VehicleSelect exists with FOCUS_ALL")
		if vs != null:
			_check(vs.item_count == 6 and vs.get_item_text(3) == "BIG-BEN F1",
					"VehicleSelect has BIG-BEN F1 option (6 options incl. EVAN and LEA)")
			vs.select(3)
			vs.item_selected.emit(3)
			await process_frame
			var settings := root.get_node("Settings")
			_check(str(settings.call("preferred_vehicle")) == "AstonMartin",
					"Selecting BIG-BEN F1 persists AstonMartin preference in Settings")
		mm.queue_free()
		await process_frame

	_restore()
	print("ASTON VERIFY: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
