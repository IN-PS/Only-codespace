extends Node
## Compara variações de luz ambiente (ferramenta de desenvolvimento).
var out_dir := "user://shots"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out_dir = a.get_slice("=", 1)
	var w := PSWorld.new(PSWorld.Mode.EDIT)
	add_child(w)
	var data := PSTemplates.create("empty", "Luz")
	data["objects"].append(PSPrefabs.instantiate("house", Vector3(0, 0, -3))[0])
	for d in PSPrefabs.instantiate("house", Vector3(0, 0, -3)):
		data["objects"].append(d)
	w.load_project(data)
	var cam := PSEditorCamera.new()
	add_child(cam)
	cam.pivot = Vector3(0, 1, -2)
	cam.distance = 14
	cam.set_view("iso")
	cam.make_current()
	for sky in ["day", "sunset", "night", "overcast"]:
		var e := PSData.default_environment()
		e["sky"] = sky
		w.apply_environment(e)
		for i in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("sky_%s.png" % sky))
	get_tree().quit()
