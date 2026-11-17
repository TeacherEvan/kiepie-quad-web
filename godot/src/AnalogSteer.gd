extends Control
## Analog steering + push-forward turbo pad drawn by the touch overlay (see TouchControls.gd).
## A thumb slides horizontally to steer proportionally, and pushes upward past the
## forward threshold to engage turbo while keeping steering live.
## Pure view: all input handling lives in TouchControls.

var value := 0.0        ## -1 .. 1, left .. right (display only; overlay owns the truth)
var turbo_value := 0.0  ## 0 .. 1 upward deflection (display only)
var turbo_active := false
var _display_value := 0.0
var _display_turbo := 0.0
var _drawn_turbo_active := false

const DEADZONE := 0.15
const TRACK := Color(0.08, 0.10, 0.14, 0.86)
const TRACK_INNER := Color(0.14, 0.18, 0.25, 0.90)
const TRACK_EDGE := Color(0.55, 0.65, 0.78, 0.62)
const TRACK_SPECULAR := Color(1.0, 1.0, 1.0, 0.12)
const CENTER := Color(0.92, 0.94, 0.98, 0.42)
const DEADZONE_MARK := Color(0.75, 0.82, 0.92, 0.35)
const GLOW_ACTIVE := Color(1.0, 0.62, 0.16, 0.32)
const TURBO_GLOW := Color(1.0, 0.74, 0.14, 0.42)
const TURBO_GUIDE := Color(1.0, 0.84, 0.42, 0.82)
const TURBO_LIT := Color(1.0, 0.92, 0.35, 1.0)
const KNOB := Color(1.0, 0.62, 0.16, 0.96)
const KNOB_TURBO := Color(1.0, 0.80, 0.22, 0.98)
const KNOB_RIM := Color(1.0, 0.86, 0.52, 0.75)
const KNOB_EDGE := Color(0.35, 0.18, 0.02, 0.92)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # the capture layer hit-tests this rect
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(44, 44)


