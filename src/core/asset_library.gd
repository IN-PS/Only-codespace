class_name PSAssetLibrary
extends Node
## Assets locais de um projeto: modelos (GLB) e texturas importados.
##
## Os modelos são carregados sob demanda, um por quadro, para que abrir um
## projeto com muitos modelos não congele a interface. Enquanto um modelo não
## fica pronto, o mundo mostra uma caixa provisória no lugar.

signal model_ready(asset_id: String)
signal library_changed

const LICENSES := ["CC0 (domínio público)", "CC-BY 4.0", "CC-BY-SA 4.0", "MIT", "Autoria própria", "Outra (ver origem)", "Desconhecida"]

var pid := ""
var entries := {}            # id -> entrada (dicionário sanitizado)
var _order: Array[String] = []
var _templates := {}         # id -> Node3D (fora da árvore, usado como molde)
var _template_aabbs := {}    # id -> AABB
var _textures := {}          # id -> Texture2D
var _failed := {}            # id -> mensagem de erro
var _queue: Array[String] = []


func setup(project_id: String, assets: Array) -> void:
	clear()
	pid = project_id
	for a in assets:
		var e := PSData.sanitize_asset_entry(a)
		if e.is_empty():
			continue
		entries[e["id"]] = e
		_order.append(e["id"])


func clear() -> void:
	for t in _templates.values():
		if is_instance_valid(t):
			t.free()
	_templates.clear()
	_template_aabbs.clear()
	_textures.clear()
	_failed.clear()
	_queue.clear()
	entries.clear()
	_order.clear()


func _exit_tree() -> void:
	clear()


func to_array() -> Array:
	var out: Array = []
	for id in _order:
		if entries.has(id):
			out.append(entries[id].duplicate(true))
	return out


func list(type_filter := "", search := "") -> Array:
	var out: Array = []
	var q := search.strip_edges().to_lower()
	for id in _order:
		var e: Dictionary = entries[id]
		if type_filter != "" and e["type"] != type_filter:
			continue
		if q != "" and not (String(e["name"]).to_lower().contains(q) or String(e["original_name"]).to_lower().contains(q) or String(e["license"]).to_lower().contains(q)):
			continue
		out.append(e)
	return out


func get_entry(id: String) -> Dictionary:
	return entries.get(id, {})


func file_path(id: String) -> String:
	var e: Dictionary = entries.get(id, {})
	if e.is_empty():
		return ""
	return PSProjectStore.project_dir(pid).path_join(e["file"])


func get_error(id: String) -> String:
	return _failed.get(id, "")


# --------------------------------------------------------------------------
# Texturas
# --------------------------------------------------------------------------

func get_texture(id: String) -> Texture2D:
	if id == "" or not entries.has(id) or entries[id]["type"] != "texture":
		return null
	if _textures.has(id):
		return _textures[id]
	var path := file_path(id)
	var bytes := FileAccess.get_file_as_bytes(path)
	var res := PSAssetValidator.inspect_image(bytes, path.get_extension())
	if not res["ok"]:
		_failed[id] = res["error"]
		App.log_error("Textura \"%s\": %s" % [entries[id]["name"], res["error"]], "Assets")
		_textures[id] = null
		return null
	var img: Image = res["image"]
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_textures[id] = tex
	return tex


# --------------------------------------------------------------------------
# Modelos
# --------------------------------------------------------------------------

func is_model_ready(id: String) -> bool:
	return _templates.has(id)


func has_model_failed(id: String) -> bool:
	return _failed.has(id)


## Pede o carregamento de um modelo. Emite `model_ready` quando terminar.
func request_model(id: String) -> void:
	if id == "" or not entries.has(id) or _templates.has(id) or _failed.has(id) or _queue.has(id):
		return
	_queue.append(id)
	set_process(true)


func _ready() -> void:
	set_process(not _queue.is_empty())


func _process(_delta: float) -> void:
	if _queue.is_empty():
		set_process(false)
		return
	var id: String = _queue.pop_front()
	load_model_now(id)
	model_ready.emit(id)


