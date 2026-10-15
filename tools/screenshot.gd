extends Node
## Ferramenta de desenvolvimento: abre o app, executa um roteiro e salva capturas de tela.
## Uso: godot --path . res://tools/screenshot.tscn -- --shots=<pasta> --tour=<nome>

var out_dir := "user://shots"
var tour := "basic"
var main: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out_dir = a.get_slice("=", 1)
		elif a.begins_with("--tour="):
			tour = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await _run_tour()
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func shot(name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("captura: ", name)


func _run_tour() -> void:
	await shot("01_browser")
	# Cria um projeto a partir do modelo "obby" e abre.
	var data := PSTemplates.create("obby", "Teste visual")
	var pid := PSProjectStore.create_project("Teste visual", data)
	main.browser.refresh()
	await shot("02_browser_list")
	main._open_project(pid, false)
	await _frames(10)
	await shot("03_editor")
	var ed: PSEditor = main.editor
	ed.add_primitive("part", {"shape": "sphere"})
	await shot("04_added_sphere")
	ed.show_panel("inspector")
	await shot("05_inspector")
	ed.show_panel("hierarchy")
	await shot("06_hierarchy")
	ed.set_tool("rotate")
	await shot("07_rotate_tool")
	ed.show_panel("scripts")
	await shot("08_scripts")
	ed.show_panel("terrain")
	await shot("09_terrain")
	ed.show_add_menu()
	await shot("10_add_menu")
	PSModal.close_top()
	ed.set_dock_open(false)
	ed.start_play()
	await _frames(30)
	await shot("11_play")
	main.play.set_paused(true)
	await shot("12_paused")
	main.play.stop()
	await _frames(5)
	await shot("13_back_to_editor")
	PSProjectStore.delete_project(pid)
