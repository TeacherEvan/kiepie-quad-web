extends Node3D
## Death Race lap and checkpoint controller.
## Tracks ordered checkpoints (Checkpoint0..Checkpoint3 -> FinishLine) so riders
## cannot reverse-cheat across the finish line, updates the bike's respawn point
## at every cleared checkpoint, updates the MatchHud lap banner, and finishes
## the race (triggering the Victory Splash video) when completed_laps >= lap_target.

signal checkpoint_cleared(cp_index: int, total_checkpoints: int)
signal lap_completed(completed_laps: int, lap_target: int)
signal race_won(winner_id: String)

@export var local_bike_path: NodePath = ^"../KiepieBike"
@export var default_lap_target := 3

var current_lap := 1
var completed_laps := 0
var next_checkpoint := 0
var total_checkpoints := 4
var race_finished := false

var _bike: Node3D = null
var _checkpoints: Array[Area3D] = []
var _finish_line: Area3D = null


func _ready() -> void:
	add_to_group("race_tracker", true)
	_bike = get_node_or_null(local_bike_path) as Node3D
	_setup_solo_or_match_mode()
	_bind_triggers()
	_sync_hud()


func _setup_solo_or_match_mode() -> void:
	# If DeathRace.tscn is launched directly in Practice / Solo mode (Match not playing),
	# enable practice_mode on CombatController so weapons and respawns work standalone,
	# and ensure the local player is in Match.players so VehicleRegistry guarantees NARDUS!
	var playing := Match != null and Match.is_playing()
	if _bike != null:
		var combat := _bike.get_node_or_null("CombatController")
		if combat != null and not playing:
			combat.set("practice_mode", true)
		var uid := str(Supabase.user_id) if (Supabase != null and str(Supabase.user_id) != "") else "mock-host"
		if Match != null and Match.players.is_empty():
			Match.players[uid] = {
				"user_id": uid,
				"display_name": Settings.display_name(),
				"color": Settings.player_color(),
				"score": 0,
				"is_ready": true,
			}
		if _bike.has_method("refresh_vehicle_assignment"):
			_bike.call("refresh_vehicle_assignment")


func _bind_triggers() -> void:
	_checkpoints.clear()
	var scene_root := get_parent()
	if scene_root == null:
		return
	var idx := 0
	while true:
		var cp := scene_root.get_node_or_null("Checkpoint%d" % idx) as Area3D
		if cp == null:
			break
		var bound_idx := idx
		cp.body_entered.connect(func(body: Node) -> void: _on_checkpoint_entered(bound_idx, cp, body))
		_checkpoints.append(cp)
		idx += 1
	total_checkpoints = maxi(1, _checkpoints.size())
	_finish_line = scene_root.get_node_or_null("FinishLine") as Area3D
	if _finish_line != null:
		_finish_line.body_entered.connect(_on_finish_line_entered)


func lap_target() -> int:
	if Match != null and Match.has_method("lap_target") and not Match.lobby.is_empty():
		return int(Match.call("lap_target"))
	return maxi(1, default_lap_target)


func _on_checkpoint_entered(cp_idx: int, cp_area: Area3D, body: Node) -> void:
	if race_finished or body != _bike or _bike == null:
		return
	if cp_idx != next_checkpoint:
		return
	next_checkpoint += 1
	# Advance respawn transform to this checkpoint facing along its forward (+Z) axis
	if _bike.has_method("set_spawn"):
		var spawn_xf := Transform3D(cp_area.global_transform.basis.orthonormalized(),
				cp_area.global_position + Vector3(0.0, 0.65, 0.0))
		_bike.call("set_spawn", spawn_xf)
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", "pickup", -2.0, 1.15)
	checkpoint_cleared.emit(next_checkpoint, total_checkpoints)
	_sync_hud()
	var hud := get_tree().get_first_node_in_group("match_hud") if get_tree() != null else null
	if hud != null and hud.has_method("announce"):
		hud.call("announce", "CHECKPOINT %d / %d" % [next_checkpoint, total_checkpoints])


func _on_finish_line_entered(body: Node) -> void:
	if race_finished or body != _bike or _bike == null:
		return
	if next_checkpoint < total_checkpoints:
		return
	next_checkpoint = 0
	completed_laps += 1
	var target := lap_target()
	if _finish_line != null and _bike.has_method("set_spawn"):
		var spawn_xf := Transform3D(_finish_line.global_transform.basis.orthonormalized(),
				_finish_line.global_position + Vector3(0.0, 0.65, 0.0))
		_bike.call("set_spawn", spawn_xf)
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", "kill" if completed_laps >= target else "pickup")
	lap_completed.emit(completed_laps, target)

	if Match != null and Match.is_playing():
		var shot_res: Dictionary = await Match.issue_shot()
		var tok := str(shot_res.get("token", ""))
		if tok != "":
			await Match.register_lap(tok)

	if completed_laps >= target:
		race_finished = true
		current_lap = target
		_sync_hud()
		var uid := str(Supabase.user_id) if (Supabase != null and str(Supabase.user_id) != "") else "mock-host"
		race_won.emit(uid)
		# In solo/practice mode (or if backend didn't already transition Match), fire HUD finish + victory splash
		if Match == null or not Match.is_finished():
			var hud := get_tree().get_first_node_in_group("match_hud") if get_tree() != null else null
			if hud != null and hud.has_method("_on_match_finished"):
				hud.call("_on_match_finished", uid)
	else:
		current_lap = completed_laps + 1
		_sync_hud()
		var hud := get_tree().get_first_node_in_group("match_hud") if get_tree() != null else null
		if hud != null and hud.has_method("announce"):
			hud.call("announce", "FINAL LAP!" if current_lap == target else ("LAP %d / %d" % [current_lap, target]))


func _sync_hud() -> void:
	var hud := get_tree().get_first_node_in_group("match_hud") if get_tree() != null else null
	if hud != null and hud.has_method("set_race_status"):
		hud.call("set_race_status", mini(current_lap, lap_target()), lap_target(), next_checkpoint, total_checkpoints)
