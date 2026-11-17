extends SceneTree
## Offline gate: settings defaults, persistence, quality presets and reset.

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
	var settings: Node = root.get_node("Settings")
	_check(str(settings.call("get_value", "gameplay", "display_name", "")) == "RIDER", "default display name")
	_check(float(settings.call("get_value", "video", "particles", 1.0)) == 1.0, "default particle multiplier")

	settings.call("set_value", "gameplay", "display_name", "TEST_RIDER")
	_check(str(settings.call("display_name")) == "TEST_RIDER", "set_value updates live value")
	var cfg := ConfigFile.new()
	_check(cfg.load("user://settings.cfg") == OK, "settings.cfg written")
	_check(str(cfg.get_value("gameplay", "display_name", "")) == "TEST_RIDER", "value persisted")

	settings.call("apply_quality", "low")
	_check(float(settings.call("get_value", "video", "particles", 0.0)) == 0.45, "low preset particle multiplier")
	_check(bool(settings.call("get_value", "video", "shadows", true)) == false, "low preset disables shadows")
	_check(str(settings.call("get_value", "video", "quality", "")) == "low", "quality key recorded")

	settings.call("reset_defaults")
	_check(str(settings.call("display_name")) == "RIDER", "reset defaults restores name")
	_check(float(settings.call("get_value", "video", "particles", 0.0)) == 1.0, "reset defaults restores particles")
	quit(1 if _fail > 0 else 0)
