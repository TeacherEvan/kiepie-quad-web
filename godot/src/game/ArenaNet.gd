extends Node3D
## Bridges local bike/controls to Supabase Realtime and the remote bike proxies.

const REMOTE_BIKE := preload("res://src/game/NetworkedBike.gd")
const PROJECTILE := preload("res://src/game/Projectile.gd")
const BANANA := preload("res://src/game/BananaProjectile.gd")
const ROCKET := preload("res://src/game/RocketProjectile.gd")
const METEOR := preload("res://src/game/MeteorStrike.gd")
const SOUNDWAVE := preload("res://src/game/SoundWaveProjectile.gd")
const BOOMERANG := preload("res://src/game/BoomerangGuitar.gd")
const DEVIL_HAND := preload("res://src/game/DevilHandStrike.gd")
const HORN_BOLT := preload("res://src/game/HornBoltProjectile.gd")
const HORN_BEAM := preload("res://src/game/HornBeam.gd")
const UNICORN_BOOM := preload("res://src/game/UnicornBoom.gd")
const VFX := preload("res://src/game/VfxFactory.gd")
const KT := preload("res://src/core/KiepieTime.gd")
const SIDE_CANNONS := preload("res://src/game/SideCannons.gd")
const SEND_HZ := 15.0
const SPAWN_ORDER := [0, 4, 2, 6, 1, 5, 3, 7]

@export var local_bike_path: NodePath

var _remote: Dictionary = {}
var _send_accum := 0.0
var _streak := 0
# ------------------------------------------------------------------ hitstop ----

var _hitstop := false
var _shot_log: Dictionary = {}   # owner_id -> Array of msec timestamps (1 s, max 24)
var _rocket_last: Dictionary = {} # owner_id -> sec timestamp of last remote rocket
var _meteor_last: Dictionary = {} # owner_id -> sec timestamp of last remote meteor
var _seen_shot_tokens: Dictionary = {}  # token -> true (dedupes replayed "shot" broadcasts)
var _strike_log: Array = []             # global rocket/meteor strikes in the last second
const MAX_SEEN_SHOT_TOKENS := 256
const MAX_REMOTE_STRIKES_PER_S := 12
const REMOTE_ROCKET_MIN_S := 1.15
const REMOTE_METEOR_MIN_S := 5.5
var _state_tick := 0             # monotonic relay sequence for bike_state
var _death_gen: Dictionary = {}  # peer_id -> monotonic death generation for respawn timer
var _local_dmg_shown_at: Dictionary = {}  # victim_id -> sec timestamp of our attacker-side damage number
var _seen_kill_tokens: Dictionary = {}  # token -> true (dedupes replayed "kill" broadcasts)
var _victim_kill_at: Dictionary = {}    # victim_id -> sec timestamp of last processed "kill"
const MAX_SEEN_KILL_TOKENS := 128
const LOCAL_DMG_DEDUP_S := 0.28
const REMOTE_PROJ_POOL_SIZE := 32
var _remote_proj_pool: Array[Node3D] = []
var _remote_proj_idx := 0
var _spawn_applied := false


func _ready() -> void:
	_place_local_bike_at_roster_slot()
	_send_accum = 1.0 / SEND_HZ
	Supabase.broadcast_received.connect(_on_broadcast)
	Match.roster_changed.connect(_sync_roster)
	Match.roster_changed.connect(_on_roster_changed_for_spawn)
	_sync_roster()


func _on_roster_changed_for_spawn() -> void:
	## A client can become ready before its own roster row arrives. Re-run the
	## placement once the uid is present, but never after the match has started
	## (that would teleport a driving player back to a spawn point).
	if _spawn_applied:
		return
	if Match != null and Match.is_playing():
		_spawn_applied = true
		return
	var uids: Array = Match.players.keys() if Match != null else []
	if not uids.has(Supabase.user_id):
		return
	_place_local_bike_at_roster_slot()
	_spawn_applied = true


