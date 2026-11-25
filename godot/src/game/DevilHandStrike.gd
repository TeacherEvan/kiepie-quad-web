extends Node3D
## Evan the Skeleton's Special — DEVIL HAND. A towering vertical demonic hand
## erupts skyward out of a cracked molten hell-portal inside the 7.5 m target
## zone over 2.0 s, splays its 3-jointed claws wide, slams into a crushing fist
## and drags everything in the kill zone underground for an instant kill.
## Same cooldown/broadcast contract as Meteor Shower.

signal impacted(point: Vector3)

const FALL_DURATION := 2.0
const BLAST_RADIUS := 7.5
const RISE_START_Y := -5.8
const RISE_END_Y := 1.45
const VFX := preload("res://src/game/VfxFactory.gd")
const COMBAT_AOE := preload("res://src/game/CombatAoe.gd")

var owner_id := ""
var owner_node: Node
var target_pos := Vector3.ZERO
var damage := 105.0
var blast_radius := BLAST_RADIUS
var fall_duration := FALL_DURATION
var token := ""
var hit_color := Color(0.85, 0.06, 0.20)
var visual_style := "devil_hand"

var _age := 0.0
var _armed := false
var _detonated := false
var _breached := false
var _hand: Node3D
var _outer_ring: MeshInstance3D
var _inner_ring: MeshInstance3D
var _portal: MeshInstance3D
var _rune_ring: Node3D
var _telegraph_cracks: Array[MeshInstance3D] = []
var _finger_chains: Array[Dictionary] = []
var _vein_mat: StandardMaterial3D = null
var _hand_base_yaw := 0.0
var _light: OmniLight3D

static var _ring_mesh: CylinderMesh = null
static var _disc_mesh: CylinderMesh = null
static var _portal_mesh: CylinderMesh = null
static var _rune_seg_mesh: BoxMesh = null
static var _forearm_mesh: CylinderMesh = null
static var _cuff_mesh: TorusMesh = null
static var _spur_mesh: CylinderMesh = null
static var _palm_mesh: BoxMesh = null
static var _palm_pad_mesh: SphereMesh = null
static var _tendon_mesh: CylinderMesh = null
static var _sigil_mesh: CylinderMesh = null
static var _knuckle_mesh: SphereMesh = null
static var _joint_mesh: SphereMesh = null
static var _proximal_mesh: CylinderMesh = null
static var _middle_mesh: CylinderMesh = null
static var _distal_mesh: CylinderMesh = null
static var _nail_mesh: ArrayMesh = null
static var _cuticle_mesh: TorusMesh = null
static var _vein_main_mesh: ArrayMesh = null
static var _vein_branch_mesh: ArrayMesh = null
static var _crack_mesh: BoxMesh = null


