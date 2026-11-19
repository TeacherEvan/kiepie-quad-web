class_name VehicleRegistry
extends RefCounted
## Deterministic vehicle assignment: every peer derives the same vehicle from
## the player id (FNV-1a-32 over UTF-8 bytes; the raw low bit is replaced by a
## high-middle one — see for_player). No new network messages; a future
## vehicle is one line in VEHICLES (hashes reshuffle across all peers
## consistently, so mixed-version lobbies must bump PROTOCOL_VERSION as usual).

const VEHICLE_BIKE := &"KiepieBike"
const VEHICLE_POGO := &"PogoPrincess"
const VEHICLES: Array[StringName] = [VEHICLE_BIKE, VEHICLE_POGO]
const _FNV_OFFSET := 2166136261
const _FNV_PRIME := 16777619

## Short weapon-profile id consumed by SideCannons/CombatController ("bike"|"pogo").
static func profile(vehicle: StringName) -> String:
	return "pogo" if vehicle == VEHICLE_POGO else "bike"

static func for_player(player_id: String) -> StringName:
	var h := _FNV_OFFSET
	for b in player_id.to_utf8_buffer():
		h = ((h ^ b) * _FNV_PRIME) & 0xffffffff
	# The raw low bit of FNV-1a is unreliable as a bin on short id strings (the
	# exact-integer audit measured it ~50/50 over sequential Talo alias ids;
	# the earlier JS readings were double-precision artifacts). Read a
	# high-middle bit of the hash instead — measured ~53% pogo over sequential
	# ids, ~49% over random ints and uuids.
	if (h >> 15) & 1:
		return VEHICLE_POGO
	return VEHICLE_BIKE

static func is_valid(vehicle: StringName) -> bool:
	return vehicle == VEHICLE_BIKE or vehicle == VEHICLE_POGO

static func model_path(vehicle: StringName) -> String:
	match vehicle:
		VEHICLE_POGO:
			return "res://assets/Pogo_Princess.glb"
		_:
			return "res://assets/Kiepie_Bike.glb"

static func display_name(vehicle: StringName) -> String:
	match vehicle:
		VEHICLE_POGO:
			return "PRINCESS"
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
