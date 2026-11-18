extends SceneTree
# Builds res://scenes/KiepieBike.tscn: a VehicleBody3D with the detailed
# GLB model, a 4-wheel raycast suspension setup and correct wheel pivots.

const GLB := "res://assets/Kiepie_Bike.glb"
const OUT := "res://scenes/KiepieBike.tscn"

func _initialize() -> void:
	var model_scene: PackedScene = load(GLB)
	if model_scene == null:
		printerr("Could not load ", GLB)
		quit(1)
		return
	var model := model_scene.instantiate()
	model.name = "Model"
	# VehicleBody3D with positive engine force drives toward local +Z;
	# the glTF import puts the Blender nose at +Z, so no flip is needed.

	var bike := VehicleBody3D.new()
	bike.name = "KiepieBike"
	bike.mass = 185.0
	# CENTER_OF_MASS_MODE_AUTO (0) makes the physics server ignore center_of_mass
	# entirely and derive it from the CollisionShape3D centroid (+0.56 m — top
	# heavy). CUSTOM (1) serializes and honours the authored CoM below the axles.
	bike.center_of_mass_mode = VehicleBody3D.CENTER_OF_MASS_MODE_CUSTOM
	bike.center_of_mass = Vector3(0.0, -0.32, 0.0)
	bike.inertia = Vector3(70.0, 120.0, 150.0)
	bike.continuous_cd = true
	bike.add_child(model)
	model.owner = bike

	# collision box that wraps the chassis (wheels are raycasts, not colliders)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.86, 0.52, 2.05)
	col.shape = box
	col.position = Vector3(0.0, 0.56, 0.02)
	bike.add_child(col)
	col.owner = bike

	# wheels: blender y -> godot z flips, blender z -> godot y
	# the wheel node is the suspension mount; the ray runs
	# wheel_rest_length + suspension_travel down from it.
	var wheel_defs := [
		{"name": "WheelFL", "pos": Vector3(-0.545, 0.50,  0.68),
				"radius": 0.280, "steer": true,  "rest": 0.22},
		{"name": "WheelFR", "pos": Vector3( 0.545, 0.50,  0.68),
				"radius": 0.280, "steer": true,  "rest": 0.22},
		{"name": "WheelRL", "pos": Vector3(-0.575, 0.50, -0.66),
				"radius": 0.280, "steer": false, "rest": 0.22},
		{"name": "WheelRR", "pos": Vector3( 0.575, 0.50, -0.66),
				"radius": 0.280, "steer": false, "rest": 0.22},
	]
	for d in wheel_defs:
		var w := VehicleWheel3D.new()
		w.name = d.name
		w.position = d.pos
		w.wheel_radius = d.radius
		w.wheel_rest_length = d.rest
		w.suspension_travel = 0.20
		w.suspension_stiffness = 45.0
		w.suspension_max_force = 1600.0
		w.damping_compression = 0.5
		w.damping_relaxation = 0.6
		w.wheel_friction_slip = 4.0
		w.use_as_steering = d.steer
		w.use_as_traction = true
		bike.add_child(w)
		w.owner = bike

	# give the whole bike a script for driving + visual wheel spin
	bike.set_script(load("res://src/KiepieBike.gd"))

	# NOTE: do NOT re-own the GLB instance's children. They belong to the
	# imported PackedScene; re-owning them makes pack() serialize ~200 duplicate
	# mesh nodes + inline ArrayMesh data into this scene (2.87 MB, double
	# geometry at runtime). Runtime lookups (Model/Wheel_*, Silencer_Tip)
	# resolve through the instance.

	var scene := PackedScene.new()
	var err := scene.pack(bike)
	if err != OK:
		printerr("pack failed: ", err)
		quit(1)
		return
	var save_err := ResourceSaver.save(scene, OUT)
	if save_err != OK:
		printerr("save failed: ", save_err)
		quit(1)
		return
	print("saved ", OUT)
	quit()
