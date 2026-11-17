extends RefCounted
class_name VfxFactory
## Pooled-by-convention particle helpers. Particle counts respect the player's
## quality multiplier. Under reduced-motion, burst particles, debris, shockwave,
## shield pulses and float/flashes are suppressed or replaced with static cues.
##
## Visual style: teen/mature "hot metal" — near-white cores, amber-to-ember
## ramps, additive sparks, dark billowing smoke. All materials are unshaded /
## emissive so they read correctly on the gl_compatibility Web renderer.

# Hot-to-cold combat palette (sRGB). Kept in one place so every effect agrees.
const COL_CORE := Color(1.0, 0.96, 0.78, 1.0)      # near-white flash
const COL_AMBER := Color(1.0, 0.82, 0.25, 1.0)     # hot amber
const COL_ORANGE := Color(1.0, 0.54, 0.12, 1.0)    # cannon orange
const COL_EMBER := Color(0.89, 0.24, 0.04, 1.0)    # ember red-orange
const COL_SMOKE := Color(0.16, 0.16, 0.18, 0.85)   # billow smoke
const COL_SMOKE_DARK := Color(0.09, 0.09, 0.11, 0.0)
const COL_BRASS := Color(0.83, 0.58, 0.15, 1.0)    # ejected casings
const COL_STEAM := Color(0.82, 0.84, 0.88, 0.55)   # overheat vent

static func _q() -> float:
	return maxf(0.0, Settings.quality_multiplier())


static func _emissive(color: Color, energy: float = 2.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static var _soft_tex: GradientTexture2D = null

static func _soft_sprite() -> GradientTexture2D:
	## Shared radial-gradient sprite (white core -> transparent rim) so
	## particles render as soft puffs/glows instead of hard-edged meshes.
	if _soft_tex == null:
		var g := Gradient.new()
		# offset 0 at the center, offset 1 at the rim. RGB fades to black with
		# the alpha (premultiplied style) so mipmapped minification has no
		# bright fringe ring around the glow.
		g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		g.colors = PackedColorArray([
			Color(1.0, 1.0, 1.0, 1.0),
			Color(0.55, 0.55, 0.55, 0.6),
			Color(0.0, 0.0, 0.0, 0.0),
		])
		var t := GradientTexture2D.new()
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 1.0)
		t.width = 128
		t.height = 128
		t.gradient = g
		_soft_tex = t
	return _soft_tex


static func _sprite_material(additive: bool) -> StandardMaterial3D:
	## Billboarded soft particle material. The particle color ramp supplies
	## hue and alpha; the material only carries the blend mode.
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_sprite()
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


static func _additive(color: Color, energy: float = 2.5) -> StandardMaterial3D:
	var m := _emissive(color, energy)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


static func _ramp(colors: Array) -> GradientTexture1D:
	## A fresh Gradient has exactly two points; set_color/set_offset at index 2
	## is an out-of-bounds write that silently drops the transparent fade stop.
	## Seed the two endpoints, then add interior stops explicitly.
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
	return ramp


static func _particle(parent: Node3D, pos: Vector3, amount: int, lifetime: float,
		dir: Vector3, spread: float, speed_min: float, speed_max: float,
		colors: Array, size: float, gravity: Vector3 = Vector3(0, -2.0, 0),
		additive: bool = false) -> GPUParticles3D:
	if Settings.reduced_motion():
		return null
	var p := GPUParticles3D.new()
	p.amount = maxi(2, int(amount * _q()))
	p.lifetime = lifetime
	p.one_shot = true
	p.local_coords = false
	p.explosiveness = 0.85
	p.visibility_aabb = AABB(Vector3(-6, -4, -6), Vector3(12, 12, 12))
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized()
	pm.spread = spread
	pm.gravity = gravity
	pm.initial_velocity_min = speed_min
	pm.initial_velocity_max = speed_max
	pm.scale_min = size * 0.45
	pm.scale_max = size * 1.4
	pm.color_ramp = _ramp(colors)
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.42
	quad.material = _sprite_material(additive)
	p.draw_pass_1 = quad
	p.position = pos
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


