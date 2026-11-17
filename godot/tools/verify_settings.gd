extends SceneTree
## Offline gate: settings defaults, persistence, quality presets and reset.
## SAFETY: wraps the whole run in a user://settings.cfg backup/restore so the
## developer's real settings are never destroyed by this "offline" gate.
## A hard crash mid-gate may still leave the backup behind; if so, restore it
## manually from user://settings.cfg.gate-backup.

const SAV := "user://settings.cfg"
const BAK := "user://settings.cfg.gate-backup"

var _fail := 0
var _had_cfg := false

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		printerr("FAIL ", label)
		_fail += 1


func _backup() -> void:
	_had_cfg = FileAccess.file_exists(SAV)
	if not _had_cfg:
		return
	# never leave a stale backup in place: it would shadow the current cfg
	if FileAccess.file_exists(BAK):
		DirAccess.remove_absolute(BAK)
	var err := DirAccess.copy_absolute(SAV, BAK)
	if err != OK:
		printerr("WARN backup of settings.cfg failed (err=%d) — continuing anyway" % err)
		_had_cfg = false


func _restore() -> void:
	if _had_cfg:
		if DirAccess.copy_absolute(BAK, SAV) == OK:
			DirAccess.remove_absolute(BAK)
		else:
			printerr("WARN could not restore settings.cfg from backup — leaving .gate-backup in place")
	elif FileAccess.file_exists(SAV):
		# the gate created it; remove it so defaults hold again
		DirAccess.remove_absolute(SAV)


func _initialize() -> void:
	_backup()
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var settings: Node = root.get_node("Settings")
	_check(str(settings.call("get_value", "gameplay", "display_name", "")) == "RIDER", "default display name")
	_check(float(settings.call("get_value", "video", "particles", 1.0)) == 1.0, "default particle multiplier")

	settings.call("set_value", "gameplay", "display_name", "TEST_RIDER")
	_check(str(settings.call("display_name")) == "TEST_RIDER", "set_value updates live value")
	var cfg := ConfigFile.new()
	_check(cfg.load("user://settings.cfg") == OK, "settings.cfg written")
	_check(str(cfg.get_value("gameplay", "display_name", "")) == "TEST_RIDER", "value persisted")

	settings.call("apply_quality", "low")
	_check(float(settings.call("get_value", "video", "particles", 0.0)) == 0.45, "low preset particle multiplier")
	_check(bool(settings.call("get_value", "video", "shadows", true)) == false, "low preset disables shadows")
	_check(str(settings.call("get_value", "video", "quality", "")) == "low", "quality key recorded")

	settings.call("reset_defaults")
	_check(str(settings.call("display_name")) == "RIDER", "reset defaults restores name")
	_check(float(settings.call("get_value", "video", "particles", 0.0)) == 1.0, "reset defaults restores particles")
	_check(int(settings.call("get_value", "meta", "version", 0)) == 2, "settings schema version is 2")
	_check(bool(settings.call("get_value", "video", "fullscreen", false)), "fullscreen defaults to true on launch")

	# v1 -> v2 config migration forces fullscreen ON for existing players once.
	var v1 := ConfigFile.new()
	v1.set_value("meta", "version", 1)
	v1.set_value("video", "fullscreen", false)
	v1.save(SAV)
	settings.call("_load")
	_check(bool(settings.call("get_value", "video", "fullscreen", false)),
			"v1 -> v2 migration enables fullscreen on launch")
	_check(int(settings.call("get_value", "meta", "version", 0)) == 2,
			"v1 -> v2 migration bumps schema version to 2")

	var sm_ps := load("res://scenes/SettingsMenu.tscn") as PackedScene
	_check(sm_ps != null, "SettingsMenu scene loads")
	if sm_ps != null:
		var sm := sm_ps.instantiate()
		var fs := sm.get_node_or_null("SafeMargin/VBox/Scroll/Rows/FullscreenRow/Fullscreen") as BaseButton
		_check(fs != null and fs.button_pressed, "SettingsMenu Fullscreen checkbox defaults to ON")
		sm.free()

	_restore()
	quit(1 if _fail > 0 else 0)
