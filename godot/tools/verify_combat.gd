extends SceneTree
## Offline gate: damage, death and random-point respawn of the local bike.

var _fail := 0


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		printerr("FAIL ", label)
		_fail += 1


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var match_state: Node = root.get_node("Match")
	match_state.call("apply_lobby", {"status": "playing", "settings": {"kill_target": 10, "respawn_delay": 0.15}})
	var holder := Node3D.new()
	root.add_child(holder)
	var bike_scene: PackedScene = load("res://scenes/KiepieBike.tscn")
	var bike := bike_scene.instantiate() as VehicleBody3D
	holder.add_child(bike)
	var combat := Node3D.new()
	combat.set_script(load("res://src/game/CombatController.gd"))
	bike.add_child(combat)
	combat.call("setup", bike)

	_check(float(combat.get("health")) == 100.0, "starts at 100 health")
	combat.call("take_damage", 30.0, "enemy-1", Vector3.ZERO)
	_check(float(combat.get("health")) == 70.0, "damage applied")
	combat.call("take_damage", 100.0, "enemy-2", Vector3.ZERO)
	_check(not bool(combat.get("alive")), "bike destroyed at zero health")
	_check(not bike.visible, "destroyed bike hidden")

	for i in range(20):
		await create_timer(0.2).timeout
		if bool(combat.get("alive")):
			break
	_check(bool(combat.get("alive")), "bike respawned after delay")
	_check(float(combat.get("health")) == 100.0, "health restored on respawn")
	_check(bike.visible, "bike visible again after respawn")

	# incoming enemy projectile must find the local bike via player_id
	var stub := GDScript.new()
	stub.source_code = "extends Node3D\nvar owner_id: String = ''\nvar token: String = ''\nvar damage: float = 30.0\n"
	stub.reload()
	var proj := Node3D.new()
	proj.set_script(stub)
	proj.set("owner_id", "enemy-9")
	proj.set("token", "enemy-token")
	proj.set("damage", 30.0)
	combat.set("_invuln_until", 0.0)  # respawn shield would block this probe
	combat.call("_on_projectile_hit", bike, Vector3.ZERO, proj)
	_check(float(combat.get("health")) == 70.0, "incoming shot damaged the local player")
	proj.queue_free()

	# --- P2-3a regression: non-positive / NaN damage is a no-op ---
	var h_before := float(combat.get("health"))
	combat.call("take_damage", -50.0, "enemy-neg", Vector3.ZERO)
	_check(float(combat.get("health")) == h_before, "take_damage(-50) leaves health unchanged")
	combat.call("take_damage", NAN, "enemy-nan", Vector3.ZERO)
	_check(float(combat.get("health")) == h_before, "take_damage(NAN) leaves health unchanged")

	# Rocket direct hit: 100% lethal, and it ignores shields / spawn invuln.
	combat.set("_shield_until", Time.get_ticks_msec() / 1000.0 + 10.0)
	combat.call("take_lethal_hit", "enemy-rocket", Vector3.ZERO, "rocket-token")
	_check(not bool(combat.get("alive")) and float(combat.get("health")) == 0.0,
			"take_lethal_hit is 100%% lethal even through an active shield")
	combat.call("reset_state")

	# F-08 regression: reset_state() after _die() must restore collision and clear active buffs
	combat.call("apply_pickup", "overdrive")
	combat.call("apply_pickup", "rapid")
	combat.call("apply_pickup", "shield")
	combat.set("_shield_until", 0.0)
	combat.set("_invuln_until", 0.0)
	combat.call("take_damage", 100.0, "enemy-3", Vector3.ZERO)
	_check(not bool(combat.get("alive")), "F-08 setup: bike dead before reset_state()")
	_check(bike.collision_layer == 0 and bike.collision_mask == 0,
			"F-08 setup: dead bike collision disabled")
	combat.set("_shield_until", Time.get_ticks_msec() / 1000.0 + 4.0)
	combat.call("reset_state")
	_check(bool(combat.get("alive")), "F-08: reset_state() restores alive")
	_check(bike.collision_layer == 1 and bike.collision_mask == 1,
			"F-08: reset_state() restores collision_layer == 1 and collision_mask == 1")
	_check(not bool(bike.get("overdrive_active")),
			"F-08: reset_state() clears bike.overdrive_active")
	_check(float(combat.get("_rapid_until")) == 0.0 and float(combat.get("_overdrive_until")) == 0.0
			and float(combat.get("_shield_until")) == 0.0,
			"F-08: reset_state() zeroes buff timers")

	# --- P0-2 regression: overlapping KT hitstop beats restore Engine.time_scale ---
	var KT := load("res://src/core/KiepieTime.gd")
	Engine.time_scale = 1.0
	KT.trigger_hitstop(root, 0.28, 0.060)
	KT.trigger_hitstop(root, 0.25, 0.055)
	await create_timer(0.12).timeout
	_check(Engine.time_scale == 1.0,
			"overlapping hitstops (kill cam + death) restore Engine.time_scale to 1.0 after 120 ms")
	KT.trigger_hitstop(root, 0.20, 0.04)
	KT.trigger_hitstop(root, 0.65, 0.20)
	await create_timer(0.08, true, false, true).timeout
	_check(is_equal_approx(Engine.time_scale, 0.65),
			"P1-7: expiring shorter deeper hitstop steps Engine.time_scale up to remaining lease (0.65, got %.2f)" % Engine.time_scale)
	KT.reset_hitstop()
	# Freeing CombatController mid-hitstop immediately restores 1.0.
	# P2-1 / BUG-5 regression: _pick_safe_spawn avoids enemy & active MeteorStrike
	var sp0 := Node3D.new()
	sp0.add_to_group("spawn_point")
	root.add_child(sp0)
	sp0.global_position = Vector3(0.0, 0.0, 0.0)
	var sp1 := Node3D.new()
	sp1.add_to_group("spawn_point")
	root.add_child(sp1)
	sp1.global_position = Vector3(40.0, 0.0, 40.0)
	sp1.rotation = Vector3(0.0, 0.75, 0.0)
	var meteor_hazard := Node3D.new()
	meteor_hazard.add_to_group("meteor_strike")
	root.add_child(meteor_hazard)
	meteor_hazard.global_position = Vector3(1.0, 0.0, 1.0)
	var meteor_picks := 0
	for _i in range(10):
		if combat.call("_pick_safe_spawn", [sp0, sp1]) == sp1:
			meteor_picks += 1
	_check(meteor_picks == 10, "P2-1/BUG-5: _pick_safe_spawn avoids active MeteorStrike at sp0 (10/10)")
	meteor_hazard.queue_free()
	await process_frame

	# Also verify enemy bike avoidance and inward-facing basis preservation.
	var enemy_bike := Node3D.new()
	enemy_bike.add_to_group("bike")
	root.add_child(enemy_bike)
	enemy_bike.global_position = Vector3(0.5, 0.0, 0.5)
	var enemy_picks := 0
	for _i in range(10):
		if combat.call("_pick_safe_spawn", [sp0, sp1]) == sp1:
			enemy_picks += 1
	_check(enemy_picks == 10, "P2-1/BUG-5: _pick_safe_spawn avoids enemy bike at sp0 (10/10)")
	sp0.queue_free()
	enemy_bike.queue_free()
	sp1.queue_free()

	# P1-4: dead local bike freezes so it never falls through the floor into the void
	combat.set("_invuln_until", 0.0)
	combat.call("take_damage", 200.0, "void-test", Vector3.ZERO)
	_check(bool(bike.get("freeze")), "P1-4: dead local bike sets freeze=true")
	for _f in range(60):
		await physics_frame
	_check(bike.global_position.y > -1.0, "P1-4: dead local bike stays above floor after 60 frames (y=%.2f)" % bike.global_position.y)
	combat.call("reset_state")
	_check(not bool(bike.get("freeze")), "P1-4: reset_state() unfreezes local bike")

	# P2-6: NaN hitstop scale is rejected safely
	KT.trigger_hitstop(root, NAN, 0.1)
	_check(is_equal_approx(Engine.time_scale, 1.0), "P2-6: KiepieTime.trigger_hitstop(NAN) leaves time_scale == 1.0")

	# Freeing CombatController mid-beat restores Engine.time_scale to 1.0.
	KT.trigger_hitstop(root, 0.25, 30.0)
	combat.call("queue_free")
	await process_frame
	await process_frame
	_check(Engine.time_scale == 1.0,
			"freeing CombatController mid-hitstop restores Engine.time_scale to 1.0")
	Engine.time_scale = 1.0
	bike.queue_free()
	holder.queue_free()
	quit(1 if _fail > 0 else 0)