## Carrega imediatamente (bloqueante). Usado pela fila e pelos testes.
func load_model_now(id: String) -> bool:
	if _templates.has(id):
		return true
	if not entries.has(id):
		return false
	var path := file_path(id)
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		_failed[id] = "Arquivo do modelo não encontrado."
		App.log_error("Modelo \"%s\": arquivo ausente (%s)." % [entries[id]["name"], entries[id]["file"]], "Assets")
		return false
	var check := PSAssetValidator.validate_bytes(bytes, path.get_extension())
	if not check["ok"]:
		_failed[id] = check["error"]
		App.log_error("Modelo \"%s\": %s" % [entries[id]["name"], check["error"]], "Assets")
		return false
	var res := PSAssetValidator.inspect_model(bytes, path.get_base_dir())
	if not res["ok"]:
		_failed[id] = res["error"]
		App.log_error("Modelo \"%s\": %s" % [entries[id]["name"], res["error"]], "Assets")
		return false
	var doc: GLTFDocument = res["doc"]
	var scene := doc.generate_scene(res["state"])
	if scene == null or not (scene is Node3D):
		if scene:
			scene.free()
		_failed[id] = "Não foi possível montar a cena do modelo."
		return false
	_strip_non_visual(scene)
	_templates[id] = scene
	_template_aabbs[id] = compute_aabb(scene)
	return true


## Remove tudo que não for visual (scripts nunca vêm de glTF, mas câmeras e
## luzes do arquivo também são descartadas para não interferir no jogo).
func _strip_non_visual(node: Node) -> void:
	for child in node.get_children():
		_strip_non_visual(child)
		if child is Camera3D or child is Light3D:
			node.remove_child(child)
			child.free()
	node.set_script(null)


func instantiate_model(id: String) -> Node3D:
	if not _templates.has(id):
		return null
	var inst: Node3D = _templates[id].duplicate()
	return inst


func get_model_aabb(id: String) -> AABB:
	return _template_aabbs.get(id, AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE))


## Caixa envolvente de todas as malhas, no espaço do nó raiz.
static func compute_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item = stack.pop_back()
		var node: Node = item[0]
		var xf: Transform3D = item[1]
		if node is MeshInstance3D and node.mesh:
			var box: AABB = xf * node.mesh.get_aabb()
			if first:
				result = box
				first = false
			else:
				result = result.merge(box)
		for c in node.get_children():
			if c is Node3D:
				stack.append([c, xf * c.transform])
	if first:
		return AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	return result


## Coleta os triângulos (no espaço do nó raiz) para criar colisões.
static func collect_faces(root: Node3D, max_tris := 30000) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item = stack.pop_back()
		var node: Node = item[0]
		var xf: Transform3D = item[1]
		if node is MeshInstance3D and node.mesh:
			var f: PackedVector3Array = node.mesh.get_faces()
			for i in f.size():
				f[i] = xf * f[i]
			faces.append_array(f)
			if faces.size() / 3 > max_tris:
				return PackedVector3Array()
		for c in node.get_children():
			if c is Node3D:
				stack.append([c, xf * c.transform])
	return faces


# --------------------------------------------------------------------------
# Importação
# --------------------------------------------------------------------------

## Importa um arquivo para o projeto. `source` pode ser um caminho comum ou um
## URI content:// devolvido pelo seletor de arquivos do Android.
## `info` aceita: name, license, origin, author.
func import_file(source: String, original_name: String, info := {}) -> Dictionary:
	if pid == "":
		return {"ok": false, "error": "Nenhum projeto aberto."}
	if entries.size() >= PSData.MAX_ASSETS:
		return {"ok": false, "error": "Limite de assets do projeto atingido."}
	if original_name.is_empty():
		original_name = PSFileAccessHelper.display_name(source)
	var ext := original_name.get_extension().to_lower()
	var bytes := FileAccess.get_file_as_bytes(source)
	if bytes.is_empty():
		var open_err := FileAccess.get_open_error()
		return {"ok": false, "error": "Não foi possível ler o arquivo (%s)." % error_string(open_err)}
	# URIs do Android nem sempre trazem a extensão: identifica pelo conteúdo.
	if PSAssetValidator.detect_type(ext) == "":
		var sniffed := PSFileAccessHelper.sniff_extension(bytes)
		if PSAssetValidator.detect_type(sniffed) != "":
			ext = sniffed
			if original_name.get_extension().is_empty():
				original_name += "." + ext
	return import_bytes(bytes, original_name, ext, info, source.get_base_dir() if not source.begins_with("content://") else "")


