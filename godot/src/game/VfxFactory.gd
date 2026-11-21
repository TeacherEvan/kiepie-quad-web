extends RefCounted
class_name VfxFactory
## Pooled-by-convention particle helpers. All counts respect the player's
## quality multiplier. Under reduced-motion, bursts, debris, shockwaves,
## shield pulses and float/flashes collapse to a single static cue.
##
## Visual language: "refined hot metal" — a white-hot core, a shaped fireball
## with a scale envelope, velocity-aligned spark streaks, charred cooling
## debris, and heavy smoke that rises and billows instead of flat blobs.
##
## Compatibility renderer (gl_compatibility / Web): GPUParticles3D with one
## draw pass each, unshaded materials, no trails, no sub-emitters, no decals.
## Every sprite is generated once at runtime so the Web pck does not grow.

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
static var _shaders_warmed := false
static var _casing_count := 0
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
	if Settings.reduced_motion():
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
	var n := normal.normalized()
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

static func muzzle_flash(parent: Node3D, pos: Vector3, dir: Vector3, color: Color) -> void:
	if parent == null:
		return
	var holder := Node3D.new()
	holder.position = pos
	parent.add_child(holder)
	var fwd := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD

	# white-hot core burst along the barrel
	_particle(holder, fwd * 0.18, 14, 0.13, fwd, 16.0, 8.0, 17.0,
			[Color(1, 0.92, 0.60, 0.95), COL_AMBER, Color(COL_EMBER.r, COL_EMBER.g, COL_EMBER.b, 0.0)],
			0.30, Vector3(0, -5, 0), true,
			{"tex": "streak", "align": true, "curve": [[0, 0.7], [0.4, 1.0], [1, 0.15]]})
	# lingering smoke wisp after the shot
	_particle(holder, Vector3.ZERO, 6, 0.75, fwd * 0.4 + Vector3.UP * 0.6, 35.0, 1.1, 2.4,
			[Color(0.38, 0.38, 0.40, 0.5), COL_SMOKE_DARK], 0.42,
			Vector3(0, 0.7, 0), false, {"tex": "smoke", "quad": 0.8, "curve": [[0, 0.6], [0.4, 1.1], [1, 1.5]]})
	_flash_billboard(holder, Vector3.ZERO, 0.85, COL_CORE, 0.12)

	# blast disc perpendicular to the barrel — gives the flash a direction
	if not Settings.reduced_motion():
		var disc := QuadMesh.new()
		disc.size = Vector2.ONE * 0.52
		var dm := _additive(color, 2.6)
		dm.albedo_texture = _ring_sprite()
		dm.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		dm.cull_mode = BaseMaterial3D.CULL_DISABLED
		disc.material = dm
		var disc_inst := MeshInstance3D.new()
		disc_inst.mesh = disc
		disc_inst.position = fwd * 0.16
		disc_inst.basis = _plane_basis(fwd)
		holder.add_child(disc_inst)
		var dt := disc_inst.create_tween()
		dt.tween_property(disc_inst, "scale", Vector3(2.1, 2.1, 2.1), 0.14)
		dt.parallel().tween_property(dm, "albedo_color:a", 0.0, 0.14)
		dt.tween_callback(disc_inst.queue_free)

	var smoke_tree := holder.get_tree()
	var lights: Array = smoke_tree.get_nodes_in_group("vfx_light") if smoke_tree != null else []
	if Settings.quality_multiplier() >= 0.75 and lights.size() < MAX_IMPACT_LIGHTS:
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 7.5
		light.omni_range = 4.0
		light.add_to_group("vfx_light")
		holder.add_child(light)
		var t := light.create_tween()
		if Settings.reduced_motion():
			light.light_energy = 2.5
			t.tween_interval(0.14)
		else:
			t.tween_property(light, "light_energy", 0.0, 0.14)
		t.tween_callback(func() -> void:
			if is_instance_valid(light):
				light.remove_from_group("vfx_light")
				light.queue_free())
	# The 0.75 s smoke wisp child outlives the 0.14 s light fade — freeing the
	# holder with the light chopped the smoke short on every shot. The holder
	# goes after the slowest child, not with the light.
	if smoke_tree != null:
		var w_holder: WeakRef = weakref(holder)
		smoke_tree.create_timer(0.9).timeout.connect(func() -> void:
			var node := w_holder.get_ref() as Node
			if node != null:
				node.queue_free())
	else:
		var ht := holder.create_tween()
		ht.tween_interval(0.14)
		ht.tween_callback(holder.queue_free)


static func casing(parent: Node3D, pos: Vector3, eject_dir: Vector3) -> void:
	if parent == null:
		return
	# Hard cap on live ejection bodies — a per-shot RigidBody3D is the one
	# VFX node that exercises the physics solver; the Web budget is finite.
	if _casing_count >= MAX_CASINGS:
		return
	_casing_count += 1
	_ensure_casing_pool()
	var body := RigidBody3D.new()
	body.mass = 0.02
	body.collision_layer = 0
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.shape = _casing_shape
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _casing_mesh
	body.add_child(mesh)
	parent.add_child(body)
	var out := eject_dir.normalized()
	body.global_position = pos + out * 0.08 + Vector3(0, 0.05, 0)
	body.linear_velocity = out * 2.6 + Vector3(0, 2.4, 0)
	body.angular_velocity = Vector3(randf_range(-14, 14), randf_range(-14, 14),
			randf_range(-14, 14))
	# Timer lives on the tree (not the body), so teardown still releases the slot.
	var tree := parent.get_tree()
	if tree != null:
		var w_body: WeakRef = weakref(body)
		var timer := tree.create_timer(2.4)
		timer.timeout.connect(func() -> void:
			_casing_count = maxi(0, _casing_count - 1)
			var node := w_body.get_ref() as Node
			if node != null:
				node.queue_free())
	else:
		_casing_count = maxi(0, _casing_count - 1)
		body.queue_free()


