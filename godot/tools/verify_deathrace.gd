extends SceneTree
## Gate: Battle Royale & Death Race game modes, Death Race circuit (loops,
## hazard pits, ramps, pickups, ordered checkpoints, finish line & lap counter),
## Victory Splash video, Rocket Launcher (1.5s CD, lethal direct / 90% 4.5m blast) &
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
	var guard := load("res://tools/_gate_settings_guard.gd") as GDScript
	var cfg_snap: Dictionary = guard.call("backup", root)
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
		var btn_br := main_menu.get_node_or_null("SafeMargin/Scroll/ScrollBox/Card/VBox/ModeRow/BtnModeBattleRoyale") as Button
		var btn_dr := main_menu.get_node_or_null("SafeMargin/Scroll/ScrollBox/Card/VBox/ModeRow/BtnModeDeathRace") as Button
		var btn_prac := main_menu.get_node_or_null("SafeMargin/Scroll/ScrollBox/Card/VBox/BtnPractice") as Button
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
	var mock_node: Node = sb.get("mock")
	if mock_node != null and mock_node.has_method("reset_cooldown_for_test"):
		mock_node.call("reset_cooldown_for_test")
	var create_res: Dictionary = await sb.call("call_rpc", "create_lobby", {
		"p_name": "DeathRaceGate",
		"p_settings": {"game_mode": "death_race", "lap_target": 2, "damage": 30, "respawn_delay": 1.0},
	})
	var lobby_dict: Dictionary = create_res.get("lobby", {})
	var lobby_id := str(lobby_dict.get("id", "dr-1"))
	await sb.call("call_rpc", "start_match", {"p_lobby_id": lobby_id})
	lobby_dict["status"] = "playing"
	match_node.call("apply_lobby", lobby_dict)
	match_node.set("players", {
		"mock-host": {"user_id": "mock-host", "display_name": "Host", "color": "#ff7a1a", "score": 0, "laps": 0, "kills": 0},
	})

	var dr_packed := load("res://scenes/DeathRace.tscn") as PackedScene
	_check(dr_packed != null, "DeathRace.tscn loads")
	if dr_packed == null:
		guard.call("restore", root, cfg_snap)
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

	# ---- 4. Arsenal: Rocket Launcher (1.5s CD, 2x dmg, 4.5m blast) & Meteor Shower (6s CD, 2s fall, massive dmg)
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

		# Fire Rocket Launcher: 1.5s cooldown, 90% blast damage, 4.5m blast radius
		cannons.call("select_weapon", "rocket")
		_check(is_equal_approx(float(cannons.call("max_cooldown_for", "rocket")), 1.5),
				"Rocket Launcher cooldown is 1.5 seconds")
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
		# Second dummy WITHOUT a local CombatController (like a remote NetworkedBike
		# proxy): AOE hits must pop a gold floating Label3D damage number for the shooter
		var dummy_proxy := StaticBody3D.new()
		dummy_proxy.name = "DummyEnemyProxy"
		dummy_proxy.add_to_group("bike")
		dummy_proxy.set("player_id", "dummy-proxy")
		var dcol2 := CollisionShape3D.new()
		var dbox2 := BoxShape3D.new()
		dbox2.size = Vector3(1.5, 1.5, 1.5)
		dcol2.shape = dbox2
		dummy_proxy.add_child(dcol2)
		dr.add_child(dummy_proxy)
		# Third dummy: hidden / respawning proxy inside blast radius MUST NOT take
		# damage or spawn a ghost floating damage number (P1-5).
		var dummy_ghost := StaticBody3D.new()
		dummy_ghost.name = "DummyGhostProxy"
		dummy_ghost.add_to_group("bike")
		dummy_ghost.set("player_id", "dummy-ghost")
		dummy_ghost.visible = false
		dr.add_child(dummy_ghost)
		var fwd := bike.global_transform.basis.z.normalized()
		dummy_enemy.global_position = bike.global_position + fwd * 3.2 + Vector3(0.0, 0.6, 0.0)
		dummy_proxy.global_position = bike.global_position + fwd * 3.6 + Vector3(0.9, 0.6, 0.0)
		dummy_ghost.global_position = bike.global_position + fwd * 3.4 + Vector3(-1.4, 0.6, 0.0)
		await physics_frame

		cannons.call("fire")
		_check(not bool(cannons.call("can_fire")) and float(cannons.call("remaining_cooldown", "rocket")) > 1.1,
				"Rocket Launcher enters 1.5s reload lockout after firing")
		_check(reload_bar != null and reload_bar.value < 20.0,
				"ReloadBar drops to reloading status after firing Rocket Launcher (%.1f%%)" % (reload_bar.value if reload_bar else -1.0))
		for _f in range(12):
			await physics_frame
			await process_frame
		_check(is_equal_approx(float(enemy_combat.get("last_dmg")), 90.0),
				"Rocket Launcher removes 90%% health (90.0) in 4.5m blast radius (got %.1f)" % float(enemy_combat.get("last_dmg")))
		var rocket_number := false
		var ghost_rocket_num := false
		for lbl in dr.find_children("*", "Label3D", true, false):
			var l3 := lbl as Label3D
			if str(l3.text).begins_with("-90"):
				if l3.global_position.distance_to(dummy_ghost.global_position) < 1.0:
					ghost_rocket_num = true
				else:
					rocket_number = true
		_check(rocket_number, "Rocket detonation spawns a floating Label3D damage number on the controller-less dummy")
		_check(not ghost_rocket_num, "Rocket detonation skips hidden/respawning proxy (no ghost damage number)")

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
		dummy_proxy.global_position = aim_pt + Vector3(-1.5, 0.5, 0.0)
		dummy_ghost.global_position = aim_pt + Vector3(0.0, 0.5, 2.2)

		cannons.call("fire")
		_check(not bool(cannons.call("can_fire")) and float(cannons.call("remaining_cooldown", "meteor")) > 5.4,
				"Meteor Shower enters 6.0s reload lockout after firing")
		await create_timer(0.5).timeout
		_check(float(enemy_combat.get("last_dmg")) == 0.0,
				"Meteor has not impacted yet at t=0.5s (2.0s sky-fall delay active)")
		await create_timer(1.75).timeout
		_check(float(enemy_combat.get("last_dmg")) >= 95.0,
				"Meteor impacts after 2.0s sky fall dealing massive damage (%.1f >= 95.0)" % float(enemy_combat.get("last_dmg")))
		var meteor_number := false
		var ghost_meteor_num := false
		for lbl in dr.find_children("*", "Label3D", true, false):
			var l3 := lbl as Label3D
			if str(l3.text).begins_with("-105"):
				if l3.global_position.distance_to(dummy_ghost.global_position) < 1.0:
					ghost_meteor_num = true
				else:
					meteor_number = true
		_check(meteor_number, "Meteor detonation spawns a floating Label3D damage number on the controller-less dummy")
		_check(not ghost_meteor_num, "Meteor detonation skips hidden/respawning proxy (no ghost damage number)")
		dummy_enemy.free()
		dummy_proxy.free()
		dummy_ghost.free()

		# End-to-end 3-victim AOE sub-token + MockBackend register_kill 3/3 scoring
		var mock_supa := root.get_node_or_null("Supabase")
		if mock_supa != null:
			var shot_res: Variant = await mock_supa.call("call_rpc", "issue_shot", {})
			var base_tok := str((shot_res as Dictionary).get("token", "")) if shot_res is Dictionary else ""
			var mock_b: Node = mock_supa.get("mock") as Node
			if mock_b != null and mock_b.has_method("reset_cooldown_for_test"):
				mock_b.call("reset_cooldown_for_test")
			var r1: Variant = await mock_supa.call("call_rpc", "register_kill", {
				"p_killer": "mock-host", "p_target": "vA", "p_token": base_tok + ":vA"
			})
			var r2: Variant = await mock_supa.call("call_rpc", "register_kill", {
				"p_killer": "mock-host", "p_target": "vB", "p_token": base_tok + ":vB"
			})
			var r3: Variant = await mock_supa.call("call_rpc", "register_kill", {
				"p_killer": "mock-host", "p_target": "vC", "p_token": base_tok + ":dDrum1"
			})
			_check(base_tok != "" and r1 is Dictionary and bool(r1.get("ok", false))
					and r2 is Dictionary and bool(r2.get("ok", false))
					and r3 is Dictionary and bool(r3.get("ok", false)),
					"AOE/drum sub-tokens (:vA, :vB, :dDrum1) all score via MockBackend register_kill")

	# ---- 5. Ordered Checkpoint + Finish Line Lap Tracking & Victory Splash Trigger
	if tracker != null and bike != null and hud != null:
		var finish := dr.get_node("FinishLine") as Area3D
		# Crossing FinishLine before checkpoints must NOT increment completed_laps
		tracker.call("_on_finish_line_entered", bike)
		_check(int(tracker.get("completed_laps")) == 0,
				"Crossing FinishLine without clearing checkpoints does not count a lap")
		# Complete Lap 1
		for cp_i in range(4):
			var cp_area := dr.get_node("Checkpoint%d" % cp_i) as Area3D
			tracker.call("_on_checkpoint_entered", cp_i, cp_area, bike)
		await tracker.call("_on_finish_line_entered", bike)
		_check(int(tracker.get("completed_laps")) == 1,
				"Clearing all 4 checkpoints + FinishLine counts Lap 1")
		# P1-5: guest _on_roster_changed() rollback recomputes current_lap = completed_laps + 1
		var m_node := root.get_node_or_null("Match")
		if m_node != null:
			var saved_lobby: Dictionary = (m_node.get("lobby") as Dictionary).duplicate(true)
			var saved_players: Dictionary = (m_node.get("players") as Dictionary).duplicate(true)
			m_node.set("lobby", {"id": "1", "host_id": "other-host", "status": "playing", "settings": {"game_mode": "death_race", "lap_target": 3}})
			m_node.set("players", {"mock-host": {"user_id": "mock-host", "laps": 0, "score": 0}})
			tracker.set("completed_laps", 1)
			tracker.set("current_lap", 2)
			tracker.call("_on_roster_changed")
			_check(int(tracker.get("completed_laps")) == 0 and int(tracker.get("current_lap")) == 1,
					"P1-5: guest RaceTracker._on_roster_changed() rollback recomputes current_lap=1")
			m_node.set("lobby", saved_lobby)
			m_node.set("players", saved_players)
			tracker.set("completed_laps", 1)
			tracker.set("current_lap", 2)
		# Regression B-P0-1: immediate second lap inside MIN_LAP_SECONDS is rejected
		for cp_i in range(4):
			var cp_area := dr.get_node("Checkpoint%d" % cp_i) as Area3D
			tracker.call("_on_checkpoint_entered", cp_i, cp_area, bike)
		await tracker.call("_on_finish_line_entered", bike)
		_check(int(tracker.get("completed_laps")) == 1,
				"Instant second lap inside MIN_LAP_SECONDS is rejected (B-P0-1)")
		# Regression P1-6: empty shot token in a live match fails closed (never credits lap)
		if mock_node != null and mock_node.has_method("reset_cooldown_for_test"):
			mock_node.call("reset_cooldown_for_test")
		var empty_rpc_stub := Node.new()
		var empty_rpc_gd := GDScript.new()
		empty_rpc_gd.source_code = "extends Node\nfunc call_rpc(_n: String, _a: Dictionary = {}) -> Dictionary:\n\treturn {}\n"
		empty_rpc_gd.reload()
		empty_rpc_stub.set_script(empty_rpc_gd)
		sb.set("mock", empty_rpc_stub)
		await tracker.call("_on_finish_line_entered", bike)
		sb.set("mock", mock_node)
		empty_rpc_stub.free()
		_check(int(tracker.get("completed_laps")) == 1,
				"RaceTracker fails closed when issue_shot returns an empty token (P1-6)")
		# Reset mock lap cooldown and finish Lap 2 (lap_target == 2)
		if mock_node != null and mock_node.has_method("reset_cooldown_for_test"):
			mock_node.call("reset_cooldown_for_test")
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

	# ---- 6. Frontend audit regressions (F-P0-1, F-P0-2, F-P1-1, F-P1-2, F-P1-6, F-P1-7, F-P1-8)
	# F-P0-2: Pit-launcher ramps launch ALONG clockwise travel direction
	#   Ramp0 = East straight (+Z), Ramp2 = South straight (-X), Ramp4 = West straight (-Z)
	var r0 := dr.get_node_or_null("Ramp0") as Node3D
	var r2 := dr.get_node_or_null("Ramp2") as Node3D
	var r4 := dr.get_node_or_null("Ramp4") as Node3D
	_check(r0 != null and r0.global_transform.basis.z.normalized().dot(Vector3.BACK) > 0.95,
			"Ramp0 launches along +Z clockwise east straight over HazardPit0 (F-P0-2)")
	_check(r2 != null and r2.global_transform.basis.z.normalized().dot(Vector3.LEFT) > 0.95,
			"Ramp2 launches along -X clockwise south straight over HazardPit1 (F-P0-2)")
	_check(r4 != null and r4.global_transform.basis.z.normalized().dot(Vector3.FORWARD) > 0.95,
			"Ramp4 launches along -Z clockwise west straight over HazardPit2 (F-P0-2)")

	# F-P1-8: Full-width straightaway clearance — EVERY LoopSeg & LoopZone under TrackLoop0/1
	# must be completely clear of NorthStraight (z in [-52, -36]) and SouthStraight (z in [36, 52]).
	var loop_intrudes := false
	for l_name in ["TrackLoop0", "TrackLoop1"]:
		var lp_node := dr.get_node_or_null(l_name) as Node3D
		_check(lp_node != null, "%s exists" % l_name)
		if lp_node == null:
			continue
		for ch in lp_node.get_children():
			if ch is StaticBody3D and str(ch.name).begins_with("LoopSeg"):
				var seg_z := (ch as Node3D).global_position.z
				if absf(seg_z) <= 52.2:
					loop_intrudes = true
			elif ch is Area3D and str(ch.name) == "LoopZone":
				var zc := ch.get_node_or_null("ZoneCollider") as CollisionShape3D
				if zc != null and zc.shape is BoxShape3D:
					var half_z := (zc.shape as BoxShape3D).size.x * 0.5  # rotated 90 deg Y -> local X is world Z
					if absf(zc.global_position.z) - half_z <= 52.2:
						loop_intrudes = true
	_check(not loop_intrudes, "TrackLoop0/1 & LoopZones are completely clear of flat straightaways (|z| > 52.2) (F-P1-8)")

	# Tier-2 Death Race Turn 1 navigation @ 26 m/s (release at 85 deg) — no spinout
	if bike != null:
		bike.call("set_spawn", Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(25.0, 0.1, -44.0)))
		bike.call("reset_bike")
		for _f in range(15):
			await physics_frame
		bike.linear_velocity = Vector3(26.0, 0.0, 0.0)
		Input.action_press("move_forward")
		Input.action_press("steer_right")
		var py1 := rad_to_deg(atan2(bike.global_transform.basis.z.x, bike.global_transform.basis.z.z))
		var tot1 := 0.0
		var max_x1 := 25.0
		var peak_slip1 := 0.0
		for _t in range(100):
			if absf(tot1) >= 85.0:
				Input.action_release("steer_right")
			await physics_frame
			var b1 := bike.global_transform.basis.orthonormalized()
			var ny1 := rad_to_deg(atan2(b1.z.x, b1.z.z))
			tot1 += fmod(ny1 - py1 + 540.0, 360.0) - 180.0
			py1 = ny1
			max_x1 = maxf(max_x1, bike.global_position.x)
			peak_slip1 = maxf(peak_slip1, absf(rad_to_deg(atan2(bike.linear_velocity.dot(b1.x), maxf(bike.linear_velocity.dot(b1.z), 0.5)))))
		Input.action_release("move_forward")
		Input.action_release("steer_right")
		_check(absf(tot1) <= 115.0 and peak_slip1 < 20.0 and max_x1 < 74.0,
				"DeathRace Turn 1 @26m/s navigates cleanly without spinout (yaw=%.1f° slip=%.1f° max_x=%.1f)" % [tot1, peak_slip1, max_x1])

		# Tier-2 TrackLoop0 360-degree completion + stalled-loop upright recovery
		bike.call("set_spawn", Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(14.0, 0.1, -56.4)))
		bike.call("reset_bike")
		for _f in range(15):
			await physics_frame
		bike.linear_velocity = Vector3(24.0, 0.0, 0.0)
		Input.action_press("move_forward")
		var loop_max_y := 0.0
		var loop_min_up := 1.0
		for _t in range(200):
			await physics_frame
			loop_max_y = maxf(loop_max_y, bike.global_position.y)
			loop_min_up = minf(loop_min_up, bike.global_transform.basis.y.normalized().y)
		Input.action_release("move_forward")
		_check(loop_max_y > 14.0 and loop_min_up < -0.5 and bike.global_transform.basis.y.normalized().y > 0.80,
				"TrackLoop0 completes 360° inversion and lands upright (max_y=%.1f min_up=%.2f end_up=%.2f)" % [
					loop_max_y, loop_min_up, bike.global_transform.basis.y.normalized().y])

		# Stalled-loop bailout: bike stalled upside-down near top of loop must right itself
		bike.global_transform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(26.0, 17.5, -58.2))
		bike.linear_velocity = Vector3(1.0, 0.0, 0.0)
		bike.angular_velocity = Vector3.ZERO
		for _t in range(240):
			await physics_frame
		_check(bike.global_transform.basis.y.normalized().y > 0.70,
				"Stalled loop bike rights itself upright instead of staying inverted (up=%.2f)" % bike.global_transform.basis.y.normalized().y)

	# HUD SpeedLabel check
	var speed_lbl := hud.get_node_or_null("SpeedLabel") as Label if hud != null else null
	_check(speed_lbl != null and speed_lbl.text.find("km/h") >= 0,
			"MatchHud displays Death Race SpeedLabel (text='%s')" % (speed_lbl.text if speed_lbl else "null"))

	# F-P1-7: Idle OmniLight3D count stays within WebGL2 8-light forward budget
	var omni_cnt := 0
	var stack: Array = [dr]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is OmniLight3D:
			omni_cnt += 1
		for ch in cur.get_children():
			stack.append(ch)
	_check(omni_cnt <= 8, "DeathRace idle OmniLight3D count (%d) <= 8 WebGL2 budget (F-P1-7)" % omni_cnt)

	# F-P1-2: MatchHud KillFeed does not overlap WeaponLabel, Banner, or Radar
	if hud != null:
		hud.call("_relayout")
		var kf := hud.get_node_or_null("KillFeed") as Control
		var wl := hud.get_node_or_null("WeaponLabel") as Control
		var bn := hud.get_node_or_null("Banner") as Control
		var rd := hud.get_node_or_null("Radar") as Control
		if kf != null and wl != null and bn != null and rd != null:
			var r_kf := kf.get_global_rect()
			_check(r_kf.intersection(wl.get_global_rect()).get_area() == 0.0
					and r_kf.intersection(bn.get_global_rect()).get_area() == 0.0
					and r_kf.intersection(rd.get_global_rect()).get_area() == 0.0,
					"MatchHud KillFeed has zero overlap with WeaponLabel/Banner/Radar (F-P1-2)")
		# P2-4: _fps_label clears WeaponLabel, Radar & TouchHUD across all 4 viewports
		var mh_gd := load("res://src/ui/MatchHud.gd") as GDScript
		var fps_667: Vector2 = mh_gd.call("compute_fps_pos", Vector2(667.0, 375.0))
		var fps_844: Vector2 = mh_gd.call("compute_fps_pos", Vector2(844.0, 390.0))
		var fps_390: Vector2 = mh_gd.call("compute_fps_pos", Vector2(390.0, 844.0))
		var fps_1280: Vector2 = mh_gd.call("compute_fps_pos", Vector2(1280.0, 720.0))
		_check(fps_667 == Vector2(102.0, 90.0) and fps_844 == Vector2(102.0, 90.0),
				"P2-4: MatchHud.compute_fps_pos places FPS right of Radar on short mobile viewports (667x375=%s, 844x390=%s)" % [str(fps_667), str(fps_844)])
		_check(fps_390 == Vector2(12.0, 272.0) and fps_1280 == Vector2(12.0, 272.0),
				"P2-4: MatchHud.compute_fps_pos places FPS below Radar/KillFeed on tall/desktop viewports (390x844=%s, 1280x720=%s)" % [str(fps_390), str(fps_1280)])
		hud.set("_show_fps", true)
		hud.call("_process", 0.016)
		var fps_lbl := hud.get("_fps_label") as Control
		if fps_lbl != null and wl != null and rd != null:
			_check(fps_lbl.position.y >= 90.0
					and fps_lbl.get_global_rect().intersection(wl.get_global_rect()).get_area() == 0.0,
					"P2-4: MatchHud._fps_label clears WeaponLabel & Radar (pos=%s)" % str(fps_lbl.position))
		hud.set("_show_fps", false)

	# F-P0-1: DestructibleBuilding.smash(impulse) accepts Rocket/Meteor impulse safely
	var pit_garage := dr.get_node_or_null("PitGarage") as Node3D
	if pit_garage != null:
		pit_garage.call("smash", Vector3(0.0, 2.0, 12.0))
		_check(not bool(pit_garage.get("_intact")),
				"DestructibleBuilding.smash(impulse) shatters PitGarage cleanly (F-P0-1)")

	# F-P1-1: Respawning after clearing Checkpoint0 preserves checkpoint spawn
	if tracker != null and bike != null and combat != null:
		tracker.set("race_finished", false)
		tracker.set("next_checkpoint", 0)
		var cp0 := dr.get_node_or_null("Checkpoint0") as Area3D
		if cp0 != null:
			tracker.call("_on_checkpoint_entered", 0, cp0, bike)
			combat.call("_respawn")
			for _f in range(3):
				await physics_frame
			var dist_cp0 := Vector2(bike.global_position.x - cp0.global_position.x,
					bike.global_position.z - cp0.global_position.z).length()
			_check(dist_cp0 < 2.5,
					"CombatController._respawn preserves Death Race Checkpoint0 (dist=%.2fm) (F-P1-1)" % dist_cp0)

	# F-P1-6: FollowCam handles vertical loop pose without collinear look_at NaN
	var cam_rig := dr.get_node_or_null("CameraRig") as Node3D
	if cam_rig != null and bike != null:
		var prev_xf := bike.global_transform
		bike.global_transform = Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.UP), Vector3(0.0, 10.0, 0.0))
		cam_rig.global_position = Vector3(0.0, 5.0, 0.0)
		cam_rig.call("_process", 0.016)
		_check(cam_rig.global_position.is_finite() and cam_rig.global_transform.basis.is_finite(),
				"FollowCam survives vertical loop pose with finite transform (F-P1-6)")
		# Tier-2 FollowCam high-speed turn lag bound
		bike.call("set_spawn", Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(-30.0, 0.1, -44.0)))
		bike.call("reset_bike")
		cam_rig.global_position = Vector3(-34.6, 2.5, -44.0)
		for _f in range(5):
			await physics_frame
		bike.linear_velocity = Vector3(35.0, 0.0, 0.0)
		Input.action_press("move_forward")
		var max_cam_d := 0.0
		var max_cam_lag := 0.0
		for _t in range(60):
			if _t == 20:
				Input.action_press("steer_right")
			await physics_frame
			cam_rig.call("_process", 1.0 / 60.0)
			max_cam_d = maxf(max_cam_d, cam_rig.global_position.distance_to(bike.global_position))
			var to_b := bike.global_position - cam_rig.global_position
			to_b.y = 0.0
			var bf := bike.global_transform.basis.z
			bf.y = 0.0
			if to_b.length() > 0.1 and bf.length() > 0.1:
				max_cam_lag = maxf(max_cam_lag, rad_to_deg(to_b.normalized().angle_to(bf.normalized())))
		Input.action_release("move_forward")
		Input.action_release("steer_right")
		_check(max_cam_d <= 6.2 and max_cam_lag <= 22.0,
				"FollowCam tracks 35 m/s turn tightly (max_dist=%.2fm <= 6.2m, lag=%.1f° <= 22°)" % [max_cam_d, max_cam_lag])
		bike.global_transform = prev_xf

	# P2-2: HazardPit ignores controller-less remote NetworkedBike proxies
	var pit := dr.get_node_or_null("HazardPit0") as Node3D
	if pit != null:
		var nb_gd := load("res://src/game/NetworkedBike.gd") as GDScript
		var fake_remote := nb_gd.new() as StaticBody3D
		fake_remote.add_to_group("bike")
		dr.add_child(fake_remote)
		pit.call("_on_body_entered", fake_remote)
		_check(not (pit.get("_occupants") as Array).has(fake_remote),
				"P2-2: HazardPit ignores controller-less remote NetworkedBike proxy")
		fake_remote.free()

	# P2-3: RocketProjectile._detonate ignores hidden/ignited FuelDrum for hit_confirmed
	var drum := dr.get_node_or_null("FuelDrum0") as Node3D
	if drum != null and combat != null:
		var hit_cnt := [0]
		var on_hit := func() -> void: hit_cnt[0] += 1
		combat.connect("hit_confirmed", on_hit)
		var prev_vis := drum.visible
		var prev_ign := bool(drum.get("_ignited"))
		var prev_pos := drum.global_position
		drum.global_position = Vector3(200.0, 0.5, 200.0)
		drum.visible = false
		drum.set("_ignited", true)
		var r_gd := load("res://src/game/RocketProjectile.gd") as GDScript
		var rkt := Node3D.new()
		rkt.set_script(r_gd)
		dr.add_child(rkt)
		rkt.set("owner_id", str(match_node.get("my_user_id")))
		rkt.set("owner_node", bike)
		rkt.set("damage", 60.0)
		rkt.set("blast_radius", 6.0)
		rkt.call("_detonate", drum.global_position, null)
		_check(hit_cnt[0] == 0, "P2-3: RocketProjectile ignores hidden/ignited FuelDrum for hit_confirmed")
		rkt.queue_free()
		drum.global_position = prev_pos
		drum.visible = prev_vis
		drum.set("_ignited", prev_ign)
		combat.disconnect("hit_confirmed", on_hit)

	# P1-5: RaceTracker missing 'laps' recovery
	var rt := dr.get_node_or_null("RaceTracker")
	if rt != null:
		rt.set("completed_laps", 1)
		rt.set("_lap_pending", true)
		var uid := str(root.get_node("Supabase").get("user_id"))
		match_node.set("lobby", {"status": "playing", "host_id": "other-host", "settings": {"lap_target": 2}})
		match_node.set("players", {uid: {"user_id": uid, "kills": 0}})
		rt.call("_on_roster_changed")
		_check(int(rt.get("completed_laps")) == 1 and bool(rt.get("_lap_pending")),
				"P1-5: RaceTracker defers rollback when 'laps' missing and _lap_pending is true")
		match_node.set("players", {uid: {"user_id": uid, "kills": 0, "laps": 1}})
		rt.call("_on_roster_changed")
		_check(not bool(rt.get("_lap_pending")),
				"P1-5: RaceTracker clears _lap_pending when auth_laps >= completed_laps")
		# P1-2: non-final pending lap reconciles back to authoritative auth_laps on timeout
		rt.set("completed_laps", 1)
		rt.set("current_lap", 2)
		rt.set("_lap_pending", true)
		match_node.set("players", {uid: {"user_id": uid, "kills": 0, "laps": 0}})
		rt.call("_reconcile_pending_lap", 1, 3)
		_check(int(rt.get("completed_laps")) == 0 and int(rt.get("current_lap")) == 1 and not bool(rt.get("_lap_pending")),
				"P1-2: RaceTracker reconciles dropped non-final guest lap back to auth_laps=0")

	# Track B: Big-Ben Small Cash Bag Rocket & Quad Lightning / Big-Ben Giant Cash Bag Meteor
	var cb_rkt_gd := load("res://src/game/RocketProjectile.gd") as GDScript
	var cb_rkt := Node3D.new()
	cb_rkt.set_script(cb_rkt_gd)
	dr.add_child(cb_rkt)
	cb_rkt.call("setup", "p1", null, Vector3.ZERO, Vector3.FORWARD, 40.0, 60.0, "t1", Color.GREEN, 4.5, "cash_bag")
	_check(str(cb_rkt.get("visual_style")) == "cash_bag" and cb_rkt.get_node_or_null("CashBag") != null,
			"Track B: RocketProjectile cash_bag mounts CashBagVisual")
	cb_rkt.queue_free()

	# NARDUS (pogo) launcher: massive cigar, distinct from Big-Ben's cash bag.
	var cg_rkt := Node3D.new()
	cg_rkt.set_script(cb_rkt_gd)
	dr.add_child(cg_rkt)
	cg_rkt.call("setup", "p1", null, Vector3.ZERO, Vector3.FORWARD, 38.0, 90.0, "t-cigar", Color.GREEN, 4.5, "cigar")
	_check(str(cg_rkt.get("visual_style")) == "cigar" and cg_rkt.get_node_or_null("Cigar") != null,
			"NARDUS rocket mounts the massive Cigar visual")
	var cg_visual := cg_rkt.get_node_or_null("Cigar") as Node3D
	var cg_body: MeshInstance3D = null
	if cg_visual != null and cg_visual.get_child_count() > 0:
		cg_body = cg_visual.get_child(0) as MeshInstance3D
	_check(cg_body != null and cg_body.mesh is CylinderMesh
			and (cg_body.mesh as CylinderMesh).height >= 1.8,
			"NARDUS cigar is massive (body >= 1.8 m)")
	cg_rkt.queue_free()

	# Rocket contract: direct hit = 100% kill, near miss = flat 90% health loss.
	var lethal_stub := GDScript.new()
	lethal_stub.source_code = "extends Node3D\nvar lethal := false\nvar last_dmg := 0.0\nvar last_tok := ''\nfunc take_lethal_hit(_att: String, _pt: Vector3, tok: String = '') -> void:\n\tlethal = true\n\tlast_tok = tok\nfunc take_damage(amount: float, _att: String, _pt: Vector3, _tok: String = '') -> void:\n\tlast_dmg += amount\n"
	lethal_stub.reload()
	var lethal_dummy := StaticBody3D.new()
	lethal_dummy.add_to_group("bike")
	# Declare player_id on a script: a dynamic set() on a bare StaticBody3D does
	# not create a real property, so get("player_id") in RocketProjectile sees null.
	var dummy_script := GDScript.new()
	dummy_script.source_code = "extends StaticBody3D\nvar player_id: String = ''\n"
	dummy_script.reload()
	lethal_dummy.set_script(dummy_script)
	lethal_dummy.set("player_id", "lethal-dummy")
	var lcol := CollisionShape3D.new()
	var lbox := BoxShape3D.new()
	lbox.size = Vector3(1.0, 1.0, 1.0)
	lcol.shape = lbox
	lethal_dummy.add_child(lcol)
	var lethal_ctrl := Node3D.new()
	lethal_ctrl.name = "CombatController"
	lethal_ctrl.set_script(lethal_stub)
	lethal_dummy.add_child(lethal_ctrl)
	dr.add_child(lethal_dummy)
	lethal_dummy.global_position = Vector3(400.0, 0.5, 400.0)
	await physics_frame
	var hit_rkt := Node3D.new()
	hit_rkt.set_script(cb_rkt_gd)
	dr.add_child(hit_rkt)
	hit_rkt.call("setup", "p1", null, Vector3.ZERO, Vector3.FORWARD, 38.0, 90.0, "t-lethal", Color.ORANGE, 0.5, "rocket")
	hit_rkt.call("_detonate", lethal_dummy.global_position, lethal_dummy)
	_check(bool(lethal_ctrl.get("lethal")), "Rocket direct hit calls take_lethal_hit (100% kill)")
	_check(str(lethal_ctrl.get("last_tok")).ends_with(":vlethal-dummy"),
			"Rocket direct hit uses a victim-suffixed token for host multi-kill credit (got %s)" % str(lethal_ctrl.get("last_tok")))
	_check(is_equal_approx(float(lethal_ctrl.get("last_dmg")), 90.0),
			"Rocket blast removes a flat 90%% health (got %.1f)" % float(lethal_ctrl.get("last_dmg")))
	hit_rkt.queue_free()
	lethal_dummy.queue_free()
	await process_frame

	var m_gd := load("res://src/game/MeteorStrike.gd") as GDScript
	var m_lt := Node3D.new()
	m_lt.set_script(m_gd)
	dr.add_child(m_lt)
	m_lt.call("setup", "p1", null, Vector3.ZERO, 100.0, "t2", Color.CYAN, 2.0, 12.0, "lightning")
	_check(str(m_lt.get("visual_style")) == "lightning",
			"Track B: MeteorStrike lightning style set")
	m_lt.queue_free()

	var m_cb := Node3D.new()
	m_cb.set_script(m_gd)
	dr.add_child(m_cb)
	m_cb.call("setup", "p1", null, Vector3.ZERO, 100.0, "t3", Color.GOLD, 2.0, 12.0, "cash_bag")
	_check(str(m_cb.get("visual_style")) == "cash_bag" and m_cb.get_node_or_null("CashBag") != null,
			"Track B: MeteorStrike cash_bag mounts giant CashBagVisual")
	m_cb.queue_free()

	# P2-6: freed owner_node mid-flight does not error on RocketProjectile / MeteorStrike _detonate()
	var freed_owner := Node3D.new()
	dr.add_child(freed_owner)
	var r_freed := Node3D.new()
	r_freed.set_script(cb_rkt_gd)
	dr.add_child(r_freed)
	r_freed.call("setup", "p-gone", freed_owner, Vector3.ZERO, Vector3.FORWARD, 40.0, 60.0, "t-gone", Color.GREEN, 4.5, "cash_bag")
	var m_freed := Node3D.new()
	m_freed.set_script(m_gd)
	dr.add_child(m_freed)
	m_freed.call("setup", "p-gone", freed_owner, Vector3.ZERO, 100.0, "t-gone-m", Color.CYAN, 2.0, 7.5, "lightning")
	freed_owner.free()
	r_freed.call("_detonate", Vector3.ZERO, null)
	m_freed.call("_detonate")
	_check(true, "P2-6: RocketProjectile & MeteorStrike _detonate() survive freed owner_node")
	r_freed.queue_free()
	m_freed.queue_free()

	var pit0 := dr.get_node_or_null("HazardPit0") as Area3D
	if pit0 != null and combat != null and bike != null:
		combat.call("reset_state")
		combat.set("_shield_until", 0.0)
		combat.set("_invuln_until", 0.0)
		var h_pre := float(combat.get("health"))
		pit0.call("_on_body_entered", bike)
		pit0.call("_physics_process", 0.35)
		_check(float(combat.get("health")) < h_pre, "HazardPit0 deals thermal damage to local bike")
		pit0.call("_on_body_exited", bike)
		combat.call("reset_state")

	dr.free()
	match_node.set("lobby", prev_lobby)
	match_node.set("players", prev_players)
	guard.call("restore", root, cfg_snap)
	print("DEATHRACE VERIFY: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
