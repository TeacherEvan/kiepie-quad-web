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
	await _effects()
	await _anchored()
	_death_vfx()
	await _bike_world_vfx()
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
	var fire_tex: ImageTexture = vf._fire_sprite()
	var scorch_tex: ImageTexture = vf._scorch_sprite()
	_check(fire_tex != null and scorch_tex != null, "turbulent fire + organic scorch sprites generated")
	if fire_tex != null and scorch_tex != null:
		var fimg := fire_tex.get_image()
		var simg := scorch_tex.get_image()
		_check(fimg.get_pixel(0, 0).a <= 0.01 and fimg.get_pixel(fimg.get_width() / 2, 0).a <= 0.01,
				"fire sprite hits zero alpha inside quad border (no square edge)")
		_check(simg.get_pixel(0, 0).a <= 0.01 and simg.get_pixel(simg.get_width() / 2, 0).a <= 0.01,
				"scorch sprite hits zero alpha inside quad border (no square scorch artifact)")
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
	vf.particle_explosion(holder, Vector3(3.5, 1, 1), Color(1.0, 0.42, 0.10), 1.55, false)
	vf.mushroom_cloud_explosion(holder, Vector3(11, 1, 1), Color(1.0, 0.26, 0.04), 2.65)
	vf.shield_block(holder, Vector3(4, 1, 1), Color(0.2, 0.8, 1))
	vf.smash_burst(holder, Vector3(5, 1, 1), Vector3(5, 3, 4))
	vf.pickup_burst(holder, Vector3(6, 1, 1), Color(0.2, 1, 0.4))
	vf.dust_ring(holder, Vector3(7, 0, 1), 1.2, 4.0)
	vf.roost(holder, Vector3(8, 0, 1), Vector3.FORWARD)
	_check(holder.get_child_count() > 0, "all VFX entry points build without script errors")
	holder.free()

	# Isolated mushroom-cloud contract: delayed stem/cap emitters actually spawn
	# on a clean holder (not counted from sibling effects), and reduced_motion
	# suppresses both particles and the delayed Wilson condensation ring.
	_set_setting("gameplay", "reduced_motion", false)
	var mush_holder := Node3D.new()
	root.add_child(mush_holder)
	vf.mushroom_cloud_explosion(mush_holder, Vector3(0, 0, 0), Color(1.0, 0.26, 0.04), 2.65)
	await create_timer(0.45).timeout
	var mush_particles := mush_holder.find_children("*", "GPUParticles3D", true, false).size()
	_check(mush_particles >= 6,
			"isolated mushroom cloud spawns >= 6 GPUParticles3D emitters incl. delayed cap beats (got %d)" % mush_particles)
	mush_holder.free()

	_set_setting("gameplay", "reduced_motion", true)
	var mush_rm := Node3D.new()
	root.add_child(mush_rm)
	vf.mushroom_cloud_explosion(mush_rm, Vector3(0, 0, 0), Color(1.0, 0.26, 0.04), 2.65)
	await create_timer(0.25).timeout
	var rm_particles := mush_rm.find_children("*", "GPUParticles3D", true, false).size()
	var rm_meshes := mush_rm.find_children("*", "MeshInstance3D", true, false)
	var rm_rings := 0
	for m in rm_meshes:
		var mi := m as MeshInstance3D
		if mi.position.y > 0.5:  # Wilson ring spawns at local y = 1.25
			rm_rings += 1
	_check(rm_particles == 0 and rm_rings == 0,
			"reduced_motion suppresses mushroom particles (%d) and delayed Wilson ring (%d)" % [rm_particles, rm_rings])
	_set_setting("gameplay", "reduced_motion", false)
	mush_rm.free()


func _anchored() -> void:
	## MVTH-1 / P2-5 regression gate: the staggered settlement dust from
	## smash_burst() must stay anchored to the collapse site. The old code
	## handed `local` offsets to dust_puff() as world positions, which spawned
	## the delayed dust columns near the origin regardless of where the
	## building fell. This gate would have caught that bug.
	var holder := Node3D.new()
	root.add_child(holder)
	var anchor := Vector3(12.0, 0.5, -8.0)
	vf.smash_burst(holder, anchor, Vector3(6.5, 3.4, 5.0))
	# puffs fire at delays 0 / 0.12 / 0.28 s — wait for the last one to land
	await create_timer(0.6).timeout
	var total := 0
	var near := 0
	for child in holder.get_children():
		if child is GPUParticles3D:
			total += 1
			if (child as GPUParticles3D).global_position.distance_to(anchor) <= 5.0:
				near += 1
	_check(total >= 5 and near >= 3,
			"collapse dust anchored to site (%d of %d emitters within 5 m of (12, 0.5, -8))" % [near, total])
	holder.free()


