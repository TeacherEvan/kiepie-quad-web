extends Control
## Analog steering pad drawn by the touch overlay (see TouchControls.gd).
## A thumb slides across the strip; the knob follows it and the overlay feeds
## steer_left/steer_right with proportional strength, so get_axis() in
## KiepieBike.gd sees a true analog value instead of binary full-lock.
## Pure view: all input handling lives in TouchControls.

var value := 0.0  ## -1 .. 1, left .. right (display only; overlay owns the truth)
var _display_value := 0.0

const DEADZONE := 0.15
const TRACK := Color(0.08, 0.10, 0.14, 0.86)
const TRACK_INNER := Color(0.14, 0.18, 0.25, 0.90)
const TRACK_EDGE := Color(0.55, 0.65, 0.78, 0.62)
const TRACK_SPECULAR := Color(1.0, 1.0, 1.0, 0.12)
const CENTER := Color(0.92, 0.94, 0.98, 0.42)
const DEADZONE_MARK := Color(0.75, 0.82, 0.92, 0.35)
const GLOW_ACTIVE := Color(1.0, 0.62, 0.16, 0.32)
const KNOB := Color(1.0, 0.62, 0.16, 0.96)
const KNOB_RIM := Color(1.0, 0.86, 0.52, 0.75)
const KNOB_EDGE := Color(0.35, 0.18, 0.02, 0.92)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # the capture layer hit-tests this rect
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(44, 44)


func _process(delta: float) -> void:
	var prev := _display_value
	if Settings.reduced_motion():
		_display_value = value
	else:
		var alpha := 1.0 - exp(-22.0 * minf(maxf(delta, 0.0), 0.1))
		_display_value = lerpf(_display_value, value, alpha)
	if not is_equal_approx(prev, _display_value):
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
	draw_line(Vector2(cx, h * 0.20), Vector2(cx, h * 0.80), CENTER, 2.5)
	var dz_px := DEADZONE * travel
	draw_line(Vector2(cx - dz_px, h * 0.30), Vector2(cx - dz_px, h * 0.70), DEADZONE_MARK, 1.5)
	draw_line(Vector2(cx + dz_px, h * 0.30), Vector2(cx + dz_px, h * 0.70), DEADZONE_MARK, 1.5)

	# Knob + active halo
	var kx := cx + _display_value * travel
	var kr := h * 0.34
	if strength > 0.05:
		var halo := KNOB
		halo.a = 0.22 * strength
		draw_circle(Vector2(kx, h * 0.5), kr * 1.28, halo)
	draw_circle(Vector2(kx, h * 0.5), kr, KNOB)
	draw_arc(Vector2(kx, h * 0.5), kr - 1.5, 0.0, TAU, 28, KNOB_RIM, 1.5, true)
	draw_arc(Vector2(kx, h * 0.5), kr, 0.0, TAU, 28, KNOB_EDGE, 2.0, true)

	# Direction chevrons on the knob
	draw_line(Vector2(kx - kr * 0.55, h * 0.5 - kr * 0.35), Vector2(kx - kr * 0.15, h * 0.5), KNOB_EDGE, 2.0)
	draw_line(Vector2(kx - kr * 0.55, h * 0.5 + kr * 0.35), Vector2(kx - kr * 0.15, h * 0.5), KNOB_EDGE, 2.0)
	draw_line(Vector2(kx + kr * 0.55, h * 0.5 - kr * 0.35), Vector2(kx + kr * 0.15, h * 0.5), KNOB_EDGE, 2.0)
	draw_line(Vector2(kx + kr * 0.55, h * 0.5 + kr * 0.35), Vector2(kx + kr * 0.15, h * 0.5), KNOB_EDGE, 2.0)
