extends PSTestCase
## Terreno e importação/validação de assets.


func test_terrain_brushes() -> void:
	var t := PSTerrain.new()
	runner.add_child(t)
	t.create(65)
	t.rebuild_all()
	eq(t.heights.size(), 65 * 65, "mapa de altura do tamanho certo")
	t.apply_brush("raise", Vector3(0, 0, 0), 4.0, 1.0)
	check(t.height_at_local(0, 0) > 0.3, "elevar sobe o centro")
	eq(t.height_at_local(20, 20), 0.0, "longe do pincel não muda")
	var h := t.height_at_local(0, 0)
	t.apply_brush("lower", Vector3(0, 0, 0), 4.0, 0.5)
	check(t.height_at_local(0, 0) < h, "abaixar desce")
	t.apply_brush("flatten", Vector3(0, 0, 0), 6.0, 1.0, {"target": 2.0})
	near(t.height_at_local(0, 0), 2.0, 0.01, "nivelar")
	t.apply_brush("smooth", Vector3(0, 0, 0), 6.0, 1.0)
	var before_color := t._color_at(32 * 65 + 32)
	t.apply_brush("paint", Vector3(0, 0, 0), 3.0, 1.0, {"color": PSTerrain.SURFACES["sand"]["color"]})
	check(t._color_at(32 * 65 + 32) != before_color, "pintar muda a cor")
	var hit := t.raycast(Vector3(0, 50, 0), Vector3.DOWN)
	check(not hit.is_empty(), "raio acerta o terreno")
	if not hit.is_empty():
		near((hit["position"] as Vector3).y, t.height_at_local(0, 0), 0.05, "ponto de impacto na superfície")
	check(t.raycast(Vector3(500, 50, 0), Vector3.DOWN).is_empty(), "raio fora do terreno não acerta")
	var snap := t.snapshot()
	t.apply_brush("raise", Vector3(10, 0, 10), 3.0, 1.0)
	t.restore(snap)
	near(t.height_at_local(10, 10), 0.0, 0.001, "restaurar desfaz o pincel")
	t.queue_free()


func test_terrain_vegetation_and_roundtrip() -> void:
	var t := PSTerrain.new()
	runner.add_child(t)
	t.create(33)
	t.generate_noise(8.0, 0.05, 42, false)
	t.auto_paint()
	var n := t.apply_vegetation("tree", Vector3.ZERO, 8.0, 3.0, false, 7)
	check(n > 0, "plantou árvores")
	var data := t.to_data()
	var json := JSON.stringify(data)
	var clean = PSData.sanitize_terrain(JSON.parse_string(json))
	var t2 := PSTerrain.new()
	runner.add_child(t2)
	t2.load_data(clean)
	eq(t2.size, 33, "tamanho preservado")
	near(t2.height_at_local(3.3, -4.1), t.height_at_local(3.3, -4.1), 0.0001, "alturas preservadas")
	eq(t2.count_vegetation(), t.count_vegetation(), "vegetação preservada")
	var removed := t2.apply_vegetation("tree", Vector3.ZERO, 50.0, 0.0, true)
	eq(removed, n, "remover plantas")
	t.queue_free()
	t2.queue_free()


func test_terrain_templates() -> void:
	for gen in ["flat", "hills", "mountains", "island"]:
		var d := PSTerrain.new_data(33, gen, 3)
		check(PSData.sanitize_terrain(d) != null, "gerador %s produz dados válidos" % gen)


func _make_glb() -> PackedByteArray:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Caixa"
	var bm := BoxMesh.new()
	bm.size = Vector3(2, 1, 1)
	mi.mesh = bm
	root.add_child(mi)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(root, state)
	var bytes := doc.generate_buffer(state)
	root.free()
	return bytes


