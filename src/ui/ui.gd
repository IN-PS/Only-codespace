class_name PSUI
extends RefCounted
## Atalhos para montar a interface em código com alvos de toque adequados.


static func button(text: String, icon := "", tooltip := "", variation := "") -> Button:
	var b := Button.new()
	b.text = text
	if icon != "":
		b.icon = PSIcons.get_icon(icon)
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(0, PSTheme.TOUCH)
	b.focus_mode = Control.FOCUS_NONE
	if variation != "":
		b.theme_type_variation = variation
	return b


static func icon_button(icon: String, tooltip := "", flat := true, size := PSTheme.TOUCH) -> Button:
	var b := Button.new()
	b.icon = PSIcons.get_icon(icon)
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = Control.FOCUS_NONE
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if flat:
		b.theme_type_variation = "FlatButton"
	return b


static func toggle(b: Button, pressed := false) -> Button:
	b.toggle_mode = true
	b.button_pressed = pressed
	return b


static func label(text: String, variation := "", autowrap := false) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if autowrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 40
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func hbox(sep := 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep := 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func spacer(horizontal := true) -> Control:
	var c := Control.new()
	if horizontal:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func line_edit(text := "", placeholder := "") -> LineEdit:
	var le := LineEdit.new()
	le.text = text
	le.placeholder_text = placeholder
	le.custom_minimum_size = Vector2(0, PSTheme.TOUCH)
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.select_all_on_focus = true
	return le


static func option(items: Array, selected := 0) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(String(it))
	if items.size() > 0:
		o.select(clampi(selected, 0, items.size() - 1))
	o.custom_minimum_size = Vector2(0, PSTheme.TOUCH)
	o.focus_mode = Control.FOCUS_NONE
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.fit_to_longest_item = false
	return o


static func check(text: String, pressed := false) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = pressed
	c.custom_minimum_size = Vector2(0, PSTheme.TOUCH - 4)
	c.focus_mode = Control.FOCUS_NONE
	return c


## Linha "rótulo: controle".
static func row(label_text: String, control: Control, label_width := 92.0) -> HBoxContainer:
	var h := hbox(8)
	var l := label(label_text, "DimLabel")
	l.custom_minimum_size.x = label_width
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	return h


## Controle deslizante com valor numérico ao lado.
static func slider(min_v: float, max_v: float, step: float, value: float, fmt := "%.2f") -> HBoxContainer:
	var h := hbox(8)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(80, PSTheme.TOUCH - 8)
	s.focus_mode = Control.FOCUS_NONE
	var grab := PSIcons.get_icon("grabber", 22.0)
	s.add_theme_icon_override("grabber", grab)
	s.add_theme_icon_override("grabber_highlight", grab)
	var l := label(fmt % value, "DimLabel")
	l.custom_minimum_size.x = 44
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(v): l.text = fmt % v)
	h.add_child(s)
	h.add_child(l)
	h.set_meta("slider", s)
	return h


static func get_slider(h: Control) -> HSlider:
	return h.get_meta("slider") as HSlider


static func color_button(c: Color, alpha := false) -> ColorPickerButton:
	var b := ColorPickerButton.new()
	b.color = c
	b.edit_alpha = alpha
	b.custom_minimum_size = Vector2(56, PSTheme.TOUCH)
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Seletor enxuto para o celular: sem amostras, modos de cor nem conta-gotas.
	var picker := b.get_picker()
	picker.presets_visible = false
	picker.color_modes_visible = false
	picker.sampler_visible = false
	picker.can_add_swatches = false
	picker.edit_intensity = false
	return b


static func separator() -> HSeparator:
	return HSeparator.new()


static func panel(stylebox: StyleBox = null) -> PanelContainer:
	var p := PanelContainer.new()
	if stylebox:
		p.add_theme_stylebox_override("panel", stylebox)
	return p


static func scroll(content: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(content)
	return s


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## Mensagem rápida no canto da tela.
static func toast(text: String, kind := "info", seconds := 2.5) -> void:
	var host: Control = App.overlay
	if host == null:
		return
	var p := PanelContainer.new()
	var color := PSTheme.PANEL_3
	match kind:
		"error":
			color = PSTheme.DANGER.darkened(0.45)
		"warn":
			color = PSTheme.WARN.darkened(0.55)
		"ok":
			color = PSTheme.SUCCESS.darkened(0.5)
	p.add_theme_stylebox_override("panel", PSTheme.box(color, 10, PSTheme.BORDER, 1, 14, 10))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text, "", true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	host.add_child(p)
	var ui_size := App.get_ui_size()
	var w := minf(ui_size.x - 32.0, 420.0)
	p.custom_minimum_size = Vector2(w, 0)
	l.custom_minimum_size.x = w - 28.0
	# Empilha toasts existentes.
	var offset := 0.0
	for c in host.get_children():
		if c != p and c.has_meta("toast"):
			offset += c.size.y + 8.0
	p.set_meta("toast", true)
	p.position = Vector2((ui_size.x - w) * 0.5, ui_size.y - 150.0 - offset)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	tw.tween_interval(seconds)
	tw.tween_property(p, "modulate:a", 0.0, 0.3)
	tw.tween_callback(p.queue_free)
