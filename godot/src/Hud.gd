extends CanvasLayer
## HUD for the Kiepie Bike test track: speed, smash counter, turbo flash,
## and the on-screen Restart / View buttons (keyboard R / C works too).

const SCENE_MAIN := "res://scenes/MainMenu.tscn"
const UI := preload("res://src/ui/UiTheme.gd")

var _bike: Node
var _cam_rig: Node
var _combat: Node
var _speed_label: Label
var _smash_label: Label
var _weapon_label: Label
var _reload_bar: ProgressBar
var _reload_fill: StyleBoxFlat
var _hitmarker: Label
var _hit_tween: Tween
var _hit_gen := 0
var _help_label: Label
var _restart_btn: Button
var _view_btn: Button
var _menu_btn: Button
var _smashed := 0
var _total := 3
var _last_speed := -1
var _last_view := ""
var _relayout_pending := false
@export var smash_total := 3   ## set by tools/build_testride.gd (serialized into the scene)


func _init() -> void:
	add_to_group("hud")
	add_to_group("back_handler")

func _ready() -> void:
	_bike = get_node_or_null("../KiepieBike")
	_cam_rig = get_node_or_null("../CameraRig")
	_combat = get_node_or_null("../KiepieBike/CombatController")
	_help_label = get_node_or_null("Help") as Label
	_speed_label = get_node_or_null("Speed") as Label
	_smash_label = get_node_or_null("Smashed") as Label
	_weapon_label = get_node_or_null("WeaponLabel") as Label
	_reload_bar = get_node_or_null("ReloadBar") as ProgressBar
	if _reload_bar != null:
		_reload_fill = UI.bar_fill(UI.OK)
		_reload_bar.add_theme_stylebox_override("fill", _reload_fill)
	_hitmarker = get_node_or_null("HitMarker") as Label
	_restart_btn = get_node_or_null("RestartBtn") as Button
	_view_btn = get_node_or_null("ViewBtn") as Button
	_menu_btn = get_node_or_null("MenuBtn") as Button
	if _restart_btn:
		_restart_btn.pressed.connect(_on_restart)
	if _view_btn:
		_view_btn.pressed.connect(_on_view)
	if _menu_btn:
		_menu_btn.pressed.connect(_on_menu)
	Settings.call_deferred("sync_back_handler")
	if _combat != null:
		if _combat.has_signal("hit_confirmed"):
			_combat.hit_confirmed.connect(_on_hit_confirmed)
		var cannons: Node = _combat.get("cannons") if "cannons" in _combat else _combat.get_node_or_null("SideCannons")
		if cannons != null:
			if cannons.has_signal("reload_changed"):
				cannons.connect("reload_changed", _on_reload_changed)
			if cannons.has_method("weapon_display_name"):
				_on_reload_changed(1.0, 0.0, true, str(cannons.call("weapon_display_name")))
	_total = maxi(1, smash_total)
	_update_smash_label()
	if get_viewport() != null:
		get_viewport().size_changed.connect(_on_viewport_resized)
	_relayout()


func _exit_tree() -> void:
	if get_viewport() != null and get_viewport().size_changed.is_connected(_on_viewport_resized):
		get_viewport().size_changed.disconnect(_on_viewport_resized)


func _process(_delta: float) -> void:
	if _bike == null:
		return
	if _speed_label and _bike.has_method("speed_kmh"):
		var kmh := int(_bike.call("speed_kmh"))
		if kmh != _last_speed:
			_last_speed = kmh
			_speed_label.text = "%d km/h" % kmh
	if _cam_rig and _view_btn:
		var mode := str(_cam_rig.get("mode"))
		if mode != _last_view:
			_last_view = mode
			_view_btn.text = "View: FREE" if mode == "free" else "View: CHASE"

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
	if _combat and _combat.has_method("reset_state"):
		_combat.call("reset_state")

func _on_view() -> void:
	if _cam_rig and _cam_rig.has_method("toggle_view"):
		_cam_rig.toggle_view()

func _on_menu() -> void:
	get_tree().change_scene_to_file(SCENE_MAIN)

func _on_back_requested() -> void:
	_on_menu()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			_on_menu()
		elif event.is_action_pressed("reset_bike"):
			_on_restart()


func _on_reload_changed(progress: float, remaining: float, is_ready: bool, label: String) -> void:
	if _reload_bar != null:
		_reload_bar.value = clampf(progress * 100.0, 0.0, 100.0)
	if _reload_fill != null:
		_reload_fill.bg_color = UI.OK if is_ready else UI.GOLD.lerp(UI.ACCENT, 1.0 - clampf(progress, 0.0, 1.0))
	if _weapon_label != null:
		if is_ready:
			_weapon_label.text = "%s · READY" % label
		else:
			_weapon_label.text = "%s · RELOADING %.1fs" % [label, remaining]


func _on_hit_confirmed() -> void:
	if _hitmarker == null:
		return
	_hit_gen += 1
	var gen := _hit_gen
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
	_hit_tween = null
	_hitmarker.modulate.a = 1.0
	if Settings.reduced_motion():
		await get_tree().create_timer(0.12).timeout
		if not is_inside_tree() or gen != _hit_gen:
			return
		if is_instance_valid(_hitmarker):
			_hitmarker.modulate.a = 0.0
		return
	_hit_tween = create_tween()
	_hit_tween.tween_property(_hitmarker, "modulate:a", 0.0, 0.14)


func _on_viewport_resized() -> void:
	# Coalesce drag-resize storms into one relayout per 100 ms window.
	if _relayout_pending:
		return
	_relayout_pending = true
	var w_self: WeakRef = weakref(self)
	var timer := get_tree().create_timer(0.1)
	timer.timeout.connect(func() -> void:
		var me := w_self.get_ref() as Node
		if me != null and is_instance_valid(me) and me.is_inside_tree():
			me.set("_relayout_pending", false)
			me.call("_relayout"))


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
	if _weapon_label != null:
		_weapon_label.position = Vector2(14.0, top_y + 104.0)
	if _reload_bar != null:
		_reload_bar.position = Vector2(14.0, top_y + 124.0)
		var rbw := 132.0 if narrow else 184.0
		_reload_bar.custom_minimum_size = Vector2(rbw, 10.0)
		_reload_bar.size = Vector2(rbw, 10.0)
	if _restart_btn != null:
		_restart_btn.offset_left = -132.0 if narrow else -150.0
		_restart_btn.offset_right = -14.0
	if _view_btn != null:
		_view_btn.offset_left = -132.0 if narrow else -150.0
		_view_btn.offset_right = -14.0
	if _menu_btn != null:
		_menu_btn.offset_left = -132.0 if narrow else -150.0
		_menu_btn.offset_right = -14.0
