extends SceneTree
## Offline gate for the VFX overhaul + new level content. Locks:
##  - reduced-motion / quality scaling contracts of VfxFactory
##  - the flat-normal and 3-stop gradient regressions
##  - scorch/scar caps so repeated fights cannot leak decals
##  - new ramp/building counts and spawn/building clearance
## Never touches the live backend (run_gates.sh exports KIEPIE_MOCK_BACKEND=1).

var vf: GDScript   # loaded at runtime: -s tool scripts cannot resolve autoloads at compile time

var _fail := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS ", label)
	else:
		printerr("FAIL ", label)
		_fail += 1


func _initialize() -> void:
	_run()


func _set_setting(section: String, key: String, value: Variant) -> void:
	# Mutate in-memory config only — never persist to user://settings.cfg.
	var settings: Node = root.get_node("Settings")
	var cfg: Dictionary = settings.get("data")
	var sec: Dictionary = cfg.get(section, {})
	sec[key] = value
	cfg[section] = sec
	settings.set("data", cfg)


func _run() -> void:
	await process_frame
	vf = load("res://src/game/VfxFactory.gd") as GDScript
	_textures()
	_scaling()
	_effects()
	_decal_caps()
	await _layout()
	print("VFX: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)


func _textures() -> void:
	vf.prewarm()
	_check(vf._soft_sprite() != null and vf._streak_sprite() != null,
			"soft puff + spark streak generated")
	_check(vf._flare_sprite() != null and vf._ring_sprite() != null,
			"flare star + ground ring generated")
	_check(vf._smoke_sprite() != null, "noise smoke sprite generated")
	var ramp: GradientTexture1D = vf._ramp([
			Color(1, 1, 1, 1), Color(1, 0.5, 0.1, 0.7), Color(1, 0.2, 0, 0)])
	_check(ramp.gradient.get_point_count() == 3 and
			is_equal_approx(ramp.gradient.get_offset(2), 1.0),
			"three-stop particle ramp keeps its transparent fade")


func _scaling() -> void:
	_set_setting("gameplay", "reduced_motion", true)
	var holder := Node3D.new()
	root.add_child(holder)
	_check(vf._particle(holder, Vector3.ZERO, 20, 0.5, Vector3.UP, 30.0,
			1.0, 2.0, [Color.WHITE, Color(1, 1, 1, 0)], 0.5) == null,
			"reduced motion suppresses burst particles")
	holder.free()
	_set_setting("gameplay", "reduced_motion", false)

	_set_setting("video", "particles", 1.0)
	var hi := Node3D.new()
	root.add_child(hi)
	var p1 = vf._particle(hi, Vector3.ZERO, 100, 0.5, Vector3.UP, 30.0,
			1.0, 2.0, [Color.WHITE, Color(1, 1, 1, 0)], 0.5)
	_set_setting("video", "particles", 0.45)
	var p2 = vf._particle(hi, Vector3.ZERO, 100, 0.5, Vector3.UP, 30.0,
			1.0, 2.0, [Color.WHITE, Color(1, 1, 1, 0)], 0.5)
	_check(p1 != null and p2 != null and p1.amount == 100 and p2.amount == 45,
			"quality multiplier scales particle counts (got %d / %d)" % [p1.amount, p2.amount])
	hi.free()
	_set_setting("video", "particles", 1.0)


func _effects() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	vf.muzzle_flash(holder, Vector3(1, 1, 1), Vector3.FORWARD, Color(1, 0.6, 0.2))
	vf.impact(holder, Vector3(2, 1, 1), Color(1, 0.6, 0.2), Vector3.FORWARD,
			"concrete", Vector3.UP)  # parallel normal used to crash looking_at
	vf.explosion(holder, Vector3(3, 1, 1), Color(1, 0.4, 0.1), 1.0)
	vf.shield_block(holder, Vector3(4, 1, 1), Color(0.2, 0.8, 1))
	vf.smash_burst(holder, Vector3(5, 1, 1), Vector3(5, 3, 4))
	vf.pickup_burst(holder, Vector3(6, 1, 1), Color(0.2, 1, 0.4))
	vf.dust_ring(holder, Vector3(7, 0, 1), 1.2, 4.0)
	vf.roost(holder, Vector3(8, 0, 1), Vector3.FORWARD)
	_check(holder.get_child_count() > 0, "all VFX entry points build without script errors")
	holder.free()


func _decal_caps() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	for i in range(20):
		vf.scorch(holder, Vector3(float(i), 0.0, 0.0))
		vf.scar(holder, Vector3(float(i), 1.0, 0.0), Vector3.UP, "metal")
	_check(get_nodes_in_group("vfx_scorch").size() <= vf.MAX_SCORCH,
			"scorch decals capped at %d" % vf.MAX_SCORCH)
	_check(get_nodes_in_group("vfx_scar").size() <= vf.MAX_SCAR,
			"bullet scars capped at %d" % vf.MAX_SCAR)
	holder.free()


func _footprint(node: Node3D) -> AABB:
	## X/Z footprint of a StaticBody's first BoxShape3D, world-space.
	for child in node.get_children():
		if child is CollisionShape3D:
			var shape := (child as CollisionShape3D).shape
			if shape is BoxShape3D:
				var half := (shape as BoxShape3D).size * 0.5
				var centre: Vector3 = node.global_position + (child as CollisionShape3D).position
				return AABB(centre - half, half * 2.0)
	return AABB(node.global_position, Vector3.ONE)


func _clearance(a: AABB, b: AABB) -> float:
	var dx: float = maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0)
	var dz: float = maxf(maxf(a.position.z - b.end.z, b.position.z - a.end.z), 0.0)
	return sqrt(dx * dx + dz * dz)


