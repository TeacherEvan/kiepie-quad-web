extends SceneTree
## Gate: EVAN THE SKELETON's three bespoke weapons — the pink sound-wave primary,
## the returning boomerang guitar rocket, the ground devil-hand special, the
## shared lethal AOE resolver, and SideCannons' "evan" profile wiring.
##
## Fully offline: runs under KIEPIE_MOCK_BACKEND=1, never touches a live match.
## Tool scripts cannot name autoloads at compile time, so Settings/Supabase are
## fetched from root and driven through call()/get() only.

const SAV := "user://settings.cfg"
const BAK := "user://settings.cfg.evan-weapons-gate-backup"

const P_SOUNDWAVE := "res://src/game/SoundWaveProjectile.gd"
const P_BOOMERANG := "res://src/game/BoomerangGuitar.gd"
const P_DEVILHAND := "res://src/game/DevilHandStrike.gd"
const P_COMBAT_AOE := "res://src/game/CombatAoe.gd"
const P_SIDE_CANNONS := "res://src/game/SideCannons.gd"
const P_REGISTRY := "res://src/game/VehicleRegistry.gd"

var _fail := 0
var _boom_hits: Array = []


func _on_boom_hit(target: Node, _point: Vector3) -> void:
	_boom_hits.append(target)


var _had_cfg := false
var _prior_user_id: Variant
var _prior_reduced_motion: Variant


## Records lethal hits so the gate can prove apply_lethal_blast really fires.
class LethalSink extends Node:
	var calls: Array[Dictionary] = []
	func take_lethal_hit(attacker: String, point: Vector3, token: String) -> void:
		calls.append({"attacker": attacker, "point": point, "token": token})


class BikeStub extends Node3D:
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
	if settings != null and _prior_reduced_motion != null:
		settings.call("set_value", "gameplay", "reduced_motion", _prior_reduced_motion)
	var sb: Node = root.get_node_or_null("Supabase")
	if sb != null and _prior_user_id != null:
		sb.set("user_id", _prior_user_id)
	if _had_cfg:
		if DirAccess.copy_absolute(BAK, SAV) == OK:
			DirAccess.remove_absolute(BAK)
	elif FileAccess.file_exists(SAV):
		DirAccess.remove_absolute(SAV)


## Missing or unparseable scripts are reported as FAIL and skipped, never fatal.
func _load(path: String, label: String) -> GDScript:
	if not ResourceLoader.exists(path):
		_check(false, "%s loads" % label)
		return null
	var script := load(path) as GDScript
	# A parse-failed GDScript can still be returned as an object; can_instantiate()
	# is the reliable "actually usable" check.
	_check(script != null and script.can_instantiate(), "%s loads" % label)
	if script != null and not script.can_instantiate():
		return null
	return script


func _vec(value: Variant) -> Vector3:
	return (value as Vector3) if value is Vector3 else Vector3.ZERO