# ---------------------------------------------------------------- impact -----

static func impact(parent: Node3D, pos: Vector3, color: Color,
		dir: Vector3 = Vector3.ZERO, surface: String = "metal",
		normal: Vector3 = Vector3.UP) -> void:
	if parent == null:
		return
	var holder := Node3D.new()
	holder.position = pos
	parent.add_child(holder)
	var shot := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.UP
	var spark_count := 16 if surface == "metal" else 9
	var spark_col := COL_AMBER if surface == "metal" else Color(1, 0.94, 0.72, 1)
	_particle(holder, Vector3.ZERO, spark_count, 0.26, shot, 85.0, 5.0, 11.0,
			[Color(1, 1, 0.82, 0.9), spark_col, Color(COL_EMBER.r, COL_EMBER.g, COL_EMBER.b, 0.0)],
			0.13, Vector3(0, -9.0, 0), true,
			{"tex": "streak", "align": true, "curve": [[0, 0.9], [0.55, 1.0], [1, 0.05]]})
	var puff_col := Color(0.70, 0.66, 0.60, 0.75) if surface != "metal" else Color(0.55, 0.55, 0.58, 0.7)
	_particle(holder, Vector3.ZERO, 14, 0.5, normal, 60.0, 1.6, 4.2,
			[puff_col, Color(0.30, 0.30, 0.32, 0.45), COL_SMOKE_DARK], 0.28,
			Vector3(0, 0.2, 0), false, {"tex": "smoke", "quad": 0.9})
	_flash_billboard(holder, Vector3.ZERO, 0.52, COL_CORE, 0.09)
	# gl_compatibility has a low real-time light budget: cap concurrent sparks'
	# point lights rather than letting a firefight allocate one per shot.
	var tree := parent.get_tree()
	var lights: Array = tree.get_nodes_in_group("vfx_light") if tree != null else []
	if lights.size() < MAX_IMPACT_LIGHTS:
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 4.5
		light.omni_range = 2.6
		light.add_to_group("vfx_light")
		holder.add_child(light)
		if Settings.reduced_motion():
			light.light_energy = 1.6
		else:
			var lt := holder.create_tween()
			lt.tween_property(light, "light_energy", 0.0, 0.12)
	var t := holder.create_tween()
	t.tween_interval(0.7)
	t.tween_callback(func() -> void:
		for c in holder.get_children():
			if c.is_in_group("vfx_light"):
				c.remove_from_group("vfx_light")
		holder.queue_free())
	# A bike is a moving body: a world-space scar there would float in mid-air.
	if surface != "bike" and normal.length_squared() > 0.1:
		scar(parent, pos + normal * 0.012, normal, surface)


static func scar(parent: Node3D, pos: Vector3, normal: Vector3,
		surface: String = "metal") -> void:
	## Small fading bullet mark flush to whatever the shot hit. No Decal node:
	## the compatibility renderer does not support them.
	if parent == null or surface == "ground":
		return
	var quad := QuadMesh.new()
	var s := randf_range(0.16, 0.30)
	quad.size = Vector2(s, s)
	var m := StandardMaterial3D.new()
	var tint := Color(0.10, 0.09, 0.09, 0.75) if surface == "concrete" else Color(0.06, 0.05, 0.04, 0.85)
	m.albedo_color = tint
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _soft_sprite()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = m
	var inst := MeshInstance3D.new()
	inst.mesh = quad
	inst.position = pos
	inst.basis = _plane_basis(normal)
	inst.add_to_group("vfx_scar")
	parent.add_child(inst)
	_cap_group(parent, "vfx_scar", MAX_SCAR)
	var t := inst.create_tween()
	t.tween_interval(4.0)
	t.tween_property(m, "albedo_color:a", 0.0, 3.0)
	t.tween_callback(func() -> void:
		if is_instance_valid(inst):
			inst.remove_from_group("vfx_scar")
			inst.queue_free())


static func shield_block(parent: Node3D, pos: Vector3, color: Color) -> void:
	## Damage absorbed by the shield/invulnerability still needs to read.
	if parent == null:
		return
	_flash_billboard(parent, pos, 0.55, color, 0.12)
	if Settings.reduced_motion():
		_static_cue(parent, pos, color, 0.55, 0.14)
		return
	_ring_quad(parent, pos, 0.32, color, 2.4, 0.38, false, Vector3.UP)
	_ring_quad(parent, pos, 0.24, Color(1, 1, 1, 0.8), 1.7, 0.28, false, Vector3.UP)
	_particle(parent, pos, 12, 0.32, Vector3.UP, 75.0, 2.5, 6.0,
			[Color(color.r, color.g, color.b, 0.9), Color(1, 1, 1, 0.6), Color(color.r, color.g, color.b, 0.0)],
			0.12, Vector3(0, -3, 0), true,
			{"tex": "streak", "align": true, "curve": [[0, 0.8], [1, 0.05]]})


# -------------------------------------------------------------- explosion ----

static func explosion(parent: Node3D, pos: Vector3, color: Color, scale: float = 1.0) -> void:
	particle_explosion(parent, pos, color, scale, false)