static func _build_vein_mesh(length: float, radius: float, amp: float, freq: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 12
	var segs := 6
	var pts: Array[Vector3] = []
	var rads: Array[float] = []
	for i in range(rings + 1):
		var t := float(i) / float(rings)
		var y := t * length
		var x := sin(t * freq) * amp
		var z := cos(t * freq * 0.72) * amp * 0.45
		pts.append(Vector3(x, y, z))
		var swell := 1.0 + 0.24 * sin(t * freq * 2.1)
		var taper := 1.0 - 0.35 * t
		rads.append(radius * swell * taper)
	var verts: Array[Array] = []
	for i in range(rings + 1):
		var c := pts[i]
		var r := rads[i]
		var ring_v: Array[Vector3] = []
		for j in range(segs):
			var ang := TAU * float(j) / float(segs)
			ring_v.append(c + Vector3(cos(ang) * r, 0.0, sin(ang) * r))
		verts.append(ring_v)
	for i in range(rings):
		for j in range(segs):
			var jn := (j + 1) % segs
			var a: Vector3 = verts[i][j]
			var b: Vector3 = verts[i][jn]
			var c2: Vector3 = verts[i + 1][jn]
			var d: Vector3 = verts[i + 1][j]
			st.add_vertex(a); st.add_vertex(b); st.add_vertex(c2)
			st.add_vertex(a); st.add_vertex(c2); st.add_vertex(d)
	st.generate_normals()
	return st.commit()


static func _build_nail_mesh() -> ArrayMesh:
	## Curved obsidian-keratin demonic fingernail: arches across dorsal (-Z) tip
	## of the distal phalanx and hooks forward/inward (+Z) to a razor talon point.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 7
	var cols := 5
	var grid: Array[Array] = []
	for i in range(rows):
		var t := float(i) / float(rows - 1)  # 0 = cuticle root, 1 = hooked tip
		var half_w := lerpf(0.155, 0.014, pow(t, 1.35))
		var thick := lerpf(0.038, 0.010, t)
		var y := lerpf(0.22, 1.32, t) - 0.14 * pow(t, 2.6)
		# Dorsal is -Z; tip hooks forward/inward toward +Z palm grip
		var z_center := -0.175 + 0.30 * pow(t, 2.05)
		var row_top: Array[Vector3] = []
		var row_bot: Array[Vector3] = []
		for j in range(cols):
			var u := (float(j) / float(cols - 1)) * 2.0 - 1.0  # -1..1 across width
			var arch := (1.0 - u * u) * lerpf(0.065, 0.015, t)
			row_top.append(Vector3(u * half_w, y, z_center - arch - thick * 0.5))
			row_bot.append(Vector3(u * half_w, y, z_center - arch + thick * 0.5))
		grid.append([row_top, row_bot])
	for i in range(rows - 1):
		var t0: Array = grid[i][0]
		var b0: Array = grid[i][1]
		var t1: Array = grid[i + 1][0]
		var b1: Array = grid[i + 1][1]
		for j in range(cols - 1):
			# Dorsal surface (-Z)
			var p_t00: Vector3 = t0[j]; var p_t10: Vector3 = t1[j]
			var p_t11: Vector3 = t1[j + 1]; var p_t01: Vector3 = t0[j + 1]
			var p_b00: Vector3 = b0[j]; var p_b10: Vector3 = b1[j]
			var p_b11: Vector3 = b1[j + 1]; var p_b01: Vector3 = b0[j + 1]
			st.add_vertex(p_t00); st.add_vertex(p_t10); st.add_vertex(p_t11)
			st.add_vertex(p_t00); st.add_vertex(p_t11); st.add_vertex(p_t01)
			# Ventral underside (+Z)
			st.add_vertex(p_b00); st.add_vertex(p_b11); st.add_vertex(p_b10)
			st.add_vertex(p_b00); st.add_vertex(p_b01); st.add_vertex(p_b11)
		# Side edges
		var s_t0L: Vector3 = t0[0]; var s_b0L: Vector3 = b0[0]
		var s_b1L: Vector3 = b1[0]; var s_t1L: Vector3 = t1[0]
		st.add_vertex(s_t0L); st.add_vertex(s_b0L); st.add_vertex(s_b1L)
		st.add_vertex(s_t0L); st.add_vertex(s_b1L); st.add_vertex(s_t1L)
		var s_t0R: Vector3 = t0[cols - 1]; var s_t1R: Vector3 = t1[cols - 1]
		var s_b1R: Vector3 = b1[cols - 1]; var s_b0R: Vector3 = b0[cols - 1]
		st.add_vertex(s_t0R); st.add_vertex(s_t1R); st.add_vertex(s_b1R)
		st.add_vertex(s_t0R); st.add_vertex(s_b1R); st.add_vertex(s_b0R)
	st.generate_normals()
	var am := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.012, 0.018)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.02, 0.04)
	mat.emission_energy_multiplier = 0.35
	mat.metallic = 0.28
	mat.roughness = 0.16
	am.surface_set_material(0, mat)
	return am


