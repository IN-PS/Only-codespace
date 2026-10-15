class_name PSProjectStore
extends RefCounted
## Armazenamento local dos projetos.
##
## Estrutura em disco (dentro de user://, que no Android é o armazenamento
## interno do aplicativo e funciona sem conexão):
##
##   user://projects/<id>/project.json      projeto salvo
##   user://projects/<id>/project.json.bak  cópia do salvamento anterior
##   user://projects/<id>/autosave.json     salvamento automático (recuperação)
##   user://projects/<id>/meta.json         resumo para a lista de projetos
##   user://projects/<id>/versions/*.json   versões guardadas
##   user://projects/<id>/assets/*          modelos e texturas importados
##
## Toda escrita é atômica: grava em ".tmp", relê e valida, e só então
## substitui o arquivo final. Uma queda no meio da gravação nunca corrompe
## o último salvamento bom.

const PROJECTS_DIR := "user://projects"
const BACKUPS_DIR := "user://backups"
const TMP_DIR := "user://tmp"
const BACKUP_FORMAT := "pocketstudio3d.backup"
const MAX_BACKUP_BYTES := 300 * 1024 * 1024
const MAX_BACKUP_FILES := 600


static func ensure_dirs() -> void:
	for d in [PROJECTS_DIR, BACKUPS_DIR, TMP_DIR]:
		if not DirAccess.dir_exists_absolute(d):
			DirAccess.make_dir_recursive_absolute(d)


static func is_valid_pid(pid: String) -> bool:
	if pid.is_empty() or pid.length() > 64:
		return false
	for c in pid:
		if not (c.is_valid_identifier() or c.is_valid_int() or c == "-"):
			return false
	return true


static func project_dir(pid: String) -> String:
	return PROJECTS_DIR.path_join(pid)


static func project_file(pid: String) -> String:
	return project_dir(pid).path_join("project.json")


static func assets_dir(pid: String) -> String:
	return project_dir(pid).path_join("assets")


static func autosave_file(pid: String) -> String:
	return project_dir(pid).path_join("autosave.json")


static func versions_dir(pid: String) -> String:
	return project_dir(pid).path_join("versions")


static func project_exists(pid: String) -> bool:
	return is_valid_pid(pid) and FileAccess.file_exists(project_file(pid))


# --------------------------------------------------------------------------
# JSON atômico
# --------------------------------------------------------------------------

static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


static func write_json_atomic(path: String, data: Variant, keep_backup := false) -> Error:
	var text := JSON.stringify(data, "", false)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.flush()
	var write_err := f.get_error()
	f.close()
	if write_err != OK:
		DirAccess.remove_absolute(tmp)
		return write_err
	# Confere se o que foi gravado é legível antes de substituir o original.
	var check := FileAccess.get_file_as_string(tmp)
	if check.length() != text.length() or JSON.parse_string(check) == null:
		DirAccess.remove_absolute(tmp)
		return ERR_FILE_CORRUPT
	if FileAccess.file_exists(path):
		if keep_backup:
			DirAccess.copy_absolute(path, path + ".bak")
		var err := DirAccess.rename_absolute(tmp, path)
		if err != OK:
			DirAccess.remove_absolute(path)
			err = DirAccess.rename_absolute(tmp, path)
		return err
	return DirAccess.rename_absolute(tmp, path)


# --------------------------------------------------------------------------
# Projetos
# --------------------------------------------------------------------------

static func make_pid(project_name: String) -> String:
	var slug := ""
	for c in project_name.to_lower().strip_edges():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			slug += c
		elif slug.length() > 0 and not slug.ends_with("-"):
			slug += "-"
	slug = slug.trim_suffix("-").substr(0, 24)
	if slug.is_empty():
		slug = "projeto"
	var pid := "%s-%x" % [slug, randi() % 0xfffff]
	while DirAccess.dir_exists_absolute(project_dir(pid)):
		pid = "%s-%x" % [slug, randi() % 0xfffff]
	return pid


