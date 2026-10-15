class_name PSAddMenu
extends RefCounted
## Folha "Adicionar": primitivas, objetos especiais, biblioteca e modelos importados.


static func open(editor: PSEditor) -> void:
	var m := PSModal.create("Adicionar", 520.0)
	var tabs := TabBar.new()
	tabs.add_tab("Formas")
	tabs.add_tab("Especiais")
	tabs.add_tab("Biblioteca")
	tabs.add_tab("Meus modelos")
	tabs.clip_tabs = false
	tabs.focus_mode = Control.FOCUS_NONE
	var tab_scroll := ScrollContainer.new()
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	tab_scroll.custom_minimum_size.y = 40
	tab_scroll.add_child(tabs)
	m.body.add_child(tab_scroll)
	var grid := GridContainer.new()
	var ui := App.get_ui_size()
	var cols := 3 if ui.x < 420 else 4
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var sc := PSUI.scroll(grid)
	sc.custom_minimum_size = Vector2(0, minf(ui.y * 0.55, 380.0))
	m.body.add_child(sc)
	var fill := func(tab: int):
		PSUI.clear(grid)
		match tab:
			0:
				for s in PSData.SHAPES:
					var shape: String = s
					grid.add_child(_tile(PSData.SHAPE_LABELS[s], s, func():
						editor.add_primitive("part", {"shape": shape, "size": [1.0, 2.0, 1.0] if shape == "capsule" else ([1.0, 0.25, 1.0] if shape == "torus" else [1.0, 1.0, 1.0])})
						m.close()))
				grid.add_child(_tile("Placa", "box", func():
					editor.add_primitive("part", {"shape": "box", "name": "Placa", "size": [4.0, 0.2, 4.0]})
					m.close()))
				grid.add_child(_tile("Parede", "box", func():
					editor.add_primitive("part", {"shape": "box", "name": "Parede", "size": [4.0, 3.0, 0.2]})
					m.close()))
			1:
				var specials := [["Grupo vazio", "group", "group"], ["Luz", "light", "light"], ["Água", "water", "water"], ["Texto 3D", "text", "text"], ["Ponto de início", "flag", "spawn"]]
				for sp in specials:
					var type: String = sp[2]
					grid.add_child(_tile(sp[0], sp[1], func():
						editor.add_primitive(type)
						m.close()))
			2:
				for e in PSPrefabs.CATALOG:
					var key: String = e["key"]
					grid.add_child(_tile(e["name"], "box", func():
						editor.add_prefab(key)
						m.close()))
			3:
				var models := editor.assets.list("model")
				if models.is_empty():
					var l := PSUI.label("Nenhum modelo importado ainda. Importe arquivos GLB na aba Assets.", "DimLabel", true)
					l.custom_minimum_size.x = 260
					grid.add_child(l)
				for e in models:
					var aid: String = e["id"]
					grid.add_child(_tile(String(e["name"]), "cube", func():
						editor.add_model(aid)
						m.close()))
	tabs.tab_changed.connect(fill)
	fill.call(0)
	m.add_button("Fechar")
	m.show_modal()


static func _tile(text: String, icon: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = PSIcons.get_icon(icon, 28.0)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.custom_minimum_size = Vector2(96, 84)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_constant_override("icon_max_width", 30)
	b.pressed.connect(cb)
	return b
