extends SceneTree
## Offline rollover-recovery gate. Locks the classic arcade dead end:
## a capsized quad used to sit on its roof until the player pressed R.
## With the righting steer in _integrate_forces, an inverted bike must
## barrel-roll back upright within the window, and an upright bike must
## be completely unaffected by the righting code path.

var _fail := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS ", label)
	else:
		printerr("FAIL ", label)
		_fail += 1

func _initialize() -> void:
	_run()

func _spawn_ride() -> Node3D:
	var scene := load("res://scenes/TestRide.tscn") as PackedScene
	var root := scene.instantiate() as Node3D
	get_root().add_child(root)
	return root

func _up_dot(bike: Node3D) -> float:
	return bike.global_transform.basis.y.normalized().dot(Vector3.UP)

func _run() -> void:
	await process_frame

	# --- inverted bike must recover ---
	var root := _spawn_ride()
	await process_frame
	var bike := root.get_node("KiepieBike") as VehicleBody3D
	var origin := bike.global_position
	bike.global_transform = Transform3D(Basis(Vector3(0.0, 0.0, 1.0), PI), origin)
	bike.linear_velocity = Vector3.ZERO
	bike.angular_velocity = Vector3.ZERO
	var start_dot := _up_dot(bike)
	_check(start_dot < 0.0, "test starts from a wheels-up pose (up.dot=%.2f)" % start_dot)
	var recovered := false
	var min_up := 1.0
	for i in range(900):
		await physics_frame
		var d := _up_dot(bike)
		min_up = minf(min_up, d)
		if d > 0.6:
			recovered = true
			break
	_check(recovered, "capsized bike rights itself (up.dot=%.2f after window)" % _up_dot(bike))
	root.queue_free()
	await process_frame

	# --- upright bike must be left alone ---
	var root2 := _spawn_ride()
	await process_frame
	var bike2 := root2.get_node("KiepieBike") as VehicleBody3D
	var min_up2 := 1.0
	for i in range(240):
		await physics_frame
		min_up2 = minf(min_up2, _up_dot(bike2))
	_check(min_up2 > 0.75, "upright bike is not disturbed by the righting code (min up=%.2f)" % min_up2)
	root2.queue_free()
	await process_frame

	print("ROLLOVER: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