func _bike_world_vfx() -> void:
	## F-09 regression: dust_ring and roost spawned from KiepieBike must attach
	## to the world parent (not the bike itself), so world coordinates are not
	## double-translated when the bike is away from the origin.
	var holder := Node3D.new()
	root.add_child(holder)
	var bike_ps := load("res://scenes/KiepieBike.tscn") as PackedScene
	var bike := bike_ps.instantiate() as VehicleBody3D
	holder.add_child(bike)
	await process_frame
	var world_pos := Vector3(20.0, 0.0, 20.0)
	bike.global_position = world_pos
	var fx_parent: Node3D = bike.call("_fx_parent") as Node3D
	_check(fx_parent != null and fx_parent != bike,
			"F-09: KiepieBike._fx_parent() returns world parent, not self")
	var before := holder.get_child_count()
	vf.dust_ring(fx_parent, world_pos, 1.1, 4.5)
	vf.roost(fx_parent, world_pos, Vector3.FORWARD)
	var spawned := 0
	var not_doubled := 0
	for i in range(before, holder.get_child_count()):
		var c := holder.get_child(i)
		if c is Node3D:
			spawned += 1
			var d := (c as Node3D).global_position.distance_to(world_pos)
			if d <= 1.0:
				not_doubled += 1
	_check(spawned >= 2 and not_doubled == spawned,
			"F-09: dust_ring/roost at (20, 0, 20) stay at world pos, not doubled (%d/%d within 1 m)" % [not_doubled, spawned])
	holder.free()


func _death_vfx() -> void:
	_set_setting("gameplay", "reduced_motion", false)
	var holder := Node3D.new()
	root.add_child(holder)
	vf.dramatic_death_explosion(holder, Vector3(9, 1, 1), Basis.IDENTITY,
			Color(1.0, 0.4, 0.1), false)
	var wreck_ok := false
	for w in get_nodes_in_group("death_wreck"):
		if w is RigidBody3D and w.collision_layer == 0:
			wreck_ok = true
	_check(wreck_ok, "dramatic death spawns tumbling cosmetic wreck (collision_layer == 0)")
	vf.dramatic_death_explosion(holder, Vector3(11, 1, 1), Basis.IDENTITY,
			Color(1.0, 0.4, 0.1), true)
	_check(holder.get_child_count() > 0, "dramatic death (pogo variant) builds without script errors")
	# Reduced motion must suppress the tumbling wreck entirely
	_set_setting("gameplay", "reduced_motion", true)
	var before := get_nodes_in_group("death_wreck").size()
	var holder2 := Node3D.new()
	root.add_child(holder2)
	vf.dramatic_death_explosion(holder2, Vector3(13, 1, 1), Basis.IDENTITY,
			Color(1.0, 0.4, 0.1), false)
	_check(get_nodes_in_group("death_wreck").size() == before,
			"reduced motion suppresses the tumbling wreck")
	_set_setting("gameplay", "reduced_motion", false)
	holder2.free()
	holder.free()


func _decal_caps() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	for i in range(20):
		vf.scorch(holder, Vector3(float(i), 0.0, 0.0))
	for i in range(vf.MAX_SCAR + 5):
		vf.scar(holder, Vector3(float(i), 1.0, 0.0), Vector3.UP, "metal")
	for i in range(vf.MAX_DAMAGE_NUMBERS + 6):
		vf.damage_number(holder, Vector3(float(i), 1.5, 0.0), 30.0, Color(1.0, 0.85, 0.22))
	_check(get_nodes_in_group("vfx_scorch").size() <= vf.MAX_SCORCH,
			"scorch decals capped at %d" % vf.MAX_SCORCH)
	_check(get_nodes_in_group("vfx_scar").size() <= vf.MAX_SCAR,
			"bullet scars capped at %d (exercised at MAX+5)" % vf.MAX_SCAR)
	_check(get_nodes_in_group("vfx_dmg_num").size() <= vf.MAX_DAMAGE_NUMBERS,
			"floating damage numbers capped at %d (got %d)" % [vf.MAX_DAMAGE_NUMBERS, get_nodes_in_group("vfx_dmg_num").size()])
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
		var dust_host := Node3D.new()
		root.add_child(dust_host)
		var vfx_cls := load("res://src/game/VfxFactory.gd")
		vfx_cls.call("dust_ring", dust_host, Vector3(5.0, 3.0, 5.0), 1.1, 4.5)
		var ring_y := 0.0
		for c in dust_host.get_children():
			if c is MeshInstance3D:
				ring_y = (c as Node3D).position.y
				break
		_check(ring_y >= 3.05, "P3-1: dust_ring respects elevated pos.y (got y=%.2f >= 3.05)" % ring_y)
		dust_host.queue_free()
		ride.free()
