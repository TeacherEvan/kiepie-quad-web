extends RefCounted
class_name VfxFactory
## Pooled-by-convention particle helpers. Particle counts respect the player's
## quality multiplier. Under reduced-motion, burst particles, debris, shockwave,
## shield pulses and float/flashes are suppressed or replaced with static cues.

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


static func _particle(parent: Node3D, pos: Vector3, amount: int, lifetime: float,
		dir: Vector3, spread: float, speed_min: float, speed_max: float,
		colors: Array, size: float, gravity: Vector3 = Vector3(0, -2.0, 0)) -> GPUParticles3D:
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
	var g := Gradient.new()
	g.set_color(0, colors[0])
	g.set_offset(0, 0.0)
	g.set_color(1, colors[colors.size() - 1])
	g.set_offset(1, 1.0)
	if colors.size() > 2:
		g.add_point(0.45, colors[1])
	var ramp := GradientTexture1D.new()
	ramp.gradient = g
	pm.color_ramp = ramp
	p.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = _emissive(colors[0], 1.8)
	p.draw_pass_1 = sm
	p.position = pos
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


static func muzzle_flash(parent: Node3D, pos: Vector3, dir: Vector3, color: Color) -> void:
	if parent == null:
		return
	var holder := Node3D.new()
	holder.position = pos
	parent.add_child(holder)
	_particle(holder, Vector3.ZERO, 16, 0.16, dir, 20.0, 5.0, 10.0,
			[Color(1, 0.96, 0.72, 1), Color(1, 0.55, 0.12, 0.9), Color(1, 0.2, 0.02, 0)],
			0.5, Vector3.ZERO)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 6.0
	light.omni_range = 3.5
	holder.add_child(light)
	var t := holder.create_tween()
	if Settings.reduced_motion():
		# Static dim flash, freed by a timer - no pulsing light.
		light.light_energy = 2.5
		t.tween_interval(0.14)
	else:
		t.tween_property(light, "light_energy", 0.0, 0.14)
	t.tween_callback(holder.queue_free)


static func impact(parent: Node3D, pos: Vector3, color: Color) -> void:
	if parent == null:
		return
	var holder := Node3D.new()
	holder.position = pos
	parent.add_child(holder)
	_particle(holder, Vector3.ZERO, 22, 0.32, Vector3.UP, 70.0, 3.0, 8.0,
			[Color(1, 0.95, 0.65, 1), color, Color(0.2, 0.2, 0.2, 0)], 0.35)
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

	# core flash
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.3)
	light.light_energy = 22.0
	light.omni_range = 9.0
	holder.add_child(light)
	if Settings.reduced_motion():
		light.light_energy = 7.0  # steady, no fade pulse
	else:
		var lt := holder.create_tween()
		lt.tween_property(light, "light_energy", 0.0, 0.55)

	_particle(holder, Vector3.ZERO, 90, 0.65, Vector3.UP, 60.0, 3.0, 11.0,
			[Color(1, 0.98, 0.78, 1), Color(1, 0.52, 0.08, 1), Color(0.7, 0.12, 0.02, 0)], 1.2)
	_particle(holder, Vector3(0, 0.4, 0), 55, 1.9, Vector3.UP, 48.0, 1.0, 4.0,
			[Color(0.30, 0.30, 0.33, 0.85), Color(0.14, 0.14, 0.16, 0)], 1.7,
			Vector3(0, 0.35, 0))

	# shockwave ring
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

	# debris
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pieces := 0 if Settings.reduced_motion() else int(10 * _q())
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
		bm.material = _emissive(color * rng.randf_range(0.6, 1.0), 1.2)
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


static func damage_number(parent: Node3D, pos: Vector3, amount: float, color: Color) -> void:
	if parent == null:
		return
	var label := Label3D.new()
	label.text = "-%d" % int(amount)
	label.font_size = 48
	label.outline_size = 10
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
	light.light_energy = 1.6
	light.omni_range = 3.2
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
	var torus := TorusMesh.new()
	torus.inner_radius = 0.7
	torus.outer_radius = 0.78
	torus.rings = 18
	var m := _emissive(Color(color.r, color.g, color.b, 0.8), 3.0)
	torus.material = m
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.position = pos
	parent.add_child(ring)
	var t := ring.create_tween()
	t.tween_property(ring, "scale", Vector3(1.9, 1.9, 1.9), 0.7)
	t.parallel().tween_property(m, "albedo_color:a", 0.0, 0.7)
	t.tween_callback(ring.queue_free)
