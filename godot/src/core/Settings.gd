extends Node
## Persistent client settings for Kiepie Quad.
## Autoload name: Settings. Backed by user://settings.cfg with a versioned
## schema so future keys can be added without wiping a player's choices.

signal changed(section: String, key: String, value: Variant)

const PATH := "user://settings.cfg"
const VERSION := 1

const DEFAULTS := {
	"meta": {"version": VERSION},
	"video": {
		"quality": "auto",          # auto / low / medium / high
		"resolution_scale": 1.0,
		"shadows": true,
		"particles": 1.0,           # multiplier consumed by VfxFactory
		"glow": true,
		"fullscreen": false,
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
	"low": {"resolution_scale": 0.72, "shadows": false, "particles": 0.45, "glow": false},
	"medium": {"resolution_scale": 0.85, "shadows": true, "particles": 0.75, "glow": true},
	"high": {"resolution_scale": 1.0, "shadows": true, "particles": 1.0, "glow": true},
}

var data: Dictionary = {}
var _cfg := ConfigFile.new()


func _ready() -> void:
	_ensure_audio_buses()
	_load()
	apply_all()
	# The Glow video toggle used to be dead UI; wire it to every
	# WorldEnvironment that enters the tree (menu, TestRide, arena).
	get_tree().node_added.connect(_on_world_environment_added)
	call_deferred("_apply_glow_to_tree")


func _on_world_environment_added(node: Node) -> void:
	if node is WorldEnvironment:
		_apply_glow(node as WorldEnvironment)


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
	# schema migration hook: future versions can transform values here
	data["meta"]["version"] = VERSION
	_save()


func _save() -> void:
	for section in data.keys():
		for key in (data[section] as Dictionary).keys():
			_cfg.set_value(section, key, data[section][key])
	_cfg.save(PATH)


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
				var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(value) else DisplayServer.WINDOW_MODE_WINDOWED
				if DisplayServer.get_name() != "web":
					DisplayServer.window_set_mode(mode)
			elif key == "resolution_scale":
				var vp := get_viewport()
				if vp != null:
					vp.scaling_3d_scale = float(value)
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
	return float(get_value("video", "particles", 1.0))


func reduced_motion() -> bool:
	return bool(get_value("gameplay", "reduced_motion", false))


func shake_multiplier() -> float:
	return 0.0 if reduced_motion() else float(get_value("gameplay", "screen_shake", 1.0))
