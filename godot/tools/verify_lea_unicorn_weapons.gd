extends SceneTree
## Gate: LEA UNICORN's bespoke arsenal — horn rapid-fire bolts, charged straight
## horn beam, the Unicorn Boom aerial flight & supernova landing bang, the shared
## lethal AOE resolver, and SideCannons' "lea" profile wiring. Offline mock only.

const SAV := "user://settings.cfg"
const BAK := "user://settings.cfg.lea-weapons-gate-backup"

const P_BOLT := "res://src/game/HornBoltProjectile.gd"
const P_BEAM := "res://src/game/HornBeam.gd"
const P_BOOM := "res://src/game/UnicornBoom.gd"
const P_AOE := "res://src/game/CombatAoe.gd"
const P_CANNONS := "res://src/game/SideCannons.gd"

var _fail := 0
var _had_cfg := false
var _prior_user_id: Variant
var _prior_reduced: Variant
var _beam_hits: Array = []
var _bolt_hits: Array = []
var _owner_bike: Node3D = null


func _on_bolt_hit(target: Node, _point: Vector3, _proj: Node) -> void:
	_bolt_hits.append(target)


func _on_beam_hit(target: Node, _point: Vector3, _proj: Node) -> void:
	_beam_hits.append(target)


class LethalSink extends Node:
	var calls: Array[Dictionary] = []
	func take_lethal_hit(attacker: String, point: Vector3, token: String) -> void:
		calls.append({"attacker": attacker, "point": point, "token": token})


class BikeStub extends Node3D:
	var player_id: String = ""
	var is_respawning: bool = false


class TargetBody extends StaticBody3D:
	var player_id: String = ""
	var is_respawning: bool = false


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
	var settings: Node = root.get_node_or_null("Settings")
	if settings != null and _prior_reduced != null:
		settings.call("set_value", "gameplay", "reduced_motion", _prior_reduced)
	var sb: Node = root.get_node_or_null("Supabase")
	if sb != null and _prior_user_id != null:
		sb.set("user_id", _prior_user_id)
	if _had_cfg:
		if DirAccess.copy_absolute(BAK, SAV) == OK:
			DirAccess.remove_absolute(BAK)
	elif FileAccess.file_exists(SAV):
		DirAccess.remove_absolute(SAV)


