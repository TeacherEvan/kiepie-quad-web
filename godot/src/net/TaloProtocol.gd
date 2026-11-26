extends RefCounted
## Pure stateless protocol & validation helpers for TaloBackend.

const PROTOCOL_VERSION := "3"
const STALE_LOBBY_S := 90.0
const MIN_LAP_SECONDS := 12.0


static func new_code() -> String:
	var alphabet := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code := ""
	for i in range(5):
		code += alphabet[randi() % alphabet.length()]
	return code


static func parse_dict(text: String) -> Dictionary:
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


static func is_hex_color(col: String) -> bool:
	if col.length() != 7 or col[0] != "#":
		return false
	for i in range(1, 7):
		var c := col.substr(i, 1)
		var ok := (c >= "0" and c <= "9") or (c >= "a" and c <= "f") or (c >= "A" and c <= "F")
		if not ok:
			return false
	return true


static func protocol_ok(channel) -> bool:
	if channel == null:
		return false
	return str(channel.get_prop("protocol_version", "")) == PROTOCOL_VERSION


static func is_channel_joinable(channel, now_unix: float, max_stale_sec: float, parse_iso_fn: Callable) -> bool:
	if channel == null or not protocol_ok(channel):
		return false
	if str(channel.get_prop("status", "waiting")) != "waiting":
		return false
	if int(channel.member_count) <= 0:
		return false
	var host_id := str(channel.get_prop("host_id", ""))
	if host_id == "" or channel.owner_alias == null or str(channel.owner_alias.id) != host_id:
		return false
	var roster := parse_dict(str(channel.get_prop("roster", "{}")))
	if not roster.has(host_id):
		return false
	var settings := parse_dict(str(channel.get_prop("settings", "{}")))
	var max_players := clampi(int(settings.get("max_players", 8)), 2, 8)
	if int(channel.member_count) >= max_players:
		return false
	var hb := float(str(channel.get_prop("heartbeat", "0")))
	if hb <= 0.0 and parse_iso_fn.is_valid():
		hb = float(parse_iso_fn.call(str(channel.updated_at)))
	if hb > 0.0 and (now_unix - hb) > max_stale_sec:
		return false
	return true


static func build_prop_array(lobby: Dictionary, roster: Dictionary, extra: Dictionary = {}) -> Array:
	var props := {
		"code": str(lobby.get("code", "")),
		"name": str(lobby.get("name", "")),
		"settings": JSON.stringify(lobby.get("settings", {})),
		"host_id": str(lobby.get("host_id", "")),
		"status": str(lobby.get("status", "")),
		"started_at": str(lobby.get("started_at", "")),
		"winner_id": str(lobby.get("winner_id", "")),
		"heartbeat": str(int(Time.get_unix_time_from_system())),
		"protocol_version": PROTOCOL_VERSION,
		"roster": JSON.stringify(roster),
	}
	for k in extra.keys():
		props[k] = extra[k]
	var prop_array: Array = []
	for k in props.keys():
		prop_array.append({"key": k, "value": str(props[k])})
	return prop_array


static func sanitize_join_row(uid: String, p: Dictionary, prev: Dictionary) -> Dictionary:
	var col := str(p.get("color", "#40c8ff"))
	if not is_hex_color(col):
		col = "#40c8ff"
	var raw_veh := str(p.get("vehicle", prev.get("vehicle", ""))) if p.has("vehicle") else str(prev.get("vehicle", ""))
	return {
		"user_id": uid,
		"display_name": str(p.get("display_name", "RIDER")).substr(0, 32),
		"color": col,
		"vehicle": VehicleRegistry.sanitize_preference(raw_veh),
		"score": int(prev.get("score", 0)),
		"kills": int(prev.get("kills", 0)),
		"laps": int(prev.get("laps", 0)),
		"is_ready": bool(prev.get("is_ready", false)),
		"respawn_at": str(prev.get("respawn_at", "")),
	}


static func prune_rate_window(timestamps: Array, now_s: float, window_s: float, max_count: int) -> Dictionary:
	var kept: Array = []
	for t in timestamps:
		if now_s - float(t) < window_s:
			kept.append(t)
	if kept.size() >= max_count:
		return {"ok": false, "kept": kept}
	kept.append(now_s)
	return {"ok": true, "kept": kept}


static func pick_leader(roster: Dictionary) -> String:
	var best := ""
	var best_score := -1
	var uids := roster.keys()
	uids.sort()  # deterministic tie-break: lowest user_id wins a score tie
	for uid in uids:
		var s := int((roster[uid] as Dictionary).get("score", 0))
		if s > best_score:
			best = str(uid)
			best_score = s
	return best


static func evaluate_outcome(lobby: Dictionary, roster: Dictionary, actor_id: String = "") -> Dictionary:
	if str(lobby.get("status", "")) == "finished":
		return {"finished": false, "winner_id": str(lobby.get("winner_id", ""))}
	var s_dict := lobby.get("settings", {}) as Dictionary
	var gmode := str(s_dict.get("game_mode", "battle_royale"))
	var target_kills := maxi(1, int(s_dict.get("kill_target", 10)))
	var target_laps := maxi(1, int(s_dict.get("lap_target", 3)))
	var uids: Array = []
	if actor_id != "" and roster.has(actor_id):
		uids = [actor_id]
	else:
		uids = roster.keys()
		uids.sort()
	for uid in uids:
		var row: Dictionary = roster[uid] as Dictionary
		if gmode == "death_race":
			if int(row.get("laps", 0)) >= target_laps:
				return {"finished": true, "winner_id": str(uid)}
		else:
			if int(row.get("score", 0)) >= target_kills:
				return {"finished": true, "winner_id": str(uid)}
	return {"finished": false, "winner_id": ""}