static func _ensure_meshes() -> void:
	if _ring_mesh == null:
		var rm := CylinderMesh.new()
		rm.top_radius = 1.0
		rm.bottom_radius = 1.0
		rm.height = 0.04
		rm.radial_segments = 28
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.88, 0.04, 0.14, 0.48)
		rmat.emission_enabled = true
		rmat.emission = Color(0.95, 0.06, 0.16)
		rmat.emission_energy_multiplier = 3.2
		rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		rm.material = rmat
		_ring_mesh = rm
	if _disc_mesh == null:
		var dm := CylinderMesh.new()
		dm.top_radius = 1.0
		dm.bottom_radius = 1.0
		dm.height = 0.05
		dm.radial_segments = 24
		var dmat := StandardMaterial3D.new()
		dmat.albedo_color = Color(1.0, 0.18, 0.12, 0.52)
		dmat.emission_enabled = true
		dmat.emission = Color(1.0, 0.12, 0.08)
		dmat.emission_energy_multiplier = 4.4
		dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		dm.material = dmat
		_disc_mesh = dm
	if _portal_mesh == null:
		var pm := CylinderMesh.new()
		pm.top_radius = 1.0
		pm.bottom_radius = 1.0
		pm.height = 0.03
		pm.radial_segments = 24
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.03, 0.005, 0.01, 0.94)
		pmat.emission_enabled = true
		pmat.emission = Color(0.45, 0.02, 0.05)
		pmat.emission_energy_multiplier = 0.65
		pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.material = pmat
		_portal_mesh = pm
	if _rune_seg_mesh == null:
		var rsm := BoxMesh.new()
		rsm.size = Vector3(0.48, 0.03, 0.16)
		var rsmat := StandardMaterial3D.new()
		rsmat.albedo_color = Color(1.0, 0.14, 0.18, 0.85)
		rsmat.emission_enabled = true
		rsmat.emission = Color(1.0, 0.10, 0.14)
		rsmat.emission_energy_multiplier = 3.8
		rsmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rsmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rsmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		rsm.material = rsmat
		_rune_seg_mesh = rsm
	if _forearm_mesh == null:
		var fm2 := CylinderMesh.new()
		fm2.top_radius = 0.88
		fm2.bottom_radius = 1.25
		fm2.height = 4.20
		fm2.radial_segments = 14
		var fmat2 := StandardMaterial3D.new()
		fmat2.albedo_color = Color(0.14, 0.015, 0.04)
		fmat2.emission_enabled = true
		fmat2.emission = Color(0.65, 0.03, 0.09)
		fmat2.emission_energy_multiplier = 0.85
		fmat2.roughness = 0.62
		fm2.material = fmat2
		_forearm_mesh = fm2
	if _cuff_mesh == null:
		var cm := TorusMesh.new()
		cm.inner_radius = 0.86
		cm.outer_radius = 1.18
		cm.rings = 16
		cm.ring_segments = 8
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.22, 0.02, 0.05)
		cmat.emission_enabled = true
		cmat.emission = Color(0.95, 0.08, 0.12)
		cmat.emission_energy_multiplier = 2.0
		cmat.metallic = 0.65
		cmat.roughness = 0.35
		cm.material = cmat
		_cuff_mesh = cm
	if _spur_mesh == null:
		var sp := CylinderMesh.new()
		sp.top_radius = 0.01
		sp.bottom_radius = 0.22
		sp.height = 0.88
		sp.radial_segments = 7
		var spmat := StandardMaterial3D.new()
		spmat.albedo_color = Color(0.10, 0.01, 0.02)
		spmat.emission_enabled = true
		spmat.emission = Color(0.85, 0.06, 0.12)
		spmat.emission_energy_multiplier = 1.5
		spmat.roughness = 0.45
		sp.material = spmat
		_spur_mesh = sp
	if _palm_mesh == null:
		var pm2 := BoxMesh.new()
		pm2.size = Vector3(2.55, 2.35, 0.92)
		var pmat2 := StandardMaterial3D.new()
		pmat2.albedo_color = Color(0.19, 0.018, 0.045)
		pmat2.emission_enabled = true
		pmat2.emission = Color(0.75, 0.03, 0.10)
		pmat2.emission_energy_multiplier = 0.95
		pmat2.metallic = 0.32
		pmat2.roughness = 0.54
		pm2.material = pmat2
		_palm_mesh = pm2
	if _palm_pad_mesh == null:
		var pp := SphereMesh.new()
		pp.radius = 0.56
		pp.height = 1.05
		pp.radial_segments = 10
		pp.rings = 6
		pp.material = _palm_mesh.material
		_palm_pad_mesh = pp
	if _tendon_mesh == null:
		var td := CylinderMesh.new()
		td.top_radius = 0.065
		td.bottom_radius = 0.085
		td.height = 1.85
		td.radial_segments = 6
		var tdmat := StandardMaterial3D.new()
		tdmat.albedo_color = Color(0.11, 0.01, 0.025)
		tdmat.roughness = 0.65
		td.material = tdmat
		_tendon_mesh = td
	if _sigil_mesh == null:
		var sm := CylinderMesh.new()
		sm.top_radius = 0.62
		sm.bottom_radius = 0.62
		sm.height = 0.98
		sm.radial_segments = 12
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(1.0, 0.12, 0.18)
		smat.emission_enabled = true
		smat.emission = Color(1.0, 0.08, 0.15)
		smat.emission_energy_multiplier = 3.4
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.material = smat
		_sigil_mesh = sm
	if _knuckle_mesh == null:
		var km := SphereMesh.new()
		km.radius = 0.34
		km.height = 0.46
		km.radial_segments = 10
		km.rings = 5
		var kmat := StandardMaterial3D.new()
		kmat.albedo_color = Color(0.25, 0.02, 0.06)
		kmat.emission_enabled = true
		kmat.emission = Color(0.82, 0.04, 0.10)
		kmat.emission_energy_multiplier = 1.25
		kmat.roughness = 0.48
		km.material = kmat
		_knuckle_mesh = km
	if _joint_mesh == null:
		var jm := SphereMesh.new()
		jm.radius = 0.25
		jm.height = 0.36
		jm.radial_segments = 8
		jm.rings = 4
		jm.material = _knuckle_mesh.material
		_joint_mesh = jm
	if _proximal_mesh == null:
		var px := CylinderMesh.new()
		px.top_radius = 0.24
		px.bottom_radius = 0.29
		px.height = 1.35
		px.radial_segments = 9
		var pxmat := StandardMaterial3D.new()
		pxmat.albedo_color = Color(0.22, 0.02, 0.05)
		pxmat.emission_enabled = true
		pxmat.emission = Color(0.78, 0.03, 0.10)
		pxmat.emission_energy_multiplier = 1.05
		pxmat.roughness = 0.52
		px.material = pxmat
		_proximal_mesh = px
	if _middle_mesh == null:
		var mm := CylinderMesh.new()
		mm.top_radius = 0.19
		mm.bottom_radius = 0.24
		mm.height = 1.05
		mm.radial_segments = 9
		var mmat := StandardMaterial3D.new()
		mmat.albedo_color = Color(0.24, 0.02, 0.05)
		mmat.emission_enabled = true
		mmat.emission = Color(0.84, 0.04, 0.11)
		mmat.emission_energy_multiplier = 1.2
		mmat.roughness = 0.48
		mm.material = mmat
		_middle_mesh = mm
	if _distal_mesh == null:
		var dm2 := CylinderMesh.new()
		dm2.top_radius = 0.14
		dm2.bottom_radius = 0.19
		dm2.height = 0.78
		dm2.radial_segments = 8
		var dmat2 := StandardMaterial3D.new()
		dmat2.albedo_color = Color(0.28, 0.02, 0.06)
		dmat2.emission_enabled = true
		dmat2.emission = Color(0.92, 0.05, 0.12)
		dmat2.emission_energy_multiplier = 1.4
		dmat2.roughness = 0.44
		dm2.material = dmat2
		_distal_mesh = dm2
	if _nail_mesh == null:
		_nail_mesh = _build_nail_mesh()
	if _cuticle_mesh == null:
		var cu := TorusMesh.new()
		cu.inner_radius = 0.11
		cu.outer_radius = 0.175
		cu.rings = 10
		cu.ring_segments = 6
		var cumat := StandardMaterial3D.new()
		cumat.albedo_color = Color(1.0, 0.18, 0.10)
		cumat.emission_enabled = true
		cumat.emission = Color(1.0, 0.12, 0.06)
		cumat.emission_energy_multiplier = 3.2
		cumat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cu.material = cumat
		_cuticle_mesh = cu
	if _vein_main_mesh == null:
		_vein_main_mesh = _build_vein_mesh(3.8, 0.068, 0.11, 7.2)
	if _vein_branch_mesh == null:
		_vein_branch_mesh = _build_vein_mesh(1.35, 0.044, 0.07, 5.5)
	if _crack_mesh == null:
		var cm2 := BoxMesh.new()
		cm2.size = Vector3(0.14, 0.025, 2.40)
		var cmat2 := StandardMaterial3D.new()
		cmat2.albedo_color = Color(1.0, 0.08, 0.12, 0.90)
		cmat2.emission_enabled = true
		cmat2.emission = Color(1.0, 0.06, 0.10)
		cmat2.emission_energy_multiplier = 3.2
		cmat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cmat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cm2.material = cmat2
		_crack_mesh = cm2


