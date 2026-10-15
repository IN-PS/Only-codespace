class_name PSProjectBrowser
extends Control
## Tela inicial: lista de projetos locais.

signal open_project(pid: String, use_recovery: bool)

var _list: VBoxContainer
var _content: VBoxContainer
var _margin: MarginContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = PSTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	_content = PSUI.vbox(12)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_margin.add_child(_content)

	var header := PSUI.hbox(10)
	var logo := TextureRect.new()
	logo.texture = load("res://icon.svg")
	logo.custom_minimum_size = Vector2(44, 44)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(logo)
	var tv := PSUI.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := PSUI.label("Pocket Studio 3D", "TitleLabel")
	title.add_theme_font_size_override("font_size", 22)
	tv.add_child(title)
	var sub := PSUI.label("Versão %s · seus projetos ficam neste aparelho" % App.VERSION, "DimLabel", true)
	sub.custom_minimum_size.x = 0
	tv.add_child(sub)
	header.add_child(tv)
	var help := PSUI.icon_button("info", "Ajuda e sobre")
	help.pressed.connect(PSAboutDialog.open)
	header.add_child(help)
	var settings := PSUI.icon_button("settings", "Configurações")
	settings.pressed.connect(PSSettingsDialog.open)
	header.add_child(settings)
	_content.add_child(header)

	var actions := PSUI.hbox(8)
	var new_btn := PSUI.button("Novo projeto", "plus", "", "AccentButton")
	new_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_btn.pressed.connect(_new_project)
	actions.add_child(new_btn)
	var imp := PSUI.button("Importar", "import", "Importar um backup .zip")
	imp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	imp.pressed.connect(_import_backup)
	actions.add_child(imp)
	_content.add_child(actions)

	_content.add_child(PSUI.label("PROJETOS", "HeaderLabel"))
	_list = PSUI.vbox(8)
	var sc := PSUI.scroll(_list)
	_content.add_child(sc)
	_relayout()
	get_viewport().size_changed.connect(_relayout)
	refresh()


func _relayout() -> void:
	if _margin == null:
		return
	var s := App.get_ui_size()
	var side := maxf(12.0, (s.x - 720.0) * 0.5)
	_margin.add_theme_constant_override("margin_left", int(side))
	_margin.add_theme_constant_override("margin_right", int(side))
	_margin.add_theme_constant_override("margin_top", 16 + int(_safe_top()))
	_margin.add_theme_constant_override("margin_bottom", 12)


func _safe_top() -> float:
	if not App.is_mobile():
		return 0.0
	return DisplayServer.get_display_safe_area().position.y / maxf(App.ui_scale, 0.01)


func refresh() -> void:
	PSUI.clear(_list)
	var projects := PSProjectStore.list_projects()
	if projects.is_empty():
		var p := PSUI.panel()
		var v := PSUI.vbox(8)
		p.add_child(v)
		v.add_child(PSUI.label("Bem-vindo!", "TitleLabel"))
		v.add_child(PSUI.label("Crie seu primeiro projeto: escolha um modelo inicial, adicione peças com o botão +, mova com os dedos e toque em \"Testar\" para jogar o que você construiu.", "", true))
		var b := PSUI.button("Criar o primeiro projeto", "plus", "", "AccentButton")
		b.pressed.connect(_new_project)
		v.add_child(b)
		_list.add_child(p)
		return
	for info in projects:
		_list.add_child(_card(info))


