class_name VehicleRegistry
extends RefCounted
## Deterministic vehicle assignment: every peer derives the same vehicle from
## the player id (FNV-1a-32 over UTF-8 bytes; high-middle bit mixer). No new
## network messages; optional player preference ("vehicle" in lobby row)
## overrides the deal when valid.

const VEHICLE_BIKE := &"KiepieBike"
const VEHICLE_POGO := &"PogoNardus"
const VEHICLE_ASTON := &"AstonMartin"
## EVAN is a preference-only "encore" vehicle: selectable in MainMenu and synced
## through the lobby row, but deliberately NOT part of the FNV deal pool. Adding
## a fourth deal vehicle would shift every deterministic hash and silently
## change the mock-host / peer-N fixtures locked by verify_pogo + verify_aston.
const VEHICLE_EVAN := &"EvanSkeleton"
## LEA is likewise preference-only: she is never dealt by the FNV hash pool.
const VEHICLE_LEA := &"LeaUnicorn"
const ALL_IDS: Array[String] = ["auto", "KiepieBike", "PogoNardus", "AstonMartin", "EvanSkeleton", "LeaUnicorn"]
const VEHICLES: Array[StringName] = [VEHICLE_BIKE, VEHICLE_POGO, VEHICLE_ASTON]
const _FNV_OFFSET := 2166136261
const _FNV_PRIME := 16777619

## Short weapon-profile id consumed by SideCannons/CombatController ("bike"|"pogo"|"aston"|"evan").
static func profile(vehicle: StringName) -> String:
	match vehicle:
		VEHICLE_POGO:
			return "pogo"
		VEHICLE_ASTON:
			return "aston"
		VEHICLE_EVAN:
			return "evan"
		VEHICLE_LEA:
			return "lea"
		_:
			return "bike"


static func from_profile(profile_id: String) -> StringName:
	match profile_id:
		"pogo":
			return VEHICLE_POGO
		"aston":
			return VEHICLE_ASTON
		"evan":
			return VEHICLE_EVAN
		"lea":
			return VEHICLE_LEA
		_:
			return VEHICLE_BIKE


static func sanitize_preference(raw: String) -> String:
	match raw:
		"KiepieBike", "PogoNardus", "AstonMartin", "EvanSkeleton", "LeaUnicorn":
			return raw
		_:
			return ""


static func _fnv32(player_id: String) -> int:
	var h := _FNV_OFFSET
	for b in player_id.to_utf8_buffer():
		h = ((h ^ b) * _FNV_PRIME) & 0xffffffff
	return h


static func for_player(player_id: String) -> StringName:
	return VEHICLES[(_fnv32(player_id) >> 12) % VEHICLES.size()]


## Roster-aware deterministic assignment: guarantees AT LEAST ONE player in any
## non-empty match roster is assigned NARDUS (VEHICLE_POGO) when no explicit
## preference overrides, with zero extra wire traffic and 100% agreement.
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
	return VEHICLE_POGO if player_id == promoted else base


static func resolve_for_player(player_id: String, roster_ids: Array = [], preferred: String = "") -> StringName:
	var clean := sanitize_preference(preferred)
	if clean != "":
		return StringName(clean)
	if not roster_ids.is_empty():
		return for_player_in_roster(player_id, roster_ids)
	return for_player(player_id)


static func is_valid(vehicle: StringName) -> bool:
	return vehicle == VEHICLE_BIKE or vehicle == VEHICLE_POGO \
			or vehicle == VEHICLE_ASTON or vehicle == VEHICLE_EVAN \
			or vehicle == VEHICLE_LEA


static func model_path(vehicle: StringName) -> String:
	match vehicle:
		VEHICLE_POGO:
			return "res://assets/Pogo_Nardus.glb"
		VEHICLE_ASTON:
			return "res://assets/Aston_Martin.glb"
		VEHICLE_EVAN:
			return "res://assets/Evan_Skeleton.glb"
		VEHICLE_LEA:
			return "res://assets/Lea_Unicorn.glb"
		_:
			return "res://assets/Kiepie_Bike.glb"


static func display_name(vehicle: StringName) -> String:
	match vehicle:
		VEHICLE_POGO:
			return "NARDUS"
		VEHICLE_ASTON:
			return "BIG-BEN F1"
		VEHICLE_EVAN:
			return "EVAN THE SKELETON"
		VEHICLE_LEA:
			return "LEA UNICORN"
		_:
			return "KIEPIE QUAD"


## Seconds between shots (normal / rapid pickup).
static func cooldown(vehicle: StringName) -> float:
	match vehicle:
		VEHICLE_POGO:
			return 0.40
		VEHICLE_EVAN:
			return 0.22
		VEHICLE_LEA:
			return 0.16
		_:
			return 0.20


static func rapid_cooldown(vehicle: StringName) -> float:
	match vehicle:
		VEHICLE_POGO:
			return 0.18
		VEHICLE_EVAN:
			return 0.10
		VEHICLE_LEA:
			return 0.08
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
		VEHICLE_ASTON:
			return 0.048
		VEHICLE_EVAN:
			return 0.050
		VEHICLE_LEA:
			return 0.018
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


static func is_aston(vehicle: StringName) -> bool:
	return vehicle == VEHICLE_ASTON


static func is_evan(vehicle: StringName) -> bool:
	return vehicle == VEHICLE_EVAN


static func is_lea(vehicle: StringName) -> bool:
	return vehicle == VEHICLE_LEA
