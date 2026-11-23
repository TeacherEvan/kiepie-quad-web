extends RefCounted
class_name CashBagVisual
## Procedural, statically cached 3D stuffed burlap cash bag with bold
## dark-emerald '$' medallions on front/back, cinched twine rope tie + knot
## tails, flared ruffled sack mouth, 5 fanned green dollar bills poking out
## the top, and a statically cached bill QuadMesh for particle fountains.

static var _initialized := false
static var _burlap_mat: StandardMaterial3D = null
static var _rope_mat: StandardMaterial3D = null
static var _medallion_mat: StandardMaterial3D = null
static var _bill_mat: StandardMaterial3D = null

static var _body_mesh: SphereMesh = null
static var _mouth_mesh: CylinderMesh = null
static var _ruffle_mesh: SphereMesh = null
static var _rope_mesh: TorusMesh = null
static var _tail_mesh: CylinderMesh = null
static var _medallion_mesh: QuadMesh = null
static var _bill_mesh: QuadMesh = null


static func _make_dollar_medallion_tex() -> ImageTexture:
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var cx := 31.5
	var cy := 31.5
	var bg := Color(0.76, 0.65, 0.44, 1.0)
	var ring := Color(0.06, 0.36, 0.16, 1.0)
	var ink := Color(0.04, 0.32, 0.13, 1.0)

	# Circular medallion base + dark-emerald border
	for y in range(sz):
		for x in range(sz):
			var dx := float(x) - cx
			var dy := float(y) - cy
			var r := sqrt(dx * dx + dy * dy)
			if r <= 29.0:
				img.set_pixel(x, y, ring if r >= 25.0 else bg)

	# Bold '$' glyph on 11x15 grid scaled up
	var glyph := [
		".....#.....",
		"....###....",
		"..#######..",
		".###.#.###.",
		".##..#..##.",
		".###.#.....",
		"..#######..",
		".....#.###.",
		"..##.#..##.",
		".###.#.###.",
		"..#######..",
		"....###....",
		".....#.....",
	]
	var rows := glyph.size()
	var cols := (glyph[0] as String).length()
	var scale_px := 3
	var ox := int(cx - float(cols * scale_px) * 0.5)
	var oy := int(cy - float(rows * scale_px) * 0.5)
	for r in range(rows):
		var line: String = glyph[r]
		for c in range(cols):
			if line[c] == "#":
				for sy in range(scale_px):
					for sx in range(scale_px):
						var px := ox + c * scale_px + sx
						var py := oy + r * scale_px + sy
						if px >= 0 and px < sz and py >= 0 and py < sz:
							img.set_pixel(px, py, ink)
	return ImageTexture.create_from_image(img)


static func _make_bill_tex() -> ImageTexture:
	var w := 64
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var paper := Color(0.24, 0.62, 0.28, 1.0)
	var border := Color(0.08, 0.34, 0.12, 1.0)
	var accent := Color(0.76, 0.88, 0.64, 1.0)
	img.fill(paper)
	for y in range(h):
		for x in range(w):
			if x < 3 or x >= w - 3 or y < 3 or y >= h - 3:
				img.set_pixel(x, y, border)
			elif (x == 5 or x == w - 6) and y >= 5 and y < h - 5:
				img.set_pixel(x, y, accent)
			elif (y == 5 or y == h - 6) and x >= 5 and x < w - 5:
				img.set_pixel(x, y, accent)
	# Center oval emblem
	var cx := 31.5
	var cy := 15.5
	for y in range(h):
		for x in range(w):
			var dx := (float(x) - cx) / 10.0
			var dy := (float(y) - cy) / 7.5
			var d := dx * dx + dy * dy
			if d <= 1.0 and d >= 0.55:
				img.set_pixel(x, y, border)
			elif d < 0.55:
				img.set_pixel(x, y, accent)
	return ImageTexture.create_from_image(img)