func setup(p_owner_id: String, p_owner_node: Node, p_target_pos: Vector3,
		p_damage: float, p_token: String, p_color: Color = Color(0.85, 0.06, 0.20),
		p_fall_duration: float = 2.0, p_blast_radius: float = 7.5,
		p_visual_style: String = "devil_hand") -> void:
	if not is_finite(p_damage) or not is_finite(p_blast_radius) or p_blast_radius <= 0.0 \
			or not is_finite(p_fall_duration) \
			or not is_finite(p_target_pos.x + p_target_pos.y + p_target_pos.z):
		push_warning("DevilHandStrike.setup: rejecting non-finite/invalid strike parameters")
		_armed = false
		queue_free()
		return
	owner_id = p_owner_id
	owner_node = p_owner_node
	target_pos = p_target_pos
	damage = maxf(0.0, p_damage)
	token = p_token
	hit_color = p_color
	visual_style = "devil_hand"
	fall_duration = maxf(0.1, p_fall_duration)
	blast_radius = minf(p_blast_radius, 7.5)
	global_position = target_pos
	_age = 0.0
	_armed = true
	_detonated = false
	_breached = false
	add_to_group("meteor_strike")
	_build_visual()


func _build_visual() -> void:
	_ensure_meshes()
	_finger_chains.clear()
	_telegraph_cracks.clear()

	# Hell-portal ground chasm + outer warning ring + shrinking countdown disc
	_outer_ring = MeshInstance3D.new()
	_outer_ring.name = "WarningRing"
	_outer_ring.mesh = _ring_mesh
	_outer_ring.position = Vector3(0.0, 0.05, 0.0)
	_outer_ring.scale = Vector3(blast_radius, 1.0, blast_radius)
	add_child(_outer_ring)

	_inner_ring = MeshInstance3D.new()
	_inner_ring.name = "CountdownRing"
	_inner_ring.mesh = _disc_mesh
	_inner_ring.position = Vector3(0.0, 0.07, 0.0)
	_inner_ring.scale = Vector3(blast_radius * 0.95, 1.0, blast_radius * 0.95)
	add_child(_inner_ring)

	_portal = MeshInstance3D.new()
	_portal.name = "AbyssPortal"
	_portal.mesh = _portal_mesh
	_portal.position = Vector3(0.0, 0.03, 0.0)
	_portal.scale = Vector3(0.05, 1.0, 0.05)
	add_child(_portal)

	_rune_ring = Node3D.new()
	_rune_ring.name = "RuneRing"
	_rune_ring.position = Vector3(0.0, 0.09, 0.0)
	add_child(_rune_ring)
	for ri in range(8):
		var seg := MeshInstance3D.new()
		seg.mesh = _rune_seg_mesh
		var ang := TAU * float(ri) / 8.0
		var r_rad := blast_radius * 0.56
		seg.position = Vector3(sin(ang) * r_rad, 0.0, cos(ang) * r_rad)
		seg.rotation.y = ang
		_rune_ring.add_child(seg)

	for ci in range(6):
		var crack := MeshInstance3D.new()
		crack.mesh = _crack_mesh
		var c_ang := TAU * float(ci) / 6.0 + 0.18 * sin(float(ci) * 2.1)
		crack.position = Vector3(sin(c_ang) * blast_radius * 0.38, 0.04, cos(c_ang) * blast_radius * 0.38)
		crack.rotation.y = c_ang
		crack.scale = Vector3(1.0, 1.0, 0.1)
		add_child(crack)
		_telegraph_cracks.append(crack)

	# Towering vertical demonic hand (oriented along +Y SKYWARD)
	_hand = Node3D.new()
	_hand.name = "DevilHand"
	_hand.position.y = RISE_START_Y
	_hand_base_yaw = 0.35
	if is_instance_valid(owner_node) and owner_node is Node3D:
		var to_caster := (owner_node as Node3D).global_position - target_pos
		to_caster.y = 0.0
		if to_caster.length_squared() > 0.25:
			_hand_base_yaw = atan2(to_caster.x, to_caster.z) + 0.35
	_hand.rotation.y = _hand_base_yaw
	add_child(_hand)

	# Per-instance pulsing glowing vein material
	_vein_mat = StandardMaterial3D.new()
	_vein_mat.albedo_color = Color(0.85, 0.06, 0.08)
	_vein_mat.emission_enabled = true
	_vein_mat.emission = Color(1.0, 0.16, 0.05)
	_vein_mat.emission_energy_multiplier = 2.0
	_vein_mat.roughness = 0.35

	var forearm := MeshInstance3D.new()
	forearm.name = "Forearm"
	forearm.mesh = _forearm_mesh
	forearm.position = Vector3(0.0, -2.50, 0.0)
	_hand.add_child(forearm)

	# Bulging sinuous veins + forked tributaries spiraling up the forearm
	var veins_root := Node3D.new()
	veins_root.name = "Veins"
	_hand.add_child(veins_root)
	for vi in range(6):
		var v_ang := TAU * float(vi) / 6.0 + 0.25
		var v_rad := 0.96
		var vm := MeshInstance3D.new()
		vm.name = "ForearmVein%d" % vi
		vm.mesh = _vein_main_mesh
		vm.material_override = _vein_mat
		vm.position = Vector3(sin(v_ang) * v_rad, -4.35, cos(v_ang) * v_rad)
		vm.rotation.y = v_ang
		veins_root.add_child(vm)
		if vi < 4:
			var vb := MeshInstance3D.new()
			vb.name = "ForearmVeinBranch%d" % vi
			vb.mesh = _vein_branch_mesh
			vb.material_override = _vein_mat
			vb.position = Vector3(sin(v_ang + 0.2) * 0.92, -2.45 - float(vi % 2) * 0.85, cos(v_ang + 0.2) * 0.92)
			vb.rotation = Vector3(0.18, v_ang + 0.3, 0.26 if vi % 2 == 0 else -0.26)
			veins_root.add_child(vb)

	var cuff := MeshInstance3D.new()
	cuff.name = "WristCuff"
	cuff.mesh = _cuff_mesh
	cuff.position = Vector3(0.0, -0.58, 0.0)
	_hand.add_child(cuff)

	for si in range(4):
		var spur := MeshInstance3D.new()
		spur.mesh = _spur_mesh
		var s_ang := TAU * float(si) / 4.0 + 0.4
		spur.position = Vector3(sin(s_ang) * 1.05, -0.52, cos(s_ang) * 1.05)
		spur.rotation.z = -sin(s_ang) * 0.65
		spur.rotation.x = cos(s_ang) * 0.65
		_hand.add_child(spur)

	var palm := MeshInstance3D.new()
	palm.name = "Palm"
	palm.mesh = _palm_mesh
	palm.position = Vector3(0.0, 0.72, 0.0)
	_hand.add_child(palm)

	# Muscular thenar (thumb heel) & hypothenar (outer palm) pads
	var thenar := MeshInstance3D.new()
	thenar.name = "ThenarPad"
	thenar.mesh = _palm_pad_mesh
	thenar.position = Vector3(-0.78, 0.35, 0.32)
	thenar.scale = Vector3(1.05, 1.15, 0.72)
	_hand.add_child(thenar)

	var hypothenar := MeshInstance3D.new()
	hypothenar.name = "HypothenarPad"
	hypothenar.mesh = _palm_pad_mesh
	hypothenar.position = Vector3(0.76, 0.55, 0.22)
	hypothenar.scale = Vector3(0.88, 1.25, 0.68)
	_hand.add_child(hypothenar)

	# Dorsal extensor tendons & metacarpal veins across back of hand (-Z)
	for ti in range(4):
		var tx := -0.78 + float(ti) * 0.52
		var tendon := MeshInstance3D.new()
		tendon.name = "DorsalTendon%d" % ti
		tendon.mesh = _tendon_mesh
		tendon.position = Vector3(tx * 0.72, 0.74, -0.46)
		tendon.rotation.z = -tx * 0.14
		_hand.add_child(tendon)

	for dvi in range(5):
		var dx := -0.95 + float(dvi) * 0.48
		var dv := MeshInstance3D.new()
		dv.name = "DorsalVein%d" % dvi
		dv.mesh = _vein_branch_mesh
		dv.material_override = _vein_mat
		dv.position = Vector3(dx * 0.65, 0.15, -0.48)
		dv.rotation.z = -dx * 0.24
		dv.scale = Vector3(1.15, 1.35, 1.15)
		veins_root.add_child(dv)

	for pvi in range(2):
		var pv := MeshInstance3D.new()
		pv.name = "PalmVein%d" % pvi
		pv.mesh = _vein_branch_mesh
		pv.material_override = _vein_mat
		pv.position = Vector3(-0.42 + float(pvi) * 0.84, 0.05, 0.48)
		pv.rotation.z = 0.22 if pvi == 0 else -0.22
		veins_root.add_child(pv)

	var sigil := MeshInstance3D.new()
	sigil.name = "PalmSigil"
	sigil.mesh = _sigil_mesh
	sigil.rotation_degrees.x = 90.0
	sigil.position = Vector3(0.0, 0.72, 0.0)
	_hand.add_child(sigil)

	# 5 anatomical 3-joint finger chains: Thumb (opposable) + Index/Middle/Ring/Pinky
	var specs := [
		{"pos": Vector3(-1.35, 0.35, 0.42), "rot": Vector3(0.0, -0.85, 0.62), "scale": 0.85, "thumb": true},
		{"pos": Vector3(-0.96, 1.88, 0.02), "rot": Vector3(0.0, 0.0, 0.16), "scale": 0.94, "thumb": false},
		{"pos": Vector3(-0.32, 2.02, 0.00), "rot": Vector3(0.0, 0.0, 0.05), "scale": 1.05, "thumb": false},
		{"pos": Vector3(0.32, 1.94, 0.00), "rot": Vector3(0.0, 0.0, -0.06), "scale": 0.96, "thumb": false},
		{"pos": Vector3(0.96, 1.76, 0.04), "rot": Vector3(0.0, 0.0, -0.18), "scale": 0.80, "thumb": false},
	]
	for i in range(specs.size()):
		var sp: Dictionary = specs[i]
		var mcp := Node3D.new()
		mcp.name = "Finger%d" % (i + 1)
		mcp.position = sp["pos"]
		mcp.rotation = sp["rot"]
		mcp.scale = Vector3.ONE * float(sp["scale"])
		_hand.add_child(mcp)

		var knuckle := MeshInstance3D.new()
		knuckle.mesh = _knuckle_mesh
		mcp.add_child(knuckle)

		var prox := MeshInstance3D.new()
		prox.mesh = _proximal_mesh
		prox.position = Vector3(0.0, 0.68, 0.0)
		mcp.add_child(prox)

		var prox_vein := MeshInstance3D.new()
		prox_vein.name = "VeinProx"
		prox_vein.mesh = _vein_branch_mesh
		prox_vein.material_override = _vein_mat
		prox_vein.position = Vector3(0.0, 0.05, -0.24)
		prox_vein.scale = Vector3(0.75, 0.92, 0.75)
		mcp.add_child(prox_vein)

		var pip := Node3D.new()
		pip.name = "PIP"
		pip.position = Vector3(0.0, 1.32, 0.0)
		pip.rotation.x = 0.22
		mcp.add_child(pip)

		var pip_joint := MeshInstance3D.new()
		pip_joint.name = "PIPJoint"
		pip_joint.mesh = _joint_mesh
		pip.add_child(pip_joint)

		var mid := MeshInstance3D.new()
		mid.mesh = _middle_mesh
		mid.position = Vector3(0.0, 0.52, 0.0)
		pip.add_child(mid)

		var mid_vein := MeshInstance3D.new()
		mid_vein.name = "VeinMid"
		mid_vein.mesh = _vein_branch_mesh
		mid_vein.material_override = _vein_mat
		mid_vein.position = Vector3(0.0, 0.04, -0.19)
		mid_vein.scale = Vector3(0.58, 0.72, 0.58)
		pip.add_child(mid_vein)

		var dip := Node3D.new()
		dip.name = "DIP"
		dip.position = Vector3(0.0, 1.02, 0.0)
		dip.rotation.x = 0.28
		pip.add_child(dip)

		var dip_joint := MeshInstance3D.new()
		dip_joint.name = "DIPJoint"
		dip_joint.mesh = _joint_mesh
		dip_joint.scale = Vector3.ONE * 0.80
		dip.add_child(dip_joint)

		var dist := MeshInstance3D.new()
		dist.mesh = _distal_mesh
		dist.position = Vector3(0.0, 0.38, 0.0)
		dip.add_child(dist)

		var cuticle := MeshInstance3D.new()
		cuticle.name = "NailCuticle"
		cuticle.mesh = _cuticle_mesh
		cuticle.position = Vector3(0.0, 0.24, -0.06)
		cuticle.rotation_degrees.x = 22.0
		dip.add_child(cuticle)

		var nail := MeshInstance3D.new()
		nail.name = "Fingernail"
		nail.mesh = _nail_mesh
		dip.add_child(nail)

		_finger_chains.append({
			"mcp": mcp, "pip": pip, "dip": dip,
			"base_rot": sp["rot"], "thumb": sp["thumb"],
		})

	if Settings.quality_multiplier() >= 0.5:
		_light = OmniLight3D.new()
		_light.light_color = Color(0.95, 0.06, 0.14)
		_light.light_energy = 6.5
		_light.omni_range = 15.0
		_light.position = Vector3(0.0, 1.2, 0.4)
		_light.add_to_group("vfx_light")
		_hand.add_child(_light)
		VFX._cap_group(_hand, "vfx_light", VFX.MAX_IMPACT_LIGHTS)


