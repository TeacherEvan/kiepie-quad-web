extends Node3D
## Player-side combat: health, death, respawn and cannon input. Attached as a
## child of the local KiepieBike instance in the multiplayer arena.

signal health_changed(current: float, maximum: float)
signal died(killer_id: String)
signal respawned()
signal heat_changed(value: float, locked: bool)
signal hurt(amount: float, attacker_id: String)
signal pickup_collected(kind: String)

const MAX_HEALTH := 100.0
const CANNON := preload("res://src/game/SideCannons.gd")
const VFX := preload("res://src/game/VfxFactory.gd")

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
var _base_power := 420.0
var _was_overheated := false


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
	cannons.setup(bike, Supabase.user_id,
			Callable(self, "_on_projectile_hit"), player_color)
	if cannons.has_signal("heat_changed"):
		cannons.heat_changed.connect(_on_heat_changed)
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
	if not Match.is_playing():
		return

	if cannons != null:
		cannons.call("set_rapid", now < _rapid_until)
	var power := _base_power * (1.35 if now < _overdrive_until else 1.0)
	bike.set("engine_power", power)

	if Input.is_action_just_pressed("fire") and cannons != null:
		cannons.fire()

	# tyre smoke while braking/handbraking at speed
	if Input.is_action_pressed("brake") and bike.linear_velocity.length() > 3.0:
		_smoke_accum += delta
		if _smoke_accum >= 0.06:
			_smoke_accum = 0.0
			for x in [-0.55, 0.55]:
				VFX.tire_smoke(_fx_parent(), bike.global_position + Vector3(x, 0.15, -0.6))


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
			if _flames() != null:
				_flames().set("emitting", true)
	pickup_collected.emit(kind)
	_play_sfx("pickup")


func _flames() -> Node:
	return bike.get_node_or_null("ExhaustFlames")


func _play_sfx(name: String) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", name)


func take_damage(amount: float, attacker_id: String, point: Vector3, token: String = "") -> void:
	if not alive or not Match.is_playing():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _invuln_until or now < _shield_until:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, MAX_HEALTH)
	hurt.emit(amount, attacker_id)
	VFX.impact(_fx_parent(), point, player_color)
	VFX.damage_number(_fx_parent(), point, amount, Color(1.0, 0.35, 0.3))
	_play_sfx("impact")
	_shake(0.18)
	if health <= 0.0:
		_last_hit_token = token
		_die(attacker_id)


func _die(by: String) -> void:
	alive = false
	killer_id = by
	died.emit(by)
	VFX.explosion(_fx_parent(), bike.global_position, player_color, 1.3)
	_play_sfx("explosion")
	_shake(0.55)
	Supabase.broadcast("kill", {
		"killer": by,
		"victim": Supabase.user_id,
		"token": _last_hit_token,
		"at": Time.get_ticks_msec(),
	})
	bike.visible = false
	bike.set_physics_process(false)
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
	else:
		pos = Vector3(RandomNumberGenerator.new().randf_range(-25, 25), 0.6,
				RandomNumberGenerator.new().randf_range(-25, 25))
	var t := Transform3D(bike.global_transform.basis, pos)
	bike.set_spawn(t)
	bike.global_transform = t
	bike.linear_velocity = Vector3.ZERO
	bike.angular_velocity = Vector3.ZERO
	bike.set_physics_process(true)
	bike.visible = true
	health = MAX_HEALTH
	alive = true
	_invuln_until = Time.get_ticks_msec() / 1000.0 + 1.0
	health_changed.emit(health, MAX_HEALTH)
	VFX.shield_pulse(_fx_parent(), pos, player_color)
	_play_sfx("respawn")
	respawned.emit()


func _setup_decorations() -> void:
	if not is_instance_valid(bike):
		return
	VFX.underglow(bike, player_color)
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("start_engine"):
		sfx.call("start_engine", bike)


func _on_heat_changed(value: float, locked: bool) -> void:
	if locked and not _was_overheated:
		_play_sfx("overheat")
	_was_overheated = locked
	heat_changed.emit(value, locked)


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
		return
	if target_id == "":
		return
	if owner_id == Supabase.user_id:
		# Our shot hit a remote bike: the victim applies damage locally and
		# broadcasts its death; ArenaNet then awards the point via the RPC.
		VFX.impact(_fx_parent(), point, player_color)
	elif target_id == Supabase.user_id:
		take_damage(float(projectile.get("damage")), owner_id, point, token)