func _process(delta: float) -> void:
	var prev_x := _display_value
	var prev_t := _display_turbo
	var prev_active := _drawn_turbo_active
	if Settings.reduced_motion():
		_display_value = value
		_display_turbo = turbo_value
	else:
		var alpha := 1.0 - exp(-22.0 * minf(maxf(delta, 0.0), 0.1))
		_display_value = lerpf(_display_value, value, alpha)
		_display_turbo = lerpf(_display_turbo, turbo_value, alpha)
	_drawn_turbo_active = turbo_active
	if not is_equal_approx(prev_x, _display_value) \
			or not is_equal_approx(prev_t, _display_turbo) \
			or prev_active != _drawn_turbo_active:
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 2.0 or h <= 2.0:
		return
	var r := h * 0.5
	var cx := w * 0.5
	var travel := maxf(w * 0.5 - r * 0.55, 1.0)

	# Outer capsule
	draw_rect(Rect2(r, 0.0, w - 2.0 * r, h), TRACK)
	draw_circle(Vector2(r, r), r, TRACK)
	draw_circle(Vector2(w - r, r), r, TRACK)

	# Inner recessed track
	var pad := 3.0
	var ir := maxf(r - pad, 1.0)
	draw_rect(Rect2(r, pad, w - 2.0 * r, h - 2.0 * pad), TRACK_INNER)
	draw_circle(Vector2(r, r), ir, TRACK_INNER)
	draw_circle(Vector2(w - r, r), ir, TRACK_INNER)

	# Upward turbo zone glow when pushed forward
	if _display_turbo > 0.02 or turbo_active:
		var t_col := TURBO_GLOW
		t_col.a *= 0.85 if turbo_active else clampf(_display_turbo * 0.7, 0.0, 0.7)
		draw_circle(Vector2(cx, h * 0.25), minf(w * 0.28, h * 0.36), t_col)
		if turbo_active:
			draw_line(Vector2(r, 2.0), Vector2(w - r, 2.0), TURBO_LIT, 2.5)

	# Directional glow proportional to steering strength
	var strength := absf(_display_value)
	if strength > 0.02:
		var glow_col := GLOW_ACTIVE
		glow_col.a *= clampf(strength, 0.0, 1.0)
		var fill_w := strength * travel
		if _display_value < 0.0:
			draw_rect(Rect2(cx - fill_w, pad + 2.0, fill_w, h - 2.0 * (pad + 2.0)), glow_col)
		else:
			draw_rect(Rect2(cx, pad + 2.0, fill_w, h - 2.0 * (pad + 2.0)), glow_col)

	# Specular top edge & outline arcs
	draw_line(Vector2(r, 2.0), Vector2(w - r, 2.0), TRACK_SPECULAR, 1.5)
	draw_arc(Vector2(r, r), r, PI * 0.5, PI * 1.5, 24, TRACK_EDGE, 2.0, true)
	draw_arc(Vector2(w - r, r), r, -PI * 0.5, PI * 0.5, 24, TRACK_EDGE, 2.0, true)
	draw_line(Vector2(r, 1.0), Vector2(w - r, 1.0), TRACK_EDGE, 2.0)
	draw_line(Vector2(r, h - 1.0), Vector2(w - r, h - 1.0), TRACK_EDGE, 2.0)

	# Centre notch + ±DEADZONE guides
	draw_line(Vector2(cx, h * 0.24), Vector2(cx, h * 0.80), CENTER, 2.5)
	var dz_px := DEADZONE * travel
	draw_line(Vector2(cx - dz_px, h * 0.32), Vector2(cx - dz_px, h * 0.72), DEADZONE_MARK, 1.5)
	draw_line(Vector2(cx + dz_px, h * 0.32), Vector2(cx + dz_px, h * 0.72), DEADZONE_MARK, 1.5)

	# Push-up turbo cue (double upward chevron + label near top edge)
	var cue_col := TURBO_LIT if turbo_active else TURBO_GUIDE
	var cw := 7.5
	var cy1 := h * 0.06
	var cy2 := cy1 + 5.5
	draw_line(Vector2(cx - cw, cy1 + 5.0), Vector2(cx, cy1), cue_col, 2.2, true)
	draw_line(Vector2(cx + cw, cy1 + 5.0), Vector2(cx, cy1), cue_col, 2.2, true)
	draw_line(Vector2(cx - cw, cy2 + 5.0), Vector2(cx, cy2), cue_col, 2.2, true)
	draw_line(Vector2(cx + cw, cy2 + 5.0), Vector2(cx, cy2), cue_col, 2.2, true)
	if ThemeDB.fallback_font != null and h >= 72.0:
		var font := ThemeDB.fallback_font
		var fsize := 12
		var label := "TURBO"
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		draw_string(font, Vector2(cx - tw * 0.5, h * 0.27), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, cue_col)

	# Knob + active halo (moves horizontally to steer, upward when pushed forward)
	var kx := cx + _display_value * travel
	var ky := h * 0.56 - clampf(_display_turbo, 0.0, 1.0) * (h * 0.22)
	var kr := h * 0.27
	var knob_col := KNOB_TURBO if turbo_active else KNOB
	if strength > 0.05 or turbo_active:
		var halo := knob_col
		halo.a = 0.28 if turbo_active else (0.20 * strength)
		draw_circle(Vector2(kx, ky), kr * (1.28 if turbo_active else 1.24), halo)
	draw_circle(Vector2(kx, ky), kr, knob_col)
	draw_arc(Vector2(kx, ky), kr - 1.5, 0.0, TAU, 28, TURBO_LIT if turbo_active else KNOB_RIM, 1.5, true)
	draw_arc(Vector2(kx, ky), kr, 0.0, TAU, 28, KNOB_EDGE, 2.0, true)

	# Direction chevrons on the knob
	draw_line(Vector2(kx - kr * 0.55, ky - kr * 0.35), Vector2(kx - kr * 0.15, ky), KNOB_EDGE, 2.0)
	draw_line(Vector2(kx - kr * 0.55, ky + kr * 0.35), Vector2(kx - kr * 0.15, ky), KNOB_EDGE, 2.0)
	draw_line(Vector2(kx + kr * 0.55, ky - kr * 0.35), Vector2(kx + kr * 0.15, ky), KNOB_EDGE, 2.0)
	draw_line(Vector2(kx + kr * 0.55, ky + kr * 0.35), Vector2(kx + kr * 0.15, ky), KNOB_EDGE, 2.0)