func _release_light() -> void:
	if is_instance_valid(_light):
		if _light.is_in_group("vfx_light"):
			_light.remove_from_group("vfx_light")
		_light.queue_free()
	_light = null


func _exit_tree() -> void:
	_release_light()


func _apply_finger_curl(curl: float) -> void:
	for ch in _finger_chains:
		var mcp := ch["mcp"] as Node3D
		var pip := ch["pip"] as Node3D
		var dip := ch["dip"] as Node3D
		var base_rot: Vector3 = ch["base_rot"]
		if bool(ch["thumb"]):
			mcp.rotation = base_rot + Vector3(curl * 0.65, curl * 0.45, -curl * 0.95)
			pip.rotation.x = 0.22 + curl * 0.85
			dip.rotation.x = 0.28 + curl * 0.75
		else:
			mcp.rotation = base_rot + Vector3(curl * 1.15, 0.0, 0.0)
			pip.rotation.x = 0.22 + curl * 1.10
			dip.rotation.x = 0.28 + curl * 0.85


func _physics_process(delta: float) -> void:
	if not _armed or _detonated:
		return
	_age += delta
	var t := clampf(_age / fall_duration, 0.0, 1.0)
	var reduced := Settings.reduced_motion()
	var quality := Settings.quality_multiplier()

	if _portal != null:
		var p_scale := clampf(t / 0.30, 0.05, 1.0) * blast_radius * 0.58
		_portal.scale = Vector3(p_scale, 1.0, p_scale)
	if _rune_ring != null and not reduced:
		_rune_ring.rotation.y -= delta * (1.4 + t * 2.5)
	for crack in _telegraph_cracks:
		var c_len := clampf(t / 0.35, 0.1, 1.0) * 1.15
		crack.scale = Vector3(1.0, 1.0, c_len)

	if _hand != null:
		# Stage 2 breach burst when talons punch through the asphalt at t >= 0.26
		if not _breached and t >= 0.26:
			_breached = true
			if not reduced and quality > 0.0:
				var fx := get_parent() as Node3D
				if fx != null:
					VFX._particle(fx, Vector3(target_pos.x, maxf(0.0, target_pos.y) + 0.25, target_pos.z),
							maxi(10, int(28 * quality)), 0.55, Vector3.UP, 38.0,
							4.0, 10.0, [Color(1.0, 0.22, 0.15, 0.9), Color(0.25, 0.02, 0.04, 0.0)],
							0.5, Vector3(0.0, -9.8, 0.0), true, {"tex": "fire", "quad": 0.45, "explosiveness": 0.9})
			var sfx := get_node_or_null("/root/Sfx")
			if sfx != null and sfx.has_method("play_3d"):
				sfx.call("play_3d", "impact", target_pos, 1.4, 0.55)
			if not reduced and get_tree() != null:
				var cam := get_tree().get_first_node_in_group("camera_rig")
				if cam != null and cam.has_method("add_shake"):
					var cam_dist := (cam as Node3D).global_position.distance_to(target_pos) if cam is Node3D else 0.0
					cam.call("add_shake", 0.22 * clampf(1.0 - cam_dist / 65.0, 0.15, 1.0))

		var rise_t := clampf((t - 0.14) / 0.64, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - rise_t, 3.0)  # powerful cubic-out eruption
		_hand.position.y = lerpf(RISE_START_Y, RISE_END_Y, eased)
		if _vein_mat != null:
			if reduced:
				_vein_mat.emission_energy_multiplier = 2.6
			else:
				var freq := lerpf(5.5, 20.0, t)
				var beat := pow(0.5 + 0.5 * sin(_age * freq), 2.0)
				_vein_mat.emission_energy_multiplier = lerpf(1.6, 4.8, t) + (0.6 + 1.4 * t) * beat
		if is_instance_valid(_light):
			_light.light_energy = lerpf(6.5, 12.0, clampf((t - 0.4) / 0.6, 0.0, 1.0))
		if not reduced:
			_hand.rotation.y = _hand_base_yaw + sin(_age * 3.8) * 0.14 * (1.0 - t * 0.4)
			_hand.rotation.z = sin(_age * 2.4) * 0.06 * (1.0 - t * 0.4)
			var pre_curl := -0.18 * (1.0 - clampf(t / 0.68, 0.0, 1.0)) + 0.44 * clampf((t - 0.72) / 0.28, 0.0, 1.0)
			_apply_finger_curl(pre_curl)

	if _inner_ring != null:
		var r := lerpf(blast_radius * 0.95, 0.35, t)
		_inner_ring.scale = Vector3(r, 1.0, r)
	if _outer_ring != null:
		var pulse := 1.0 if reduced else (1.0 + 0.05 * sin(_age * 22.0))
		_outer_ring.scale = Vector3(blast_radius * pulse, 1.0, blast_radius * pulse)
	if _age >= fall_duration:
		_detonate()


