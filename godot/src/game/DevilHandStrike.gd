extends Node3D
## Evan the Skeleton's Special — DEVIL HAND. A giant demonic hand erupts from
## the ground inside the 7.5 m target zone after a 2.0 s telegraph, snaps its
## claws shut and drags everything in the kill zone underground for an instant
## kill. Same cooldown/broadcast contract as Meteor Shower; only the animation
## and the lethal resolution differ.

signal impacted(point: Vector3)

const FALL_DURATION := 2.0
const BLAST_RADIUS := 7.5
const RISE_START_Y := -3.5
const RISE_END_Y := 0.9
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
var _hand: Node3D
var _outer_ring: MeshInstance3D
var _inner_ring: MeshInstance3D
var _finger_pivots: Array[Node3D] = []
var _light: OmniLight3D

static var _ring_mesh: CylinderMesh = null
static var _disc_mesh: CylinderMesh = null
static var _palm_mesh: BoxMesh = null
static var _knuckle_mesh: SphereMesh = null
static var _finger_mesh: CapsuleMesh = null
static var _distal_mesh: CapsuleMesh = null
static var _claw_mesh: CylinderMesh = null
static var _forearm_mesh: CylinderMesh = null
static var _crack_mesh: BoxMesh = null


static func _ensure_meshes() -> void:
	if _ring_mesh == null:
		var rm := CylinderMesh.new()
		rm.top_radius = 1.0
		rm.bottom_radius = 1.0
		rm.height = 0.04
		rm.radial_segments = 28
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.85, 0.04, 0.12, 0.46)
		rmat.emission_enabled = true
		rmat.emission = Color(0.92, 0.06, 0.14)
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
		dmat.albedo_color = Color(1.0, 0.18, 0.12, 0.55)
		dmat.emission_enabled = true
		dmat.emission = Color(1.0, 0.12, 0.08)
		dmat.emission_energy_multiplier = 4.4
		dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		dm.material = dmat
		_disc_mesh = dm
	if _palm_mesh == null:
		var pm := BoxMesh.new()
		pm.size = Vector3(2.9, 0.85, 2.6)
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.21, 0.02, 0.05)
		pmat.emission_enabled = true
		pmat.emission = Color(0.72, 0.03, 0.09)
		pmat.emission_energy_multiplier = 0.85
		pmat.metallic = 0.35
		pmat.roughness = 0.58
		pm.material = pmat
		_palm_mesh = pm
	if _knuckle_mesh == null:
		var km := SphereMesh.new()
		km.radius = 0.38
		km.height = 0.44
		km.radial_segments = 10
		km.rings = 5
		var kmat := StandardMaterial3D.new()
		kmat.albedo_color = Color(0.27, 0.02, 0.06)
		kmat.emission_enabled = true
		kmat.emission = Color(0.80, 0.04, 0.10)
		kmat.emission_energy_multiplier = 1.1
		kmat.roughness = 0.52
		km.material = kmat
		_knuckle_mesh = km
	if _finger_mesh == null:
		var fm := CapsuleMesh.new()
		fm.radius = 0.27
		fm.height = 1.60
		fm.radial_segments = 10
		fm.rings = 5
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color(0.24, 0.02, 0.05)
		fmat.emission_enabled = true
		fmat.emission = Color(0.78, 0.03, 0.10)
		fmat.emission_energy_multiplier = 0.95
		fmat.metallic = 0.32
		fmat.roughness = 0.55
		fm.material = fmat
		_finger_mesh = fm
	if _distal_mesh == null:
		var dm2 := CapsuleMesh.new()
		dm2.radius = 0.23
		dm2.height = 1.10
		dm2.radial_segments = 10
		dm2.rings = 4
		var dmat2 := StandardMaterial3D.new()
		dmat2.albedo_color = Color(0.26, 0.02, 0.06)
		dmat2.emission_enabled = true
		dmat2.emission = Color(0.85, 0.04, 0.11)
		dmat2.emission_energy_multiplier = 1.1
		dmat2.roughness = 0.50
		dm2.material = dmat2
		_distal_mesh = dm2
	if _claw_mesh == null:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.006
		cm.bottom_radius = 0.185
		cm.height = 0.62
		cm.radial_segments = 8
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.95, 0.12, 0.10)
		cmat.emission_enabled = true
		cmat.emission = Color(1.0, 0.16, 0.10)
		cmat.emission_energy_multiplier = 4.2
		cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cm.material = cmat
		_claw_mesh = cm
	if _forearm_mesh == null:
		var fm2 := CylinderMesh.new()
		fm2.top_radius = 0.95
		fm2.bottom_radius = 1.20
		fm2.height = 3.40
		fm2.radial_segments = 12
		var fmat2 := StandardMaterial3D.new()
		fmat2.albedo_color = Color(0.17, 0.02, 0.05)
		fmat2.emission_enabled = true
		fmat2.emission = Color(0.62, 0.03, 0.08)
		fmat2.emission_energy_multiplier = 0.7
		fmat2.roughness = 0.65
		fm2.material = fmat2
		_forearm_mesh = fm2
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
		p_damage: float, p_token: String, p_color: Color = Color(0.85,0.06,0.20),
		p_fall_duration: float = 2.0, p_blast_radius: float = 7.5,
		p_visual_style: String = "devil_hand") -> void:
	owner_id = p_owner_id
	owner_node = p_owner_node
	target_pos = p_target_pos
	damage = p_damage
	token = p_token
	hit_color = p_color
	visual_style = p_visual_style if p_visual_style in ["devil_hand"] else "devil_hand"
	fall_duration = maxf(0.1, p_fall_duration)
	blast_radius = p_blast_radius
	global_position = target_pos
	_age = 0.0
	_armed = true
	_detonated = false
	add_to_group("meteor_strike")
	_build_visual()


