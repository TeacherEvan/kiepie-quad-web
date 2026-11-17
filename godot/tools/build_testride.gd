extends SceneTree
# Builds res://scenes/TestRide.tscn - flat asphalt pad with the Kiepie Bike,
# sun, environment, follow/orbit camera, HUD, ramps and 3 smashable buildings.

const OUT := "res://scenes/TestRide.tscn"
const DECOR := preload("res://src/game/BuildingDecor.gd")


func _chip(bg := Color(0.075, 0.085, 0.105, 0.80),
		border := Color(1.0, 1.0, 1.0, 0.08)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_top = 1
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_bottom = 2
	s.corner_radius_top_left = 12
	s.corner_radius_top_right = 12
	s.corner_radius_bottom_left = 12
	s.corner_radius_bottom_right = 12
	s.content_margin_left = 14.0
	s.content_margin_right = 14.0
	s.content_margin_top = 7.0
	s.content_margin_bottom = 7.0
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0.0, 3.0)
	return s


func _button_style(bg: Color, border: Color, corner := 13) -> StyleBoxFlat:
	var s := _chip(bg, border)
	s.corner_radius_top_left = corner
	s.corner_radius_top_right = corner
	s.corner_radius_bottom_left = corner
	s.corner_radius_bottom_right = corner
	return s