func _place_local_bike_at_roster_slot() -> void:
	if Match == null or Match.players.size() <= 1:
		return
	if not (Match.players as Dictionary).has(Supabase.user_id):
		return
	var bike := get_node_or_null(local_bike_path) as VehicleBody3D
	if bike == null:
		return
	var tree := get_tree()
	if tree == null:
		return
	var points := tree.get_nodes_in_group("spawn_point")
	if points.is_empty():
		return
	points.sort_custom(func(a: Node, b: Node) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	var uids: Array[String] = []
	for k in Match.players.keys():
		uids.append(str(k))
	uids.sort()
	var idx := maxi(0, uids.find(Supabase.user_id))
	var slot: int = SPAWN_ORDER[idx % SPAWN_ORDER.size()] % points.size()
	var sp := points[slot] as Node3D
	if sp == null:
		return
	var t := Transform3D(sp.global_transform.basis.orthonormalized(), sp.global_position + Vector3(0.0, 0.6, 0.0))
	if bike.has_method("set_spawn"):
		bike.call("set_spawn", t)
	bike.global_transform = t
	bike.linear_velocity = Vector3.ZERO
	bike.angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(bike.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, t)
	var cam := tree.get_first_node_in_group("camera_rig") as Node3D
	if cam != null:
		cam.global_position = t.origin - t.basis.z * 4.6 + Vector3(0.0, 1.9, 0.0)
		cam.look_at(t.origin + Vector3(0.0, 0.72, 0.0), Vector3.UP)


func _exit_tree() -> void:
	# A hitstop coroutine may still be awaiting when the arena unloads — never
	# leave Engine.time_scale stuck at the hitstop value (resets the gen so the
	# pending beat's timer cannot clobber the next scene).
	KT.reset_hitstop()
	_hitstop = false
	for p in _remote_proj_pool:
		if is_instance_valid(p):
			p.queue_free()
	_remote_proj_pool.clear()
	if Supabase != null and Supabase.broadcast_received.is_connected(_on_broadcast):
		Supabase.broadcast_received.disconnect(_on_broadcast)
	if Match != null and Match.roster_changed.is_connected(_sync_roster):
		Match.roster_changed.disconnect(_sync_roster)
	if Match != null and Match.roster_changed.is_connected(_on_roster_changed_for_spawn):
		Match.roster_changed.disconnect(_on_roster_changed_for_spawn)


func _process(delta: float) -> void:
	if not Match.is_playing():
		return
	_send_accum += delta
	if _send_accum >= 1.0 / SEND_HZ:
		_send_accum = 0.0
		_send_state()


func _send_state() -> void:
	var bike := get_node_or_null(local_bike_path) as Node3D
	# No visibility gate: dead bikes must keep broadcasting "d": true during
	# their respawn window so peers stop showing them and remote proxies enter
	# the respawn state instead of reappearing at the corpse position.
	if bike == null:
		return
	var q := Quaternion(bike.global_transform.basis.orthonormalized())
	var combat := get_tree().get_first_node_in_group("local_combat")
	Supabase.broadcast("state", {
		"id": Supabase.user_id,
		"p": [bike.global_position.x, bike.global_position.y, bike.global_position.z],
		"r": [q.x, q.y, q.z, q.w],
		"t": bool(bike.get("turbo_active")),
		"d": (combat == null or not bool(combat.get("alive"))),
		"n": _state_tick,
	})
	_state_tick += 1


func note_local_damage_shown(victim_id: String) -> void:
	## Called by local damage sources (projectiles, rockets, meteors, drums) the
	## moment they pop an attacker-side damage number. The echoed "hurt"
	## broadcast from the victim is then deduped for LOCAL_DMG_DEDUP_S.
	if victim_id == "":
		return
	_local_dmg_shown_at[victim_id] = Time.get_ticks_msec() / 1000.0


func _on_broadcast(event: String, payload: Variant) -> void:
	if not (payload is Dictionary):
		return
	var p := payload as Dictionary
	match event:
		"state":
			var id := str(p.get("id", ""))
			if id == "" or id == Supabase.user_id:
				return
			# Only roster members may own a proxy: departed or rogue peers cannot
			# inject unremovable ghost StaticBody3D colliders into the arena.
			if Match != null and not Match.players.is_empty() and not Match.players.has(id):
				return
			if not _remote.has(id):
				_create_remote(id)
			var rb: Node = _remote.get(id)
			if is_instance_valid(rb):
				rb.call("apply_state", p)
		"shot":
			_spawn_remote_shot(p)
		"kill":
			if Match != null and not Match.lobby.is_empty() and not Match.is_playing():
				return
			var killer := str(p.get("killer", ""))
			var victim := str(p.get("victim", ""))
			var token := str(p.get("token", ""))
			if victim == "" or token == "":
				return
			if (not Supabase.use_mock or Match.players.size() > 1) and not Match.players.is_empty() and not Match.players.has(victim):
				return
			if _seen_kill_tokens.has(token):
				return
			var kill_now := Time.get_ticks_msec() / 1000.0
			var min_kill_gap := maxf(0.5, Match.respawn_delay() * 0.5)
			if (kill_now - float(_victim_kill_at.get(victim, -10.0))) < min_kill_gap:
				return
			_seen_kill_tokens[token] = true
			while _seen_kill_tokens.size() > MAX_SEEN_KILL_TOKENS:
				_seen_kill_tokens.erase(_seen_kill_tokens.keys()[0])
			_victim_kill_at[victim] = kill_now
			var feed := get_tree().get_first_node_in_group("match_hud")
			# The victim broadcasts its death; only the killer's client awards
			# the point through the authoritative RPC (the server owns scores).
			if killer == Supabase.user_id and victim != Supabase.user_id and killer != "hazard-pit":
				_streak += 1
				Match.register_kill(victim, token)
				_play_sfx("kill")
				_do_hitstop()
				if _streak >= 3 and feed != null and feed.has_method("announce"):
					feed.call("announce", "RAMPAGE ×%d" % _streak)
			if victim == Supabase.user_id:
				_streak = 0
				_start_kill_cam(killer)
			if _remote.has(victim):
				_hide_remote_briefly(victim)
			if feed != null and feed.has_method("add_kill"):
				feed.call("add_kill", killer, victim)
		"hurt":
			# Victim-authoritative damage number. Exact post-mitigation damage,
			# shown on the victim's proxy for every peer — deduplicated against
			# our own attacker-side number when we were the shooter.
			var victim := str(p.get("victim", ""))
			var attacker := str(p.get("attacker", ""))
			var dmg := int(p.get("dmg", 0))
			if victim == "" or victim == Supabase.user_id or dmg < 1:
				return
			var rb: Node = _remote.get(victim)
			if rb == null or not is_instance_valid(rb) or not bool(rb.get("visible")):
				return
			var now := Time.get_ticks_msec() / 1000.0
			if now - float(_local_dmg_shown_at.get(victim, -10.0)) < LOCAL_DMG_DEDUP_S:
				return
			var col := Color(1.0, 0.88, 0.26) if attacker == Supabase.user_id else Color(1.0, 0.48, 0.22)
			var rb3d := rb as Node3D
			if rb3d == null:
				return
			VFX.damage_number(self, rb3d.global_position + Vector3(0.0, 0.65, 0.0), float(dmg), col)


func _play_sfx(name: String) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", name)


func _do_hitstop() -> void:
	if Settings.reduced_motion() or _hitstop:
		return
	_hitstop = true
	# Lease via the shared refcounted slow-mo coordinator (KiepieTime):
	# restore happens when the last beat ends, or on scene unload via
	# KT.reset_hitstop() — the kill cam and the death hitstop cannot clobber
	# each other or leave the engine slow-mo'd.
	KT.trigger_hitstop(get_tree(), 0.28, 0.060)
	await get_tree().create_timer(0.06, true, false, true).timeout
	if not is_instance_valid(self):
		return
	_hitstop = false


func _start_kill_cam(killer: String) -> void:
	var cam := get_tree().get_first_node_in_group("camera_rig")
	var target: Node = _remote.get(killer)
	if cam != null and target != null and is_instance_valid(target):
		cam.call("spectate", target, Match.respawn_delay())


func _hide_remote_briefly(id: String) -> void:
	var rb: Node = _remote.get(id)
	if rb == null or not is_instance_valid(rb):
		return
	var gen := int(_death_gen.get(id, 0)) + 1
	_death_gen[id] = gen
	if rb.has_method("mark_killed"):
		rb.call("mark_killed", 0.55)
	else:
		rb.call("set_respawning", true)
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(Match.respawn_delay() + 0.5).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if int(_death_gen.get(id, 0)) != gen:
		return
	if is_instance_valid(rb) and _remote.has(id):
		rb.call("set_respawning", false)


func _create_remote(id: String) -> void:
	var row: Dictionary = Match.players.get(id, {})
	if row.is_empty():
		row = {"display_name": "RIDER", "color": "#40c8ff"}
	var rb := (REMOTE_BIKE as GDScript).new() as StaticBody3D
	add_child(rb)
	rb.call("setup", id, str(row.get("display_name", "RIDER")),
			str(row.get("color", "#40c8ff")))
	_remote[id] = rb


func _spawn_remote_shot(p: Dictionary) -> void:
	if Match != null and not Match.lobby.is_empty() and not Match.is_playing():
		return
	var owner_id := str(p.get("id", ""))
	if owner_id == "" or owner_id == Supabase.user_id:
		return
	# Mirrors the "state" gate at _on_broadcast: a departed or rogue peer cannot
	# inject damaging shots just because it left an initialised proxy behind.
	if Match != null and not Match.players.is_empty() and not Match.players.has(owner_id):
		return
	var origin_a: Variant = p.get("o", null)
	var dir_a: Variant = p.get("d", null)
	# Socket payloads are untrusted: a short array would index out of bounds
	# and throw a script error on every malformed "shot" broadcast.
	if not (origin_a is Array) or not (dir_a is Array):
		return
	if (origin_a as Array).size() < 3 or (dir_a as Array).size() < 3:
		return
	var o := Vector3(float(origin_a[0]), float(origin_a[1]), float(origin_a[2]))
	var d := Vector3(float(dir_a[0]), float(dir_a[1]), float(dir_a[2]))
	# Socket payloads are untrusted: JSON "1e999" parses to float inf, which
	# sails straight through a zero-length guard.
	if not (is_finite(o.x) and is_finite(o.y) and is_finite(o.z)
			and is_finite(d.x) and is_finite(d.y) and is_finite(d.z)):
		return
	# shots leave the muzzle of a live bike (well, its ~4 m lag window); anything
	# parked further away or from an uninitialised / respawning peer is fabricated
	var sender: Node3D = _remote.get(owner_id)
	if sender == null or not is_instance_valid(sender) or not bool(sender.get("_initialised")) or bool(sender.get("is_respawning")):
		return
	if sender.global_position.distance_to(o) > 16.0:
		return
	if d.length_squared() < 1e-8:
		return
	if d.length() > 100.0:
		# absurd impulse: not a direction we are willing to simulate
		return
	# per-sender rate limit: 24 remote shots per second. Twin-barrel rapid fire
	# emits 2 shots every 0.09 s (~22/s) — the old 12/s cap silently dropped
	# legitimate tracers on fast fire. Still bounds any forged shot flood.
	var weapon_kind := str(p.get("w", "primary"))
	# Validate before logging: a junk packet must not consume a real shooter's
	# 24/s tracer window, and a replayed token must not consume it twice.
	if weapon_kind != "primary" and weapon_kind != "rocket" and weapon_kind != "meteor":
		return
	if not _claim_shot_token(str(p.get("token", ""))):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var window: Array = _shot_log.get(owner_id, [])
	var kept: Array = []
	for t in window:
		if now - float(t) < 1.0:
			kept.append(t)
	if kept.size() >= 24:
		return
	kept.append(now)
	_shot_log[owner_id] = kept
	if weapon_kind == "rocket":
		if now - float(_rocket_last.get(owner_id, -REMOTE_ROCKET_MIN_S)) < REMOTE_ROCKET_MIN_S:
			return
		_rocket_last[owner_id] = now
	elif weapon_kind == "meteor":
		if now - float(_meteor_last.get(owner_id, -REMOTE_METEOR_MIN_S)) < REMOTE_METEOR_MIN_S:
			return
		_meteor_last[owner_id] = now
	if weapon_kind != "primary":
		# Per-id limits cannot stop a forged id from multiplying strikes across
		# the roster. One global budget bounds damaging nodes regardless of id.
		var fresh_strikes: Array = []
		for t in _strike_log:
			if now - float(t) < 1.0:
				fresh_strikes.append(t)
		if fresh_strikes.size() >= MAX_REMOTE_STRIKES_PER_S:
			return
		fresh_strikes.append(now)
		_strike_log = fresh_strikes
	var roster_keys: Array = Match.players.keys() if Match != null else []
	var pref := ""
	if Match != null and Match.players.has(owner_id) and Match.players[owner_id] is Dictionary:
		pref = str((Match.players[owner_id] as Dictionary).get("vehicle", ""))
	var vehicle := VehicleRegistry.resolve_for_player(owner_id, roster_keys, pref)
	var pogo := VehicleRegistry.is_pogo(vehicle)
	var aston := VehicleRegistry.is_aston(vehicle)
	var evan := VehicleRegistry.is_evan(vehicle)
	var lea := VehicleRegistry.is_lea(vehicle)
	var combat := get_tree().get_first_node_in_group("local_combat")
	if weapon_kind == "rocket":
		# Match the shooter's launcher exactly: EVAN = boomerang guitar,
		# NARDUS = massive cigar, BIG-BEN = cash bag, Quad = finned rocket.
		# Wire kind stays "rocket" so PROTOCOL_VERSION is unchanged.
		var rocket_dmg := ROCKET.BLAST_DAMAGE
		var rocket := Node3D.new()
		rocket.set_script(HORN_BEAM if lea else (BOOMERANG if evan else ROCKET))
		add_child(rocket)
		var rocket_style := "horn_beam" if lea else ("boomerang" if evan else ("cigar" if pogo else ("cash_bag" if aston else "rocket")))
		var rocket_color := Color(0.40, 0.90, 1.0) if lea \
				else (Color(0.94, 0.06, 0.07) if evan else Color(1.0, 0.38, 0.10))
		rocket.setup(owner_id, _remote.get(owner_id), o, d, 38.0, rocket_dmg,
				str(p.get("token", "")), rocket_color, 4.5, rocket_style)
		if lea and combat != null and combat.has_method("_on_projectile_hit"):
			rocket.on_hit = Callable(combat, "_on_projectile_hit")
		return
	elif weapon_kind == "meteor":
		if d.length() > 65.0:
			return
		var target_pos := o + d
		var meteor_dmg := Match.damage() * 3.5
		var strike := Node3D.new()
		strike.set_script(UNICORN_BOOM if lea else (DEVIL_HAND if evan else METEOR))
		add_child(strike)
		var meteor_style := "unicorn_boom" if lea else ("devil_hand" if evan else ("cash_bag" if aston else ("meteor" if pogo else "lightning")))
		var strike_color := Color(1.0, 0.55, 0.88) if lea \
				else (Color(0.85, 0.06, 0.20) if evan else Color(1.0, 0.28, 0.06))
		strike.setup(owner_id, _remote.get(owner_id), target_pos, meteor_dmg,
				str(p.get("token", "")), strike_color, 2.0, 7.5, meteor_style)
		return
	var proj_script: GDScript = HORN_BOLT if lea else (SOUNDWAVE if evan else (BANANA if pogo else PROJECTILE))
	var dmg := Match.damage() * VehicleRegistry.damage_multiplier(vehicle)
	var shot_color := Color(1.0, 0.82, 0.28) if lea else (Color(1.0, 0.12, 0.28) if evan else (Color(1.0, 0.9, 0.25) if pogo else (Color(0.68, 1.0, 0.20) if aston else Color(1.0, 0.35, 0.25))))
	var proj := _acquire_remote_proj(proj_script)
	proj.setup(owner_id, _remote.get(owner_id), o, d, SIDE_CANNONS.SHOT_SPEED, dmg,
			str(p.get("token", "")), shot_color)
	if proj.has_method("set_visual_origin") and (lea or evan):
		var sender_model := sender.get_node_or_null("Model")
		if lea and sender_model != null and sender_model.has_method("get_horn_world_pos"):
			proj.call("set_visual_origin", sender_model.call("get_horn_world_pos") as Vector3)
		elif evan and sender_model != null and sender_model.has_method("get_guitar_world_pos"):
			proj.call("set_visual_origin", sender_model.call("get_guitar_world_pos") as Vector3)
	if combat != null and combat.has_method("_on_projectile_hit"):
		proj.on_hit = Callable(combat, "_on_projectile_hit")


func _claim_shot_token(token: String) -> bool:
	## Bounded replay dedup for socket "shot" broadcasts. Un-tokened legacy
	## packets pass through; Talo v1 cannot bind a token to an authenticated
	## sender, so this only stops verbatim replays, not id spoofing.
	if token == "":
		return true
	if _seen_shot_tokens.has(token):
		return false
	_seen_shot_tokens[token] = true
	if _seen_shot_tokens.size() > MAX_SEEN_SHOT_TOKENS:
		var keys := _seen_shot_tokens.keys()
		for k in keys.slice(0, 64):
			_seen_shot_tokens.erase(k)
	return true


func _acquire_remote_proj(proj_script: GDScript) -> Node3D:
	var slot := _acquire_remote_proj_raw(proj_script)
	# Never reuse a slot with the previous shot's callback or inert state.
	slot.set("on_hit", Callable())
	slot.visible = true
	slot.set_physics_process(true)
	return slot


func _acquire_remote_proj_raw(proj_script: GDScript) -> Node3D:
	var n := _remote_proj_pool.size()
	for offset in range(n):
		var idx := (_remote_proj_idx + offset) % n
		var cand: Node3D = _remote_proj_pool[idx]
		if is_instance_valid(cand) and cand.get_script() == proj_script and not cand.is_physics_processing():
			_remote_proj_idx = (idx + 1) % REMOTE_PROJ_POOL_SIZE
			return cand
	if _remote_proj_pool.size() < REMOTE_PROJ_POOL_SIZE:
		var p := Node3D.new()
		p.set_script(proj_script)
		p.set("pooled", true)
		add_child(p)
		_remote_proj_pool.append(p)
		return p
	for offset in range(n):
		var idx := (_remote_proj_idx + offset) % n
		var cand: Node3D = _remote_proj_pool[idx]
		if is_instance_valid(cand) and cand.get_script() == proj_script:
			_remote_proj_idx = (idx + 1) % REMOTE_PROJ_POOL_SIZE
			return cand
	var idx := _remote_proj_idx
	_remote_proj_idx = (idx + 1) % REMOTE_PROJ_POOL_SIZE
	var slot := _remote_proj_pool[idx]
	if is_instance_valid(slot):
		slot.queue_free()
	slot = Node3D.new()
	slot.set_script(proj_script)
	slot.set("pooled", true)
	add_child(slot)
	_remote_proj_pool[idx] = slot
	return slot


func _sync_roster() -> void:
	for uid in Match.players.keys():
		var id := str(uid)
		if id == Supabase.user_id:
			continue
		if not _remote.has(id):
			_create_remote(id)
		else:
			var rb: Node = _remote.get(id)
			var row: Dictionary = Match.players.get(uid, {})
			if is_instance_valid(rb) and rb.has_method("update_identity"):
				rb.call("update_identity", str(row.get("display_name", "RIDER")),
						str(row.get("color", "#40c8ff")))
	for id in _remote.keys():
		if not Match.players.has(id):
			var node: Node = _remote[id]
			if is_instance_valid(node):
				node.queue_free()
			_remote.erase(id)
			_shot_log.erase(id)
			_rocket_last.erase(id)
			_meteor_last.erase(id)
			_death_gen.erase(id)
			_local_dmg_shown_at.erase(id)
			_victim_kill_at.erase(id)
