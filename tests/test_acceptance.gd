extends PSTestCase
## Testes de aceitação (lista do pedido original), executados de ponta a ponta.


func _touch(pos: Vector2, pressed: bool, index := 0) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	runner.get_viewport().push_input(ev)


func _drag(pos: Vector2, rel: Vector2, index := 0) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	ev.relative = rel
	runner.get_viewport().push_input(ev)


func _open_editor(pid: String, recovery := false) -> PSEditor:
	var ed := PSEditor.new()
	runner.add_child(ed)
	var res := ed.open_project(pid, recovery)
	check(res["ok"], "editor abriu o projeto")
	await frames(2)
	await physics_frames(2)
	return ed


## 1 e 2: criar um projeto e mover objetos com os dedos (arrastando o próprio objeto).
func test_create_project_and_move_with_finger() -> void:
	var data := PSTemplates.create("empty", "Aceitação 1")
	var pid := PSProjectStore.create_project("Aceitação 1", data)
	check(pid != "", "projeto criado no aparelho")
	var ed: PSEditor = await _open_editor(pid)
	ed.camera.pivot = Vector3(0, 0.5, 0)
	ed.camera.distance = 12
	ed.camera.set_view("iso")
	ed.add_primitive("part", {"shape": "box"})
	var id: String = ed.selection[0]
	ed.world.set_object_global_transform(id, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	ed.set_tool("move")
	await physics_frames(2)
	var start := ed.camera.unproject_position(Vector3(0, 0.5, 0))
	# O dedo começa sobre o objeto (onde fica a alça central do gizmo, que move
	# no plano horizontal na altura do objeto) e termina sobre o ponto (3, 0.5, 2).
	var target := ed.camera.unproject_position(Vector3(3, 0.5, 2))
	_touch(start, true)
	var steps := 10
	for i in steps:
		var p := start.lerp(target, float(i + 1) / steps)
		_drag(p, (target - start) / steps)
	_touch(target, false)
	await frames(1)
	var pos := ed.world.get_global_transform_of(id).origin
	near(pos.x, 3.0, 0.3, "objeto arrastado em X")
	near(pos.z, 2.0, 0.3, "objeto arrastado em Z")
	near(pos.y, 0.5, 0.05, "continua apoiado sobre a base")
	ed.queue_free()
	await frames(1)
	PSProjectStore.delete_project(pid)


## 3: importar um modelo 3D compatível e usá-lo no mundo.
func test_import_model_into_world() -> void:
	var pid := temp_project("empty", "Aceitação 3")
	var ed: PSEditor = await _open_editor(pid)
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = CylinderMesh.new()
	root.add_child(mi)
	var st := GLTFState.new()
	var doc := GLTFDocument.new()
	doc.append_from_scene(root, st)
	var glb := doc.generate_buffer(st)
	root.free()
	var r := ed.assets.import_bytes(glb, "torre.glb", "glb", {"license": "Autoria própria"})
	check(r["ok"], "GLB importado")
	ed.add_model(r["entry"]["id"])
	await frames(3)
	var id: String = ed.selection[0]
	var obj := ed.world.get_obj(id)
	check(obj.type == "model" and not obj.placeholder, "modelo aparece no mundo")
	ed.save_project()
	var reloaded: Dictionary = PSProjectStore.load_project(pid)["data"]
	eq(reloaded["assets"].size(), 1, "asset registrado no projeto salvo")
	eq(reloaded["assets"][0]["license"], "Autoria própria", "licença salva")
	ed.queue_free()
	await frames(1)
	PSProjectStore.delete_project(pid)


## 4: salvar e reabrir o projeto com tudo igual.
func test_save_and_reopen_everything() -> void:
	var pid := temp_project("terrain", "Aceitação 4")
	var ed: PSEditor = await _open_editor(pid)
	ed.add_prefab("house")
	ed.world.terrain.apply_brush("raise", Vector3(5, 0, 5), 3.0, 1.0)
	ed.panels["scripts"].create_script("Teste", "print('oi')")
	var env: Dictionary = ed.world.env_data.duplicate()
	env["sky"] = "night"
	ed.world.apply_environment(env)
	check(ed.save_project(), "salvou")
	var before := JSON.stringify(ed.build_project_data()["objects"])
	var h_before := ed.world.terrain.height_at_local(5, 5)
	ed.queue_free()
	await frames(1)
	var ed2: PSEditor = await _open_editor(pid)
	eq(JSON.stringify(ed2.build_project_data()["objects"]), before, "objetos idênticos ao reabrir")
	near(ed2.world.terrain.height_at_local(5, 5), h_before, 0.001, "terreno idêntico")
	eq(ed2.world.env_data["sky"], "night", "ambiente salvo")
	eq(ed2.project["scripts"].size(), 1, "script salvo")
	ed2.queue_free()
	await frames(1)
	PSProjectStore.delete_project(pid)


## 6: recuperar um projeto após o aplicativo fechar sem salvar.
func test_recover_after_app_closed() -> void:
	var pid := temp_project("empty", "Aceitação 6")
	var ed: PSEditor = await _open_editor(pid)
	ed.add_primitive("part", {"shape": "sphere", "name": "Esfera não salva"})
	var unsaved_id: String = ed.selection[0]
	check(ed.dirty, "há alterações não salvas")
	# O Android avisa que o app foi para segundo plano; depois o sistema mata o processo.
	ed.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	ed.free()
	check(PSProjectStore.has_recovery(pid), "salvamento automático existe")
	check(PSProjectStore.list_projects().filter(func(p): return p["id"] == pid)[0]["recovery"], "lista de projetos avisa que há recuperação")
	var ed2: PSEditor = await _open_editor(pid, true)
	check(ed2.world.has_object(unsaved_id), "objeto recuperado")
	check(ed2.dirty, "projeto recuperado fica marcado como não salvo")
	ed2.save_project()
	check(not PSProjectStore.has_recovery(pid), "salvar limpa a recuperação")
	ed2.queue_free()
	await frames(1)
	PSProjectStore.delete_project(pid)


## Terreno esculpido com o dedo, com desfazer.
func test_sculpt_terrain_with_finger() -> void:
	var pid := temp_project("empty", "Terreno toque")
	var data: Dictionary = PSProjectStore.load_project(pid)["data"]
	data["terrain"] = PSTerrain.new_data(65, "flat")
	data["objects"] = []
	PSProjectStore.save_project(pid, data)
	var ed: PSEditor = await _open_editor(pid)
	ed.camera.pivot = Vector3.ZERO
	ed.camera.distance = 30
	ed.camera.set_view("iso")
	ed.show_panel("terrain")
	ed.set_dock_open(false)
	ed.brush["tool"] = "raise"
	ed.brush["strength"] = 1.0
	ed.set_brush_active(true)
	await frames(1)
	var p := ed.camera.unproject_position(Vector3.ZERO)
	_touch(p, true)
	for i in 6:
		_drag(p + Vector2(i * 6, 0), Vector2(6, 0))
	_touch(p + Vector2(36, 0), false)
	await frames(1)
	check(ed.world.terrain.height_at_local(0, 0) > 0.3, "terreno elevado pelo dedo (%.2f)" % ed.world.terrain.height_at_local(0, 0))
	ed.do_undo()
	near(ed.world.terrain.height_at_local(0, 0), 0.0, 0.001, "desfazer pincel")
	ed.queue_free()
	await frames(1)
	PSProjectStore.delete_project(pid)


## 7: funções locais não dependem de internet (nenhuma API de rede é usada).
func test_no_network_apis_used() -> void:
	var forbidden := ["HTTPRequest", "HTTPClient", "StreamPeerTCP", "TCPServer", "PacketPeerUDP", "UDPServer", "WebSocketPeer", "WebRTC", "ENetMultiplayerPeer", "JavaScriptBridge", "OS.execute", "OS.create_process"]
	var hits: Array = []
	for path in _scripts("res://src"):
		var code := FileAccess.get_file_as_string(path)
		for f in forbidden:
			if code.contains(f):
				hits.append("%s usa %s" % [path, f])
	eq(hits, [], "código do app não usa rede nem executa programas")


func _scripts(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_scripts(dir.path_join(sub)))
	return out