func _build_visual() -> void:
	_ensure_meshes()
	_finger_pivots.clear()

	# Ground warning ring + shrinking countdown disc (same contract as Meteor).
	_outer_ring = MeshInstance3D.new()
	_outer_ring.name = "WarningRing"
	_outer_ring.mesh = _ring_mesh
	_outer_ring.position = Vector3(0.0, 0.06, 0.0)
	_outer_ring.scale = Vector3(blast_radius, 1.0, blast_radius)
	add_child(_outer_ring)

	_inner_ring = MeshInstance3D.new()
	_inner_ring.name = "CountdownRing"
	_inner_ring.mesh = _disc_mesh
	_inner_ring.position = Vector3(0.0, 0.08, 0.0)
	_inner_ring.scale = Vector3(blast_radius * 0.95, 1.0, blast_radius * 0.95)
	add_child(_inner_ring)

	# The hand waits below the deck, then erupts into the kill zone.
	_hand = Node3D.new()
	_hand.name = "DevilHand"
	_hand.position.y = RISE_START_Y
	add_child(_hand)

	var palm := MeshInstance3D.new()
	palm.name = "Palm"
	palm.mesh = _palm_mesh
	_hand.add_child(palm)

	var forearm := MeshInstance3D.new()
	forearm.name = "Forearm"
	forearm.mesh = _forearm_mesh
	forearm.rotation_degrees.x = 90.0
	forearm.position.z = -2.35
	_hand.add_child(forearm)

	# Four fingers plus a splayed thumb; each pivot carries two bent segments
	# and a glowing claw so the whole hand can curl as one grab.
	var finger_x := [-1.12, -0.56, 0.0, 0.56, 1.12]
	for i in range(finger_x.size()):
		var pivot := Node3D.new()
		pivot.name = "Finger%d" % (i + 1)
		pivot.position = Vector3(finger_x[i], 0.06, 1.12)
		if i == 0:
			# Thumb: lower, closer in and thrown sideways.
			pivot.position = Vector3(-1.30, 0.02, 0.28)
			pivot.rotation_degrees.y = -32.0
		elif i == 4:
			pivot.rotation_degrees.y = 9.0
		_hand.add_child(pivot)
		_finger_pivots.append(pivot)

		var knuckle := MeshInstance3D.new()
		knuckle.name = "Knuckle"
		knuckle.mesh = _knuckle_mesh
		knuckle.position.z = 0.06
		pivot.add_child(knuckle)

		var prox := MeshInstance3D.new()
		prox.name = "Proximal"
		prox.mesh = _finger_mesh
		prox.rotation_degrees.x = 90.0
		prox.position.z = 0.68
		pivot.add_child(prox)

		var distal := Node3D.new()
		distal.name = "Distal"
		distal.position.z = 1.38
		distal.rotation_degrees.x = 18.0
		pivot.add_child(distal)

		var tip_bone := MeshInstance3D.new()
		tip_bone.name = "DistalBone"
		tip_bone.mesh = _distal_mesh
		tip_bone.rotation_degrees.x = 90.0
		tip_bone.position.z = 0.42
		distal.add_child(tip_bone)

		var claw := MeshInstance3D.new()
		claw.name = "Claw"
		claw.mesh = _claw_mesh
		claw.rotation_degrees.x = 90.0
		claw.position.z = 0.98
		distal.add_child(claw)

	if Settings.quality_multiplier() >= 0.5:
		_light = OmniLight3D.new()
		_light.light_color = Color(0.92, 0.06, 0.12)
		_light.light_energy = 6.5
		_light.omni_range = 13.0
		_light.position = Vector3(0.0, 0.40, 0.60)
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


