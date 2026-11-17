extends Node3D
## Bridges local bike/controls to Supabase Realtime and the remote bike proxies.

const REMOTE_BIKE := preload("res://src/game/NetworkedBike.gd")
const PROJECTILE := preload("res://src/game/Projectile.gd")
const SEND_HZ := 15.0

@export var local_bike_path: NodePath

var _remote: Dictionary = {}
var _send_accum := 0.0
var _streak := 0
var _hitstop := false


func _ready() -> void:
	Supabase.broadcast_received.connect(_on_broadcast)
	Match.roster_changed.connect(_sync_roster)
	_sync_roster()


func _exit_tree() -> void:
	# A hitstop coroutine may still be awaiting when the arena unloads — never
	# leave Engine.time_scale stuck at the 0.28 hitstop value.
	Engine.time_scale = 1.0
	_hitstop = false


func _process(delta: float) -> void:
	if not Match.is_playing():
		return
	_send_accum += delta
	if _send_accum >= 1.0 / SEND_HZ:
		_send_accum = 0.0
		_send_state()


func _send_state() -> void:
	var bike := get_node_or_null(local_bike_path) as Node3D
	if bike == null or not bike.visible:
		return
	var q := Quaternion(bike.global_transform.basis)
	var combat := get_tree().get_first_node_in_group("local_combat")
	Supabase.broadcast("state", {
		"id": Supabase.user_id,
		"p": [bike.global_position.x, bike.global_position.y, bike.global_position.z],
		"r": [q.x, q.y, q.z, q.w],
		"t": bool(bike.get("turbo_active")),
		"d": (combat == null or not bool(combat.get("alive"))),
	})


func _on_broadcast(event: String, payload: Variant) -> void:
	if not (payload is Dictionary):
		return
	var p := payload as Dictionary
	match event:
		"state":
			var id := str(p.get("id", ""))
			if id == "" or id == Supabase.user_id:
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
			if killer == Supabase.user_id and victim != "" and token != "":
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
	rb.call("set_respawning", true)
	await get_tree().create_timer(Match.respawn_delay() + 0.5).timeout
	if is_instance_valid(rb) and _remote.has(id):
		rb.call("set_respawning", false)


func _create_remote(id: String) -> void:
	var row: Dictionary = Match.players.get(id, {})
	if row.is_empty():
		row = {"display_name": "RIDER", "color": "#40c8ff"}
	var rb := Node3D.new()
	rb.set_script(REMOTE_BIKE)
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
	if not (origin_a is Array) or not (dir_a is Array):
		return
	var o := Vector3(float(origin_a[0]), float(origin_a[1]), float(origin_a[2]))
	var d := Vector3(float(dir_a[0]), float(dir_a[1]), float(dir_a[2]))
	var proj := Node3D.new()
	proj.set_script(PROJECTILE)
	add_child(proj)
	proj.setup(owner_id, _remote.get(owner_id), o, d, 46.0, Match.damage(),
			str(p.get("token", "")), Color(1.0, 0.35, 0.25))
	var combat := get_tree().get_first_node_in_group("local_combat")
	if combat != null and combat.has_method("_on_projectile_hit"):
		proj.on_hit = Callable(combat, "_on_projectile_hit")


func _sync_roster() -> void:
	for uid in Match.players.keys():
		var id := str(uid)
		if id != Supabase.user_id and not _remote.has(id):
			_create_remote(id)
	for id in _remote.keys():
		if not Match.players.has(id):
			var node: Node = _remote[id]
			if is_instance_valid(node):
				node.queue_free()
			_remote.erase(id)