func _style_button(btn: Button, accent: Color) -> void:
	var normal := _button_style(Color(0.090, 0.106, 0.137, 0.88), Color(0.42, 0.50, 0.62, 0.55))
	var hover := _button_style(Color(0.122, 0.145, 0.184, 0.92), accent)
	var pressed := _button_style(Color(0.055, 0.063, 0.082, 0.94), Color(1.0, 0.82, 0.42, 0.95))
	var focus := _button_style(Color(0.090, 0.106, 0.137, 0.88), Color(1.0, 0.75, 0.30, 0.9))
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_color_override("font_color", Color(0.91, 0.93, 0.97, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.82, 0.45, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.93, 0.62, 1.0))
	btn.add_theme_font_size_override("font_size", 15)
	btn.custom_minimum_size = Vector2(0.0, 44.0)


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "TestRide"

	# ---------------- environment
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.11, 0.19, 0.40, 1)
	sky_mat.sky_horizon_color = Color(0.42, 0.60, 0.72, 1)
	sky_mat.ground_horizon_color = Color(0.34, 0.37, 0.40, 1)
	sky_mat.ground_bottom_color = Color(0.16, 0.15, 0.14, 1)
	sky_mat.sun_angle_max = 28.0
	sky_mat.sun_curve = 0.18
	var sky_res := Sky.new()
	sky_res.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = 2
	env.sky = sky_res
	env.ambient_light_source = 3
	env.ambient_light_sky_contribution = 0.62
	env.ambient_light_color = Color(0.72, 0.80, 0.88, 1)
	env.ambient_light_energy = 0.68
	env.fog_enabled = true
	env.fog_light_color = Color(0.32, 0.40, 0.46, 1)
	env.fog_density = 0.00125
	env.tonemap_mode = 3
	env.tonemap_exposure = 1.18
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)

	# ---------------- sun
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.75
	sun.light_color = Color(1.0, 0.97, 0.90, 1)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	sun.rotation_degrees = Vector3(-48.0, 25.0, 0.0)
	root.add_child(sun)

	# ---------------- ground pad (asphalt)
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var ground_col := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(400.0, 1.0, 400.0)
	ground_col.shape = ground_shape
	ground.add_child(ground_col)
	var ground_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	var asphalt := StandardMaterial3D.new()
	var asphalt_tex := load("res://assets/tex_asphalt.png") as Texture2D
	asphalt.albedo_texture = asphalt_tex
	asphalt.albedo_color = Color(0.82, 0.82, 0.86, 1)
	asphalt.roughness = 0.96
	asphalt.uv1_scale = Vector3(210.0, 210.0, 1.0)
	box.material = asphalt
	ground_mesh.mesh = box
	ground.add_child(ground_mesh)
	ground.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(ground)

	# ---------------- cones (ring + a slalom pair)
	_add_cone_ring(root, 30.0, 24)
	_add_cones(root, [Vector3(8, 0.35, 14), Vector3(-8, 0.35, 14),
						Vector3(8, 0.35, -6), Vector3(-8, 0.35, -6)])

	# ---------------- start line
	var pad := MeshInstance3D.new()
	pad.name = "StartLine"
	var start_mesh := BoxMesh.new()
	start_mesh.size = Vector3(14.0, 0.012, 1.6)
	var start_mat := StandardMaterial3D.new()
	start_mat.albedo_color = Color(0.88, 0.88, 0.88, 1)
	start_mat.roughness = 0.75
	start_mesh.material = start_mat
	pad.mesh = start_mesh
	pad.position = Vector3(0.0, 0.012, 8.0)
	root.add_child(pad)

	# ---------------- ramps (drive over them)
	_add_ramp(root, "RampLeft", Vector3(-8.0, 0.0, 10.0), Vector3(13.0, 0.0, 0.0))
	_add_ramp(root, "RampRight", Vector3(8.0, 0.0, 14.0), Vector3(13.0, 0.0, 0.0))
	_add_ramp(root, "RampBig", Vector3(0.0, 0.0, 26.0), Vector3(16.0, 0.0, 0.0))
	# jump line: RampBig clears the cone ring, a down-slope waits at z=40
	_add_ramp(root, "RampBigLanding", Vector3(0.0, 0.0, 40.0), Vector3(10.0, 180.0, 0.0))
	# south kicker and the return lane's side hop
	_add_ramp(root, "RampSouth", Vector3(0.0, 0.0, -20.0), Vector3(14.0, 0.0, 0.0))
	_add_ramp(root, "RampWest", Vector3(-22.0, 0.0, -2.0), Vector3(13.0, 90.0, 0.0))

	# ---------------- buildings (drive through / smash)

	# ---------------- the Kiepie Bike
	var bike_scene: PackedScene = load("res://scenes/KiepieBike.tscn")
	var bike := bike_scene.instantiate()
	bike.name = "KiepieBike"
	bike.position = Vector3(0.0, 0.45, 8.0)
	bike.rotation = Vector3(0.0, 0.0, 0.0)
	bike.add_to_group("bike")
	root.add_child(bike)

	# ---------------- camera rig + camera
	var rig := Node3D.new()
	rig.name = "CameraRig"
	rig.position = Vector3(0.0, 1.6, 13.0)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	cam.fov = 62.0
	rig.add_child(cam)
	rig.set_script(load("res://src/FollowCam.gd"))
	rig.set("target_path", NodePath("../KiepieBike"))
	root.add_child(rig)

	# ---------------- HUD
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	layer.set_script(load("res://src/Hud.gd"))

	var help := Label.new()
	help.name = "Help"
	help.text = ("KIEPIE QUAD\nW/Up throttle   S/Down brake   A/D steer\n"
			+ "Q/E dodge left/right   SHIFT = turbo\n"
			+ "Space handbrake   C = camera   R = restart")
	help.position = Vector2(16, 14)
	help.offset_right = 244.0
	help.offset_bottom = 110.0
	help.autowrap_mode = 2
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.78, 0.83, 0.89, 0.96))
	help.add_theme_stylebox_override("normal", _chip())
	layer.add_child(help)

	var speed := Label.new()
	speed.name = "Speed"
	speed.text = "0 km/h"
	speed.position = Vector2(16, 128)
	speed.offset_right = 150.0
	speed.offset_bottom = 176.0
	speed.add_theme_font_size_override("font_size", 30)
	speed.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	speed.add_theme_stylebox_override("normal", _chip(Color(0.06, 0.075, 0.10, 0.82)))
	layer.add_child(speed)

	var smashed := Label.new()
	smashed.name = "Smashed"
	smashed.text = "Buildings smashed: 0 / 4"
	smashed.position = Vector2(16, 186)
	smashed.offset_right = 260.0
	smashed.offset_bottom = 220.0
	smashed.add_theme_font_size_override("font_size", 16)
	smashed.add_theme_color_override("font_color", Color(1.0, 0.83, 0.38, 1.0))
	smashed.add_theme_stylebox_override("normal",
			_chip(Color(0.085, 0.075, 0.035, 0.82), Color(1.0, 0.83, 0.38, 0.28)))
	layer.add_child(smashed)

	var turbo := Label.new()
	turbo.name = "Turbo"
	turbo.text = "TURBO"
	turbo.visible = false
	turbo.anchor_left = 0.5
	turbo.anchor_right = 0.5
	turbo.offset_left = -110.0
	turbo.offset_right = 110.0
	turbo.offset_top = 20.0
	turbo.offset_bottom = 84.0
	turbo.horizontal_alignment = 1
	turbo.add_theme_font_size_override("font_size", 42)
	turbo.add_theme_color_override("font_color", Color(1.0, 0.68, 0.16, 1.0))
	turbo.add_theme_constant_override("outline_size", 10)
	turbo.add_theme_color_override("font_outline_color", Color(0.10, 0.02, 0.0, 0.9))
	turbo.add_theme_stylebox_override("normal",
			_chip(Color(0.13, 0.05, 0.01, 0.85), Color(1.0, 0.55, 0.12, 0.65)))
	layer.add_child(turbo)

	var restart := Button.new()
	restart.name = "RestartBtn"
	restart.text = "Restart  (R)"
	restart.anchor_right = 1.0
	restart.anchor_left = 1.0
	restart.offset_right = -14.0
	restart.offset_left = -150.0
	restart.offset_top = 12.0
	restart.offset_bottom = 56.0
	restart.focus_mode = Control.FOCUS_NONE
	_style_button(restart, Color(1.0, 0.46, 0.10, 0.9))
	layer.add_child(restart)

	var view := Button.new()
	view.name = "ViewBtn"
	view.text = "View: CHASE (click to orbit)"
	view.anchor_right = 1.0
	view.anchor_left = 1.0
	view.offset_right = -14.0
	view.offset_left = -150.0
	view.offset_top = 64.0
	view.offset_bottom = 108.0
	view.focus_mode = Control.FOCUS_NONE
	_style_button(view, Color(1.0, 0.46, 0.10, 0.9))
	layer.add_child(view)

	root.add_child(layer)

	# ---------------- touch controls (mobile)
	_add_touch_controls(root)

	# ---------------- buildings: create now so we can wire the smash signal
	var b1 := _add_building(root, "Workshop", "Workshop",
			Vector3(13.0, 0.0, 22.0), Vector3(6.5, 3.4, 5.0), Color(0.44, 0.31, 0.25))
	var b2 := _add_building(root, "Shed", "Shed",
			Vector3(12.0, 0.0, -14.0), Vector3(4.2, 2.3, 3.6), Color(0.55, 0.55, 0.55))
	var b3 := _add_building(root, "Store", "Store",
			Vector3(-12.5, 0.0, 18.0), Vector3(4.8, 4.6, 4.2), Color(0.30, 0.37, 0.47))
	_add_building(root, "Garage", "Garage",
			Vector3(-14.0, 0.0, -18.0), Vector3(5.0, 3.0, 4.4), Color(0.48, 0.44, 0.38))
	# HUD total is an exported property so it is serialized into the .tscn
	var hud_node := root.get_node_or_null("HUD")
	if hud_node != null:
		hud_node.set("smash_total", 4)
	# ---------------- save (own the instance, never its children)
	for child in root.get_children():
		child.owner = root
		if child.name != "KiepieBike":
			_set_owners(child, root)
	var scene := PackedScene.new()
	if scene.pack(root) != OK:
		printerr("pack failed")
		quit(1)
		return
	if ResourceSaver.save(scene, OUT) != OK:
		printerr("save failed")
		quit(1)
		return
	print("saved ", OUT)
	quit()


