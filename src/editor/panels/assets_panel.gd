class_name PSAssetsPanel
extends PSPanel
## Biblioteca de assets: modelos internos (CC0) e arquivos importados pelo usuário.

var _search: LineEdit
var _filter: OptionButton
var _list: VBoxContainer
var _details: VBoxContainer
var _selected := ""          # "prefab:<chave>" ou id de asset
var _preview: PSModelPreview

const FILTERS := ["Tudo", "Biblioteca interna", "Meus modelos", "Minhas texturas"]


func _build() -> void:
	var imp := PSUI.hbox(6)
	var im := PSUI.button("Modelo", "import", "Importar modelo GLB ou glTF")
	im.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	im.pressed.connect(func(): _start_import("model"))
	imp.add_child(im)
	var it := PSUI.button("Textura", "image", "Importar textura PNG, JPG ou WebP")
	it.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	it.pressed.connect(func(): _start_import("texture"))
	imp.add_child(it)
	add_child(imp)
	var sr := PSUI.hbox(6)
	_search = PSUI.line_edit("", "Buscar assets…")
	_search.right_icon = PSIcons.get_icon("search", 18.0, "#9aa1b2")
	_search.text_changed.connect(func(_t): _refresh_list())
	sr.add_child(_search)
	_filter = PSUI.option(FILTERS)
	_filter.size_flags_horizontal = Control.SIZE_FILL
	_filter.custom_minimum_size.x = 120
	_filter.item_selected.connect(func(_i): _refresh_list())
	sr.add_child(_filter)
	add_child(sr)
	var body := PSUI.vbox(8)
	add_child(PSUI.scroll(body))
	_details = PSUI.vbox(6)
	body.add_child(_details)
	_list = PSUI.vbox(4)
	body.add_child(_list)
	editor.assets.library_changed.connect(_on_library_changed)


func _on_library_changed() -> void:
	if is_visible_in_tree():
		_refresh_list()


func on_shown() -> void:
	_refresh_list()
	_show_details()


func on_hidden() -> void:
	if _preview:
		_preview.set_model(null)


func _refresh_list() -> void:
	PSUI.clear(_list)
	var q := _search.text.strip_edges().to_lower()
	var f := _filter.selected
	var count := 0
	if f == 0 or f == 1:
		_list.add_child(PSUI.label("BIBLIOTECA INTERNA (CC0)", "HeaderLabel"))
		for e in PSPrefabs.CATALOG:
			if q != "" and not (String(e["name"]).to_lower().contains(q) or String(e["tags"]).contains(q)):
				continue
			_list.add_child(_row("prefab:" + e["key"], "box", e["name"], "Peças prontas · CC0"))
			count += 1
	if f == 0 or f == 2:
		var models := editor.assets.list("model", q)
		_list.add_child(PSUI.label("MEUS MODELOS (%d)" % models.size(), "HeaderLabel"))
		for e in models:
			var st: Dictionary = e.get("stats", {})
			_list.add_child(_row(e["id"], "cube", e["name"], "%s · %s vért. · %s" % [App.format_bytes(int(e["size"])), st.get("vertices", "?"), e["license"]]))
			count += 1
		if models.is_empty() and q == "":
			_list.add_child(PSUI.label("Nenhum modelo importado. Toque em \"Modelo\" para importar um arquivo GLB.", "DimLabel", true))
	if f == 0 or f == 3:
		var texs := editor.assets.list("texture", q)
		_list.add_child(PSUI.label("MINHAS TEXTURAS (%d)" % texs.size(), "HeaderLabel"))
		for e in texs:
			var st: Dictionary = e.get("stats", {})
			_list.add_child(_row(e["id"], "image", e["name"], "%dx%d · %s · %s" % [int(st.get("width", 0)), int(st.get("height", 0)), App.format_bytes(int(e["size"])), e["license"]]))
			count += 1
	if count == 0 and q != "":
		_list.add_child(PSUI.label("Nada encontrado para \"%s\"." % q, "DimLabel"))


