extends SceneTree
## Offline gate: audio pack, pickups and chain-exploding fuel drums.

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
	var sfx := root.get_node_or_null("Sfx")
	_check(sfx != null, "Sfx autoload present")
	if sfx != null:
		var sample_count := int((sfx.get("SAMPLES") as Dictionary).size())
		# 9 since the dead overheat sample was removed (audit P3-25; the mechanic is gone).
		_check(sample_count == 10, "10 sound samples registered (got %d)" % sample_count)

	var arena_scene: PackedScene = load("res://scenes/Arena.tscn")
	_check(arena_scene != null, "Arena scene loads")
	if arena_scene == null:
		quit(1)
		return
	var match_state := root.get_node("Match")
	match_state.call("apply_lobby", {"status": "playing", "settings": {"kill_target": 10}})
	var arena := arena_scene.instantiate()
	root.add_child(arena)
	for i in range(4):
		await process_frame
	var pickups := arena.find_children("*", "Area3D", true, false).filter(func(n): return n.name.begins_with("Pickup"))
	_check(pickups.size() == 8, "8 pickups in arena (got %d)" % pickups.size())
	var drums := arena.get_tree().get_nodes_in_group("hazard")
	_check(drums.size() == 10, "10 fuel drums in arena (got %d)" % drums.size())

	var first: Node = arena.get_node_or_null("FuelDrum0")
	var neighbour: Node = arena.get_node_or_null("FuelDrum1")
	var distant: Node = arena.get_node_or_null("FuelDrum8")
	var bike: Node3D = arena.get_node_or_null("KiepieBike") as Node3D
	var combat: Node = bike.get_node_or_null("CombatController") if bike != null else null
	if combat != null:
		_check(str(bike.get("player_id")) != "", "local bike has player_id for hit attribution")
	if first != null and neighbour != null and distant != null:
		first.call("ignite", "test-shooter", "test-token")
		await create_timer(0.5).timeout  # chain timer is wall-clock, not frame-count
		_check(not is_instance_valid(first), "ignited drum destroyed")
		_check(not is_instance_valid(neighbour), "adjacent drum chained")
		_check(is_instance_valid(distant), "distant drum survived (chain terminates)")

	if combat != null and is_instance_valid(distant):
		distant.global_position = bike.global_position  # isolated drum on the player
		distant.call("ignite", "enemy-1", "enemy-token")
		for i in range(6):
			await process_frame
		_check(float(combat.get("health")) < 100.0, "drum blast damaged the player")

	arena.queue_free()
	quit(1 if _fail > 0 else 0)
