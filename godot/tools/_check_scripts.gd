extends SceneTree
## Compile-check every gameplay script inside a real project run (autoload-aware).
## Scans res://src recursively, but still requires the known-critical scripts
## to exist and refuses to pass if any directory could not be enumerated.

const REQUIRED := [
	"res://src/core/Settings.gd",
	"res://src/net/MockBackend.gd",
	"res://src/net/SupabaseClient.gd",
	"res://src/net/MatchState.gd",
	"res://src/net/LobbyService.gd",
	"res://src/net/TaloBackend.gd",
	"res://src/net/TaloProtocol.gd",
	"res://src/game/CombatAoe.gd",
	"res://src/game/VfxSprites.gd",
	"res://src/game/VfxCore.gd",
	"res://src/game/VfxHeavy.gd",
	"res://src/game/VfxFactory.gd",
	"res://src/game/Projectile.gd",
	"res://src/game/SideCannons.gd",
	"res://src/game/CombatController.gd",
	"res://src/game/NetworkedBike.gd",
	"res://src/game/ArenaNet.gd",
	"res://src/ui/UiTheme.gd",
]

var _enum_failed := false

func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		printerr("FAILED open ", dir_path)
		_enum_failed = true
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if entry != "." and entry != "..":
				_collect(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()

func _initialize() -> void:
	var paths: Array[String] = []
	_collect("res://src", paths)
	paths.sort()
	if _enum_failed:
		printerr("compile check: directory enumeration failed")
		quit(1)
		return
	if paths.is_empty():
		printerr("compile check: no scripts found under res://src")
		quit(1)
		return
	var failed := 0
	for p in REQUIRED:
		if not paths.has(p):
			printerr("FAILED missing ", p)
			failed += 1
	for p in paths:
		var s = load(p)
		if s == null:
			printerr("FAILED ", p)
			failed += 1
		else:
			print("OK ", p)
	print("compile check: %d/%d loaded, %d required" % [paths.size() - failed, paths.size(), REQUIRED.size()])
	quit(1 if failed > 0 else 0)