func _set_owners(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_set_owners(child, owner)


func _add_touch_controls(root: Node) -> void:
	var touch := CanvasLayer.new()
	touch.name = "TouchHUD"
	touch.layer = 2  # above the HUD; clusters don't overlap it visually
	touch.set_script(load("res://src/TouchControls.gd"))

	# --- left thumb: steering (bottom-left corner)
	var left := Button.new()
	left.name = "BtnLeft"
	left.text = "<"
	left.anchor_left = 0.0
	left.anchor_right = 0.0
	left.anchor_top = 1.0
	left.anchor_bottom = 1.0
	left.offset_left = 10.0
	left.offset_right = 98.0
	left.offset_top = -128.0
	left.offset_bottom = -18.0
	left.focus_mode = Control.FOCUS_NONE
	_style_button(left, Color(0.42, 0.50, 0.62, 0.55))
	left.add_theme_font_size_override("font_size", 44)
	touch.add_child(left)

	var right := Button.new()
	right.name = "BtnRight"
	right.text = ">"
	right.anchor_left = 0.0
	right.anchor_right = 0.0
	right.anchor_top = 1.0
	right.anchor_bottom = 1.0
	right.offset_left = 106.0
	right.offset_right = 194.0
	right.offset_top = -128.0
	right.offset_bottom = -18.0
	right.focus_mode = Control.FOCUS_NONE
	_style_button(right, Color(0.42, 0.50, 0.62, 0.55))
	right.add_theme_font_size_override("font_size", 44)
	touch.add_child(right)

	# --- dodge leaps: above the steering cluster, same left thumb reach
	var dodge_left := Button.new()
	dodge_left.name = "BtnDodgeLeft"
	dodge_left.text = "DODGE L"
	dodge_left.anchor_left = 0.0
	dodge_left.anchor_right = 0.0
	dodge_left.anchor_top = 1.0
	dodge_left.anchor_bottom = 1.0
	dodge_left.offset_left = 10.0
	dodge_left.offset_right = 98.0
	dodge_left.offset_top = -234.0
	dodge_left.offset_bottom = -144.0
	dodge_left.focus_mode = Control.FOCUS_NONE
	_style_button(dodge_left, Color(0.55, 0.42, 0.78, 0.85))
	dodge_left.add_theme_font_size_override("font_size", 15)
	dodge_left.pivot_offset = Vector2(45.0, 45.0)
	touch.add_child(dodge_left)

	var dodge_right := Button.new()
	dodge_right.name = "BtnDodgeRight"
	dodge_right.text = "DODGE R"
	dodge_right.anchor_left = 0.0
	dodge_right.anchor_right = 0.0
	dodge_right.anchor_top = 1.0
	dodge_right.anchor_bottom = 1.0
	dodge_right.offset_left = 106.0
	dodge_right.offset_right = 194.0
	dodge_right.offset_top = -234.0
	dodge_right.offset_bottom = -144.0
	dodge_right.focus_mode = Control.FOCUS_NONE
	_style_button(dodge_right, Color(0.55, 0.42, 0.78, 0.85))
	dodge_right.add_theme_font_size_override("font_size", 15)
	dodge_right.pivot_offset = Vector2(45.0, 45.0)
	touch.add_child(dodge_right)

	# --- right thumb: TURBO above BRAKE, big GAS on the far right (bottom-right corner)
	var turbo_btn := Button.new()
	turbo_btn.name = "BtnTurbo"
	turbo_btn.text = "TURBO"
	turbo_btn.anchor_left = 1.0
	turbo_btn.anchor_right = 1.0
	turbo_btn.anchor_top = 1.0
	turbo_btn.anchor_bottom = 1.0
	turbo_btn.offset_left = -182.0
	turbo_btn.offset_right = -98.0
	turbo_btn.offset_top = -194.0
	turbo_btn.offset_bottom = -128.0
	turbo_btn.focus_mode = Control.FOCUS_NONE
	_style_button(turbo_btn, Color(1.0, 0.68, 0.16, 0.9))
	turbo_btn.add_theme_font_size_override("font_size", 18)
	touch.add_child(turbo_btn)

	var brake := Button.new()
	brake.name = "BtnBrake"
	brake.text = "BRAKE"
	brake.anchor_left = 1.0
	brake.anchor_right = 1.0
	brake.anchor_top = 1.0
	brake.anchor_bottom = 1.0
	brake.offset_left = -182.0
	brake.offset_right = -98.0
	brake.offset_top = -112.0
	brake.offset_bottom = -12.0
	brake.focus_mode = Control.FOCUS_NONE
	_style_button(brake, Color(0.55, 0.60, 0.70, 0.65))
	brake.add_theme_font_size_override("font_size", 20)
	touch.add_child(brake)

	var gas := Button.new()
	gas.name = "BtnGas"
	gas.text = "GAS"
	gas.anchor_left = 1.0
	gas.anchor_right = 1.0
	gas.anchor_top = 1.0
	gas.anchor_bottom = 1.0
	gas.offset_left = -90.0
	gas.offset_right = -8.0
	gas.offset_top = -176.0
	gas.offset_bottom = -18.0
	gas.focus_mode = Control.FOCUS_NONE
	_style_button(gas, Color(1.0, 0.46, 0.10, 0.9))
	gas.add_theme_font_size_override("font_size", 36)
	touch.add_child(gas)

	# --- top-right column, below Restart/View: manual overlay toggle (auto-detect fallback)
	var toggle := Button.new()
	toggle.name = "BtnTouchToggle"
	toggle.text = "TOUCH: AUTO"
	toggle.anchor_left = 1.0
	toggle.anchor_right = 1.0
	toggle.anchor_top = 0.0
	toggle.anchor_bottom = 0.0
	toggle.offset_left = -164.0
	toggle.offset_right = -14.0
	toggle.offset_top = 116.0
	toggle.offset_bottom = 160.0
	toggle.focus_mode = Control.FOCUS_NONE
	_style_button(toggle, Color(0.42, 0.50, 0.62, 0.55))
	toggle.add_theme_font_size_override("font_size", 13)
	touch.add_child(toggle)

	root.add_child(touch)


func _add_cone_ring(root: Node, radius: float, count: int) -> void:
	for i in range(count):
		var angle := TAU * float(i) / float(count)
		var pos := Vector3(cos(angle) * radius, 0.35, sin(angle) * radius)
		_add_cones(root, [pos])


func _add_cones(root: Node, positions: Array) -> void:
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.02
	cone_mesh.bottom_radius = 0.16
	cone_mesh.height = 0.7
	var cone_mat := StandardMaterial3D.new()
	var cone_tex := load("res://assets/tex_cone.png") as Texture2D
	cone_mat.albedo_texture = cone_tex
	cone_mat.albedo_color = Color(1.0, 1.0, 1.0, 1)
	cone_mat.roughness = 0.45
	cone_mesh.material = cone_mat
	var cone_shape := CylinderShape3D.new()
	cone_shape.height = 0.7
	cone_shape.radius = 0.17

	for pos in positions:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		col.shape = cone_shape
		body.add_child(col)
		var mesh := MeshInstance3D.new()
		mesh.mesh = cone_mesh
		body.add_child(mesh)
		body.position = pos
		root.add_child(body)


func _add_ramp(root: Node, ramp_name: String, pos: Vector3, rot_deg: Vector3) -> void:
	# ground-level frame: ramp node sits at y=0, plank is a rotated box whose
	# low (+Z) edge touches the ground; a stand column fills the high end.
	var theta: float = abs(deg_to_rad(rot_deg.x))
	var rot_x: float = -rot_deg.x   # low (-Z) edge faces the approach direction (+Z travel)
	var half_len := 1.75
	var plank_c := sin(theta) * half_len + 0.06
	var stand_h := sin(theta) * 2.0 * half_len * 0.82
	var stand_z := cos(theta) * (half_len * 0.78)

	var ramp := StaticBody3D.new()
	ramp.name = ramp_name

	var plank_shape := BoxShape3D.new()
	plank_shape.size = Vector3(2.7, 0.16, 3.5)
	var col1 := CollisionShape3D.new()
	col1.shape = plank_shape
	col1.position = Vector3(0.0, plank_c, 0.0)
	col1.rotation_degrees = Vector3(rot_x, 0.0, 0.0)
	ramp.add_child(col1)

	var stand_shape := BoxShape3D.new()
	stand_shape.size = Vector3(2.7, stand_h, 0.34)
	var col2 := CollisionShape3D.new()
	col2.shape = stand_shape
	col2.position = Vector3(0.0, stand_h * 0.5, stand_z)
	ramp.add_child(col2)

	var plank_mesh := BoxMesh.new()
	plank_mesh.size = plank_shape.size
	var plank_mat := StandardMaterial3D.new()
	plank_mat.albedo_color = Color(0.17, 0.17, 0.18, 1)
	plank_mat.roughness = 0.82
	plank_mesh.material = plank_mat
	var mesh1 := MeshInstance3D.new()
	mesh1.mesh = plank_mesh
	mesh1.position = col1.position
	mesh1.rotation_degrees = Vector3(rot_x, 0.0, 0.0)
	ramp.add_child(mesh1)

	var stand_mesh := BoxMesh.new()
	stand_mesh.size = stand_shape.size
	var stand_mat := StandardMaterial3D.new()
	stand_mat.albedo_color = Color(0.80, 0.62, 0.10, 1)
	stand_mat.roughness = 0.6
	stand_mesh.material = stand_mat
	var mesh2 := MeshInstance3D.new()
	mesh2.mesh = stand_mesh
	mesh2.position = col2.position
	ramp.add_child(mesh2)

	# chevron stripe across the plank face
	var stripe := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(2.55, 0.05, 0.32)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.95, 0.80, 0.14, 1)
	smat.roughness = 0.5
	smat.emission_enabled = true
	smat.emission = Color(0.85, 0.68, 0.10, 1)
	smat.emission_energy_multiplier = 1.5
	sm.material = smat
	stripe.mesh = sm
	stripe.position = Vector3(0.0, plank_c + 0.10, cos(theta) * 1.28)
	stripe.rotation_degrees = Vector3(rot_x, 0.0, 0.0)
	ramp.add_child(stripe)

	ramp.position = Vector3(pos.x, 0.0, pos.z)
	ramp.rotation_degrees.y = rot_deg.y
	root.add_child(ramp)


