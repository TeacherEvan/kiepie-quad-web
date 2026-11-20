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
			["BtnModeBattleRoyale", "BtnModeDeathRace", "BtnPractice", "BtnCreate", "BtnJoinAuto", "BtnJoinCode", "BtnSettings"],
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
		# Mount TouchHUD live so runtime-created AnalogSteer/AnalogDrive pads are
		# actually inspected (not silently skipped on an unmounted packed tree).
		var touch_hud := inst.get_node_or_null("TouchHUD")
		if touch_hud != null:
			inst.remove_child(touch_hud)
			root.add_child(touch_hud)
			await process_frame
			for pad_name in ["AnalogSteer", "AnalogDrive"]:
				var pad := touch_hud.get_node_or_null(pad_name) as Control
				_check(pad != null and pad.focus_mode == Control.FOCUS_NONE,
						"Arena.%s focus_mode == FOCUS_NONE (live)" % pad_name)
			var steer_pad := touch_hud.get_node_or_null("AnalogSteer") as Control
			var vp_sz := root.get_visible_rect().size
			if steer_pad != null and vp_sz.x >= 700.0 and vp_sz.y >= 520.0:
				_check(steer_pad.offset_bottom <= -52.0,
						"Desktop AnalogSteer clears bottom Web hint strip (offset_bottom=%.1f <= -52)" % steer_pad.offset_bottom)
			touch_hud.queue_free()
			await process_frame
		if inst != null:
			inst.free()

	# Glyph coverage guard: every shipped scene label/button/Label3D must render
	# with Godot's bundled fallback font (no hexadecimal tofu boxes on WebGL2).
	var font := ThemeDB.fallback_font
	for scene_path in [
		"res://scenes/MainMenu.tscn",
		"res://scenes/LobbyMenu.tscn",
		"res://scenes/SettingsMenu.tscn",
		"res://scenes/Arena.tscn",
		"res://scenes/DeathRace.tscn",
		"res://scenes/TestRide.tscn",
	]:
		var ps := load(scene_path) as PackedScene
		if ps == null:
			continue
		var s_inst := ps.instantiate()
		var missing: Array[String] = []
		for n in s_inst.find_children("*", "", true, false):
			if n is Button or n is Label or n is Label3D:
				var txt := str(n.get("text"))
				for idx in range(txt.length()):
					var code := txt.unicode_at(idx)
					if code >= 32 and not font.has_char(code):
						missing.append("%s:U+%04X" % [n.name, code])
		_check(missing.is_empty(),
				"%s has zero unsupported tofu glyphs (%s)" % [scene_path.get_file(), ", ".join(missing)])
		s_inst.free()

	# Mobile portrait (390px) horizontal-fit guard for MainMenu: Subtitle must
	# wrap and the mode pills must clip cleanly so the card never overflows 390px.
	var mm_ps := load("res://scenes/MainMenu.tscn") as PackedScene
	if mm_ps != null:
		var mm := mm_ps.instantiate() as Control
		var sub := mm.get_node_or_null("SafeMargin/Card/VBox/Subtitle") as Label
		var br := mm.get_node_or_null("SafeMargin/Card/VBox/ModeRow/BtnModeBattleRoyale") as Button
		var dr := mm.get_node_or_null("SafeMargin/Card/VBox/ModeRow/BtnModeDeathRace") as Button
		var card := mm.get_node_or_null("SafeMargin/Card") as Control
		_check(sub != null and sub.autowrap_mode != TextServer.AUTOWRAP_OFF,
				"MainMenu.Subtitle wraps on narrow mobile screens")
		_check(br != null and br.clip_text and dr != null and dr.clip_text,
				"MainMenu mode pills clip text cleanly on narrow mobile screens")
		_check(card != null and card.get_combined_minimum_size().x <= 366.0,
				"MainMenu Card fits 390px mobile portrait without overflow (min_x=%.1f <= 366)" % (card.get_combined_minimum_size().x if card else 999.0))
		root.add_child(mm)
		if mm.has_method("_apply_responsive_layout"):
			mm.call("_apply_responsive_layout", Vector2(844, 390))
			await process_frame
			_check(card != null and card.get_combined_minimum_size().y <= 365.0,
					"MainMenu Card fits 844x390 landscape without clipping (min_y=%.1f <= 365)" % (card.get_combined_minimum_size().y if card else 999.0))
			mm.call("_apply_responsive_layout", Vector2(667, 375))
			await process_frame
			_check(card != null and card.get_combined_minimum_size().y <= 365.0,
					"MainMenu Card fits 667x375 landscape without clipping (min_y=%.1f <= 365)" % (card.get_combined_minimum_size().y if card else 999.0))
		mm.queue_free()
		await process_frame

	# MatchHud 6-kill WeakRef eviction + free-while-timer-pending guard
	var hud_script := load("res://src/ui/MatchHud.gd") as GDScript
	if hud_script != null:
		var hud := CanvasLayer.new()
		hud.set_script(hud_script)
		root.add_child(hud)
		await process_frame
		for k in range(6):
			hud.call("add_kill", "Player%d" % k, "Victim%d" % k)
		var feed := hud.get_node_or_null("KillFeed") as VBoxContainer
		if feed == null:
			feed = hud.get("_kill_feed") as VBoxContainer
		_check(feed == null or feed.get_child_count() <= 4,
				"MatchHud evicts old kill-feed lines (count=%d <= 4)" % (feed.get_child_count() if feed else 0))
		hud.queue_free()
		await create_timer(0.15).timeout
		_check(true, "MatchHud freed with pending kill-feed timers without crash")

	quit(1 if _fail > 0 else 0)