static func mushroom_cloud_explosion(parent: Node3D, pos: Vector3,
		color: Color = Color(1.0, 0.26, 0.04), scale: float = 2.65) -> void:
	## Towering 6-stage meteor detonation. See Stage 2M inside particle_explosion.
	particle_explosion(parent, pos, color, scale, true)


static func particle_explosion(parent: Node3D, pos: Vector3, color: Color, scale: float = 1.0,
		mushroom: bool = false) -> void:
	if parent == null:
		return
	var holder := Node3D.new()
	holder.name = "Explosion"
	holder.position = pos
	holder.scale = Vector3.ONE * scale
	parent.add_child(holder)

	var reduced := Settings.reduced_motion()

	# Stage 0: Dynamic flash light — fast attack, warm release; freed from vfx_light group
	# as soon as it fades out so chained explosions never starve WebGL2's 8-light budget.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.70, 0.28).lerp(color, 0.25)
	light.light_energy = 32.0
	light.omni_range = clampf(12.0 * scale, 9.0, 26.0)
	light.add_to_group("vfx_light")
	holder.add_child(light)
	_cap_group(parent, "vfx_light", MAX_IMPACT_LIGHTS)
	if reduced:
		light.light_energy = 7.5
		var lrt := holder.create_tween()
		lrt.tween_interval(0.35)
		lrt.tween_callback(func() -> void:
			if is_instance_valid(light):
				light.remove_from_group("vfx_light")
				light.queue_free())
	else:
		var lt := holder.create_tween()
		lt.tween_property(light, "light_energy", 32.0, 0.04).from(0.0)
		lt.tween_property(light, "light_energy", 0.0, 0.56)
		lt.tween_callback(func() -> void:
			if is_instance_valid(light):
				light.remove_from_group("vfx_light")
				light.queue_free())

	# Stage 0b: Volumetric 3D expanding plasma core sphere (instant punch from every angle)
	if not reduced:
		var core_mat := _additive(Color(1.0, 0.94, 0.72, 0.92), 3.6)
		var core_inst := MeshInstance3D.new()
		core_inst.mesh = _ensure_plasma_sphere()
		core_inst.material_override = core_mat
		core_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		core_inst.position = Vector3(0.0, 0.35, 0.0)
		core_inst.scale = Vector3.ONE * 0.35
		holder.add_child(core_inst)
		var ct := core_inst.create_tween()
		ct.tween_property(core_inst, "scale", Vector3.ONE * 2.15, 0.19).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		ct.parallel().tween_property(core_mat, "albedo_color", Color(1.0, 0.36, 0.04, 0.0), 0.19)
		ct.tween_callback(core_inst.queue_free)

	# Stage 1a: Daylight-readable ALPHA-BLENDED turbulent fireball billows (deep saturated
	# amber -> vermilion -> charred crimson -> soot, tightly cohesive around the blast core!)
	_particle(holder, Vector3(0, 0.25, 0), 46, 0.88, Vector3.UP, 64.0, 1.8, 4.8,
			[Color(1.0, 0.80, 0.22, 0.98), Color(1.0, 0.42, 0.06, 0.94),
			 Color(0.68, 0.14, 0.04, 0.68), Color(0.10, 0.09, 0.10, 0.0)],
			1.35, Vector3(0, 2.2, 0), false,
			{"tex": "fire", "quad": 1.38, "curve": [[0, 0.48], [0.28, 1.38], [0.72, 1.12], [1, 0.32]],
			 "hue": 0.04, "damping": 3.5, "angular": 2.6, "explosiveness": 0.96})

	# Stage 1b: Tight incandescent ADDITIVE fire heart burning inside the fireball
	_particle(holder, Vector3(0, 0.28, 0), 34, 0.54, Vector3.UP, 52.0, 1.6, 4.8,
			[Color(1.0, 0.99, 0.85, 1.0), Color(1.0, 0.82, 0.28, 0.94),
			 Color(1.0, 0.38, 0.05, 0.0)],
			0.96, Vector3(0, 1.4, 0), true,
			{"tex": "fire", "quad": 1.02, "curve": [[0, 0.50], [0.26, 1.35], [1, 0.08]],
			 "hue": 0.03, "damping": 3.4, "angular": 3.2, "explosiveness": 1.0})

	# Stage 3: High-velocity ballistic spark streaks + slow-drifting buoyant embers
	_particle(holder, Vector3(0, 0.35, 0), 56, 1.15, Vector3.UP, 84.0, 10.0, 24.0,
			[Color(1.0, 0.96, 0.72, 1.0), Color(1.0, 0.58, 0.14, 0.88),
			 Color(0.89, 0.20, 0.03, 0.0)],
			0.24, Vector3(0, -13.0, 0), true,
			{"tex": "streak", "align": true, "curve": [[0, 1.0], [0.55, 0.85], [1, 0.0]],
			 "explosiveness": 0.98})
	_particle(holder, Vector3(0, 0.40, 0), 20, 1.65, Vector3.UP, 65.0, 1.2, 3.6,
			[Color(1.0, 0.84, 0.34, 0.95), Color(1.0, 0.38, 0.06, 0.70), Color(0.75, 0.14, 0.02, 0.0)],
			0.11, Vector3(0, 0.95, 0), true,
			{"tex": "soft", "quad": 0.36, "curve": [[0, 0.8], [0.5, 1.0], [1, 0.0]],
			 "damping": 0.55, "explosiveness": 0.78})

	_flash_billboard(holder, Vector3(0, 0.42, 0), 3.1, COL_CORE, 0.17)

	var debris_chunks: Array[RigidBody3D] = []
	if mushroom:
		# ------- Stage 2M: colossal meteor mushroom cloud anatomy -------
		# (a) Mach ground shockwave: twin colossal expanding rings + 360° dust skirt
		if not reduced:
			_ring_quad(holder, Vector3(0, 0.26, 0), 0.62, Color(1.0, 0.72, 0.30, 0.95), 11.5, 0.55, false)
			_ring_quad(holder, Vector3(0, 0.17, 0), 1.15, Color(0.50, 0.44, 0.38, 0.75), 14.0, 0.90, true)
		_particle(holder, Vector3(0, 0.20, 0), 34, 1.6, Vector3(0, 0.14, 1), 88.0, 5.5, 12.0,
				[Color(0.45, 0.39, 0.33, 0.78), Color(0.26, 0.24, 0.22, 0.45), Color(0.17, 0.15, 0.14, 0.0)],
				1.6, Vector3(0, 0.5, 0), false,
				{"tex": "smoke", "quad": 1.5, "curve": [[0, 0.42], [0.35, 1.2], [1, 2.1]],
				 "damping": 2.2, "angular": 2.0, "explosiveness": 0.96})
		# (b) Buoyant thermal stem: narrow 14° column, positive upward acceleration,
		#     incandescent magma-orange at the base churning to dark volcanic soot.
		var mushroom_aabb := MUSHROOM_AABB
		_particle(holder, Vector3(0, 0.3, 0), 58, 3.2, Vector3.UP, 14.5, 3.2, 6.8,
				[Color(1.0, 0.62, 0.10, 0.96), Color(0.85, 0.28, 0.05, 0.88),
				 Color(0.24, 0.20, 0.19, 0.72), Color(0.12, 0.11, 0.12, 0.0)],
				1.55, Vector3(0, 4.6, 0), false,
				{"tex": "fire", "quad": 1.25, "curve": [[0, 0.38], [0.3, 1.05], [1, 1.9]],
				 "angular": 1.6, "damping": 0.35, "explosiveness": 0.88, "aabb": mushroom_aabb})
		# (c) Elevated toroidal cap canopy: two delayed beats billowing outward at
		#     the stem apex (holder scale lifts local 2.35 m to 2.35 * scale world).
		var cap_pos := Vector3(0.0, 2.35, 0.0)
		var cap_beats := [
			{"t": 0.14, "tex": "fire",
			 "colors": [Color(1.0, 0.58, 0.10, 0.95), Color(0.80, 0.26, 0.05, 0.85),
			 		Color(0.22, 0.18, 0.17, 0.50), Color(0.12, 0.11, 0.12, 0.0)]},
			{"t": 0.30, "tex": "smoke",
			 "colors": [Color(0.62, 0.30, 0.08, 0.85), Color(0.30, 0.16, 0.08, 0.75),
			 		Color(0.14, 0.12, 0.12, 0.0)]},
		]
		for beat in cap_beats:
			var bt := holder.create_tween()
			bt.tween_interval(float(beat["t"]))
			bt.tween_callback(func() -> void:
				if is_instance_valid(holder):
					_particle(holder, cap_pos, 64, 3.5, Vector3(0, 0.55, 0), 74.0, 2.6, 5.4,
							beat["colors"],
							1.35, Vector3(0, 0.75, 0), false,
							{"tex": str(beat["tex"]), "quad": 1.35,
							 "curve": [[0, 0.45], [0.32, 1.45], [0.75, 1.85], [1, 2.25]],
							 "box": Vector3(1.15, 0.32, 1.15), "angular": 2.8, "damping": 1.15,
							 "explosiveness": 0.85, "aabb": mushroom_aabb}))
		# (d) Wilson condensation ring: pale vapor annulus encircling the stem
		if not reduced:
			var wt := holder.create_tween()
			wt.tween_interval(0.10)
			wt.tween_callback(func() -> void:
				if is_instance_valid(holder):
					_ring_quad(holder, Vector3(0, 1.25, 0), 0.85, Color(0.92, 0.94, 0.98, 0.72), 9.5, 0.55, false))
	else:
		# Stage 2a: Heavy buoyant dark soot mushroom column rising and curling upward
		_particle(holder, Vector3(0, 0.45, 0), 46, 2.55, Vector3.UP, 36.0, 1.2, 3.8,
				[Color(0.24, 0.21, 0.20, 0.84), Color(0.16, 0.16, 0.18, 0.56), COL_SMOKE_DARK],
				2.35, Vector3(0, 1.35, 0), false,
				{"tex": "smoke", "quad": 1.40, "curve": [[0, 0.55], [0.35, 1.25], [1, 2.35]],
				 "angular": 2.0, "damping": 0.72, "explosiveness": 0.82})

		# Stage 2b: Low ground-hugging blast soot/dust skirt anchoring the explosion to terrain
		_particle(holder, Vector3(0, 0.22, 0), 22, 1.15, Vector3(0, 0.18, 1), 88.0, 4.2, 9.2,
				[Color(0.42, 0.36, 0.30, 0.72), Color(0.24, 0.22, 0.20, 0.38), Color(0.18, 0.16, 0.15, 0.0)],
				1.35, Vector3(0, 0.35, 0), false,
				{"tex": "smoke", "quad": 1.15, "curve": [[0, 0.45], [0.35, 1.15], [1, 1.85]],
				 "damping": 2.4, "angular": 1.8, "explosiveness": 0.96})

		# Dual expanding ground shockwave rings: crisp thermal wave + matte dust wave
		if not reduced:
			_ring_quad(holder, Vector3(0, 0.24, 0), 0.56, Color(1.0, 0.80, 0.36, 0.95), 7.2, 0.36, false)
			_ring_quad(holder, Vector3(0, 0.16, 0), 1.05, Color(0.54, 0.48, 0.41, 0.72), 9.0, 0.68, true)

	# Stage 4: Irregular hot-to-char shrapnel shards (no harsh floating box shadows!)
	_ensure_rubble_pool()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pieces := 0 if (reduced or mushroom) else int(11 * _q())
	if pieces > 0:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = COL_CHAR
		mat.emission_enabled = true
		mat.emission = COL_EMBER
		mat.emission_energy_multiplier = 2.2
		mat.roughness = 0.82
		mat.metallic = 0.25
		for i in range(pieces):
			var variant := i % _rubble_meshes.size()
			var chunk := RigidBody3D.new()
			chunk.mass = rng.randf_range(2.0, 8.0)
			chunk.collision_layer = 0
			chunk.collision_mask = 0
			var col := CollisionShape3D.new()
			col.shape = _rubble_shapes[variant]
			chunk.add_child(col)
			var mesh := MeshInstance3D.new()
			mesh.mesh = _rubble_meshes[variant]
			mesh.material_override = mat
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chunk.add_child(mesh)
			chunk.add_to_group("vfx_shard")
			parent.add_child(chunk)
			_cap_group(parent, "vfx_shard", MAX_EXPLOSION_SHARDS)
			debris_chunks.append(chunk)
			chunk.global_position = pos + Vector3(rng.randf_range(-0.45, 0.45),
					rng.randf_range(0.25, 0.95), rng.randf_range(-0.45, 0.45)) * scale
			var v_scale := clampf(scale, 0.85, 1.75)
			chunk.linear_velocity = Vector3(rng.randf_range(-8.5, 8.5), rng.randf_range(4.5, 11.5),
					rng.randf_range(-8.5, 8.5)) * v_scale
			chunk.angular_velocity = Vector3(rng.randf_range(-11, 11), rng.randf_range(-11, 11),
					rng.randf_range(-11, 11))
		var cool := holder.create_tween()
		cool.tween_property(mat, "emission_energy_multiplier", 0.0, 0.85)

	# Stage 5: Secondary internal detonation beat for visceral multi-stage punch
	if not reduced and not mushroom:
		var pop := holder.create_tween()
		pop.tween_interval(0.14)
		pop.tween_callback(func() -> void:
			if is_instance_valid(holder):
				var off := Vector3(rng.randf_range(-0.35, 0.35), 0.78, rng.randf_range(-0.35, 0.35))
				_flash_billboard(holder, off, 1.35, COL_AMBER, 0.12)
				_particle(holder, off, 14, 0.48, Vector3.UP, 60.0, 1.8, 5.2,
						[Color(1.0, 0.86, 0.36, 0.95), Color(0.95, 0.36, 0.05, 0.78),
						 Color(0.22, 0.10, 0.06, 0.0)],
						0.85, Vector3(0, 1.8, 0), false,
						{"tex": "fire", "quad": 1.05, "curve": [[0, 0.5], [0.35, 1.2], [1, 0.2]],
						 "damping": 2.4, "explosiveness": 1.0}))

	scorch(parent, pos, scale)

	var cleanup := holder.create_tween()
	cleanup.tween_interval(4.8 if mushroom else 3.4)
	cleanup.tween_callback(func() -> void:
		for c in debris_chunks:
			if is_instance_valid(c):
				c.remove_from_group("vfx_shard")
				c.queue_free()
		if is_instance_valid(holder):
			holder.queue_free())