func _layout() -> void:
	var arena_ps := load("res://scenes/Arena.tscn") as PackedScene
	_check(arena_ps != null, "Arena scene loads")
	if arena_ps != null:
		var arena := arena_ps.instantiate() as Node3D
		root.add_child(arena)
		for i in range(4):
			await process_frame
		var ramps: Array = arena.find_children("Ramp*", "StaticBody3D", true, false)
		var buildings: Array = arena.get_tree().get_nodes_in_group("destructible")
		var spawns: Array = arena.get_tree().get_nodes_in_group("spawn_point")
		var pickups := arena.find_children("Pickup*", "Area3D", true, false)
		var drums: Array = arena.get_tree().get_nodes_in_group("hazard")
		_check(ramps.size() == 10, "Arena has 10 ramps (got %d)" % ramps.size())
		_check(buildings.size() == 7, "Arena has 7 destructible buildings (got %d)" % buildings.size())
		_check(spawns.size() == 8, "Arena has 8 spawn points (got %d)" % spawns.size())
		_check(pickups.size() == 8, "Arena still has 8 pickups (got %d)" % pickups.size())
		_check(drums.size() == 10, "Arena still has 10 fuel drums (got %d)" % drums.size())
		_check(arena.get_node_or_null("AmbientVfx/DustMotes") != null,
				"ambient dust emitter built in arena")
		var min_spawn_gap := 1e9
		var min_ramp_gap := 1e9
		for s in spawns:
			for b in buildings:
				min_spawn_gap = minf(min_spawn_gap, _clearance(
						AABB((s as Node3D).global_position, Vector3.ONE), _footprint(b as Node3D)))
		for r in ramps:
			for b in buildings:
				min_ramp_gap = minf(min_ramp_gap, _clearance(
						_footprint(r as Node3D), _footprint(b as Node3D)))
		_check(min_spawn_gap >= 2.5,
				"spawn points clear building walls (min %.2f m)" % min_spawn_gap)
		_check(min_ramp_gap >= 1.0,
				"ramp footprints clear buildings (min %.2f m)" % min_ramp_gap)
		arena.free()

	var ride_ps := load("res://scenes/TestRide.tscn") as PackedScene
	_check(ride_ps != null, "TestRide scene loads")
	if ride_ps != null:
		var ride := ride_ps.instantiate() as Node3D
		root.add_child(ride)
		for i in range(4):
			await process_frame
		var ramps := ride.find_children("Ramp*", "StaticBody3D", true, false)
		var buildings: Array = ride.get_tree().get_nodes_in_group("destructible")
		var hud := ride.get_node_or_null("HUD")
		_check(ramps.size() == 6, "TestRide has 6 ramps (got %d)" % ramps.size())
		_check(buildings.size() == 4, "TestRide has 4 buildings (got %d)" % buildings.size())
		var total: Variant = hud.get("_total") if hud != null else null
		_check(hud != null and int(total) == 4,
				"TestRide HUD total follows the building count (got %s)" % str(total))
		ride.free()
