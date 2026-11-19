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
var _smoke_accum := 0.0
var _base_power := 210.0
var _touch_ctrl: Node = null
var _touch_switch_connected := false


func _ready() -> void:
	add_to_group("local_combat")
	if bike == null and get_parent() is VehicleBody3D:
		setup(get_parent() as VehicleBody3D)


func setup(p_bike: VehicleBody3D) -> void:
	bike = p_bike
	player_color = Color.html(Settings.player_color())
	# Projectile hit attribution reads player_id from the collider; remote bikes
	# get theirs in NetworkedBike.setup, the local bike needs it here.
	bike.set("player_id", Supabase.user_id)
	_base_power = float(bike.get("engine_power"))
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
	var power := _base_power * (1.35 if overdrive else 1.0)
	bike.set("engine_power", power)

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

	# tyre smoke while braking/handbraking at speed
	if Input.is_action_pressed("brake") and bike.linear_velocity.length() > 3.0:
		_smoke_accum += delta
		if _smoke_accum >= 0.06:
			_smoke_accum = 0.0
			var basis := bike.global_transform.basis
			for x in [-0.55, 0.55]:
				VFX.tire_smoke(_fx_parent(),
						bike.global_position + basis.x * x + Vector3(0.0, 0.15, 0.0) - basis.z * 0.6)


func apply_pickup(kind: String) -> void:
	if not alive:
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


func _flames() -> Node:
	return bike.get_node_or_null("ExhaustFlames")


func _play_sfx(name: String) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", name)


func take_damage(amount: float, attacker_id: String, point: Vector3, token: String = "") -> void:
	# practice mode: cannons/drums/buildings fire and deal damage without an
	# arena lobby (the match gate is for network sync, not for offline play)
	if not alive or (not practice_mode and not Match.is_playing()):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _invuln_until or now < _shield_until:
		# Absorbed damage still needs a read — otherwise a shield looks broken.
		VFX.shield_block(_fx_parent(), point, Color(0.30, 0.88, 1.0))
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, MAX_HEALTH)
	hurt.emit(amount, attacker_id)
	VFX.impact(_fx_parent(), point, player_color, Vector3.ZERO, "bike")
	VFX.damage_number(_fx_parent(), point, amount, Color(1.0, 0.35, 0.3))
	_play_sfx("impact")
	_shake(0.18)
	if health <= 0.0:
		_last_hit_token = token
		_die(attacker_id)


func _die(by: String) -> void:
	alive = false
	# never name an attacker the lobby doesn't know: broadcasts relay unverified
	# wire strings verbatim, and every honest peer would score them
	var attributable := by
	if practice_mode or Match.players.is_empty() or Match.players.has(by):
		attributable = by
	else:
		attributable = ""
	killer_id = attributable
	died.emit(attributable)
	VFX.explosion(_fx_parent(), bike.global_position, player_color, 1.3)
	_play_sfx("explosion")
	_shake(0.55)
	if not practice_mode:
		Supabase.broadcast("kill", {
			"killer": attributable,
			"victim": Supabase.user_id,
			"token": _last_hit_token,
			"at": Time.get_ticks_msec(),
		})
	bike.visible = false
	bike.set_physics_process(false)
	# A dead body left on layer 1 keeps eating live projectiles and blocking
	# bikes for the whole respawn window, though it is invisible and inert.
	bike.collision_layer = 0
	bike.collision_mask = 0
	_respawn_at = Time.get_ticks_msec() / 1000.0 + Match.respawn_delay()
	Match.self_respawn_at.connect(_on_server_respawn, CONNECT_ONE_SHOT)


func _on_server_respawn(_seconds: float) -> void:
	# server confirms the delay; keep the local timer but never shorten it
	pass


func _respawn() -> void:
	var points := get_tree().get_nodes_in_group("spawn_point")
	var pos := Vector3(0.0, 0.6, 0.0)
	if not points.is_empty():
		var pick: Node3D = points[RandomNumberGenerator.new().randi_range(0, points.size() - 1)] as Node3D
		pos = pick.global_position + Vector3(0.0, 0.6, 0.0)
	elif practice_mode:
		pos = Vector3(0.0, 0.6, 0.0)
	else:
		pos = Vector3(RandomNumberGenerator.new().randf_range(-25, 25), 0.6,
				RandomNumberGenerator.new().randf_range(-25, 25))
	var t := Transform3D(Basis.IDENTITY, pos)
	bike.set_spawn(t)
	# reset_bike() zeroes wheel force/brake/steer, clears dodge state and pushes
	# the spawn transform into PhysicsServer3D — direct global_transform writes
	# get overwritten on the next physics sync step.
	bike.reset_bike()
	bike.collision_layer = 1
	bike.collision_mask = 1
	bike.set_physics_process(true)
	bike.visible = true
	health = MAX_HEALTH
	alive = true
	_invuln_until = Time.get_ticks_msec() / 1000.0 + 1.0
	health_changed.emit(health, MAX_HEALTH)
	VFX.shield_pulse(_fx_parent(), pos, player_color)
	_play_sfx("respawn")
	respawned.emit()


func reset_state() -> void:
	## Restores health/visibility when restarting TestRide manually (RestartBtn / R).
	if bike == null:
		return
	if Match.self_respawn_at.is_connected(_on_server_respawn):
		Match.self_respawn_at.disconnect(_on_server_respawn)
	bike.collision_layer = 1
	bike.collision_mask = 1
	_rapid_until = 0.0
	_overdrive_until = 0.0
	_shield_until = 0.0
	if cannons != null:
		cannons.call("set_rapid", false)
	if "overdrive_active" in bike:
		bike.set("overdrive_active", false)
	bike.set("engine_power", _base_power)
	bike.set_physics_process(true)
	bike.visible = true
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
		sfx.call("start_engine", bike)


func _touch_overlay() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	if _touch_ctrl == null or not is_instance_valid(_touch_ctrl):
		_touch_ctrl = tree.get_first_node_in_group("touch_controls")
		_touch_switch_connected = false
	return _touch_ctrl


func _on_weapon_switch_requested() -> void:
	if not alive or cannons == null:
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
		if owner_id == Supabase.user_id:
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
	elif target_id == Supabase.user_id:
		take_damage(float(projectile.get("damage")), owner_id, point, token)