# ------------------------------------------------------------- death VFX -----

static func _build_death_wreck(pos: Vector3, basis: Basis, is_pogo: bool,
		rng: RandomNumberGenerator) -> RigidBody3D:
	## Cosmetic tumbling wreck: no collision layers/masks, never blocks the track.
	var wreck := RigidBody3D.new()
	wreck.mass = 18.0
	wreck.collision_layer = 0
	wreck.collision_mask = 0
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.10, 0.09, 0.09)
	frame_mat.emission_enabled = true
	frame_mat.emission = COL_EMBER
	frame_mat.emission_energy_multiplier = 1.6
	frame_mat.roughness = 0.85
	frame_mat.metallic = 0.3
	var cast_off := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not is_pogo:
		# Blackened quad chassis silhouette: central frame box + two axle crossbars
		var frame := BoxMesh.new()
		frame.size = Vector3(0.62, 0.22, 1.35)
		frame.material = frame_mat
		var fi := MeshInstance3D.new()
		fi.mesh = frame
		fi.position = Vector3(0.0, 0.05, 0.0)
		fi.cast_shadow = cast_off
		wreck.add_child(fi)
		for z in [0.52, -0.52]:
			var axle := BoxMesh.new()
			axle.size = Vector3(1.3, 0.10, 0.12)
			axle.material = frame_mat
			var ai := MeshInstance3D.new()
			ai.mesh = axle
			ai.position = Vector3(0.0, -0.08, z)
			ai.cast_shadow = cast_off
			wreck.add_child(ai)
	else:
		# Charred pogo stick, bent, with a glowing banana-blaster still in its hand
		_stick_wreck_mesh(wreck, frame_mat, cast_off)
	wreck.transform = Transform3D(basis.orthonormalized(), pos + Vector3(0, 0.55, 0))
	wreck.linear_velocity = Vector3(rng.randf_range(-4.5, 4.5),
			rng.randf_range(9.5, 12.8), rng.randf_range(-4.5, 4.5))
	wreck.angular_velocity = Vector3(rng.randf_range(-14, 14),
			rng.randf_range(-10, 10), rng.randf_range(-14, 14))
	wreck.add_to_group("death_wreck")
	# Continuous fire-and-soot plume streaming off the wreck (one_shot = false)
	var plume := GPUParticles3D.new()
	plume.amount = maxi(4, int(26 * _q()))
	plume.lifetime = 0.85
	plume.one_shot = false
	plume.local_coords = false
	plume.explosiveness = 0.0
	plume.visibility_aabb = AABB(Vector3(-4, -6, -4), Vector3(8, 14, 8))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 24.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, 2.6, 0)
	pm.scale_min = 0.28
	pm.scale_max = 0.85
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.28
	pm.color_ramp = _ramp([Color(1.0, 0.62, 0.12, 0.9), Color(0.75, 0.22, 0.05, 0.6),
			Color(0.12, 0.11, 0.12, 0.0)])
	plume.process_material = pm
	plume.draw_pass_1 = _sprite_quad(false, "fire", 0.55)
	wreck.add_child(plume)
	plume.emitting = true
	return wreck


