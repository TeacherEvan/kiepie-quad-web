extends SceneTree
## Gate: Battle Royale & Death Race game modes, Death Race circuit (loops,
## hazard pits, ramps, pickups, ordered checkpoints, finish line & lap counter),
## Victory Splash video, Rocket Launcher (5s CD, 2x dmg, 4.5m blast) &
## Meteor Shower (6s CD, practical ground aim reticle, 2s sky-fall delay,
## massive AOE damage), HUD reload bar, and mobile right-analog-back switching.

var _fail := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS ", label)
	else:
		printerr("FAIL ", label)
		_fail += 1


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var sb: Node = root.get_node_or_null("Supabase")
	if sb == null or not bool(sb.get("use_mock")):
		printerr("LIVE BACKEND — refusing to run gate (KIEPIE_MOCK_BACKEND=1 not effective)")
		quit(2)
		return
	var match_node: Node = root.get_node("Match")
	var prev_lobby: Dictionary = (match_node.get("lobby") as Dictionary).duplicate(true)
	var prev_players: Dictionary = (match_node.get("players") as Dictionary).duplicate(true)

	# ---- 1. Dashboard (MainMenu) Battle Royale (default) & Death Race mode selection
	var main_packed := load("res://scenes/MainMenu.tscn") as PackedScene
	_check(main_packed != null, "MainMenu.tscn loads")
	if main_packed != null:
		var main_menu := main_packed.instantiate() as Control
		root.add_child(main_menu)
		await process_frame
		var btn_br := main_menu.get_node_or_null("SafeMargin/Card/VBox/ModeRow/BtnModeBattleRoyale") as Button
		var btn_dr := main_menu.get_node_or_null("SafeMargin/Card/VBox/ModeRow/BtnModeDeathRace") as Button
		var btn_prac := main_menu.get_node_or_null("SafeMargin/Card/VBox/BtnPractice") as Button
		_check(btn_br != null and btn_dr != null, "Dashboard displays Battle Royale & Death Race mode buttons")
		_check(str(main_menu.get("selected_game_mode")) == "battle_royale",
				"Battle Royale is the default game mode on the Dashboard")
		if btn_dr != null:
			btn_dr.pressed.emit()
			await process_frame
			_check(str(main_menu.get("selected_game_mode")) == "death_race",
					"Clicking Death Race switches Dashboard mode to death_race")
			_check(btn_prac != null and btn_prac.text.find("DEATH RACE") >= 0,
					"Practice button updates for Death Race (%s)" % (btn_prac.text if btn_prac else "null"))
		if btn_br != null:
			btn_br.pressed.emit()
			await process_frame
			_check(str(main_menu.get("selected_game_mode")) == "battle_royale",
					"Clicking Battle Royale switches Dashboard mode back to battle_royale")
		main_menu.free()

	# ---- 2. Victory Splash video asset exists in web-assets/ outside godot/
	var victory_mp4 := ProjectSettings.globalize_path("res://../web-assets/kiepie-victory-splash.mp4")
	_check(FileAccess.file_exists(victory_mp4), "web-assets/kiepie-victory-splash.mp4 exists")

	# ---- 3. DeathRace.tscn circuit: loops, pits, ramps, pickups, checkpoints, finish line & lap counter
	match_node.call("apply_lobby", {
		"id": "dr-1",
		"host_id": "mock-host",
		"status": "playing",
		"settings": {"game_mode": "death_race", "lap_target": 2, "damage": 30, "respawn_delay": 1.0},
	})
	match_node.set("players", {
		"mock-host": {"user_id": "mock-host", "display_name": "Host", "color": "#ff7a1a", "score": 0},
	})

	var dr_packed := load("res://scenes/DeathRace.tscn") as PackedScene
	_check(dr_packed != null, "DeathRace.tscn loads")
	if dr_packed == null:
		quit(1)
		return
	var dr := dr_packed.instantiate() as Node3D
	root.add_child(dr)
	for _i in range(4):
		await physics_frame
		await process_frame

	var bike := dr.get_node_or_null("KiepieBike") as VehicleBody3D
	var combat := dr.get_node_or_null("KiepieBike/CombatController")
	var cannons := combat.get("cannons") as Node3D if combat != null else null
	var tracker := dr.get_node_or_null("RaceTracker")
	var hud := dr.get_node_or_null("HUD") as CanvasLayer
	var touch_hud := dr.get_node_or_null("TouchHUD") as CanvasLayer

	_check(dr.get_node_or_null("CircuitTrack") != null, "DeathRace has CircuitTrack with turns & pit lane")
	_check(dr.get_node_or_null("FinishLine") != null, "DeathRace has FinishLine gantry")
	_check(dr.get_node_or_null("Checkpoint0") != null and dr.get_node_or_null("Checkpoint1") != null
			and dr.get_node_or_null("Checkpoint2") != null and dr.get_node_or_null("Checkpoint3") != null,
			"DeathRace has 4 ordered Checkpoints (Checkpoint0..3)")
	_check(dr.get_node_or_null("TrackLoop0/LoopZone") != null and dr.get_node_or_null("TrackLoop1/LoopZone") != null,
			"DeathRace has 2 360-degree Stunt Loops with LoopZone centripetal adhesion")
	_check(dr.get_node_or_null("HazardPit0") != null and dr.get_node_or_null("HazardPit1") != null
			and dr.get_node_or_null("HazardPit2") != null,
			"DeathRace has 3 molten Hazard Pits (HazardPit0..2)")
	_check(dr.get_node_or_null("Ramp0") != null and dr.get_node_or_null("Ramp7") != null,
			"DeathRace has 8 jump ramps (Ramp0..7)")
	_check(dr.get_node_or_null("PickupOverdrive0") != null and dr.get_node_or_null("PickupRepairPit0") != null,
			"DeathRace has track and pit-lane pickups")

	# Guaranteed Nardus assignment in a 1-player roster whose ID is "mock-host"
	_check(bike != null and str(bike.get("vehicle_profile")) == "pogo",
			"Single-player Death Race roster guarantees Nardus assignment even for mock-host")

	# LoopZone physics check: entering LoopZone sets bike.loop_up != Vector3.ZERO
	var loop_zone := dr.get_node_or_null("TrackLoop0/LoopZone") as Area3D
	if loop_zone != null and bike != null:
		loop_zone.call("_on_body_entered", bike)
		loop_zone.call("_physics_process", 0.016)
		var lup: Vector3 = bike.get("loop_up")
		_check(lup.length() > 0.9, "LoopZone computes centripetal loop_up vector on bike (len=%.2f)" % lup.length())
		loop_zone.call("_on_body_exited", bike)
		_check((bike.get("loop_up") as Vector3).length() < 0.01, "Exiting LoopZone clears bike.loop_up")

	# ---- 4. Arsenal: Rocket Launcher (5s CD, 2x dmg, 4.5m blast) & Meteor Shower (6s CD, 2s fall, massive dmg)
	var reload_bar := hud.get_node_or_null("ReloadBar") as ProgressBar if hud != null else null
	var weapon_lbl := hud.get_node_or_null("WeaponLabel") as Label if hud != null else null
	_check(reload_bar != null and weapon_lbl != null, "HUD has ReloadBar and WeaponLabel for reloading status")

	if cannons != null and touch_hud != null and bike != null:
		# Mobile right-analog-back (DOWN) cycles weapons: primary -> rocket -> meteor -> primary
		var pad := touch_hud.get_node_or_null("AnalogDrive") as Control
		var toggle := touch_hud.get_node_or_null("BtnTouchToggle") as Button
		if toggle != null and not bool(touch_hud.call("is_overlay_active")):
			toggle.pressed.emit()
			await process_frame
			await process_frame
		_check(str(cannons.get("current_weapon")) == "primary", "Starts on primary weapon")
		if pad != null:
			var r := pad.get_global_rect()
			var centre := r.get_center()
			var down_pos := Vector2(centre.x, centre.y + (r.size.y * 0.5 - 16.0))
			touch_hud.call("_on_pointer_down", 0, centre)
			await process_frame
			touch_hud.call("_on_pointer_move", 0, down_pos)
			await process_frame
			_check(str(cannons.get("current_weapon")) == "rocket",
					"Pushing right analog back switches weapon to Rocket Launcher")
			touch_hud.call("_on_pointer_move", 0, centre)
			await process_frame
			touch_hud.call("_on_pointer_up", 0, centre)
			await process_frame

		# Fire Rocket Launcher: 5.0s cooldown, 2x damage (60.0), 4.5m blast radius
		cannons.call("select_weapon", "rocket")
		_check(is_equal_approx(float(cannons.call("max_cooldown_for", "rocket")), 5.0),
				"Rocket Launcher cooldown is 5.0 seconds")
		# Spawn a dummy enemy bike 3.0m in front of muzzle (inside 4.5m blast radius)
		var dummy_enemy := StaticBody3D.new()
		dummy_enemy.name = "DummyEnemy"
		dummy_enemy.add_to_group("bike")
		var dcol := CollisionShape3D.new()
		var dbox := BoxShape3D.new()
		dbox.size = Vector3(1.5, 1.5, 1.5)
		dcol.shape = dbox
		dummy_enemy.add_child(dcol)
		var enemy_combat := Node3D.new()
		var stub := GDScript.new()
		stub.source_code = "extends Node3D\nvar last_dmg := 0.0\nfunc take_damage(amount: float, _att: String, _pt: Vector3, _tok: String = '') -> void:\n\tlast_dmg += amount\n"
		stub.reload()
		enemy_combat.name = "CombatController"
		enemy_combat.set_script(stub)
		dummy_enemy.add_child(enemy_combat)
		dr.add_child(dummy_enemy)
		var fwd := bike.global_transform.basis.z.normalized()
		dummy_enemy.global_position = bike.global_position + fwd * 3.2 + Vector3(0.0, 0.6, 0.0)
		await physics_frame

		cannons.call("fire")
		_check(not bool(cannons.call("can_fire")) and float(cannons.call("remaining_cooldown", "rocket")) > 4.5,
				"Rocket Launcher enters 5.0s reload lockout after firing")
		_check(reload_bar != null and reload_bar.value < 20.0,
				"ReloadBar drops to reloading status after firing Rocket Launcher (%.1f%%)" % (reload_bar.value if reload_bar else -1.0))
		for _f in range(12):
			await physics_frame
			await process_frame
		_check(is_equal_approx(float(enemy_combat.get("last_dmg")), 60.0),
				"Rocket Launcher deals double MG damage (60.0) in 4.5m blast radius (got %.1f)" % float(enemy_combat.get("last_dmg")))

		# Switch to Meteor Shower: 6.0s cooldown, ground aim reticle, 2.0s sky-fall delay, massive 105.0 damage
		cannons.call("select_weapon", "meteor")
		await process_frame
		_check(is_equal_approx(float(cannons.call("max_cooldown_for", "meteor")), 6.0),
				"Meteor Shower cooldown is 6.0 seconds")
		var reticle := dr.get_node_or_null("MeteorAimReticle") as Node3D
		_check(reticle != null and reticle.visible, "Selecting Meteor Shower displays 3D ground aiming reticle")
		var aim_pt: Vector3 = cannons.call("compute_meteor_target")
		enemy_combat.set("last_dmg", 0.0)
		dummy_enemy.global_position = aim_pt + Vector3(1.5, 0.5, 0.0)  # inside 7.5m meteor blast radius

		cannons.call("fire")
		_check(not bool(cannons.call("can_fire")) and float(cannons.call("remaining_cooldown", "meteor")) > 5.4,
				"Meteor Shower enters 6.0s reload lockout after firing")
		await create_timer(0.5).timeout
		_check(float(enemy_combat.get("last_dmg")) == 0.0,
				"Meteor has not impacted yet at t=0.5s (2.0s sky-fall delay active)")
		await create_timer(1.75).timeout
		_check(float(enemy_combat.get("last_dmg")) >= 95.0,
				"Meteor impacts after 2.0s sky fall dealing massive damage (%.1f >= 95.0)" % float(enemy_combat.get("last_dmg")))
		dummy_enemy.free()

	# ---- 5. Ordered Checkpoint + Finish Line Lap Tracking & Victory Splash Trigger
	if tracker != null and bike != null and hud != null:
		var finish := dr.get_node("FinishLine") as Area3D
		# Crossing FinishLine before checkpoints must NOT increment completed_laps
		tracker.call("_on_finish_line_entered", bike)
		_check(int(tracker.get("completed_laps")) == 0,
				"Crossing FinishLine without clearing checkpoints does not count a lap")
		# Complete Lap 1 & Lap 2 (lap_target == 2)
		for lap_i in range(2):
			for cp_i in range(4):
				var cp_area := dr.get_node("Checkpoint%d" % cp_i) as Area3D
				tracker.call("_on_checkpoint_entered", cp_i, cp_area, bike)
			await tracker.call("_on_finish_line_entered", bike)
		_check(int(tracker.get("completed_laps")) == 2 and bool(tracker.get("race_finished")),
				"Clearing all 4 checkpoints + FinishLine across 2 laps finishes Death Race")
		var res_panel := hud.get_node_or_null("ResultPanel") as Control
		var v_banner := hud.get_node_or_null("ResultPanel/VictorySplashBanner") as Label
		_check(bool(hud.get("victory_splash_shown")) and res_panel != null and res_panel.visible
				and v_banner != null and v_banner.visible,
				"Winning Death Race triggers Victory Splash and ResultPanel")

	dr.free()
	match_node.set("lobby", prev_lobby)
	match_node.set("players", prev_players)
	print("DEATHRACE VERIFY: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
