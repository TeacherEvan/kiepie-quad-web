extends RefCounted
class_name TouchOverlayKit
## Shared mobile-touch overlay builder for the Arena and TestRide scenes.
## Layout is identical in both scenes; accents and the gas/toggle styling
## differ slightly (arena = wide combat layout, testride = compact practice
## layout). Both variants are locked by verify_touch.gd /
## verify_touch_multitouch.gd.
##
## Callers: tools/build_arena.gd, tools/build_testride.gd — after editing a
## preset here, rebuild both scenes (run_gates.sh does) and commit .tscn + .gd
## together.

const UI := preload("res://src/ui/UiTheme.gd")

## Each preset carries the full UI.style_button() argument list per button so
## callers get byte-identical results to the duplicated code this replaced:
##   style_font / style_min_h -> UI.style_button(btn, accent, style_font, style_min_h)
##   font_override            -> btn.add_theme_font_size_override("font_size", font_override)
const PRESETS := {
	"arena": {
		# Wide combat overlay: purple dodges, custom orange gas, muted toggle.
		"dodge_accent": Color(0.55, 0.42, 0.78, 0.85),
		"dodge_style_font": 15,
		"dodge_style_min_h": 44.0,
		"gas_accent": Color(1.0, 0.46, 0.10, 0.9),
		"gas_style_font": 15,
		"gas_style_min_h": 44.0,
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
		# Compact practice overlay: INFO dodges, ACCENT gas, TEXT toggle.
		"dodge_accent": UI.INFO,
		"dodge_style_font": 15,
		"dodge_style_min_h": 44.0,
		"gas_accent": UI.ACCENT,
		"gas_style_font": 16,   # UI.style_button default
		"gas_style_min_h": 52.0, # UI.style_button default
		"toggle_offset_left": -146.0,
		"toggle_offset_right": -14.0,
		"toggle_offset_top": 166.0,
		"toggle_offset_bottom": 210.0,
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
	touch.layer = 2  # above the HUD; clusters don't overlap it visually
	touch.set_script(load("res://src/TouchControls.gd"))

	# --- steering is an analog pad built at runtime by TouchControls.gd
	# (fills the space the old BtnLeft/BtnRight lived in)

	# --- dodge leaps: compact "L" & "R" above the steering cluster
	for spec in [["BtnDodgeLeft", "L", 32.0, 84.0], ["BtnDodgeRight", "R", 108.0, 160.0]]:
		var dodge := Button.new()
		dodge.name = spec[0]
		dodge.text = spec[1]
		dodge.anchor_left = 0.0
		dodge.anchor_right = 0.0
		dodge.anchor_top = 1.0
		dodge.anchor_bottom = 1.0
		dodge.offset_left = spec[2]
		dodge.offset_right = spec[3]
		dodge.offset_top = -230.0
		dodge.offset_bottom = -184.0
		dodge.focus_mode = Control.FOCUS_NONE
		UI.style_button(dodge, cfg["dodge_accent"], int(cfg["dodge_style_font"]), float(cfg["dodge_style_min_h"]))
		dodge.add_theme_font_size_override("font_size", 15)
		dodge.pivot_offset = Vector2(26.0, 23.0)
		touch.add_child(dodge)

	# --- right thumb: compact GAS pedal (auto-fire handles cannons; analog push handles turbo)
	var gas := Button.new()
	gas.name = "BtnGas"
	gas.text = "GAS"
	gas.anchor_left = 1.0
	gas.anchor_right = 1.0
	gas.anchor_top = 1.0
	gas.anchor_bottom = 1.0
	gas.offset_left = -92.0
	gas.offset_right = -14.0
	gas.offset_top = -96.0
	gas.offset_bottom = -18.0
	gas.focus_mode = Control.FOCUS_NONE
	UI.style_button(gas, cfg["gas_accent"], int(cfg["gas_style_font"]), float(cfg["gas_style_min_h"]))
	gas.add_theme_font_size_override("font_size", 18)
	touch.add_child(gas)

	# --- manual overlay toggle (auto-detect fallback)
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
