extends RefCounted
## Shared VFX sprites, materials, ramps, curves, and primitive spawners.

# Hot-to-cold combat palette (sRGB). One place so every effect agrees.
const COL_CORE := Color(1.0, 0.95, 0.78, 1.0)
const COL_AMBER := Color(1.0, 0.82, 0.25, 1.0)
const COL_ORANGE := Color(1.0, 0.54, 0.12, 1.0)
const COL_EMBER := Color(0.89, 0.24, 0.04, 1.0)
const COL_SMOKE := Color(0.16, 0.16, 0.18, 0.85)
const COL_SMOKE_DARK := Color(0.09, 0.09, 0.11, 0.0)
const COL_BRASS := Color(0.83, 0.58, 0.15, 1.0)
const COL_STEAM := Color(0.82, 0.84, 0.88, 0.55)
const COL_CHAR := Color(0.19, 0.15, 0.12, 1.0)
const COL_GLASS := Color(0.72, 0.90, 1.0, 1.0)
const COL_DUST := Color(0.68, 0.60, 0.50, 0.9)

const MAX_SCORCH := 12
const MAX_SCAR := 24
const MAX_IMPACT_LIGHTS := 8
const MAX_WRECKS := 6
const MAX_DAMAGE_NUMBERS := 18
const MAX_EXPLOSION_SHARDS := 36

# Mushroom cloud visibility AABB (tall enough for stem ~45m + cap ~26m at scale=2.65)
const MUSHROOM_AABB := AABB(Vector3(-18, -6, -18), Vector3(36, 48, 36))

static var _soft_tex: GradientTexture2D = null
static var _streak_tex: ImageTexture = null
static var _flare_tex: ImageTexture = null
static var _ring_tex: ImageTexture = null
static var _smoke_tex: ImageTexture = null
static var _fire_tex: ImageTexture = null
static var _scorch_tex: ImageTexture = null
static var _plasma_sphere: SphereMesh = null
static var _noise: FastNoiseLite = null
static var _sprite_mats: Dictionary = {}
static var _sprite_quads: Dictionary = {}
static var _rubble_meshes: Array[BoxMesh] = []
static var _rubble_shapes: Array[BoxShape3D] = []
static var _casing_shape: CylinderShape3D = null
static var _casing_mesh: CylinderMesh = null
static var _bolt_unit_mesh: CylinderMesh = null
static var _shaders_warmed := false
const MAX_CASINGS := 24


static func _q() -> float:
	return maxf(0.0, Settings.quality_multiplier())


static func _ensure_rubble_pool() -> void:
	if not _rubble_meshes.is_empty():
		return
	# Irregular elongated/faceted shrapnel slabs instead of identical toy cubes
	for dims in [
		Vector3(0.32, 0.08, 0.16),
		Vector3(0.24, 0.14, 0.28),
		Vector3(0.42, 0.07, 0.12),
		Vector3(0.18, 0.15, 0.22),
	]:
		var bm := BoxMesh.new()
		bm.size = dims
		_rubble_meshes.append(bm)
		var bs := BoxShape3D.new()
		bs.size = dims
		_rubble_shapes.append(bs)


static func _ensure_plasma_sphere() -> SphereMesh:
	if _plasma_sphere == null:
		var sm := SphereMesh.new()
		sm.radius = 0.65
		sm.height = 1.30
		sm.radial_segments = 12
		sm.rings = 8
		_plasma_sphere = sm
	return _plasma_sphere


static func _ensure_casing_pool() -> void:
	if _casing_shape != null and _casing_mesh != null:
		return
	var shape := CylinderShape3D.new()
	shape.radius = 0.028
	shape.height = 0.075
	_casing_shape = shape
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.028
	cyl.bottom_radius = 0.028
	cyl.height = 0.075
	cyl.radial_segments = 8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COL_BRASS
	mat.metallic = 0.85
	mat.roughness = 0.32
	cyl.material = mat
	_casing_mesh = cyl


static func _ensure_bolt_mesh() -> CylinderMesh:
	if _bolt_unit_mesh == null:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.85
		cm.bottom_radius = 1.0
		cm.height = 1.0
		cm.radial_segments = 6
		_bolt_unit_mesh = cm
	return _bolt_unit_mesh


