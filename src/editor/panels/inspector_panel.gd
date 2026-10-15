class_name PSInspectorPanel
extends PSPanel
## Propriedades do objeto selecionado: nome, transformação por coordenadas,
## forma, material, física, luz, texto e opções.

var _content: VBoxContainer
var _scroll: ScrollContainer
var _pos_fields: Array = []
var _rot_fields: Array = []
var _size_fields: Array = []
var _current_id := ""
var _dirty_rebuild := false
var _sections_state := {}


func _build() -> void:
	_content = PSUI.vbox(8)
	_scroll = PSUI.scroll(_content)
	add_child(_scroll)


func on_shown() -> void:
	_rebuild()


func on_selection_changed() -> void:
	if is_visible_in_tree():
		_rebuild()
	else:
		_dirty_rebuild = true


func on_world_changed() -> void:
	if is_visible_in_tree() and not _editing():
		_rebuild.call_deferred()


func on_object_updated(id: String) -> void:
	if id == _current_id and is_visible_in_tree() and not _editing():
		refresh_transform()


func _editing() -> bool:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return f != null and is_ancestor_of(f)


func _rebuild() -> void:
	_dirty_rebuild = false
	var scroll_v := _scroll.scroll_vertical
	PSUI.clear(_content)
	_pos_fields.clear()
	_rot_fields.clear()
	_size_fields.clear()
	var sel: Array = editor.selection
	if sel.is_empty():
		_current_id = ""
		_content.add_child(PSUI.label("Nenhum objeto selecionado.", "DimLabel"))
		_content.add_child(PSUI.label("Toque em um objeto na vista 3D ou na Hierarquia para editar as propriedades dele.", "DimLabel", true))
		return
	if sel.size() > 1:
		_current_id = ""
		_build_multi(sel)
		return
	_current_id = sel[0]
	var obj := editor.world.get_obj(_current_id)
	if obj == null:
		return
	_build_single(obj)
	_scroll.set_deferred("scroll_vertical", scroll_v)


func _section(title: String, key: String) -> PSSection:
	var s := PSSection.create(title, _sections_state.get(key, true))
	s.toggled.connect(func(on): _sections_state[key] = on)
	_content.add_child(s)
	return s


# --------------------------------------------------------------------------
# Um objeto
# --------------------------------------------------------------------------

func _build_single(obj: PSWorld.PSObject) -> void:
	var id := obj.id
	var d: Dictionary = obj.data
	var head := PSUI.hbox(6)
	var name_edit := PSUI.line_edit(String(d.get("name", "")), "Nome")
	name_edit.max_length = PSData.MAX_NAME
	var commit_name := func(_t = ""):
		var t := name_edit.text.strip_edges()
		if t != "" and t != String(editor.world.get_obj(id).data.get("name", "")):
			editor.edit_objects([id], func(x): x["name"] = t, "Renomear")
	name_edit.text_submitted.connect(commit_name)
	name_edit.focus_exited.connect(commit_name)
	head.add_child(name_edit)
	_content.add_child(head)
	var type_text := PSData.TYPE_LABELS.get(obj.type, obj.type) as String
	if obj.type == "part":
		type_text += " · " + PSData.SHAPE_LABELS.get(d.get("shape", "box"), "")
	_content.add_child(PSUI.label(type_text, "DimLabel"))

	# Transformação
	var tr := _section("TRANSFORMAÇÃO", "transform")
	_pos_fields = _vec_row(tr.content, "Posição", 0.1, 2, func(axis, v): _set_pos(id, axis, v), func(): editor.commit_preview("Mover"))
	_rot_fields = _vec_row(tr.content, "Rotação °", 1.0, 1, func(axis, v): _set_rot(id, axis, v), func(): editor.commit_preview("Girar"))
	if d.has("size"):
		var label := "Escala" if obj.type in ["model", "text"] else "Tamanho"
		_size_fields = _vec_row(tr.content, label, 0.05, 2, func(axis, v): _set_obj_size(id, axis, v), func(): editor.commit_preview("Redimensionar"))
		for f in _size_fields:
			f.min_value = PSData.MIN_SIZE
			f.max_value = PSData.MAX_SIZE
	refresh_transform()

	match obj.type:
		"part":
			_build_shape(id, d)
			_build_material(id, d, true)
			_build_physics(id, d)
		"model":
			_build_model_info(id, d)
			_build_physics(id, d)
		"text":
			_build_text(id, d)
			_build_material(id, d, false)
		"water":
			_build_water(id, d)
		"light":
			_build_light(id, d)
		"spawn":
			_content.add_child(PSUI.label("O jogador começa aqui no modo de teste, olhando na direção da seta.", "DimLabel", true))
		"group":
			var n := editor.world.get_children_ids(id).size()
			_content.add_child(PSUI.label("Grupo com %d objeto(s). Mover ou girar o grupo leva todos juntos." % n, "DimLabel", true))
	_build_flags(id, obj)
	_build_extra_sections(id, obj)


