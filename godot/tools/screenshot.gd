extends SceneTree
## Runs the demo scene under a real renderer (xvfb + mesa), lets the bike
## settle, positions the camera and saves a screenshot.
## Usage: godot-4.3 --path . --script tools/screenshot.gd

const CAMERA_POS := Vector3(-3.0, 1.3, 4.6)
const LOOK_AT := Vector3(0.0, 0.4, 8.0)
const RENDERS := "/home/leandi-duplessis/github/3D builds/Kiepie bike/renders"
const OUT := RENDERS + "/kiepie_godot_left_flank.png"

func _initialize() -> void:
	var inst: Node = load("res://scenes/TestRide.tscn").instantiate()
	root.add_child(inst)
	# cancel the follow-cam so we can place the camera ourselves
	var rig = inst.get_node("CameraRig")
	rig.set_script(null)
	var bike = inst.get_node("KiepieBike")

	# let the suspension settle
	for i in range(90):
		await physics_frame

	var cam: Camera3D = rig.get_node("Camera3D")
	rig.global_position = CAMERA_POS
	cam.look_at(LOOK_AT, Vector3.UP)

	for i in range(30):
		await self.process_frame

	var image := root.get_viewport().get_texture().get_image()
	image.save_png(OUT)
	print("saved ", OUT, " size ", image.get_width(), "x", image.get_height())
	quit()