func _facade_texture_for(node_name: String) -> Texture2D:
	match node_name:
		"Workshop":
			return load("res://assets/tex_facade_workshop.png") as Texture2D
		"Shed":
			return load("res://assets/tex_facade_shed.png") as Texture2D
		"Store":
			return load("res://assets/tex_facade_store.png") as Texture2D
		"Garage":
			return load("res://assets/tex_facade_garage.jpg") as Texture2D
		_:
			return null


func _add_building(root: Node, node_name: String, display_name: String,
		origin: Vector3, size: Vector3, wall_color: Color) -> StaticBody3D:
	var building := StaticBody3D.new()
	building.name = node_name
	building.set_script(load("res://src/DestructibleBuilding.gd"))
	building.set("building_name", display_name)

	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	col.shape = box_shape
	col.position = Vector3(0.0, size.y * 0.5, 0.0)
	building.add_child(col)

	# main block (textured facade)
	var facade := _facade_texture_for(node_name)
	var body_mesh := BoxMesh.new()
	body_mesh.size = size
	var wall_mat := StandardMaterial3D.new()
	if facade != null:
		wall_mat.albedo_texture = facade
		wall_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
		wall_mat.uv1_scale = Vector3(1.0, 1.0, 1.0)
	else:
		wall_mat.albedo_color = wall_color
	wall_mat.roughness = 0.85
	body_mesh.material = wall_mat
	var body_inst := MeshInstance3D.new()
	body_inst.name = "MainBlock"
	body_inst.mesh = body_mesh
	body_inst.position = Vector3(0.0, size.y * 0.5, 0.0)
	building.add_child(body_inst)

	# roof slab
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(size.x + 0.5, 0.28, size.z + 0.5)
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.22, 0.23, 0.24, 1)
	roof_mat.roughness = 0.8
	roof_mesh.material = roof_mat
	var roof_inst := MeshInstance3D.new()
	roof_inst.name = "Roof"
	roof_inst.mesh = roof_mesh
	roof_inst.position = Vector3(0.0, size.y + 0.14, 0.0)
	building.add_child(roof_inst)

	# door (faces the pad centre)
	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3(size.x * 0.38, size.y * 0.62, 0.08)
	var door_mat := StandardMaterial3D.new()
	door_mat.albedo_color = Color(0.13, 0.12, 0.11, 1)
	door_mat.roughness = 0.7
	door_mesh.material = door_mat
	var door := MeshInstance3D.new()
	door.name = "Door"
	door.mesh = door_mesh
	door.position = Vector3(0.0, size.y * 0.31, size.z * 0.5 + 0.045)
	building.add_child(door)
	var awning_mesh := BoxMesh.new()
	awning_mesh.size = Vector3(size.x * 0.46, 0.10, 0.34)
	var awning_mat := StandardMaterial3D.new()
	awning_mat.albedo_color = Color(0.85, 0.42, 0.08, 1)
	awning_mat.roughness = 0.55
	door_mesh = awning_mesh
	var awning := MeshInstance3D.new()
	awning.name = "Awning"
	awning.mesh = door_mesh
	awning.position = Vector3(0.0, size.y * 0.62 + 0.28, size.z * 0.5 + 0.16)
	building.add_child(awning)

	DECOR.dress(building, size, display_name)

	# face the pad centre
	building.position = origin
	building.rotation.y = atan2(origin.x, origin.z) + PI
	# smash detection is handled by a SmashTrigger Area3D inside DestructibleBuilding._ready()
	root.add_child(building)
	return building
