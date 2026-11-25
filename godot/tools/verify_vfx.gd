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
	var guard := load("res://tools/_gate_settings_guard.gd") as GDScript
	var cfg_snap: Dictionary = guard.call("backup", root)
	vf = load("res://src/game/VfxFactory.gd") as GDScript
	_textures()
	_scaling()
	await _effects()
	await _meteor_clamp()
	await _anchored()
	_death_vfx()
	await _bike_world_vfx()
	_decal_caps()
	await _layout()
	guard.call("restore", root, cfg_snap)
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


func _meteor_clamp() -> void:
	## MeteorStrike._detonate: the dust ring renders at/above ground even
	## when target_pos dips below y=0 (MeteorStrike.gd:265 clamps target_pos.y;
	## the ring quad is at pos.y + 0.10).
	var meteor_script := load("res://src/game/MeteorStrike.gd") as GDScript
	var owner := Node3D.new()
	var m := Node3D.new()
	m.set_script(meteor_script)
	owner.add_child(m)
	root.add_child(owner)
	m.set("target_pos", Vector3(3.5, -0.5, 2.0))
	await process_frame
	m.call("_detonate")
	await process_frame
	var ring_quads := []
	for c in owner.get_children():
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		var qm := mi.mesh as QuadMesh
		if qm != null and absf(qm.size.x - 5.6) < 0.01:
			ring_quads.append(mi)
	_check(ring_quads.size() >= 1,
			"MeteorStrike dust ring spawns a QuadMesh of size 5.6 (n=%d)" % ring_quads.size())
	var above := 0
	for q in ring_quads:
		if q.position.y >= 0.05:
			above += 1
	_check(above >= 1,
			"MeteorStrike dust ring spawns at/above ground (y>=0.05, n=%d of %d)" % [above, ring_quads.size()])
	m.queue_free()
	owner.queue_free()


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
	vf.scorch(holder, Vector3(5.0, 4.0, 5.0))
	var max_scorch_y := 0.0
	for sc_n in get_nodes_in_group("vfx_scorch"):
		if sc_n is Node3D:
			max_scorch_y = maxf(max_scorch_y, (sc_n as Node3D).position.y)
	_check(max_scorch_y >= 4.0, "P3-3: VfxFactory.scorch() respects elevated pos.y (max_y=%.2f)" % max_scorch_y)
	var zero_b: Basis = vf.call("_plane_basis", Vector3.ZERO)
	_check(zero_b.is_finite() and zero_b.determinant() > 0.5, "P2-8: VfxFactory._plane_basis(ZERO) returns finite basis")
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
		# P2-12: no TestRide cone may impale any Ramp*
		var min_cone_ramp_gap := 1e9
		for c in ride.get_children():
			if c is StaticBody3D and str(c.name).begins_with("Cone"):
				for r in ramps:
					min_cone_ramp_gap = minf(min_cone_ramp_gap, _clearance(
							AABB((c as Node3D).global_position - Vector3(0.3, 0.3, 0.3), Vector3(0.6, 0.6, 0.6)),
							_footprint(r as Node3D)))
		_check(min_cone_ramp_gap >= 1.5,
				"P2-12: TestRide cones clear all ramps by >= 1.5 m (min %.2f m)" % min_cone_ramp_gap)
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

	await _pooling_and_settings()