func _load(path: String, label: String) -> GDScript:
	if not ResourceLoader.exists(path):
		_check(false, "%s loads" % label)
		return null
	var script := load(path) as GDScript
	_check(script != null and script.can_instantiate(), "%s loads" % label)
	if script != null and not script.can_instantiate():
		return null
	return script


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
	sb.set("user_id", "lea-weapons-gate")
	var settings: Node = root.get_node_or_null("Settings")
	if settings != null:
		_prior_reduced = settings.call("get_value", "gameplay", "reduced_motion", false)
		settings.call("set_value", "gameplay", "reduced_motion", false)
	var holder := Node3D.new()
	holder.name = "LeaWeaponsHolder"
	root.add_child(holder)

	var bolt_script := _load(P_BOLT, "HornBoltProjectile")
	var beam_script := _load(P_BEAM, "HornBeam")
	var boom_script := _load(P_BOOM, "UnicornBoom")
	var aoe_script := _load(P_AOE, "CombatAoe")
	var cannons_script := _load(P_CANNONS, "SideCannons")
	var vfx_script: GDScript = load("res://src/game/VfxFactory.gd")

	# ---- 1. Horn rapid fire: setup propagation and degenerate-direction guard.
	if bolt_script != null:
		var bolt := Node3D.new()
		bolt.set_script(bolt_script)
		holder.add_child(bolt)
		bolt.call("setup", "lea-owner", holder, Vector3.ZERO, Vector3.ZERO,
				52.0, 30.0, "bolt-tok", Color(1, 0.82, 0.28))
		_check(bool(bolt.get("_inert")), "zero-direction horn bolt stays inert")
		bolt.call("setup", "lea-owner", holder, Vector3.ZERO, Vector3(0, 0, 1),
				52.0, 30.0, "bolt-tok", Color(1, 0.82, 0.28))
		var bv: Vector3 = bolt.get("velocity")
		_check(not bool(bolt.get("_inert")) and bv.length() > 51.0 and bv.length() < 53.0,
				"valid horn bolt gets a full-speed finite velocity")
		_check(float(bolt.get("damage")) == 30.0 and str(bolt.get("token")) == "bolt-tok",
				"horn bolt propagates damage and token")
		bolt.set("pooled", true)
		bolt.set("on_hit", Callable(self, "_on_beam_hit"))
		bolt.call("setup", "lea-owner", holder, Vector3.ZERO, Vector3.ZERO,
				52.0, 30.0, "bolt-tok", Color(1, 0.82, 0.28))
		_check(bool(bolt.get("_inert")) and (bolt.get("on_hit") as Callable).is_null(),
				"pooled horn bolt clears stale callbacks and parks inert")
		if is_instance_valid(bolt):
			bolt.set_physics_process(false)
			bolt.queue_free()

		# Real swept-ray proof: a bolt fired from chassis height must hit a
		# rider-sized collider, which is the bug a horn-tip-only origin hides.
		var bolt_target := TargetBody.new()
		bolt_target.name = "BoltTarget"
		bolt_target.player_id = "lea-weapons-gate"
		bolt_target.position = Vector3(0.0, 0.55, -4.0)
		var bshape := CollisionShape3D.new()
		var bbox := BoxShape3D.new()
		bbox.size = Vector3(0.95, 0.52, 0.95)
		bshape.shape = bbox
		bolt_target.add_child(bshape)
		bolt_target.add_to_group("bike")
		holder.add_child(bolt_target)
		var live_bolt := Node3D.new()
		live_bolt.set_script(bolt_script)
		holder.add_child(live_bolt)
		live_bolt.call("setup", "lea-owner", holder, Vector3(0, 0.55, 0), Vector3(0, 0, -1),
				52.0, 30.0, "bolt-live", Color(1, 0.82, 0.28))
		live_bolt.on_hit = Callable(self, "_on_bolt_hit")
		for _i in range(20):
			await physics_frame
			if not is_instance_valid(live_bolt) or _bolt_hits.size() > 0:
				break
		_check(_bolt_hits.size() > 0, "horn bolt fired at chassis height hits a rider collider")
		if is_instance_valid(live_bolt):
			live_bolt.set_physics_process(false)
			live_bolt.queue_free()
		bolt_target.queue_free()
		await process_frame

	# ---- 2. Horn beam: fail-closed parameters, charge -> straight-line hit.
	if beam_script != null:
		var bad := Node3D.new()
		bad.set_script(beam_script)
		holder.add_child(bad)
		bad.call("setup", "lea-owner", holder, Vector3.ZERO, Vector3(0, 0, 1),
				38.0, NAN, "beam-bad", Color.WHITE)
		_check(bool(bad.get("_inert")), "horn beam rejects NaN damage (fail closed)")

		var target := TargetBody.new()
		target.name = "BeamTarget"
		target.player_id = "lea-weapons-gate"
		target.position = Vector3(0.0, 0.8, -4.0)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.2, 1.2, 1.2)
		shape.shape = box
		target.add_child(shape)
		target.add_to_group("bike")
		holder.add_child(target)
		var sink := LethalSink.new()
		sink.name = "CombatController"
		target.add_child(sink)

		var second := TargetBody.new()
		second.name = "BeamSecondTarget"
		second.player_id = "lea-weapons-gate"
		second.position = Vector3(0.0, 0.8, -8.0)
		var shape2 := CollisionShape3D.new()
		var box2 := BoxShape3D.new()
		box2.size = Vector3(1.2, 1.2, 1.2)
		shape2.shape = box2
		second.add_child(shape2)
		second.add_to_group("bike")
		holder.add_child(second)
		var second_sink := LethalSink.new()
		second_sink.name = "CombatController"
		second.add_child(second_sink)

		var beam := Node3D.new()
		beam.set_script(beam_script)
		holder.add_child(beam)
		beam.call("setup", "lea-owner", holder, Vector3(0, 1.9, 0), Vector3(0, 0, -1),
				38.0, 90.0, "beam-tok", Color(0.40, 0.90, 1.0))
		_check(not bool(beam.get("_inert")) and not bool(beam.get("_beaming")),
				"horn beam starts in the charge phase")
		var charge_vortex := beam.get_node_or_null("ChargeVortex") as Node3D
		var charge_ring := beam.get_node_or_null("ChargeVortex/ChargeRing") as Node3D
		_check(charge_vortex != null and charge_ring != null,
				"horn beam builds a particle vortex in front of the horn")
		_check(charge_vortex != null and charge_vortex.position.is_zero_approx()
				and charge_ring != null and charge_ring.position.z < -0.1,
				"horn beam charge ring offsets along ChargeVortex local forward axis")
		var sparks := beam.get_node_or_null("ChargeVortex/ChargeSparks") as GPUParticles3D
		if sparks != null and sparks.process_material is ParticleProcessMaterial:
			_check((sparks.process_material as ParticleProcessMaterial).direction.z < 0.0,
					"horn beam charge sparks emit along ChargeVortex local -Z forward axis")
		beam.on_hit = Callable(self, "_on_beam_hit")
		for _i in range(48):
			await physics_frame
			if not is_instance_valid(beam) or bool(beam.get("_beaming")):
				break
		_check(bool(beam.get("_beaming")), "horn beam transitions from charge to straight beam")
		var beam_mesh := beam.get_node_or_null("PlasmaBeam") as MeshInstance3D
		if beam_mesh != null:
			var fwd := Vector3(0, 0, -1)
			var half := beam_mesh.scale.z * 0.5
			var far_a := beam_mesh.global_transform * Vector3(0, 0, -0.5)
			var far_b := beam_mesh.global_transform * Vector3(0, 0, 0.5)
			_check(maxf(far_a.dot(fwd), far_b.dot(fwd)) > half * 0.9
					and minf(far_a.dot(fwd), far_b.dot(fwd)) > -0.02,
					"horn beam visual extends forward along the firing ray")
		_check(sink.calls.size() == 1
				and str(sink.calls[0].get("token", "")) == "beam-tok:vlea-weapons-gate",
				"horn beam lethally hits a rider on the line with a victim sub-token")
		_check(_beam_hits.size() >= 2, "horn beam invokes on_hit for every rider on the line")
		_check(second_sink.calls.is_empty(),
				"only the first rider on the beam line is a lethal direct hit")
		if is_instance_valid(beam):
			beam.set_physics_process(false)
			beam.queue_free()
		target.queue_free()
		second.queue_free()
		await process_frame

	# ---- 3. Unicorn Boom: bounded setup, real lethal resolver invocation.
	if boom_script != null:
		var bad_boom := Node3D.new()
		bad_boom.set_script(boom_script)
		holder.add_child(bad_boom)
		bad_boom.call("setup", "lea-owner", holder, Vector3.ZERO,
				NAN, "boom-bad", Color.WHITE, 2.0, 7.5)
		_check(not bool(bad_boom.get("_armed")), "unicorn boom rejects NaN damage")

		var owner_bike := BikeStub.new()
		_owner_bike = owner_bike
		owner_bike.name = "LeaOwner"
		owner_bike.set("player_id", "lea-owner")
		owner_bike.add_to_group("bike")
		holder.add_child(owner_bike)
		var victim := BikeStub.new()
		victim.name = "BoomVictim"
		victim.set("player_id", "lea-weapons-gate")
		victim.add_to_group("bike")
		holder.add_child(victim)
		var edge := BikeStub.new()
		edge.name = "BoomEdge"
		edge.set("player_id", "lea-weapons-gate")
		edge.position = Vector3(7.5, 0.0, 0.0)
		edge.add_to_group("bike")
		holder.add_child(edge)
		var outside := BikeStub.new()
		outside.name = "BoomOutside"
		outside.set("player_id", "lea-outside")
		outside.position = Vector3(7.51, 0.0, 0.0)
		outside.add_to_group("bike")
		holder.add_child(outside)
		var proxy := BikeStub.new()
		proxy.name = "BoomProxy"
		proxy.set("player_id", "remote-peer")
		proxy.add_to_group("bike")
		holder.add_child(proxy)
		var v_sink := LethalSink.new(); v_sink.name = "CombatController"; victim.add_child(v_sink)
		var e_sink := LethalSink.new(); e_sink.name = "CombatController"; edge.add_child(e_sink)
		var o_sink := LethalSink.new(); o_sink.name = "CombatController"; outside.add_child(o_sink)
		var p_sink := LethalSink.new(); p_sink.name = "CombatController"; proxy.add_child(p_sink)
		await process_frame

		var boom := Node3D.new()
		boom.set_script(boom_script)
		holder.add_child(boom)
		boom.call("setup", "lea-owner", owner_bike, Vector3.ZERO,
				105.0, "boom-tok", Color(1, 0.55, 0.88), 0.20, 99.0)
		_check(bool(boom.get("_armed")) and float(boom.get("blast_radius")) == 7.5,
				"unicorn boom arms and clamps an oversized radius to 7.5 m")
		_check(boom.is_in_group("meteor_strike"),
				"unicorn boom joins the meteor_strike telegraph group")
		var tele := holder.get_node_or_null("BoomTelegraph")
		_check(tele != null and tele.get_node_or_null("OuterRing") != null
				and tele.get_node_or_null("CountdownRing") != null
				and tele.get_node_or_null("RuneRing") != null,
				"unicorn boom spawns pulsing ground telegraph (OuterRing + CountdownRing + RuneRing)")
		boom.call("_detonate")
		_check(v_sink.calls.size() == 1
				and str(v_sink.calls[0].get("token", "")) == "boom-tok:vlea-weapons-gate",
				"UnicornBoom._detonate invokes the lethal resolver on the in-zone victim")
		_check(e_sink.calls.size() == 1, "unicorn boom kills a rider at exactly 7.5 m")
		_check(o_sink.calls.is_empty(), "unicorn boom spares a rider at 7.51 m")
		_check(p_sink.calls.is_empty(), "unicorn boom never mutates a remote proxy")
		if is_instance_valid(boom):
			boom.set_physics_process(false)
			boom.queue_free()
		await process_frame

		# ---- 3b. Real VehicleBody3D aerial flight + supernova landing bang + auto wing fold.
		var fx_arena := Node3D.new()
		fx_arena.name = "BoomFlightArena"
		holder.add_child(fx_arena)
		var flyer := VehicleBody3D.new()
		flyer.name = "LeaFlyer"
		flyer.set("player_id", "lea-flyer")
		flyer.collision_layer = 1
		flyer.collision_mask = 1
		flyer.position = Vector3(0.0, 0.6, 0.0)
		flyer.add_to_group("bike")
		fx_arena.add_child(flyer)
		var lea_vis_glb := (load("res://assets/Lea_Unicorn.glb") as PackedScene).instantiate() as Node3D
		lea_vis_glb.set_script(load("res://src/game/LeaVisual.gd"))
		lea_vis_glb.name = "Model"
		flyer.add_child(lea_vis_glb)

		var fly_target := BikeStub.new()
		fly_target.name = "BoomFlyTarget"
		fly_target.set("player_id", "lea-weapons-gate")
		fly_target.position = Vector3(0.0, 0.5, 18.0)
		fly_target.add_to_group("bike")
		fx_arena.add_child(fly_target)
		var fly_sink := LethalSink.new()
		fly_sink.name = "CombatController"
		fly_target.add_child(fly_sink)

		var debris := RigidBody3D.new()
		debris.name = "LooseDebris"
		debris.mass = 2.0
		debris.position = Vector3(3.0, 0.5, 18.0)
		fx_arena.add_child(debris)
		await process_frame

		var fly_boom := Node3D.new()
		fly_boom.set_script(boom_script)
		fx_arena.add_child(fly_boom)
		fly_boom.call("setup", "lea-flyer", flyer, Vector3(0.0, 0.0, 18.0),
				105.0, "boom-fly-tok", Color(1, 0.55, 0.88), 0.40, 7.5)
		_check(bool(lea_vis_glb.call("is_wings_open")),
				"UnicornBoom flight opens Lea's wings during takeoff/flight")
		var max_y := flyer.global_position.y
		for _f in range(60):
			await physics_frame
			max_y = maxf(max_y, flyer.global_position.y)
			if not is_instance_valid(fly_boom) or bool(fly_boom.get("_detonated")):
				break
		await physics_frame
		_check(max_y > 4.5, "UnicornBoom physically flies the unicorn through the air (max_y=%.2f)" % max_y)
		var land_xz := Vector2(flyer.global_position.x, flyer.global_position.z - 18.0).length()
		_check(land_xz < 0.25, "UnicornBoom lands the unicorn at target_pos (err=%.3f)" % land_xz)
		_check(flyer.global_transform.basis.y.y > 0.99 and not flyer.freeze and flyer.collision_layer == 1,
				"UnicornBoom restores upright unfrozen physics & collision after landing")
		_check(fly_sink.calls.size() == 1, "UnicornBoom damages/kills target at landing zone")
		_check(not bool(lea_vis_glb.call("is_wings_open"))
				and float(lea_vis_glb.get("_boom_cd")) == 0.0,
				"UnicornBoom touchdown automatically calls on_boom_land() to fold wings")
		_check(fx_arena.get_node_or_null("BoomShockwaveDome") != null
				and fx_arena.get_node_or_null("BoomRainbowShell") != null
				and fx_arena.get_node_or_null("BoomSkyPillar") != null
				and fx_arena.get_node_or_null("BoomCoreFlash") != null,
				"UnicornBoom supernova landing spawns Dome, RainbowShell, 20m SkyPillar & CoreFlash")
		_check(debris.linear_velocity.length() > 1.0,
				"UnicornBoom detonation applies radial impulse to nearby loose RigidBody3D debris")
		var max_scorch := int(vfx_script.get("MAX_SCORCH")) if vfx_script != null else 12
		var max_lights := int(vfx_script.get("MAX_IMPACT_LIGHTS")) if vfx_script != null else 8
		var scorch_n := get_nodes_in_group("vfx_scorch").size()
		var light_n := get_nodes_in_group("vfx_light").size()
		_check(scorch_n >= 1 and scorch_n <= max_scorch,
				"UnicornBoom spawns ground scorch respecting MAX_SCORCH (%d/%d)" % [scorch_n, max_scorch])
		_check(light_n <= max_lights,
				"UnicornBoom respects MAX_IMPACT_LIGHTS cap (%d/%d)" % [light_n, max_lights])
		var imp_light_ref: Node = fx_arena.get_node_or_null("BoomImpactLight")
		_check(imp_light_ref != null and imp_light_ref.is_in_group("vfx_light"),
				"UnicornBoom spawns BoomImpactLight in vfx_light group")
		if is_instance_valid(fly_boom):
			fly_boom.set_physics_process(false)
			fly_boom.queue_free()
		# Wait past the 0.72 s impact light tween after UnicornBoom is freed to prove
		# static cleanup lambdas execute with zero invalid-instance errors.
		for _w in range(55):
			await physics_frame
			if not is_instance_valid(imp_light_ref):
				break
		_check(not is_instance_valid(imp_light_ref),
				"BoomImpactLight cleans up & leaves vfx_light after UnicornBoom frees")

		# ---- 3c. Early abort/teardown mid-flight must safely unfreeze & fold wings.
		var abort_boom := Node3D.new()
		abort_boom.set_script(boom_script)
		fx_arena.add_child(abort_boom)
		abort_boom.call("setup", "lea-flyer", flyer, Vector3(0.0, 0.0, 32.0),
				105.0, "boom-abort-tok", Color(1, 0.55, 0.88), 1.5, 7.5)
		await physics_frame
		_check(flyer.freeze and bool(lea_vis_glb.call("is_wings_open")),
				"mid-flight freeze & open wings armed before abort")
		abort_boom.queue_free()
		await process_frame
		_check(not flyer.freeze and flyer.collision_layer == 1
				and not bool(lea_vis_glb.call("is_wings_open")),
				"mid-flight teardown safely restores physics, collision & folds wings")
		fx_arena.queue_free()
		await process_frame

	if aoe_script != null:
		_check(aoe_script.has_method("apply_blast") and aoe_script.has_method("apply_lethal_blast"),
				"CombatAoe keeps both blast resolvers")

	# ---- 4. SideCannons lea wiring.
	if cannons_script != null:
		var profiles: Variant = cannons_script.get("PROFILES")
		_check(profiles is Dictionary and (profiles as Dictionary).has("lea"),
				"SideCannons PROFILES has a 'lea' entry")
		var probe := Node3D.new()
		probe.set_script(cannons_script)
		probe.call("setup", probe, "lea-gate", Callable(), Color.WHITE, "lea")
		_check(str(probe.call("weapon_display_name", "primary")) == "HORN RAPID FIRE",
				"lea primary label is HORN RAPID FIRE")
		_check(str(probe.call("weapon_display_name", "rocket")) == "HORN BEAM",
				"lea rocket label is HORN BEAM")
		_check(str(probe.call("weapon_display_name", "meteor")) == "UNICORN BOOM",
				"lea meteor label is UNICORN BOOM")
		probe.free()

	# ---- 5. Reduced-motion safety: both visuals arm cleanly, no dome/pillar storm.
	var settings2: Node = root.get_node_or_null("Settings")
	if settings2 != null and beam_script != null and boom_script != null:
		settings2.call("set_value", "gameplay", "reduced_motion", true)
		var rm_holder := Node3D.new()
		rm_holder.name = "ReducedMotionHolder"
		holder.add_child(rm_holder)
		var b2 := Node3D.new()
		b2.set_script(beam_script)
		rm_holder.add_child(b2)
		b2.call("setup", "lea-owner", rm_holder, Vector3.ZERO, Vector3(0, 0, -1),
				38.0, 90.0, "reduced-beam", Color.WHITE)
		_check(not bool(b2.get("_inert")), "horn beam arms safely with reduced motion")
		if is_instance_valid(b2):
			b2.set_physics_process(false); b2.queue_free()
		var u2 := Node3D.new()
		u2.set_script(boom_script)
		rm_holder.add_child(u2)
		u2.call("setup", "lea-owner", _owner_bike, Vector3.ZERO,
				105.0, "reduced-boom", Color.WHITE, 0.2, 7.5)
		_check(bool(u2.get("_armed")), "unicorn boom arms safely with reduced motion")
		u2.call("_detonate")
		_check(rm_holder.get_node_or_null("BoomShockwaveDome") == null
				and rm_holder.get_node_or_null("BoomSkyPillar") == null
				and rm_holder.get_node_or_null("BoomCoreFlash") == null,
				"reduced motion suppresses UnicornBoom dome, sky-pillar & flash storm")
		if is_instance_valid(u2):
			u2.set_physics_process(false); u2.queue_free()
		rm_holder.queue_free()
		await process_frame

	# ---- 5. Building destruction, HornBeam chassis-height pierce & wide-building UnicornBoom ----
	var settings3 := root.get_node_or_null("Settings")
	if settings3 != null:
		settings3.call("set_value", "gameplay", "reduced_motion", false)
	var db_script := load("res://src/DestructibleBuilding.gd") as Script
	var combat_script := load("res://src/game/CombatController.gd") as Script
	var hb_script := load("res://src/game/HornBoltProjectile.gd") as Script
	if db_script != null and combat_script != null and hb_script != null:
		var db1 := StaticBody3D.new()
		db1.name = "VerifyLeaDestructible1"
		var col1 := CollisionShape3D.new()
		var box1 := BoxShape3D.new()
		box1.size = Vector3(7.2, 4.8, 5.6)
		col1.shape = box1
		db1.add_child(col1)
		db1.set_script(db_script)
		db1.position = Vector3(0.0, 2.4, -12.0)
		holder.add_child(db1)
		await process_frame

		var owner_bike := Node3D.new()
		owner_bike.add_to_group("bike")
		owner_bike.set("player_id", "p_lea_test")
		holder.add_child(owner_bike)

		var cc := Node3D.new()
		cc.set_script(combat_script)
		cc.set("bike", owner_bike)
		cc.set("practice_mode", true)
		holder.add_child(cc)
		await process_frame

		var hb: Node = hb_script.new()
		hb.set("owner_id", "p_lea_test")
		hb.set("damage", 50.0)
		hb.set("velocity", Vector3(0.0, 0.0, -40.0))
		cc.call("_on_projectile_hit", db1, Vector3(0.0, 1.0, -9.2), hb)
		_check(bool(db1.get("_intact")), "DestructibleBuilding survives first 50-dmg HornBolt hit")
		cc.call("_on_projectile_hit", db1, Vector3(0.0, 1.0, -9.2), hb)
		_check(not bool(db1.get("_intact")), "DestructibleBuilding collapses after >= 100 cumulative HornBolt damage")
		hb.free()

	if db_script != null and beam_script != null:
		var beam_owner := Node3D.new()
		beam_owner.add_to_group("bike")
		beam_owner.position = Vector3.ZERO
		holder.add_child(beam_owner)

		var target_bike := StaticBody3D.new()
		target_bike.add_to_group("bike")
		target_bike.set("player_id", "p_target_beam")
		var tcol := CollisionShape3D.new()
		var tbox := BoxShape3D.new()
		tbox.size = Vector3(1.2, 1.0, 1.6)
		tcol.shape = tbox
		target_bike.add_child(tcol)
		target_bike.position = Vector3(0.0, 0.55, 10.0)
		holder.add_child(target_bike)

		var db_beam := StaticBody3D.new()
		var dbcol := CollisionShape3D.new()
		var dbox := BoxShape3D.new()
		dbox.size = Vector3(7.2, 4.8, 5.6)
		dbcol.shape = dbox
		db_beam.add_child(dbcol)
		db_beam.set_script(db_script)
		db_beam.position = Vector3(0.0, 2.4, 18.0)
		holder.add_child(db_beam)

		var wall := StaticBody3D.new()
		var wcol := CollisionShape3D.new()
		var wbox := BoxShape3D.new()
		wbox.size = Vector3(10.0, 6.0, 2.0)
		wcol.shape = wbox
		wall.add_child(wcol)
		wall.position = Vector3(0.0, 3.0, 26.0)
		holder.add_child(wall)
		await process_frame

		var beam: Node = beam_script.new()
		holder.add_child(beam)
		beam.call("setup", "p_lea_test", beam_owner, Vector3(0.0, 0.62, 0.0), Vector3(0.0, 0.0, 1.0),
				60.0, 85.0, "tok_beam_bldg", Color(1.0, 0.45, 0.92), 4.5, "horn_beam")
		var max_beam_len := 0.0
		for _f in range(55):
			await physics_frame
			if is_instance_valid(beam):
				var bm := beam.get("_beam") as MeshInstance3D
				if bm != null:
					max_beam_len = maxf(max_beam_len, bm.scale.z)
			if not bool(db_beam.get("_intact")) and max_beam_len > 0.0:
				break
		_check(not bool(db_beam.get("_intact")), "HornBeam smashes DestructibleBuilding in its path")
		_check(max_beam_len >= 20.0 and max_beam_len <= 27.0, "HornBeam visual stops on solid wall behind building (len=%.1f)" % max_beam_len)

	if db_script != null and boom_script != null:
		var db_wide := StaticBody3D.new()
		var dwcol := CollisionShape3D.new()
		var dwbox := BoxShape3D.new()
		dwbox.size = Vector3(7.2, 4.8, 5.6)
		dwcol.shape = dwbox
		db_wide.add_child(dwcol)
		db_wide.set_script(db_script)
		db_wide.position = Vector3(8.5, 2.4, 0.0)
		holder.add_child(db_wide)

		var flyer2 := RigidBody3D.new()
		flyer2.collision_layer = 1
		flyer2.collision_mask = 1
		holder.add_child(flyer2)
		await process_frame

		var boom2: Node = boom_script.new()
		holder.add_child(boom2)
		boom2.call("setup", "p_lea_test", flyer2, Vector3.ZERO, 105.0,
				"tok_boom_wide", Color(1.0, 0.55, 0.88), 0.05, 7.5, "unicorn_boom")
		for _f in range(30):
			await physics_frame
			if not bool(db_wide.get("_intact")) and not flyer2.freeze:
				break
		_check(not bool(db_wide.get("_intact")), "UnicornBoom smashes wide DestructibleBuilding within 7.5m footprint")
		_check(not flyer2.freeze and flyer2.collision_layer == 1, "UnicornBoom restores flyer physics & collision after blast")

	holder.queue_free()
	await process_frame
	_restore()
	print("LEA WEAPONS VERIFY: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
