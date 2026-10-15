class_name PSFileAccessHelper
extends RefCounted
## Seleção e exportação de arquivos.
##
## No Android usa o seletor nativo do sistema (Storage Access Framework), que
## devolve URIs "content://" — não é preciso pedir permissão de armazenamento.
## No computador usa o FileDialog do próprio Godot.

static var _dialog: FileDialog


static func uses_native_dialog() -> bool:
	return App.is_android() and DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)


## Abre um arquivo. `callback` recebe (path: String) — vazio se cancelado.
static func pick_file(title: String, filters: PackedStringArray, callback: Callable) -> void:
	if uses_native_dialog():
		var err := DisplayServer.file_dialog_show(title, "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters,
			func(status: bool, paths: PackedStringArray, _filter: int):
				callback.call(paths[0] if status and paths.size() > 0 else ""))
		if err != OK:
			App.log_error("Seletor de arquivos indisponível (%s)." % error_string(err), "Arquivos")
			callback.call("")
		return
	_show_godot_dialog(title, filters, FileDialog.FILE_MODE_OPEN_FILE, "", callback)


## Oferece salvar uma cópia de `src_path` em um local escolhido pelo usuário.
static func offer_export(src_path: String, suggested_name: String) -> void:
	if uses_native_dialog():
		var err := DisplayServer.file_dialog_show("Salvar backup", "", suggested_name, false, DisplayServer.FILE_DIALOG_MODE_SAVE_FILE, PackedStringArray(["*.zip"]),
			func(status: bool, paths: PackedStringArray, _filter: int):
				if status and paths.size() > 0:
					var ok := copy_file(src_path, paths[0])
					PSUI.toast("Backup salvo." if ok else "Falha ao salvar o backup.", "ok" if ok else "error"))
		if err == OK:
			return
	var abs_path := ProjectSettings.globalize_path(src_path)
	var m := PSModal.create("Backup gerado")
	m.add_text("O backup foi salvo em:\n%s" % abs_path)
	if not App.is_mobile():
		m.add_button("Abrir pasta", func(): OS.shell_open(abs_path.get_base_dir()))
	else:
		var on_saved := func(p: String):
			if p != "":
				PSUI.toast("Backup salvo." if copy_file(src_path, p) else "Falha ao salvar.", "ok")
		var open_dialog := func():
			_show_godot_dialog("Salvar backup", PackedStringArray(["*.zip"]), FileDialog.FILE_MODE_SAVE_FILE, suggested_name, on_saved)
		m.add_button("Salvar em…", open_dialog)
	m.add_button("OK", Callable(), "AccentButton")
	m.show_modal()


static func copy_file(src: String, dst: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(src)
	if bytes.is_empty():
		return false
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	return true


static func _show_godot_dialog(title: String, filters: PackedStringArray, mode: int, filename: String, callback: Callable) -> void:
	if _dialog and is_instance_valid(_dialog):
		_dialog.queue_free()
	var d := FileDialog.new()
	d.title = title
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.file_mode = mode
	d.filters = filters
	d.use_native_dialog = false
	d.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS) if OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS) != "" else OS.get_user_data_dir()
	if filename != "":
		d.current_file = filename
	var done := [false]
	d.file_selected.connect(func(p):
		done[0] = true
		callback.call(p))
	d.canceled.connect(func():
		if not done[0]:
			callback.call(""))
	d.visibility_changed.connect(func():
		if not d.visible:
			d.queue_free())
	App.overlay.add_child(d)
	var s := App.get_ui_size()
	d.popup_centered(Vector2i(int(minf(s.x - 20, 720)), int(minf(s.y - 20, 520))))
	_dialog = d


## Nome legível de um caminho ou URI content://.
static func display_name(path: String) -> String:
	var p := path.uri_decode()
	var name := p.get_file()
	if name.contains(":"):
		name = name.get_slice(":", name.get_slice_count(":") - 1)
	return name.get_file()


## Detecta a extensão pelo conteúdo quando o nome não tem extensão conhecida.
static func sniff_extension(bytes: PackedByteArray) -> String:
	if bytes.size() >= 4 and bytes.decode_u32(0) == PSAssetValidator.GLB_MAGIC:
		return "glb"
	if bytes.size() >= 8 and bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		return "png"
	if bytes.size() >= 3 and bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF:
		return "jpg"
	if bytes.size() >= 12 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		return "webp"
	if bytes.size() >= 4 and bytes.slice(0, 4).get_string_from_ascii() == "PK\u0003\u0004":
		return "zip"
	var head := bytes.slice(0, mini(bytes.size(), 64)).get_string_from_utf8().strip_edges()
	if head.begins_with("{"):
		return "gltf"
	return ""
