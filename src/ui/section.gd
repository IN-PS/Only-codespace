class_name PSSection
extends VBoxContainer
## Seção recolhível com cabeçalho tocável.

signal toggled(expanded: bool)

var header: Button
var content: VBoxContainer
var expanded := true


static func create(title: String, start_expanded := true) -> PSSection:
	var s := PSSection.new()
	s._build(title, start_expanded)
	return s


func _build(title: String, start_expanded: bool) -> void:
	add_theme_constant_override("separation", 6)
	header = Button.new()
	header.text = title
	header.theme_type_variation = "FlatButton"
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.custom_minimum_size = Vector2(0, 38)
	header.focus_mode = Control.FOCUS_NONE
	header.add_theme_color_override("font_color", PSTheme.TEXT_DIM)
	header.add_theme_font_size_override("font_size", 13)
	header.pressed.connect(func(): set_expanded(not expanded))
	add_child(header)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	add_child(content)
	set_expanded(start_expanded)


func set_expanded(on: bool) -> void:
	expanded = on
	content.visible = on
	header.icon = PSIcons.get_icon("down" if on else "right", 18.0, "#9aa1b2")
	toggled.emit(on)