static func _stick_wreck_mesh(wreck: RigidBody3D, frame_mat: StandardMaterial3D,
		cast_off: int) -> void:
	var stick := CylinderMesh.new()
	stick.top_radius = 0.05
	stick.bottom_radius = 0.07
	stick.height = 1.15
	stick.material = frame_mat
	var si := MeshInstance3D.new()
	si.mesh = stick
	si.position = Vector3(0.0, 0.1, 0.0)
	si.rotation_degrees = Vector3(38.0, 0.0, 24.0)
	si.cast_shadow = cast_off
	wreck.add_child(si)
	var banana_mat := frame_mat.duplicate() as StandardMaterial3D
	banana_mat.emission = Color(1.0, 0.85, 0.25)
	banana_mat.emission_energy_multiplier = 2.4
	var blaster := CapsuleMesh.new()
	blaster.radius = 0.075
	blaster.height = 0.42
	blaster.material = banana_mat
	var bi := MeshInstance3D.new()
	bi.mesh = blaster
	bi.position = Vector3(0.0, 0.44, 0.26)
	bi.rotation_degrees = Vector3(72.0, 0.0, 0.0)
	bi.cast_shadow = cast_off
	wreck.add_child(bi)


static func dramatic_death_explosion(parent: Node3D, pos: Vector3, basis: Basis,
		color: Color, is_pogo: bool = false) -> void:
	## 4-beat death sequence: primary detonation, launch shockwave, tumbling
	## charred wreck with a fire plume, then two staggered mid-air cook-offs.
	if parent == null:
		return
	var reduced := Settings.reduced_motion()
	# Beat 1: primary 1.65x kill detonation + golden kill-spark shower
	particle_explosion(parent, pos, color, 1.65, false)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_particle(parent, pos + Vector3(0, 0.3, 0), 36, 1.1, Vector3.UP, 72.0, 9.0, 22.0,
			[Color(1.0, 0.96, 0.70, 1.0), Color(1.0, 0.62, 0.15, 0.9),
			 Color(0.88, 0.22, 0.04, 0.0)],
			0.24, Vector3(0, -9.0, 0), true,
			{"tex": "streak", "align": true, "curve": [[0, 1.0], [0.55, 0.8], [1, 0.0]],
			 "explosiveness": 0.96})
	if reduced:
		return
	_ring_quad(parent, pos + Vector3(0, 0.4, 0), 0.6, Color(1.0, 0.82, 0.35, 0.95), 9.2, 0.5, false)
	# Beat 2: tumbling charred wreck hurled skyward (capped, fully cosmetic)
	var tree := parent.get_tree()
	var wreck_count := tree.get_nodes_in_group("death_wreck").size() if tree != null else MAX_WRECKS
	if wreck_count >= MAX_WRECKS:
		return
	var wreck := _build_death_wreck(pos, basis, is_pogo, rng)
	parent.add_child(wreck)
	# Beat 3: two staggered mid-air cook-offs tracking the tumbling wreck
	var cook := func(sz: float) -> void:
		if not is_instance_valid(wreck):
			return
		var wp := wreck.global_position
		_flash_billboard(parent, wp, sz, COL_AMBER, 0.14)
		_particle(parent, wp, 22, 0.55, Vector3.UP, 68.0, 2.2, 6.8,
				[Color(1.0, 0.86, 0.36, 0.95), Color(0.95, 0.36, 0.05, 0.78),
				 Color(0.20, 0.09, 0.05, 0.0)],
				0.9, Vector3(0, 0.6, 0), false,
				{"tex": "fire", "quad": 1.1, "curve": [[0, 0.5], [0.35, 1.25], [1, 0.25]],
				 "damping": 2.0, "explosiveness": 1.0})
		_particle(parent, wp, 14, 0.8, Vector3.UP, 80.0, 5.0, 12.0,
				[Color(1.0, 0.9, 0.55, 1.0), Color(1.0, 0.5, 0.1, 0.85), Color(0.7, 0.15, 0.03, 0.0)],
				0.2, Vector3(0, -6.0, 0), true,
				{"tex": "streak", "align": true, "curve": [[0, 1.0], [1, 0.0]],
				 "explosiveness": 0.95})
	var seq := parent.create_tween()
	seq.tween_interval(0.24)
	seq.tween_callback(func() -> void: cook.call(1.35))
	seq.tween_interval(0.28)  # absolute t = 0.52s
	seq.tween_callback(func() -> void: cook.call(1.7))
	seq.tween_interval(1.13)  # absolute t = 1.65s — wreck shatters into embers
	seq.tween_callback(func() -> void:
		if is_instance_valid(wreck):
			wreck.remove_from_group("death_wreck")
			wreck.queue_free())


