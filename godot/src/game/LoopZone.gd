extends Area3D
## Centripetal normal controller for 360° vertical stunt loops in Death Race.
## Tracks bikes inside the loop cylinder and sets bike.loop_up toward the loop's
## central axis so KiepieBike._integrate_forces() aligns the righting spring and
## applies centripetal track adhesion all the way around the 360° inversion.

@export var loop_radius := 9.5
@export var loop_half_width := 5.5
@export var helical_pitch := 3.6

var _bikes: Array[Node3D] = []
var _climbed: Dictionary = {}


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
		_climbed.erase(body.get_instance_id())
		if is_instance_valid(body):
			if "loop_up" in body:
				body.set("loop_up", Vector3.ZERO)
			if "loop_tangent" in body:
				body.set("loop_tangent", Vector3.ZERO)
			if "loop_center_pull" in body:
				body.set("loop_center_pull", Vector3.ZERO)


func _exit_tree() -> void:
	for b in _bikes:
		if is_instance_valid(b):
			if "loop_up" in b:
				b.set("loop_up", Vector3.ZERO)
			if "loop_tangent" in b:
				b.set("loop_tangent", Vector3.ZERO)
			if "loop_center_pull" in b:
				b.set("loop_center_pull", Vector3.ZERO)
	_bikes.clear()
	_climbed.clear()


func _physics_process(_delta: float) -> void:
	if _bikes.is_empty():
		return
	var bx := global_transform.basis
	if not bx.is_finite() or absf(bx.determinant()) <= 0.01:
		return
	var pruned := false
	for i in range(_bikes.size() - 1, -1, -1):
		var b := _bikes[i]
		if not is_instance_valid(b) or not b.global_position.is_finite() or not b.visible:
			if is_instance_valid(b):
				if "loop_up" in b:
					b.set("loop_up", Vector3.ZERO)
				if "loop_tangent" in b:
					b.set("loop_tangent", Vector3.ZERO)
				if "loop_center_pull" in b:
					b.set("loop_center_pull", Vector3.ZERO)
			_bikes.remove_at(i)
			pruned = true
			continue
		var lp := to_local(b.global_position)
		if not lp.is_finite() or absf(lp.x) > loop_half_width + 4.0 \
				or absf(lp.z) > loop_radius + 6.0 or lp.y < -3.0 or lp.y > loop_radius * 2.5 + 4.0:
			# Bike teleported/respawned/reset out of the loop before body_exited
			# flushed: clear loop normals immediately instead of pulling it sideways.
			if "loop_up" in b:
				b.set("loop_up", Vector3.ZERO)
			if "loop_tangent" in b:
				b.set("loop_tangent", Vector3.ZERO)
			if "loop_center_pull" in b:
				b.set("loop_center_pull", Vector3.ZERO)
			_climbed.erase(b.get_instance_id())
			_bikes.remove_at(i)
			pruned = true
			continue
		var bid := b.get_instance_id()
		if lp.y > 4.0:
			_climbed[bid] = true
		var in_footprint := absf(lp.x) < loop_half_width and absf(lp.z) < loop_radius + 3.0
		if in_footprint and lp.y < 1.0 and lp.z < -0.5:
			_climbed.erase(bid)
		var climbed := bool(_climbed.get(bid, false))
		if in_footprint and ((lp.y < 1.8 and lp.z < -0.4 and not climbed) or (climbed and lp.y < 1.8 and lp.z > 0.4)):
			if "loop_up" in b:
				b.set("loop_up", Vector3.ZERO)
			if "loop_tangent" in b:
				b.set("loop_tangent", Vector3.ZERO)
			if "loop_center_pull" in b:
				b.set("loop_center_pull", Vector3.ZERO)
			continue
		var rel_y := lp.y - loop_radius
		var rel_z := lp.z
		if Vector2(rel_z, rel_y).length_squared() > 0.25:
			var theta := atan2(rel_z, -rel_y)
			if theta < 0.0:
				theta += TAU
			var rup_local := Vector3(0.0, -rel_y, -rel_z).normalized()
			var tang_local := Vector3(helical_pitch / TAU, loop_radius * sin(theta), loop_radius * cos(theta)).normalized()
			var target_x := (theta / TAU - 0.5) * helical_pitch
			var x_err := target_x - lp.x
			var rup_world := (bx * rup_local).normalized()
			var tang_world := (bx * tang_local).normalized()
			var pull := bx.x.normalized() * clampf(x_err * 8.0, -10.0, 10.0) if (in_footprint and lp.y > 0.5) else Vector3.ZERO
			if rup_world.is_finite():
				b.set("loop_up", rup_world)
			if "loop_tangent" in b and tang_world.is_finite():
				b.set("loop_tangent", tang_world)
			if "loop_center_pull" in b and pull.is_finite():
				b.set("loop_center_pull", pull)
		else:
			b.set("loop_up", Vector3.UP)
			if "loop_tangent" in b:
				b.set("loop_tangent", Vector3.ZERO)
			if "loop_center_pull" in b:
				b.set("loop_center_pull", Vector3.ZERO)
	if pruned:
		var live_ids := {}
		for lb in _bikes:
			if is_instance_valid(lb):
				live_ids[lb.get_instance_id()] = true
		for kid in _climbed.keys():
			if not live_ids.has(kid):
				_climbed.erase(kid)