func _physics_process(delta: float) -> void:
	if not _armed or _detonated:
		return
	_age += delta
	var t := clampf(_age / fall_duration, 0.0, 1.0)
	var reduced := Settings.reduced_motion()
	if _hand != null:
		# Slow rise, then an aggressive grab snap over the last fifth.
		var rise_t := clampf((t - 0.06) / 0.86, 0.0, 1.0)
		var eased := rise_t * rise_t * (3.0 - 2.0 * rise_t)
		if t > 0.80:
			var snap := clampf((t - 0.80) / 0.20, 0.0, 1.0)
			eased = lerpf(eased, 1.0, snap * snap)
		_hand.position.y = lerpf(RISE_START_Y, RISE_END_Y, eased)
		if not reduced:
			_hand.rotation.y = sin(_age * 5.0) * 0.10 * (1.0 - t)
			_hand.rotation.z = sin(_age * 3.0) * 0.05 * (1.0 - t)
			var curl := clampf((t - 0.55) / 0.45, 0.0, 1.0)
			for pivot in _finger_pivots:
				pivot.rotation.x = curl * 0.30
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
		# Claws close around the catch, then the hand drags it under.
		for pivot in _finger_pivots:
			pivot.rotation.x = 1.35
		var dt := _hand.create_tween()
		dt.tween_property(_hand, "position:y", RISE_START_Y, 0.26).set_ease(Tween.EASE_IN)
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
		var shake := 0.78 * clampf(1.0 - cam_dist / 65.0, 0.15, 1.0)
		cam.call("add_shake", shake)

	impacted.emit(target_pos)

	var tree := get_tree()
	if tree == null:
		return
	# Instant kill: every rider in the zone is dragged down by its own
	# CombatController with the same "<token>:v<victim>" sub-token as rockets.
	COMBAT_AOE.apply_lethal_blast(tree, fx, target_pos, blast_radius,
			owner_id, owner_node, token, true)


func _impact_vfx(fx: Node3D, reduced: bool, quality: float) -> void:
	var ground_y := maxf(0.0, target_pos.y)
	if reduced:
		VFX._static_cue(fx, Vector3(target_pos.x, ground_y + 0.40, target_pos.z),
				Color(0.92, 0.06, 0.14), blast_radius * 0.90, 0.24)
		return
	var ground_pos := Vector3(target_pos.x, ground_y + 0.06, target_pos.z)
	VFX._ring_quad(fx, ground_pos, blast_radius * 0.62,
			Color(1.0, 0.10, 0.16, 0.92), 1.85, 0.34)
	VFX._ring_quad(fx, Vector3(target_pos.x, ground_y + 0.14, target_pos.z),
			blast_radius * 0.40, Color(0.75, 0.02, 0.10, 0.80), 2.10, 0.26)
	if quality > 0.0:
		VFX._particle(fx, Vector3(target_pos.x, ground_y + 0.35, target_pos.z),
				maxi(16, int(56 * quality)), 0.72, Vector3.UP, 64.0,
				3.0, 12.0, [
					Color(1.0, 0.16, 0.20, 0.95),
					Color(0.62, 0.03, 0.08, 0.78),
					Color(0.08, 0.01, 0.02, 0.0),
				], 0.80, Vector3(0.0, -5.0, 0.0), true,
				{"tex": "fire", "quad": 0.55, "explosiveness": 0.95})

	# Emissive fissures radiating out of the grab site.
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
