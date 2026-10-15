class_name PSModal
extends Control
## Diálogo modal desenhado dentro da própria interface (sem janelas do sistema),
## com fundo escurecido, botões grandes e fechamento pelo botão "voltar".

signal closed

var panel: PanelContainer
var body: VBoxContainer
var buttons: HBoxContainer
var title_label: Label
var dismissable := true


static func create(title: String, width := 420.0) -> PSModal:
	var m := PSModal.new()
	m._setup(title, width)
	return m


func _setup(title: String, width: float) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PSTheme.box(PSTheme.PANEL, 14, PSTheme.BORDER, 1, 18, 16))
	var ui_size := App.get_ui_size()
	panel.custom_minimum_size = Vector2(minf(width, ui_size.x - 24.0), 0)
	center.add_child(panel)
	var v := PSUI.vbox(12)
	panel.add_child(v)
	title_label = PSUI.label(title, "TitleLabel", true)
	v.add_child(title_label)
	body = PSUI.vbox(10)
	v.add_child(body)
	buttons = PSUI.hbox(8)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(buttons)


func _on_dim_input(ev: InputEvent) -> void:
	if not dismissable:
		return
	if (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and ev.pressed):
		close()


func add_text(text: String) -> Label:
	var l := PSUI.label(text, "", true)
	l.custom_minimum_size.x = panel.custom_minimum_size.x - 40.0
	body.add_child(l)
	return l


func add_button(text: String, callback: Callable = Callable(), variation := "", close_after := true) -> Button:
	var b := PSUI.button(text, "", "", variation)
	b.custom_minimum_size.x = 96
	b.pressed.connect(func():
		if callback.is_valid():
			callback.call()
		if close_after:
			close())
	buttons.add_child(b)
	return b


func show_modal() -> PSModal:
	var host: Control = App.overlay
	if host == null:
		push_error("PSModal sem overlay")
		return self
	host.add_child(self)
	return self


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


## Responde ao botão "voltar" do Android. Retorna true se tratou o evento.
static func close_top() -> bool:
	var host: Control = App.overlay
	if host == null:
		return false
	for i in range(host.get_child_count() - 1, -1, -1):
		var c := host.get_child(i)
		if c is PSModal and not c.is_queued_for_deletion():
			if c.dismissable:
				c.close()
			return true
	return false


static func is_open() -> bool:
	var host: Control = App.overlay
	if host == null:
		return false
	for c in host.get_children():
		if c is PSModal and not c.is_queued_for_deletion():
			return true
	return false


# --------------------------------------------------------------------------
# Atalhos
# --------------------------------------------------------------------------

static func message(title: String, text: String) -> PSModal:
	var m := create(title)
	m.add_text(text)
	m.add_button("OK", Callable(), "AccentButton")
	return m.show_modal()


static func confirm(title: String, text: String, ok_text: String, on_ok: Callable, danger := false, cancel_text := "Cancelar") -> PSModal:
	var m := create(title)
	m.add_text(text)
	m.add_button(cancel_text)
	m.add_button(ok_text, on_ok, "DangerButton" if danger else "AccentButton")
	return m.show_modal()


## Três opções (ex.: "Salvar", "Descartar", "Cancelar").
static func choice3(title: String, text: String, a_text: String, on_a: Callable, b_text: String, on_b: Callable, cancel_text := "Cancelar") -> PSModal:
	var m := create(title)
	m.add_text(text)
	m.add_button(cancel_text)
	m.add_button(b_text, on_b, "DangerButton")
	m.add_button(a_text, on_a, "AccentButton")
	return m.show_modal()


static func prompt(title: String, label_text: String, default_text: String, on_ok: Callable, ok_text := "OK", placeholder := "") -> PSModal:
	var m := create(title)
	if label_text != "":
		m.add_text(label_text)
	var le := PSUI.line_edit(default_text, placeholder)
	le.max_length = PSData.MAX_NAME
	m.body.add_child(le)
	var submit := func():
		var t := le.text.strip_edges()
		if t.is_empty():
			return
		on_ok.call(t)
		m.close()
	le.text_submitted.connect(func(_t): submit.call())
	m.add_button("Cancelar")
	m.add_button(ok_text, submit, "AccentButton", false)
	m.show_modal()
	le.call_deferred("grab_focus")
	return m


## Lista de opções em botões grandes. `on_pick` recebe o índice.
static func pick_list(title: String, options: Array, on_pick: Callable) -> PSModal:
	var m := create(title)
	var list := PSUI.vbox(6)
	for i in options.size():
		var b := PSUI.button(String(options[i]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var idx := i
		b.pressed.connect(func():
			on_pick.call(idx)
			m.close())
		list.add_child(b)
	var sc := PSUI.scroll(list)
	sc.custom_minimum_size.y = minf(options.size() * 50.0, App.get_ui_size().y * 0.6)
	m.body.add_child(sc)
	m.add_button("Cancelar")
	return m.show_modal()
