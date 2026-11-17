extends SceneTree
## Gate: the Blender-authored GLB contains the two cannon muzzle anchors.

var _fail := 0


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		printerr("FAIL ", label)
		_fail += 1


func _find(root: Node, name: String) -> Node3D:
	if root.name == name and root is Node3D:
		return root as Node3D
	for c in root.get_children():
		var found := _find(c, name)
		if found != null:
			return found
	return null


func _initialize() -> void:
	var glb: PackedScene = load("res://assets/Kiepie_Bike.glb")
	_check(glb != null, "GLB loaded")
	if glb == null:
		quit(1)
		return
	var model := glb.instantiate()
	var left := _find(model, "Muzzle_L")
	var right := _find(model, "Muzzle_R")
	if left == null:
		left = _find(model, "Cannon_Bore_L")
	if right == null:
		right = _find(model, "Cannon_Bore_R")
	_check(left != null, "left muzzle anchor exists in GLB")
	_check(right != null, "right muzzle anchor exists in GLB")
	if left != null and right != null:
		_check(left.position.x < -0.2 and right.position.x > 0.2, "muzzles are on opposite sides")
		_check(left.position.z > 0.5 and right.position.z > 0.5, "muzzles sit at the front (+Z)")
		_check(absf(left.position.x + right.position.x) < 0.05, "muzzles are symmetric")
	var mesh_count := model.find_children("*", "MeshInstance3D", true, false).size()
	_check(mesh_count > 100, "model still has full chassis geometry (%d meshes)" % mesh_count)
	model.free()
	quit(1 if _fail > 0 else 0)