func _card(info: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", PSTheme.box(PSTheme.PANEL, 12, PSTheme.BORDER, 1, 12, 10))
	var h := PSUI.hbox(8)
	card.add_child(h)
	var open_btn := Button.new()
	open_btn.theme_type_variation = "FlatButton"
	open_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	open_btn.custom_minimum_size.y = 56
	open_btn.focus_mode = Control.FOCUS_NONE
	open_btn.icon = PSIcons.get_icon("cube", 26.0, "#6aa5ff")
	var sub := "%s · %d objeto(s)" % [App.format_time(info["modified"]), info["objects"]]
	if info.get("broken", false):
		sub = "Arquivo danificado — tente abrir para usar a cópia de segurança"
	open_btn.text = "%s\n%s" % [info["name"], sub]
	open_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	open_btn.pressed.connect(func(): _open(info))
	h.add_child(open_btn)
	if info.get("recovery", false):
		var badge := PSUI.label("não salvo", "DimLabel")
		badge.add_theme_color_override("font_color", PSTheme.WARN)
		badge.tooltip_text = "Há alterações recuperáveis do salvamento automático"
		h.add_child(badge)
	var more := PSUI.icon_button("menu", "Opções do projeto")
	more.pressed.connect(func(): _project_menu(info))
	h.add_child(more)
	return card


func _open(info: Dictionary) -> void:
	var pid: String = info["id"]
	if PSProjectStore.has_recovery(pid):
		var t := FileAccess.get_modified_time(PSProjectStore.autosave_file(pid))
		var on_recover := func(): open_project.emit(pid, true)
		var on_discard := func():
			PSProjectStore.discard_recovery(pid)
			open_project.emit(pid, false)
		PSModal.choice3("Recuperar alterações?",
			"O projeto \"%s\" tem alterações não salvas de %s (o aplicativo pode ter fechado antes de salvar)." % [info["name"], App.format_time(t)],
			"Recuperar", on_recover, "Descartar", on_discard)
		return
	open_project.emit(pid, false)


func _project_menu(info: Dictionary) -> void:
	var pid: String = info["id"]
	var opts := ["Abrir", "Renomear", "Duplicar", "Exportar backup (.zip)", "Excluir"]
	PSModal.pick_list(String(info["name"]), opts, func(i): _on_project_action(i, info))


func _on_project_action(i: int, info: Dictionary) -> void:
	var pid: String = info["id"]
	match i:
		0:
			_open(info)
		1:
			PSModal.prompt("Renomear projeto", "", String(info["name"]), func(t):
				PSProjectStore.rename_project(pid, t)
				refresh())
		2:
			var new_pid := PSProjectStore.duplicate_project(pid, String(info["name"]) + " (cópia)")
			PSUI.toast("Projeto duplicado." if new_pid != "" else "Falha ao duplicar.", "ok" if new_pid != "" else "error")
			refresh()
		3:
			var path := PSProjectStore.export_backup(pid)
			if path == "":
				PSUI.toast("Falha ao gerar o backup.", "error")
			else:
				PSFileAccessHelper.offer_export(path, path.get_file())
		4:
			_confirm_delete(info)


func _confirm_delete(info: Dictionary) -> void:
	var pid: String = info["id"]
	var do_delete := func():
		PSProjectStore.delete_project(pid)
		refresh()
	PSModal.confirm("Excluir projeto", "Excluir \"%s\" e todos os seus assets e versões? Isso não pode ser desfeito." % info["name"], "Excluir", do_delete, true)


func _new_project() -> void:
	var m := PSModal.create("Novo projeto", 480.0)
	var name_edit := PSUI.line_edit("Meu jogo", "Nome do projeto")
	name_edit.max_length = PSData.MAX_NAME
	m.body.add_child(PSUI.row("Nome", name_edit, 60))
	m.body.add_child(PSUI.label("MODELO INICIAL", "HeaderLabel"))
	var group := ButtonGroup.new()
	var buttons: Array = []
	for i in PSTemplates.LIST.size():
		var t: Dictionary = PSTemplates.LIST[i]
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == 0
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s\n%s" % [t["name"], t["desc"]]
		b.custom_minimum_size.y = 54
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		m.body.add_child(b)
		buttons.append(b)
	var create := func():
		var n := name_edit.text.strip_edges()
		if n.is_empty():
			n = "Meu jogo"
		var idx := 0
		for i in buttons.size():
			if buttons[i].button_pressed:
				idx = i
		var data := PSTemplates.create(PSTemplates.LIST[idx]["key"], n)
		var pid := PSProjectStore.create_project(n, data)
		if pid == "":
			PSUI.toast("Não foi possível criar o projeto.", "error")
			return
		App.log_info("Projeto criado: %s" % n, "Projeto")
		m.close()
		open_project.emit(pid, false)
	m.add_button("Cancelar")
	m.add_button("Criar", create, "AccentButton", false)
	m.show_modal()


func _import_backup() -> void:
	var filters := PackedStringArray(["*.zip"]) if PSFileAccessHelper.uses_native_dialog() else PackedStringArray(["*.zip ; Backup do Pocket Studio"])
	PSFileAccessHelper.pick_file("Importar backup", filters, func(path: String):
		if path == "":
			return
		# Copia para a pasta temporária antes (necessário para URIs content:// do Android).
		var tmp := PSProjectStore.TMP_DIR.path_join("import_%d.zip" % Time.get_ticks_msec())
		PSProjectStore.ensure_dirs()
		if not PSFileAccessHelper.copy_file(path, tmp):
			PSModal.message("Importar backup", "Não foi possível ler o arquivo.")
			return
		var res := PSProjectStore.import_backup(tmp)
		DirAccess.remove_absolute(tmp)
		if res["ok"]:
			PSUI.toast("Backup importado: " + String(res["name"]), "ok")
			refresh()
		else:
			PSModal.message("Importar backup", String(res["error"])))


func handle_back() -> bool:
	return false
