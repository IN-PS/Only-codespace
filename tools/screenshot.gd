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
	await shot("01_browser_empty")
	var data := PSTemplates.create("obby", "Percurso")
	var pid := PSProjectStore.create_project("Percurso", data)
	var pid2 := PSProjectStore.create_project("Ilha", PSTemplates.create("terrain", "Ilha"))
	main.browser.refresh()
	await shot("02_browser_list")
	main._open_project(pid, false)
	await _frames(10)
	await shot("03_editor")
	var ed: PSEditor = main.editor
	ed.add_prefab("house")
	var house: Array = ed.selection.duplicate()
	await shot("04_added_house")
	ed.show_panel("inspector")
	await shot("05_inspector")
	ed.show_panel("hierarchy")
	await shot("06_hierarchy")
	ed.set_tool("rotate")
	var sp := PSData.new_object("part", {"shape": "sphere"})
	ed.show_panel("scripts")
	var sid: String = ed.panels["scripts"].create_script("Moeda", PSScriptTemplates.get_code("coin"))
	ed.panels["scripts"]._select(sid)
	await shot("07_scripts")
	ed.show_panel("world")
	await shot("08_world")
	ed.show_add_menu()
	await shot("09_add_menu")
	PSModal.close_top()
	ed.set_dock_open(false)
	ed.set_selection(house)
	ed.delete_selection()
	ed.start_play()
	await _frames(30)
	main.play.player.look(-120, 60)
	await _frames(5)
	await shot("10_play")
	main.play.set_paused(true)
	await shot("11_paused")
	main.play.stop()
	await _frames(5)
	ed.close_project()
	await _frames(5)
	main._open_project(pid2, false)
	await _frames(10)
	ed = main.editor
	ed.show_panel("terrain")
	ed.set_brush_active(true)
	await shot("12_terrain")
	ed.show_panel("assets")
	await shot("13_assets")
	ed.set_dock_open(false)
	ed.start_play()
	await _frames(40)
	await shot("14_play_island")
	main.play.stop()
	await _frames(3)
	ed.close_project()
	await _frames(3)
	PSProjectStore.delete_project(pid)
	PSProjectStore.delete_project(pid2)
