extends Control
## Right-thumb drive pad drawn by the touch overlay (see TouchControls.gd).
## Resting a finger on it holds GAS; pushing UP holds FIRE (cannons fire on
## their own cooldown); pushing LEFT/RIGHT triggers the dodge cartwheel.
## Pure view: all input arbitration lives in TouchControls.gd.

var value := 0.0             ## -1 .. 1, horizontal dodge deflection (display only)
var fire_value := 0.0        ## 0 .. 1, upward deflection (display only)
var fire_active := false     ## true while the UP threshold is held
var swap_value := 0.0        ## 0 .. 1, downward weapon-switch deflection (display only)
var swap_active := false     ## true while the DOWN weapon-switch threshold is held
var dodge_left_active := false
var dodge_right_active := false
var gas_active := false      ## true while a finger rests on the pad

var _display_value := 0.0
var _display_fire := 0.0
var _display_swap := 0.0
var _drawn_fire := false
var _drawn_swap := false
var _drawn_left := false
var _drawn_right := false

const DEADZONE := 0.15
const TRACK := Color(0.08, 0.10, 0.14, 0.86)
const TRACK_INNER := Color(0.14, 0.18, 0.25, 0.90)
const TRACK_EDGE := Color(0.55, 0.65, 0.78, 0.62)
const TRACK_SPECULAR := Color(1.0, 1.0, 1.0, 0.12)
const CENTER := Color(0.92, 0.94, 0.98, 0.42)
const DEADZONE_MARK := Color(0.75, 0.82, 0.92, 0.35)
const GAS_TINT := Color(0.30, 0.86, 0.62, 0.14)
const FIRE_GLOW := Color(1.0, 0.45, 0.12, 0.42)
const FIRE_GUIDE := Color(1.0, 0.66, 0.26, 0.80)
const FIRE_LIT := Color(1.0, 0.82, 0.30, 1.0)
const DODGE_GLOW := Color(0.26, 0.80, 1.0, 0.34)
const DODGE_GUIDE := Color(0.52, 0.86, 1.0, 0.78)
const DODGE_LIT := Color(0.62, 0.92, 1.0, 1.0)
const SWAP_GLOW := Color(0.75, 0.32, 1.0, 0.40)
const SWAP_GUIDE := Color(0.84, 0.58, 1.0, 0.82)
const SWAP_LIT := Color(0.95, 0.76, 1.0, 1.0)
const KNOB := Color(1.0, 0.62, 0.16, 0.96)
const KNOB_FIRE := Color(1.0, 0.82, 0.24, 0.98)
const KNOB_DODGE := Color(0.42, 0.82, 1.0, 0.98)
const KNOB_SWAP := Color(0.84, 0.48, 1.0, 0.98)
const KNOB_RIM := Color(1.0, 0.86, 0.52, 0.75)
const KNOB_EDGE := Color(0.35, 0.18, 0.02, 0.92)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # TouchCapture hit-tests this rect
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(44, 44)