## Gancho para seções adicionais (ex.: script do objeto).
func _build_extra_sections(id: String, obj: PSWorld.PSObject) -> void:
	PSScriptsPanel.build_inspector_section(self, _content, id, obj)


func _vec_row(parent: Control, label: String, step: float, decimals: int, on_change: Callable, on_commit: Callable) -> Array:
	parent.add_child(PSUI.label(label, "HeaderLabel"))
	var h := PSUI.hbox(4)
	var fields: Array = []
	var axes := [["X", PSTheme.AXIS_X], ["Y", PSTheme.AXIS_Y], ["Z", PSTheme.AXIS_Z]]
	for i in 3:
		var f := PSNumberField.create(axes[i][0], axes[i][1], step, decimals)
		var axis := i
		f.value_changed.connect(func(v): on_change.call(axis, v))
		f.value_committed.connect(func(_v): on_commit.call())
		h.add_child(f)
		fields.append(f)
	parent.add_child(h)
	return fields


func refresh_transform() -> void:
	if _current_id == "" or not editor.world.has_object(_current_id):
		return
	var obj := editor.world.get_obj(_current_id)
	var p := obj.node.position
	var e := obj.node.basis.get_euler() * (180.0 / PI)
	for i in _pos_fields.size():
		_pos_fields[i].set_value(p[i])
	for i in _rot_fields.size():
		_rot_fields[i].set_value(snappedf(e[i], 0.1))
	if not _size_fields.is_empty():
		var s := PSData.arr_to_v3(obj.data.get("size"), Vector3.ONE)
		for i in 3:
			_size_fields[i].set_value(s[i])


func _set_pos(id: String, axis: int, v: float) -> void:
	editor.preview_objects([id], func(d):
		var p := PSData.arr_to_v3(d["pos"])
		p[axis] = v
		d["pos"] = PSData.v3_to_arr(p))


func _set_rot(id: String, axis: int, v: float) -> void:
	editor.preview_objects([id], func(d):
		var e := Basis(PSData.arr_to_quat(d["rot"])).get_euler() * (180.0 / PI)
		e[axis] = v
		d["rot"] = PSData.quat_to_arr(Quaternion.from_euler(e * (PI / 180.0))))


func _set_obj_size(id: String, axis: int, v: float) -> void:
	editor.preview_objects([id], func(d):
		var s := PSData.arr_to_v3(d["size"], Vector3.ONE)
		s[axis] = maxf(v, PSData.MIN_SIZE)
		d["size"] = PSData.v3_to_arr(s))


func _build_shape(id: String, d: Dictionary) -> void:
	var sec := _section("FORMA", "shape")
	var labels: Array = []
	for s in PSData.SHAPES:
		labels.append(PSData.SHAPE_LABELS[s])
	var opt := PSUI.option(labels, PSData.SHAPES.find(d.get("shape", "box")))
	opt.item_selected.connect(func(i): editor.edit_objects([id], func(x): x["shape"] = PSData.SHAPES[i], "Forma"))
	sec.content.add_child(PSUI.row("Forma", opt))


