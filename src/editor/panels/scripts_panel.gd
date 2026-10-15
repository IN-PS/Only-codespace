class_name PSScriptsPanel
extends PSPanel
## Editor de scripts: lista, código com realce de sintaxe, verificação de erros,
## modelos prontos, anexar a objetos e referência da API.

const KEYWORDS := ["and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"]
const BUILTINS := ["self", "script", "world", "player", "ui", "shared", "vec", "rgb", "hex", "print", "warn", "time", "after", "every", "cancel", "math", "string", "table", "pairs", "ipairs", "tostring", "tonumber", "type", "pcall", "error", "assert", "select", "unpack"]
const EVENTS := ["on_start", "on_update", "on_touch", "on_leave", "on_click"]
const MEMBERS := ["position", "rotation", "size", "color", "visible", "solid", "velocity", "name", "parent", "exists", "move", "rotate", "destroy", "clone", "applyImpulse", "children", "find", "lookAt", "get", "set", "x", "y", "z", "length", "normalized", "distance", "dot", "cross", "lerp", "speed", "jumpPower", "onGround", "inWater", "respawn", "setSpawn", "cameraMode", "message", "text", "create", "findAll", "objects", "gravity", "floor", "ceil", "random", "sin", "cos", "abs", "sqrt", "min", "max", "clamp", "lerp", "format", "insert", "remove", "concat", "upper", "lower", "sub", "len"]
const QUICK_KEYS := ["( )", "\"", "=", ".", ":", "..", ",", "{ }", "[ ]", "+", "-", "*", "/", "<", ">", "~=", "#", "end", "then", "do", "local", "⇥"]

var _picker: OptionButton
var _code: CodeEdit
var _status: Label
var _attach_label: Label
var _current := ""
var _check_timer: Timer
var _save_timer: Timer
var _loading := false
var _error_line := -1


func _build() -> void:
	prefers_maximized = true
	var top := PSUI.hbox(4)
	_picker = PSUI.option([])
	_picker.item_selected.connect(func(i): _select(String(_picker.get_item_metadata(i))))
	top.add_child(_picker)
	var add := PSUI.icon_button("plus", "Novo script", false)
	add.pressed.connect(_new_script_dialog)
	top.add_child(add)
	var att := PSUI.icon_button("parent", "Anexar este script aos objetos selecionados", false)
	att.pressed.connect(_attach_to_selection)
	top.add_child(att)
	var more := PSUI.icon_button("menu", "Opções do script", false)
	more.pressed.connect(_script_menu)
	top.add_child(more)
	add_child(top)

	_attach_label = PSUI.label("", "DimLabel")
	_attach_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_attach_label.clip_text = true
	add_child(_attach_label)

	_code = CodeEdit.new()
	_code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code.gutters_draw_line_numbers = true
	_code.indent_automatic = true
	_code.indent_size = 2
	_code.indent_use_spaces = true
	_code.auto_brace_completion_enabled = true
	_code.code_completion_enabled = true
	_code.code_completion_prefixes = [".", ":"]
	_code.minimap_draw = false
	_code.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	_code.caret_blink = true
	_code.highlight_current_line = true
	_code.scroll_smooth = true
	_code.add_theme_font_size_override("font_size", 14)
	_code.syntax_highlighter = _make_highlighter()
	_code.text_changed.connect(_on_text_changed)
	_code.code_completion_requested.connect(_on_completion_requested)
	_code.placeholder_text = "Crie um script com o botão +"
	add_child(_code)

	var keys := PSUI.hbox(3)
	var keys_scroll := ScrollContainer.new()
	keys_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	keys_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	keys_scroll.custom_minimum_size.y = 36
	keys_scroll.add_child(keys)
	for k in QUICK_KEYS:
		var b := Button.new()
		b.text = k
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(36, 34)
		b.add_theme_font_size_override("font_size", 14)
		var key: String = k
		b.pressed.connect(func(): _quick_insert(key))
		keys.add_child(b)
	add_child(keys_scroll)

	var bottom := PSUI.hbox(4)
	var check := PSUI.button("Verificar", "check")
	check.pressed.connect(func(): _check(true))
	bottom.add_child(check)
	var tpl := PSUI.button("Modelos", "copy")
	tpl.pressed.connect(_insert_template_dialog)
	bottom.add_child(tpl)
	var api := PSUI.icon_button("info", "Referência da API", false)
	api.pressed.connect(PSScriptDocs.open)
	bottom.add_child(api)
	_status = PSUI.label("", "DimLabel")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bottom.add_child(_status)
	add_child(bottom)

	_check_timer = Timer.new()
	_check_timer.one_shot = true
	_check_timer.wait_time = 0.8
	_check_timer.timeout.connect(func(): _check(false))
	add_child(_check_timer)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.4
	_save_timer.timeout.connect(_store_code)
	add_child(_save_timer)