static func _flash_billboard(parent: Node3D, pos: Vector3, size: float,
		color: Color, duration: float) -> void:
	## Short-lived additive camera-facing star flash (muzzle / impact pop).
	if Settings.reduced_motion():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var m := _additive(color, 4.0)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = m
	var inst := MeshInstance3D.new()
	inst.mesh = quad
	inst.position = pos
	parent.add_child(inst)
	var t := inst.create_tween()
	t.tween_property(inst, "scale", Vector3(1.9, 1.9, 1.9), duration)
	t.parallel().tween_property(m, "albedo_color:a", 0.0, duration)
	t.tween_callback(inst.queue_free)


static func muzzle_flash(parent: Node3D, pos: Vector3, dir: Vector3, color: Color) -> void:
	if parent == null:
		return
	var holder := Node3D.new()
	holder.position = pos
	parent.add_child(holder)
	# hot core burst along the barrel
	_particle(holder, Vector3.ZERO, 16, 0.16, dir, 20.0, 5.0, 10.0,
			[Color(1.0, 0.85, 0.45, 0.9), Color(1.0, 0.58, 0.14, 0.7),
			 Color(0.89, 0.24, 0.04, 0.0)], 0.5, Vector3.ZERO, true)
	# lingering smoke wisp after the shot
	_particle(holder, Vector3.ZERO, 6, 0.7, dir * 0.5 + Vector3.UP * 0.5, 35.0, 1.2, 2.6,
			[Color(0.36, 0.36, 0.38, 0.55), COL_SMOKE_DARK], 0.42,
			Vector3(0, 0.6, 0), false)
	# camera-facing pop at the barrel tip
	_flash_billboard(holder, Vector3.ZERO, 0.85, COL_CORE, 0.12)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 7.5
	light.omni_range = 4.0
	holder.add_child(light)
	var t := holder.create_tween()
	if Settings.reduced_motion():
		# Static dim flash, freed by a timer - no pulsing light.
		light.light_energy = 2.5
		t.tween_interval(0.14)
	else:
		t.tween_property(light, "light_energy", 0.0, 0.14)
	t.tween_callback(holder.queue_free)


static func casing(parent: Node3D, pos: Vector3, eject_dir: Vector3) -> void:
	## Eject a brass shell out of the breech of whichever barrel just fired.
	## No collision (layer/mask 0) so casings never intersect physics queries.
	if parent == null:
		return
	var body := RigidBody3D.new()
	body.mass = 0.02
	body.collision_layer = 0
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.028
	shape.height = 0.075
	col.shape = shape
	body.add_child(col)
	var mesh := MeshInstance3D.new()
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
	mesh.mesh = cyl
	body.add_child(mesh)
	parent.add_child(body)
	var out := eject_dir.normalized()
	body.global_position = pos + out * 0.08 + Vector3(0, 0.05, 0)
	body.linear_velocity = out * 2.6 + Vector3(0, 2.4, 0)
	body.angular_velocity = Vector3(randf_range(-14, 14), randf_range(-14, 14),
			randf_range(-14, 14))
	var t := body.create_tween()
	t.tween_interval(2.4)
	t.tween_callback(body.queue_free)


static func steam_vent(parent: Node3D, pos: Vector3) -> void:
	## Overheat cue: a short white steam burst from a hot barrel.
	if parent == null:
		return
	_particle(parent, pos, 12, 0.85, Vector3.UP, 28.0, 1.6, 3.4,
			[COL_STEAM, Color(COL_STEAM.r, COL_STEAM.g, COL_STEAM.b, 0.0)], 0.34,
			Vector3(0, -0.4, 0), false)


static func impact(parent: Node3D, pos: Vector3, color: Color) -> void:
	if parent == null:
		return
	var holder := Node3D.new()
	holder.position = pos
	parent.add_child(holder)
	# additive spark spray, hot near-white
	_particle(holder, Vector3.ZERO, 14, 0.28, Vector3.UP, 95.0, 4.5, 9.5,
			[Color(1.0, 0.92, 0.62, 0.85), Color(1.0, 0.66, 0.20, 0.6),
			 Color(0.89, 0.24, 0.04, 0.0)], 0.22, Vector3(0, -9.0, 0), true)
	# heavier smoke/ember follow-through
	_particle(holder, Vector3.ZERO, 22, 0.34, Vector3.UP, 70.0, 3.0, 8.0,
			[Color(1, 0.95, 0.65, 1), color, COL_SMOKE_DARK], 0.36,
			Vector3(0, -2.0, 0), false)
	_flash_billboard(holder, Vector3.ZERO, 0.6, COL_CORE, 0.10)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.5
	light.omni_range = 2.6
	holder.add_child(light)
	if not Settings.reduced_motion():
		var lt := holder.create_tween()
		lt.tween_property(light, "light_energy", 0.0, 0.12)
	else:
		light.light_energy = 1.6
	var t := holder.create_tween()
	t.tween_interval(0.8)
	t.tween_callback(holder.queue_free)