func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


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

	var settings: Node = root.get_node_or_null("Settings")
	if settings != null:
		_prior_reduced_motion = settings.call("get_value", "gameplay", "reduced_motion", false)

	var dh_probe: Node = null
	var soundwave := _load(P_SOUNDWAVE, "SoundWaveProjectile")
	var boomerang := _load(P_BOOMERANG, "BoomerangGuitar")
	var devilhand := _load(P_DEVILHAND, "DevilHandStrike")
	var combat_aoe := _load(P_COMBAT_AOE, "CombatAoe")
	var cannons_script := _load(P_SIDE_CANNONS, "SideCannons")

	var registry: GDScript = null
	if ResourceLoader.exists(P_REGISTRY):
		registry = load(P_REGISTRY) as GDScript

	# ---- throwaway hierarchy: nothing here is a live match, bike or backend.
	var holder := Node3D.new()
	holder.name = "EvanWeaponsGateHolder"
	root.add_child(holder)
	await process_frame
	var owner := Node3D.new()
	owner.name = "EvanWeaponOwner"
	owner.position = Vector3(0.0, 1.0, 0.0)
	holder.add_child(owner)
	await process_frame

	var origin := owner.global_position + Vector3(0.0, 0.6, 0.0)

	# ---- 1. SoundWaveProjectile: pink primary projectile.
	if soundwave != null:
		var sw := Node3D.new()
		sw.name = "SoundWaveProbe"
		sw.set_script(soundwave)
		holder.add_child(sw)
		# An unconfigured projectile self-recycles on its first physics tick —
		# hold physics until setup() has armed it.
		sw.set_physics_process(false)
		await process_frame
		_check(is_instance_valid(sw) and sw.has_method("setup"),
				"SoundWaveProjectile exposes setup()")
		sw.call("setup", "evan-gate", owner, origin, Vector3.RIGHT,
				26.0, 37.0, "evan-sound-token", Color(0.95, 0.10, 0.46))
		sw.set_physics_process(true)
		await physics_frame
		var sv: Vector3 = _vec(sw.get("velocity"))
		_check(_finite(sv) and sv.length_squared() > 0.0,
				"SoundWaveProjectile velocity is finite and non-zero after setup")
		_check(is_equal_approx(float(sw.get("damage")), 37.0),
				"SoundWaveProjectile propagates damage 37.0")
		_check(str(sw.get("token")) == "evan-sound-token",
				"SoundWaveProjectile propagates its shot token")
		_check(str(sw.get("owner_id")) == "evan-gate",
				"SoundWaveProjectile propagates owner_id")
		_check(sw.get("on_hit") is Callable,
				"SoundWaveProjectile exposes the on_hit callback slot")
		# Zero/Empty mutant: a degenerate direction must not poison velocity
		# with NaN or leave an active projectile pointing nowhere.
		var sw_zero := Node3D.new()
		sw_zero.set_script(soundwave)
		holder.add_child(sw_zero)
		sw_zero.set_physics_process(false)
		await process_frame
		sw_zero.call("setup", "evan-gate", owner, origin, Vector3.ZERO,
				26.0, 37.0, "evan-zero-token", Color(0.95, 0.10, 0.46))
		var zv: Vector3 = _vec(sw_zero.get("velocity"))
		_check(_finite(zv), "zero-direction setup leaves a finite velocity (no NaN)")
		sw.set_physics_process(false)

	# ---- 2. BoomerangGuitar: thrown guitar that comes back to the owner.
	if boomerang != null:
		var boom := Node3D.new()
		boom.name = "BoomerangGuitarProbe"
		boom.set_script(boomerang)
		holder.add_child(boom)
		boom.set_physics_process(false)
		await process_frame
		_check(is_instance_valid(boom) and boom.has_method("setup"),
				"BoomerangGuitar exposes setup()")
		boom.call("setup", "evan-gate", owner, origin, Vector3.RIGHT,
				18.0, 55.0, "evan-boom-token", Color(1.0, 0.20, 0.55), 4.5, "boomerang")
		boom.set_physics_process(true)
		await physics_frame
		var bv: Vector3 = _vec(boom.get("velocity"))
		_check(_finite(bv) and bv.length_squared() > 0.0,
				"BoomerangGuitar velocity is finite and non-zero after setup")
		_check(is_equal_approx(float(boom.get("damage")), 55.0),
				"BoomerangGuitar propagates damage 55.0")
		_check(str(boom.get("token")) == "evan-boom-token",
				"BoomerangGuitar propagates its shot token")
		_check(str(boom.get("owner_id")) == "evan-gate",
				"BoomerangGuitar propagates owner_id")
		_check(is_equal_approx(float(boom.get("blast_radius")), 4.5),
				"BoomerangGuitar carries the 4.5 m blast radius")

		# ~1.2 s of simulated flight: the guitar must turn back, not fly away
		# forever. Accept a reversed velocity, a shrinking distance from the
		# owner after the outward peak, or the comeback arresting its speed.
		var forward := Vector3.RIGHT
		var peak_dist := 0.0
		var saw_reverse := false
		var saw_return := false
		var started := Time.get_ticks_msec()
		for _f in range(120):
			await physics_frame
			if not is_instance_valid(boom):
				break
			var cur_vel: Vector3 = _vec(boom.get("velocity"))
			if cur_vel.length_squared() > 1.0e-6 and cur_vel.normalized().dot(forward) < -0.2:
				saw_reverse = true
			var dist := boom.global_position.distance_to(owner.global_position)
			peak_dist = maxf(peak_dist, dist)
			if peak_dist > 1.0 and dist < peak_dist - 0.6:
				saw_return = true
			if Time.get_ticks_msec() - started > 4000:
				break
		# Drag alone can bleed speed on a one-way flight; only an actual
		# reversal or a shrinking distance proves the return steering works.
		_check(saw_reverse or saw_return,
				"BoomerangGuitar reverses direction or returns within ~1.2 s (not merely slowed by drag)")
		if is_instance_valid(boom):
			boom.set_physics_process(false)

		# Verify BoomerangGuitar hides & restores owner's EvanVisual held guitar
		var boom_evan_glb: PackedScene = load("res://assets/Evan_Skeleton.glb")
		var evan_visual_script: GDScript = load("res://src/game/EvanVisual.gd")
		if boom_evan_glb != null and evan_visual_script != null:
			var evan_owner := Node3D.new()
			evan_owner.name = "EvanBoomOwner"
			holder.add_child(evan_owner)
			var evan_model := boom_evan_glb.instantiate() as Node3D
			evan_model.name = "Model"
			evan_model.set_script(evan_visual_script)
			evan_owner.add_child(evan_model)
			await process_frame
			var g_body := evan_model.find_child("GuitarBody", true, false) as Node3D
			var sync_boom := Node3D.new()
			sync_boom.set_script(boomerang)
			holder.add_child(sync_boom)
			sync_boom.set_physics_process(false)
			await process_frame
			sync_boom.call("setup", "evan-gate", evan_owner, origin, Vector3.RIGHT,
					18.0, 55.0, "evan-sync-token", Color(1.0, 0.20, 0.55), 4.5, "boomerang")
			_check(g_body != null and not g_body.visible,
					"BoomerangGuitar.setup hides owner's held GuitarBody")
			sync_boom.call("_finish", true)
			_check(g_body != null and g_body.visible,
					"BoomerangGuitar._finish restores owner's held GuitarBody")
			evan_owner.queue_free()
			await process_frame

		# A scenery-only contact must not emit the enemy "hit" confirmation.
		var scenery := Node3D.new()
		scenery.name = "Ground"
		holder.add_child(scenery)
		var contact_boom := Node3D.new()
		contact_boom.set_script(boomerang)
		holder.add_child(contact_boom)
		contact_boom.set_physics_process(false)
		await process_frame
		contact_boom.call("setup", "evan-gate", owner, origin, Vector3.RIGHT,
				18.0, 55.0, "evan-contact-token", Color(1.0, 0.20, 0.55), 4.5, "boomerang")
		_boom_hits.clear()
		contact_boom.connect("hit", _on_boom_hit)
		contact_boom.call("_on_contact", scenery, Vector3.ZERO, Vector3.UP)
		contact_boom.call("_finish")
		_check(_boom_hits.is_empty(), "scenery contact does not emit a boomerang enemy hit")

	# ---- 3. DevilHandStrike: ground hand instant-kill special.
	if devilhand != null:
		var dh := Node3D.new()
		dh.name = "DevilHandStrikeProbe"
		dh.set_script(devilhand)
		holder.add_child(dh)
		dh.set_physics_process(false)
		dh_probe = dh
		await process_frame
		_check(is_instance_valid(dh) and dh.has_method("setup"),
				"DevilHandStrike exposes setup()")
		var target := owner.global_position + Vector3(0.0, 0.0, 7.0)
		# 2.0 s fall: long enough that this gate never needs to wait for impact.
		dh.call("setup", "evan-gate", owner, target, 105.0, "evan-hand-token",
				Color(0.90, 0.05, 0.18), 2.0, 7.5, "devil_hand")
		dh.set_physics_process(true)
		await physics_frame
		_check(dh.is_in_group("meteor_strike"),
				"DevilHandStrike joins the meteor_strike group on setup")
		var tp: Vector3 = _vec(dh.get("target_pos"))
		_check(_finite(tp) and tp.distance_to(target) < 0.01,
				"DevilHandStrike propagates a finite target_pos")
		_check(is_equal_approx(float(dh.get("damage")), 105.0),
				"DevilHandStrike propagates damage 105.0")
		_check(str(dh.get("token")) == "evan-hand-token",
				"DevilHandStrike propagates its shot token")
		_check(str(dh.get("owner_id")) == "evan-gate",
				"DevilHandStrike propagates owner_id")
		_check(is_equal_approx(float(dh.get("blast_radius")), 7.5),
				"DevilHandStrike carries the 7.5 m blast radius")
		_check(dh.find_child("Veins", true, false) != null,
				"DevilHandStrike builds anatomical Veins group")
		var nail_count := 0
		for fi in range(1, 6):
			var fn := dh.find_child("Finger%d" % fi, true, false)
			if fn != null and fn.find_child("Fingernail", true, false) != null:
				nail_count += 1
		_check(nail_count == 5, "DevilHandStrike builds curved Fingernail on all 5 fingers (%d/5)" % nail_count)

		# Net-supplied instant-kill parameters must be sanitised (AUD P2).
		var dh_big := Node3D.new()
		dh_big.set_script(devilhand)
		holder.add_child(dh_big)
		dh_big.set_physics_process(false)
		await process_frame
		dh_big.call("setup", "evan-gate", owner, target, 105.0, "evan-big-token",
				Color(0.90, 0.05, 0.18), 2.0, 50.0, "devil_hand")
		_check(float(dh_big.get("blast_radius")) <= 7.5,
				"DevilHandStrike clamps an oversized blast radius to 7.5 m (%.2f)"
				% float(dh_big.get("blast_radius")))
		var dh_bad := Node3D.new()
		dh_bad.set_script(devilhand)
		holder.add_child(dh_bad)
		dh_bad.set_physics_process(false)
		await process_frame
		dh_bad.call("setup", "evan-gate", owner, target, NAN, "evan-nan-token",
				Color(0.90, 0.05, 0.18), 2.0, 7.5, "devil_hand")
		_check(not bool(dh_bad.get("_armed")) and dh_bad.is_queued_for_deletion(),
				"DevilHandStrike rejects non-finite damage and queues free")
		var dh_nan_pos := Node3D.new()
		dh_nan_pos.set_script(devilhand)
		holder.add_child(dh_nan_pos)
		dh_nan_pos.set_physics_process(false)
		await process_frame
		dh_nan_pos.call("setup", "evan-gate", owner, Vector3(NAN, 0.0, 0.0), 105.0, "evan-nanpos-token",
				Color(0.90, 0.05, 0.18), 2.0, 7.5, "devil_hand")
		_check(not bool(dh_nan_pos.get("_armed")) and dh_nan_pos.is_queued_for_deletion(),
				"DevilHandStrike rejects non-finite target_pos and queues free")
		dh.set_physics_process(false)

	# ---- 4. CombatAoe's shared resolver: old blast plus the new lethal version.
	if combat_aoe != null:
		_check(combat_aoe.has_method("apply_blast"),
				"CombatAoe.apply_blast still exists (static)")
		_check(combat_aoe.has_method("apply_lethal_blast"),
				"CombatAoe.apply_lethal_blast exists (static)")

		# Actually invoke it — existence alone would pass a no-op stub.
		var local_uid := str(sb.get("user_id"))
		var victim_id := local_uid if local_uid != "" else "evan-victim"
		var center := Vector3.ZERO
		var owner_bike := BikeStub.new()
		owner_bike.name = "OwnerBike"
		owner_bike.set("player_id", "evan-owner")
		owner_bike.add_to_group("bike")
		holder.add_child(owner_bike)
		var victim_bike := BikeStub.new()
		victim_bike.name = "VictimBike"
		victim_bike.set("player_id", victim_id)
		victim_bike.add_to_group("bike")
		holder.add_child(victim_bike)
		var far_bike := BikeStub.new()
		far_bike.name = "FarBike"
		far_bike.set("player_id", "evan-far")
		far_bike.position = Vector3(60.0, 0.0, 0.0)
		far_bike.add_to_group("bike")
		holder.add_child(far_bike)
		# Exact boundary: radius test is `<= 7.5`, so this rider must be killed
		# while one 0.01 m further out must survive (kills a `<` flip mutant).
		var edge_bike := BikeStub.new()
		edge_bike.name = "EdgeBike"
		edge_bike.set("player_id", victim_id)
		edge_bike.position = Vector3(7.5, 0.0, 0.0)
		edge_bike.add_to_group("bike")
		holder.add_child(edge_bike)
		var just_out_bike := BikeStub.new()
		just_out_bike.name = "JustOutBike"
		just_out_bike.set("player_id", "evan-just-out")
		just_out_bike.position = Vector3(7.51, 0.0, 0.0)
		just_out_bike.add_to_group("bike")
		holder.add_child(just_out_bike)
		var owner_sink := LethalSink.new()
		owner_sink.name = "CombatController"
		owner_bike.add_child(owner_sink)
		var victim_sink := LethalSink.new()
		victim_sink.name = "CombatController"
		victim_bike.add_child(victim_sink)
		var far_sink := LethalSink.new()
		far_sink.name = "CombatController"
		far_bike.add_child(far_sink)
		var edge_sink := LethalSink.new()
		edge_sink.name = "CombatController"
		edge_bike.add_child(edge_sink)
		var just_out_sink := LethalSink.new()
		just_out_sink.name = "CombatController"
		just_out_bike.add_child(just_out_sink)
		# A remote proxy that happens to expose take_lethal_hit must never be
		# mutated from the shooter's client (AUD P2 fail-closed guard).
		var proxy_bike := BikeStub.new()
		proxy_bike.name = "RemoteProxyBike"
		proxy_bike.set("player_id", "remote-peer")
		proxy_bike.add_to_group("bike")
		holder.add_child(proxy_bike)
		var proxy_sink := LethalSink.new()
		proxy_sink.name = "CombatController"
		proxy_bike.add_child(proxy_sink)
		var hit_confirm_stub := GDScript.new()
		hit_confirm_stub.source_code = "extends Node\nsignal hit_confirmed\nvar count := 0\nfunc _ready() -> void:\n\tconnect('hit_confirmed', func() -> void: count += 1)\n"
		hit_confirm_stub.reload()
		var local_combat_stub := Node.new()
		local_combat_stub.set_script(hit_confirm_stub)
		local_combat_stub.add_to_group("local_combat")
		holder.add_child(local_combat_stub)
		await process_frame
		combat_aoe.call("apply_lethal_blast", self, holder, center, 7.5,
				local_uid if local_uid != "" else "evan-gate", owner_bike, "lethal-tok", true)
		_check(int(local_combat_stub.get("count")) >= 1,
				"apply_lethal_blast emits hit_confirmed when owner catches enemy proxy")
		_check(victim_sink.calls.size() == 1,
				"apply_lethal_blast kills the in-zone victim (%d calls)" % victim_sink.calls.size())
		_check(victim_sink.calls.size() == 1
				and str(victim_sink.calls[0].get("token", "")) == "lethal-tok:v%s" % victim_id,
				"lethal hit uses the ':v<victim>' sub-token contract (saw %s, want %s)"
				% [str(victim_sink.calls[0].get("token", "")) if victim_sink.calls.size() > 0 else "<none>",
					"lethal-tok:v%s" % victim_id])
		_check(owner_sink.calls.is_empty(), "apply_lethal_blast skips the owner")
		_check(far_sink.calls.is_empty(), "apply_lethal_blast skips out-of-zone riders")
		_check(edge_sink.calls.size() == 1, "apply_lethal_blast kills a rider at exactly 7.5 m")
		_check(just_out_sink.calls.is_empty(), "apply_lethal_blast spares a rider at 7.51 m")
		_check(proxy_sink.calls.is_empty(), "apply_lethal_blast never mutates a remote proxy")

		# Prove DevilHandStrike actually calls the resolver on detonation.
		if dh_probe != null and is_instance_valid(dh_probe):
			dh_probe.call("_detonate")
			_check(victim_sink.calls.size() == 2
					and str(victim_sink.calls[1].get("token", "")) == "evan-hand-token:v%s" % victim_id,
					"DevilHandStrike._detonate() invokes the lethal resolver")
			_check(proxy_sink.calls.is_empty(), "DevilHandStrike detonation leaves remote proxies untouched")

	# ---- 5. SideCannons "evan" wiring + the three signature display names.
	if cannons_script != null:
		var profiles: Variant = cannons_script.get("PROFILES")
		_check(profiles is Dictionary and (profiles as Dictionary).has("evan"),
				"SideCannons PROFILES has an 'evan' entry")
		var probe := Node3D.new()
		probe.name = "EvanCannonProbe"
		probe.set_script(cannons_script)
		holder.add_child(probe)
		await process_frame
		_check(probe.has_method("setup"), "SideCannons exposes setup()")
		probe.call("setup", probe, "evan-gate", Callable(), Color.WHITE, "evan")
		_check(str(probe.get("weapon_profile")) == "evan",
				"SideCannons probe selects the evan weapon profile")
		_check(str(probe.call("weapon_display_name", "primary")) == "RIFF BLASTER",
				"Evan primary reads RIFF BLASTER")
		_check(str(probe.call("weapon_display_name", "rocket")) == "BOOMERANG GUITAR",
				"Evan rocket reads BOOMERANG GUITAR")
		_check(str(probe.call("weapon_display_name", "meteor")) == "DEVIL HAND",
				"Evan special reads DEVIL HAND")
		var prof: Variant = probe.get("_profile")
		if prof is Dictionary:
			var d := prof as Dictionary
			_check(is_equal_approx(float(d.get("cooldown", -1.0)), 0.22),
					"Evan profile cooldown is 0.22 s")
			_check(is_equal_approx(float(d.get("rapid_cooldown", -1.0)), 0.10),
					"Evan profile rapid cooldown is 0.10 s")
			_check(is_equal_approx(float(d.get("spread", -1.0)), 0.050),
					"Evan profile spread is 0.050")
			var expected_sfx := "fire"
			if registry != null:
				expected_sfx = str(registry.call("fire_sfx", &"EvanSkeleton"))
			_check(str(d.get("sfx", "")) == expected_sfx,
					"Evan profile SFX is '%s'" % expected_sfx)
		else:
			_check(false, "SideCannons _profile is a Dictionary")

		# A reused pool slot must not carry a stale hit callback (AUD P2).
		if soundwave != null:
			var fx := Node3D.new()
			holder.add_child(fx)
			var slot_a: Node = probe.call("_acquire_pooled_proj", soundwave, fx)
			slot_a.set_physics_process(false)
			slot_a.set("on_hit", Callable(probe, "weapon_display_name"))
			# Force the very next acquire to reuse this exact slot.
			var forced_pool: Array[Node3D] = []
			for _p in range(48):
				forced_pool.append(slot_a)
			probe.set("_proj_pool", forced_pool)
			probe.set("_proj_pool_idx", 0)
			var slot_b: Node = probe.call("_acquire_pooled_proj", soundwave, fx)
			slot_b.set_physics_process(false)
			var cb: Variant = slot_b.get("on_hit")
			var cb_valid := cb is Callable and (cb as Callable).is_valid()
			_check(slot_b == slot_a and not cb_valid,
					"pooled projectile slot clears a stale on_hit callback (same=%s cb=%s)" % [slot_b == slot_a, cb])

	# ---- 6. Reduced motion safety: spawning the pink projectile must not crash.
	if settings != null and soundwave != null:
		settings.call("set_value", "gameplay", "reduced_motion", true)
		await process_frame
		var rm := Node3D.new()
		rm.name = "ReducedMotionSoundWave"
		rm.set_script(soundwave)
		holder.add_child(rm)
		rm.set_physics_process(false)
		await process_frame
		rm.call("setup", "evan-gate-rm", owner, origin, Vector3.FORWARD,
				20.0, 12.0, "evan-rm-token", Color.PINK)
		rm.set_physics_process(true)
		for _f in range(3):
			await physics_frame
		var rmv: Vector3 = _vec(rm.get("velocity"))
		_check(is_instance_valid(rm) and _finite(rmv),
				"SoundWaveProjectile sets up safely with reduced_motion enabled")
		rm.set_physics_process(false)

	# ---- 5. Building destruction, guitar anchor height & wide-building AOE footprint ----
	var evan_glb_scene := load("res://assets/Evan_Skeleton.glb") as PackedScene
	var evan_vis_script := load("res://src/game/EvanVisual.gd") as Script
	if evan_glb_scene != null and evan_vis_script != null:
		var evan_model := evan_glb_scene.instantiate() as Node3D
		evan_model.set_script(evan_vis_script)
		holder.add_child(evan_model)
		await process_frame
		var gpos: Vector3 = evan_model.call("get_guitar_world_pos")
		_check(gpos.y > 0.80, "EvanVisual.get_guitar_world_pos() returns chest height (y=%.2f > 0.80)" % gpos.y)
		evan_model.queue_free()
		await process_frame

	var db_script := load("res://src/DestructibleBuilding.gd") as Script
	var combat_script := load("res://src/game/CombatController.gd") as Script
	var sw_script := load("res://src/game/SoundWaveProjectile.gd") as Script
	if db_script != null and combat_script != null and sw_script != null:
		var db1 := StaticBody3D.new()
		db1.name = "VerifyDestructible1"
		var col1 := CollisionShape3D.new()
		var box1 := BoxShape3D.new()
		box1.size = Vector3(7.2, 4.8, 5.6)
		col1.shape = box1
		db1.add_child(col1)
		db1.set_script(db_script)
		db1.position = Vector3(0.0, 2.4, -12.0)
		holder.add_child(db1)
		await process_frame

		var cc := Node3D.new()
		cc.set_script(combat_script)
		cc.set("bike", owner)
		cc.set("practice_mode", true)
		holder.add_child(cc)
		await process_frame

		var sw: Node = sw_script.new()
		sw.set("owner_id", "p_evan_test")
		sw.set("damage", 35.0)
		sw.set("velocity", Vector3(0.0, 0.0, -40.0))
		cc.call("_on_projectile_hit", db1, Vector3(0.0, 1.0, -9.2), sw)
		_check(bool(db1.get("_intact")), "DestructibleBuilding survives first 35-dmg SoundWave hit")
		cc.call("_on_projectile_hit", db1, Vector3(0.0, 1.0, -9.2), sw)
		cc.call("_on_projectile_hit", db1, Vector3(0.0, 1.0, -9.2), sw)
		_check(not bool(db1.get("_intact")), "DestructibleBuilding collapses after >= 100 cumulative SoundWave damage")
		sw.free()

	var boom_script_evan := load("res://src/game/BoomerangGuitar.gd") as Script
	if db_script != null and boom_script_evan != null:
		var db2 := StaticBody3D.new()
		db2.name = "VerifyDestructible2"
		var col2 := CollisionShape3D.new()
		var box2 := BoxShape3D.new()
		box2.size = Vector3(7.2, 4.8, 5.6)
		col2.shape = box2
		db2.add_child(col2)
		db2.set_script(db_script)
		db2.position = Vector3(0.0, 2.4, -10.0)
		holder.add_child(db2)
		await process_frame

		var bg: Node = boom_script_evan.new()
		holder.add_child(bg)
		bg.call("setup", "p_evan_test", owner, Vector3(0.0, 0.72, 0.0), Vector3(0.0, 0.0, -1.0),
				28.0, 60.0, "tok_boom_bldg", Color(1.0, 0.12, 0.28), 7.5, "boomerang")
		for _f in range(30):
			await physics_frame
			if not bool(db2.get("_intact")):
				break
		_check(not bool(db2.get("_intact")), "BoomerangGuitar smashes DestructibleBuilding in its path")
		if is_instance_valid(bg):
			bg.queue_free()

	var aoe_script := load("res://src/game/CombatAoe.gd") as Script
	if db_script != null and aoe_script != null:
		var db3 := StaticBody3D.new()
		db3.name = "VerifyDestructibleWide"
		var col3 := CollisionShape3D.new()
		var box3 := BoxShape3D.new()
		box3.size = Vector3(7.2, 4.8, 5.6)
		col3.shape = box3
		db3.add_child(col3)
		db3.set_script(db_script)
		db3.position = Vector3(8.5, 2.4, 0.0)
		holder.add_child(db3)
		await process_frame
		aoe_script.call("apply_lethal_blast", self, holder, Vector3.ZERO, 7.5, "p_evan_test", owner, "tok_aoe_wide", true)
		_check(not bool(db3.get("_intact")), "CombatAoe smashes wide DestructibleBuilding whose wall overlaps 7.5m blast")

	# ---- cleanup: detach physics first, then free the whole throwaway tree.
	for ch in holder.get_children():
		if ch is Node:
			ch.set_physics_process(false)
	holder.free()
	await process_frame

	_restore()
	print("EVAN WEAPONS VERIFY: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
