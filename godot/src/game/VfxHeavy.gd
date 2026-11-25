extends RefCounted
## Heavy explosions, death wrecks, lightning strikes, and cash explosions.

const S := preload("res://src/game/VfxSprites.gd")
const CORE := preload("res://src/game/VfxCore.gd")


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
	S._cap_group(parent, "vfx_light", S.MAX_IMPACT_LIGHTS)
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
		var core_mat := S._additive(Color(1.0, 0.94, 0.72, 0.92), 3.6)
		var core_inst := MeshInstance3D.new()
		core_inst.mesh = S._ensure_plasma_sphere()
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
	S._particle(holder, Vector3(0, 0.25, 0), 46, 0.88, Vector3.UP, 64.0, 1.8, 4.8,
			[Color(1.0, 0.80, 0.22, 0.98), Color(1.0, 0.42, 0.06, 0.94),
			 Color(0.68, 0.14, 0.04, 0.68), Color(0.10, 0.09, 0.10, 0.0)],
			1.35, Vector3(0, 2.2, 0), false,
			{"tex": "fire", "quad": 1.38, "curve": [[0, 0.48], [0.28, 1.38], [0.72, 1.12], [1, 0.32]],
			 "hue": 0.04, "damping": 3.5, "angular": 2.6, "explosiveness": 0.96})

	# Stage 1b: Tight incandescent ADDITIVE fire heart burning inside the fireball
	S._particle(holder, Vector3(0, 0.28, 0), 34, 0.54, Vector3.UP, 52.0, 1.6, 4.8,
			[Color(1.0, 0.99, 0.85, 1.0), Color(1.0, 0.82, 0.28, 0.94),
			 Color(1.0, 0.38, 0.05, 0.0)],
			0.96, Vector3(0, 1.4, 0), true,
			{"tex": "fire", "quad": 1.02, "curve": [[0, 0.50], [0.26, 1.35], [1, 0.08]],
			 "hue": 0.03, "damping": 3.4, "angular": 3.2, "explosiveness": 1.0})

	# Stage 3: High-velocity ballistic spark streaks + slow-drifting buoyant embers
	S._particle(holder, Vector3(0, 0.35, 0), 56, 1.15, Vector3.UP, 84.0, 10.0, 24.0,
			[Color(1.0, 0.96, 0.72, 1.0), Color(1.0, 0.58, 0.14, 0.88),
			 Color(0.89, 0.20, 0.03, 0.0)],
			0.24, Vector3(0, -13.0, 0), true,
			{"tex": "streak", "align": true, "curve": [[0, 1.0], [0.55, 0.85], [1, 0.0]],
			 "explosiveness": 0.98})
	S._particle(holder, Vector3(0, 0.40, 0), 20, 1.65, Vector3.UP, 65.0, 1.2, 3.6,
			[Color(1.0, 0.84, 0.34, 0.95), Color(1.0, 0.38, 0.06, 0.70), Color(0.75, 0.14, 0.02, 0.0)],
			0.11, Vector3(0, 0.95, 0), true,
			{"tex": "soft", "quad": 0.36, "curve": [[0, 0.8], [0.5, 1.0], [1, 0.0]],
			 "damping": 0.55, "explosiveness": 0.78})

	S._flash_billboard(holder, Vector3(0, 0.42, 0), 3.1, S.COL_CORE, 0.17)

	var debris_chunks: Array[RigidBody3D] = []
	if mushroom:
		# ------- Stage 2M: colossal meteor mushroom cloud anatomy -------
		# (a) Mach ground shockwave: twin colossal expanding rings + 360° dust skirt
		if not reduced:
			S._ring_quad(holder, Vector3(0, 0.26, 0), 0.62, Color(1.0, 0.72, 0.30, 0.95), 11.5, 0.55, false)
			S._ring_quad(holder, Vector3(0, 0.17, 0), 1.15, Color(0.50, 0.44, 0.38, 0.75), 14.0, 0.90, true)
		S._particle(holder, Vector3(0, 0.20, 0), 34, 1.6, Vector3(0, 0.14, 1), 88.0, 5.5, 12.0,
				[Color(0.45, 0.39, 0.33, 0.78), Color(0.26, 0.24, 0.22, 0.45), Color(0.17, 0.15, 0.14, 0.0)],
				1.6, Vector3(0, 0.5, 0), false,
				{"tex": "smoke", "quad": 1.5, "curve": [[0, 0.42], [0.35, 1.2], [1, 2.1]],
				 "damping": 2.2, "angular": 2.0, "explosiveness": 0.96})
		# (b) Buoyant thermal stem: narrow 14° column, positive upward acceleration,
		#     incandescent magma-orange at the base churning to dark volcanic soot.
		var mushroom_aabb := S.MUSHROOM_AABB
		S._particle(holder, Vector3(0, 0.3, 0), 58, 3.2, Vector3.UP, 14.5, 3.2, 6.8,
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
					S._particle(holder, cap_pos, 64, 3.5, Vector3(0, 0.55, 0), 74.0, 2.6, 5.4,
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
					S._ring_quad(holder, Vector3(0, 1.25, 0), 0.85, Color(0.92, 0.94, 0.98, 0.72), 9.5, 0.55, false))
	else:
		# Stage 2a: Heavy buoyant dark soot mushroom column rising and curling upward
		S._particle(holder, Vector3(0, 0.45, 0), 46, 2.55, Vector3.UP, 36.0, 1.2, 3.8,
				[Color(0.24, 0.21, 0.20, 0.84), Color(0.16, 0.16, 0.18, 0.56), S.COL_SMOKE_DARK],
				2.35, Vector3(0, 1.35, 0), false,
				{"tex": "smoke", "quad": 1.40, "curve": [[0, 0.55], [0.35, 1.25], [1, 2.35]],
				 "angular": 2.0, "damping": 0.72, "explosiveness": 0.82})

		# Stage 2b: Low ground-hugging blast soot/dust skirt anchoring the explosion to terrain
		S._particle(holder, Vector3(0, 0.22, 0), 22, 1.15, Vector3(0, 0.18, 1), 88.0, 4.2, 9.2,
				[Color(0.42, 0.36, 0.30, 0.72), Color(0.24, 0.22, 0.20, 0.38), Color(0.18, 0.16, 0.15, 0.0)],
				1.35, Vector3(0, 0.35, 0), false,
				{"tex": "smoke", "quad": 1.15, "curve": [[0, 0.45], [0.35, 1.15], [1, 1.85]],
				 "damping": 2.4, "angular": 1.8, "explosiveness": 0.96})

		# Dual expanding ground shockwave rings: crisp thermal wave + matte dust wave
		if not reduced:
			S._ring_quad(holder, Vector3(0, 0.24, 0), 0.56, Color(1.0, 0.80, 0.36, 0.95), 7.2, 0.36, false)
			S._ring_quad(holder, Vector3(0, 0.16, 0), 1.05, Color(0.54, 0.48, 0.41, 0.72), 9.0, 0.68, true)

	# Stage 4: Irregular hot-to-char shrapnel shards (no harsh floating box shadows!)
	S._ensure_rubble_pool()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pieces := 0 if (reduced or mushroom) else int(11 * S._q())
	if pieces > 0:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = S.COL_CHAR
		mat.emission_enabled = true
		mat.emission = S.COL_EMBER
		mat.emission_energy_multiplier = 2.2
		mat.roughness = 0.82
		mat.metallic = 0.25
		for i in range(pieces):
			var variant := i % S._rubble_meshes.size()
			var chunk := RigidBody3D.new()
			chunk.mass = rng.randf_range(2.0, 8.0)
			chunk.collision_layer = 0
			chunk.collision_mask = 0
			var col := CollisionShape3D.new()
			col.shape = S._rubble_shapes[variant]
			chunk.add_child(col)
			var mesh := MeshInstance3D.new()
			mesh.mesh = S._rubble_meshes[variant]
			mesh.material_override = mat
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chunk.add_child(mesh)
			chunk.add_to_group("vfx_shard")
			parent.add_child(chunk)
			S._cap_group(parent, "vfx_shard", S.MAX_EXPLOSION_SHARDS)
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
				S._flash_billboard(holder, off, 1.35, S.COL_AMBER, 0.12)
				S._particle(holder, off, 14, 0.48, Vector3.UP, 60.0, 1.8, 5.2,
						[Color(1.0, 0.86, 0.36, 0.95), Color(0.95, 0.36, 0.05, 0.78),
						 Color(0.22, 0.10, 0.06, 0.0)],
						0.85, Vector3(0, 1.8, 0), false,
						{"tex": "fire", "quad": 1.05, "curve": [[0, 0.5], [0.35, 1.2], [1, 0.2]],
						 "damping": 2.4, "explosiveness": 1.0}))

	CORE.scorch(parent, pos, scale)

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
		rng: RandomNumberGenerator, vehicle_profile: String = "") -> RigidBody3D:
	## Cosmetic tumbling wreck: no collision layers/masks, never blocks the track.
	var wreck := RigidBody3D.new()
	wreck.mass = 18.0
	wreck.collision_layer = 0
	wreck.collision_mask = 0
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.10, 0.09, 0.09)
	frame_mat.emission_enabled = true
	frame_mat.emission = S.COL_EMBER
	frame_mat.emission_energy_multiplier = 1.6
	frame_mat.roughness = 0.85
	frame_mat.metallic = 0.3
	var cast_off := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vehicle_profile == "aston":
		var tub := BoxMesh.new()
		tub.size = Vector3(0.46, 0.20, 1.95)
		tub.material = frame_mat
		var ti := MeshInstance3D.new()
		ti.mesh = tub
		ti.position = Vector3(0.0, 0.04, 0.0)
		ti.cast_shadow = cast_off
		wreck.add_child(ti)
		for wz in [0.95, -0.88]:
			var wing := BoxMesh.new()
			wing.size = Vector3(1.25 if wz > 0.0 else 0.85, 0.08, 0.24)
			wing.material = frame_mat
			var wi := MeshInstance3D.new()
			wi.mesh = wing
			wi.position = Vector3(0.0, 0.0 if wz > 0.0 else 0.24, wz)
			wi.cast_shadow = cast_off
			wreck.add_child(wi)
	elif not is_pogo:
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
	if S._q() > 0.0:
		var plume := GPUParticles3D.new()
		plume.amount = maxi(4, int(26 * S._q()))
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
		pm.color_ramp = S._ramp([Color(1.0, 0.62, 0.12, 0.9), Color(0.75, 0.22, 0.05, 0.6),
				Color(0.12, 0.11, 0.12, 0.0)])
		plume.process_material = pm
		plume.draw_pass_1 = S._sprite_quad(false, "fire", 0.55)
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
		color: Color, is_pogo: bool = false, vehicle_profile: String = "") -> void:
	## 4-beat death sequence: primary detonation, launch shockwave, tumbling
	## charred wreck with a fire plume, then two staggered mid-air cook-offs.
	if parent == null:
		return
	var reduced := Settings.reduced_motion()
	# Beat 1: primary 1.65x kill detonation + golden kill-spark shower
	particle_explosion(parent, pos, color, 1.65, false)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	S._particle(parent, pos + Vector3(0, 0.3, 0), 36, 1.1, Vector3.UP, 72.0, 9.0, 22.0,
			[Color(1.0, 0.96, 0.70, 1.0), Color(1.0, 0.62, 0.15, 0.9),
			 Color(0.88, 0.22, 0.04, 0.0)],
			0.24, Vector3(0, -9.0, 0), true,
			{"tex": "streak", "align": true, "curve": [[0, 1.0], [0.55, 0.8], [1, 0.0]],
			 "explosiveness": 0.96})
	if reduced:
		return
	S._ring_quad(parent, pos + Vector3(0, 0.4, 0), 0.6, Color(1.0, 0.82, 0.35, 0.95), 9.2, 0.5, false)
	# Beat 2: tumbling charred wreck hurled skyward (capped, fully cosmetic)
	var tree := parent.get_tree()
	var wreck_count := tree.get_nodes_in_group("death_wreck").size() if tree != null else S.MAX_WRECKS
	if wreck_count >= S.MAX_WRECKS:
		return
	var wreck := _build_death_wreck(pos, basis, is_pogo, rng, vehicle_profile)
	parent.add_child(wreck)
	# Beat 3: two staggered mid-air cook-offs tracking the tumbling wreck
	var cook := func(sz: float) -> void:
		if not is_instance_valid(wreck):
			return
		var wp := wreck.global_position
		S._flash_billboard(parent, wp, sz, S.COL_AMBER, 0.14)
		S._particle(parent, wp, 22, 0.55, Vector3.UP, 68.0, 2.2, 6.8,
				[Color(1.0, 0.86, 0.36, 0.95), Color(0.95, 0.36, 0.05, 0.78),
				 Color(0.20, 0.09, 0.05, 0.0)],
				0.9, Vector3(0, 0.6, 0), false,
				{"tex": "fire", "quad": 1.1, "curve": [[0, 0.5], [0.35, 1.25], [1, 0.25]],
				 "damping": 2.0, "explosiveness": 1.0})
		S._particle(parent, wp, 14, 0.8, Vector3.UP, 80.0, 5.0, 12.0,
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


static func _build_bolt_segment(parent: Node3D, p0: Vector3, p1: Vector3,
		core_r: float, sheath_r: float, core_mat: StandardMaterial3D,
		sheath_mat: StandardMaterial3D) -> void:
	var diff := p1 - p0
	var length := diff.length()
	if length < 0.01:
		return
	var mid := (p0 + p1) * 0.5
	var up := diff / length
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var right := up.cross(ref).normalized()
	var fwd := right.cross(up).normalized()
	var seg_basis := Basis(right, up, fwd)
	var unit_mesh := S._ensure_bolt_mesh()

	var core := MeshInstance3D.new()
	core.mesh = unit_mesh
	core.material_override = core_mat
	core.position = mid
	core.basis = seg_basis
	core.scale = Vector3(core_r, length, core_r)
	parent.add_child(core)

	var sheath := MeshInstance3D.new()
	sheath.mesh = unit_mesh
	sheath.material_override = sheath_mat
	sheath.position = mid
	sheath.basis = seg_basis
	sheath.scale = Vector3(sheath_r, length, sheath_r)
	parent.add_child(sheath)


static func _populate_lightning_bolt(bolt_root: Node3D, height: float,
		core_mat: StandardMaterial3D, sheath_mat: StandardMaterial3D) -> void:
	var steps := 10
	var prev := Vector3(randf_range(-1.8, 1.8), height, randf_range(-1.8, 1.8))
	for i in range(1, steps + 1):
		var frac := float(i) / float(steps)
		var jitter := (1.0 - frac) * 2.4
		var next := Vector3(
			randf_range(-jitter, jitter),
			lerpf(height, 0.0, frac),
			randf_range(-jitter, jitter)
		)
		if i == steps:
			next = Vector3.ZERO
		_build_bolt_segment(bolt_root, prev, next, 0.16, 0.42, core_mat, sheath_mat)
		if i < steps - 1 and randf() < 0.55:
			var b_end := next + Vector3(randf_range(-5.5, 5.5), -randf_range(3.5, 8.0), randf_range(-5.5, 5.5))
			_build_bolt_segment(bolt_root, next, b_end, 0.07, 0.20, core_mat, sheath_mat)
		prev = next


static func lightning_strike_explosion(parent: Node3D, pos: Vector3,
		scale: float = 1.35) -> void:
	if parent == null:
		return
	var holder := Node3D.new()
	holder.position = pos
	parent.add_child(holder)

	var core_mat := S._additive(Color(0.95, 0.99, 1.0, 1.0), 7.5)
	var sheath_mat := S._additive(Color(0.32, 0.78, 1.0, 0.65), 4.2)
	var reduced := Settings.reduced_motion()

	var bolt_root := Node3D.new()
	bolt_root.name = "MegaBolt"
	holder.add_child(bolt_root)
	_populate_lightning_bolt(bolt_root, 42.0, core_mat, sheath_mat)

	var light := OmniLight3D.new()
	light.light_color = Color(0.68, 0.92, 1.0)
	light.light_energy = 11.0 * scale
	light.omni_range = 18.0 * scale
	light.add_to_group("vfx_light")
	holder.add_child(light)
	S._cap_group(parent, "vfx_light", S.MAX_IMPACT_LIGHTS)

	var release_light := func() -> void:
		if is_instance_valid(light):
			if light.is_in_group("vfx_light"):
				light.remove_from_group("vfx_light")
			light.queue_free()

	if reduced:
		S._static_cue(holder, Vector3(0.0, 0.3, 0.0), Color(0.45, 0.88, 1.0), 3.4 * scale, 0.25)
		light.light_energy = 3.5 * scale
		var lt := holder.create_tween()
		lt.tween_interval(0.22)
		lt.tween_callback(func() -> void:
			release_light.call()
			if is_instance_valid(bolt_root):
				bolt_root.queue_free())
	else:
		# 3 rapid flicker beats
		var bt := holder.create_tween()
		bt.tween_interval(0.06)
		bt.tween_callback(func() -> void:
			if is_instance_valid(bolt_root):
				bolt_root.visible = false)
		bt.tween_interval(0.04)
		bt.tween_callback(func() -> void:
			if is_instance_valid(bolt_root):
				bolt_root.visible = true
				bolt_root.rotation_degrees.y = 75.0)
		bt.tween_interval(0.06)
		bt.tween_callback(func() -> void:
			if is_instance_valid(bolt_root):
				bolt_root.visible = false)
		bt.tween_interval(0.04)
		bt.tween_callback(func() -> void:
			if is_instance_valid(bolt_root):
				bolt_root.visible = true
				bolt_root.rotation_degrees.y = -65.0)
		bt.tween_interval(0.07)
		bt.tween_callback(func() -> void:
			if is_instance_valid(bolt_root):
				bolt_root.queue_free())

		var lt := holder.create_tween()
		lt.tween_property(light, "light_energy", 0.0, 0.34)
		lt.tween_callback(release_light)

		# Twin electric shockwave rings
		S._ring_quad(holder, Vector3(0.0, 0.08, 0.0), 3.2 * scale, Color(0.65, 0.95, 1.0, 0.9), 2.3, 0.38)
		S._ring_quad(holder, Vector3(0.0, 0.14, 0.0), 2.4 * scale, Color(0.58, 0.45, 1.0, 0.85), 2.2, 0.28)

		# 64 radial electric arc sparks
		S._particle(holder, Vector3(0.0, 0.3, 0.0), 64, 0.48, Vector3.UP, 88.0,
				9.0 * scale, 20.0 * scale,
				[Color(1.0, 1.0, 1.0, 1.0), Color(0.38, 0.86, 1.0, 0.9), Color(0.45, 0.35, 1.0, 0.0)],
				0.24, Vector3(0.0, -14.0, 0.0), true,
				{"tex": "streak", "align": true, "quad": 0.42})

		# Ozone mist
		S._particle(holder, Vector3(0.0, 0.6, 0.0), 22, 0.95, Vector3.UP, 75.0,
				1.6, 4.2,
				[Color(0.52, 0.82, 1.0, 0.45), Color(0.35, 0.48, 0.72, 0.25), Color(0.18, 0.22, 0.30, 0.0)],
				0.4, Vector3(0.0, 1.2, 0.0), false,
				{"tex": "smoke", "quad": 1.6 * scale})

	CORE.scorch(parent, pos, scale)
	var cleanup := holder.create_tween()
	cleanup.tween_interval(1.25)
	cleanup.tween_callback(holder.queue_free)


static func cash_explosion(parent: Node3D, pos: Vector3, big: bool = false) -> void:
	if parent == null:
		return
	var holder := Node3D.new()
	holder.position = pos
	parent.add_child(holder)
	var scale := 2.0 if big else 1.15
	var reduced := Settings.reduced_motion()

	var light := OmniLight3D.new()
	light.light_color = Color(0.92, 0.84, 0.26)
	light.light_energy = (9.5 if big else 5.5)
	light.omni_range = (14.0 if big else 7.5)
	light.add_to_group("vfx_light")
	holder.add_child(light)
	S._cap_group(parent, "vfx_light", S.MAX_IMPACT_LIGHTS)

	var release_light := func() -> void:
		if is_instance_valid(light):
			if light.is_in_group("vfx_light"):
				light.remove_from_group("vfx_light")
			light.queue_free()

	var lt := holder.create_tween()
	if reduced:
		light.light_energy = 3.0 if big else 2.0
		lt.tween_interval(0.16)
	else:
		lt.tween_property(light, "light_energy", 0.0, 0.28)
	lt.tween_callback(release_light)

	if reduced:
		S._static_cue(holder, Vector3(0.0, 0.3, 0.0), Color(0.22, 0.85, 0.38), 2.2 * scale, 0.28)
		S._static_cue(holder, Vector3(0.0, 0.08, 0.0), Color(1.0, 0.85, 0.22, 0.85), 2.0 * scale, 0.26)
	else:
		# Twin gold / emerald shockwave rings
		S._ring_quad(holder, Vector3(0.0, 0.08, 0.0), 2.4 * scale, Color(1.0, 0.84, 0.22, 0.90), 2.0, 0.40)
		S._ring_quad(holder, Vector3(0.0, 0.12, 0.0), 1.8 * scale, Color(0.18, 0.88, 0.42, 0.85), 2.0, 0.32)

		# Exploding fountain of fluttering dollar-bill quads
		if S._q() > 0.0:
			var bill_count := maxi(8, int((110 if big else 42) * S._q()))
			var bills := GPUParticles3D.new()
			bills.amount = bill_count
			bills.lifetime = 1.35 if big else 1.05
			bills.one_shot = true
			bills.explosiveness = 0.92
			bills.visibility_aabb = AABB(Vector3(-14, -4, -14), Vector3(28, 22, 28))
			var pm := ParticleProcessMaterial.new()
			pm.direction = Vector3.UP
			pm.spread = 72.0
			pm.initial_velocity_min = 6.5 if big else 4.2
			pm.initial_velocity_max = 16.0 if big else 10.5
			pm.gravity = Vector3(0.0, -7.5, 0.0)
			pm.damping_min = 1.6
			pm.damping_max = 3.2
			pm.angular_velocity_min = -260.0
			pm.angular_velocity_max = 260.0
			pm.scale_min = 1.1 if big else 0.85
			pm.scale_max = 1.7 if big else 1.25
			pm.color_ramp = S._ramp([
				Color(1.0, 1.0, 1.0, 1.0),
				Color(0.95, 1.0, 0.95, 0.95),
				Color(0.85, 0.95, 0.85, 0.0),
			])
			bills.process_material = pm
			bills.draw_pass_1 = CashBagVisual.get_bill_mesh()
			holder.add_child(bills)
			bills.emitting = true

		# Gold sparkles
		S._particle(holder, Vector3(0.0, 0.25, 0.0), 36 if big else 20, 0.55, Vector3.UP, 82.0,
				5.0 * scale, 12.0 * scale,
				[Color(1.0, 0.96, 0.62, 1.0), Color(1.0, 0.82, 0.18, 0.9), Color(0.18, 0.78, 0.34, 0.0)],
				0.22, Vector3(0.0, -9.0, 0.0), true,
				{"tex": "flare", "quad": 0.45})

	var cleanup := holder.create_tween()
	cleanup.tween_interval(1.6)
	cleanup.tween_callback(holder.queue_free)