func _detonate() -> void:
	if _detonated:
		return
	_detonated = true
	if is_in_group("meteor_strike"):
		remove_from_group("meteor_strike")
	_release_light()

	var reduced := Settings.reduced_motion()
	var quality := Settings.quality_multiplier()
	if _hand != null and not reduced:
		# Slam into a crushing fist, pause briefly, then yank straight underground!
		var dt := create_tween()
		dt.tween_method(_apply_finger_curl, 0.44, 1.25, 0.10).set_ease(Tween.EASE_OUT)
		dt.tween_interval(0.08)
		dt.tween_property(_hand, "position:y", RISE_START_Y - 1.2, 0.34).set_ease(Tween.EASE_IN)
		if _portal != null:
			dt.parallel().tween_property(_portal, "scale", Vector3(0.01, 1.0, 0.01), 0.34)
		if _outer_ring != null:
			dt.parallel().tween_property(_outer_ring, "scale", Vector3(0.01, 1.0, 0.01), 0.34)
		dt.tween_callback(queue_free)
	else:
		queue_free()

	var fx := get_parent() as Node3D
	if fx == null and get_tree() != null:
		fx = get_tree().current_scene as Node3D
	if fx != null:
		_impact_vfx(fx, reduced, quality)

	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		if sfx.has_method("play_3d"):
			sfx.call("play_3d", "explosion", target_pos, 2.0, 0.68)
		elif sfx.has_method("play"):
			sfx.call("play", "explosion", 2.0, 0.68)

	var cam := get_tree().get_first_node_in_group("camera_rig") if get_tree() != null else null
	if cam != null and cam.has_method("add_shake"):
		var cam_dist := (cam as Node3D).global_position.distance_to(target_pos) if cam is Node3D else 0.0
		var shake := 0.85 * clampf(1.0 - cam_dist / 65.0, 0.15, 1.0)
		cam.call("add_shake", shake)

	impacted.emit(target_pos)

	var tree := get_tree()
	if tree == null:
		return
	COMBAT_AOE.apply_lethal_blast(tree, fx, target_pos, blast_radius,
			owner_id, owner_node, token, true)


