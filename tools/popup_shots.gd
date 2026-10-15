extends Node
## Captura dos popups (seletor de cor, menu suspenso) no tamanho de celular.

var out_dir := "user://shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out_dir = a.get_slice("=", 1)
	var main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var pid := PSProjectStore.create_project("Popups", PSTemplates.create("empty", "Popups"))
	main._open_project(pid, false)
	await _frames(5)
	var ed: PSEditor = main.editor
	ed.add_primitive("part", {"shape": "box"})
	ed.show_panel("inspector")
	await _frames(3)
	var insp: PSInspectorPanel = ed.panels["inspector"]
	var cb := _find(insp, ColorPickerButton) as ColorPickerButton
	cb.get_popup().popup()
	cb.get_popup().position = Vector2i(0, 0)
	await _shot("p1_color_picker")
	cb.get_popup().hide()
	var opt := _find(insp, OptionButton) as OptionButton
	opt.show_popup()
	await _shot("p2_option_popup")
	opt.get_popup().hide()
	PSProjectStore.delete_project(pid)
	get_tree().quit()


func _find(node: Node, cls) -> Node:
	for c in node.get_children():
		if is_instance_of(c, cls):
			return c
		var r := _find(c, cls)
		if r:
			return r
	return null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("captura: ", name)
