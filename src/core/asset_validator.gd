class_name PSAssetValidator
extends RefCounted
## Validação de arquivos importados (modelos glTF/GLB e texturas).
##
## Regras de segurança:
##  - somente extensões de dados (nunca .gd, .tscn, .tres, .res, .scn ou executáveis);
##  - limite de tamanho por tipo;
##  - conferência da assinatura binária ("magic bytes"), não só da extensão;
##  - glTF: só referências internas ("data:") ou arquivos na mesma pasta,
##    sem URLs, caminhos absolutos ou "..";
##  - extensões glTF obrigatórias que o motor não suporta são recusadas;
##  - limites de vértices/nós para não travar celulares modestos.
## glTF/GLB são formatos de dados: carregá-los não executa código.

const MODEL_EXTS := ["glb", "gltf"]
const TEXTURE_EXTS := ["png", "jpg", "jpeg", "webp"]
const BUFFER_EXTS := ["bin"]

const MAX_MODEL_BYTES := 32 * 1024 * 1024
const MAX_TEXTURE_BYTES := 8 * 1024 * 1024
const MAX_TEXTURE_DIM := 4096
const MAX_VERTICES := 400000
const MAX_NODES := 3000

const GLB_MAGIC := 0x46546C67  # "glTF"
const GLB_CHUNK_JSON := 0x4E4F534A
const PNG_SIG := [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]


static func is_allowed_extension(ext: String) -> bool:
	return ext in MODEL_EXTS or ext in TEXTURE_EXTS or ext in BUFFER_EXTS


static func detect_type(ext: String) -> String:
	ext = ext.to_lower()
	if ext in MODEL_EXTS:
		return "model"
	if ext in TEXTURE_EXTS:
		return "texture"
	return ""


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


## Primeira etapa: valida bytes, extensão e assinatura. Não interpreta o conteúdo.
static func validate_bytes(bytes: PackedByteArray, ext: String) -> Dictionary:
	ext = ext.to_lower()
	var type := detect_type(ext)
	if type == "":
		return _fail("Formato não suportado (.%s). Use GLB, glTF, PNG, JPG ou WebP." % ext)
	if bytes.is_empty():
		return _fail("O arquivo está vazio.")
	if type == "model" and bytes.size() > MAX_MODEL_BYTES:
		return _fail("Modelo grande demais (%s). Limite: %s." % [App.format_bytes(bytes.size()), App.format_bytes(MAX_MODEL_BYTES)])
	if type == "texture" and bytes.size() > MAX_TEXTURE_BYTES:
		return _fail("Textura grande demais (%s). Limite: %s." % [App.format_bytes(bytes.size()), App.format_bytes(MAX_TEXTURE_BYTES)])
	match ext:
		"glb":
			return _check_glb(bytes)
		"gltf":
			return _check_gltf_json(bytes)
		"png":
			for i in PNG_SIG.size():
				if bytes.size() <= i or bytes[i] != PNG_SIG[i]:
					return _fail("O arquivo não é um PNG válido (assinatura incorreta).")
		"jpg", "jpeg":
			if bytes.size() < 3 or bytes[0] != 0xFF or bytes[1] != 0xD8 or bytes[2] != 0xFF:
				return _fail("O arquivo não é um JPEG válido (assinatura incorreta).")
		"webp":
			if bytes.size() < 12 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WEBP":
				return _fail("O arquivo não é um WebP válido (assinatura incorreta).")
	return {"ok": true, "type": type}