func _pooling_and_settings() -> void:
	var settings_node := root.get_node_or_null("Settings")
	if settings_node != null:
		var prior_rm: bool = bool(settings_node.call("reduced_motion"))
		var prior_glow: Variant = settings_node.call("get_value", "video", "glow", true)
		settings_node.call("set_value", "video", "glow", true)
		var is_mob: bool = bool(settings_node.call("_is_mobile_auto"))
		_check(bool(settings_node.call("effective_glow")) == (not is_mob),
				"Settings.effective_glow() respects video/glow and mobile-auto")
		settings_node.call("set_value", "video", "glow", false)
		_check(not bool(settings_node.call("effective_glow")),
				"Settings.effective_glow() returns false when video/glow=false")
		settings_node.call("set_value", "video", "glow", prior_glow)

		# DestructibleBuilding reduced_motion debris guard
		var bldg_script := load("res://src/DestructibleBuilding.gd") as GDScript
		if bldg_script != null:
			var bldg_holder := Node3D.new()
			root.add_child(bldg_holder)
			settings_node.call("set_value", "gameplay", "reduced_motion", true)
			var b1 := StaticBody3D.new()
			b1.set_script(bldg_script)
			bldg_holder.add_child(b1)
			b1.call("smash", Vector3.FORWARD)
			var debris_rm := 0
			for c in bldg_holder.get_children():
				if c is RigidBody3D:
					debris_rm += 1
			_check(debris_rm == 0, "DestructibleBuilding.smash() spawns 0 debris under reduced_motion=true (got %d)" % debris_rm)
			b1.queue_free()

			settings_node.call("set_value", "gameplay", "reduced_motion", false)
			var b2 := StaticBody3D.new()
			b2.set_script(bldg_script)
			bldg_holder.add_child(b2)
			b2.call("smash", Vector3.FORWARD)
			var debris_full := 0
			for c in bldg_holder.get_children():
				if c is RigidBody3D:
					debris_full += 1
					c.queue_free()
			_check(debris_full >= 4, "DestructibleBuilding.smash() spawns >=4 debris under reduced_motion=false (got %d)" % debris_full)
			b2.queue_free()
			bldg_holder.queue_free()
			await process_frame
		settings_node.call("set_value", "gameplay", "reduced_motion", prior_rm)

	# SideCannons 30-shot pool cap + bike->pogo swap + muzzle tracking + _exit_tree cleanup
	var cannons_script := load("res://src/game/SideCannons.gd") as GDScript
	if cannons_script != null:
		var owner_bike := Node3D.new()
		root.add_child(owner_bike)
		var m_l := Node3D.new()
		m_l.name = "Muzzle_L"
		m_l.position = Vector3(-0.4, 0.5, 0.5)
		owner_bike.add_child(m_l)
		var m_r := Node3D.new()
		m_r.name = "Muzzle_R"
		m_r.position = Vector3(0.4, 0.5, 0.5)
		owner_bike.add_child(m_r)
		var sc := Node3D.new()
		sc.set_script(cannons_script)
		owner_bike.add_child(sc)
		sc.call("setup", owner_bike, "p1", Callable(), Color.WHITE, "bike")
		var match_node := root.get_node_or_null("Match")
		var prev_lobby: Dictionary = (match_node.get("lobby") as Dictionary).duplicate(true) if match_node != null else {}
		if match_node != null:
			match_node.set("lobby", {"status": "waiting", "settings": {}})
		sc.set("_cooldown", 0.0)
		sc.call("fire")
		await process_frame
		_check((sc.get("_muzzle_flashes") as Array).is_empty() and (sc.get("_proj_pool") as Array).is_empty(),
				"P2-6: SideCannons.fire emits 0 muzzle flashes/projectiles when Match.is_playing() is false")
		if match_node != null:
			match_node.set("lobby", {"status": "playing", "settings": {"damage": 30.0}})
		for _s in range(30):
			sc.set("_cooldown", 0.0)
			sc.call("fire")
		await process_frame
		var pool: Array = sc.get("_proj_pool")
		_check(pool.size() > 0 and pool.size() <= 48, "SideCannons 30 rapid shots keeps _proj_pool in 1..48 (got %d)" % pool.size())
		var all_valid := true
		for p in pool:
			if not is_instance_valid(p):
				all_valid = false
		_check(all_valid, "SideCannons _proj_pool slots are all valid")

		# Swap bike -> pogo and verify stale bike slots cleared + muzzle flash tracking + cleanup
		m_l.name = "BananaMuzzle_L"
		m_r.name = "BananaMuzzle_R"
		m_l.position = Vector3(-0.3, 1.2, 0.4)
		m_r.position = Vector3(0.3, 1.2, 0.4)
		sc.call("setup", owner_bike, "p1", Callable(), Color.WHITE, "pogo")
		_check((sc.get("_proj_pool") as Array).is_empty(),
				"P1-9b: SideCannons.setup(..., 'pogo') clears stale bike Projectile.gd slots")
		sc.set("_cooldown", 0.0)
		sc.call("fire")
		await process_frame
		if match_node != null:
			match_node.set("lobby", prev_lobby)
		var flashes: Array = sc.get("_muzzle_flashes")
		_check(flashes.size() == 2 and is_instance_valid(flashes[0]),
				"SideCannons bike->pogo swap rebuilds 2 MuzzleFlashPool nodes")
		if flashes.size() >= 1 and is_instance_valid(flashes[0]):
			_check(absf((flashes[0] as Node3D).position.y - 1.2) < 0.05,
					"MuzzleFlashPool tracks vertical muzzle movement (y=%.2f)" % (flashes[0] as Node3D).position.y)
		sc.queue_free()
		await process_frame
		var leftover_flashes := 0
		for c in owner_bike.get_children():
			if c.name.begins_with("MuzzleFlashPool"):
				leftover_flashes += 1
		_check(leftover_flashes == 0, "SideCannons._exit_tree() frees MuzzleFlashPool nodes (leftover=%d)" % leftover_flashes)
		owner_bike.queue_free()

	# BananaProjectile trail parent + recycled state cleanup
	var banana_script := load("res://src/game/BananaProjectile.gd") as GDScript
	if banana_script != null:
		var bp := Node3D.new()
		bp.set_script(banana_script)
		bp.set("velocity", Vector3.FORWARD * 40.0)
		bp.set("on_hit", func(_a, _b, _c): pass)
		root.add_child(bp)
		await process_frame
		var trail: Node = bp.get("_trail")
		_check(trail == null or trail.get_parent() == bp,
				"BananaProjectile._trail is parented to self (not _tracer)")
		bp.call("_recycle")
		_check(not (bp.get("on_hit") as Callable).is_valid(),
				"BananaProjectile._recycle() clears on_hit Callable")
		bp.queue_free()

	# ArenaNet 40-shot remote pool cap (with real initialised remote peer)
	var net_script := load("res://src/game/ArenaNet.gd") as GDScript
	if net_script != null:
		var net := Node3D.new()
		net.set_script(net_script)
		root.add_child(net)
		var peer_stub_gd := GDScript.new()
		peer_stub_gd.source_code = "extends Node3D\nvar _initialised := true\nvar is_respawning := false\n"
		peer_stub_gd.reload()
		var peer_node := Node3D.new()
		peer_node.set_script(peer_stub_gd)
		net.add_child(peer_node)
		(net.get("_remote") as Dictionary)["peer-2"] = peer_node
		for _r in range(40):
			if _r == 20:
				(net.get("_shot_log") as Dictionary).clear()
			net.call("_spawn_remote_shot", {"id": "peer-2", "o": [0.0, 0.0, 0.0], "d": [0.0, 0.0, 1.0], "token": "tok"})
		var rpool: Array = net.get("_remote_proj_pool")
		_check(rpool.size() > 0 and rpool.size() <= 32, "ArenaNet 40 remote shots caps _remote_proj_pool in (0..32] (got %d)" % rpool.size())

		# P1-9a: mixed Quad ("user-42") + Nardus ("peer-1") alternating shots reuse pooled slots without thrashing
		var mix_net := Node3D.new()
		mix_net.set_script(net_script)
		root.add_child(mix_net)
		var stub_gd := GDScript.new()
		stub_gd.source_code = "extends Node3D\nvar _initialised := true\nvar is_respawning := false\n"
		stub_gd.reload()
		var s_quad := Node3D.new()
		s_quad.set_script(stub_gd)
		var s_pogo := Node3D.new()
		s_pogo.set_script(stub_gd)
		root.add_child(s_quad)
		root.add_child(s_pogo)
		mix_net.set("_remote", {"user-42": s_quad, "peer-1": s_pogo})
		var m_mix := root.get_node_or_null("Match")
		var prev_players: Dictionary = (m_mix.get("players") as Dictionary).duplicate(true) if m_mix != null else {}
		if m_mix != null:
			m_mix.set("players", {"user-42": {}, "peer-1": {}})
		for _m in range(32):
			var pid := "user-42" if (_m % 2 == 0) else "peer-1"
			mix_net.call("_spawn_remote_shot", {"id": pid, "o": [0.0, 0.0, 0.0], "d": [0.0, 0.0, 1.0], "token": "mix-%d" % _m})
		var mix_pool: Array = mix_net.get("_remote_proj_pool")
		_check(mix_pool.size() == 32, "P1-9a: 32 mixed remote shots populate full pool (got %d)" % mix_pool.size())
		var ids_before: Dictionary = {}
		for p in mix_pool:
			if is_instance_valid(p):
				ids_before[p.get_instance_id()] = true
		(mix_net.get("_shot_log") as Dictionary).clear()
		for _m2 in range(16):
			var pid2 := "peer-1" if (_m2 % 2 == 0) else "user-42"
			mix_net.call("_spawn_remote_shot", {"id": pid2, "o": [0.0, 0.0, 0.0], "d": [0.0, 0.0, 1.0], "token": "mix2-%d" % _m2})
		var survived := 0
		for p in (mix_net.get("_remote_proj_pool") as Array):
			if is_instance_valid(p) and ids_before.has(p.get_instance_id()):
				survived += 1
		_check(survived == 32, "P1-9a: mixed Quad/Nardus remote pool reuses slots without thrashing (%d/32 survived)" % survived)
		if m_mix != null:
			m_mix.set("players", prev_players)
		s_quad.queue_free()
		s_pogo.queue_free()
		mix_net.queue_free()
		net.queue_free()
		await process_frame

	# P2-4: global explosion shard cap (MAX_EXPLOSION_SHARDS = 36)
	var s_node_cap := root.get_node_or_null("Settings")
	var prev_rm: Variant = s_node_cap.call("get_value", "gameplay", "reduced_motion", false) if s_node_cap != null else false
	var prev_pq: Variant = s_node_cap.call("get_value", "video", "particles", 1.0) if s_node_cap != null else 1.0
	if s_node_cap != null:
		s_node_cap.call("set_value", "gameplay", "reduced_motion", false)
		s_node_cap.call("set_value", "video", "particles", 1.0)
	var shard_holder := Node3D.new()
	root.add_child(shard_holder)
	var vfx_gd := load("res://src/game/VfxFactory.gd") as GDScript
	for _e in range(6):
		vfx_gd.call("particle_explosion", shard_holder, Vector3.ZERO, Color.ORANGE, 1.0, false)
	var shard_nodes := get_nodes_in_group("vfx_shard")
	_check(shard_nodes.size() > 0 and shard_nodes.size() <= 36,
			"P2-4: 6 explosions cap vfx_shard group <= 36 (got %d)" % shard_nodes.size())
	for sn in shard_nodes:
		if is_instance_valid(sn):
			sn.remove_from_group("vfx_shard")
			sn.queue_free()
	shard_holder.queue_free()
	if s_node_cap != null:
		s_node_cap.call("set_value", "gameplay", "reduced_motion", prev_rm)
		s_node_cap.call("set_value", "video", "particles", prev_pq)
	await process_frame

	# P2-1: Projectile pooled reuse resets visible, physics_process, and _age
	var proj_gd := load("res://src/game/Projectile.gd") as GDScript
	var proj := Node3D.new()
	proj.set_script(proj_gd)
	root.add_child(proj)
	proj.visible = false
	proj.set_physics_process(false)
	proj.set("_age", 9.0)
	proj.call("setup", "p1", null, Vector3.ZERO, Vector3.FORWARD, 52.0, 30.0, "tok", Color.WHITE)
	_check(proj.visible and proj.is_physics_processing() and float(proj.get("_age")) == 0.0,
			"P2-1: Projectile pooled reuse resets visible, physics_process, and _age")
	proj.queue_free()

	# P2-1b: BananaProjectile degenerate-first-call pooled reuse resets visible, physics_process, and _age
	var bp_pool := Node3D.new()
	bp_pool.set_script(banana_script)
	bp_pool.set("pooled", true)
	root.add_child(bp_pool)
	bp_pool.call("setup", "p1", null, Vector3.ZERO, Vector3.ZERO, 52.0, 60.0, "tok-bad", Color.YELLOW)
	bp_pool.call("setup", "p1", null, Vector3.ZERO, Vector3.FORWARD, 52.0, 60.0, "tok-ok", Color.YELLOW)
	_check(bp_pool.visible and bp_pool.is_physics_processing() and float(bp_pool.get("_age")) == 0.0,
			"P2-1b: BananaProjectile degenerate-first-call pooled reuse resets visible, physics_process, and _age")
	bp_pool.queue_free()

	# P2-2: impact() OmniLight3D freed by 0.20s
	var fx_holder := Node3D.new()
	root.add_child(fx_holder)
	vfx_gd.call("impact", fx_holder, Vector3.ZERO, Color.WHITE, Vector3.UP, "metal", Vector3.UP)
	_check(get_nodes_in_group("vfx_light").size() > 0, "P2-2: impact() spawns vfx_light")
	await create_timer(0.20).timeout
	_check(get_nodes_in_group("vfx_light").size() == 0, "P2-2: impact() vfx_light freed by 0.20s")

	# P2-5: casing() returns early under reduced_motion
	if s_node_cap != null:
		s_node_cap.call("set_value", "gameplay", "reduced_motion", true)
	var before_casing := fx_holder.get_child_count()
	vfx_gd.call("casing", fx_holder, Vector3.ZERO, Vector3.RIGHT)
	_check(fx_holder.get_child_count() == before_casing, "P2-5: casing() skips under reduced_motion")
	if s_node_cap != null:
		s_node_cap.call("set_value", "gameplay", "reduced_motion", prev_rm)

	# Track B: lightning_strike_explosion & cash_explosion smoke + reduced_motion + particles=0.0 + bolt mesh reuse
	vfx_gd.call("prewarm")
	var cb_gd := load("res://src/game/CashBagVisual.gd") as GDScript
	_check(cb_gd != null and bool(cb_gd.get("_initialized")), "P2-2: VfxFactory.prewarm() warms CashBagVisual")

	vfx_gd.call("lightning_strike_explosion", fx_holder, Vector3.ZERO, 1.35)
	var bolt_meshes := {}
	for mi in fx_holder.find_children("*", "MeshInstance3D", true, false):
		var m_inst := mi as MeshInstance3D
		if m_inst != null and m_inst.mesh is CylinderMesh:
			bolt_meshes[m_inst.mesh.get_instance_id()] = true
	_check(bolt_meshes.size() == 1, "P2-2: MegaBolt segments share 1 cached CylinderMesh (got %d)" % bolt_meshes.size())

	if s_node_cap != null:
		s_node_cap.call("set_value", "gameplay", "reduced_motion", true)
	var rm_holder := Node3D.new()
	root.add_child(rm_holder)
	vfx_gd.call("cash_explosion", rm_holder, Vector3.ZERO, true)
	vfx_gd.call("lightning_strike_explosion", rm_holder, Vector3.ZERO, 1.35)
	var rm_gpu := rm_holder.find_children("*", "GPUParticles3D", true, false)
	var ring_tex: Variant = vfx_gd.call("_ring_sprite")
	var rm_rings := 0
	for mi in rm_holder.find_children("*", "MeshInstance3D", true, false):
		var m_inst := mi as MeshInstance3D
		if m_inst != null and m_inst.material_override is StandardMaterial3D:
			if (m_inst.material_override as StandardMaterial3D).albedo_texture == ring_tex:
				rm_rings += 1
	_check(rm_gpu.is_empty() and rm_rings == 0,
			"P1-5: cash_explosion & lightning_strike_explosion spawn 0 GPUParticles3D and 0 ring-sprite quads under reduced_motion")
	_check(rm_holder.find_child("MegaBolt", true, false) != null,
			"P1-5: MegaBolt spawns initially under reduced_motion")
	await create_timer(0.40).timeout
	_check(rm_holder.find_child("MegaBolt", true, false) == null and get_nodes_in_group("vfx_light").size() == 0,
			"P1-5: reduced_motion heavy strikes free MegaBolt and vfx_light by 0.40s")
	rm_holder.queue_free()
	if s_node_cap != null:
		s_node_cap.call("set_value", "gameplay", "reduced_motion", prev_rm)
		s_node_cap.call("set_value", "video", "particles", 0.0)
	var q0_holder := Node3D.new()
	root.add_child(q0_holder)
	vfx_gd.call("cash_explosion", q0_holder, Vector3.ZERO, true)
	var r_gd := load("res://src/game/RocketProjectile.gd") as GDScript
	if r_gd != null:
		var rp := Node3D.new()
		rp.set_script(r_gd)
		q0_holder.add_child(rp)
		rp.call("setup", "p1", null, Vector3.ZERO, Vector3.FORWARD, 35.0, 60.0, "q0-r", Color.ORANGE)
	var m_gd := load("res://src/game/MeteorStrike.gd") as GDScript
	if m_gd != null:
		var ms := Node3D.new()
		ms.set_script(m_gd)
		q0_holder.add_child(ms)
		ms.call("setup", "p1", null, Vector3.ZERO, 90.0, "q0-m", Color.ORANGE, 0.5, 6.0, "meteor")
	var db_gd := load("res://src/DestructibleBuilding.gd") as GDScript
	if db_gd != null:
		var db := StaticBody3D.new()
		db.set_script(db_gd)
		q0_holder.add_child(db)
		db.call("smash", Vector3(0.0, 2.0, 8.0))
	_check(q0_holder.find_children("*", "GPUParticles3D", true, false).is_empty(),
			"P2-3: particles=0.0 spawns 0 GPUParticles3D across cash_explosion, RocketProjectile, MeteorStrike, and DestructibleBuilding")
	vfx_gd.call("particle_explosion", q0_holder, Vector3.ZERO, Color.ORANGE, 1.0, false)
	vfx_gd.call("lightning_strike_explosion", q0_holder, Vector3.ZERO, 1.35)
	_check(q0_holder.find_children("*", "OmniLight3D", true, false).is_empty(),
			"P3-10: particles=0.0 spawns 0 OmniLight3D nodes across particle_explosion, lightning_strike_explosion, and cash_explosion")
	q0_holder.queue_free()
	if s_node_cap != null:
		s_node_cap.call("set_value", "video", "particles", prev_pq)

	fx_holder.queue_free()
	await process_frame
