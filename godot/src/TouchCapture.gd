extends Control
## Raw pointer sink for the touch overlay.
## The drive buttons are MOUSE_FILTER_IGNORE display-only shells; this full-rect
## control receives the real events so every finger (InputEventScreenTouch.index)
## can own its own action. Buttons rode Godot's emulated single mouse pointer,
## which made two-finger steering+gas impossible.
##
## MOUSE_FILTER_PASS: we observe, we never consume, so taps still reach the rest
## of the UI (HUD restart, TOUCH toggle, pause).
##
## Mouse handling: when project emulation is on (default), every touch emits a
## deterministic PAIRED mouse event. Mouse events are tracked under a
## dedicated namespace key (MOUSE_POINTER) that can never collide with a touch
## index, and every hold is matched by exactly one release, so the paired
## emulated stream never leaks or double-drops. Real desktop mice take the same
## path, so clickable drive buttons keep working on PC.
const MOUSE_POINTER := 100

signal pointer_down(pointer: int, at: Vector2)
signal pointer_move(pointer: int, at: Vector2)
signal pointer_up(pointer: int, at: Vector2)

var _left_down := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_NONE


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		# An edge gesture (back-swipe, system interrupt) can cancel a finger
		# mid-hold; the OS may never send a matching pressed=false. Never leave
		# an action latched because of it.
		if touch.canceled:
			pointer_up.emit(touch.index, touch.position)
		elif touch.pressed:
			pointer_down.emit(touch.index, touch.position)
		else:
			pointer_up.emit(touch.index, touch.position)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		pointer_move.emit(drag.index, drag.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		_left_down = mb.pressed
		if mb.pressed:
			pointer_down.emit(MOUSE_POINTER, mb.position)
		else:
			pointer_up.emit(MOUSE_POINTER, mb.position)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 or _left_down:
			pointer_move.emit(MOUSE_POINTER, motion.position)