static func prewarm(host: Node3D = null) -> void:
	## Called once when the first bike enters a scene: builds the tiny sprite
	## set, pooled particle materials/meshes, and (on GPU runs) warms WebGL
	## shaders offscreen so a firefight's first shot never stalls compilation.
	_soft_sprite()
	_streak_sprite()
	_flare_sprite()
	_ring_sprite()
	_smoke_sprite()
	_fire_sprite()
	_scorch_sprite()
	_ensure_rubble_pool()
	_ensure_plasma_sphere()
	_ensure_bolt_mesh()
	var cash_bag_gd := load("res://src/game/CashBagVisual.gd") as GDScript
	if cash_bag_gd != null and cash_bag_gd.has_method("prewarm"):
		cash_bag_gd.call("prewarm")
	for additive in [false, true]:
		for key in ["soft", "streak", "flare", "ring", "smoke", "fire"]:
			_sprite_material(additive, key)
	if host != null and not _shaders_warmed and DisplayServer.get_name() != "headless":
		_shaders_warmed = true
		var rack := Node3D.new()
		rack.name = "VfxShaderPrewarm"
		rack.position = Vector3(0.0, -150.0, 0.0)
		rack.scale = Vector3(0.001, 0.001, 0.001)
		host.add_child(rack)
		for key in ["soft", "streak"]:
			var q := _sprite_quad(key == "streak", key, 0.42)
			var m := MeshInstance3D.new()
			m.mesh = q
			rack.add_child(m)
		var r := MeshInstance3D.new()
		r.mesh = _rubble_meshes[0]
		r.material_override = _emissive(COL_CHAR, 1.0)
		rack.add_child(r)
		var tree := host.get_tree()
		if tree != null:
			var w_rack: WeakRef = weakref(rack)
			tree.create_timer(0.25).timeout.connect(func() -> void:
				var node := w_rack.get_ref() as Node
				if node != null:
					node.queue_free())


# ------------------------------------------------------------------ palette --

static func _emissive(color: Color, energy: float = 2.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func _additive(color: Color, energy: float = 2.5) -> StandardMaterial3D:
	var m := _emissive(color, energy)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


static var _ramp_cache: Dictionary = {}

static func _ramp(colors: Array) -> GradientTexture1D:
	## A fresh Gradient has exactly two points; set_color/set_offset at index 2
	## is an out-of-bounds write that silently drops the transparent fade stop.
	## Seed the two endpoints, then add interior stops explicitly.
	## Cached by content: every burst used to allocate identical ramps.
	var cache_key := ""
	for c in colors:
		cache_key += (c as Color).to_html() + "|"
	var cached: Variant = _ramp_cache.get(cache_key)
	if cached != null:
		return cached
	var g := Gradient.new()
	var n := colors.size()
	if n == 0:
		g.set_color(0, Color.WHITE)
		g.set_color(1, Color.WHITE)
	else:
		g.set_color(0, colors[0])
		g.set_offset(0, 0.0)
		g.set_color(1, colors[n - 1] if n > 1 else colors[0])
		g.set_offset(1, 1.0)
		for i in range(1, n - 1):
			g.add_point(float(i) / float(n - 1), colors[i])
	var ramp := GradientTexture1D.new()
	ramp.gradient = g
	_ramp_cache[cache_key] = ramp
	return ramp


static var _curve_cache: Dictionary = {}

static func _curve(keys: Array) -> CurveTexture:
	## [offset, value] pairs describing a particle's size over its lifetime.
	## Cached by content — identical per burst.
	var cache_key := ""
	for k in keys:
		cache_key += str(k[0]) + ":" + str(k[1]) + "|"
	var cached: Variant = _curve_cache.get(cache_key)
	if cached != null:
		return cached
	var c := Curve.new()
	c.clear_points()
	for k in keys:
		c.add_point(Vector2(float(k[0]), float(k[1])))
	var t := CurveTexture.new()
	t.curve = c
	_curve_cache[cache_key] = t
	return t


# ---------------------------------------------------------------- sprites ----

static func _soft_sprite() -> GradientTexture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.38, 1.0])
		g.colors = PackedColorArray([
			Color(1, 1, 1, 1), Color(0.68, 0.68, 0.68, 0.52), Color(0, 0, 0, 0)])
		var t := GradientTexture2D.new()
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		# fill_to = (1.0, 0.5) puts gradient offset 1.0 strictly at the inscribed circle
		# (r = 0.5), guaranteeing alpha == 0.0 before touching the quad border!
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 96
		t.height = 96
		t.gradient = g
		_soft_tex = t
	return _soft_tex


