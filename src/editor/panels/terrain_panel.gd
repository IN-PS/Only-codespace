class_name PSTerrainPanel
extends PSPanel
## Criação e edição de terreno: esculpir, pintar, montanhas, água e vegetação.

const TOOLS := [
	["raise", "Elevar"], ["lower", "Abaixar"], ["smooth", "Suavizar"], ["flatten", "Nivelar"],
	["paint", "Pintar"], ["veg_add", "Plantar"], ["veg_remove", "Remover plantas"],
]
const SIZES := [[33, "32 m"], [65, "64 m"], [129, "128 m"]]
const GENERATORS := [["flat", "Plano"], ["hills", "Colinas"], ["mountains", "Montanhas"], ["island", "Ilha"]]

var _content: VBoxContainer
var _brush_btn: Button
var _tool_buttons := {}
var _dynamic: VBoxContainer
var _new_size := 1
var _new_gen := 1


func _build() -> void:
	_content = PSUI.vbox(8)
	add_child(PSUI.scroll(_content))


func on_shown() -> void:
	_rebuild()


func on_hidden() -> void:
	editor.set_brush_active(false)


func on_world_changed() -> void:
	if is_visible_in_tree():
		_rebuild.call_deferred()


func on_brush_state() -> void:
	if _brush_btn:
		_brush_btn.set_pressed_no_signal(editor.brush["active"])
		_brush_btn.text = "Pincel ativo — toque para parar" if editor.brush["active"] else "Ativar pincel"


func _rebuild() -> void:
	PSUI.clear(_content)
	_tool_buttons.clear()
	_brush_btn = null
	var t := editor.world.terrain
	if t == null:
		_build_create()
	else:
		_build_edit(t)


func _build_create() -> void:
	_content.add_child(PSUI.label("Este mundo ainda não tem terreno.", ""))
	var size_opt := PSUI.option(SIZES.map(func(x): return x[1]), _new_size)
	size_opt.item_selected.connect(func(i): _new_size = i)
	_content.add_child(PSUI.row("Tamanho", size_opt))
	var gen_opt := PSUI.option(GENERATORS.map(func(x): return x[1]), _new_gen)
	gen_opt.item_selected.connect(func(i): _new_gen = i)
	_content.add_child(PSUI.row("Relevo", gen_opt))
	var b := PSUI.button("Criar terreno", "mountain", "", "AccentButton")
	b.pressed.connect(_create_terrain)
	_content.add_child(b)
	_content.add_child(PSUI.label("Terrenos maiores usam mais memória. Em celulares modestos, prefira 64 m.", "DimLabel", true))


func _create_terrain() -> void:
	var data := PSTerrain.new_data(SIZES[_new_size][0], GENERATORS[_new_gen][0], randi() % 100000)
	_set_terrain_undoable(data, "Criar terreno")


func _set_terrain_undoable(new_data: Variant, label: String) -> void:
	var old_data = editor.world.get_terrain_data()
	var do_call := func(): editor.world.set_terrain_data(new_data)
	var undo_call := func(): editor.world.set_terrain_data(old_data)
	editor.undo.custom(label, do_call, undo_call)
	editor.mark_changed()


