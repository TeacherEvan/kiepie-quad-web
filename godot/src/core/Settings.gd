extends Node
## Persistent client settings for Kiepie Quad.
## Autoload name: Settings. Backed by user://settings.cfg with a versioned
## schema so future keys can be added without wiping a player's choices.

signal changed(section: String, key: String, value: Variant)

const PATH := "user://settings.cfg"
const VERSION := 2

const DEFAULTS := {
	"meta": {"version": VERSION},
	"video": {
		"quality": "auto",          # auto / low / medium / high
		"resolution_scale": 1.0,
		"shadows": true,
		"particles": 1.0,           # multiplier consumed by VfxFactory
		"glow": true,
		"fullscreen": true,
		"fov": 62.0,
		"show_fps": false,
	},
	"audio": {
		"master": 0.9,
		"sfx": 0.9,
		"engine": 0.7,
		"ui": 0.6,
		"muted": false,
	},
	"controls": {
		"fire_size": 1.0,           # scales the touch FIRE button
		"dodge_size": 1.0,          # scales the right drive pad (fire/dodge zones)
		"steer_sensitivity": 1.0,
		"touch_force": false,
	},
	"gameplay": {
		"display_name": "RIDER",
		"color": "#ff7a1a",
		"screen_shake": 1.0,
		"reduced_motion": false,
		"kill_feed": true,
	},
	"network": {
		"auto_join": true,
	},
}

const QUALITY_PRESETS := {
	"auto": {"resolution_scale": 1.0, "shadows": true, "particles": 1.0, "glow": true},
	"low": {"resolution_scale": 0.72, "shadows": false, "particles": 0.45, "glow": false},
	"medium": {"resolution_scale": 0.85, "shadows": true, "particles": 0.75, "glow": true},
	"high": {"resolution_scale": 1.0, "shadows": true, "particles": 1.0, "glow": true},
}

var data: Dictionary = {}
var _cfg := ConfigFile.new()
var _web_back_installed := false
var _back_poll_accum := 0.0
var _scale_pending := false


func _ready() -> void:
	_ensure_audio_buses()
	_load()
	apply_all()
	var tree := get_tree()
	if tree != null:
		# Let sub-screens handle mobile hardware/browser Back without closing the app.
		tree.set_quit_on_go_back(false)
		# The Glow & Shadows toggles wire dynamically to every scene that enters the tree.
		tree.node_added.connect(_on_node_added)
		tree.root.size_changed.connect(_sync_mobile_scale)
	_install_web_back_bridge()
	call_deferred("_apply_video_to_tree")
	call_deferred("_sync_mobile_scale")


