extends RefCounted
class_name BuildingDecor
## Shared facade dressing for tools/build_arena.gd and tools/build_testride.gd.
## Windows are merged into a single mesh (one draw call instead of ~12).
## Everything is a direct child of the building so DestructibleBuilding.smash()
## hides/frees it along with the shell.

static func _mat(color: Color, emissive: bool = false, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.55
	if emissive:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _quad(st: SurfaceTool, c: Vector3, u: Vector3, v: Vector3,
		w: float, h: float) -> void:
	## u = across the window, v = up. Double-sided material so winding is moot.
	var a := c - u * w * 0.5 - v * h * 0.5
	var b := c + u * w * 0.5 - v * h * 0.5
	var d := c + u * w * 0.5 + v * h * 0.5
	var e := c - u * w * 0.5 + v * h * 0.5
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 0)); st.add_vertex(b)
	st.set_uv(Vector2(1, 1)); st.add_vertex(d)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 1)); st.add_vertex(d)
	st.set_uv(Vector2(0, 1)); st.add_vertex(e)


static func add_windows(building: Node3D, size: Vector3) -> void:
	# Only facade sides that are long enough; tiny kiosks get one row.
	var rows := 1 if size.y < 3.0 else 2
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ys := [0.46, 0.74]
	for r in range(rows):
		var y: float = size.y * float(ys[r])
		for sx in [-0.30, 0.0, 0.30]:
			var x: float = size.x * float(sx)
			_quad(st, Vector3(x, y, size.z * 0.5 + 0.012), Vector3.RIGHT, Vector3.UP,
					minf(0.66, size.x * 0.16), 0.52)
			_quad(st, Vector3(x, y, -size.z * 0.5 - 0.012), Vector3.RIGHT, Vector3.UP,
					minf(0.66, size.x * 0.16), 0.52)
	for r in range(rows):
		var y: float = size.y * float(ys[r])
		for sz in [-0.22, 0.22]:
			var z: float = size.z * float(sz)
			_quad(st, Vector3(size.x * 0.5 + 0.012, y, z), Vector3.FORWARD, Vector3.UP,
					minf(0.66, size.z * 0.16), 0.52)
			_quad(st, Vector3(-size.x * 0.5 - 0.012, y, z), Vector3.FORWARD, Vector3.UP,
					minf(0.66, size.z * 0.16), 0.52)
	st.generate_normals()
	var mesh := st.commit()
	var m := _mat(Color(0.40, 0.64, 0.74, 0.92), true, 1.4)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, m)
	var inst := MeshInstance3D.new()
	inst.name = "Windows"
	inst.mesh = mesh
	building.add_child(inst)


static func add_trim(building: Node3D, size: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(size.x + 0.08, 0.55, size.z + 0.08)
	box.material = _mat(Color(0.20, 0.17, 0.15, 1.0))
	var inst := MeshInstance3D.new()
	inst.name = "BaseTrim"
	inst.mesh = box
	inst.position = Vector3(0, 0.27, 0)
	building.add_child(inst)


static func add_roof_props(building: Node3D, size: Vector3) -> void:
	# An AC unit and a vent stack break up the roof silhouette.
	var box := BoxMesh.new()
	box.size = Vector3(size.x * 0.30, 0.48, size.z * 0.26)
	var pipes := BoxMesh.new()
	pipes.size = Vector3(0.22, 0.85, 0.22)
	# Simpler and cheaper than merging two primitives: two small meshes.
	box.material = _mat(Color(0.36, 0.38, 0.40, 1.0))
	var ac_inst := MeshInstance3D.new()
	ac_inst.name = "RoofAC"
	ac_inst.mesh = box
	ac_inst.position = Vector3(-size.x * 0.22, size.y + 0.48, -size.z * 0.15)
	building.add_child(ac_inst)
	pipes.material = _mat(Color(0.28, 0.29, 0.31, 1.0))
	var pipe_inst := MeshInstance3D.new()
	pipe_inst.name = "RoofVent"
	pipe_inst.mesh = pipes
	pipe_inst.position = Vector3(size.x * 0.28, size.y + 0.60, size.z * 0.22)
	building.add_child(pipe_inst)


static func add_sign(building: Node3D, size: Vector3, text: String) -> void:
	var board := BoxMesh.new()
	board.size = Vector3(size.x * 0.72, 0.46, 0.09)
	board.material = _mat(Color(0.09, 0.10, 0.12, 1.0))
	var inst := MeshInstance3D.new()
	inst.name = "SignBoard"
	inst.mesh = board
	inst.position = Vector3(0, size.y * 0.88, size.z * 0.5 + 0.10)
	building.add_child(inst)
	var label := Label3D.new()
	label.name = "Sign"
	label.text = text.to_upper()
	label.font_size = 56
	label.outline_size = 6
	label.outline_modulate = Color(0.02, 0.02, 0.03, 1.0)
	label.modulate = Color(1.0, 0.88, 0.55, 1.0)
	label.position = Vector3(0, size.y * 0.88, size.z * 0.5 + 0.16)
	building.add_child(label)


static func add_beacon(building: Node3D, size: Vector3) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.10
	sphere.height = 0.20
	sphere.radial_segments = 8
	sphere.rings = 4
	var m := _mat(Color(1.0, 0.32, 0.10, 1.0), true, 2.0)
	sphere.material = m
	var inst := MeshInstance3D.new()
	inst.name = "Beacon"
	inst.mesh = sphere
	inst.position = Vector3(size.x * 0.36, size.y + 0.28, size.z * 0.36)
	building.add_child(inst)


static func dress(building: Node3D, size: Vector3, text: String) -> void:
	add_windows(building, size)
	add_trim(building, size)
	add_roof_props(building, size)
	add_sign(building, size, text)
	add_beacon(building, size)