# ------------------------------------------------------------------ dust -----

static func dust_puff(parent: Node3D, local_pos: Vector3, amount: int = 64) -> void:
	if parent == null:
		return
	_particle(parent, local_pos, amount, 1.2, Vector3.UP, 78.0, 2.0, 5.2,
			[Color(0.76, 0.70, 0.62, 0.95), Color(0.58, 0.52, 0.45, 0.7),
			 Color(0.50, 0.45, 0.39, 0.0)], 1.5, Vector3(0, -2.0, 0), false,
			{"tex": "smoke", "quad": 1.15, "curve": [[0, 0.7], [0.4, 1.15], [1, 1.6]], "angular": 1.2})


static func dust_ring(parent: Node3D, pos: Vector3, radius: float = 1.2,
		amount: float = 5.0) -> void:
	## Ground-hugging dust wave for ramp landings and building collapse.
	if parent == null or Settings.reduced_motion():
		return
	_ring_quad(parent, Vector3(pos.x, pos.y + 0.10, pos.z), radius,
			Color(0.72, 0.66, 0.57, 0.55), amount, 0.65, true)
	_particle(parent, Vector3(pos.x, pos.y + 0.16, pos.z), 16, 0.7, Vector3.UP, 60.0, 1.2, 3.2,
			[Color(0.72, 0.66, 0.58, 0.6), Color(0.5, 0.46, 0.4, 0.0)], 0.7,
			Vector3(0, -1.2, 0), false, {"tex": "smoke", "quad": 1.1})


