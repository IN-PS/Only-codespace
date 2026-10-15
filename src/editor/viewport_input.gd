class_name PSViewportInput
extends Control
## Camada transparente sobre a vista 3D que transforma toques e mouse em gestos:
##  - um dedo: pointer_down / pointer_move / pointer_up (com detecção de toque curto);
##  - toque duplo e toque longo;
##  - dois dedos: arrastar (pan) + pinça (zoom);
##  - mouse: botão esquerdo = dedo; botão direito/meio = girar/arrastar; roda = zoom.
## Fica atrás dos painéis: só recebe eventos que nenhum painel consumiu.

signal pointer_down(pos: Vector2)
signal pointer_move(pos: Vector2, rel: Vector2)
signal pointer_up(pos: Vector2, was_tap: bool)
signal pointer_cancel
signal double_tap(pos: Vector2)
signal long_press(pos: Vector2)
signal two_finger(center: Vector2, pan: Vector2, zoom_factor: float)
signal mouse_orbit(rel: Vector2)
signal mouse_pan(rel: Vector2)
signal wheel_zoom(factor: float, pos: Vector2)
signal hover(pos: Vector2)

const TAP_TIME := 0.35
const TAP_MOVE := 12.0
const LONG_PRESS_TIME := 0.55
const DOUBLE_TAP_TIME := 0.35

var _touches := {}           # index -> posição
var _primary := -1           # índice do dedo principal (-2 = mouse)
var _primary_start := Vector2.ZERO
var _primary_time := 0.0
var _primary_moved := false
var _long_fired := false
var _multi := false
var _last_tap_time := -10.0
var _last_tap_pos := Vector2.ZERO
var _prev_center := Vector2.ZERO
var _prev_dist := 0.0
var _mouse_mode := 0         # 0 nada, 1 girar (direito), 2 arrastar (meio)


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(_delta: float) -> void:
	if _primary != -1 and not _primary_moved and not _long_fired and not _multi:
		if _now() - _primary_time >= LONG_PRESS_TIME:
			_long_fired = true
			long_press.emit(_primary_start)


func is_active() -> bool:
	return _primary != -1 or _multi


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		_on_touch(ev)
		accept_event()
	elif ev is InputEventScreenDrag:
		_on_drag(ev)
		accept_event()
	elif ev is InputEventMouseButton:
		if ev.device == InputEvent.DEVICE_ID_EMULATION:
			accept_event()
			return
		_on_mouse_button(ev)
		accept_event()
	elif ev is InputEventMouseMotion:
		if ev.device == InputEvent.DEVICE_ID_EMULATION:
			accept_event()
			return
		_on_mouse_motion(ev)
	elif ev is InputEventMagnifyGesture:
		wheel_zoom.emit(1.0 / maxf(ev.factor, 0.01), ev.position)
	elif ev is InputEventPanGesture:
		mouse_pan.emit(-ev.delta * 8.0)


# --------------------------------------------------------------------------
# Toque
# --------------------------------------------------------------------------

func _on_touch(ev: InputEventScreenTouch) -> void:
	if ev.pressed:
		_touches[ev.index] = ev.position
		if _touches.size() == 1 and _primary == -1:
			_start_primary(ev.index, ev.position)
		elif _touches.size() >= 2:
			if _primary != -1 and not _multi:
				_primary = -1
				pointer_cancel.emit()
			_multi = true
			_reset_multi()
	else:
		_touches.erase(ev.index)
		if ev.index == _primary and not _multi:
			_end_primary(ev.position)
		if _touches.size() < 2 and _multi:
			if _touches.is_empty():
				_multi = false
				_primary = -1
			else:
				_reset_multi()
		if ev.canceled:
			_touches.clear()
			_multi = false
			if _primary != -1:
				_primary = -1
				pointer_cancel.emit()


func _on_drag(ev: InputEventScreenDrag) -> void:
	if not _touches.has(ev.index):
		_touches[ev.index] = ev.position
	_touches[ev.index] = ev.position
	if _multi and _touches.size() >= 2:
		var pts := _two_points()
		var p0: Vector2 = pts[0]
		var p1: Vector2 = pts[1]
		var center := (p0 + p1) * 0.5
		var dist := p0.distance_to(p1)
		var pan := center - _prev_center
		var factor := 1.0
		if _prev_dist > 1.0 and dist > 1.0:
			factor = _prev_dist / dist
		_prev_center = center
		_prev_dist = dist
		two_finger.emit(center, pan, factor)
	elif ev.index == _primary:
		_move_primary(ev.position, ev.relative)


func _two_points() -> Array:
	var keys := _touches.keys()
	keys.sort()
	return [_touches[keys[0]] as Vector2, _touches[keys[1]] as Vector2]


func _reset_multi() -> void:
	if _touches.size() >= 2:
		var pts := _two_points()
		var p0: Vector2 = pts[0]
		var p1: Vector2 = pts[1]
		_prev_center = (p0 + p1) * 0.5
		_prev_dist = p0.distance_to(p1)


# --------------------------------------------------------------------------
# Ponteiro principal (dedo único ou botão esquerdo)
# --------------------------------------------------------------------------

func _start_primary(index: int, pos: Vector2) -> void:
	_primary = index
	_primary_start = pos
	_primary_time = _now()
	_primary_moved = false
	_long_fired = false
	pointer_down.emit(pos)


func _move_primary(pos: Vector2, rel: Vector2) -> void:
	if not _primary_moved and pos.distance_to(_primary_start) > TAP_MOVE:
		_primary_moved = true
	if _primary_moved:
		pointer_move.emit(pos, rel)


func _end_primary(pos: Vector2) -> void:
	var was_tap := not _primary_moved and not _long_fired and (_now() - _primary_time) <= TAP_TIME * 2.0
	_primary = -1
	pointer_up.emit(pos, was_tap)
	if was_tap:
		var t := _now()
		if t - _last_tap_time <= DOUBLE_TAP_TIME and pos.distance_to(_last_tap_pos) < 30.0:
			double_tap.emit(pos)
			_last_tap_time = -10.0
		else:
			_last_tap_time = t
			_last_tap_pos = pos


# --------------------------------------------------------------------------
# Mouse (computador)
# --------------------------------------------------------------------------

func _on_mouse_button(ev: InputEventMouseButton) -> void:
	match ev.button_index:
		MOUSE_BUTTON_LEFT:
			if ev.pressed and _primary == -1:
				_start_primary(-2, ev.position)
			elif not ev.pressed and _primary == -2:
				_end_primary(ev.position)
		MOUSE_BUTTON_RIGHT:
			_mouse_mode = 1 if ev.pressed else 0
		MOUSE_BUTTON_MIDDLE:
			_mouse_mode = 2 if ev.pressed else 0
		MOUSE_BUTTON_WHEEL_UP:
			if ev.pressed:
				wheel_zoom.emit(0.88, ev.position)
		MOUSE_BUTTON_WHEEL_DOWN:
			if ev.pressed:
				wheel_zoom.emit(1.0 / 0.88, ev.position)


func _on_mouse_motion(ev: InputEventMouseMotion) -> void:
	if _primary == -2:
		_move_primary(ev.position, ev.relative)
	elif _mouse_mode == 1:
		if ev.shift_pressed:
			mouse_pan.emit(ev.relative)
		else:
			mouse_orbit.emit(ev.relative)
	elif _mouse_mode == 2:
		mouse_pan.emit(ev.relative)
	else:
		hover.emit(ev.position)
