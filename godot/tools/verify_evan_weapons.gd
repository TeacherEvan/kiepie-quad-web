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
		var saw_arrest := false
		var started := Time.get_ticks_msec()
		for _f in range(120):
			await physics_frame
			if not is_instance_valid(boom):
				break
			var cur_vel: Vector3 = _vec(boom.get("velocity"))
			if cur_vel.length_squared() > 1.0e-6 and cur_vel.normalized().dot(forward) < -0.2:
				saw_reverse = true
			# A return curve that bleeds off its outbound speed has engaged the
			# comeback even before the direction vector fully flips.
			if cur_vel.length() < 18.0 * 0.3 and peak_dist > 3.0:
				saw_arrest = true
			var dist := boom.global_position.distance_to(owner.global_position)
			peak_dist = maxf(peak_dist, dist)
			if peak_dist > 1.0 and dist < peak_dist - 0.6:
				saw_return = true
			if Time.get_ticks_msec() - started > 4000:
				break
		_check(saw_reverse or saw_return or saw_arrest,
				"BoomerangGuitar turns back / arrests its flight within ~1.2 s (does not fly away forever)")
		if is_instance_valid(boom):
			boom.set_physics_process(false)

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
		var owner_sink := LethalSink.new()
		owner_sink.name = "CombatController"
		owner_bike.add_child(owner_sink)
		var victim_sink := LethalSink.new()
		victim_sink.name = "CombatController"
		victim_bike.add_child(victim_sink)
		var far_sink := LethalSink.new()
		far_sink.name = "CombatController"
		far_bike.add_child(far_sink)
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
		await process_frame
		combat_aoe.call("apply_lethal_blast", self, holder, center, 7.5,
				local_uid if local_uid != "" else "evan-gate", owner_bike, "lethal-tok", true)
		_check(victim_sink.calls.size() == 1,
				"apply_lethal_blast kills the in-zone victim (%d calls)" % victim_sink.calls.size())
		_check(victim_sink.calls.size() == 1
				and str(victim_sink.calls[0].get("token", "")) == "lethal-tok:v%s" % victim_id,
				"lethal hit uses the ':v<victim>' sub-token contract (saw %s, want %s)"
				% [str(victim_sink.calls[0].get("token", "")) if victim_sink.calls.size() > 0 else "<none>",
					"lethal-tok:v%s" % victim_id])
		_check(owner_sink.calls.is_empty(), "apply_lethal_blast skips the owner")
		_check(far_sink.calls.is_empty(), "apply_lethal_blast skips out-of-zone riders")
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

	# ---- cleanup: detach physics first, then free the whole throwaway tree.
	for ch in holder.get_children():
		if ch is Node:
			ch.set_physics_process(false)
	holder.free()
	await process_frame

	_restore()
	print("EVAN WEAPONS VERIFY: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