static func roost(parent: Node3D, pos: Vector3, forward: Vector3) -> void:
	## Rear-wheel dirt/rooster-tail kicked up at speed or under hard steering.
	if parent == null or _q() <= 0.0:
		return
	var fwd := forward
	if fwd.length_squared() < 1e-8:
		fwd = Vector3.FORWARD
	_particle(parent, pos, 6, 0.42, -fwd.normalized() + Vector3.UP * 0.45, 42.0, 1.6, 4.0,
			[Color(0.72, 0.68, 0.62, 0.55), Color(0.55, 0.52, 0.48, 0.0)], 0.34,
			Vector3(0, -2.4, 0), false, {"tex": "smoke", "quad": 0.9})


static func tire_smoke(parent: Node3D, pos: Vector3) -> void:
	if parent == null or _q() <= 0.0:
		return
	_particle(parent, pos, 5, 0.55, Vector3.UP, 35.0, 0.5, 1.8,
			[Color(0.62, 0.62, 0.64, 0.45), Color(0.40, 0.40, 0.42, 0.0)], 0.45,
			Vector3(0, 0.25, 0), false, {"tex": "smoke", "quad": 0.9})


static func scorch(parent: Node3D, pos: Vector3, blast_scale: float = 1.0) -> void:
	if parent == null:
		return
	var quad := QuadMesh.new()
	var s := 2.75 * clampf(blast_scale, 0.80, 2.65)
	quad.size = Vector2(s, s)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.04, 0.04, 0.78)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _scorch_sprite()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = m
	var disc := MeshInstance3D.new()
	disc.mesh = quad
	disc.position = Vector3(pos.x, 0.024, pos.z)
	disc.rotation_degrees.x = -90.0
	disc.rotation_degrees.z = randf_range(0.0, 360.0)
	disc.add_to_group("vfx_scorch")
	parent.add_child(disc)
	_cap_group(parent, "vfx_scorch", MAX_SCORCH)
	var t := disc.create_tween()
	t.tween_interval(7.0)
	t.tween_property(m, "albedo_color:a", 0.0, 4.0)
	t.tween_callback(func() -> void:
		if is_instance_valid(disc):
			disc.remove_from_group("vfx_scorch")
			disc.queue_free())


# ---------------------------------------------------------------- smash ------