static func _ensure_assets() -> void:
	if _initialized:
		return
	_initialized = true

	_burlap_mat = StandardMaterial3D.new()
	_burlap_mat.albedo_color = Color(0.68, 0.55, 0.36)
	_burlap_mat.roughness = 0.92
	_burlap_mat.metallic = 0.0

	_rope_mat = StandardMaterial3D.new()
	_rope_mat.albedo_color = Color(0.46, 0.34, 0.20)
	_rope_mat.roughness = 0.95

	_medallion_mat = StandardMaterial3D.new()
	_medallion_mat.albedo_texture = _make_dollar_medallion_tex()
	_medallion_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_medallion_mat.alpha_scissor_threshold = 0.5
	_medallion_mat.roughness = 0.78

	_bill_mat = StandardMaterial3D.new()
	_bill_mat.albedo_texture = _make_bill_tex()
	_bill_mat.roughness = 0.72
	_bill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_body_mesh = SphereMesh.new()
	_body_mesh.radius = 0.30
	_body_mesh.height = 0.56
	_body_mesh.radial_segments = 14
	_body_mesh.rings = 8
	_body_mesh.material = _burlap_mat

	_mouth_mesh = CylinderMesh.new()
	_mouth_mesh.top_radius = 0.21
	_mouth_mesh.bottom_radius = 0.10
	_mouth_mesh.height = 0.16
	_mouth_mesh.radial_segments = 12
	_mouth_mesh.material = _burlap_mat

	_ruffle_mesh = SphereMesh.new()
	_ruffle_mesh.radius = 0.075
	_ruffle_mesh.height = 0.12
	_ruffle_mesh.radial_segments = 8
	_ruffle_mesh.rings = 5
	_ruffle_mesh.material = _burlap_mat

	_rope_mesh = TorusMesh.new()
	_rope_mesh.inner_radius = 0.085
	_rope_mesh.outer_radius = 0.135
	_rope_mesh.rings = 14
	_rope_mesh.ring_segments = 8
	_rope_mesh.material = _rope_mat

	_tail_mesh = CylinderMesh.new()
	_tail_mesh.top_radius = 0.018
	_tail_mesh.bottom_radius = 0.024
	_tail_mesh.height = 0.16
	_tail_mesh.radial_segments = 6
	_tail_mesh.material = _rope_mat

	_medallion_mesh = QuadMesh.new()
	_medallion_mesh.size = Vector2(0.28, 0.28)
	_medallion_mesh.material = _medallion_mat

	_bill_mesh = QuadMesh.new()
	_bill_mesh.size = Vector2(0.24, 0.12)
	_bill_mesh.material = _bill_mat


static func prewarm() -> void:
	_ensure_assets()


static func get_bill_mesh() -> QuadMesh:
	_ensure_assets()
	return _bill_mesh


static func build_bag(scale_factor: float = 1.0) -> Node3D:
	_ensure_assets()
	var root := Node3D.new()
	root.name = "CashBag"
	root.scale = Vector3.ONE * scale_factor

	# Stuffed burlap body
	var body := MeshInstance3D.new()
	body.mesh = _body_mesh
	body.scale = Vector3(1.06, 0.96, 0.92)
	root.add_child(body)

	# Bold dark-emerald '$' medallions on front and back
	for side_z in [1.0, -1.0]:
		var med := MeshInstance3D.new()
		med.mesh = _medallion_mesh
		med.position = Vector3(0.0, -0.02, 0.278 * side_z)
		if side_z < 0.0:
			med.rotation_degrees.y = 180.0
		root.add_child(med)

	# Cinched twine rope tie at the neck
	var rope := MeshInstance3D.new()
	rope.mesh = _rope_mesh
	rope.position = Vector3(0.0, 0.22, 0.0)
	root.add_child(rope)

	# Knot tails
	for s in [-1.0, 1.0]:
		var tail := MeshInstance3D.new()
		tail.mesh = _tail_mesh
		tail.position = Vector3(0.045 * s, 0.19, 0.11)
		tail.rotation_degrees = Vector3(38.0, 0.0, -28.0 * s)
		root.add_child(tail)

	# Flared ruffled sack mouth
	var mouth := MeshInstance3D.new()
	mouth.mesh = _mouth_mesh
	mouth.position = Vector3(0.0, 0.30, 0.0)
	root.add_child(mouth)

	for i in range(6):
		var ang := float(i) * TAU / 6.0
		var ruffle := MeshInstance3D.new()
		ruffle.mesh = _ruffle_mesh
		ruffle.position = Vector3(cos(ang) * 0.15, 0.36, sin(ang) * 0.15)
		root.add_child(ruffle)

	# 5 fanned green dollar bills poking out the top
	for i in range(5):
		var frac := float(i) - 2.0
		var bill := MeshInstance3D.new()
		bill.mesh = _bill_mesh
		bill.position = Vector3(frac * 0.042, 0.40 + (2.0 - absf(frac)) * 0.015, frac * 0.012)
		bill.rotation_degrees = Vector3(12.0 * absf(frac), frac * 14.0, -frac * 18.0)
		root.add_child(bill)

	return root
