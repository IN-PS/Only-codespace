class_name PSConsolePanel
extends PSPanel
## Console de mensagens e erros (editor, importação e scripts).

var _log: RichTextLabel
var _filter: OptionButton
const FILTERS := ["Tudo", "Avisos e erros", "Só erros"]


func _build() -> void:
	var row := PSUI.hbox(6)
	_filter = PSUI.option(FILTERS)
	_filter.item_selected.connect(func(_i): _refresh())
	row.add_child(_filter)
	var copy := PSUI.icon_button("copy", "Copiar tudo", false)
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(_plain_text())
		PSUI.toast("Console copiado.", "ok", 1.2))
	row.add_child(copy)
	var clear := PSUI.icon_button("trash", "Limpar", false)
	clear.pressed.connect(func(): App.clear_log())
	row.add_child(clear)
	add_child(row)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_stylebox_override("normal", PSTheme.box(Color("15171c"), 6, PSTheme.BORDER, 1, 8, 6))
	_log.add_theme_font_size_override("normal_font_size", 13)
	add_child(_log)
	App.log_added.connect(_on_log_added)


func on_shown() -> void:
	_refresh()


func _on_log_added(_entry: Dictionary) -> void:
	if is_visible_in_tree():
		_refresh()


func _accept(e: Dictionary) -> bool:
	match _filter.selected:
		1:
			return int(e["level"]) >= App.LogLevel.WARN
		2:
			return int(e["level"]) == App.LogLevel.ERROR
	return true


func _line(e: Dictionary) -> String:
	var color := ["#9aa1b2", "#e3b341", "#ff7b72"][int(e["level"])] as String
	var t := Time.get_datetime_dict_from_unix_time(int(e["time"]) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	var src := ("[b]%s[/b] " % String(e["source"]).replace("[", "(")) if String(e["source"]) != "" else ""
	return "[color=#6b7283]%02d:%02d:%02d[/color] [color=%s]%s%s[/color]" % [t.hour, t.minute, t.second, color, src, String(e["msg"]).replace("[", "[lb]")]


func _refresh() -> void:
	var lines: PackedStringArray = []
	for e in App.log_entries:
		if _accept(e):
			lines.append(_line(e))
	_log.text = "\n".join(lines) if not lines.is_empty() else "[color=#6b7283]Sem mensagens.[/color]"


func _plain_text() -> String:
	var lines: PackedStringArray = []
	for e in App.log_entries:
		lines.append("[%s] %s" % [e["source"], e["msg"]])
	return "\n".join(lines)
