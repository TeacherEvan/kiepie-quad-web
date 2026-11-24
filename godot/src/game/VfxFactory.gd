extends RefCounted
class_name VfxFactory
## Lightweight facade delegating to VfxSprites, VfxCore, and VfxHeavy.

const S := preload("res://src/game/VfxSprites.gd")
const CORE := preload("res://src/game/VfxCore.gd")
const HEAVY := preload("res://src/game/VfxHeavy.gd")

const COL_CORE := S.COL_CORE
const COL_AMBER := S.COL_AMBER
const COL_ORANGE := S.COL_ORANGE
const COL_EMBER := S.COL_EMBER
const COL_SMOKE := S.COL_SMOKE
const COL_SMOKE_DARK := S.COL_SMOKE_DARK
const COL_BRASS := S.COL_BRASS
const COL_STEAM := S.COL_STEAM
const COL_CHAR := S.COL_CHAR
const COL_GLASS := S.COL_GLASS
const COL_DUST := S.COL_DUST

const MAX_SCORCH := S.MAX_SCORCH
const MAX_SCAR := S.MAX_SCAR
const MAX_IMPACT_LIGHTS := S.MAX_IMPACT_LIGHTS
const MAX_WRECKS := S.MAX_WRECKS
const MAX_DAMAGE_NUMBERS := S.MAX_DAMAGE_NUMBERS
const MAX_EXPLOSION_SHARDS := S.MAX_EXPLOSION_SHARDS
const MAX_CASINGS := S.MAX_CASINGS
const MUSHROOM_AABB := S.MUSHROOM_AABB


static func _q() -> float:
	return S._q()


static func prewarm(host: Node3D = null) -> void:
	S.prewarm(host)


static func _emissive(color: Color, energy: float = 2.5) -> StandardMaterial3D:
	return S._emissive(color, energy)


static func _additive(color: Color, energy: float = 2.5) -> StandardMaterial3D:
	return S._additive(color, energy)


static func _ramp(colors: Array) -> GradientTexture1D:
	return S._ramp(colors)


static func _curve(keys: Array) -> CurveTexture:
	return S._curve(keys)


static func _plane_basis(normal: Vector3) -> Basis:
	return S._plane_basis(normal)


static func _cap_group(parent: Node, group: String, cap: int) -> void:
	S._cap_group(parent, group, cap)


static func _soft_sprite() -> GradientTexture2D:
	return S._soft_sprite()


static func _streak_sprite() -> ImageTexture:
	return S._streak_sprite()


static func _flare_sprite() -> ImageTexture:
	return S._flare_sprite()


static func _ring_sprite() -> ImageTexture:
	return S._ring_sprite()


static func _smoke_sprite() -> ImageTexture:
	return S._smoke_sprite()


static func _fire_sprite() -> ImageTexture:
	return S._fire_sprite()


static func _scorch_sprite() -> ImageTexture:
	return S._scorch_sprite()


static func _sprite_quad(additive: bool, key: String, quad_size: float) -> QuadMesh:
	return S._sprite_quad(additive, key, quad_size)


static func _ring_quad(parent: Node3D, pos: Vector3, radius: float,
		color: Color, grow: float = 1.8, duration: float = 0.25, matte: bool = false,
		normal: Vector3 = Vector3.UP) -> MeshInstance3D:
	return S._ring_quad(parent, pos, radius, color, grow, duration, matte, normal)


static func _particle(parent: Node3D, pos: Vector3, amount: int, lifetime: float,
		dir: Vector3, spread: float, speed_min: float, speed_max: float,
		colors: Array, size: float, gravity: Vector3 = Vector3(0, -2.0, 0),
		additive: bool = false, opts: Dictionary = {}) -> GPUParticles3D:
	return S._particle(parent, pos, amount, lifetime, dir, spread, speed_min, speed_max,
			colors, size, gravity, additive, opts)


static func _static_cue(parent: Node3D, pos: Vector3, color: Color,
		radius: float, duration: float = 0.20) -> void:
	S._static_cue(parent, pos, color, radius, duration)


static func muzzle_flash(parent: Node3D, pos: Vector3, dir: Vector3, color: Color) -> void:
	CORE.muzzle_flash(parent, pos, dir, color)


static func casing(parent: Node3D, pos: Vector3, eject_dir: Vector3) -> void:
	CORE.casing(parent, pos, eject_dir)


static func impact(parent: Node3D, pos: Vector3, color: Color,
		dir: Vector3 = Vector3.ZERO, surface: String = "metal",
		normal: Vector3 = Vector3.UP) -> void:
	CORE.impact(parent, pos, color, dir, surface, normal)


static func scar(parent: Node3D, pos: Vector3, normal: Vector3,
		kind: String = "metal") -> void:
	CORE.scar(parent, pos, normal, kind)


static func shield_block(parent: Node3D, pos: Vector3, color: Color) -> void:
	CORE.shield_block(parent, pos, color)


static func dust_puff(parent: Node3D, local_pos: Vector3, amount: int = 64) -> void:
	CORE.dust_puff(parent, local_pos, amount)


static func dust_ring(parent: Node3D, pos: Vector3, radius: float = 1.2,
		amount: float = 5.0) -> void:
	CORE.dust_ring(parent, pos, radius, amount)


static func roost(parent: Node3D, pos: Vector3, forward: Vector3) -> void:
	CORE.roost(parent, pos, forward)


static func tire_smoke(parent: Node3D, pos: Vector3) -> void:
	CORE.tire_smoke(parent, pos)


static func scorch(parent: Node3D, pos: Vector3, blast_scale: float = 1.0) -> void:
	CORE.scorch(parent, pos, blast_scale)


static func smash_burst(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	CORE.smash_burst(parent, pos, size)


static func pickup_burst(parent: Node3D, pos: Vector3, color: Color) -> void:
	CORE.pickup_burst(parent, pos, color)


static func damage_number(parent: Node3D, pos: Vector3, amount: float, color: Color) -> void:
	CORE.damage_number(parent, pos, amount, color)


static func underglow(parent: Node3D, color: Color) -> Node3D:
	return CORE.underglow(parent, color)


static func shield_pulse(parent: Node3D, pos: Vector3, color: Color) -> void:
	CORE.shield_pulse(parent, pos, color)


static func explosion(parent: Node3D, pos: Vector3, color: Color, scale: float = 1.0) -> void:
	HEAVY.explosion(parent, pos, color, scale)


static func mushroom_cloud_explosion(parent: Node3D, pos: Vector3,
		color: Color = Color(1.0, 0.26, 0.04), scale: float = 2.65) -> void:
	HEAVY.mushroom_cloud_explosion(parent, pos, color, scale)


static func particle_explosion(parent: Node3D, pos: Vector3, color: Color, scale: float = 1.0,
		mushroom: bool = false) -> void:
	HEAVY.particle_explosion(parent, pos, color, scale, mushroom)


static func dramatic_death_explosion(parent: Node3D, pos: Vector3, basis: Basis,
		color: Color, is_pogo: bool = false, vehicle_profile: String = "") -> void:
	HEAVY.dramatic_death_explosion(parent, pos, basis, color, is_pogo, vehicle_profile)


static func lightning_strike_explosion(parent: Node3D, pos: Vector3,
		scale: float = 1.35) -> void:
	HEAVY.lightning_strike_explosion(parent, pos, scale)


static func cash_explosion(parent: Node3D, pos: Vector3, big: bool = false) -> void:
	HEAVY.cash_explosion(parent, pos, big)
