extends RefCounted
## Core combat, driving, and impact VFX.

const S := preload("res://src/game/VfxSprites.gd")

static var _casing_count := 0


static func muzzle_flash(parent: Node3D, pos: Vector3, dir: Vector3, color: Color) -> void:
	if parent == null:
		return
	var holder := Node3D.new()
	holder.position = pos
	parent.add_child(holder)
	var fwd := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD

	# white-hot core burst along the barrel
	S._particle(holder, fwd * 0.18, 14, 0.13, fwd, 16.0, 8.0, 17.0,
			[Color(1, 0.92, 0.60, 0.95), S.COL_AMBER, Color(S.COL_EMBER.r, S.COL_EMBER.g, S.COL_EMBER.b, 0.0)],
			0.30, Vector3(0, -5, 0), true,
			{"tex": "streak", "align": true, "curve": [[0, 0.7], [0.4, 1.0], [1, 0.15]]})
	# lingering smoke wisp after the shot
	S._particle(holder, Vector3.ZERO, 6, 0.75, fwd * 0.4 + Vector3.UP * 0.6, 35.0, 1.1, 2.4,
			[Color(0.38, 0.38, 0.40, 0.5), S.COL_SMOKE_DARK], 0.42,
			Vector3(0, 0.7, 0), false, {"tex": "smoke", "quad": 0.8, "curve": [[0, 0.6], [0.4, 1.1], [1, 1.5]]})
	S._flash_billboard(holder, Vector3.ZERO, 0.85, S.COL_CORE, 0.12)

	# blast disc perpendicular to the barrel — gives the flash a direction
	if not Settings.reduced_motion():
		var disc := QuadMesh.new()
		disc.size = Vector2.ONE * 0.52
		var dm := S._additive(color, 2.6)
		dm.albedo_texture = S._ring_sprite()
		dm.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		dm.cull_mode = BaseMaterial3D.CULL_DISABLED
		disc.material = dm
		var disc_inst := MeshInstance3D.new()
		disc_inst.mesh = disc
		disc_inst.position = fwd * 0.16
		disc_inst.basis = S._plane_basis(fwd)
		holder.add_child(disc_inst)
		var dt := disc_inst.create_tween()
		dt.tween_property(disc_inst, "scale", Vector3(2.1, 2.1, 2.1), 0.14)
		dt.parallel().tween_property(dm, "albedo_color:a", 0.0, 0.14)
		dt.tween_callback(disc_inst.queue_free)

	var smoke_tree := holder.get_tree()
	var lights: Array = smoke_tree.get_nodes_in_group("vfx_light") if smoke_tree != null else []
	if Settings.quality_multiplier() >= 0.75 and lights.size() < S.MAX_IMPACT_LIGHTS:
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
	if parent == null or Settings.reduced_motion() or S._q() <= 0.0:
		return
	# Hard cap on live ejection bodies — a per-shot RigidBody3D is the one
	# VFX node that exercises the physics solver; the Web budget is finite.
	if _casing_count >= S.MAX_CASINGS:
		return
	_casing_count += 1
	S._ensure_casing_pool()
	var body := RigidBody3D.new()
	body.mass = 0.02
	body.collision_layer = 0
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.shape = S._casing_shape
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	mesh.mesh = S._casing_mesh
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
	var spark_col := S.COL_AMBER if surface == "metal" else Color(1, 0.94, 0.72, 1)
	S._particle(holder, Vector3.ZERO, spark_count, 0.26, shot, 85.0, 5.0, 11.0,
			[Color(1, 1, 0.82, 0.9), spark_col, Color(S.COL_EMBER.r, S.COL_EMBER.g, S.COL_EMBER.b, 0.0)],
			0.13, Vector3(0, -9.0, 0), true,
			{"tex": "streak", "align": true, "curve": [[0, 0.9], [0.55, 1.0], [1, 0.05]]})
	var puff_col := Color(0.70, 0.66, 0.60, 0.75) if surface != "metal" else Color(0.55, 0.55, 0.58, 0.7)
	S._particle(holder, Vector3.ZERO, 14, 0.5, normal, 60.0, 1.6, 4.2,
			[puff_col, Color(0.30, 0.30, 0.32, 0.45), S.COL_SMOKE_DARK], 0.28,
			Vector3(0, 0.2, 0), false, {"tex": "smoke", "quad": 0.9})
	S._flash_billboard(holder, Vector3.ZERO, 0.52, S.COL_CORE, 0.09)
	# gl_compatibility has a low real-time light budget: cap concurrent sparks'
	# point lights rather than letting a firefight allocate one per shot.
	var tree := parent.get_tree()
	var lights: Array = tree.get_nodes_in_group("vfx_light") if tree != null else []
	if lights.size() < S.MAX_IMPACT_LIGHTS:
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 4.5
		light.omni_range = 2.6
		light.add_to_group("vfx_light")
		holder.add_child(light)
		var release_light := func() -> void:
			if is_instance_valid(light):
				if light.is_in_group("vfx_light"):
					light.remove_from_group("vfx_light")
				light.queue_free()
		if Settings.reduced_motion():
			light.light_energy = 1.6
			var lt := holder.create_tween()
			lt.tween_interval(0.14)
			lt.tween_callback(release_light)
		else:
			var lt := holder.create_tween()
			lt.tween_property(light, "light_energy", 0.0, 0.12)
			lt.tween_callback(release_light)
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
	m.albedo_texture = S._soft_sprite()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = m
	var inst := MeshInstance3D.new()
	inst.mesh = quad
	inst.position = pos
	inst.basis = S._plane_basis(normal)
	inst.add_to_group("vfx_scar")
	parent.add_child(inst)
	S._cap_group(parent, "vfx_scar", S.MAX_SCAR)
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
	S._flash_billboard(parent, pos, 0.55, color, 0.12)
	if Settings.reduced_motion():
		S._static_cue(parent, pos, color, 0.55, 0.14)
		return
	S._ring_quad(parent, pos, 0.32, color, 2.4, 0.38, false, Vector3.UP)
	S._ring_quad(parent, pos, 0.24, Color(1, 1, 1, 0.8), 1.7, 0.28, false, Vector3.UP)
	S._particle(parent, pos, 12, 0.32, Vector3.UP, 75.0, 2.5, 6.0,
			[Color(color.r, color.g, color.b, 0.9), Color(1, 1, 1, 0.6), Color(color.r, color.g, color.b, 0.0)],
			0.12, Vector3(0, -3, 0), true,
			{"tex": "streak", "align": true, "curve": [[0, 0.8], [1, 0.05]]})