static func smash_burst(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	## Structural collapse in three beats: glass flash, dust wave, settling puffs.
	if parent == null:
		return
	_flash_billboard(parent, pos + Vector3(0, 1.0, 0), 1.4, Color(0.86, 0.94, 1.0), 0.12)
	var tree := parent.get_tree()
	if tree == null:
		return
	if Settings.reduced_motion():
		_static_cue(parent, Vector3(pos.x, 0.25, pos.z), Color(0.75, 0.68, 0.58, 0.85), 1.6, 0.35)
		return
	# glass glints
	_particle(parent, pos + Vector3(0, 1.2, 0), 20, 0.75, Vector3.UP, 80.0, 3.0, 9.0,
			[Color(0.85, 0.95, 1.0, 0.9), COL_GLASS, Color(0.5, 0.7, 0.9, 0.0)],
			0.11, Vector3(0, -8, 0), true,
			{"tex": "streak", "align": true, "curve": [[0, 1], [1, 0.05]]})
	# timber/metal splinters
	_particle(parent, pos + Vector3(0, 1.0, 0), 18, 1.1, Vector3.UP, 70.0, 2.5, 7.5,
			[Color(0.55, 0.42, 0.30, 0.9), Color(0.30, 0.26, 0.23, 0.0)],
			0.20, Vector3(0, -6, 0), false,
			{"tex": "streak", "align": true, "curve": [[0, 1], [1, 0.1]]})
	# ground shockwave scaled to the building footprint
	var reach := maxf(size.x, size.z) * 0.85
	_ring_quad(parent, Vector3(pos.x, 0.10, pos.z), 0.9,
			Color(0.72, 0.66, 0.57, 0.6), reach, 0.8, true)
	# staggered dust columns: the building settles instead of vanishing
	var puffs := [
		{"d": 0.0, "h": 0.7, "o": Vector3(0, 0, 0)},
		{"d": 0.12, "h": 1.5, "o": Vector3(size.x * 0.2, 0, -size.z * 0.15)},
		{"d": 0.28, "h": 2.3, "o": Vector3(-size.x * 0.18, 0, size.z * 0.18)},
	]
	var w_parent: WeakRef = weakref(parent)
	for spec in puffs:
		var delay: float = spec["d"]
		var local: Vector3 = spec["o"]
		var height: float = spec["h"]
		var timer := tree.create_timer(delay)
		timer.timeout.connect(func() -> void:
			var p_node := w_parent.get_ref() as Node3D
			if p_node != null and p_node.is_inside_tree():
				# Anchor to the collapse site: `local` is a relative offset,
				# not a world-space position.
				dust_puff(p_node, pos + local + Vector3(0, height, 0), 22))


# --------------------------------------------------------------- pickups -----

static func pickup_burst(parent: Node3D, pos: Vector3, color: Color) -> void:
	if parent == null:
		return
	shield_pulse(parent, pos, color)
	_flash_billboard(parent, pos, 0.7, color, 0.14)
	if Settings.reduced_motion():
		_static_cue(parent, pos, color, 0.7, 0.16)
		# Pulse rings are suppressed too, so replace them with one static ring.
		_static_cue(parent, pos, Color(1, 1, 1, 0.8), 0.34, 0.16)
		return
	_particle(parent, pos, 18, 0.75, Vector3.UP, 18.0, 2.0, 5.5,
			[Color(color.r, color.g, color.b, 0.9), Color(1, 1, 1, 0.7),
			 Color(color.r, color.g, color.b, 0.0)], 0.14, Vector3(0, -1.5, 0), true,
			{"tex": "streak", "align": true, "curve": [[0, 1], [1, 0.05]]})


# ------------------------------------------------------------- UI / misc -----

static func damage_number(parent: Node3D, pos: Vector3, amount: float, color: Color) -> void:
	if parent == null:
		return
	var label := Label3D.new()
	label.text = "-%d" % int(amount)
	# Meteor and heavy-blast hits get a bigger read than chip damage.
	label.font_size = 76 if amount >= 85.0 else 64
	label.outline_size = 14
	label.outline_modulate = Color(0.12, 0.05, 0.02, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Never clip the number inside the vehicle mesh.
	label.no_depth_test = true
	label.modulate = color
	# Scatter horizontally so twin-barrel hits don't stack on the same pixel.
	label.position = pos + Vector3(randf_range(-0.28, 0.28), 0.8, 0.0)
	label.add_to_group("vfx_dmg_num")
	parent.add_child(label)
	_cap_group(parent, "vfx_dmg_num", MAX_DAMAGE_NUMBERS)
	var cleanup_lbl := func() -> void:
		if is_instance_valid(label):
			label.remove_from_group("vfx_dmg_num")
			label.queue_free()
	var t := label.create_tween()
	if Settings.reduced_motion():
		t.tween_interval(0.75)
		t.tween_callback(cleanup_lbl)
		return
	label.scale = Vector3.ONE * 1.35
	t.tween_property(label, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(label, "position", label.position + Vector3(0.0, 1.65, 0.0), 0.75)
	t.parallel().tween_property(label, "modulate:a", 0.0, 0.75)
	t.parallel().tween_property(label, "outline_modulate:a", 0.0, 0.75)
	t.tween_callback(cleanup_lbl)


static func underglow(parent: Node3D, color: Color) -> Node3D:
	if parent == null:
		return null
	var holder := Node3D.new()
	holder.name = "Underglow"
	holder.position = Vector3(0.0, 0.18, 0.0)
	parent.add_child(holder)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.52
	torus.outer_radius = 0.62
	torus.rings = 16
	var mat := _emissive(Color(color.r, color.g, color.b, 0.7), 2.6)
	torus.material = mat
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.position.y = 0.03
	holder.add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.8
	light.omni_range = 3.4
	holder.add_child(light)
	return holder


static func shield_pulse(parent: Node3D, pos: Vector3, color: Color) -> void:
	if parent == null or Settings.reduced_motion():
		return
	for spec in [{"inner": 0.70, "outer": 0.78, "delay": 0.0, "grow": 1.9},
			{"inner": 0.48, "outer": 0.53, "delay": 0.09, "grow": 1.55}]:
		var torus := TorusMesh.new()
		torus.inner_radius = spec["inner"]
		torus.outer_radius = spec["outer"]
		torus.rings = 18
		var m := _emissive(Color(color.r, color.g, color.b, 0.8), 3.0)
		torus.material = m
		var ring := MeshInstance3D.new()
		ring.mesh = torus
		ring.position = pos
		parent.add_child(ring)
		var t := ring.create_tween()
		if spec["delay"] > 0.0:
			t.tween_interval(spec["delay"])
		var grow: float = spec["grow"]
		t.tween_property(ring, "scale", Vector3(grow, grow, grow), 0.7)
		t.parallel().tween_property(m, "albedo_color:a", 0.0, 0.7)
		t.tween_callback(ring.queue_free)
