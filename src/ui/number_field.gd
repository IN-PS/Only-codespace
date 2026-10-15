class_name PSNumberField
extends HBoxContainer
## Campo numérico para toque: toque no valor para digitar, ou arraste o
## rótulo (X/Y/Z) para os lados para ajustar continuamente.

signal value_changed(value: float)     # durante o arraste (ao vivo)
signal value_committed(value: float)   # ao soltar ou confirmar a digitação

var value := 0.0
var step := 0.1
var min_value := -1e9
var max_value := 1e9
var decimals := 2
var drag_sensitivity := 1.0

var _label: Label
var _edit: LineEdit
var _dragging := false
var _drag_accum := 0.0
var _drag_start_value := 0.0
var _drag_index := -1


static func create(axis_text: String, axis_color: Color, p_step := 0.1, p_decimals := 2) -> PSNumberField:
	var f := PSNumberField.new()
	f.step = p_step
	f.decimals = p_decimals
	f._build(axis_text, axis_color)
	return f


func _build(axis_text: String, axis_color: Color) -> void:
	add_theme_constant_override("separation", 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label = Label.new()
	_label.text = axis_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.custom_minimum_size = Vector2(22 if axis_text.length() <= 1 else 30, PSTheme.TOUCH - 4)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_font_size_override("font_size", 13)
	_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_label.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	_label.tooltip_text = "Arraste para ajustar"
	var bg := PanelContainer.new()
	var sb := PSTheme.box(axis_color.darkened(0.35), 6, Color.TRANSPARENT, 0, 2, 0)
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_right = 0
	bg.add_theme_stylebox_override("panel", sb)
	bg.mouse_filter = Control.MOUSE_FILTER_PASS
	bg.add_child(_label)
	add_child(bg)
	_label.gui_input.connect(_on_label_input)
	_edit = LineEdit.new()
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.custom_minimum_size = Vector2(48, PSTheme.TOUCH - 4)
	_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	_edit.select_all_on_focus = true
	_edit.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var esb := PSTheme.box(Color("15171c"), 6, PSTheme.BORDER, 1, 6, 4)
	esb.corner_radius_top_left = 0
	esb.corner_radius_bottom_left = 0
	_edit.add_theme_stylebox_override("normal", esb)
	var fsb := esb.duplicate() as StyleBoxFlat
	fsb.border_color = PSTheme.ACCENT
	_edit.add_theme_stylebox_override("focus", fsb)
	_edit.text_submitted.connect(func(_t): _commit_text(); _edit.release_focus())
	_edit.focus_exited.connect(_commit_text)
	add_child(_edit)
	_refresh_text()


func set_value(v: float, emit := false) -> void:
	v = clampf(v, min_value, max_value)
	value = v
	if not _edit.has_focus():
		_refresh_text()
	if emit:
		value_changed.emit(value)


func set_editable(on: bool) -> void:
	_edit.editable = on
	_label.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE


func _refresh_text() -> void:
	var s := String.num(value, decimals)
	if s == "-0":
		s = "0"
	_edit.text = s


func _commit_text() -> void:
	var t := _edit.text.strip_edges().replace(",", ".")
	var expr := Expression.new()
	var v := value
	if t.is_valid_float():
		v = t.to_float()
	elif expr.parse(t) == OK:
		# Permite contas simples como "2*3" ou "10/4" (só números e operadores).
		var ok := true
		for c in t:
			if not ("0123456789.+-*/() ".contains(c)):
				ok = false
		if ok:
			var r = expr.execute()
			if not expr.has_execute_failed() and (typeof(r) == TYPE_FLOAT or typeof(r) == TYPE_INT):
				v = float(r)
	v = clampf(v, min_value, max_value)
	if not is_equal_approx(v, value):
		value = v
		value_changed.emit(value)
		value_committed.emit(value)
	_refresh_text()


func _on_label_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed and _drag_index == -1:
			_begin_drag(ev.index)
		elif not ev.pressed and ev.index == _drag_index:
			_end_drag()
		accept_event()
	elif ev is InputEventScreenDrag and ev.index == _drag_index:
		_drag_by(ev.relative.x)
		accept_event()
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.device != InputEvent.DEVICE_ID_EMULATION:
		if ev.pressed:
			_begin_drag(-2)
		elif _drag_index == -2:
			_end_drag()
		accept_event()
	elif ev is InputEventMouseMotion and _drag_index == -2 and ev.device != InputEvent.DEVICE_ID_EMULATION:
		_drag_by(ev.relative.x)
		accept_event()


func _begin_drag(index: int) -> void:
	_drag_index = index
	_dragging = true
	_drag_accum = 0.0
	_drag_start_value = value


func _drag_by(dx: float) -> void:
	_drag_accum += dx * drag_sensitivity
	var v := _drag_start_value + roundf(_drag_accum / 6.0) * step
	v = clampf(v, min_value, max_value)
	if not is_equal_approx(v, value):
		value = v
		_refresh_text()
		value_changed.emit(value)


func _end_drag() -> void:
	_drag_index = -1
	_dragging = false
	if not is_equal_approx(value, _drag_start_value):
		value_committed.emit(value)
