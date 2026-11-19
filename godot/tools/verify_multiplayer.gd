extends SceneTree
## Offline regression gate for multiplayer remote-player visibility & Talo relay:
## 1. ArenaNet._create_remote() instantiates NetworkedBike as StaticBody3D (no base type mismatch).
## 2. NetworkedBike.setup() tints meshes via surface override material (no MeshInstance3D.material error),
##    adds CollisionShape3D + Label3D Nameplate, and stays hidden until the first live state snapshot.
## 3. Roster spawn spreading assigns distinct SpawnPoints across peers so bikes don't overlap.
## 4. TaloBackend.broadcast("state") sends wire kind "bike_state" and relays both guest and host
##    positions back as broadcast_received("state") without mutating lobby/roster or failing float IDs.
## 5. Remote death/respawn ("d": true/false) and remote shots work cleanly without script errors.
## Exits 1 on any failure.

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

	# ---- 1-3, 5: ArenaNet + NetworkedBike full proxy creation, transform sync, death & shot
	match_node.call("apply_lobby", {
		"id": "1",
		"host_id": "mock-host",
		"status": "playing",
		"settings": {"kill_target": 10, "respawn_delay": 1.0},
	})
	match_node.set("players", {
		"mock-host": {"user_id": "mock-host", "display_name": "Host", "color": "#ff7a1a", "score": 0},
		"peer-2": {"user_id": "peer-2", "display_name": "PeerTwo", "color": "#40c8ff", "score": 0},
		"peer-3": {"user_id": "peer-3", "display_name": "PeerThree", "color": "#66ff88", "score": 0},
	})

	var arena := (load("res://scenes/Arena.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(arena)
	for _i in range(4):
		await process_frame

	var net := arena.get_node_or_null("ArenaNet")
	var local_bike := arena.get_node_or_null("KiepieBike") as VehicleBody3D
	var sp0 := arena.get_node_or_null("SpawnPoint0") as Node3D
	_check(net != null and local_bike != null, "ArenaNet and local KiepieBike exist in Arena")
	if net != null:
		var remote_dict: Dictionary = net.get("_remote")
		_check(remote_dict.size() == 2 and remote_dict.has("peer-2") and remote_dict.has("peer-3"),
				"ArenaNet creates NetworkedBike proxies for all non-local roster peers")
		var rb2 := remote_dict.get("peer-2") as StaticBody3D
		_check(rb2 != null and is_instance_valid(rb2), "peer-2 proxy is a valid StaticBody3D")
		if rb2 != null:
			_check(rb2.is_in_group("bike"), "remote proxy registers in group 'bike'")
			_check(rb2.get_node_or_null("Model") != null, "remote proxy loads Kiepie_Bike Model")
			var col_count := rb2.find_children("*", "CollisionShape3D", false, false).size()
			var nameplate := rb2.get_node_or_null("Nameplate") as Label3D
			_check(col_count >= 1, "remote proxy creates CollisionShape3D hitbox")
			_check(nameplate != null and nameplate.text == "PeerTwo",
					"remote proxy creates Label3D Nameplate (%s)" % (nameplate.text if nameplate else "null"))
			_check(not rb2.visible, "remote proxy stays hidden until first live state packet arrives")

			# Simulate peer-2 state update through the backend bridge
			var mock: Node = sb.get("mock")
			mock.call("simulate_remote_state", {
				"id": "peer-2",
				"p": [18.0, 0.6, -12.0],
				"r": [0.0, 0.0, 0.0, 1.0],
				"t": true,
				"d": false,
			})
			await process_frame
			_check(rb2.visible and rb2.global_position.distance_to(Vector3(18.0, 0.6, -12.0)) < 0.05,
					"remote state packet reveals and snaps peer-2 to (18, 0.6, -12)")

			# Simulate remote shot from near peer-2
			var before_children := net.get_child_count()
			mock.call("simulate_remote_shot", {
				"id": "peer-2",
				"o": [18.6, 0.9, -11.4],
				"d": [0.0, 0.0, 1.0],
				"token": "shot-peer-2",
			})
			await process_frame
			_check(net.get_child_count() > before_children, "remote peer shot spawns projectile near peer-2")

			# B-P1-1 regression: remote meteor/rocket flood is throttled per weapon cooldown
			var before_meteor := net.get_child_count()
			for mi in range(4):
				mock.call("simulate_remote_shot", {
					"id": "peer-2",
					"w": "meteor",
					"o": [18.6, 0.9, -11.4],
					"d": [0.0, 0.0, 14.0],
					"token": "meteor-flood-%d" % mi,
				})
			await process_frame
			_check(net.get_child_count() - before_meteor == 1,
					"B-P1-1: remote meteor flood spawns at most 1 strike per 5.5s window (got %d)" % (net.get_child_count() - before_meteor))

			# B-P1-5 regression: non-roster rogue state packet cannot spawn a ghost proxy
			mock.call("simulate_remote_state", {
				"id": "rogue-non-roster",
				"p": [0.0, 0.6, 0.0],
				"r": [0.0, 0.0, 0.0, 1.0],
				"d": false,
			})
			await process_frame
			_check(not (net.get("_remote") as Dictionary).has("rogue-non-roster"),
					"B-P1-5: ArenaNet ignores bike_state from unknown non-roster peer")

			# Death hides proxy; respawn reveals at new position
			mock.call("simulate_remote_state", {
				"id": "peer-2",
				"p": [18.0, 0.6, -12.0],
				"r": [0.0, 0.0, 0.0, 1.0],
				"d": true,
			})
			await process_frame
			_check(not rb2.visible, "death state hides remote proxy")
			mock.call("simulate_remote_state", {
				"id": "peer-2",
				"p": [-24.0, 0.6, 14.0],
				"r": [0.0, 0.0, 0.0, 1.0],
				"d": false,
			})
			for _f in range(12):
				await process_frame
			_check(rb2.visible and rb2.global_position.distance_to(Vector3(-24.0, 0.6, 14.0)) < 1.5,
					"respawn state reveals and moves remote proxy")

	# ---- Arena HUD minimalism: corner 50%-smaller armor, x/y counter, scoreboard dropdown, dual analog pads
	var hud := arena.get_node_or_null("HUD") as CanvasLayer
	var touch_hud := arena.get_node_or_null("TouchHUD") as CanvasLayer
	if hud != null:
		var hb := hud.get_node_or_null("HealthBar") as Control
		var banner := hud.get_node_or_null("Banner") as Label
		var score_toggle := hud.get_node_or_null("ScoreToggle") as Button
		var scoreboard := hud.get_node_or_null("Scoreboard") as Control
		_check(hb != null and hb.size.x <= 140.0 and hb.size.y <= 14.0
				and hb.position.x < 40.0 and hb.position.y < 60.0,
				"Arena HealthBar is 50%% smaller and pinned in top-left corner (%s @ %s)" % [
					str(hb.size) if hb else "null", str(hb.position) if hb else "null"])
		_check(banner != null and banner.text == "0/10" and banner.position.x < 40.0
				and not banner.has_theme_stylebox_override("normal"),
				"Arena Banner shows subtle '0/10' corner score instead of top banner ('%s')" % (banner.text if banner else "null"))
		_check(hud.get_node_or_null("Crosshair") == null, "No center Crosshair obstructing view")
		if score_toggle != null and scoreboard != null:
			_check(not scoreboard.visible, "Arena Scoreboard starts collapsed as dropdown")
			score_toggle.pressed.emit()
			_check(scoreboard.visible, "ScoreToggle opens Scoreboard dropdown")
			score_toggle.pressed.emit()
			_check(not scoreboard.visible, "ScoreToggle closes Scoreboard dropdown")
		else:
			_check(false, "Arena ScoreToggle and Scoreboard dropdown exist")
	if touch_hud != null:
		var left_pad := touch_hud.get_node_or_null("AnalogSteer") as Control
		var right_pad := touch_hud.get_node_or_null("AnalogDrive") as Control
		_check(left_pad != null and left_pad.size.x >= 44.0 and left_pad.size.y >= 44.0
				and right_pad != null and right_pad.size.x >= 44.0 and right_pad.size.y >= 44.0,
				"Arena has both analog pads at >= 44px (%s / %s)" % [
					str(left_pad.size) if left_pad else "null",
					str(right_pad.size) if right_pad else "null"])
		_check(touch_hud.get_node_or_null("BtnGas") == null
				and touch_hud.get_node_or_null("BtnDodgeLeft") == null
				and touch_hud.get_node_or_null("BtnDodgeRight") == null,
				"Arena touch overlay has no GAS / L-R dodge buttons")

	# Check local bike spawn slot assignment for host vs guest
	if sp0 != null and local_bike != null and net != null:
		sb.set("user_id", "peer-2")
		net.call("_place_local_bike_at_roster_slot")
		_check(local_bike.global_position.distance_to(sp0.global_position + Vector3(0, 0.6, 0)) > 5.0,
				"non-first roster peer spawns at its own SpawnPoint instead of stacking on SpawnPoint0")
		sb.set("user_id", "mock-host")

	arena.free()

	# ---- 4: TaloBackend socket wire relay for guest + host "bike_state" & float JSON alias IDs
	var tb: Node = (load("res://src/net/TaloBackend.gd") as GDScript).new()
	root.add_child(tb)
	tb.set("is_ready", true)
	tb.set("user_id", "12345678")
	tb.set("_channel_id", 42)
	tb.set("_lobby", {"id": "42", "host_id": "12345678", "status": "playing", "settings": {}})
	tb.set("_roster", {
		"12345678": {"user_id": "12345678", "display_name": "Host", "score": 0},
		"23456789": {"user_id": "23456789", "display_name": "Guest", "score": 0},
	})
	var received: Array = []
	tb.connect("broadcast_received", func(ev: String, pay: Variant) -> void:
		received.append([ev, pay]))
	var pg_updates := [0]
	tb.connect("postgres_change", func(_d: Dictionary) -> void:
		pg_updates[0] += 1)

	# Float-parsed JSON alias IDs (e.g. 23456789.0) must match integer string IDs cleanly
	var guest_bike := JSON.stringify({"k": "bike_state", "p": {
		"id": "23456789", "p": [1.0, 0.6, 2.0], "r": [0.0, 0.0, 0.0, 1.0], "d": false}})
	await tb.call("_on_socket_message", "v1.channels.message", {
		"channel": {"id": 42.0},
		"playerAlias": {"id": 23456789.0},
		"message": guest_bike,
	})
	_check(received.size() == 1 and str(received[0][0]) == "state"
			and str((received[0][1] as Dictionary).get("id", "")) == "23456789",
			"TaloBackend relays guest bike_state to ArenaNet as 'state' (incl. large float JSON alias IDs)")

	# Host bike_state must relay to peers WITHOUT triggering lobby/roster postgres_change spam
	var host_bike := JSON.stringify({"k": "bike_state", "p": {
		"id": "12345678", "p": [5.0, 0.6, -3.0], "r": [0.0, 0.0, 0.0, 1.0], "d": false}})
	await tb.call("_on_socket_message", "v1.channels.message", {
		"channel": {"id": 42.0},
		"playerAlias": {"id": 12345678.0},
		"message": host_bike,
	})
	_check(received.size() == 2 and pg_updates[0] == 0,
			"TaloBackend relays host bike_state without triggering lobby/roster state churn")

	# Spoofed bike_state claiming another user's id must be dropped
	var spoof_bike := JSON.stringify({"k": "bike_state", "p": {
		"id": "12345678", "p": [99.0, 0.6, 99.0], "r": [0.0, 0.0, 0.0, 1.0], "d": false}})
	await tb.call("_on_socket_message", "v1.channels.message", {
		"channel": {"id": 42.0},
		"playerAlias": {"id": 23456789.0},
		"message": spoof_bike,
	})
	_check(received.size() == 2, "TaloBackend drops bike_state whose id disagrees with sender alias")

	tb.free()
	match_node.set("lobby", prev_lobby)
	match_node.set("players", prev_players)
	print("MULTIPLAYER: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