# -------------------------------------------------------------- explosion ----


static func dust_puff(parent: Node3D, local_pos: Vector3, amount: int = 64) -> void:
	if parent == null:
		return
	S._particle(parent, local_pos, amount, 1.2, Vector3.UP, 78.0, 2.0, 5.2,
			[Color(0.76, 0.70, 0.62, 0.95), Color(0.58, 0.52, 0.45, 0.7),
			 Color(0.50, 0.45, 0.39, 0.0)], 1.5, Vector3(0, -2.0, 0), false,
			{"tex": "smoke", "quad": 1.15, "curve": [[0, 0.7], [0.4, 1.15], [1, 1.6]], "angular": 1.2})


static func dust_ring(parent: Node3D, pos: Vector3, radius: float = 1.2,
		amount: float = 5.0) -> void:
	## Ground-hugging dust wave for ramp landings and building collapse.
	if parent == null or Settings.reduced_motion():
		return
	S._ring_quad(parent, Vector3(pos.x, pos.y + 0.10, pos.z), radius,
			Color(0.72, 0.66, 0.57, 0.55), amount, 0.65, true)
	S._particle(parent, Vector3(pos.x, pos.y + 0.16, pos.z), 16, 0.7, Vector3.UP, 60.0, 1.2, 3.2,
			[Color(0.72, 0.66, 0.58, 0.6), Color(0.5, 0.46, 0.4, 0.0)], 0.7,
			Vector3(0, -1.2, 0), false, {"tex": "smoke", "quad": 1.1})