static func explosion(parent: Node3D, pos: Vector3, color: Color, scale: float = 1.0) -> void:
	if parent == null:
		return
	var holder := Node3D.new()
	holder.name = "Explosion"
	holder.position = pos
	holder.scale = Vector3.ONE * scale
	parent.add_child(holder)

	# core flash — hot, with a fast attack and slightly slower release
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.74, 0.34)
	light.light_energy = 26.0
	light.omni_range = 10.0
	holder.add_child(light)
	if Settings.reduced_motion():
		light.light_energy = 7.0  # steady, no fade pulse
	else:
		var lt := holder.create_tween()
		lt.tween_property(light, "light_energy", 26.0, 0.05).from(0.0)
		lt.tween_property(light, "light_energy", 0.0, 0.5)

	# fireball: white-hot core -> amber -> ember -> dark smoke
	_particle(holder, Vector3.ZERO, 90, 0.68, Vector3.UP, 62.0, 3.0, 11.5,
			[Color(1.0, 0.78, 0.30, 0.85), Color(1.0, 0.52, 0.10, 0.65),
			 Color(0.82, 0.20, 0.02, 0.0)], 1.05, Vector3(0, -1.2, 0), true)
	# long-lived dark billow rising off the fireball
	_particle(holder, Vector3(0, 0.5, 0), 55, 2.0, Vector3.UP, 48.0, 1.0, 4.2,
			[Color(0.30, 0.30, 0.33, 0.85), COL_SMOKE, COL_SMOKE_DARK], 1.75,
			Vector3(0, 0.35, 0), false)
	# ember spray — small, fast, gravity-bound, additive
	_particle(holder, Vector3(0, 0.3, 0), 40, 1.15, Vector3.UP, 75.0, 6.0, 13.0,
			[Color(1.0, 0.80, 0.35, 0.8), Color(1.0, 0.48, 0.08, 0.55),
			 Color(0.89, 0.24, 0.04, 0.0)], 0.16, Vector3(0, -7.5, 0), true)

	# camera-facing core pop at detonation
	_flash_billboard(holder, Vector3(0, 0.4, 0), 2.4, COL_CORE, 0.16)

	# shockwave ring — hot expanding torus
	if not Settings.reduced_motion():
		var torus := TorusMesh.new()
		torus.inner_radius = 0.45
		torus.outer_radius = 0.62
		torus.rings = 20
		var m := _emissive(Color(1.0, 0.72, 0.30, 0.85), 3.0)
		m.albedo_color.a = 0.85
		torus.material = m
		var ring := MeshInstance3D.new()
		ring.mesh = torus
		ring.rotation_degrees.x = 90.0
		ring.position.y = 0.25
		holder.add_child(ring)
		var rt := ring.create_tween()
		rt.tween_property(ring, "scale", Vector3(5.5, 5.5, 1.0), 0.45)
		rt.parallel().tween_property(m, "albedo_color:a", 0.0, 0.45)

	# ground dust ring — wider, slower, matte (not emissive)
	if not Settings.reduced_motion():
		var dust_torus := TorusMesh.new()
		dust_torus.inner_radius = 0.8
		dust_torus.outer_radius = 1.15
		dust_torus.rings = 14
		var dust_mat := StandardMaterial3D.new()
		dust_mat.albedo_color = Color(0.42, 0.38, 0.33, 0.7)
		dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dust_torus.material = dust_mat
		var dust := MeshInstance3D.new()
		dust.mesh = dust_torus
		dust.rotation_degrees.x = 90.0
		dust.position.y = 0.18
		holder.add_child(dust)
		var dt := dust.create_tween()
		dt.tween_property(dust, "scale", Vector3(7.5, 7.5, 1.0), 0.7)
		dt.parallel().tween_property(dust_mat, "albedo_color:a", 0.0, 0.7)

	# debris — hot ember chunks that cool as they fly
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pieces := 0 if Settings.reduced_motion() else int(12 * _q())
	for i in range(pieces):
		var size := rng.randf_range(0.12, 0.38)
		var chunk := RigidBody3D.new()
		chunk.mass = rng.randf_range(2.0, 8.0)
		chunk.collision_layer = 0
		chunk.collision_mask = 0
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3.ONE * size
		col.shape = box
		chunk.add_child(col)
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * size
		bm.material = _emissive(COL_EMBER * rng.randf_range(0.55, 1.0), 1.6)
		mesh.mesh = bm
		chunk.add_child(mesh)
		holder.add_child(chunk)
		chunk.global_position = pos + Vector3(rng.randf_range(-0.5, 0.5),
				rng.randf_range(0.2, 1.0), rng.randf_range(-0.5, 0.5))
		chunk.linear_velocity = Vector3(rng.randf_range(-6, 6), rng.randf_range(3, 9),
				rng.randf_range(-6, 6))
		chunk.angular_velocity = Vector3(rng.randf_range(-8, 8), rng.randf_range(-8, 8), rng.randf_range(-8, 8))

	scorch(parent, pos)

	var cleanup := holder.create_tween()
	cleanup.tween_interval(3.2)
	cleanup.tween_callback(holder.queue_free)


