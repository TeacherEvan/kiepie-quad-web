extends Node3D
## Player-side combat: health, death, respawn and cannon input. Attached as a
## child of the local KiepieBike instance. In the multiplayer arena it is
## match-gated; in practice mode (TestRide) it works standalone.

signal health_changed(current: float, maximum: float)
signal died(killer_id: String)
signal respawned()
signal hurt(amount: float, attacker_id: String)
signal pickup_collected(kind: String)
signal hit_confirmed()

const MAX_HEALTH := 100.0
const CANNON := preload("res://src/game/SideCannons.gd")
const VFX := preload("res://src/game/VfxFactory.gd")
const KT := preload("res://src/core/KiepieTime.gd")

@export var practice_mode := false

var bike: VehicleBody3D
var cannons: Node3D
var health := MAX_HEALTH
var alive := true
var killer_id := ""
var player_color := Color(1.0, 0.48, 0.12)

var _respawn_at := 0.0
var _invuln_until := 0.0
var _fx_holder: Node3D
var _last_hit_token := ""
var _rapid_until := 0.0
var _overdrive_until := 0.0
var _shield_until := 0.0
var _touch_ctrl: Node = null
var _touch_switch_connected := false


func _ready() -> void:
	add_to_group("local_combat")
	if bike == null and get_parent() is VehicleBody3D:
		setup(get_parent() as VehicleBody3D)


func setup(p_bike: VehicleBody3D) -> void:
	bike = p_bike
	player_color = Color.from_string(Settings.player_color(), Color(1.0, 0.48, 0.12))
	# Projectile hit attribution reads player_id from the collider; remote bikes
	# get theirs in NetworkedBike.setup, the local bike needs it here.
	bike.set("player_id", Supabase.user_id)
	cannons = Node3D.new()
	cannons.name = "SideCannons"
	cannons.set_script(CANNON)
	add_child(cannons)
	var profile := str(p_bike.get("vehicle_profile")) if "vehicle_profile" in p_bike else "bike"
	cannons.setup(bike, Supabase.user_id,
			Callable(self, "_on_projectile_hit"), player_color, profile)
	# Adding meshes/audio during the parent's setup phase is illegal in Godot
	# 4.3 - defer until the bike is fully in the tree.
	call_deferred("_setup_decorations")