func _build_edit(t: PSTerrain) -> void:
	_brush_btn = PSUI.toggle(PSUI.button("Ativar pincel", "brush", "Liga/desliga a edição do terreno com o dedo"))
	_brush_btn.toggled.connect(func(on): editor.set_brush_active(on))
	_content.add_child(_brush_btn)
	on_brush_state()

	var grid := GridContainer.new()
	grid.columns = 2
	for td in TOOLS:
		var b := PSUI.toggle(PSUI.button(td[1]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key: String = td[0]
		b.pressed.connect(func(): _select_tool(key))
		grid.add_child(b)
		_tool_buttons[key] = b
	_content.add_child(grid)

	var radius := PSUI.slider(1.0, 20.0, 0.5, float(editor.brush["radius"]), "%.1f m")
	PSUI.get_slider(radius).value_changed.connect(func(v): editor.brush["radius"] = v)
	_content.add_child(PSUI.row("Raio", radius))
	var strength := PSUI.slider(0.05, 1.0, 0.05, float(editor.brush["strength"]))
	PSUI.get_slider(strength).value_changed.connect(func(v): editor.brush["strength"] = v)
	_content.add_child(PSUI.row("Força", strength))

	_dynamic = PSUI.vbox(6)
	_content.add_child(_dynamic)
	_select_tool(String(editor.brush["tool"]))

	_content.add_child(PSUI.separator())
	_content.add_child(PSUI.label("GERAR", "HeaderLabel"))
	var gen_row := PSUI.hbox(6)
	var mount := PSUI.button("Montanhas", "mountain")
	mount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mount.pressed.connect(func(): _generate("mountains"))
	gen_row.add_child(mount)
	var hills := PSUI.button("Colinas")
	hills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hills.pressed.connect(func(): _generate("hills"))
	gen_row.add_child(hills)
	_content.add_child(gen_row)
	var row2 := PSUI.hbox(6)
	var island := PSUI.button("Ilha")
	island.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	island.pressed.connect(func(): _generate("island"))
	row2.add_child(island)
	var flat := PSUI.button("Aplainar tudo")
	flat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flat.pressed.connect(func(): _generate("flat"))
	row2.add_child(flat)
	_content.add_child(row2)
	var auto := PSUI.button("Pintura automática (altura e inclinação)", "palette")
	auto.pressed.connect(_auto_paint)
	_content.add_child(auto)
	var water := PSUI.button("Adicionar água", "water")
	water.pressed.connect(_add_water)
	_content.add_child(water)

	_content.add_child(PSUI.separator())
	_content.add_child(PSUI.label("Tamanho: %d m × %d m · Vegetação: %d" % [t.size - 1, t.size - 1, t.count_vegetation()], "DimLabel"))
	var del := PSUI.button("Remover terreno", "trash", "", "DangerButton")
	del.pressed.connect(func(): PSModal.confirm("Remover terreno", "O terreno e a vegetação serão removidos. Você pode desfazer depois.", "Remover", func(): _set_terrain_undoable(null, "Remover terreno"), true))
	_content.add_child(del)


func _select_tool(key: String) -> void:
	editor.brush["tool"] = key
	for k in _tool_buttons:
		_tool_buttons[k].set_pressed_no_signal(k == key)
	if _dynamic == null:
		return
	PSUI.clear(_dynamic)
	match key:
		"paint":
			_dynamic.add_child(PSUI.label("SUPERFÍCIE", "HeaderLabel"))
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 6)
			flow.add_theme_constant_override("v_separation", 6)
			for sk in PSTerrain.SURFACES:
				var s: Dictionary = PSTerrain.SURFACES[sk]
				var b := PSUI.toggle(PSUI.button(s["label"]), editor.brush["surface"] == sk)
				var c: Color = s["color"]
				b.add_theme_stylebox_override("normal", PSTheme.box(c.darkened(0.45), 8, c, 2))
				b.add_theme_stylebox_override("pressed", PSTheme.box(c.darkened(0.15), 8, Color.WHITE, 2))
				var surf: String = sk
				b.pressed.connect(func():
					editor.brush["surface"] = surf
					for other in flow.get_children():
						other.set_pressed_no_signal(other == b))
				flow.add_child(b)
			_dynamic.add_child(flow)
		"veg_add", "veg_remove":
			var kinds: Array = PSTerrain.VEG_KINDS.keys()
			var labels: Array = kinds.map(func(k): return PSTerrain.VEG_KINDS[k]["label"])
			var opt := PSUI.option(labels, maxi(0, kinds.find(editor.brush["veg_kind"])))
			opt.item_selected.connect(func(i): editor.brush["veg_kind"] = kinds[i])
			_dynamic.add_child(PSUI.row("Tipo", opt))
			if key == "veg_add":
				var dens := PSUI.slider(0.2, 4.0, 0.1, float(editor.brush["density"]), "%.1f")
				PSUI.get_slider(dens).value_changed.connect(func(v): editor.brush["density"] = v)
				_dynamic.add_child(PSUI.row("Densidade", dens))
			_dynamic.add_child(PSUI.label("Árvores, pinheiros e rochas têm colisão no jogo; arbustos e capim não.", "DimLabel", true))
		"flatten":
			_dynamic.add_child(PSUI.label("Nivela na altura do ponto onde o dedo tocou primeiro.", "DimLabel", true))


func _terrain_action(label: String, mutate: Callable) -> void:
	var t := editor.world.terrain
	if t == null:
		return
	var before := t.snapshot()
	mutate.call(t)
	t.rebuild_all()
	var after := t.snapshot()
	var redo_call := func():
		if editor.world.terrain:
			editor.world.terrain.restore(after)
	var undo_call := func():
		if editor.world.terrain:
			editor.world.terrain.restore(before)
	editor.undo.custom(label, redo_call, undo_call, false)
	_rebuild()


func _generate(kind: String) -> void:
	var seed_value := randi() % 100000
	_terrain_action("Gerar terreno", func(t: PSTerrain): _apply_generator(t, kind, seed_value))


func _apply_generator(t: PSTerrain, kind: String, seed_value: int) -> void:
	match kind:
		"mountains":
			t.generate_noise(22.0, 0.02, seed_value, false)
		"hills":
			t.generate_noise(6.0, 0.03, seed_value, false)
		"island":
			t.generate_noise(10.0, 0.035, seed_value, true)
		"flat":
			t.heights.fill(0.0)
	if kind != "flat":
		t.auto_paint()
	t._update_veg_heights_in(Rect2i(0, 0, t.size, t.size))


func _auto_paint() -> void:
	_terrain_action("Pintura automática", func(t: PSTerrain): t.auto_paint())


func _add_water() -> void:
	var t := editor.world.terrain
	var size := float(t.size - 1) * 1.5 if t else 64.0
	var d := PSData.new_object("water")
	d["id"] = App.new_id("o")
	d["name"] = editor.world.make_unique_name("Água")
	d["size"] = [size, 4.0, size]
	d["pos"] = PSData.v3_to_arr(t.global_position if t else Vector3.ZERO)
	editor.add_objects([d], "Adicionar água")