static func _image_tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


static func _streak_sprite() -> ImageTexture:
	## Soft vertical streak; used with particle_flag_align_y for sparks that
	## read as motion instead of round dots.
	if _streak_tex == null:
		var w := 16
		var h := 64
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in range(h):
			var v := float(y) / float(h - 1)
			var vfall: float = pow(maxf(0.0, 1.0 - absf(v - 0.46) * 2.1), 1.4)
			for x in range(w):
				var u := float(x) / float(w - 1)
				var hfall: float = pow(maxf(0.0, 1.0 - absf(u - 0.5) * 2.0), 1.8)
				var a: float = clampf(vfall * hfall, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_streak_tex = _image_tex(img)
	return _streak_tex


static func _flare_sprite() -> ImageTexture:
	## Four-point star: a bright core plus thin horizontal/vertical spikes.
	if _flare_tex == null:
		var s := 64
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		for y in range(s):
			var v: float = absf(float(y) / float(s - 1) - 0.5) * 2.0
			for x in range(s):
				var u: float = absf(float(x) / float(s - 1) - 0.5) * 2.0
				var core: float = pow(maxf(0.0, 1.0 - sqrt(u * u + v * v) * 2.5), 2.0)
				var spike_h: float = pow(maxf(0.0, 1.0 - u * 9.0), 1.4) * pow(maxf(0.0, 1.0 - v), 2.2)
				var spike_v: float = pow(maxf(0.0, 1.0 - v * 9.0), 1.4) * pow(maxf(0.0, 1.0 - u), 2.2)
				var a: float = clampf(maxf(core, maxf(spike_h, spike_v) * 0.8), 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_flare_tex = _image_tex(img)
	return _flare_tex


static func _ring_sprite() -> ImageTexture:
	## Flat soft annulus, used for shockwaves and ground dust waves (2 tris).
	if _ring_tex == null:
		var s := 96
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		for y in range(s):
			var v := float(y) / float(s - 1) * 2.0 - 1.0
			for x in range(s):
				var u := float(x) / float(s - 1) * 2.0 - 1.0
				var r: float = sqrt(u * u + v * v)
				var band: float = exp(-pow((r - 0.70) * 6.5, 2.0))
				var edge: float = clampf((1.0 - r) * 6.0, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(band * edge, 0.0, 1.0)))
		_ring_tex = _image_tex(img)
	return _ring_tex


static func _smoke_sprite() -> ImageTexture:
	## Multi-octave turbulent billow puff with strict zero-alpha border:
	## reads as churning oil/diesel smoke instead of uniform round discs.
	if _smoke_tex == null:
		if _noise == null:
			_noise = FastNoiseLite.new()
			_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			_noise.fractal_octaves = 3
			_noise.frequency = 0.055
		var s := 64
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		for y in range(s):
			var v := float(y) / float(s - 1) * 2.0 - 1.0
			for x in range(s):
				var u := float(x) / float(s - 1) * 2.0 - 1.0
				var r := sqrt(u * u + v * v)
				var radial: float = clampf(1.0 - r / 0.94, 0.0, 1.0)
				var n: float = _noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
				var billow: float = clampf(pow(radial, 0.95) * (0.42 + n * 0.92), 0.0, 1.0)
				# Subtle self-shaded puff luminance so thick smoke has internal volume
				var shade: float = clampf(0.68 + n * 0.32 - v * 0.14, 0.45, 1.0)
				img.set_pixel(x, y, Color(shade, shade, shade, billow))
		_smoke_tex = _image_tex(img)
	return _smoke_tex


static func _fire_sprite() -> ImageTexture:
	## High-contrast turbulent flame tongue sprite for rich daylight fireballs:
	## dense white-hot ridges tapering into wispy jagged combustion edges.
	if _fire_tex == null:
		var fn := FastNoiseLite.new()
		fn.seed = 4271
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.fractal_octaves = 3
		fn.frequency = 0.078
		var s := 64
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		for y in range(s):
			var v := float(y) / float(s - 1) * 2.0 - 1.0
			for x in range(s):
				var u := float(x) / float(s - 1) * 2.0 - 1.0
				var r := sqrt(u * u + v * v)
				var n: float = fn.get_noise_2d(float(x) + 17.0, float(y) - 9.0) * 0.5 + 0.5
				var n2: float = fn.get_noise_2d(float(x) * 1.9 - 31.0, float(y) * 1.9 + 23.0) * 0.5 + 0.5
				# Noise-warped radial boundary for torn flame tongues, zero-clamped inside quad
				var edge_r := r - (n - 0.5) * 0.34
				var mask: float = clampf(1.0 - edge_r / 0.88, 0.0, 1.0)
				var hard_border: float = clampf((0.95 - r) * 10.0, 0.0, 1.0)
				var a: float = clampf(pow(mask, 1.15) * (0.65 + n2 * 0.55) * hard_border, 0.0, 1.0)
				# Bright core luminance fading slightly toward outer soot rim
				var lum: float = clampf(0.75 + mask * 0.35 + (n2 - 0.4) * 0.25, 0.55, 1.0)
				img.set_pixel(x, y, Color(lum, lum * (0.86 + mask * 0.14), lum * (0.72 + mask * 0.28), a))
		_fire_tex = _image_tex(img)
	return _fire_tex


static func _scorch_sprite() -> ImageTexture:
	## Organic radial blast crater soot mark with jagged ray streaks and a
	## strict zero-alpha margin — never shows a rectangular quad border on asphalt.
	if _scorch_tex == null:
		var sn := FastNoiseLite.new()
		sn.seed = 9013
		sn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		sn.fractal_octaves = 3
		sn.frequency = 0.075
		var s := 96
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		for y in range(s):
			var v := float(y) / float(s - 1) * 2.0 - 1.0
			for x in range(s):
				var u := float(x) / float(s - 1) * 2.0 - 1.0
				var r := sqrt(u * u + v * v)
				var ang := atan2(v, u)
				# Radial blast rays + surface noise
				var rays := sin(ang * 7.0 + 0.6) * 0.07 + cos(ang * 13.0 - 1.1) * 0.05
				var n: float = sn.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
				var eff_r := r + rays + (n - 0.5) * 0.18
				var core: float = clampf(1.0 - eff_r / 0.86, 0.0, 1.0)
				var border: float = clampf((0.93 - r) * 12.0, 0.0, 1.0)
				var a: float = clampf(pow(core, 1.45) * border, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_scorch_tex = _image_tex(img)
	return _scorch_tex


static func _sprite_material(additive: bool, key: String = "soft") -> StandardMaterial3D:
	var cache_key := "%s|%s" % [key, str(additive)]
	if _sprite_mats.has(cache_key):
		return _sprite_mats[cache_key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_sprite()
	match key:
		"streak":
			m.albedo_texture = _streak_sprite()
			# BILLBOARD_ENABLED overrides particle_flag_align_y in Godot 4; disabling
			# billboard lets sparks align along their velocity vector as true streaks!
			m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"flare":
			m.albedo_texture = _flare_sprite()
		"ring":
			m.albedo_texture = _ring_sprite()
		"smoke":
			m.albedo_texture = _smoke_sprite()
		"fire":
			m.albedo_texture = _fire_sprite()
		"scorch":
			m.albedo_texture = _scorch_sprite()
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_sprite_mats[cache_key] = m
	return m


static func _sprite_quad(additive: bool, key: String, quad_size: float) -> QuadMesh:
	var qkey := "%s|%s|%.3f" % [key, str(additive), quad_size]
	if _sprite_quads.has(qkey):
		return _sprite_quads[qkey] as QuadMesh
	var quad := QuadMesh.new()
	quad.size = Vector2(quad_size * 0.44, quad_size * 2.55) if key == "streak" else Vector2.ONE * quad_size
	quad.material = _sprite_material(additive, key)
	_sprite_quads[qkey] = quad
	return quad


# --------------------------------------------------------------- particles ---

static func _particle(parent: Node3D, pos: Vector3, amount: int, lifetime: float,
		dir: Vector3, spread: float, speed_min: float, speed_max: float,
		colors: Array, size: float, gravity: Vector3 = Vector3(0, -2.0, 0),
		additive: bool = false, opts: Dictionary = {}) -> GPUParticles3D:
	if Settings.reduced_motion() or _q() <= 0.0:
		return null
	var p := GPUParticles3D.new()
	p.amount = maxi(2, int(amount * _q()))
	p.lifetime = lifetime
	p.one_shot = true
	p.local_coords = false
	p.explosiveness = float(opts.get("explosiveness", 0.85))
	p.visibility_aabb = opts.get("aabb", AABB(Vector3(-8, -6, -8), Vector3(16, 16, 16)))
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.UP
	pm.spread = spread
	pm.gravity = gravity
	pm.initial_velocity_min = speed_min
	pm.initial_velocity_max = speed_max
	pm.scale_min = size * 0.45
	pm.scale_max = size * 1.4
	pm.color_ramp = _ramp(colors)
	if opts.has("curve"):
		pm.scale_curve = _curve(opts["curve"])
	if opts.has("damping"):
		pm.damping_min = float(opts["damping"])
		pm.damping_max = float(opts["damping"]) * 1.4
	if opts.has("hue"):
		pm.hue_variation_min = -float(opts["hue"])
		pm.hue_variation_max = float(opts["hue"])
	if opts.has("angular"):
		pm.angular_velocity_min = -float(opts["angular"])
		pm.angular_velocity_max = float(opts["angular"])
	if bool(opts.get("align", false)):
		pm.particle_flag_align_y = true
	if opts.has("box"):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = opts["box"]
	p.process_material = pm
	p.draw_pass_1 = _sprite_quad(additive, str(opts.get("tex", "soft")), float(opts.get("quad", 0.42)))
	p.position = pos
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


static func _flash_billboard(parent: Node3D, pos: Vector3, size: float,
		color: Color, duration: float) -> void:
	if parent == null or Settings.reduced_motion():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var m := _additive(color, 4.0)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _flare_sprite()
	quad.material = m
	var inst := MeshInstance3D.new()
	inst.mesh = quad
	inst.position = pos
	parent.add_child(inst)
	var t := inst.create_tween()
	t.tween_property(inst, "scale", Vector3(1.75, 1.75, 1.75), duration)
	t.parallel().tween_property(m, "albedo_color:a", 0.0, duration)
	t.tween_callback(inst.queue_free)


static func _ring_quad(parent: Node3D, pos: Vector3, radius: float,
		color: Color, grow: float, duration: float, matte: bool = false,
		normal: Vector3 = Vector3.UP) -> MeshInstance3D:
	## A flat expanding annulus. Two triangles instead of a torus's hundreds.
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * radius * 2.0
	var m: StandardMaterial3D
	if matte:
		m = StandardMaterial3D.new()
		m.albedo_color = color
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		m = _additive(color, 2.2)
	m.albedo_texture = _ring_sprite()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = m
	var inst := MeshInstance3D.new()
	inst.mesh = quad
	inst.position = pos
	inst.basis = _plane_basis(normal)
	parent.add_child(inst)
	var t := inst.create_tween()
	t.tween_property(inst, "scale", Vector3(grow, grow, grow), duration)
	t.parallel().tween_property(m, "albedo_color:a", 0.0, duration)
	t.tween_callback(inst.queue_free)
	return inst


static func _plane_basis(normal: Vector3) -> Basis:
	## Orient a quad so its flat face lies on the given surface normal. Using
	## World Up directly blows up when the normal *is* up (ground hits).
	var n := normal.normalized() if normal.length_squared() > 1e-8 else Vector3.UP
	var up := Vector3.UP
	if absf(n.dot(up)) > 0.98:
		up = Vector3.FORWARD
	return Basis.looking_at(-n, up)


static func _static_cue(parent: Node3D, pos: Vector3, color: Color,
		size: float, duration: float) -> void:
	## Reduced-motion feedback: one unshaded billboard, no tween, no particles.
	if parent == null or not Settings.reduced_motion():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var m := _additive(color, 1.8)
	m.albedo_texture = _flare_sprite()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = m
	var inst := MeshInstance3D.new()
	inst.mesh = quad
	inst.position = pos
	parent.add_child(inst)
	var tree := parent.get_tree()
	if tree != null:
		var w_inst: WeakRef = weakref(inst)
		var timer := tree.create_timer(duration)
		timer.timeout.connect(func() -> void:
			var node := w_inst.get_ref() as Node
			if node != null:
				node.queue_free())


static func _cap_group(parent: Node, group: String, cap: int) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var tree := parent.get_tree()
	if tree == null:
		return
	var old := tree.get_nodes_in_group(group)
	var excess := old.size() - cap
	var i := 0
	while excess > 0 and i < old.size():
		var victim = old[i]
		if is_instance_valid(victim):
			# Leave the group now: queue_free() is deferred, so until the frame
			# ends the decal would still count against the cap.
			(victim as Node).remove_from_group(group)
			(victim as Node).queue_free()
			excess -= 1
		i += 1


# ------------------------------------------------------------------ shoot ----