func on_shown() -> void:
	_refresh_picker()


func on_hidden() -> void:
	_store_code()


func on_world_changed() -> void:
	if is_visible_in_tree():
		_update_attach_label()


# --------------------------------------------------------------------------
# Dados
# --------------------------------------------------------------------------

func _scripts() -> Array:
	if not editor.project.has("scripts") or not (editor.project["scripts"] is Array):
		editor.project["scripts"] = []
	return editor.project["scripts"]


func _find(sid: String) -> Dictionary:
	for s in _scripts():
		if s["id"] == sid:
			return s
	return {}


func open_script(sid: String) -> void:
	editor.show_panel("scripts")
	_select(sid)


func _refresh_picker() -> void:
	_picker.clear()
	var list := _scripts()
	for i in list.size():
		var s: Dictionary = list[i]
		var label := String(s["name"])
		if s.get("global", false):
			label += "  (global)"
		if not s.get("enabled", true):
			label += "  (desativado)"
		_picker.add_item(label)
		_picker.set_item_metadata(i, s["id"])
	if list.is_empty():
		_current = ""
		_loading = true
		_code.text = ""
		_code.editable = false
		_loading = false
		_status.text = "Nenhum script. Toque em + para criar."
		_attach_label.text = ""
		return
	_code.editable = true
	if _find(_current).is_empty():
		_current = String(list[0]["id"])
	for i in list.size():
		if list[i]["id"] == _current:
			_picker.select(i)
	_load_current()


func _select(sid: String) -> void:
	_store_code()
	_current = sid
	_refresh_picker()


func _load_current() -> void:
	var s := _find(_current)
	_loading = true
	_code.text = String(s.get("code", ""))
	_code.clear_undo_history()
	_loading = false
	_update_attach_label()
	_check(false)


func _update_attach_label() -> void:
	if _current == "":
		return
	var s := _find(_current)
	if s.get("global", false):
		_attach_label.text = "Script global (roda uma vez, sem objeto)"
		return
	var n := 0
	for o in editor.world.objects.values():
		if o.data.get("script", "") == _current:
			n += 1
	_attach_label.text = "Anexado a %d objeto(s)" % n


func _on_text_changed() -> void:
	if _loading:
		return
	_save_timer.start()
	_check_timer.start()


func _store_code() -> void:
	if _current == "":
		return
	var s := _find(_current)
	if s.is_empty():
		return
	if String(s.get("code", "")) != _code.text:
		s["code"] = _code.text.substr(0, PSData.MAX_CODE)
		editor.mark_changed()


func _check(verbose: bool) -> void:
	if _error_line >= 0 and _error_line < _code.get_line_count():
		_code.set_line_background_color(_error_line, Color(0, 0, 0, 0))
	_error_line = -1
	if _current == "":
		return
	var res := PSLuaParser.parse(_code.text)
	if res["ok"]:
		_status.text = "Sem erros de sintaxe."
		_status.add_theme_color_override("font_color", PSTheme.SUCCESS)
		if verbose:
			PSUI.toast("Nenhum erro encontrado.", "ok", 1.2)
	else:
		_error_line = int(res["line"]) - 1
		_status.text = "Linha %d: %s" % [res["line"], res["error"]]
		_status.add_theme_color_override("font_color", PSTheme.DANGER)
		if _error_line >= 0 and _error_line < _code.get_line_count():
			_code.set_line_background_color(_error_line, Color(PSTheme.DANGER, 0.25))
		if verbose:
			_code.set_caret_line(maxi(_error_line, 0))
			PSModal.message("Erro de sintaxe", "Linha %d: %s" % [res["line"], res["error"]])


# --------------------------------------------------------------------------
# Ações
# --------------------------------------------------------------------------

func _new_script_dialog(attach_to: Array = []) -> void:
	var names: Array = []
	for t in PSScriptTemplates.LIST:
		names.append(t["name"])
	PSModal.pick_list("Novo script a partir de…", names, func(i):
		var t: Dictionary = PSScriptTemplates.LIST[i]
		var sid := create_script(String(t["name"]), String(t["code"]), attach_to)
		open_script(sid))