func test_validator_signatures() -> void:
	var glb := _make_glb()
	check(PSAssetValidator.validate_bytes(glb, "glb")["ok"], "GLB válido aceito")
	var fake := "isto não é um modelo".to_utf8_buffer()
	check(not PSAssetValidator.validate_bytes(fake, "glb")["ok"], "GLB falso recusado")
	check(not PSAssetValidator.validate_bytes(fake, "png")["ok"], "PNG falso recusado")
	check(not PSAssetValidator.validate_bytes(fake, "gd")["ok"], "script recusado")
	check(not PSAssetValidator.validate_bytes(fake, "tscn")["ok"], "cena Godot recusada")
	check(not PSAssetValidator.validate_bytes(PackedByteArray(), "png")["ok"], "arquivo vazio recusado")
	var big := PackedByteArray()
	big.resize(PSAssetValidator.MAX_TEXTURE_BYTES + 1)
	check(not PSAssetValidator.validate_bytes(big, "png")["ok"], "textura grande demais recusada")
	var gltf_url := JSON.stringify({"asset": {"version": "2.0"}, "buffers": [{"uri": "https://exemplo.com/x.bin", "byteLength": 4}]}).to_utf8_buffer()
	check(not PSAssetValidator.validate_bytes(gltf_url, "gltf")["ok"], "glTF com URL externa recusado")
	var gltf_up := JSON.stringify({"asset": {"version": "2.0"}, "images": [{"uri": "../segredo.png"}]}).to_utf8_buffer()
	check(not PSAssetValidator.validate_bytes(gltf_up, "gltf")["ok"], "glTF com ../ recusado")
	var draco := JSON.stringify({"asset": {"version": "2.0"}, "extensionsRequired": ["KHR_draco_mesh_compression"]}).to_utf8_buffer()
	var r := PSAssetValidator.validate_bytes(draco, "gltf")
	check(not r["ok"] and String(r["error"]).contains("Draco"), "Draco recusado com dica")
	var v1 := JSON.stringify({"asset": {"version": "1.0"}}).to_utf8_buffer()
	check(not PSAssetValidator.validate_bytes(v1, "gltf")["ok"], "glTF 1.0 recusado")


func test_import_model_and_texture() -> void:
	var pid := temp_project("blank")
	var lib := PSAssetLibrary.new()
	runner.add_child(lib)
	lib.setup(pid, [])
	var glb := _make_glb()
	var tmp := "user://tmp/teste_modelo.glb"
	PSProjectStore.ensure_dirs()
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_buffer(glb)
	f.close()
	var r := lib.import_file(tmp, "teste_modelo.glb", {"license": "CC0 (domínio público)", "origin": "teste", "author": "robô"})
	check(r["ok"], "modelo importado: %s" % r.get("error", ""))
	if r["ok"]:
		var e: Dictionary = r["entry"]
		eq(e["license"], "CC0 (domínio público)", "licença registrada")
		eq(e["origin"], "teste", "origem registrada")
		eq(e["stats"]["vertices"] > 0, true, "estatísticas calculadas")
		check(lib.load_model_now(e["id"]), "modelo carrega")
		var inst := lib.instantiate_model(e["id"])
		check(inst != null, "instancia")
		var box := lib.get_model_aabb(e["id"])
		near(box.size.x, 2.0, 0.01, "caixa envolvente correta")
		if inst:
			inst.free()
		var dup := lib.import_file(tmp, "copia.glb")
		check(not dup["ok"] and dup.has("duplicate"), "detecta importação duplicada")
	# Sem extensão (como URIs do Android): identifica pelo conteúdo.
	var tmp2 := "user://tmp/arquivo_sem_extensao"
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 1, 0))
	var f2 := FileAccess.open(tmp2, FileAccess.WRITE)
	f2.store_buffer(img.save_png_to_buffer())
	f2.close()
	var r2 := lib.import_file(tmp2, "", {})
	check(r2["ok"], "textura sem extensão identificada pelo conteúdo: %s" % r2.get("error", ""))
	if r2["ok"]:
		check(lib.get_texture(r2["entry"]["id"]) != null, "textura carrega")
	DirAccess.remove_absolute(tmp)
	DirAccess.remove_absolute(tmp2)
	lib.queue_free()
	PSProjectStore.delete_project(pid)


func test_world_with_model_in_play_mode() -> void:
	var pid := temp_project("blank")
	var lib := PSAssetLibrary.new()
	runner.add_child(lib)
	lib.setup(pid, [])
	var r := lib.import_bytes(_make_glb(), "caixa.glb", "glb")
	check(r["ok"], "importado")
	var aid: String = r["entry"]["id"]
	var data := PSData.new_project_data("m")
	var o := PSData.new_object("model", {"asset": aid})
	o["id"] = "m1"
	data["objects"] = [o]
	var w := PSWorld.new(PSWorld.Mode.PLAY)
	w.set_assets(lib)
	runner.add_child(w)
	lib.load_model_now(aid)
	w.load_project(data)
	var obj := w.get_obj("m1")
	check(obj != null and not obj.placeholder, "modelo instanciado no modo de jogo")
	check(obj.node is StaticBody3D, "modelo fixo vira corpo estático")
	var shapes := obj.node.get_children().filter(func(c): return c is CollisionShape3D)
	eq(shapes.size(), 1, "tem colisão")
	w.queue_free()
	lib.queue_free()
	PSProjectStore.delete_project(pid)
