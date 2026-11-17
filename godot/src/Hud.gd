extends CanvasLayer
## HUD for the Kiepie Bike test track: speed, smash counter, turbo flash,
## and the on-screen Restart / View buttons (keyboard R / C works too).

const UI := preload("res://src/ui/UiTheme.gd")

var _bike: Node
var _cam_rig: Node
var _combat: Node
var _speed_label: Label
var _smash_label: Label
var _turbo_label: Label
var _heat_label: Label
var _heat_bar: ProgressBar
var _hitmarker: Label
var _hit_tween: Tween
var _heat_fill_normal: StyleBoxFlat
var _heat_fill_warn: StyleBoxFlat
var _heat_fill_locked: StyleBoxFlat
var _help_label: Label
var _restart_btn: Button
var _view_btn: Button
var _smashed := 0
var _total := 3
@export var smash_total := 3   ## set by tools/build_testride.gd (serialized into the scene)


func _init() -> void:
	add_to_group("hud")

func _ready() -> void:
	_bike = get_node_or_null("../KiepieBike")
	_cam_rig = get_node_or_null("../CameraRig")
	_combat = get_node_or_null("../KiepieBike/CombatController")
	_help_label = get_node_or_null("Help") as Label
	_speed_label = get_node_or_null("Speed") as Label
	_smash_label = get_node_or_null("Smashed") as Label
	_turbo_label = get_node_or_null("Turbo") as Label
	_heat_label = get_node_or_null("HeatLabel") as Label
	_heat_bar = get_node_or_null("HeatBar") as ProgressBar
	_hitmarker = get_node_or_null("HitMarker") as Label
	_restart_btn = get_node_or_null("RestartBtn") as Button
	_view_btn = get_node_or_null("ViewBtn") as Button
	if _restart_btn:
		_restart_btn.pressed.connect(_on_restart)
	if _view_btn:
		_view_btn.pressed.connect(_on_view)
	if _heat_bar:
		_heat_fill_normal = UI.bar_fill(UI.ACCENT)
		_heat_fill_warn = UI.bar_fill(UI.WARN)
		_heat_fill_locked = UI.bar_fill(UI.DANGER)
		_heat_bar.add_theme_stylebox_override("fill", _heat_fill_normal)
	if _combat != null:
		if _combat.has_signal("heat_changed"):
			_combat.heat_changed.connect(_on_heat_changed)
		if _combat.has_signal("hit_confirmed"):
			_combat.hit_confirmed.connect(_on_hit_confirmed)
	_total = maxi(1, smash_total)
	_update_smash_label()
	if get_viewport() != null:
		get_viewport().size_changed.connect(_relayout)
	_relayout()


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
		var narrow := get_viewport() != null and get_viewport().get_visible_rect().size.x < 700.0
		var prefix := "Smashed" if narrow else "Buildings smashed"
		_smash_label.text = "%s: %d / %d" % [prefix, _smashed, _total]

func _on_restart() -> void:
	if _bike and _bike.has_method("reset_bike"):
		_bike.call("reset_bike")

func _on_view() -> void:
	if _cam_rig and _cam_rig.has_method("toggle_view"):
		_cam_rig.toggle_view()


func _on_heat_changed(value: float, locked: bool) -> void:
	if _heat_bar != null:
		_heat_bar.value = clampf(value * 100.0, 0.0, 100.0)
		if locked:
			_heat_bar.add_theme_stylebox_override("fill", _heat_fill_locked)
		elif value >= 0.72:
			_heat_bar.add_theme_stylebox_override("fill", _heat_fill_warn)
		else:
			_heat_bar.add_theme_stylebox_override("fill", _heat_fill_normal)
	if _heat_label != null:
		_heat_label.text = "OVERHEAT" if locked else "CANNONS"
		_heat_label.add_theme_color_override("font_color", UI.DANGER if locked else UI.TEXT)


func _on_hit_confirmed() -> void:
	if _hitmarker == null:
		return
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
	_hitmarker.modulate.a = 1.0
	if Settings.reduced_motion():
		await get_tree().create_timer(0.12).timeout
		if is_instance_valid(_hitmarker):
			_hitmarker.modulate.a = 0.0
		return
	_hit_tween = create_tween()
	_hit_tween.tween_property(_hitmarker, "modulate:a", 0.0, 0.14)


func _relayout() -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1280.0, 720.0)
	var narrow := vp.x < 700.0
	var compact_h := vp.y < 500.0
	if _help_label != null:
		_help_label.visible = not narrow and not compact_h
	var top_y := 12.0 if (narrow or compact_h) else 132.0
	if _speed_label != null:
		_speed_label.position = Vector2(14.0, top_y)
		_speed_label.custom_minimum_size = Vector2(126.0 if narrow else 150.0, 0.0)
	if _smash_label != null:
		var smash_w := 132.0 if narrow else 250.0
		_smash_label.position = Vector2(14.0, top_y + 62.0)
		_smash_label.custom_minimum_size = Vector2(smash_w, 0.0)
		_smash_label.offset_right = 14.0 + smash_w
		_smash_label.size.x = smash_w
		_smash_label.add_theme_font_size_override("font_size", 13 if narrow else 16)
		_update_smash_label()
	if _heat_label != null:
		_heat_label.position = Vector2(14.0, top_y + 108.0)
	if _heat_bar != null:
		var bar_w := 160.0 if narrow else 200.0
		_heat_bar.position = Vector2(14.0, top_y + 130.0)
		_heat_bar.offset_right = 14.0 + bar_w
		_heat_bar.offset_bottom = top_y + 146.0
	if _turbo_label != null:
		if narrow:
			_turbo_label.offset_top = 166.0
			_turbo_label.offset_bottom = 212.0
		else:
			_turbo_label.offset_top = 12.0 if compact_h else 20.0
			_turbo_label.offset_bottom = _turbo_label.offset_top + (48.0 if compact_h else 64.0)
	if _restart_btn != null:
		_restart_btn.offset_left = -132.0 if narrow else -150.0
		_restart_btn.offset_right = -14.0
	if _view_btn != null:
		_view_btn.offset_left = -132.0 if narrow else -150.0
		_view_btn.offset_right = -14.0
