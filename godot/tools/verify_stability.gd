extends SceneTree

## Rollover-immunity probe: full-throttle with alternating steering, then coast.
func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/TestRide.tscn")
	var root_node := scene.instantiate() as Node3D
	get_root().add_child(root_node)
	# wait one frame: children are not inside the tree until enter-tree notifications flush
	await process_frame
	var bike := root_node.get_node("KiepieBike") as VehicleBody3D
	var min_up := 1.0
	Input.action_press("move_forward")
	for i in range(360):
		if (i / 45) % 2 == 0:
			Input.action_press("steer_left")
			Input.action_release("steer_right")
		else:
			Input.action_press("steer_right")
			Input.action_release("steer_left")
		await process_frame
		min_up = minf(min_up, bike.global_transform.basis.y.normalized().y)
	Input.action_release("move_forward")
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	for i in range(120):
		await process_frame
		min_up = minf(min_up, bike.global_transform.basis.y.normalized().y)
	var final_up := bike.global_transform.basis.y.normalized().y
	print("STABILITY: min up.y = %.3f (expect > 0.80)" % min_up)
	print("STABILITY: final up.y = %.3f (expect > 0.95)" % final_up)
	if min_up > 0.80 and final_up > 0.95:
		print("STABILITY: PASS")
	else:
		print("STABILITY: FAIL")
	quit()