static func list_projects() -> Array:
	ensure_dirs()
	var out: Array = []
	var dir := DirAccess.open(PROJECTS_DIR)
	if dir == null:
		return out
	for pid in dir.get_directories():
		if not is_valid_pid(pid):
			continue
		var has_main := FileAccess.file_exists(project_file(pid))
		var has_auto := FileAccess.file_exists(autosave_file(pid))
		if not has_main and not has_auto:
			continue
		var meta = read_json(project_dir(pid).path_join("meta.json"))
		var info := {"id": pid, "name": pid, "modified": 0.0, "objects": 0, "recovery": has_recovery(pid), "broken": false}
		if meta is Dictionary:
			info["name"] = String(meta.get("name", pid)).substr(0, PSData.MAX_NAME)
			info["modified"] = float(meta.get("modified", 0.0))
			info["objects"] = int(meta.get("objects", 0))
		else:
			var data = read_json(project_file(pid))
			var clean := PSData.sanitize_project(data)
			if clean.is_empty():
				info["broken"] = true
			else:
				info["name"] = clean["name"]
				info["modified"] = clean["modified"]
				info["objects"] = clean["objects"].size()
		out.append(info)
	out.sort_custom(func(a, b): return a["modified"] > b["modified"])
	return out


static func create_project(project_name: String, data: Dictionary = {}) -> String:
	ensure_dirs()
	var pid := make_pid(project_name)
	DirAccess.make_dir_recursive_absolute(assets_dir(pid))
	DirAccess.make_dir_recursive_absolute(versions_dir(pid))
	var d := data.duplicate(true) if not data.is_empty() else PSData.new_project_data(project_name)
	d["name"] = project_name.substr(0, PSData.MAX_NAME)
	var now := Time.get_unix_time_from_system()
	d["created"] = now
	d["modified"] = now
	if save_project(pid, d, false) != OK:
		return ""
	return pid


## Carrega um projeto. Se o arquivo principal estiver corrompido, tenta a cópia .bak.
static func load_project(pid: String) -> Dictionary:
	if not is_valid_pid(pid):
		return {"ok": false, "error": "Identificador de projeto inválido."}
	var data := PSData.sanitize_project(read_json(project_file(pid)))
	if not data.is_empty():
		return {"ok": true, "data": data, "used_backup": false}
	var bak := PSData.sanitize_project(read_json(project_file(pid) + ".bak"))
	if not bak.is_empty():
		return {"ok": true, "data": bak, "used_backup": true}
	var auto := PSData.sanitize_project(read_json(autosave_file(pid)))
	if not auto.is_empty():
		return {"ok": true, "data": auto, "used_backup": true}
	return {"ok": false, "error": "O arquivo do projeto está ausente ou corrompido."}


static func save_project(pid: String, data: Dictionary, keep_backup := true) -> Error:
	if not is_valid_pid(pid):
		return ERR_INVALID_PARAMETER
	if not DirAccess.dir_exists_absolute(project_dir(pid)):
		DirAccess.make_dir_recursive_absolute(project_dir(pid))
	data["modified"] = Time.get_unix_time_from_system()
	data["app_version"] = App.VERSION
	var err := write_json_atomic(project_file(pid), data, keep_backup)
	if err != OK:
		return err
	_write_meta(pid, data)
	# Um salvamento explícito torna a recuperação automática obsoleta.
	if FileAccess.file_exists(autosave_file(pid)):
		DirAccess.remove_absolute(autosave_file(pid))
	return OK


static func _write_meta(pid: String, data: Dictionary) -> void:
	var meta := {
		"name": data.get("name", pid),
		"modified": data.get("modified", 0.0),
		"objects": (data.get("objects", []) as Array).size(),
	}
	write_json_atomic(project_dir(pid).path_join("meta.json"), meta)


static func autosave(pid: String, data: Dictionary) -> Error:
	if not is_valid_pid(pid):
		return ERR_INVALID_PARAMETER
	var d := data.duplicate(false)
	d["modified"] = Time.get_unix_time_from_system()
	return write_json_atomic(autosave_file(pid), d)


static func has_recovery(pid: String) -> bool:
	var a := autosave_file(pid)
	if not FileAccess.file_exists(a):
		return false
	var p := project_file(pid)
	if not FileAccess.file_exists(p):
		return true
	return FileAccess.get_modified_time(a) >= FileAccess.get_modified_time(p)


static func load_recovery(pid: String) -> Dictionary:
	var data := PSData.sanitize_project(read_json(autosave_file(pid)))
	if data.is_empty():
		return {"ok": false, "error": "O salvamento automático está corrompido."}
	return {"ok": true, "data": data}


static func discard_recovery(pid: String) -> void:
	if FileAccess.file_exists(autosave_file(pid)):
		DirAccess.remove_absolute(autosave_file(pid))


static func rename_project(pid: String, new_name: String) -> Error:
	var res := load_project(pid)
	if not res["ok"]:
		return ERR_FILE_CORRUPT
	var data: Dictionary = res["data"]
	data["name"] = new_name.strip_edges().substr(0, PSData.MAX_NAME)
	return save_project(pid, data)