## Cria um script (com desfazer) e opcionalmente o anexa aos objetos dados.
func create_script(script_name: String, code: String, attach_to: Array = []) -> String:
	_store_code()
	var entry := {"id": App.new_id("s"), "name": _unique_name(script_name), "code": code, "enabled": true, "global": false}
	var list := _scripts()
	var do_call := func():
		if _find(entry["id"]).is_empty():
			list.append(entry)
	var undo_call := func():
		list.erase(entry)
		if _current == entry["id"]:
			_current = ""
		if is_visible_in_tree():
			_refresh_picker()
	editor.undo.custom("Novo script", do_call, undo_call)
	if not attach_to.is_empty():
		editor.edit_objects(attach_to, func(d): d["script"] = entry["id"], "Anexar script")
	return entry["id"]


func _unique_name(base: String) -> String:
	var names := {}
	for s in _scripts():
		names[s["name"]] = true
	if not names.has(base):
		return base
	var i := 2
	while names.has("%s %d" % [base, i]):
		i += 1
	return "%s %d" % [base, i]


func _script_menu() -> void:
	if _current == "":
		return
	var s := _find(_current)
	var opts := ["Renomear", "Duplicar", "Tornar global" if not s.get("global", false) else "Deixar de ser global", "Desativar" if s.get("enabled", true) else "Ativar", "Desanexar de todos os objetos", "Excluir"]
	PSModal.pick_list(String(s["name"]), opts, func(i): _on_script_action(i, s))


func _on_script_action(i: int, s: Dictionary) -> void:
	match i:
		0:
			PSModal.prompt("Renomear script", "", String(s["name"]), func(t):
				s["name"] = t
				editor.mark_changed()
				_refresh_picker())
		1:
			_store_code()
			var sid := create_script(String(s["name"]) + " (cópia)", String(s["code"]))
			_select(sid)
		2:
			s["global"] = not s.get("global", false)
			editor.mark_changed()
			_refresh_picker()
		3:
			s["enabled"] = not s.get("enabled", true)
			editor.mark_changed()
			_refresh_picker()
		4:
			_detach_all(String(s["id"]))
		5:
			_delete_current()


func _detach_all(sid: String) -> void:
	var ids: Array = []
	for id in editor.world.objects:
		if editor.world.objects[id].data.get("script", "") == sid:
			ids.append(id)
	if not ids.is_empty():
		editor.edit_objects(ids, func(d): d["script"] = "", "Desanexar script")
	_update_attach_label()


func _delete_current() -> void:
	var s := _find(_current)
	if s.is_empty():
		return
	var do_delete := func():
		_detach_all(String(s["id"]))
		var list := _scripts()
		var idx := list.find(s)
		var do_call := func():
			list.erase(s)
			_current = ""
			if is_visible_in_tree():
				_refresh_picker()
		var undo_call := func():
			if not list.has(s):
				list.insert(clampi(idx, 0, list.size()), s)
			if is_visible_in_tree():
				_refresh_picker()
		editor.undo.custom("Excluir script", do_call, undo_call)
	PSModal.confirm("Excluir script", "Excluir \"%s\"? Os objetos que o usam ficarão sem script." % s["name"], "Excluir", do_delete, true)


func _attach_to_selection() -> void:
	if _current == "":
		PSUI.toast("Crie ou escolha um script primeiro.", "info", 1.5)
		return
	if editor.selection.is_empty():
		PSUI.toast("Selecione na vista os objetos que vão usar este script.", "info", 2.0)
		return
	var sid := _current
	editor.edit_objects(editor.selection, func(d): d["script"] = sid, "Anexar script")
	_update_attach_label()
	PSUI.toast("Script anexado a %d objeto(s)." % editor.selection.size(), "ok", 1.5)


func _insert_template_dialog() -> void:
	var names: Array = []
	for t in PSScriptTemplates.LIST:
		names.append(t["name"])
	PSModal.pick_list("Inserir modelo no fim do script", names, func(i):
		if _current == "":
			var sid := create_script(String(PSScriptTemplates.LIST[i]["name"]), String(PSScriptTemplates.LIST[i]["code"]))
			_select(sid)
			return
		var code := _code.text
		if code != "" and not code.ends_with("\n"):
			code += "\n"
		_code.text = code + ("\n" if code != "" else "") + String(PSScriptTemplates.LIST[i]["code"])
		_on_text_changed())


