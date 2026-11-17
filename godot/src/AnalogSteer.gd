extends Control
## Analog steering pad drawn by the touch overlay (see TouchControls.gd).
## A thumb slides across the strip; the knob follows it and the overlay feeds
## steer_left/steer_right with proportional strength, so get_axis() in
## KiepieBike.gd sees a true analog value instead of binary full-lock.
## Pure view: all input handling lives in TouchControls.

var value := 0.0  ## -1 .. 1, left .. right (display only; overlay owns the truth)

const TRACK := Color(0.16, 0.20, 0.28, 0.78)
const TRACK_EDGE := Color(0.55, 0.65, 0.78, 0.55)
const CENTER := Color(0.90, 0.90, 0.88, 0.35)
const KNOB := Color(1.0, 0.62, 0.16, 0.95)
const KNOB_EDGE := Color(0.35, 0.18, 0.02, 0.9)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # the capture layer hit-tests this rect
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(44, 44)

func _draw() -> void:
	var w := size.x
	var h := size.y
	var r := h * 0.5
	# track: rounded rect via two circles + body
	draw_rect(Rect2(r, 0, w - 2.0 * r, h), TRACK)
	draw_circle(Vector2(r, r), r, TRACK)
	draw_circle(Vector2(w - r, r), r, TRACK)
	# outline arcs
	draw_arc(Vector2(r, r), r, PI * 0.5, PI * 1.5, 24, TRACK_EDGE, 2.0, true)
	draw_arc(Vector2(w - r, r), r, -PI * 0.5, PI * 0.5, 24, TRACK_EDGE, 2.0, true)
	draw_line(Vector2(r, 1.0), Vector2(w - r, 1.0), TRACK_EDGE, 2.0)
	draw_line(Vector2(r, h - 1.0), Vector2(w - r, h - 1.0), TRACK_EDGE, 2.0)
	# centre notch + deadzone ticks
	var cx := w * 0.5
	draw_line(Vector2(cx, h * 0.22), Vector2(cx, h * 0.78), CENTER, 3.0)
	# knob
	var kx := cx + value * (w * 0.5 - r * 0.55)
	var kr := h * 0.34
	draw_circle(Vector2(kx, h * 0.5), kr, KNOB)
	draw_arc(Vector2(kx, h * 0.5), kr, 0.0, TAU, 28, KNOB_EDGE, 2.0, true)
	# direction chevrons on the knob
	draw_line(Vector2(kx - kr * 0.55, h * 0.5 - kr * 0.35), Vector2(kx - kr * 0.15, h * 0.5), KNOB_EDGE, 2.0)
	draw_line(Vector2(kx - kr * 0.55, h * 0.5 + kr * 0.35), Vector2(kx - kr * 0.15, h * 0.5), KNOB_EDGE, 2.0)
	draw_line(Vector2(kx + kr * 0.55, h * 0.5 - kr * 0.35), Vector2(kx + kr * 0.15, h * 0.5), KNOB_EDGE, 2.0)
	draw_line(Vector2(kx + kr * 0.55, h * 0.5 + kr * 0.35), Vector2(kx + kr * 0.15, h * 0.5), KNOB_EDGE, 2.0)
