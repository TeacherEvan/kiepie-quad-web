extends Area3D
## Floating combat pickup placed in the arena by tools/build_arena.gd.
## A "bike" physics body driving into it receives apply_pickup(kind); the
## pickup then hides for RESPAWN_SEC seconds and comes back. Self-contained:
## it builds its own trigger + visuals in _ready so it works headlessly too.

const VFX := preload("res://src/game/VfxFactory.gd")

const RESPAWN_SEC := 12.0

## One of: "shield", "rapid", "repair", "overdrive".
@export var kind: String = "repair"

var _visual: MeshInstance3D
var _glow: OmniLight3D
var _trigger: CollisionShape3D
var _t := 0.0
var _collected := false


func _color() -> Color:
	match kind:
		"shield":
			return Color(0.18, 0.92, 1.00, 1.0)   # cyan
		"rapid":
			return Color(1.00, 0.86, 0.16, 1.0)   # yellow
		"repair":
			return Color(0.22, 1.00, 0.42, 1.0)   # green
		"overdrive":
			return Color(1.00, 0.20, 0.85, 1.0)   # magenta
		_:
			return Color(0.80, 0.80, 0.80, 1.0)


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	monitoring = true
	monitorable = false

	# Physics trigger (layer 2, mask 1 -> detects the bike on layer 1).
	_trigger = CollisionShape3D.new()
	_trigger.name = "Trigger"
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6
	_trigger.shape = sphere
	add_child(_trigger)

	# Floating glowing torus.
	var c := _color()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.26
	torus.outer_radius = 0.42
	torus.rings = 16
	torus.ring_segments = 24
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	torus.material = mat
	_visual = MeshInstance3D.new()
	_visual.name = "Gem"
	_visual.mesh = torus
	_visual.rotation_degrees.x = 20.0
	add_child(_visual)

	_glow = OmniLight3D.new()
	_glow.name = "Glow"
	_glow.light_color = c
	_glow.light_energy = 2.0
	_glow.omni_range = 3.0
	add_child(_glow)

	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	if _collected:
		return
	if is_instance_valid(_visual):
		_visual.rotation.y += delta * 1.6
		_visual.position.y = sin(_t * 2.2) * 0.12
	if is_instance_valid(_glow):
		_glow.light_energy = 1.7 + sin(_t * 3.0) * 0.35


func _on_body_entered(body: Node) -> void:
	if _collected or body == null:
		return
	if not body.is_in_group("bike"):
		return
	var handler := _pickup_handler(body)
	if handler == null:
		return
	handler.call("apply_pickup", kind)
	_collect()


func _pickup_handler(body: Node) -> Node:
	# Primary path: the body itself exposes apply_pickup (contract).
	if body.has_method("apply_pickup"):
		return body
	# The arena bike is a VehicleBody3D with apply_pickup on its CombatController
	# child. Resolve that handler so pickups work with the shipped scene.
	for child in body.get_children():
		if child.has_method("apply_pickup"):
			return child
	return null


func _collect() -> void:
	_collected = true
	set_deferred("monitoring", false)
	if is_instance_valid(_trigger):
		_trigger.set_deferred("disabled", true)
	if is_instance_valid(_visual):
		_visual.visible = false
	if is_instance_valid(_glow):
		_glow.visible = false

	VFX.pickup_burst(_fx_parent(), global_position, _color())

	var tree := get_tree()
	if tree != null:
		var timer := tree.create_timer(RESPAWN_SEC)
		timer.timeout.connect(_respawn)


func _respawn() -> void:
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_collected = false
	set_deferred("monitoring", true)
	if is_instance_valid(_trigger):
		_trigger.set_deferred("disabled", false)
	if is_instance_valid(_visual):
		_visual.visible = true
	if is_instance_valid(_glow):
		_glow.visible = true


func _fx_parent() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene is Node3D:
		return scene as Node3D
	var parent := get_parent()
	if parent is Node3D:
		return parent as Node3D
	return null