func _is_mobile_auto() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if str(get_value("video", "quality", "auto")) != "auto":
		return false
	return OS.has_feature("web") and (DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"))


func effective_resolution_scale() -> float:
	var scale := float(get_value("video", "resolution_scale", 1.0))
	return minf(scale, 0.72) if _is_mobile_auto() else scale


func effective_shadows() -> bool:
	var on := bool(get_value("video", "shadows", true))
	return false if _is_mobile_auto() else on


func _install_web_back_bridge() -> void:
	if _web_back_installed or DisplayServer.get_name() == "headless":
		return
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return
	_web_back_installed = true
	JavaScriptBridge.eval("""
(() => {
  if (window.__kiepieBackInstalled) return;
  window.__kiepieBackInstalled = true;
  window.__kiepieBackArmed = false;
  window.__kiepieBackPending = false;
  window.__kiepieArmBack = () => {
    if (!window.__kiepieBackArmed && window.history && window.history.pushState) {
      try {
        window.history.pushState({ kiepieSubscreen: true }, '');
        window.__kiepieBackArmed = true;
      } catch (_) {}
    }
  };
  window.__kiepieDisarmBack = () => {
    window.__kiepieBackArmed = false;
  };
  window.addEventListener('popstate', () => {
    if (window.__kiepieVk && typeof window.__kiepieVk.isOpen === 'function' && window.__kiepieVk.isOpen()) {
      if (typeof window.__kiepieVk.close === 'function') window.__kiepieVk.close();
      window.__kiepieBackArmed = false;
      window.__kiepieArmBack();
      return;
    }
    if (window.__kiepieBackArmed) {
      window.__kiepieBackArmed = false;
      window.__kiepieBackPending = true;
    }
  });
})();
""", true)


func sync_back_handler() -> void:
	## Arms the browser history guard whenever a sub-screen (Lobby/Settings/TestRide/Arena)
	## is active so mobile edge-swipe / hardware Back returns to MainMenu instead of leaving the page.
	if not _web_back_installed or not Engine.has_singleton("JavaScriptBridge"):
		return
	var tree := get_tree()
	var has_handler := tree != null and not tree.get_nodes_in_group("back_handler").is_empty()
	if has_handler:
		JavaScriptBridge.eval("window.__kiepieArmBack && window.__kiepieArmBack();", true)
	else:
		JavaScriptBridge.eval("window.__kiepieDisarmBack && window.__kiepieDisarmBack();", true)


func _process(delta: float) -> void:
	if not _web_back_installed or not Engine.has_singleton("JavaScriptBridge"):
		return
	# Poll the browser back-button bridge at 4 Hz, not every frame — each JS
	# bridge crossing is synchronous and competes with the render loop on Web.
	_back_poll_accum += delta
	if _back_poll_accum < 0.25:
		return
	_back_poll_accum = 0.0
	var pending := bool(JavaScriptBridge.eval("!!window.__kiepieBackPending", true))
	if pending:
		JavaScriptBridge.eval("window.__kiepieBackPending = false;", true)
		_trigger_back_handler()


func _notification(what: int) -> void:
	if what == Node.NOTIFICATION_WM_GO_BACK_REQUEST:
		_trigger_back_handler()


func _trigger_back_handler() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var handlers := tree.get_nodes_in_group("back_handler")
	for i in range(handlers.size() - 1, -1, -1):
		var h := handlers[i]
		if is_instance_valid(h) and h.has_method("_on_back_requested"):
			h.call("_on_back_requested")
			return


func _sync_mobile_scale() -> void:
	# Coalesce drag-resize storms into one sync per 100 ms window. On Web this
	# path makes a synchronous JS-bridge call (devicePixelRatio), so it must not
	# run per resize event.
	if _scale_pending:
		return
	_scale_pending = true
	var timer := get_tree().create_timer(0.1)
	timer.timeout.connect(func() -> void:
		_scale_pending = false
		_sync_mobile_scale_now())


func _sync_mobile_scale_now() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var win := get_tree().root
	if win == null:
		return
	var px := Vector2(DisplayServer.window_get_size())
	if px.x <= 0.0 or px.y <= 0.0:
		return
	var dpr := 1.0
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var raw := float(JavaScriptBridge.eval("window.devicePixelRatio || 1", true))
		if raw > 0.0:
			dpr = raw
	elif OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		dpr = maxf(1.0, DisplayServer.screen_get_scale())
	var css := px / dpr
	if css.x >= 1000.0 and css.y >= 540.0:
		win.content_scale_factor = 1.0
		return
	var stretch := minf(px.x / 1280.0, px.y / 720.0)
	if stretch > 0.0:
		win.content_scale_factor = clampf(dpr / stretch, 1.0, 4.5)


func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment:
		_apply_glow(node as WorldEnvironment)
	elif node is DirectionalLight3D:
		(node as DirectionalLight3D).shadow_enabled = effective_shadows()
	elif node.is_in_group("back_handler"):
		call_deferred("sync_back_handler")


func _apply_video_to_tree() -> void:
	_apply_glow_to_tree()
	_apply_shadows_to_tree()
	_apply_resolution_scale()


func _apply_shadows_to_tree() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var on := effective_shadows()
	for node in tree.root.find_children("*", "DirectionalLight3D", true, false):
		(node as DirectionalLight3D).shadow_enabled = on


func _apply_resolution_scale() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_scale = effective_resolution_scale()


func _apply_glow_to_tree() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.root.find_children("*", "WorldEnvironment", true, false):
		_apply_glow(node as WorldEnvironment)


func _apply_glow(world_env: WorldEnvironment) -> void:
	## Screen-space glow (bloom) for emissive VFX. gl_compatibility-safe:
	## additive blend on the HDR buffer, modest intensity, threshold above
	## the sky so only hot cores bloom.
	var env := world_env.environment
	if env == null:
		return
	var enabled := bool(get_value("video", "glow", true))
	env.glow_enabled = enabled
	env.glow_intensity = 0.62
	env.glow_strength = 1.12
	env.glow_bloom = 0.14
	env.glow_hdr_threshold = 0.82
	env.glow_hdr_scale = 1.6
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE


func _ensure_audio_buses() -> void:
	## Godot ships only "Master"; create the buses the audio sliders control.
	var wanted := ["Master", "SFX", "Engine", "UI"]
	for i in range(1, wanted.size()):
		var found := false
		for b in range(AudioServer.bus_count):
			if AudioServer.get_bus_name(b) == wanted[i]:
				found = true
				break
		if not found:
			AudioServer.add_bus()
			AudioServer.set_bus_name(i, wanted[i])
			AudioServer.set_bus_send(i, "Master")


func _load() -> void:
	data = {}
	for section in DEFAULTS.keys():
		data[section] = (DEFAULTS[section] as Dictionary).duplicate(true)
	if _cfg.load(PATH) == OK:
		for section in _cfg.get_sections():
			if not data.has(section):
				data[section] = {}
			for key in _cfg.get_section_keys(section):
				data[section][key] = _cfg.get_value(section, key)
		# Migrate v1 configs to enable fullscreen-on-launch by default.
		if int((data.get("meta", {}) as Dictionary).get("version", 1)) < 2:
			(data["video"] as Dictionary)["fullscreen"] = true
	else:
		push_warning("Settings: no readable settings.cfg at %s — using defaults" % PATH)
	data["meta"]["version"] = VERSION
	_save()


func _save() -> void:
	for section in data.keys():
		for key in (data[section] as Dictionary).keys():
			_cfg.set_value(section, key, data[section][key])
	var err := _cfg.save(PATH)
	if err != OK:
		# Silent settings loss on full disk / Web quota rejection used to be invisible.
		push_warning("Settings: could not write %s (err=%d) — changes are session-only" % [PATH, err])


func get_value(section: String, key: String, fallback: Variant = null) -> Variant:
	if not data.has(section):
		return fallback
	return (data[section] as Dictionary).get(key, fallback)


func set_value(section: String, key: String, value: Variant) -> void:
	if not data.has(section):
		data[section] = {}
	var old: Variant = (data[section] as Dictionary).get(key, null)
	if old == value:
		return
	data[section][key] = value
	_save()
	_apply(section, key, value)
	changed.emit(section, key, value)


func apply_quality(preset: String) -> void:
	if not QUALITY_PRESETS.has(preset):
		return
	set_value("video", "quality", preset)
	var q: Dictionary = QUALITY_PRESETS[preset]
	for key in q.keys():
		set_value("video", key, q[key])


func reset_defaults() -> void:
	data = {}
	for section in DEFAULTS.keys():
		data[section] = (DEFAULTS[section] as Dictionary).duplicate(true)
	_cfg = ConfigFile.new()
	_save()
	apply_all()
	changed.emit("*", "*", null)


func apply_all() -> void:
	_apply("audio", "master", get_value("audio", "master"))
	_apply("audio", "sfx", get_value("audio", "sfx"))
	_apply("audio", "engine", get_value("audio", "engine"))
	_apply("audio", "ui", get_value("audio", "ui"))
	_apply("audio", "muted", get_value("audio", "muted"))
	_apply("video", "fullscreen", get_value("video", "fullscreen"))
	_apply("video", "resolution_scale", get_value("video", "resolution_scale"))
	_apply("video", "shadows", get_value("video", "shadows"))
	_apply("video", "glow", get_value("video", "glow"))
	_apply("video", "show_fps", get_value("video", "show_fps"))


func _apply(section: String, key: String, value: Variant) -> void:
	match section:
		"audio":
			var bus_index: int = {
				"master": 0, "sfx": 1, "engine": 2, "ui": 3,
			}.get(key, -1)
			if bus_index != -1 and bus_index < AudioServer.bus_count:
				var linear := maxf(0.0001, float(value))
				AudioServer.set_bus_volume_db(bus_index, linear_to_db(linear))
			elif key == "muted":
				AudioServer.set_bus_mute(0, bool(value))
		"video":
			if key == "fullscreen":
				if DisplayServer.get_name() == "headless" or OS.get_environment("KIEPIE_MOCK_BACKEND") == "1":
					return
				var want_fs := bool(value)
				if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
					JavaScriptBridge.eval("window.__kiepieSetFullscreen && window.__kiepieSetFullscreen(%s);" % ("true" if want_fs else "false"), true)
				elif DisplayServer.get_name() != "web":
					var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if want_fs else DisplayServer.WINDOW_MODE_WINDOWED
					DisplayServer.window_set_mode(mode)
			elif key == "quality":
				_apply_video_to_tree()
			elif key == "resolution_scale":
				_apply_resolution_scale()
			elif key == "shadows":
				_apply_shadows_to_tree()
			elif key == "glow":
				_apply_glow_to_tree()
			# show_fps is consumed by MatchHud's optional FPS overlay
		_:
			pass


func display_name() -> String:
	var n := str(get_value("gameplay", "display_name", "RIDER")).strip_edges()
	return n.substr(0, 16) if n.length() > 16 else (n if n != "" else "RIDER")


func player_color() -> String:
	return str(get_value("gameplay", "color", "#ff7a1a"))


func quality_multiplier() -> float:
	var mult := float(get_value("video", "particles", 1.0))
	return minf(mult, 0.55) if _is_mobile_auto() else mult


func reduced_motion() -> bool:
	return bool(get_value("gameplay", "reduced_motion", false))


func shake_multiplier() -> float:
	return 0.0 if reduced_motion() else float(get_value("gameplay", "screen_shake", 1.0))
