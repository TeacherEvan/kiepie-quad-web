extends Area3D
## Centripetal normal controller for 360° vertical stunt loops in Death Race.
## Tracks bikes inside the loop cylinder and sets bike.loop_up toward the loop's
## central axis so KiepieBike._integrate_forces() aligns the righting spring and
## applies centripetal track adhesion all the way around the 360° inversion.

@export var loop_radius := 9.0
@export var loop_half_width := 5.5

var _bikes: Array[Node3D] = []


func _ready() -> void:
	add_to_group("loop_zone", true)
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if body is Node3D and body.is_in_group("bike") and "loop_up" in body:
		if not _bikes.has(body as Node3D):
			_bikes.append(body as Node3D)


func _on_body_exited(body: Node) -> void:
	if body is Node3D and _bikes.has(body as Node3D):
		_bikes.erase(body as Node3D)
		if is_instance_valid(body) and "loop_up" in body:
			body.set("loop_up", Vector3.ZERO)


func _exit_tree() -> void:
	for b in _bikes:
		if is_instance_valid(b) and "loop_up" in b:
			b.set("loop_up", Vector3.ZERO)
	_bikes.clear()


func _physics_process(_delta: float) -> void:
	if _bikes.is_empty():
		return
	var local_up := global_transform.basis.y.normalized()
	var center := global_position + local_up * loop_radius
	# Loop axis is the local X axis of the LoopZone node (travel is along local Z)
	var axis_x := global_transform.basis.x.normalized()
	for i in range(_bikes.size() - 1, -1, -1):
		var b := _bikes[i]
		if not is_instance_valid(b):
			_bikes.remove_at(i)
			continue
		var rel := b.global_position - center
		var axial := axis_x * rel.dot(axis_x)
		var radial_to_center := -(rel - axial)
		if radial_to_center.length_squared() > 0.25:
			b.set("loop_up", radial_to_center.normalized())
		else:
			b.set("loop_up", Vector3.UP)
