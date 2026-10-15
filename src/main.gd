extends Node
## Cena principal: alterna entre a lista de projetos, o editor e o modo de teste.

var ui_root: Control
var overlay_layer: CanvasLayer
var browser: PSProjectBrowser
var editor: PSEditor
var play: Node


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	get_tree().set_quit_on_go_back(false)
	var theme := PSTheme.get_theme()
	get_tree().root.theme = theme
	RenderingServer.set_default_clear_color(PSTheme.BG)
	ui_root = Control.new()
	ui_root.name = "UI"
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = theme
	add_child(ui_root)
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 50
	add_child(overlay_layer)
	var overlay := Control.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.theme = theme
	overlay_layer.add_child(overlay)
	App.overlay = overlay
	PSProjectStore.ensure_dirs()
	_show_browser()
	App.log_info("Pocket Studio 3D %s iniciado (%s, renderizador %s)." % [App.VERSION, OS.get_name(), RenderingServer.get_current_rendering_method()], "App")


func _show_browser() -> void:
	if browser == null:
		browser = PSProjectBrowser.new()
		browser.name = "ProjectBrowser"
		browser.open_project.connect(_open_project)
		ui_root.add_child(browser)
	browser.visible = true
	browser.refresh()


func _open_project(pid: String, use_recovery: bool) -> void:
	if editor:
		editor.queue_free()
		editor = null
	editor = PSEditor.new()
	editor.name = "Editor"
	ui_root.add_child(editor)
	var res := editor.open_project(pid, use_recovery)
	if not res["ok"]:
		editor.queue_free()
		editor = null
		PSModal.message("Não foi possível abrir", String(res.get("error", "Erro desconhecido.")))
		return
	browser.visible = false
	editor.request_close.connect(_close_editor)
	editor.request_play.connect(_start_play)


func _close_editor() -> void:
	if editor:
		editor.queue_free()
		editor = null
	_show_browser()


func _start_play() -> void:
	if editor == null or play != null:
		return
	var data := editor.build_project_data()
	play = PSPlaySession.new()
	play.name = "Play"
	editor.set_editor_active(false)
	ui_root.add_child(play)
	play.finished.connect(_stop_play)
	play.start(data, editor.assets, editor.pid)


func _stop_play() -> void:
	if play:
		play.queue_free()
		play = null
	if editor:
		editor.set_editor_active(true)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_on_back()
		NOTIFICATION_WM_CLOSE_REQUEST:
			if editor:
				editor.autosave_now()
			get_tree().quit()


func _on_back() -> void:
	if PSModal.close_top():
		return
	if play:
		play.handle_back()
	elif editor:
		editor.handle_back()
	else:
		PSModal.confirm("Sair", "Fechar o Pocket Studio 3D?", "Sair", func(): get_tree().quit())