func _impact_vfx(fx: Node3D, reduced: bool, quality: float) -> void:
	var ground_y := maxf(0.0, target_pos.y)
	if reduced:
		VFX._static_cue(fx, Vector3(target_pos.x, ground_y + 0.40, target_pos.z),
				Color(0.92, 0.06, 0.14), blast_radius * 0.90, 0.24)
		return
	var ground_pos := Vector3(target_pos.x, ground_y + 0.06, target_pos.z)
	VFX._ring_quad(fx, ground_pos, blast_radius * 0.68,
			Color(1.0, 0.10, 0.16, 0.94), 1.95, 0.36)
	VFX._ring_quad(fx, Vector3(target_pos.x, ground_y + 0.16, target_pos.z),
			blast_radius * 0.44, Color(0.75, 0.02, 0.10, 0.82), 2.20, 0.28)
	if quality > 0.0:
		VFX._particle(fx, Vector3(target_pos.x, ground_y + 0.35, target_pos.z),
				maxi(18, int(64 * quality)), 0.78, Vector3.UP, 64.0,
				3.5, 13.5, [
					Color(1.0, 0.18, 0.22, 0.96),
					Color(0.65, 0.03, 0.08, 0.80),
					Color(0.08, 0.01, 0.02, 0.0),
				], 0.85, Vector3(0.0, -5.0, 0.0), true,
				{"tex": "fire", "quad": 0.58, "explosiveness": 0.95})

	var cracks := Node3D.new()
	cracks.name = "DevilHandCracks"
	cracks.position = ground_pos
	fx.add_child(cracks)
	var mats: Array[StandardMaterial3D] = []
	var count := maxi(6, int(12 * maxf(0.40, quality)))
	for i in range(count):
		var angle := TAU * float(i) / float(count) + 0.12 * sin(float(i) * 3.7)
		var mat := VFX._additive(Color(1.0, 0.08, 0.12, 0.90), 3.2)
		var crack := MeshInstance3D.new()
		crack.mesh = _crack_mesh
		crack.material_override = mat
		var reach := blast_radius * lerpf(0.55, 0.92, fmod(float(i), 3.0) / 2.0)
		crack.position = Vector3(sin(angle) * reach, 0.0, cos(angle) * reach)
		crack.rotation.y = angle
		crack.scale = Vector3(1.0, 1.0, lerpf(0.65, 1.25, fmod(float(i), 4.0) / 3.0))
		cracks.add_child(crack)
		mats.append(mat)
	if not mats.is_empty():
		var ct := cracks.create_tween()
		ct.tween_property(mats[0], "albedo_color:a", 0.0, 0.42)
		for i in range(1, mats.size()):
			ct.parallel().tween_property(mats[i], "albedo_color:a", 0.0, 0.42)
		ct.tween_callback(cracks.queue_free)