func _build_material(ids_or_id: Variant, d: Dictionary, allow_texture: bool) -> void:
	var ids: Array = ids_or_id if ids_or_id is Array else [ids_or_id]
	var sec := _section("APARÊNCIA", "material")
	var mat: Dictionary = d.get("mat", PSData.default_material())
	var color := PSData.arr_to_color(mat.get("color"))
	var cb := PSUI.color_button(color, true)
	cb.color_changed.connect(func(c): editor.preview_objects(ids, func(x): x["mat"]["color"] = PSData.color_to_arr(c)))
	cb.popup_closed.connect(func(): editor.commit_preview("Cor"))
	sec.content.add_child(PSUI.row("Cor", cb))
	# Paleta rápida (um toque).
	var swatches := HFlowContainer.new()
	swatches.add_theme_constant_override("h_separation", 4)
	swatches.add_theme_constant_override("v_separation", 4)
	for hex in ["f2f2f2", "9e9e9e", "424242", "ef5350", "ff9800", "ffd54f", "66bb6a", "26a69a", "42a5f5", "5c6bc0", "ab47bc", "8d6e63"]:
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(34, 34)
		sw.focus_mode = Control.FOCUS_NONE
		var c := Color(hex)
		var sb := PSTheme.box(c, 6, PSTheme.BORDER, 1)
		sw.add_theme_stylebox_override("normal", sb)
		sw.add_theme_stylebox_override("hover", PSTheme.box(c.lightened(0.15), 6, Color.WHITE, 1))
		sw.add_theme_stylebox_override("pressed", PSTheme.box(c, 6, Color.WHITE, 2))
		sw.tooltip_text = "#" + hex
		sw.pressed.connect(func():
			cb.color = Color(c.r, c.g, c.b, cb.color.a)
			editor.edit_objects(ids, func(x): x["mat"]["color"] = PSData.color_to_arr(Color(c.r, c.g, c.b, PSData.arr_to_color(x["mat"]["color"]).a)), "Cor"))
		swatches.add_child(sw)
	sec.content.add_child(swatches)
	_mat_slider(sec, ids, "Metal", "metal", 0.0, 1.0, 0.05, float(mat.get("metal", 0.0)))
	_mat_slider(sec, ids, "Aspereza", "rough", 0.0, 1.0, 0.05, float(mat.get("rough", 0.8)))
	_mat_slider(sec, ids, "Brilho", "emit", 0.0, 8.0, 0.1, float(mat.get("emit", 0.0)))
	if allow_texture:
		var tex_id := String(mat.get("tex", ""))
		var tex_name := "Nenhuma"
		if tex_id != "":
			var e := editor.assets.get_entry(tex_id)
			tex_name = String(e.get("name", "(ausente)"))
		var tb := PSUI.button(tex_name, "image", "Escolher textura")
		tb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tb.pressed.connect(func(): _choose_texture(ids))
		sec.content.add_child(PSUI.row("Textura", tb))
		if tex_id != "":
			_mat_slider(sec, ids, "Repetição", "uv", 0.1, 20.0, 0.1, float(mat.get("uv", 1.0)))


func _mat_slider(sec: PSSection, ids: Array, label: String, key: String, lo: float, hi: float, step: float, value: float) -> void:
	var h := PSUI.slider(lo, hi, step, value)
	var s := PSUI.get_slider(h)
	s.value_changed.connect(func(v): editor.preview_objects(ids, func(x): x["mat"][key] = v))
	s.drag_ended.connect(func(_changed): editor.commit_preview(label))
	sec.content.add_child(PSUI.row(label, h))


func _choose_texture(ids: Array) -> void:
	var list := editor.assets.list("texture")
	var names: Array = ["Nenhuma"]
	for e in list:
		names.append(String(e["name"]))
	if list.is_empty():
		names.append("(importe texturas na aba Assets)")
	PSModal.pick_list("Textura", names, func(i):
		if i == 0:
			editor.edit_objects(ids, func(x): x["mat"]["tex"] = "", "Textura")
		elif i - 1 < list.size():
			var tid: String = list[i - 1]["id"]
			editor.edit_objects(ids, func(x): x["mat"]["tex"] = tid, "Textura")
		_rebuild())


