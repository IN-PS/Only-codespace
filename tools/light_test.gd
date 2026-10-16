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
	var e := PSData.default_environment()
	e["sky"] = "sunset"
	w.apply_environment(e)
	cam.distance = 9
	var variants := [
		["q1_nb2", 1, 2.0, 0.06],
		["q2_nb2", 2, 2.0, 0.06],
		["q1_nb4", 1, 4.0, 0.1],
		["q2_nb4", 2, 4.0, 0.1],
	]
	for v in variants:
		RenderingServer.directional_soft_shadow_filter_set_quality(v[1])
		w.sun.shadow_normal_bias = v[2]
		w.sun.shadow_bias = v[3]
		for i in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("sh_%s.png" % v[0]))
	get_tree().quit()