func _quick_insert(key: String) -> void:
	if not _code.editable:
		return
	_code.grab_focus()
	match key:
		"( )":
			_code.insert_text_at_caret("()")
			_code.set_caret_column(_code.get_caret_column() - 1)
		"{ }":
			_code.insert_text_at_caret("{}")
			_code.set_caret_column(_code.get_caret_column() - 1)
		"[ ]":
			_code.insert_text_at_caret("[]")
			_code.set_caret_column(_code.get_caret_column() - 1)
		"⇥":
			_code.insert_text_at_caret("  ")
		"end", "then", "do", "local":
			_code.insert_text_at_caret(key + (" " if key != "end" else ""))
		_:
			_code.insert_text_at_caret(key)


# --------------------------------------------------------------------------
# Realce e autocompletar
# --------------------------------------------------------------------------

func _make_highlighter() -> CodeHighlighter:
	var h := CodeHighlighter.new()
	h.number_color = Color("f78c6c")
	h.symbol_color = Color("89ddff")
	h.function_color = Color("82aaff")
	h.member_variable_color = Color("e6e8ee")
	for k in KEYWORDS:
		h.add_keyword_color(k, Color("ff7ab2"))
	for b in BUILTINS:
		h.add_keyword_color(b, Color("ffcb6b"))
	for e in EVENTS:
		h.add_keyword_color(e, Color("c792ea"))
	h.add_color_region("--[[", "]]", Color("6b7283"), false)
	h.add_color_region("--", "", Color("6b7283"), true)
	h.add_color_region("\"", "\"", Color("c3e88d"), true)
	h.add_color_region("'", "'", Color("c3e88d"), true)
	h.add_color_region("[[", "]]", Color("c3e88d"), false)
	return h


func _on_completion_requested() -> void:
	var line := _code.get_line(_code.get_caret_line())
	var col := _code.get_caret_column()
	var start := col
	while start > 0 and (line[start - 1].is_valid_identifier() or line[start - 1].is_valid_int() or line[start - 1] == "_"):
		start -= 1
	var prefix := line.substr(start, col - start)
	var after_dot := start > 0 and (line[start - 1] == "." or line[start - 1] == ":")
	var words: Array = MEMBERS if after_dot else KEYWORDS + BUILTINS + EVENTS
	var seen := {}
	for w in words:
		if seen.has(w):
			continue
		seen[w] = true
		if prefix == "" or String(w).begins_with(prefix):
			var kind := CodeEdit.KIND_MEMBER if after_dot else CodeEdit.KIND_PLAIN_TEXT
			_code.add_code_completion_option(kind, w, w)
	_code.update_code_completion_options(false)


# --------------------------------------------------------------------------
# Seção "Script" do inspetor
# --------------------------------------------------------------------------

static func build_inspector_section(inspector: Node, content: Control, id: String, obj: Variant) -> void:
	var o: PSWorld.PSObject = obj
	if o.type == "spawn":
		return
	var ed: PSEditor = inspector.editor
	var panel: PSScriptsPanel = ed.panels.get("scripts")
	var sec := PSSection.create("SCRIPT", true)
	content.add_child(sec)
	var sid := String(o.data.get("script", ""))
	var current_name := "Nenhum"
	if sid != "":
		var s := panel._find(sid)
		current_name = String(s.get("name", "(ausente)"))
	var row := PSUI.hbox(6)
	var pick := PSUI.button(current_name, "code", "Escolher script")
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pick.pressed.connect(func():
		var list := panel._scripts()
		var names: Array = ["Nenhum", "Novo script a partir de modelo…"]
		for s in list:
			names.append(String(s["name"]))
		PSModal.pick_list("Script do objeto", names, func(i):
			if i == 0:
				ed.edit_objects([id], func(d): d["script"] = "", "Remover script")
			elif i == 1:
				panel._new_script_dialog([id])
			else:
				var chosen: String = list[i - 2]["id"]
				ed.edit_objects([id], func(d): d["script"] = chosen, "Anexar script")))
	row.add_child(pick)
	if sid != "" and not panel._find(sid).is_empty():
		var edit := PSUI.button("Editar", "code")
		edit.pressed.connect(func(): panel.open_script(sid))
		row.add_child(edit)
	sec.content.add_child(row)