static func duplicate_project(pid: String, new_name: String) -> String:
	var res := load_project(pid)
	if not res["ok"]:
		return ""
	var new_pid := make_pid(new_name)
	if _copy_dir(project_dir(pid), project_dir(new_pid)) != OK:
		delete_project(new_pid)
		return ""
	var data: Dictionary = res["data"]
	data["name"] = new_name.substr(0, PSData.MAX_NAME)
	data["created"] = Time.get_unix_time_from_system()
	discard_recovery(new_pid)
	if save_project(new_pid, data, false) != OK:
		delete_project(new_pid)
		return ""
	return new_pid


static func delete_project(pid: String) -> Error:
	if not is_valid_pid(pid):
		return ERR_INVALID_PARAMETER
	var path := project_dir(pid)
	if not DirAccess.dir_exists_absolute(path):
		return ERR_DOES_NOT_EXIST
	return _remove_dir(path)


static func _copy_dir(from: String, to: String) -> Error:
	DirAccess.make_dir_recursive_absolute(to)
	var dir := DirAccess.open(from)
	if dir == null:
		return DirAccess.get_open_error()
	for f in dir.get_files():
		var err := DirAccess.copy_absolute(from.path_join(f), to.path_join(f))
		if err != OK:
			return err
	for sub in dir.get_directories():
		var err := _copy_dir(from.path_join(sub), to.path_join(sub))
		if err != OK:
			return err
	return OK


static func _remove_dir(path: String) -> Error:
	# Proteção: só apaga dentro das pastas do aplicativo.
	if not (path.begins_with(PROJECTS_DIR + "/") or path.begins_with(TMP_DIR + "/")):
		return ERR_UNAUTHORIZED
	var dir := DirAccess.open(path)
	if dir == null:
		return DirAccess.get_open_error()
	dir.include_hidden = true
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub in dir.get_directories():
		_remove_dir(path.path_join(sub))
	return DirAccess.remove_absolute(path)


# --------------------------------------------------------------------------
# Versões
# --------------------------------------------------------------------------

static func save_version(pid: String, data: Dictionary, label := "") -> Error:
	if not is_valid_pid(pid):
		return ERR_INVALID_PARAMETER
	DirAccess.make_dir_recursive_absolute(versions_dir(pid))
	var now := Time.get_unix_time_from_system()
	var fname := "v%d_%04d.json" % [int(now), randi() % 10000]
	var entry := {"label": label.substr(0, PSData.MAX_NAME), "time": now, "data": data}
	var err := write_json_atomic(versions_dir(pid).path_join(fname), entry)
	if err == OK:
		prune_versions(pid, int(App.get_setting("max_versions", 15)))
	return err


