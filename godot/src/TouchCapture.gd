extends Control
## Raw pointer sink for the touch overlay.
## The drive buttons are MOUSE_FILTER_IGNORE display-only shells; this full-rect
## control receives the real events so every finger (InputEventScreenTouch.index)
## can own its own action. Buttons rode Godot's emulated single mouse pointer,
## which made two-finger steering+gas impossible.
##
## MOUSE_FILTER_IGNORE + _input(): we observe via make_input_local(), never
## consuming or blocking events, so clicks/taps still reach the rest of the UI
## (HUD RestartBtn/ViewBtn/MenuBtn, TOUCH toggle, ResultPanel).
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
	# MOUSE_FILTER_IGNORE so lower CanvasLayers (HUD RestartBtn, ViewBtn, MenuBtn,
	# ResultPanel) and earlier siblings (BtnTouchToggle) never get swallowed.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_process_input(true)


func _input(event: InputEvent) -> void:
	var local_ev := make_input_local(event)
	if local_ev is InputEventScreenTouch:
		var touch := local_ev as InputEventScreenTouch
		# An edge gesture (back-swipe, system interrupt) can cancel a finger
		# mid-hold; the OS may never send a matching pressed=false. Never leave
		# an action latched because of it.
		if touch.canceled:
			pointer_up.emit(touch.index, touch.position)
		elif touch.pressed:
			pointer_down.emit(touch.index, touch.position)
		else:
			pointer_up.emit(touch.index, touch.position)
	elif local_ev is InputEventScreenDrag:
		var drag := local_ev as InputEventScreenDrag
		pointer_move.emit(drag.index, drag.position)
	elif local_ev is InputEventMouseButton:
		var mb := local_ev as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		_left_down = mb.pressed
		if mb.pressed:
			pointer_down.emit(MOUSE_POINTER, mb.position)
		else:
			pointer_up.emit(MOUSE_POINTER, mb.position)
	elif local_ev is InputEventMouseMotion:
		var motion := local_ev as InputEventMouseMotion
		if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 or _left_down:
			pointer_move.emit(MOUSE_POINTER, motion.position)
