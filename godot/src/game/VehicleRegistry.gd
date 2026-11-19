class_name VehicleRegistry
extends RefCounted
## Deterministic vehicle assignment: every peer derives the same vehicle from
## the player id (FNV-1a-32 over UTF-8 bytes; the raw low bit is replaced by a
## high-middle one — see for_player). No new network messages; a future
## vehicle is one line in VEHICLES (hashes reshuffle across all peers
## consistently, so mixed-version lobbies must bump PROTOCOL_VERSION as usual).

const VEHICLE_BIKE := &"KiepieBike"
const VEHICLE_POGO := &"PogoNardus"
const VEHICLES: Array[StringName] = [VEHICLE_BIKE, VEHICLE_POGO]
const _FNV_OFFSET := 2166136261
const _FNV_PRIME := 16777619

## Short weapon-profile id consumed by SideCannons/CombatController ("bike"|"pogo").
static func profile(vehicle: StringName) -> String:
	return "pogo" if vehicle == VEHICLE_POGO else "bike"

static func _fnv32(player_id: String) -> int:
	var h := _FNV_OFFSET
	for b in player_id.to_utf8_buffer():
		h = ((h ^ b) * _FNV_PRIME) & 0xffffffff
	return h

static func for_player(player_id: String) -> StringName:
	# The raw low bit of FNV-1a is unreliable as a bin on short id strings (the
	# exact-integer audit measured it ~50/50 over sequential Talo alias ids;
	# the earlier JS readings were double-precision artifacts). Read a
	# high-middle bit of the hash instead — measured ~53% pogo over sequential
	# ids, ~49% over random ints and uuids.
	if (_fnv32(player_id) >> 15) & 1:
		return VEHICLE_POGO
	return VEHICLE_BIKE

## Roster-aware deterministic assignment: guarantees AT LEAST ONE player in any
## non-empty match roster is assigned NARDUS (VEHICLE_POGO), with zero extra
## wire traffic and 100% agreement across all peers.
static func for_player_in_roster(player_id: String, roster_ids: Array) -> StringName:
	var base := for_player(player_id)
	if base == VEHICLE_POGO or roster_ids.is_empty():
		return base
	var sorted_ids: Array[String] = []
	for raw in roster_ids:
		var s := str(raw)
		if s != "" and not sorted_ids.has(s):
			sorted_ids.append(s)
	if player_id != "" and not sorted_ids.has(player_id):
		sorted_ids.append(player_id)
	if sorted_ids.is_empty():
		return base
	sorted_ids.sort()
	for uid in sorted_ids:
		if for_player(uid) == VEHICLE_POGO:
			return base
	var promoted := sorted_ids[0]
	var best_hash := -1
	for uid in sorted_ids:
		var h := _fnv32(uid)
		if h > best_hash:
			best_hash = h
			promoted = uid
	return VEHICLE_POGO if player_id == promoted else VEHICLE_BIKE

static func is_valid(vehicle: StringName) -> bool:
	return vehicle == VEHICLE_BIKE or vehicle == VEHICLE_POGO

static func model_path(vehicle: StringName) -> String:
	match vehicle:
		VEHICLE_POGO:
			return "res://assets/Pogo_Nardus.glb"
		_:
			return "res://assets/Kiepie_Bike.glb"

static func display_name(vehicle: StringName) -> String:
	match vehicle:
		VEHICLE_POGO:
			return "NARDUS"
		_:
			return "KIEPIE QUAD"

## Seconds between shots (normal / rapid pickup).
static func cooldown(vehicle: StringName) -> float:
	match vehicle:
		VEHICLE_POGO:
			return 0.40
		_:
			return 0.20

static func rapid_cooldown(vehicle: StringName) -> float:
	match vehicle:
		VEHICLE_POGO:
			return 0.18
		_:
			return 0.09

## Multiplier applied on top of Match.damage().
static func damage_multiplier(vehicle: StringName) -> float:
	match vehicle:
		VEHICLE_POGO:
			return 2.0
		_:
			return 1.0

static func spread(vehicle: StringName) -> float:
	match vehicle:
		VEHICLE_POGO:
			return 0.075
		_:
			return 0.055

static func fire_sfx(vehicle: StringName) -> String:
	match vehicle:
		VEHICLE_POGO:
			return "pop"
		_:
			return "fire"

static func is_pogo(vehicle: StringName) -> bool:
	return vehicle == VEHICLE_POGO
