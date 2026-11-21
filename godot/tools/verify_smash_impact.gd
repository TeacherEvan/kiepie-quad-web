extends SceneTree

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail += 1
		print("  FAIL: %s" % msg)


## End-to-end impact test: teleport the bike onto the Workshop doorway axis,
## drive it into the facade under throttle, and assert the building smashes.
func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/TestRide.tscn")
	var root_node := scene.instantiate() as Node3D
	get_root().add_child(root_node)
	# wait one frame: children are not inside the tree (and global transforms are
	# invalid) until the tree flushes its enter-tree notifications
	await process_frame
	var bike := root_node.get_node("KiepieBike") as VehicleBody3D
	var workshop := root_node.get_node("Workshop") as StaticBody3D
	var wpos := workshop.global_position
	# direction from the Workshop toward the pad centre (its facade faces that way)
	var to_pad := Vector3(-wpos.x, 0.0, -wpos.z)
	if to_pad.length() < 0.001:
		to_pad = Vector3(0.0, 0.0, -1.0)
	to_pad = to_pad.normalized()
	# teleport the bike onto the doorway axis, nose aimed into the facade
	bike.global_position = wpos + to_pad * 5.5 + Vector3(0.0, 0.5, 0.0)
	var fwd := -to_pad
	bike.rotation = Vector3(0.0, atan2(fwd.x, fwd.z), 0.0)
	bike.linear_velocity = Vector3.ZERO
	bike.angular_velocity = Vector3.ZERO
	Input.action_press("move_forward")
	for i in range(300):
		# physics ticks, not render frames: throttle only applies per tick
		await physics_frame
	Input.action_release("move_forward")
	var intact = workshop.get("_intact")
	var up_after := bike.global_transform.basis.y.normalized().y
	var debris := 0
	for child in root_node.get_children():
		if child is RigidBody3D:
			debris += 1
	print("bike end pos=(%.2f, %.2f, %.2f) vel=(%.2f, %.2f, %.2f)" % [
		bike.global_position.x, bike.global_position.y, bike.global_position.z,
		bike.linear_velocity.x, bike.linear_velocity.y, bike.linear_velocity.z])
	print("Workshop _intact=%s" % intact)
	print("UP_Y_AFTER_SMASH: %.3f (expect > 0.80)" % up_after)
	print("DEBRIS: %d RigidBody3D children in root (1 is the bike; 14 new debris expected)" % debris)
	_check(intact == false, "Workshop _intact == false after impact")
	_check(debris >= 15, "debris >= 15 RigidBody3D children (got %d)" % debris)
	_check(up_after > 0.80, "up_after > 0.80 (got %.3f)" % up_after)
	root_node.free()
	print("SMASH_IMPACT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	quit(1 if _fail > 0 else 0)