func import_bytes(bytes: PackedByteArray, original_name: String, ext: String, info := {}, base_dir := "") -> Dictionary:
	var check := PSAssetValidator.validate_bytes(bytes, ext)
	if not check["ok"]:
		return check
	var sha := _sha256(bytes)
	for e in entries.values():
		if e["sha256"] == sha:
			return {"ok": false, "error": "Este arquivo já foi importado como \"%s\"." % e["name"], "duplicate": e["id"]}
	var type: String = check["type"]
	var id := App.new_id("a")
	var stats := {}
	var store_bytes := bytes
	var store_ext := ext
	if type == "model":
		var external: Array = check.get("external", [])
		if not external.is_empty():
			if base_dir.is_empty():
				return {"ok": false, "error": "Este .gltf depende de arquivos externos (%s). No celular, use o formato GLB (arquivo único)." % ", ".join(external)}
			for ref in external:
				var ref_path := base_dir.path_join(ref)
				if not FileAccess.file_exists(ref_path):
					return {"ok": false, "error": "Arquivo referenciado pelo modelo não encontrado: %s" % ref}
				var ref_len := FileAccess.get_file_as_bytes(ref_path).size()
				if ref_len > PSAssetValidator.MAX_MODEL_BYTES:
					return {"ok": false, "error": "Arquivo referenciado grande demais: %s" % ref}
		var res := PSAssetValidator.inspect_model(bytes, base_dir)
		if not res["ok"]:
			return res
		stats = res["stats"]
		if ext == "gltf":
			# Converte para GLB (arquivo único e autocontido dentro do projeto).
			var doc: GLTFDocument = res["doc"]
			var scene := doc.generate_scene(res["state"])
			if scene == null:
				return {"ok": false, "error": "Falha ao converter o glTF."}
			var out_state := GLTFState.new()
			var out_doc := GLTFDocument.new()
			var err := out_doc.append_from_scene(scene, out_state)
			scene.free()
			if err != OK:
				return {"ok": false, "error": "Falha ao converter o glTF para GLB (%s)." % error_string(err)}
			store_bytes = out_doc.generate_buffer(out_state)
			store_ext = "glb"
			if store_bytes.is_empty():
				return {"ok": false, "error": "Falha ao converter o glTF para GLB."}
	else:
		var img_res := PSAssetValidator.inspect_image(bytes, ext)
		if not img_res["ok"]:
			return img_res
		stats = img_res["stats"]
		if store_ext == "jpeg":
			store_ext = "jpg"
	var rel := "assets/%s.%s" % [id, store_ext]
	DirAccess.make_dir_recursive_absolute(PSProjectStore.assets_dir(pid))
	var f := FileAccess.open(PSProjectStore.project_dir(pid).path_join(rel), FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Não foi possível gravar o asset (%s)." % error_string(FileAccess.get_open_error())}
	f.store_buffer(store_bytes)
	f.close()
	var display_name := String(info.get("name", "")).strip_edges()
	if display_name.is_empty():
		display_name = original_name.get_basename().substr(0, PSData.MAX_NAME)
	var entry := PSData.sanitize_asset_entry({
		"id": id,
		"type": type,
		"name": display_name,
		"file": rel,
		"size": store_bytes.size(),
		"sha256": sha,
		"license": String(info.get("license", "Desconhecida")),
		"origin": String(info.get("origin", "")),
		"author": String(info.get("author", "")),
		"original_name": original_name,
		"imported": Time.get_unix_time_from_system(),
		"stats": stats,
	})
	entries[id] = entry
	_order.append(id)
	library_changed.emit()
	App.log_info("Asset importado: %s (%s, %s)." % [display_name, type, App.format_bytes(store_bytes.size())], "Assets")
	return {"ok": true, "entry": entry}


func update_info(id: String, info: Dictionary) -> void:
	if not entries.has(id):
		return
	var e: Dictionary = entries[id]
	for k in ["name", "license", "origin", "author"]:
		if info.has(k):
			e[k] = String(info[k]).substr(0, 200 if k == "origin" else PSData.MAX_NAME)
	library_changed.emit()


func remove_asset(id: String) -> void:
	if not entries.has(id):
		return
	var path := file_path(id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	entries.erase(id)
	_order.erase(id)
	if _templates.has(id):
		_templates[id].free()
		_templates.erase(id)
	_textures.erase(id)
	_failed.erase(id)
	library_changed.emit()


static func _sha256(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()
