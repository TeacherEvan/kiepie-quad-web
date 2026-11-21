extends SceneTree

var _failures := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		push_error("FAIL: " + msg)
		_failures += 1

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/TestRide.tscn")
	var root_node := scene.instantiate() as Node3D
	get_root().add_child(root_node)
	var bike := root_node.get_node("KiepieBike") as VehicleBody3D
	var fl := bike.get_node("WheelFL")
	print("has is_in_contact FL: ", fl.has_method("is_in_contact"))
	print("wheel pos ", fl.position, " rest_len ", fl.wheel_rest_length,
			" travel ", fl.suspension_travel, " radius ", fl.wheel_radius)
	var min_up := 1.0
	Input.action_press("move_forward")
	for i in range(180):
		await physics_frame
		min_up = minf(min_up, bike.global_transform.basis.y.normalized().y)
		if i % 60 == 0:
			var contact_txt := ""
			if fl.has_method("is_in_contact"):
				contact_txt = "contact=%s" % fl.call("is_in_contact")
			print("t=%d pos=(%.2f,%.2f,%.2f) vel=(%.2f,%.2f,%.2f) %s" % [
				i, bike.global_position.x, bike.global_position.y, bike.global_position.z,
				bike.linear_velocity.x, bike.linear_velocity.y, bike.linear_velocity.z, contact_txt])
	print("MIN_UP_Y: %.3f (expect > 0.80)" % min_up)
	_check(min_up > 0.80, "bike stayed upright (min_up_y=%.3f)" % min_up)
	_check(bike.linear_velocity.length() > 5.0,
			"bike accelerated past 5 m/s (%.2f)" % bike.linear_velocity.length())
	_check(fl.has_method("is_in_contact") and bool(fl.call("is_in_contact")),
			"front-left wheel in contact at rest/after drive")
	quit(1 if _failures > 0 else 0)
