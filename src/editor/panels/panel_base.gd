class_name PSPanel
extends VBoxContainer
## Base dos painéis do editor (Hierarquia, Propriedades, Terreno...).

var editor: PSEditor
var panel_title := ""
var panel_icon := ""
## Em retrato, abre o painel ocupando quase a tela toda (ex.: editor de código).
var prefers_maximized := false


func setup(p_editor: PSEditor) -> void:
	editor = p_editor
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_build()


## Monta os controles (chamado uma vez).
func _build() -> void:
	pass


## Painel ficou visível.
func on_shown() -> void:
	pass


func on_hidden() -> void:
	pass


func on_selection_changed() -> void:
	pass


func on_world_changed() -> void:
	pass


func on_object_updated(_id: String) -> void:
	pass