func _build_physics(ids_or_id: Variant, d: Dictionary) -> void:
	var ids: Array = ids_or_id if ids_or_id is Array else [ids_or_id]
	var sec := _section("FÍSICA", "physics")
	var phys: Dictionary = d.get("phys", PSData.default_physics())
	var labels: Array = []
	for m in PSData.PHYS_MODES:
		labels.append(PSData.PHYS_LABELS[m])
	var opt := PSUI.option(labels, PSData.PHYS_MODES.find(phys.get("mode", "static")))
	opt.item_selected.connect(func(i):
		editor.edit_objects(ids, func(x): x["phys"]["mode"] = PSData.PHYS_MODES[i], "Física")
		_rebuild())
	sec.content.add_child(PSUI.row("Tipo", opt))
	var mode := String(phys.get("mode", "static"))
	if mode == "dynamic":
		var mf := PSNumberField.create("kg", PSTheme.PANEL_3, 0.1, 2)
		mf.min_value = 0.01
		mf.max_value = 10000.0
		mf.set_value(float(phys.get("mass", 1.0)))
		mf.value_committed.connect(func(v): editor.edit_objects(ids, func(x): x["phys"]["mass"] = v, "Massa"))
		sec.content.add_child(PSUI.row("Massa", mf))
	if mode != "none":
		for p in [["Atrito", "friction"], ["Quique", "bounce"]]:
			var h := PSUI.slider(0.0, 1.0, 0.05, float(phys.get(p[1], 0.6 if p[1] == "friction" else 0.0)))
			var key: String = p[1]
			var lbl: String = p[0]
			PSUI.get_slider(h).drag_ended.connect(func(_c): editor.edit_objects(ids, func(x): x["phys"][key] = PSUI.get_slider(h).value, lbl))
			sec.content.add_child(PSUI.row(lbl, h))
	var hint := {
		"static": "Não se move; o jogador pode ficar em cima.",
		"dynamic": "Cai com a gravidade, colide e pode ser empurrado.",
		"kinematic": "Só se move por script; carrega o jogador (plataformas móveis).",
		"none": "Atravessável. Útil para decoração e áreas de gatilho.",
	}
	sec.content.add_child(PSUI.label(hint.get(mode, ""), "DimLabel", true))


func _build_model_info(_id: String, d: Dictionary) -> void:
	var sec := _section("MODELO", "model")
	var e := editor.assets.get_entry(String(d.get("asset", "")))
	if e.is_empty():
		sec.content.add_child(PSUI.label("Asset ausente no projeto.", "DimLabel"))
		return
	sec.content.add_child(PSUI.label(String(e["name"]), ""))
	var st: Dictionary = e.get("stats", {})
	sec.content.add_child(PSUI.label("%s vértices · %s · Licença: %s" % [st.get("vertices", "?"), App.format_bytes(int(e.get("size", 0))), e.get("license", "?")], "DimLabel", true))
	if String(e.get("origin", "")) != "":
		sec.content.add_child(PSUI.label("Origem: " + String(e["origin"]), "DimLabel", true))
	var err := editor.assets.get_error(String(d.get("asset", "")))
	if err != "":
		var l := PSUI.label("Erro: " + err, "", true)
		l.add_theme_color_override("font_color", PSTheme.DANGER)
		sec.content.add_child(l)


func _build_text(id: String, d: Dictionary) -> void:
	var sec := _section("TEXTO", "text")
	var le := PSUI.line_edit(String(d.get("text", "")), "Texto")
	le.max_length = 200
	var commit := func(_t = ""):
		if le.text != String(editor.world.get_obj(id).data.get("text", "")):
			editor.edit_objects([id], func(x): x["text"] = le.text, "Texto")
	le.text_submitted.connect(commit)
	le.focus_exited.connect(commit)
	sec.content.add_child(le)


func _build_water(id: String, d: Dictionary) -> void:
	var sec := _section("ÁGUA", "water")
	var mat: Dictionary = d.get("mat", {})
	var cb := PSUI.color_button(PSData.arr_to_color(mat.get("color"), Color(0.15, 0.45, 0.75, 0.7)), true)
	cb.color_changed.connect(func(c): editor.preview_objects([id], func(x): x["mat"]["color"] = PSData.color_to_arr(c)))
	cb.popup_closed.connect(func(): editor.commit_preview("Cor da água"))
	sec.content.add_child(PSUI.row("Cor", cb))
	sec.content.add_child(PSUI.label("No modo de teste o jogador nada dentro do volume (Tamanho Y = profundidade).", "DimLabel", true))