func _process(delta: float) -> void:
	var prev_x := _display_value
	var prev_f := _display_fire
	var prev_s := _display_swap
	var prev_fire := _drawn_fire
	var prev_swap := _drawn_swap
	var prev_left := _drawn_left
	var prev_right := _drawn_right
	if Settings.reduced_motion():
		_display_value = value
		_display_fire = fire_value
		_display_swap = swap_value
	else:
		var alpha := 1.0 - exp(-22.0 * minf(maxf(delta, 0.0), 0.1))
		_display_value = lerpf(_display_value, value, alpha)
		_display_fire = lerpf(_display_fire, fire_value, alpha)
		_display_swap = lerpf(_display_swap, swap_value, alpha)
	_drawn_fire = fire_active
	_drawn_swap = swap_active
	_drawn_left = dodge_left_active
	_drawn_right = dodge_right_active
	if not is_equal_approx(prev_x, _display_value) \
			or not is_equal_approx(prev_f, _display_fire) \
			or not is_equal_approx(prev_s, _display_swap) \
			or prev_fire != _drawn_fire or prev_swap != _drawn_swap \
			or prev_left != _drawn_left or prev_right != _drawn_right:
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 2.0 or h <= 2.0:
		return
	var cx := w * 0.5
	var cy := h * 0.5
	var rad := minf(minf(w, h) * 0.26, 26.0)
	var pad := 3.0

	# Rounded track + recessed inner well.
	_rounded(cx, cy, w, h, rad, TRACK)
	_rounded(cx, cy, w - 2.0 * pad, h - 2.0 * pad, maxf(rad - pad, 1.0), TRACK_INNER)

	# A quiet green wash says "gas is live" whenever a finger is on the pad.
	if gas_active:
		_rounded(cx, cy, w - 8.0, h - 8.0, maxf(rad - 4.0, 1.0), GAS_TINT)

	# Upward FIRE glow and its chevrons.
	if _display_fire > 0.02 or fire_active:
		var f_col := FIRE_GLOW
		f_col.a *= 0.85 if fire_active else clampf(_display_fire * 0.7, 0.0, 0.7)
		draw_circle(Vector2(cx, h * 0.26), minf(w * 0.28, h * 0.30), f_col)
		if fire_active:
			draw_line(Vector2(rad, 2.0), Vector2(w - rad, 2.0), FIRE_LIT, 2.5)
	# Downward weapon SWAP glow.
	if _display_swap > 0.02 or swap_active:
		var s_col := SWAP_GLOW
		s_col.a *= 0.85 if swap_active else clampf(_display_swap * 0.7, 0.0, 0.7)
		draw_circle(Vector2(cx, h * 0.76), minf(w * 0.28, h * 0.28), s_col)
		if swap_active:
			draw_line(Vector2(rad, h - 2.0), Vector2(w - rad, h - 2.0), SWAP_LIT, 2.5)
	# Dodge side glows.
	if _display_value < -0.02 or dodge_left_active:
		var l_col := DODGE_GLOW
		l_col.a *= 0.85 if dodge_left_active else clampf(-_display_value * 0.7, 0.0, 0.7)
		draw_circle(Vector2(w * 0.20, cy), minf(w * 0.26, h * 0.36), l_col)
	if _display_value > 0.02 or dodge_right_active:
		var r_col := DODGE_GLOW
		r_col.a *= 0.85 if dodge_right_active else clampf(_display_value * 0.7, 0.0, 0.7)
		draw_circle(Vector2(w * 0.80, cy), minf(w * 0.26, h * 0.36), r_col)

	# Cross guides + deadzone marks (horizontal dodge deadband).
	draw_line(Vector2(cx, h * 0.24), Vector2(cx, h * 0.82), CENTER, 2.5)
	draw_line(Vector2(w * 0.24, cy), Vector2(w * 0.76, cy), CENTER, 1.5)
	var travel := maxf(w * 0.5 - rad - 6.0, 1.0)
	var dz_px := DEADZONE * travel
	draw_line(Vector2(cx - dz_px, cy - h * 0.12), Vector2(cx - dz_px, cy + h * 0.12), DEADZONE_MARK, 1.5)
	draw_line(Vector2(cx + dz_px, cy - h * 0.12), Vector2(cx + dz_px, cy + h * 0.12), DEADZONE_MARK, 1.5)

	# FIRE cue at the top.
	var cue := FIRE_LIT if fire_active else FIRE_GUIDE
	var cw := 7.5
	var cy1 := h * 0.07
	var cy2 := cy1 + 5.5
	draw_line(Vector2(cx - cw, cy1 + 5.0), Vector2(cx, cy1), cue, 2.2, true)
	draw_line(Vector2(cx + cw, cy1 + 5.0), Vector2(cx, cy1), cue, 2.2, true)
	draw_line(Vector2(cx - cw, cy2 + 5.0), Vector2(cx, cy2), cue, 2.2, true)
	draw_line(Vector2(cx + cw, cy2 + 5.0), Vector2(cx, cy2), cue, 2.2, true)

	# Dodge chevrons left/right (pointing outward: < on left, > on right).
	var lcue := DODGE_LIT if dodge_left_active else DODGE_GUIDE
	var rcue := DODGE_LIT if dodge_right_active else DODGE_GUIDE
	draw_line(Vector2(w * 0.10 + 2.0, cy - 6.0), Vector2(w * 0.10 - 4.0, cy), lcue, 2.2, true)
	draw_line(Vector2(w * 0.10 + 2.0, cy + 6.0), Vector2(w * 0.10 - 4.0, cy), lcue, 2.2, true)
	draw_line(Vector2(w * 0.90 - 2.0, cy - 6.0), Vector2(w * 0.90 + 4.0, cy), rcue, 2.2, true)
	draw_line(Vector2(w * 0.90 - 2.0, cy + 6.0), Vector2(w * 0.90 + 4.0, cy), rcue, 2.2, true)

	# Specular top edge + outline (four 90° quarter-arcs + 4 straight borders).
	draw_line(Vector2(rad, 2.0), Vector2(w - rad, 2.0), TRACK_SPECULAR, 1.5)
	draw_arc(Vector2(rad, rad), rad, PI, PI * 1.5, 12, TRACK_EDGE, 2.0, true)
	draw_arc(Vector2(w - rad, rad), rad, -PI * 0.5, 0.0, 12, TRACK_EDGE, 2.0, true)
	draw_arc(Vector2(rad, h - rad), rad, PI * 0.5, PI, 12, TRACK_EDGE, 2.0, true)
	draw_arc(Vector2(w - rad, h - rad), rad, 0.0, PI * 0.5, 12, TRACK_EDGE, 2.0, true)
	draw_line(Vector2(rad, 1.0), Vector2(w - rad, 1.0), TRACK_EDGE, 2.0)
	draw_line(Vector2(rad, h - 1.0), Vector2(w - rad, h - 1.0), TRACK_EDGE, 2.0)
	draw_line(Vector2(1.0, rad), Vector2(1.0, h - rad), TRACK_EDGE, 2.0)
	draw_line(Vector2(w - 1.0, rad), Vector2(w - 1.0, h - rad), TRACK_EDGE, 2.0)

	# Text cues (only on pads tall enough to read them).
	var scue := SWAP_LIT if swap_active else SWAP_GUIDE
	if ThemeDB.fallback_font != null and h >= 72.0:
		var font := ThemeDB.fallback_font
		var fsize := 12
		draw_string(font, Vector2(cx - font.get_string_size("FIRE", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x * 0.5,
				h * 0.27), "FIRE", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, cue)
		draw_string(font, Vector2(cx - font.get_string_size("SWAP", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x * 0.5,
				h * 0.85), "SWAP", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, scue)

	# Knob: horizontal for dodge, upward for fire, downward for weapon swap.
	var kx := cx + _display_value * travel
	var ky := cy - (clampf(_display_fire, 0.0, 1.0) - clampf(_display_swap, 0.0, 1.0)) * (h * 0.22)
	var kr := minf(w * 0.16, h * 0.24)
	var knob_col := KNOB
	if fire_active:
		knob_col = KNOB_FIRE
	elif swap_active:
		knob_col = KNOB_SWAP
	elif dodge_left_active or dodge_right_active:
		knob_col = KNOB_DODGE
	if absf(_display_value) > 0.05 or fire_active or swap_active or dodge_left_active or dodge_right_active:
		var halo := knob_col
		halo.a = 0.28 if (fire_active or swap_active or dodge_left_active or dodge_right_active) else (0.20 * absf(_display_value))
		draw_circle(Vector2(kx, ky), kr * 1.26, halo)
	draw_circle(Vector2(kx, ky), kr, knob_col)
	draw_arc(Vector2(kx, ky), kr - 1.5, 0.0, TAU, 24, KNOB_RIM, 1.5, true)
	draw_arc(Vector2(kx, ky), kr, 0.0, TAU, 24, KNOB_EDGE, 2.0, true)
	draw_line(Vector2(kx - kr * 0.5, ky), Vector2(kx + kr * 0.5, ky), KNOB_EDGE, 2.0)


func _rounded(cx: float, cy: float, w: float, h: float, r: float, col: Color) -> void:
	draw_rect(Rect2(cx - w * 0.5 + r, cy - h * 0.5, w - 2.0 * r, h), col)
	draw_rect(Rect2(cx - w * 0.5, cy - h * 0.5 + r, w, h - 2.0 * r), col)
	draw_circle(Vector2(cx - w * 0.5 + r, cy - h * 0.5 + r), r, col)
	draw_circle(Vector2(cx + w * 0.5 - r, cy - h * 0.5 + r), r, col)
	draw_circle(Vector2(cx - w * 0.5 + r, cy + h * 0.5 - r), r, col)
	draw_circle(Vector2(cx + w * 0.5 - r, cy + h * 0.5 - r), r, col)
