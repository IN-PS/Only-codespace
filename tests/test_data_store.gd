extends PSTestCase
## Esquema de dados e armazenamento de projetos.


func test_sanitize_rejects_garbage() -> void:
	eq(PSData.sanitize_project(null), {}, "null não é projeto")
	eq(PSData.sanitize_project({"format": "outro"}), {}, "formato errado")
	eq(PSData.sanitize_project([1, 2, 3]), {}, "array não é projeto")
	var p := PSData.sanitize_project({
		"format": PSData.FORMAT,
		"name": 123,
		"objects": [
			{"id": "a1", "type": "part", "pos": ["x", INF, 5], "size": [-3, 1e9, 0], "shape": "bomba"},
			{"id": "a1", "type": "part"},
			{"id": "../hack", "type": "part"},
			{"id": "b2", "type": "desconhecido"},
			{"id": "c3", "type": "group", "parent": "naoexiste"},
			"lixo",
		],
		"assets": [{"id": "z", "type": "model", "file": "../../etc/passwd"}, {"id": "y", "type": "model", "file": "assets/ok.glb"}],
		"scripts": [{"id": "s1", "code": 42}],
	})
	check(not p.is_empty(), "projeto com lixo deve ser recuperável")
	eq(p["name"], "Projeto", "nome inválido vira padrão")
	eq(p["objects"].size(), 2, "só objetos válidos e ids únicos")
	var a: Dictionary = p["objects"][0]
	eq(a["shape"], "box", "forma inválida vira cubo")
	eq(PSData.arr_to_v3(a["pos"]), Vector3(0, 0, 5), "coordenadas inválidas viram 0")
	eq(PSData.arr_to_v3(a["size"]), Vector3(PSData.MIN_SIZE, PSData.MAX_SIZE, PSData.MIN_SIZE), "tamanho limitado")
	eq(p["objects"][1]["parent"], "", "pai inexistente vira raiz")
	eq(p["assets"].size(), 1, "asset fora da pasta assets/ é descartado")
	eq(p["scripts"][0]["code"], "", "código não-texto vira vazio")


func test_vector_quaternion_roundtrip() -> void:
	var q := Quaternion.from_euler(Vector3(0.3, -1.2, 2.0))
	var q2 := PSData.arr_to_quat(JSON.parse_string(JSON.stringify(PSData.quat_to_arr(q))))
	check(q.is_equal_approx(q2) or q.is_equal_approx(-q2), "quaternion sobrevive ao JSON")
	eq(PSData.arr_to_quat([0, 0, 0, 0]), Quaternion.IDENTITY, "quaternion nulo vira identidade")
	eq(PSData.arr_to_color([2, -1, 0.5]), Color(1, 0, 0.5, 1), "cor limitada a 0..1")


func test_create_save_load_list() -> void:
	var pid := temp_project("empty", "Projeto de teste A")
	check(pid != "", "projeto criado")
	var listed := PSProjectStore.list_projects().filter(func(p): return p["id"] == pid)
	eq(listed.size(), 1, "aparece na lista")
	eq(listed[0]["name"], "Projeto de teste A", "nome na lista")
	var res := PSProjectStore.load_project(pid)
	check(res["ok"], "carrega")
	var data: Dictionary = res["data"]
	data["objects"].append(PSData.sanitize_object(PSData.new_object("part", {"id": "novo1"})))
	eq(PSProjectStore.save_project(pid, data), OK, "salva")
	var again := PSProjectStore.load_project(pid)
	eq(again["data"]["objects"].size(), data["objects"].size(), "objeto novo persistiu")
	check(FileAccess.file_exists(PSProjectStore.project_file(pid) + ".bak"), "cópia .bak criada")
	PSProjectStore.delete_project(pid)
	check(not PSProjectStore.project_exists(pid), "excluído")


func test_corrupted_file_uses_backup() -> void:
	var pid := temp_project("empty")
	var data: Dictionary = PSProjectStore.load_project(pid)["data"]
	data["name"] = "Versão boa"
	PSProjectStore.save_project(pid, data)
	data["name"] = "Versão mais nova"
	PSProjectStore.save_project(pid, data)
	# Simula uma queda de energia que corrompeu o arquivo principal.
	var f := FileAccess.open(PSProjectStore.project_file(pid), FileAccess.WRITE)
	f.store_string("{\"format\": \"pocketstudio3d.proj")
	f.close()
	var res := PSProjectStore.load_project(pid)
	check(res["ok"], "recupera da cópia")
	check(res.get("used_backup", false), "informa que usou a cópia")
	eq(res["data"]["name"], "Versão boa", "cópia = salvamento anterior")
	PSProjectStore.delete_project(pid)


