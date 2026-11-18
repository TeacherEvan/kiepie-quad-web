extends SceneTree
## Offline gate: keyboard focus on navigation UI + reduced-motion helper.
## Touch-only gameplay buttons must stay FOCUS_NONE (see verify_touch.gd).

var _fail := 0


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		printerr("FAIL ", label)
		_fail += 1


func _check_scene(path: String, names: Array, expected: int) -> void:
	var ps := load(path) as PackedScene
	_check(ps != null, "scene loads: " + path.get_file())
	if ps == null:
		return
	# Instantiate WITHOUT adding to the tree: properties are materialised but
	# _ready never runs, so no lobby/network side effects. Packed-state inspection
	# cannot be used here - Godot omits properties equal to the class default.
	var inst := ps.instantiate()
	if inst == null:
		printerr("FAIL instantiate ", path)
		_fail += 1
		return
	var by_name := {}
	for b in inst.find_children("*", "Button", true, false):
		by_name[str((b as Node).name)] = b
	for n in names:
		var b := by_name.get(str(n)) as Button
		_check(b != null and b.focus_mode == expected,
				"%s.%s focus_mode == %d" % [path.get_file(), n, expected])
		if b != null and expected == Control.FOCUS_ALL:
			_check(b.get_theme_stylebox("focus") != null,
					"%s.%s has a visible focus stylebox" % [path.get_file(), n])
	inst.free()


func _initialize() -> void:
	await process_frame
	var settings := root.get_node("Settings")
	_check(settings != null and settings.has_method("reduced_motion"),
			"Settings.reduced_motion() available")

	if settings != null:
		# Mutate the in-memory config only - set_value() would persist to user://settings.cfg.
		var cfg: Dictionary = settings.get("data")
		var gameplay: Dictionary = cfg.get("gameplay", {})
		var before: Variant = gameplay.get("reduced_motion", false)
		gameplay["reduced_motion"] = true
		cfg["gameplay"] = gameplay
		settings.set("data", cfg)
		_check(bool(settings.call("reduced_motion")), "reduced_motion() reads the setting")
		_check(is_equal_approx(float(settings.call("shake_multiplier")), 0.0),
				"reduced motion zeroes camera shake")
		gameplay["reduced_motion"] = before
		cfg["gameplay"] = gameplay
		settings.set("data", cfg)

	# Menu / result navigation must be keyboard reachable.
	_check_scene("res://scenes/MainMenu.tscn",
			["BtnPractice", "BtnCreate", "BtnJoinAuto", "BtnJoinCode", "BtnSettings"],
			Control.FOCUS_ALL)
	_check_scene("res://scenes/LobbyMenu.tscn",
			["BtnLeave", "BtnCopy", "BtnStart", "BtnReady"], Control.FOCUS_ALL)
	_check_scene("res://scenes/SettingsMenu.tscn",
			["BtnBack", "BtnDefaults"], Control.FOCUS_ALL)

	# Arena: result buttons keyboard-reachable, driving buttons not focusable.
	var arena := load("res://scenes/Arena.tscn") as PackedScene
	_check(arena != null, "Arena scene loads")
	if arena != null:
		var inst := arena.instantiate()
		var by_name := {}
		if inst != null:
			for b in inst.find_children("*", "Button", true, false):
				by_name[str((b as Node).name)] = b
		for n in ["PlayAgainBtn", "LeaveBtn"]:
			var b := by_name.get(str(n)) as Button
			_check(b != null and b.focus_mode == Control.FOCUS_ALL,
					"Arena.%s focus_mode == FOCUS_ALL" % n)
		for n in ["BtnTouchToggle", "MenuBtn", "ScoreToggle"]:
			var b := by_name.get(str(n)) as Button
			_check(b != null and b.focus_mode == Control.FOCUS_NONE,
					"Arena.%s focus_mode == FOCUS_NONE" % n)
		for pad_name in ["AnalogSteer", "AnalogDrive"]:  # runtime-created; absent without _ready()
			var pad := inst.get_node_or_null("TouchHUD/" + pad_name) as Control
			if pad != null:
				_check(pad.focus_mode == Control.FOCUS_NONE,
						"Arena.%s focus_mode == FOCUS_NONE" % pad_name)
		if inst != null:
			inst.free()

	quit(1 if _fail > 0 else 0)