func _build_light(id: String, d: Dictionary) -> void:
	var sec := _section("LUZ", "light")
	var l: Dictionary = d.get("light", PSData.default_light())
	var kinds := ["Pontual", "Holofote"]
	var opt := PSUI.option(kinds, PSData.LIGHT_KINDS.find(l.get("kind", "point")))
	opt.item_selected.connect(func(i):
		editor.edit_objects([id], func(x): x["light"]["kind"] = PSData.LIGHT_KINDS[i], "Tipo de luz")
		_rebuild())
	sec.content.add_child(PSUI.row("Tipo", opt))
	var cb := PSUI.color_button(PSData.arr_to_color(l.get("color")))
	cb.color_changed.connect(func(c): editor.preview_objects([id], func(x): x["light"]["color"] = PSData.color_to_arr(c)))
	cb.popup_closed.connect(func(): editor.commit_preview("Cor da luz"))
	sec.content.add_child(PSUI.row("Cor", cb))
	for p in [["Intensidade", "energy", 0.0, 16.0, 0.1], ["Alcance", "range", 0.5, 60.0, 0.5]]:
		_light_slider(sec, id, p[0], p[1], p[2], p[3], p[4], float(l.get(p[1], 1.0)))
	if l.get("kind", "point") == "spot":
		_light_slider(sec, id, "Abertura °", "angle", 1.0, 89.0, 1.0, float(l.get("angle", 35.0)))
	var sh := PSUI.check("Projetar sombras (mais pesado)", bool(l.get("shadow", false)))
	sh.toggled.connect(func(on): editor.edit_objects([id], func(x): x["light"]["shadow"] = on, "Sombra da luz"))
	sec.content.add_child(sh)


func _light_slider(sec: PSSection, id: String, label: String, key: String, lo: float, hi: float, step: float, value: float) -> void:
	var h := PSUI.slider(lo, hi, step, value, "%.1f")
	var s := PSUI.get_slider(h)
	s.value_changed.connect(func(v): editor.preview_objects([id], func(x): x["light"][key] = v))
	s.drag_ended.connect(func(_c): editor.commit_preview(label))
	sec.content.add_child(PSUI.row(label, h))


func _build_flags(id: String, obj: PSWorld.PSObject) -> void:
	var sec := _section("OPÇÕES", "flags")
	var vis := PSUI.check("Visível no jogo", bool(obj.data.get("visible", true)))
	vis.toggled.connect(func(on): editor.edit_objects([id], func(x): x["visible"] = on, "Visibilidade"))
	sec.content.add_child(vis)
	var lock := PSUI.check("Travado (não seleciona tocando na vista)", bool(obj.data.get("locked", false)))
	lock.toggled.connect(func(on): editor.edit_objects([id], func(x): x["locked"] = on, "Travar"))
	sec.content.add_child(lock)
	if obj.data.has("shadow"):
		var sh := PSUI.check("Projetar sombra", bool(obj.data.get("shadow", true)))
		sh.toggled.connect(func(on): editor.edit_objects([id], func(x): x["shadow"] = on, "Sombra"))
		sec.content.add_child(sh)


# --------------------------------------------------------------------------
# Vários objetos
# --------------------------------------------------------------------------

func _build_multi(sel: Array) -> void:
	_content.add_child(PSUI.label("%d objetos selecionados" % sel.size(), "TitleLabel"))
	_content.add_child(PSUI.label("Use o gizmo para mover, girar ou escalar todos juntos. As alterações abaixo valem para todas as peças selecionadas.", "DimLabel", true))
	var parts: Array = []
	var phys_ids: Array = []
	for id in sel:
		var o := editor.world.get_obj(id)
		if o == null:
			continue
		if o.type == "part":
			parts.append(id)
		if o.type in ["part", "model"]:
			phys_ids.append(id)
	if not parts.is_empty():
		_build_material(parts, editor.world.get_obj(parts[0]).data, true)
	if not phys_ids.is_empty():
		_build_physics(phys_ids, editor.world.get_obj(phys_ids[0]).data)
	var row := PSUI.hbox(6)
	var g := PSUI.button("Agrupar", "group")
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.pressed.connect(func(): editor.group_selection())
	row.add_child(g)
	var dup := PSUI.button("Duplicar", "copy")
	dup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dup.pressed.connect(func(): editor.duplicate_selection())
	row.add_child(dup)
	_content.add_child(row)