func _row(key: String, icon: String, title: String, subtitle: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 52)
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.button_pressed = key == _selected
	b.icon = PSIcons.get_icon(icon, 22.0, "#9aa1b2")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = "%s\n%s" % [title, subtitle]
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(func():
		_selected = key
		_show_details()
		_refresh_list())
	return b


func _show_details() -> void:
	PSUI.clear(_details)
	_preview = null
	if _selected == "":
		return
	if _selected.begins_with("prefab:"):
		var key := _selected.substr(7)
		_details.add_child(PSUI.label(PSPrefabs.display_name(key), "TitleLabel"))
		_details.add_child(PSUI.label("Licença: %s · Origem: %s" % [PSPrefabs.LICENSE, PSPrefabs.ORIGIN], "DimLabel", true))
		var ins := PSUI.button("Inserir no mundo", "plus", "", "AccentButton")
		ins.pressed.connect(func(): editor.add_prefab(key))
		_details.add_child(ins)
		_details.add_child(PSUI.separator())
		return
	var e := editor.assets.get_entry(_selected)
	if e.is_empty():
		_selected = ""
		return
	_details.add_child(PSUI.label(String(e["name"]), "TitleLabel"))
	if e["type"] == "model":
		_preview = PSModelPreview.new()
		_details.add_child(_preview)
		if editor.assets.load_model_now(_selected):
			_preview.set_model(editor.assets.instantiate_model(_selected))
		else:
			var err := PSUI.label("Não foi possível carregar: " + editor.assets.get_error(_selected), "", true)
			err.add_theme_color_override("font_color", PSTheme.DANGER)
			_details.add_child(err)
		var st: Dictionary = e.get("stats", {})
		_details.add_child(PSUI.label("%s malhas · %s vértices · %s triângulos · %s materiais" % [st.get("meshes", "?"), st.get("vertices", "?"), st.get("triangles", "?"), st.get("materials", "?")], "DimLabel", true))
	else:
		var tex := editor.assets.get_texture(_selected)
		if tex:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.custom_minimum_size = Vector2(0, 140)
			_details.add_child(tr)
	_details.add_child(PSUI.label("Arquivo original: %s · Importado em %s" % [e.get("original_name", ""), App.format_time(float(e.get("imported", 0)))], "DimLabel", true))
	_details.add_child(PSUI.label("Licença: %s" % e.get("license", ""), ""))
	if String(e.get("author", "")) != "":
		_details.add_child(PSUI.label("Autor: %s" % e["author"], "DimLabel", true))
	if String(e.get("origin", "")) != "":
		_details.add_child(PSUI.label("Origem: %s" % e["origin"], "DimLabel", true))
	var actions := PSUI.hbox(6)
	if e["type"] == "model":
		var ins := PSUI.button("Inserir", "plus", "", "AccentButton")
		ins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var aid: String = _selected
		ins.pressed.connect(func(): editor.add_model(aid))
		actions.add_child(ins)
	else:
		var ap := PSUI.button("Aplicar à seleção", "palette", "", "AccentButton")
		ap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tid: String = _selected
		ap.pressed.connect(func(): _apply_texture(tid))
		actions.add_child(ap)
	var info := PSUI.icon_button("text", "Editar informações", false)
	info.pressed.connect(func(): _edit_info(e))
	actions.add_child(info)
	var del := PSUI.icon_button("trash", "Excluir asset", false)
	del.pressed.connect(func(): _delete_asset(e))
	actions.add_child(del)
	_details.add_child(actions)
	_details.add_child(PSUI.separator())


func _apply_texture(tex_id: String) -> void:
	var ids: Array = []
	for id in editor.selection:
		if editor.world.get_obj(id).type == "part":
			ids.append(id)
	if ids.is_empty():
		PSUI.toast("Selecione peças na vista para aplicar a textura.", "info", 2.0)
		return
	editor.edit_objects(ids, func(x): x["mat"]["tex"] = tex_id, "Textura")
	PSUI.toast("Textura aplicada a %d peça(s)." % ids.size(), "ok", 1.5)


func _usage_count(asset_id: String) -> int:
	var n := 0
	for obj in editor.world.objects.values():
		if obj.type == "model" and obj.data.get("asset", "") == asset_id:
			n += 1
		elif obj.data.has("mat") and obj.data["mat"].get("tex", "") == asset_id:
			n += 1
	return n


