class_name PSTheme
extends RefCounted
## Tema escuro "editor profissional", montado em código.
## Tamanhos em unidades de interface (≈ dp no Android).

const BG := Color("121317")
const PANEL := Color("1b1d23")
const PANEL_2 := Color("23262e")
const PANEL_3 := Color("2c3039")
const BORDER := Color("323743")
const TEXT := Color("e6e8ee")
const TEXT_DIM := Color("9aa1b2")
const TEXT_FAINT := Color("6b7283")
const ACCENT := Color("3d7eff")
const ACCENT_HOVER := Color("5a92ff")
const ACCENT_DIM := Color("24407a")
const DANGER := Color("e5534b")
const WARN := Color("e3b341")
const SUCCESS := Color("3fb950")
const AXIS_X := Color("ef5350")
const AXIS_Y := Color("66bb6a")
const AXIS_Z := Color("42a5f5")

const FONT_SIZE := 15
const TOUCH := 44.0

static var _theme: Theme


static func box(bg: Color, radius := 8, border := Color.TRANSPARENT, border_w := 0, margin_h := 10.0, margin_v := 6.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	s.anti_aliasing = true
	return s


static func empty(margin := 0.0) -> StyleBoxEmpty:
	var s := StyleBoxEmpty.new()
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	return s


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = FONT_SIZE

	# Painéis
	t.set_stylebox("panel", "Panel", box(PANEL, 0))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 10, BORDER, 1, 8, 8))

	# Botões
	var normal := box(PANEL_2, 8, BORDER, 1)
	var hover := box(PANEL_3, 8, BORDER, 1)
	var pressed := box(ACCENT_DIM, 8, ACCENT, 1)
	var disabled := box(PANEL, 8, BORDER, 1)
	var focus := box(Color.TRANSPARENT, 8, ACCENT, 2)
	focus.draw_center = false
	for cls in ["Button", "MenuButton", "OptionButton", "ColorPickerButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("hover_pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, focus)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
		t.set_color("font_hover_pressed_color", cls, Color.WHITE)
		t.set_color("font_focus_color", cls, TEXT)
		t.set_color("font_disabled_color", cls, TEXT_FAINT)
		t.set_color("icon_normal_color", cls, TEXT)
		t.set_color("icon_hover_color", cls, Color.WHITE)
		t.set_color("icon_pressed_color", cls, Color.WHITE)
		t.set_color("icon_hover_pressed_color", cls, Color.WHITE)
		t.set_color("icon_disabled_color", cls, TEXT_FAINT)
		t.set_constant("h_separation", cls, 6)
		t.set_constant("icon_max_width", cls, 22)

	# Botão "plano" (barras de ferramentas)
	t.set_type_variation("FlatButton", "Button")
	t.set_stylebox("normal", "FlatButton", box(Color(0, 0, 0, 0), 8))
	t.set_stylebox("hover", "FlatButton", box(Color(1, 1, 1, 0.06), 8))
	t.set_stylebox("pressed", "FlatButton", box(ACCENT_DIM, 8))
	t.set_stylebox("hover_pressed", "FlatButton", box(ACCENT_DIM, 8))
	t.set_stylebox("disabled", "FlatButton", box(Color(0, 0, 0, 0), 8))

	# Botão de destaque
	t.set_type_variation("AccentButton", "Button")
	t.set_stylebox("normal", "AccentButton", box(ACCENT, 8))
	t.set_stylebox("hover", "AccentButton", box(ACCENT_HOVER, 8))
	t.set_stylebox("pressed", "AccentButton", box(ACCENT.darkened(0.2), 8))
	t.set_stylebox("disabled", "AccentButton", box(ACCENT_DIM, 8))
	t.set_color("font_color", "AccentButton", Color.WHITE)

	t.set_type_variation("DangerButton", "Button")
	t.set_stylebox("normal", "DangerButton", box(DANGER.darkened(0.35), 8, DANGER, 1))
	t.set_stylebox("hover", "DangerButton", box(DANGER.darkened(0.2), 8, DANGER, 1))
	t.set_stylebox("pressed", "DangerButton", box(DANGER, 8))

	# Textos
	t.set_color("font_color", "Label", TEXT)
	t.set_type_variation("DimLabel", "Label")
	t.set_color("font_color", "DimLabel", TEXT_DIM)
	t.set_font_size("font_size", "DimLabel", 13)
	t.set_type_variation("TitleLabel", "Label")
	t.set_font_size("font_size", "TitleLabel", 18)
	t.set_type_variation("HeaderLabel", "Label")
	t.set_font_size("font_size", "HeaderLabel", 13)
	t.set_color("font_color", "HeaderLabel", TEXT_DIM)

	# Campos de texto
	var le := box(Color("15171c"), 6, BORDER, 1, 8, 6)
	var le_focus := box(Color("15171c"), 6, ACCENT, 1, 8, 6)
	for cls in ["LineEdit", "TextEdit", "CodeEdit"]:
		t.set_stylebox("normal", cls, le)
		t.set_stylebox("focus", cls, le_focus)
		t.set_stylebox("read_only", cls, box(PANEL, 6, BORDER, 1, 8, 6))
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_placeholder_color", cls, TEXT_FAINT)
		t.set_color("caret_color", cls, ACCENT_HOVER)
		t.set_color("selection_color", cls, ACCENT_DIM)
	t.set_color("background_color", "CodeEdit", Color("15171c"))
	t.set_color("current_line_color", "CodeEdit", Color("1d2028"))
	t.set_color("line_number_color", "CodeEdit", TEXT_FAINT)

	# Árvore e listas
	t.set_stylebox("panel", "Tree", box(Color("15171c"), 6, BORDER, 1, 4, 4))
	t.set_stylebox("focus", "Tree", empty())
	t.set_stylebox("selected", "Tree", box(ACCENT_DIM, 4))
	t.set_stylebox("selected_focus", "Tree", box(ACCENT_DIM, 4))
	t.set_stylebox("cursor", "Tree", empty())
	t.set_stylebox("cursor_unfocused", "Tree", empty())
	t.set_color("font_color", "Tree", TEXT)
	t.set_color("font_selected_color", "Tree", Color.WHITE)
	t.set_color("guide_color", "Tree", BORDER)
	t.set_constant("v_separation", "Tree", 12)
	t.set_constant("item_margin", "Tree", 18)
	t.set_constant("draw_guides", "Tree", 0)
	t.set_constant("draw_relationship_lines", "Tree", 1)
	t.set_color("relationship_line_color", "Tree", BORDER)
	t.set_stylebox("panel", "ItemList", box(Color("15171c"), 6, BORDER, 1, 4, 4))
	t.set_stylebox("selected", "ItemList", box(ACCENT_DIM, 4))
	t.set_stylebox("selected_focus", "ItemList", box(ACCENT_DIM, 4))
	t.set_stylebox("focus", "ItemList", empty())
	t.set_constant("v_separation", "ItemList", 10)

	# Abas
	t.set_stylebox("tab_selected", "TabBar", box(PANEL_3, 6, Color.TRANSPARENT, 0, 12, 8))
	t.set_stylebox("tab_unselected", "TabBar", box(Color(0, 0, 0, 0), 6, Color.TRANSPARENT, 0, 12, 8))
	t.set_stylebox("tab_hovered", "TabBar", box(PANEL_2, 6, Color.TRANSPARENT, 0, 12, 8))
	t.set_stylebox("tab_focus", "TabBar", empty())
	t.set_color("font_selected_color", "TabBar", Color.WHITE)
	t.set_color("font_unselected_color", "TabBar", TEXT_DIM)
	t.set_color("font_hovered_color", "TabBar", TEXT)

	# Menus e janelas
	t.set_stylebox("panel", "PopupMenu", box(PANEL_2, 8, BORDER, 1, 6, 6))
	t.set_stylebox("hover", "PopupMenu", box(ACCENT_DIM, 6))
	t.set_constant("v_separation", "PopupMenu", 14)
	t.set_constant("item_start_padding", "PopupMenu", 12)
	t.set_constant("item_end_padding", "PopupMenu", 12)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("panel", "PopupPanel", box(PANEL_2, 8, BORDER, 1, 8, 8))
	t.set_stylebox("panel", "TooltipPanel", box(Color("0d0e11"), 6, BORDER, 1, 8, 6))
	t.set_color("font_color", "TooltipLabel", TEXT)

	# Caixas de seleção e controles deslizantes
	for cls in ["CheckBox", "CheckButton"]:
		t.set_stylebox("normal", cls, empty(4))
		t.set_stylebox("hover", cls, empty(4))
		t.set_stylebox("pressed", cls, empty(4))
		t.set_stylebox("hover_pressed", cls, empty(4))
		t.set_stylebox("focus", cls, empty(4))
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, TEXT)
		t.set_color("font_hover_pressed_color", cls, Color.WHITE)
	var slider := box(Color("15171c"), 4, BORDER, 1, 0, 3)
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT_DIM, 4, Color.TRANSPARENT, 0, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, 4, Color.TRANSPARENT, 0, 0, 3))

	# Barras de rolagem largas para o dedo
	for cls in ["VScrollBar", "HScrollBar"]:
		var sc := box(Color(0, 0, 0, 0.0), 4, Color.TRANSPARENT, 0, 3, 3)
		t.set_stylebox("scroll", cls, sc)
		t.set_stylebox("scroll_focus", cls, sc)
		t.set_stylebox("grabber", cls, box(Color(1, 1, 1, 0.16), 4, Color.TRANSPARENT, 0, 3, 3))
		t.set_stylebox("grabber_highlight", cls, box(Color(1, 1, 1, 0.26), 4, Color.TRANSPARENT, 0, 3, 3))
		t.set_stylebox("grabber_pressed", cls, box(ACCENT, 4, Color.TRANSPARENT, 0, 3, 3))

	t.set_stylebox("separator", "HSeparator", box(BORDER, 0, Color.TRANSPARENT, 0, 0, 0))
	t.set_constant("separation", "HSeparator", 8)
	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("separation", "HBoxContainer", 6)
	t.set_constant("h_separation", "GridContainer", 6)
	t.set_constant("v_separation", "GridContainer", 6)
	_theme = t
	return t
