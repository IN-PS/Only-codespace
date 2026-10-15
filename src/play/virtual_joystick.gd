class_name PSVirtualJoystick
extends Control
## Joystick virtual flutuante: aparece onde o polegar toca na área esquerda.

signal moved(vec: Vector2)

const BASE_RADIUS := 64.0
const KNOB_RADIUS := 28.0

var output := Vector2.ZERO
var _touch := -1
var _center := Vector2.ZERO
var _knob := Vector2.ZERO
var _rest := Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	resized.connect(_on_resized)
	_on_resized()


func _on_resized() -> void:
	_rest = Vector2(BASE_RADIUS + 28.0, size.y - BASE_RADIUS - 28.0)
	queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed and _touch == -1:
			_touch = ev.index
			_center = ev.position
			_update(ev.position)
		elif not ev.pressed and ev.index == _touch:
			_release()
		accept_event()
	elif ev is InputEventScreenDrag and ev.index == _touch:
		_update(ev.position)
		accept_event()
	elif ev is InputEventMouseButton and ev.device != InputEvent.DEVICE_ID_EMULATION and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed and _touch == -1:
			_touch = -2
			_center = ev.position
			_update(ev.position)
		elif not ev.pressed and _touch == -2:
			_release()
		accept_event()
	elif ev is InputEventMouseMotion and _touch == -2 and ev.device != InputEvent.DEVICE_ID_EMULATION:
		_update(ev.position)
		accept_event()


func _update(pos: Vector2) -> void:
	var d := pos - _center
	if d.length() > BASE_RADIUS:
		# O centro acompanha o dedo para nunca "travar" na borda.
		_center = pos - d.normalized() * BASE_RADIUS
		d = pos - _center
	_knob = d
	output = d / BASE_RADIUS
	if output.length() < 0.12:
		output = Vector2.ZERO
	moved.emit(output)
	queue_redraw()


func _release() -> void:
	_touch = -1
	output = Vector2.ZERO
	_knob = Vector2.ZERO
	moved.emit(output)
	queue_redraw()


func reset() -> void:
	_release()


func _draw() -> void:
	var c := _center if _touch != -1 else _rest
	draw_circle(c, BASE_RADIUS, Color(1, 1, 1, 0.08))
	draw_arc(c, BASE_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 2.0, true)
	draw_circle(c + _knob, KNOB_RADIUS, Color(1, 1, 1, 0.45 if _touch != -1 else 0.25))