func _physics_process(delta: float) -> void:
	if bike == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not alive:
		if now >= _respawn_at:
			_respawn()
		return
	if not practice_mode and not Match.is_playing():
		return

	if cannons != null:
		cannons.call("set_rapid", now < _rapid_until)
	var overdrive := now < _overdrive_until
	if bike != null and "overdrive_active" in bike:
		bike.set("overdrive_active", overdrive)

	var touch := _touch_overlay()
	if touch != null and not _touch_switch_connected and touch.has_signal("weapon_switch_requested"):
		touch.connect("weapon_switch_requested", _on_weapon_switch_requested)
		_touch_switch_connected = true
	var touch_active := touch != null and touch.has_method("is_overlay_active") \
			and bool(touch.call("is_overlay_active"))
	if touch_active:
		# Mobile firing is MANUAL: only the right pad's UP gesture (or a real
		# physical F on a desktop running the overlay) fires. Never read the
		# "fire" InputAction here — touch-to-mouse emulation presses
		# MOUSE_BUTTON_LEFT, which is bound to it and would free-fire constantly.
		var fire_held := touch.has_method("is_fire_held") and bool(touch.call("is_fire_held"))
		if cannons != null and (Input.is_physical_key_pressed(KEY_F) or fire_held):
			cannons.fire()
	elif Input.is_action_pressed("fire") and cannons != null:
		# Do not fire desktop weapons when clicking a HUD button with the mouse.
		var vp := get_viewport()
		var hovered := vp.gui_get_hovered_control() if vp != null else null
		if not (hovered is BaseButton and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
			cannons.fire()


func apply_pickup(kind: String) -> void:
	if not alive or (not practice_mode and not Match.is_playing()):
		return
	var now := Time.get_ticks_msec() / 1000.0
	match kind:
		"shield":
			_shield_until = now + 4.0
			VFX.shield_pulse(_fx_parent(), bike.global_position, Color(0.25, 0.85, 1.0))
		"rapid":
			_rapid_until = now + 8.0
		"repair":
			health = minf(MAX_HEALTH, health + 45.0)
			health_changed.emit(health, MAX_HEALTH)
		"overdrive":
			_overdrive_until = now + 8.0
			if bike != null and "overdrive_active" in bike:
				bike.set("overdrive_active", true)
	pickup_collected.emit(kind)
	_play_sfx("pickup")


func _play_sfx(name: String) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", name)


func _exit_tree() -> void:
	# Free of the hitstop leaves: force time_scale back to 1.0 so nothing
	# lingers after this tree unloads.
	KT.reset_hitstop()
	if Match != null and Match.self_respawn_at.is_connected(_on_server_respawn):
		Match.self_respawn_at.disconnect(_on_server_respawn)
	if _fx_holder != null and is_instance_valid(_fx_holder):
		_fx_holder.queue_free()
	_fx_holder = null


func take_damage(amount: float, attacker_id: String, point: Vector3, token: String = "",
		bypass_invuln: bool = false) -> void:
	# Non-positive / NaN damage: no health movement, no events, no death path.
	if not is_finite(amount) or amount <= 0.0:
		return
	# practice mode: cannons/drums/buildings fire and deal damage without an
	# arena lobby (the match gate is for network sync, not for offline play)
	if not alive or (not practice_mode and not Match.is_playing()):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not bypass_invuln and (now < _invuln_until or now < _shield_until):
		# Absorbed damage still needs a read — otherwise a shield looks broken.
		VFX.shield_block(_fx_parent(), point, Color(0.30, 0.88, 1.0))
		return
	_commit_hit(maxf(0.0, health - amount), amount, attacker_id, point, token,
			0.18, Color(1.0, 0.35, 0.3))


## Rocket direct hit: 100% lethal, ignores shield and spawn invulnerability.
## Displayed damage reads 100 (the whole health bar) rather than an oversized value.
func take_lethal_hit(attacker_id: String, point: Vector3, token: String = "") -> void:
	if not alive or (not practice_mode and not Match.is_playing()):
		return
	_commit_hit(0.0, MAX_HEALTH, attacker_id, point, token, 0.4,
			Color(1.0, 0.28, 0.18))


## Single commit point for ordinary and lethal hits. Keeping telemetry, VFX and
## the death/token path here prevents the two entry points from drifting again.
func _commit_hit(new_health: float, shown_amount: float, attacker_id: String,
		point: Vector3, token: String, shake: float, num_color: Color) -> void:
	health = new_health
	health_changed.emit(health, MAX_HEALTH)
	hurt.emit(shown_amount, attacker_id)
	# Victim-authoritative telemetry: peers render exact post-mitigation damage
	# numbers on the victim's proxy (validated by alias in TaloBackend).
	if not practice_mode:
		Supabase.broadcast("hurt", {
			"victim": Supabase.user_id,
			"attacker": attacker_id,
			"dmg": int(roundf(shown_amount)),
		})
	VFX.impact(_fx_parent(), point, player_color, Vector3.ZERO, "bike")
	VFX.damage_number(_fx_parent(), point, shown_amount, num_color)
	_play_sfx("impact")
	_shake(shake)
	if health <= 0.0:
		_last_hit_token = token
		_die(attacker_id)


func _die(by: String) -> void:
	alive = false
	# never name an attacker the lobby doesn't know: broadcasts relay unverified
	# wire strings verbatim, and every honest peer would score them
	var is_env := (by == "hazard-pit")
	var attributable := by
	var kill_tok := _last_hit_token
	if is_env:
		attributable = "hazard-pit"
		kill_tok = "env:hazard-pit:%d" % Time.get_ticks_msec()
	elif practice_mode or Match.players.is_empty() or Match.players.has(by):
		attributable = by
	else:
		attributable = ""
	killer_id = attributable
	died.emit(attributable)
	var v_prof := str(bike.get("vehicle_profile")) if "vehicle_profile" in bike else "bike"
	var is_pogo := v_prof == "pogo"
	VFX.dramatic_death_explosion(_fx_parent(), bike.global_position,
			bike.global_transform.basis, player_color, is_pogo, v_prof)
	_play_sfx("explosion")
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", "explosion", 2.5, 0.58)
	_shake(0.82)
	if not Settings.reduced_motion():
		Input.vibrate_handheld(35)
		# 55 ms death hitstop via the shared refcounted slow-mo coordinator:
		# overlapping kill-cam (ArenaNet) beats cannot leave it slow-mo'd.
		KT.trigger_hitstop(get_tree(), 0.25, 0.055)
	if not practice_mode:
		Supabase.broadcast("kill", {
			"killer": attributable,
			"victim": Supabase.user_id,
			"token": kill_tok,
			"at": Time.get_ticks_msec(),
		})
	bike.visible = false
	# A dead body left on layer 1 keeps eating live projectiles and blocking
	# bikes for the whole respawn window; disable collision & wheel forces BEFORE
	# freezing so VehicleBody3D never freezes while wheels intersect geometry.
	bike.collision_layer = 0
	bike.collision_mask = 0
	bike.set_physics_process(false)
	if "_wheels" in bike:
		var wheels_dict: Variant = bike.get("_wheels")
		if wheels_dict is Dictionary:
			for w in (wheels_dict as Dictionary).values():
				if w is VehicleWheel3D and is_instance_valid(w):
					(w as VehicleWheel3D).engine_force = 0.0
					(w as VehicleWheel3D).brake = 0.0
					(w as VehicleWheel3D).steering = 0.0
	bike.linear_velocity = Vector3.ZERO
	bike.angular_velocity = Vector3.ZERO
	if bike.get_rid().is_valid():
		PhysicsServer3D.body_set_state(bike.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(bike.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	bike.freeze = true
	var ep: Variant = bike.get("_engine_player")
	if ep is AudioStreamPlayer3D:
		(ep as AudioStreamPlayer3D).stream_paused = true
	_respawn_at = Time.get_ticks_msec() / 1000.0 + Match.respawn_delay()
	if not Match.self_respawn_at.is_connected(_on_server_respawn):
		Match.self_respawn_at.connect(_on_server_respawn, CONNECT_ONE_SHOT)


func _on_server_respawn(_seconds: float) -> void:
	# server confirms the delay; keep the local timer but never shorten it
	pass


func _respawn() -> void:
	# In Death Race, RaceTracker advances bike._spawn at every cleared checkpoint;
	# preserve that checkpoint transform instead of teleporting back to the start grid.
	var tree := get_tree()
	var in_race := tree != null and tree.get_first_node_in_group("race_tracker") != null
	var pos := Vector3(0.0, 0.6, 0.0)
	if in_race:
		var sp_xf: Variant = bike.get("_spawn")
		if sp_xf is Transform3D:
			pos = (sp_xf as Transform3D).origin
	else:
		var points := tree.get_nodes_in_group("spawn_point") if tree != null else []
		if not points.is_empty():
			var pick := _pick_safe_spawn(points)
			pos = pick.global_position + Vector3(0.0, 0.6, 0.0)
			var t := Transform3D(pick.global_transform.basis.orthonormalized(), pos)
			bike.set_spawn(t)
		elif practice_mode:
			pos = Vector3(0.0, 0.6, 0.0)
			bike.set_spawn(Transform3D(Basis.IDENTITY, pos))
		else:
			pos = Vector3(randf_range(-25.0, 25.0), 0.6, randf_range(-25.0, 25.0))
			bike.set_spawn(Transform3D(Basis.IDENTITY, pos))
	# reset_bike() zeroes wheel force/brake/steer, clears dodge state and pushes
	# the spawn transform into PhysicsServer3D — direct global_transform writes
	# get overwritten on the next physics sync step.
	# reset_bike() zeroes wheel force/brake/steer, clears dodge state, pushes
	# the spawn transform into PhysicsServer3D and snaps FollowCam. Keep
	# collision disabled until after unfreezing to avoid VehicleBody3D NaN.
	bike.collision_layer = 0
	bike.collision_mask = 0
	bike.reset_bike()
	bike.freeze = false
	var ep: Variant = bike.get("_engine_player")
	if ep is AudioStreamPlayer3D:
		(ep as AudioStreamPlayer3D).stream_paused = false
	bike.collision_layer = 1
	bike.collision_mask = 1
	bike.set_physics_process(true)
	bike.visible = true
	bike.call_deferred("_notify_camera_snap")
	health = MAX_HEALTH
	alive = true
	_invuln_until = Time.get_ticks_msec() / 1000.0 + 1.0
	health_changed.emit(health, MAX_HEALTH)
	VFX.shield_pulse(_fx_parent(), pos, player_color)
	_play_sfx("respawn")
	respawned.emit()


func _pick_safe_spawn(points: Array) -> Node3D:
	var tree := get_tree()
	var hazards: Array[Vector3] = []
	if tree != null:
		for b in tree.get_nodes_in_group("bike"):
			if b == bike or not is_instance_valid(b) or not (b is Node3D):
				continue
			var bn := b as Node3D
			if bn.visible and bn.get("is_respawning") != true:
				hazards.append(bn.global_position)
		for m in tree.get_nodes_in_group("meteor_strike"):
			if is_instance_valid(m) and m is Node3D:
				hazards.append((m as Node3D).global_position)
	var scored: Array = []
	var best_dist := -1.0
	for p in points:
		var sp := p as Node3D
		if sp == null:
			continue
		var min_d := 1e9
		for h in hazards:
			min_d = minf(min_d, sp.global_position.distance_to(h))
		if min_d > best_dist:
			best_dist = min_d
		scored.append({"sp": sp, "d": min_d})
	var top: Array[Node3D] = []
	for item in scored:
		if float(item["d"]) >= best_dist - 3.0:
			top.append(item["sp"] as Node3D)
	if top.is_empty():
		return points[0] as Node3D
	return top[randi_range(0, top.size() - 1)]


func reset_state() -> void:
	## Restores health/visibility when restarting TestRide manually (RestartBtn / R).
	if bike == null:
		return
	if Match.self_respawn_at.is_connected(_on_server_respawn):
		Match.self_respawn_at.disconnect(_on_server_respawn)
	bike.collision_layer = 0
	bike.collision_mask = 0
	_rapid_until = 0.0
	_overdrive_until = 0.0
	_shield_until = 0.0
	_last_hit_token = ""
	if cannons != null:
		cannons.call("set_rapid", false)
		if cannons.has_method("reset_cooldowns"):
			cannons.call("reset_cooldowns")
	if "overdrive_active" in bike:
		bike.set("overdrive_active", false)
	bike.freeze = false
	var ep: Variant = bike.get("_engine_player")
	if ep is AudioStreamPlayer3D:
		(ep as AudioStreamPlayer3D).stream_paused = false
	bike.collision_layer = 1
	bike.collision_mask = 1
	bike.set_physics_process(true)
	bike.visible = true
	bike.call_deferred("_notify_camera_snap")
	health = MAX_HEALTH
	alive = true
	_invuln_until = Time.get_ticks_msec() / 1000.0 + 0.5
	health_changed.emit(health, MAX_HEALTH)
	respawned.emit()


func _setup_decorations() -> void:
	if not is_instance_valid(bike):
		return
	VFX.prewarm(_fx_parent())
	VFX.underglow(bike, player_color)
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("start_engine"):
		var eng: Variant = sfx.call("start_engine", bike)
		if eng is AudioStreamPlayer3D and "_engine_player" in bike:
			bike.set("_engine_player", eng)


func _touch_overlay() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	if _touch_ctrl == null or not is_instance_valid(_touch_ctrl):
		_touch_ctrl = tree.get_first_node_in_group("touch_controls")
		_touch_switch_connected = false
	return _touch_ctrl


func _on_weapon_switch_requested() -> void:
	if not alive or (not practice_mode and not Match.is_playing()) or cannons == null:
		return
	if cannons.has_method("cycle_weapon"):
		cannons.call("cycle_weapon", 1)


func _unhandled_key_input(event: InputEvent) -> void:
	if not alive or cannons == null:
		return
	if not practice_mode and not Match.is_playing():
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		match k.physical_keycode:
			KEY_TAB, KEY_V:
				if cannons.has_method("cycle_weapon"):
					cannons.call("cycle_weapon", 1)
			KEY_1:
				if cannons.has_method("select_weapon"):
					cannons.call("select_weapon", "primary")
			KEY_2:
				if cannons.has_method("select_weapon"):
					cannons.call("select_weapon", "rocket")
			KEY_3:
				if cannons.has_method("select_weapon"):
					cannons.call("select_weapon", "meteor")


func _shake(amount: float) -> void:
	var cam := get_tree().get_first_node_in_group("camera_rig") if get_tree() != null else null
	if cam != null and cam.has_method("add_shake"):
		cam.call("add_shake", amount)


func _fx_parent() -> Node3D:
	var t := get_tree()
	if t == null:
		return null
	if t.current_scene is Node3D:
		return t.current_scene as Node3D
	if _fx_holder == null or not is_instance_valid(_fx_holder):
		_fx_holder = Node3D.new()
		t.root.add_child(_fx_holder)
	return _fx_holder


func _arena_net() -> Node:
	var tree := get_tree()
	if tree == null or not (tree.current_scene is Node):
		return null
	return tree.current_scene.get_node_or_null("ArenaNet")


func _note_local_damage_shown(target_id: String) -> void:
	## Tell ArenaNet we already popped a number for this victim locally so the
	## echoed victim-authoritative "hurt" broadcast doesn't double-spawn one.
	var net := _arena_net()
	if net != null and net.has_method("note_local_damage_shown"):
		net.call("note_local_damage_shown", target_id)


func _on_projectile_hit(collider: Object, point: Vector3, projectile: Node) -> void:
	if collider == null or projectile == null:
		return
	var owner_id := str(projectile.get("owner_id"))
	var token := str(projectile.get("token"))
	var target_id := ""
	if collider is Node and (collider as Node).is_in_group("bike"):
		target_id = str((collider as Node).get("player_id"))
	elif collider is Node and (collider as Node).is_in_group("hazard"):
		if (collider as Node).has_method("ignite"):
			(collider as Node).call("ignite", owner_id, token)
			_play_sfx("impact")
		if owner_id == Supabase.user_id or (practice_mode and (owner_id == "" or owner_id == str(bike.get("player_id")))):
			hit_confirmed.emit()
		return
	if target_id == "":
		return
	if owner_id == Supabase.user_id:
		# Our shot hit a remote bike: the victim applies damage locally and
		# broadcasts its death; ArenaNet then awards the point via the RPC.
		var incoming: Vector3 = Vector3(projectile.get("velocity")).normalized() \
				if projectile.get("velocity") != null else Vector3.ZERO
		VFX.impact(_fx_parent(), point, player_color, incoming, "metal")
		hit_confirmed.emit()
		VFX.damage_number(_fx_parent(), point + Vector3(0.0, 0.45, 0.0),
				float(projectile.get("damage")), Color(1.0, 0.88, 0.26))
		_note_local_damage_shown(target_id)
	elif target_id == Supabase.user_id:
		take_damage(float(projectile.get("damage")), owner_id, point, token)
