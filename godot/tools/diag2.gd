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
	for i in range(5):
		await process_frame
	var hud := root_node.get_node("HUD")
	var smashed_label := hud.get_node("Smashed") as Label
	print("hud ready: ", hud.is_node_ready(), " label starts: '", smashed_label.text, "'")
	_check(hud.is_node_ready(), "HUD is ready")
	_check(smashed_label != null, "HUD Smashed label exists")
	var prev_text := smashed_label.text if smashed_label else ""
	for name in ["Workshop", "Shed", "Store"]:
		var b := root_node.get_node(name)
		_check(b != null, "%s building exists" % name)
		b.smash()
		for j in range(3):
			await process_frame
		print("", name, " smashed -> label: '", smashed_label.text, "'")
		_check(smashed_label.text != prev_text, "HUD counter advanced after %s" % name)
		prev_text = smashed_label.text
	quit(1 if _failures > 0 else 0)
