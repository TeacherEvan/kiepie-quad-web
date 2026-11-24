extends RefCounted
## Shared user://settings.cfg backup/restore + clean-default reset helper for gates.
## Prevents gates from permanently corrupting a developer's local settings.cfg
## or failing when a developer has non-default vehicle/particles/reduced_motion.

const CFG_PATH := "user://settings.cfg"


static func backup(root: Node) -> Dictionary:
	var existed := FileAccess.file_exists(CFG_PATH)
	var bytes := FileAccess.get_file_as_bytes(CFG_PATH) if existed else PackedByteArray()
	var settings := root.get_node_or_null("Settings") if root != null else null
	if settings != null:
		var cfg: Dictionary = (settings.get("data") as Dictionary).duplicate(true)
		var gp: Dictionary = (cfg.get("gameplay", {}) as Dictionary).duplicate(true)
		gp["vehicle"] = "auto"
		gp["reduced_motion"] = false
		cfg["gameplay"] = gp
		var vid: Dictionary = (cfg.get("video", {}) as Dictionary).duplicate(true)
		vid["particles"] = 1.0
		cfg["video"] = vid
		var ctrl: Dictionary = (cfg.get("controls", {}) as Dictionary).duplicate(true)
		ctrl["touch_force"] = false
		cfg["controls"] = ctrl
		settings.set("data", cfg)
	return {"existed": existed, "bytes": bytes}


static func restore(root: Node, snap: Dictionary) -> void:
	if bool(snap.get("existed", false)):
		var f := FileAccess.open(CFG_PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(snap.get("bytes", PackedByteArray()) as PackedByteArray)
			f.close()
	else:
		if FileAccess.file_exists(CFG_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_PATH))
	var settings := root.get_node_or_null("Settings") if root != null else null
	if settings != null and settings.has_method("load_from_disk"):
		settings.call("load_from_disk")
