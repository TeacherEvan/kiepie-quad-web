extends CanvasLayer
## HUD for the Kiepie Bike test track: speed, smash counter, turbo flash,
## and the on-screen Restart / View buttons (keyboard R / C works too).

var _bike: Node
var _cam_rig: Node
var _speed_label: Label
var _smash_label: Label
var _turbo_label: Label
var _view_btn: Button
var _smashed := 0
var _total := 3

func _init() -> void:
	add_to_group("hud")

func _ready() -> void:
	_bike = get_node_or_null("../KiepieBike")
	_cam_rig = get_node_or_null("../CameraRig")
	_speed_label = get_node_or_null("Speed") as Label
	_smash_label = get_node_or_null("Smashed") as Label
	_turbo_label = get_node_or_null("Turbo") as Label
	var restart_btn := get_node_or_null("RestartBtn") as Button
	_view_btn = get_node_or_null("ViewBtn") as Button
	if restart_btn:
		restart_btn.pressed.connect(_on_restart)
	if _view_btn:
		_view_btn.pressed.connect(_on_view)
	_update_smash_label()

func _process(_delta: float) -> void:
	if _bike == null:
		return
	if _speed_label and _bike.has_method("speed_kmh"):
		_speed_label.text = "%d km/h" % int(_bike.call("speed_kmh"))
	if _turbo_label:
		_turbo_label.visible = bool(_bike.get("turbo_active"))
	if _cam_rig and _view_btn:
		_view_btn.text = "View: FREE" if _cam_rig.get("mode") == "free" else "View: CHASE"

func register_smash() -> void:
	_smashed += 1
	_update_smash_label()

func _update_smash_label() -> void:
	if _smash_label:
		_smash_label.text = "Buildings smashed: %d / %d" % [_smashed, _total]

func _on_restart() -> void:
	if _bike and _bike.has_method("reset_bike"):
		_bike.call("reset_bike")

func _on_view() -> void:
	if _cam_rig and _cam_rig.has_method("toggle_view"):
		_cam_rig.toggle_view()
