extends RefCounted
class_name TouchOverlayKit
## Shared mobile-touch overlay builder for the Arena and TestRide scenes.
## The two analog pads (AnalogSteer left, AnalogDrive right) are created at
## runtime by TouchControls.gd; only the always-on TOUCH toggle is authored
## here. Both variants are locked by verify_touch.gd / verify_touch_multitouch.gd.
##
## Callers: tools/build_arena.gd, tools/build_testride.gd — after editing a
## preset here, rebuild both scenes (run_gates.sh does) and commit .tscn + .gd
## together.

const UI := preload("res://src/ui/UiTheme.gd")

## Each preset carries the full UI.style_button() argument list for the toggle:
##   style_font / style_min_h -> UI.style_button(btn, accent, style_font, style_min_h)
##   font_override            -> btn.add_theme_font_size_override("font_size", font_override)
const PRESETS := {
	"arena": {
		"toggle_offset_left": -108.0,
		"toggle_offset_right": -10.0,
		"toggle_offset_top": 12.0,
		"toggle_offset_bottom": 56.0,
		"toggle_accent": Color(0.42, 0.50, 0.62, 0.55),
		"toggle_style_font": 15,
		"toggle_style_min_h": 44.0,
		"toggle_font_override": 11,
	},
	"testride": {
		"toggle_offset_left": -150.0,
		"toggle_offset_right": -14.0,
		"toggle_offset_top": 184.0,
		"toggle_offset_bottom": 236.0,
		"toggle_accent": UI.TEXT,
		"toggle_style_font": 16,   # UI.style_button default
		"toggle_style_min_h": 52.0, # UI.style_button default
		"toggle_font_override": 13,
	},
}


static func build(root: Node, preset: String) -> CanvasLayer:
	var cfg: Dictionary = PRESETS.get(preset, PRESETS["arena"])
	var touch := CanvasLayer.new()
	touch.name = "TouchHUD"
	touch.layer = 2  # above the HUD; pads don't overlap it visually
	touch.set_script(load("res://src/TouchControls.gd"))

	# --- manual overlay toggle (auto-detect fallback); the pads are runtime nodes
	var toggle := Button.new()
	toggle.name = "BtnTouchToggle"
	toggle.text = "TOUCH: AUTO"
	toggle.anchor_left = 1.0
	toggle.anchor_right = 1.0
	toggle.anchor_top = 0.0
	toggle.anchor_bottom = 0.0
	toggle.offset_left = float(cfg["toggle_offset_left"])
	toggle.offset_right = float(cfg["toggle_offset_right"])
	toggle.offset_top = float(cfg["toggle_offset_top"])
	toggle.offset_bottom = float(cfg["toggle_offset_bottom"])
	toggle.focus_mode = Control.FOCUS_NONE
	UI.style_button(toggle, cfg["toggle_accent"], int(cfg["toggle_style_font"]), float(cfg["toggle_style_min_h"]))
	toggle.add_theme_font_size_override("font_size", int(cfg["toggle_font_override"]))
	touch.add_child(toggle)

	root.add_child(touch)
	return touch