static func roost(parent: Node3D, pos: Vector3, forward: Vector3) -> void:
	## Rear-wheel dirt/rooster-tail kicked up at speed or under hard steering.
	if parent == null or S._q() <= 0.0:
		return
	var fwd := forward
	if fwd.length_squared() < 1e-8:
		fwd = Vector3.FORWARD
	S._particle(parent, pos, 6, 0.42, -fwd.normalized() + Vector3.UP * 0.45, 42.0, 1.6, 4.0,
			[Color(0.72, 0.68, 0.62, 0.55), Color(0.55, 0.52, 0.48, 0.0)], 0.34,
			Vector3(0, -2.4, 0), false, {"tex": "smoke", "quad": 0.9})


static func tire_smoke(parent: Node3D, pos: Vector3) -> void:
	if parent == null or S._q() <= 0.0:
		return
	S._particle(parent, pos, 5, 0.55, Vector3.UP, 35.0, 0.5, 1.8,
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
	m.albedo_texture = S._scorch_sprite()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = m
	var disc := MeshInstance3D.new()
	disc.mesh = quad
	disc.position = Vector3(pos.x, maxf(0.024, pos.y + 0.024), pos.z)
	disc.rotation_degrees.x = -90.0
	disc.rotation_degrees.z = randf_range(0.0, 360.0)
	disc.add_to_group("vfx_scorch")
	parent.add_child(disc)
	S._cap_group(parent, "vfx_scorch", S.MAX_SCORCH)
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
	S._flash_billboard(parent, pos + Vector3(0, 1.0, 0), 1.4, Color(0.86, 0.94, 1.0), 0.12)
	var tree := parent.get_tree()
	if tree == null:
		return
	if Settings.reduced_motion():
		S._static_cue(parent, Vector3(pos.x, 0.25, pos.z), Color(0.75, 0.68, 0.58, 0.85), 1.6, 0.35)
		return
	# glass glints
	S._particle(parent, pos + Vector3(0, 1.2, 0), 20, 0.75, Vector3.UP, 80.0, 3.0, 9.0,
			[Color(0.85, 0.95, 1.0, 0.9), S.COL_GLASS, Color(0.5, 0.7, 0.9, 0.0)],
			0.11, Vector3(0, -8, 0), true,
			{"tex": "streak", "align": true, "curve": [[0, 1], [1, 0.05]]})
	# timber/metal splinters
	S._particle(parent, pos + Vector3(0, 1.0, 0), 18, 1.1, Vector3.UP, 70.0, 2.5, 7.5,
			[Color(0.55, 0.42, 0.30, 0.9), Color(0.30, 0.26, 0.23, 0.0)],
			0.20, Vector3(0, -6, 0), false,
			{"tex": "streak", "align": true, "curve": [[0, 1], [1, 0.1]]})
	# ground shockwave scaled to the building footprint
	var reach := maxf(size.x, size.z) * 0.85
	S._ring_quad(parent, Vector3(pos.x, 0.10, pos.z), 0.9,
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
	S._flash_billboard(parent, pos, 0.7, color, 0.14)
	if Settings.reduced_motion():
		S._static_cue(parent, pos, color, 0.7, 0.16)
		# Pulse rings are suppressed too, so replace them with one static ring.
		S._static_cue(parent, pos, Color(1, 1, 1, 0.8), 0.34, 0.16)
		return
	S._particle(parent, pos, 18, 0.75, Vector3.UP, 18.0, 2.0, 5.5,
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
	S._cap_group(parent, "vfx_dmg_num", S.MAX_DAMAGE_NUMBERS)
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
	var mat := S._emissive(Color(color.r, color.g, color.b, 0.7), 2.6)
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
		var m := S._emissive(Color(color.r, color.g, color.b, 0.8), 3.0)
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