func _delete_asset(e: Dictionary) -> void:
	var used := _usage_count(e["id"])
	if used > 0:
		PSModal.message("Asset em uso", "\"%s\" é usado por %d objeto(s). Remova ou troque esses objetos antes de excluir o asset." % [e["name"], used])
		return
	var do_delete := func():
		editor.assets.remove_asset(e["id"])
		_selected = ""
		editor.mark_changed()
		_show_details()
		_refresh_list()
	PSModal.confirm("Excluir asset", "Excluir \"%s\" do projeto? O arquivo será apagado (não pode ser desfeito)." % e["name"], "Excluir", do_delete, true)


## Formulário de informações (licença/origem/autor).
func _info_form(m: PSModal, defaults: Dictionary) -> Dictionary:
	var name_edit := PSUI.line_edit(String(defaults.get("name", "")), "Nome no projeto")
	name_edit.max_length = PSData.MAX_NAME
	m.body.add_child(PSUI.row("Nome", name_edit, 70))
	var lic_idx := PSAssetLibrary.LICENSES.find(defaults.get("license", "Desconhecida"))
	var lic := PSUI.option(PSAssetLibrary.LICENSES, lic_idx if lic_idx >= 0 else PSAssetLibrary.LICENSES.size() - 1)
	m.body.add_child(PSUI.row("Licença", lic, 70))
	var author := PSUI.line_edit(String(defaults.get("author", "")), "Quem criou (opcional)")
	m.body.add_child(PSUI.row("Autor", author, 70))
	var origin := PSUI.line_edit(String(defaults.get("origin", "")), "Site ou fonte (opcional)")
	origin.max_length = 200
	m.body.add_child(PSUI.row("Origem", origin, 70))
	return {"name": name_edit, "license": lic, "author": author, "origin": origin}


func _read_form(f: Dictionary) -> Dictionary:
	return {
		"name": (f["name"] as LineEdit).text.strip_edges(),
		"license": PSAssetLibrary.LICENSES[(f["license"] as OptionButton).selected],
		"author": (f["author"] as LineEdit).text.strip_edges(),
		"origin": (f["origin"] as LineEdit).text.strip_edges(),
	}


func _edit_info(e: Dictionary) -> void:
	var m := PSModal.create("Informações do asset")
	var f := _info_form(m, e)
	m.add_button("Cancelar")
	var on_save := func():
		editor.assets.update_info(e["id"], _read_form(f))
		editor.mark_changed()
		_show_details()
	m.add_button("Salvar", on_save, "AccentButton")
	m.show_modal()


func _start_import(kind: String) -> void:
	var filters := PackedStringArray(["*.glb, *.gltf ; Modelos 3D (glTF 2.0)"]) if kind == "model" else PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Imagens"])
	if PSFileAccessHelper.uses_native_dialog():
		filters = PackedStringArray(["*.glb", "*.gltf"]) if kind == "model" else PackedStringArray(["*.png", "*.jpg", "*.jpeg", "*.webp"])
	PSFileAccessHelper.pick_file("Importar " + ("modelo" if kind == "model" else "textura"), filters, func(path: String):
		if path != "":
			_confirm_import(path))


func _confirm_import(path: String) -> void:
	var original := PSFileAccessHelper.display_name(path)
	var m := PSModal.create("Importar asset")
	m.add_text("Arquivo: %s\nInforme a licença e a origem para saber depois se você pode publicar o jogo com este asset." % original)
	var f := _info_form(m, {"name": original.get_basename(), "license": "Desconhecida"})
	m.add_button("Cancelar")
	var on_import := func():
		var res := editor.assets.import_file(path, original, _read_form(f))
		if res["ok"]:
			_selected = res["entry"]["id"]
			editor.mark_changed()
			_refresh_list()
			_show_details()
			PSUI.toast("Importado: " + String(res["entry"]["name"]), "ok")
		else:
			App.log_error("Importação recusada: " + String(res["error"]), "Assets")
			PSModal.message("Não foi possível importar", String(res["error"]))
	m.add_button("Importar", on_import, "AccentButton")
	m.show_modal()
