extends Node3D
## One dust-mote volume that makes the still arena air feel alive. A single
## GPUParticles3D, no per-frame work, quality-scaled and reduced-motion aware.
## Built by tools/build_arena.gd — never hand-edit an instanced scene.

const VFX := preload("res://src/game/VfxFactory.gd")


func _ready() -> void:
	var q := maxf(0.0, Settings.quality_multiplier())
	if Settings.reduced_motion() or q <= 0.0:
		return
	var p := GPUParticles3D.new()
	p.name = "DustMotes"
	p.amount = maxi(8, int(80 * q))
	p.lifetime = 9.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 14, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(36, 3.0, 36)
	pm.direction = Vector3(0.25, 1.0, 0.1)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.65
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.035
	pm.scale_max = 0.11
	pm.color_ramp = VFX._ramp([
			Color(0.95, 0.88, 0.72, 0.0),
			Color(0.95, 0.88, 0.72, 0.22),
			Color(0.95, 0.88, 0.72, 0.0)])
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.30
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = VFX._soft_sprite()
	quad.material = m
	p.draw_pass_1 = quad
	p.position = Vector3(0, 3.5, 0)
	add_child(p)
	p.emitting = true
