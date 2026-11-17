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

	combat.queue_free()
	bike.queue_free()
	holder.queue_free()
	quit(1 if _fail > 0 else 0)