static func dust_puff(parent: Node3D, local_pos: Vector3, amount: int = 64) -> void:
	## Wide, slow tan dust burst for building smashes. Soft sprite particles,
	## quality-scaled and reduced-motion aware via _particle().
	if parent == null:
		return
	_particle(parent, local_pos, amount, 1.15, Vector3.UP, 78.0, 2.2, 5.4,
			[Color(0.74, 0.68, 0.60, 0.95), Color(0.58, 0.53, 0.46, 0.75),
			 Color(0.55, 0.50, 0.44, 0.0)], 1.45, Vector3(0, -2.2, 0))


static func damage_number(parent: Node3D, pos: Vector3, amount: float, color: Color) -> void:
	if parent == null:
		return
	var label := Label3D.new()
	label.text = "-%d" % int(amount)
	label.font_size = 56
	label.outline_size = 12
	label.outline_modulate = Color(0.12, 0.05, 0.02, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.position = pos + Vector3(0.0, 0.8, 0.0)
	parent.add_child(label)
	var t := label.create_tween()
	if Settings.reduced_motion():
		t.tween_interval(0.65)  # static number, no float-up
	else:
		t.tween_property(label, "position", label.position + Vector3(0.0, 1.5, 0.0), 0.65)
		t.parallel().tween_property(label, "modulate:a", 0.0, 0.65)
	t.tween_callback(label.queue_free)


static func underglow(parent: Node3D, color: Color) -> Node3D:
	## Emissive ring under the chassis so players are readable at a glance.
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


static func tire_smoke(parent: Node3D, pos: Vector3) -> void:
	if parent == null or _q() <= 0.0:
		return
	_particle(parent, pos, 5, 0.55, Vector3.UP, 35.0, 0.5, 1.8,
			[Color(0.62, 0.62, 0.64, 0.45), Color(0.40, 0.40, 0.42, 0.0)], 0.45,
			Vector3(0, 0.25, 0))


static func scorch(parent: Node3D, pos: Vector3) -> void:
	if parent == null:
		return
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.9
	cyl.bottom_radius = 1.1
	cyl.height = 0.012
	cyl.radial_segments = 16
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.05, 0.05, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl.material = mat
	disc.mesh = cyl
	disc.position = Vector3(pos.x, 0.02, pos.z)
	parent.add_child(disc)
	var t := disc.create_tween()
	t.tween_interval(16.0)
	t.tween_property(mat, "albedo_color:a", 0.0, 4.0)
	t.tween_callback(disc.queue_free)


static func shield_pulse(parent: Node3D, pos: Vector3, color: Color) -> void:
	if parent == null or Settings.reduced_motion():
		return
	# outer ring expands, inner ring lags — a two-beat pulse reads as "energy"
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
