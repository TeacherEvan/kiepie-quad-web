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

		# Fire Rocket Launcher: 1.5s cooldown, 2x damage (60.0), 4.5m blast radius
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
		var fwd := bike.global_transform.basis.z.normalized()
		dummy_enemy.global_position = bike.global_position + fwd * 3.2 + Vector3(0.0, 0.6, 0.0)
		dummy_proxy.global_position = bike.global_position + fwd * 3.6 + Vector3(0.9, 0.6, 0.0)
		await physics_frame

		cannons.call("fire")
		_check(not bool(cannons.call("can_fire")) and float(cannons.call("remaining_cooldown", "rocket")) > 1.1,
				"Rocket Launcher enters 1.5s reload lockout after firing")
		_check(reload_bar != null and reload_bar.value < 20.0,
				"ReloadBar drops to reloading status after firing Rocket Launcher (%.1f%%)" % (reload_bar.value if reload_bar else -1.0))
		for _f in range(12):
			await physics_frame
			await process_frame
		_check(is_equal_approx(float(enemy_combat.get("last_dmg")), 60.0),
				"Rocket Launcher deals double MG damage (60.0) in 4.5m blast radius (got %.1f)" % float(enemy_combat.get("last_dmg")))
		var rocket_number := false
		for lbl in dr.find_children("*", "Label3D", true, false):
			if str((lbl as Label3D).text).begins_with("-60"):
				rocket_number = true
		_check(rocket_number, "Rocket detonation spawns a floating Label3D damage number on the controller-less dummy")

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
		for lbl in dr.find_children("*", "Label3D", true, false):
			if str((lbl as Label3D).text).begins_with("-105"):
				meteor_number = true
		_check(meteor_number, "Meteor detonation spawns a floating Label3D damage number on the controller-less dummy")
		dummy_enemy.free()
		dummy_proxy.free()

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

	# F-P1-8: TrackLoop0/LoopZone does not overlap the flat straightaway center (26, 0.5, -44)
	var lz0 := dr.get_node_or_null("TrackLoop0/LoopZone") as Area3D
	var lz0_col := lz0.get_node_or_null("ZoneCollider") as CollisionShape3D if lz0 != null else null
	_check(lz0_col != null and lz0_col.shape is BoxShape3D, "TrackLoop0/LoopZone/ZoneCollider exists")
	if lz0_col != null and lz0_col.shape is BoxShape3D:
		var local_flat := lz0_col.to_local(Vector3(26.0, 0.5, -44.0))
		var half := (lz0_col.shape as BoxShape3D).size * 0.5
		var overlaps_flat := absf(local_flat.x) < half.x and absf(local_flat.y) < half.y and absf(local_flat.z) < half.z
		_check(not overlaps_flat, "TrackLoop0/LoopZone is clear of flat lane center (26,0.5,-44) (F-P1-8)")

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
		bike.global_transform = prev_xf

	dr.free()
	match_node.set("lobby", prev_lobby)
	match_node.set("players", prev_players)
	print("DEATHRACE VERIFY: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