static func _check_glb(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 20:
		return _fail("Arquivo GLB truncado.")
	if bytes.decode_u32(0) != GLB_MAGIC:
		return _fail("O arquivo não é um GLB válido (assinatura incorreta).")
	var version := bytes.decode_u32(4)
	if version != 2:
		return _fail("Versão de GLB não suportada (%d). Use glTF 2.0." % version)
	var total := bytes.decode_u32(8)
	if total > bytes.size():
		return _fail("Arquivo GLB truncado ou corrompido.")
	var json_len := bytes.decode_u32(12)
	if bytes.decode_u32(16) != GLB_CHUNK_JSON or json_len == 0 or 20 + json_len > bytes.size():
		return _fail("Bloco JSON do GLB ausente ou corrompido.")
	var json_text := bytes.slice(20, 20 + json_len).get_string_from_utf8()
	return _check_gltf_structure(JSON.parse_string(json_text), true)


static func _check_gltf_json(bytes: PackedByteArray) -> Dictionary:
	var parsed = JSON.parse_string(bytes.get_string_from_utf8())
	return _check_gltf_structure(parsed, false)


static func _check_gltf_structure(gltf: Variant, is_glb: bool) -> Dictionary:
	if not (gltf is Dictionary):
		return _fail("O conteúdo glTF não é um JSON válido.")
	var asset = gltf.get("asset")
	if not (asset is Dictionary) or not String(asset.get("version", "")).begins_with("2"):
		return _fail("Somente glTF 2.0 é suportado.")
	var supported := GLTFDocument.get_supported_gltf_extensions()
	var required = gltf.get("extensionsRequired", [])
	if required is Array:
		for e in required:
			if not supported.has(String(e)):
				var hint := ""
				if String(e) == "KHR_draco_mesh_compression":
					hint = " Exporte o modelo sem compressão Draco."
				return _fail("O modelo exige a extensão \"%s\", que não é suportada.%s" % [e, hint])
	var external: Array = []
	for key in ["buffers", "images"]:
		var arr = gltf.get(key, [])
		if not (arr is Array):
			continue
		for item in arr:
			if not (item is Dictionary) or not item.has("uri"):
				continue
			var uri := String(item["uri"])
			if uri.begins_with("data:"):
				continue
			var check := check_relative_uri(uri)
			if not check.is_empty():
				return _fail(check)
			external.append(uri.uri_decode())
	var nodes = gltf.get("nodes", [])
	if nodes is Array and nodes.size() > MAX_NODES:
		return _fail("O modelo tem nós demais (%d). Limite: %d." % [nodes.size(), MAX_NODES])
	return {"ok": true, "type": "model", "external": external, "glb": is_glb}


## Retorna "" se a URI for um arquivo simples na mesma pasta; senão, a mensagem de erro.
static func check_relative_uri(uri: String) -> String:
	var u := uri.uri_decode()
	if u.contains("://") or u.begins_with("/") or u.begins_with("\\") or u.contains(":"):
		return "O modelo referencia um endereço externo (%s). Por segurança, só arquivos locais são aceitos." % uri
	if u.contains("..") or u.contains("/") or u.contains("\\"):
		return "O modelo referencia um arquivo fora da pasta dele (%s). Use um GLB ou coloque os arquivos na mesma pasta." % uri
	if not is_allowed_extension(u.get_extension().to_lower()):
		return "O modelo referencia um arquivo de tipo não permitido (%s)." % uri
	return ""


## Segunda etapa: interpreta o modelo e calcula estatísticas. Não instancia nada na cena.
static func inspect_model(bytes: PackedByteArray, base_path: String) -> Dictionary:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_buffer(bytes, base_path, state)
	if err != OK:
		return _fail("Falha ao ler o modelo (%s)." % error_string(err))
	var vertices := 0
	var triangles := 0
	for gmesh in state.get_meshes():
		var im: ImporterMesh = gmesh.mesh
		if im == null:
			continue
		for s in im.get_surface_count():
			var arrays := im.get_surface_arrays(s)
			var verts = arrays[Mesh.ARRAY_VERTEX]
			var idx = arrays[Mesh.ARRAY_INDEX]
			var vc: int = verts.size() if verts != null else 0
			vertices += vc
			triangles += (idx.size() / 3) if idx != null and idx.size() > 0 else vc / 3
	if vertices > MAX_VERTICES:
		return _fail("O modelo tem vértices demais (%d). Limite para celulares: %d." % [vertices, MAX_VERTICES])
	if vertices == 0:
		return _fail("O modelo não contém malhas visíveis.")
	return {
		"ok": true,
		"state": state,
		"doc": doc,
		"stats": {
			"meshes": state.get_meshes().size(),
			"vertices": vertices,
			"triangles": triangles,
			"materials": state.get_materials().size(),
			"textures": state.get_textures().size(),
			"animations": state.get_animations().size(),
			"nodes": state.get_nodes().size(),
		},
	}


static func inspect_image(bytes: PackedByteArray, ext: String) -> Dictionary:
	var img := Image.new()
	var err := FAILED
	match ext.to_lower():
		"png":
			err = img.load_png_from_buffer(bytes)
		"jpg", "jpeg":
			err = img.load_jpg_from_buffer(bytes)
		"webp":
			err = img.load_webp_from_buffer(bytes)
	if err != OK or img.is_empty():
		return _fail("Não foi possível decodificar a imagem.")
	if img.get_width() > MAX_TEXTURE_DIM or img.get_height() > MAX_TEXTURE_DIM:
		return _fail("Imagem grande demais (%dx%d). Limite: %dx%d." % [img.get_width(), img.get_height(), MAX_TEXTURE_DIM, MAX_TEXTURE_DIM])
	return {"ok": true, "image": img, "stats": {"width": img.get_width(), "height": img.get_height()}}