static func list_versions(pid: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(versions_dir(pid))
	if dir == null:
		return out
	for f in dir.get_files():
		if not (f.begins_with("v") and f.ends_with(".json")):
			continue
		var path := versions_dir(pid).path_join(f)
		var entry = read_json(path)
		if not (entry is Dictionary):
			continue
		var objects := 0
		if entry.get("data") is Dictionary and entry["data"].get("objects") is Array:
			objects = entry["data"]["objects"].size()
		out.append({
			"file": f,
			"label": String(entry.get("label", "")),
			"time": float(entry.get("time", 0.0)),
			"objects": objects,
			"bytes": FileAccess.get_size(path) if FileAccess.file_exists(path) else 0,
		})
	out.sort_custom(func(a, b): return a["time"] > b["time"])
	return out


static func load_version(pid: String, file: String) -> Dictionary:
	if file.contains("/") or file.contains("\\") or file.contains(".."):
		return {"ok": false, "error": "Nome de versão inválido."}
	var entry = read_json(versions_dir(pid).path_join(file))
	if not (entry is Dictionary):
		return {"ok": false, "error": "Versão ilegível."}
	var data := PSData.sanitize_project(entry.get("data"))
	if data.is_empty():
		return {"ok": false, "error": "Versão corrompida."}
	return {"ok": true, "data": data}


static func delete_version(pid: String, file: String) -> Error:
	if file.contains("/") or file.contains("\\") or file.contains(".."):
		return ERR_INVALID_PARAMETER
	return DirAccess.remove_absolute(versions_dir(pid).path_join(file))


static func prune_versions(pid: String, keep: int) -> void:
	var versions := list_versions(pid)
	for i in range(keep, versions.size()):
		delete_version(pid, versions[i]["file"])


# --------------------------------------------------------------------------
# Backups (.zip)
# --------------------------------------------------------------------------

## Gera um backup .zip do projeto e retorna o caminho do arquivo ("" em caso de erro).
static func export_backup(pid: String, dest_path := "") -> String:
	ensure_dirs()
	var res := load_project(pid)
	if not res["ok"]:
		return ""
	var data: Dictionary = res["data"]
	if dest_path.is_empty():
		var d := Time.get_datetime_dict_from_system()
		dest_path = BACKUPS_DIR.path_join("%s_%04d%02d%02d_%02d%02d.zip" % [pid, d.year, d.month, d.day, d.hour, d.minute])
	var zip := ZIPPacker.new()
	if zip.open(dest_path) != OK:
		return ""
	var files: Array = []
	var project_bytes := JSON.stringify(data).to_utf8_buffer()
	_zip_add(zip, "project.json", project_bytes)
	files.append({"path": "project.json", "size": project_bytes.size()})
	var adir := DirAccess.open(assets_dir(pid))
	if adir != null:
		for f in adir.get_files():
			var bytes := FileAccess.get_file_as_bytes(assets_dir(pid).path_join(f))
			_zip_add(zip, "assets/" + f, bytes)
			files.append({"path": "assets/" + f, "size": bytes.size()})
	var manifest := {
		"format": BACKUP_FORMAT,
		"version": 1,
		"app_version": App.VERSION,
		"project_name": data.get("name", pid),
		"created": Time.get_unix_time_from_system(),
		"files": files,
	}
	_zip_add(zip, "backup.json", JSON.stringify(manifest, "\t").to_utf8_buffer())
	zip.close()
	return dest_path


static func _zip_add(zip: ZIPPacker, name: String, bytes: PackedByteArray) -> void:
	zip.start_file(name)
	zip.write_file(bytes)
	zip.close_file()


static func _is_safe_zip_entry(path: String) -> bool:
	if path == "project.json" or path == "backup.json":
		return true
	if not path.begins_with("assets/"):
		return false
	var fname := path.substr(7)
	if fname.is_empty() or fname.contains("/") or fname.contains("\\") or fname.contains("..") or fname.begins_with("."):
		return false
	return PSAssetValidator.is_allowed_extension(fname.get_extension().to_lower())


## Importa um backup .zip como um projeto novo. Nada do arquivo é executado:
## somente o JSON do projeto e assets com extensões permitidas são extraídos.
static func import_backup(zip_path: String) -> Dictionary:
	ensure_dirs()
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return {"ok": false, "error": "Não foi possível abrir o arquivo .zip."}
	var names := zip.get_files()
	if not names.has("project.json"):
		zip.close()
		return {"ok": false, "error": "O arquivo não é um backup do Pocket Studio 3D (project.json ausente)."}
	if names.size() > MAX_BACKUP_FILES:
		zip.close()
		return {"ok": false, "error": "O backup tem arquivos demais."}
	for n in names:
		if n.ends_with("/"):
			continue
		if not _is_safe_zip_entry(n):
			zip.close()
			return {"ok": false, "error": "O backup contém um arquivo não permitido: %s" % n}
	var data := PSData.sanitize_project(JSON.parse_string(zip.read_file("project.json").get_string_from_utf8()))
	if data.is_empty():
		zip.close()
		return {"ok": false, "error": "O project.json do backup é inválido."}
	var pid := make_pid(String(data.get("name", "projeto")))
	DirAccess.make_dir_recursive_absolute(assets_dir(pid))
	DirAccess.make_dir_recursive_absolute(versions_dir(pid))
	var total := 0
	for n in names:
		if not n.begins_with("assets/") or n.ends_with("/"):
			continue
		var bytes := zip.read_file(n)
		total += bytes.size()
		if total > MAX_BACKUP_BYTES:
			zip.close()
			delete_project(pid)
			return {"ok": false, "error": "O backup excede o limite de %s." % App.format_bytes(MAX_BACKUP_BYTES)}
		var f := FileAccess.open(project_dir(pid).path_join(n), FileAccess.WRITE)
		if f == null:
			zip.close()
			delete_project(pid)
			return {"ok": false, "error": "Falha ao gravar %s." % n}
		f.store_buffer(bytes)
		f.close()
	zip.close()
	# Remove referências a assets cujo arquivo não veio no backup.
	var kept: Array = []
	for a in data["assets"]:
		if FileAccess.file_exists(project_dir(pid).path_join(a["file"])):
			kept.append(a)
	data["assets"] = kept
	if save_project(pid, data, false) != OK:
		delete_project(pid)
		return {"ok": false, "error": "Falha ao salvar o projeto importado."}
	return {"ok": true, "pid": pid, "name": data["name"]}