func test_autosave_recovery() -> void:
	var pid := temp_project("empty")
	check(not PSProjectStore.has_recovery(pid), "sem recuperação no início")
	var data: Dictionary = PSProjectStore.load_project(pid)["data"]
	data["name"] = "Alterado sem salvar"
	eq(PSProjectStore.autosave(pid, data), OK, "salvamento automático")
	check(PSProjectStore.has_recovery(pid), "há recuperação")
	var rec := PSProjectStore.load_recovery(pid)
	check(rec["ok"], "carrega recuperação")
	eq(rec["data"]["name"], "Alterado sem salvar", "dados recuperados")
	eq(PSProjectStore.load_project(pid)["data"]["name"], "Teste automatizado", "arquivo principal intocado")
	PSProjectStore.save_project(pid, rec["data"])
	check(not PSProjectStore.has_recovery(pid), "salvar limpa a recuperação")
	PSProjectStore.delete_project(pid)


func test_versions() -> void:
	var pid := temp_project("empty")
	var data: Dictionary = PSProjectStore.load_project(pid)["data"]
	for i in 5:
		data["name"] = "v%d" % i
		eq(PSProjectStore.save_version(pid, data, "rótulo %d" % i), OK, "salva versão")
		OS.delay_msec(5)
	var versions := PSProjectStore.list_versions(pid)
	eq(versions.size(), 5, "5 versões")
	PSProjectStore.prune_versions(pid, 3)
	eq(PSProjectStore.list_versions(pid).size(), 3, "poda mantém 3")
	var v := PSProjectStore.load_version(pid, versions[0]["file"])
	check(v["ok"], "carrega versão")
	check(not PSProjectStore.load_version(pid, "../project.json")["ok"], "recusa caminho com ..")
	PSProjectStore.delete_project(pid)


func test_rename_duplicate() -> void:
	var pid := temp_project("obby", "Original")
	eq(PSProjectStore.rename_project(pid, "Renomeado"), OK, "renomeia")
	eq(PSProjectStore.load_project(pid)["data"]["name"], "Renomeado", "nome novo")
	var copy := PSProjectStore.duplicate_project(pid, "Cópia")
	check(copy != "" and copy != pid, "duplica")
	eq(PSProjectStore.load_project(copy)["data"]["objects"].size(), PSProjectStore.load_project(pid)["data"]["objects"].size(), "cópia tem os mesmos objetos")
	PSProjectStore.delete_project(pid)
	PSProjectStore.delete_project(copy)
	eq(PSProjectStore.delete_project("../../etc"), ERR_INVALID_PARAMETER, "recusa id malicioso")


func test_backup_roundtrip() -> void:
	var pid := temp_project("obby", "Backup")
	# Coloca um asset de textura no projeto.
	var lib := PSAssetLibrary.new()
	lib.setup(pid, [])
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var r := lib.import_bytes(img.save_png_to_buffer(), "vermelho.png", "png", {"license": "CC0 (domínio público)"})
	check(r["ok"], "textura importada")
	var data: Dictionary = PSProjectStore.load_project(pid)["data"]
	data["assets"] = lib.to_array()
	PSProjectStore.save_project(pid, data)
	lib.free()
	var zip := PSProjectStore.export_backup(pid)
	check(zip != "" and FileAccess.file_exists(zip), "zip gerado")
	var imp := PSProjectStore.import_backup(zip)
	check(imp["ok"], "zip importado: %s" % imp.get("error", ""))
	if imp["ok"]:
		var d2: Dictionary = PSProjectStore.load_project(imp["pid"])["data"]
		eq(d2["objects"].size(), data["objects"].size(), "objetos preservados")
		eq(d2["assets"].size(), 1, "asset preservado")
		check(FileAccess.file_exists(PSProjectStore.project_dir(imp["pid"]).path_join(d2["assets"][0]["file"])), "arquivo do asset extraído")
		PSProjectStore.delete_project(imp["pid"])
	DirAccess.remove_absolute(zip)
	PSProjectStore.delete_project(pid)


func test_malicious_backup_rejected() -> void:
	PSProjectStore.ensure_dirs()
	var cases := {
		"traversal": "assets/../../evil.glb",
		"script": "assets/virus.gd",
		"scene": "assets/cena.tscn",
		"outside": "outro/arquivo.png",
	}
	for k in cases:
		var path := PSProjectStore.TMP_DIR.path_join("mal_%s.zip" % k)
		var zip := ZIPPacker.new()
		zip.open(path)
		zip.start_file("project.json")
		zip.write_file(JSON.stringify(PSData.new_project_data("x")).to_utf8_buffer())
		zip.close_file()
		zip.start_file(cases[k])
		zip.write_file("conteúdo".to_utf8_buffer())
		zip.close_file()
		zip.close()
		var res := PSProjectStore.import_backup(path)
		check(not res["ok"], "backup malicioso '%s' recusado" % k)
		DirAccess.remove_absolute(path)
