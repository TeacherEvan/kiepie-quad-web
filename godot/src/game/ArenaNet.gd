extends Node3D
## Bridges local bike/controls to Supabase Realtime and the remote bike proxies.

const REMOTE_BIKE := preload("res://src/game/NetworkedBike.gd")
const PROJECTILE := preload("res://src/game/Projectile.gd")
const BANANA := preload("res://src/game/BananaProjectile.gd")
const ROCKET := preload("res://src/game/RocketProjectile.gd")
const METEOR := preload("res://src/game/MeteorStrike.gd")
const VFX := preload("res://src/game/VfxFactory.gd")
const SEND_HZ := 15.0
const SPAWN_ORDER := [0, 4, 2, 6, 1, 5, 3, 7]

@export var local_bike_path: NodePath

var _remote: Dictionary = {}
var _send_accum := 0.0
var _streak := 0
var _hitstop := false
var _shot_log: Dictionary = {}   # owner_id -> Array of msec timestamps (1 s, max 24)
var _rocket_last: Dictionary = {} # owner_id -> sec timestamp of last remote rocket
var _meteor_last: Dictionary = {} # owner_id -> sec timestamp of last remote meteor
const REMOTE_ROCKET_MIN_S := 1.15
const REMOTE_METEOR_MIN_S := 5.5
var _state_tick := 0             # monotonic relay sequence for bike_state
var _death_gen: Dictionary = {}  # peer_id -> monotonic death generation for respawn timer
var _local_dmg_shown_at: Dictionary = {}  # victim_id -> sec timestamp of our attacker-side damage number
const LOCAL_DMG_DEDUP_S := 0.28


func _ready() -> void:
	_place_local_bike_at_roster_slot()
	_send_accum = 1.0 / SEND_HZ
	Supabase.broadcast_received.connect(_on_broadcast)
	Match.roster_changed.connect(_sync_roster)
	_sync_roster()


func _place_local_bike_at_roster_slot() -> void:
	if Match == null or Match.players.size() <= 1:
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
	# leave Engine.time_scale stuck at the 0.28 hitstop value.
	Engine.time_scale = 1.0
	_hitstop = false
	if Supabase != null and Supabase.broadcast_received.is_connected(_on_broadcast):
		Supabase.broadcast_received.disconnect(_on_broadcast)
	if Match != null and Match.roster_changed.is_connected(_sync_roster):
		Match.roster_changed.disconnect(_sync_roster)


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
	var q := Quaternion(bike.global_transform.basis)
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
			var killer := str(p.get("killer", ""))
			var victim := str(p.get("victim", ""))
			var token := str(p.get("token", ""))
			# The victim broadcasts its death; only the killer's client awards
			# the point through the authoritative RPC (the server owns scores).
			if killer == Supabase.user_id and victim != "" and victim != Supabase.user_id and token != "":
				_streak += 1
				Match.register_kill(victim, token)
				_play_sfx("kill")
				_do_hitstop()
				if _streak >= 3:
					var feed := get_tree().get_first_node_in_group("match_hud")
					if feed != null and feed.has_method("announce"):
						feed.call("announce", "RAMPAGE ×%d" % _streak)
			if victim == Supabase.user_id:
				_streak = 0
				_start_kill_cam(killer)
			if _remote.has(victim):
				_hide_remote_briefly(victim)
			var feed := get_tree().get_first_node_in_group("match_hud")
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
	var previous := Engine.time_scale
	Engine.time_scale = 0.28
	await get_tree().create_timer(0.06, true, false, true).timeout
	if not is_instance_valid(self):
		return
	Engine.time_scale = previous
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
	var owner_id := str(p.get("id", ""))
	if owner_id == "" or owner_id == Supabase.user_id:
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
	if sender.global_position.distance_to(o) > 5.0:
		return
	if d.length_squared() < 1e-8:
		return
	if d.length() > 100.0:
		# absurd impulse: not a direction we are willing to simulate
		return
	# per-sender rate limit: 24 remote shots per second. Twin-barrel rapid fire
	# emits 2 shots every 0.09 s (~22/s) — the old 12/s cap silently dropped
	# legitimate tracers on fast fire. Still bounds any forged shot flood.
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
	var weapon_kind := str(p.get("w", "primary"))
	if weapon_kind != "primary" and weapon_kind != "rocket" and weapon_kind != "meteor":
		return
	if weapon_kind == "rocket":
		if now - float(_rocket_last.get(owner_id, -REMOTE_ROCKET_MIN_S)) < REMOTE_ROCKET_MIN_S:
			return
		_rocket_last[owner_id] = now
	elif weapon_kind == "meteor":
		if now - float(_meteor_last.get(owner_id, -REMOTE_METEOR_MIN_S)) < REMOTE_METEOR_MIN_S:
			return
		_meteor_last[owner_id] = now
	var roster_keys: Array = Match.players.keys() if Match != null else []
	var vehicle := VehicleRegistry.for_player_in_roster(owner_id, roster_keys) if not roster_keys.is_empty() \
			else VehicleRegistry.for_player(owner_id)
	var pogo := VehicleRegistry.is_pogo(vehicle)
	var combat := get_tree().get_first_node_in_group("local_combat")
	if weapon_kind == "rocket":
		var rocket_dmg := Match.damage() * 2.0
		var rocket := Node3D.new()
		rocket.set_script(ROCKET)
		add_child(rocket)
		rocket.setup(owner_id, _remote.get(owner_id), o, d, 38.0, rocket_dmg,
				str(p.get("token", "")), Color(1.0, 0.38, 0.10), 4.5)
		return
	elif weapon_kind == "meteor":
		if d.length() > 65.0:
			return
		var target_pos := o + d
		var meteor_dmg := Match.damage() * 3.5
		var strike := Node3D.new()
		strike.set_script(METEOR)
		add_child(strike)
		strike.setup(owner_id, _remote.get(owner_id), target_pos, meteor_dmg,
				str(p.get("token", "")), Color(1.0, 0.28, 0.06), 2.0, 7.5)
		return
	var proj_script: GDScript = BANANA if pogo else PROJECTILE
	var dmg := Match.damage() * VehicleRegistry.damage_multiplier(vehicle)
	var shot_color := Color(1.0, 0.9, 0.25) if pogo else Color(1.0, 0.35, 0.25)
	var proj := Node3D.new()
	proj.set_script(proj_script)
	add_child(proj)
	# Keep in sync with SideCannons.SHOT_SPEED.
	proj.setup(owner_id, _remote.get(owner_id), o, d, 52.0, dmg,
			str(p.get("token", "")), shot_color)
	if combat != null and combat.has_method("_on_projectile_hit"):
		proj.on_hit = Callable(combat, "_on_projectile_hit")


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
