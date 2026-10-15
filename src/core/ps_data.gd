class_name PSData
extends RefCounted
## Esquema dos dados de projeto e funções de (de)serialização.
##
## Todo arquivo lido do disco passa por `sanitize_project()`, que descarta
## campos desconhecidos, corrige tipos e limita valores. Assim um arquivo
## corrompido ou malicioso não consegue derrubar o editor.

const FORMAT := "pocketstudio3d.project"
const FORMAT_VERSION := 1

const OBJECT_TYPES := ["part", "group", "model", "light", "spawn", "water", "text"]
const SHAPES := ["box", "sphere", "cylinder", "cone", "capsule", "wedge", "torus", "pyramid"]
const PHYS_MODES := ["static", "dynamic", "kinematic", "none"]
const LIGHT_KINDS := ["point", "spot"]
const SKIES := ["day", "sunset", "night", "overcast"]
const CAMERA_MODES := ["third", "first"]
const ASSET_TYPES := ["model", "texture"]

const MAX_OBJECTS := 5000
const MAX_SCRIPTS := 200
const MAX_ASSETS := 500
const MAX_NAME := 64
const MAX_CODE := 100000
const MAX_COORD := 10000.0
const MIN_SIZE := 0.01
const MAX_SIZE := 2000.0

const TYPE_LABELS := {
	"part": "Peça",
	"group": "Grupo",
	"model": "Modelo",
	"light": "Luz",
	"spawn": "Ponto de início",
	"water": "Água",
	"text": "Texto 3D",
}

const SHAPE_LABELS := {
	"box": "Cubo",
	"sphere": "Esfera",
	"cylinder": "Cilindro",
	"cone": "Cone",
	"capsule": "Cápsula",
	"wedge": "Rampa",
	"torus": "Toro",
	"pyramid": "Pirâmide",
}

const PHYS_LABELS := {
	"static": "Fixo",
	"dynamic": "Dinâmico (cai e colide)",
	"kinematic": "Móvel por script",
	"none": "Sem colisão",
}


# --------------------------------------------------------------------------
# Conversões
# --------------------------------------------------------------------------

static func v3_to_arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


static func arr_to_v3(a: Variant, fallback := Vector3.ZERO) -> Vector3:
	if a is Array and a.size() >= 3:
		var out := Vector3(_f(a[0], fallback.x), _f(a[1], fallback.y), _f(a[2], fallback.z))
		return out
	return fallback


static func quat_to_arr(q: Quaternion) -> Array:
	q = q.normalized()
	return [snappedf(q.x, 0.000001), snappedf(q.y, 0.000001), snappedf(q.z, 0.000001), snappedf(q.w, 0.000001)]


static func arr_to_quat(a: Variant) -> Quaternion:
	if a is Array and a.size() >= 4:
		var q := Quaternion(_f(a[0], 0.0), _f(a[1], 0.0), _f(a[2], 0.0), _f(a[3], 1.0))
		if q.length_squared() < 0.000001:
			return Quaternion.IDENTITY
		return q.normalized()
	return Quaternion.IDENTITY


static func color_to_arr(c: Color) -> Array:
	return [snappedf(c.r, 0.001), snappedf(c.g, 0.001), snappedf(c.b, 0.001), snappedf(c.a, 0.001)]


static func arr_to_color(a: Variant, fallback := Color.WHITE) -> Color:
	if a is Array and a.size() >= 3:
		var alpha := _f(a[3], 1.0) if a.size() >= 4 else 1.0
		return Color(
			clampf(_f(a[0], fallback.r), 0.0, 1.0),
			clampf(_f(a[1], fallback.g), 0.0, 1.0),
			clampf(_f(a[2], fallback.b), 0.0, 1.0),
			clampf(alpha, 0.0, 1.0))
	return fallback


static func _f(v: Variant, fallback: float) -> float:
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		var x := float(v)
		if is_finite(x):
			return x
	return fallback


# --------------------------------------------------------------------------
# Padrões
# --------------------------------------------------------------------------

static func default_material(color := Color(0.78, 0.79, 0.82)) -> Dictionary:
	return {
		"color": color_to_arr(color),
		"metal": 0.0,
		"rough": 0.8,
		"emit": 0.0,
		"tex": "",
		"uv": 1.0,
	}


static func default_physics(mode := "static") -> Dictionary:
	return {"mode": mode, "mass": 1.0, "friction": 0.6, "bounce": 0.0}


static func default_light() -> Dictionary:
	return {"kind": "point", "color": color_to_arr(Color(1.0, 0.92, 0.8)), "energy": 2.0, "range": 8.0, "angle": 35.0, "shadow": false}


static func default_environment() -> Dictionary:
	return {
		"sky": "day",
		"sun_yaw": -40.0,
		"sun_pitch": -55.0,
		"sun_energy": 1.0,
		"ambient": 0.6,
		"fog": false,
		"fog_density": 0.01,
		"gravity": 9.8,
	}


static func default_game() -> Dictionary:
	return {
		"camera": "third",
		"walk_speed": 6.0,
		"jump": 7.0,
		"start_message": "",
		"respawn_y": -40.0,
	}


## Cria o dicionário de um novo objeto do tipo indicado com valores padrão.
static func new_object(type: String, extra := {}) -> Dictionary:
	var d := {
		"id": "",
		"type": type,
		"name": TYPE_LABELS.get(type, "Objeto"),
		"parent": "",
		"pos": [0.0, 0.0, 0.0],
		"rot": [0.0, 0.0, 0.0, 1.0],
		"visible": true,
		"locked": false,
		"script": "",
	}
	match type:
		"part":
			d["shape"] = "box"
			d["size"] = [1.0, 1.0, 1.0]
			d["mat"] = default_material()
			d["phys"] = default_physics()
			d["shadow"] = true
		"model":
			d["asset"] = ""
			d["size"] = [1.0, 1.0, 1.0]
			d["phys"] = default_physics()
			d["shadow"] = true
		"light":
			d["light"] = default_light()
		"water":
			d["size"] = [20.0, 1.0, 20.0]
			d["mat"] = default_material(Color(0.15, 0.45, 0.75, 0.7))
		"text":
			d["text"] = "Olá!"
			d["size"] = [1.0, 1.0, 1.0]
			d["mat"] = default_material(Color(1, 1, 1))
		"spawn", "group":
			pass
	for k in extra:
		d[k] = extra[k]
	if d.has("shape") and extra.has("shape"):
		d["name"] = SHAPE_LABELS.get(d["shape"], d["name"])
	if extra.has("name"):
		d["name"] = extra["name"]
	return d


static func new_project_data(project_name: String) -> Dictionary:
	var now := Time.get_unix_time_from_system()
	return {
		"format": FORMAT,
		"format_version": FORMAT_VERSION,
		"app_version": "0.1.0",
		"name": project_name,
		"created": now,
		"modified": now,
		"env": default_environment(),
		"game": default_game(),
		"objects": [],
		"terrain": null,
		"scripts": [],
		"assets": [],
		"editor": {},
	}


# --------------------------------------------------------------------------
# Sanitização
# --------------------------------------------------------------------------

static func _num(d: Dictionary, key: String, fallback: float, lo: float, hi: float) -> float:
	return clampf(_f(d.get(key), fallback), lo, hi)


static func _str(d: Dictionary, key: String, fallback: String, max_len: int) -> String:
	var v = d.get(key)
	if typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME:
		return String(v).substr(0, max_len)
	return fallback


static func _bool(d: Dictionary, key: String, fallback: bool) -> bool:
	var v = d.get(key)
	if typeof(v) == TYPE_BOOL:
		return v
	return fallback


static func _enum(d: Dictionary, key: String, options: Array, fallback: String) -> String:
	var v = d.get(key)
	if typeof(v) == TYPE_STRING and options.has(v):
		return v
	return fallback


static func _safe_id(v: Variant) -> String:
	if typeof(v) != TYPE_STRING:
		return ""
	var s: String = v
	if s.length() > 48:
		return ""
	for c in s:
		if not (c.is_valid_identifier() or c.is_valid_int() or c == "-"):
			return ""
	return s


static func sanitize_v3(v: Variant, fallback: Vector3, lo: float, hi: float) -> Array:
	var x := arr_to_v3(v, fallback)
	return v3_to_arr(Vector3(clampf(x.x, lo, hi), clampf(x.y, lo, hi), clampf(x.z, lo, hi)))


static func sanitize_material(m: Variant, fallback_color := Color(0.78, 0.79, 0.82)) -> Dictionary:
	var d: Dictionary = m if m is Dictionary else {}
	return {
		"color": color_to_arr(arr_to_color(d.get("color"), fallback_color)),
		"metal": _num(d, "metal", 0.0, 0.0, 1.0),
		"rough": _num(d, "rough", 0.8, 0.0, 1.0),
		"emit": _num(d, "emit", 0.0, 0.0, 16.0),
		"tex": _safe_id(d.get("tex", "")),
		"uv": _num(d, "uv", 1.0, 0.01, 100.0),
	}


static func sanitize_physics(p: Variant) -> Dictionary:
	var d: Dictionary = p if p is Dictionary else {}
	return {
		"mode": _enum(d, "mode", PHYS_MODES, "static"),
		"mass": _num(d, "mass", 1.0, 0.01, 10000.0),
		"friction": _num(d, "friction", 0.6, 0.0, 1.0),
		"bounce": _num(d, "bounce", 0.0, 0.0, 1.0),
	}


static func sanitize_light(l: Variant) -> Dictionary:
	var d: Dictionary = l if l is Dictionary else {}
	return {
		"kind": _enum(d, "kind", LIGHT_KINDS, "point"),
		"color": color_to_arr(arr_to_color(d.get("color"), Color(1, 0.92, 0.8))),
		"energy": _num(d, "energy", 2.0, 0.0, 16.0),
		"range": _num(d, "range", 8.0, 0.1, 200.0),
		"angle": _num(d, "angle", 35.0, 1.0, 89.0),
		"shadow": _bool(d, "shadow", false),
	}


## Retorna um objeto válido ou um dicionário vazio se não for recuperável.
static func sanitize_object(o: Variant) -> Dictionary:
	if not (o is Dictionary):
		return {}
	var src: Dictionary = o
	var type := _enum(src, "type", OBJECT_TYPES, "")
	if type == "":
		return {}
	var id := _safe_id(src.get("id"))
	if id == "":
		return {}
	var d := new_object(type)
	d["id"] = id
	d["name"] = _str(src, "name", d["name"], MAX_NAME)
	d["parent"] = _safe_id(src.get("parent", ""))
	d["pos"] = sanitize_v3(src.get("pos"), Vector3.ZERO, -MAX_COORD, MAX_COORD)
	d["rot"] = quat_to_arr(arr_to_quat(src.get("rot")))
	d["visible"] = _bool(src, "visible", true)
	d["locked"] = _bool(src, "locked", false)
	d["script"] = _safe_id(src.get("script", ""))
	match type:
		"part":
			d["shape"] = _enum(src, "shape", SHAPES, "box")
			d["size"] = sanitize_v3(src.get("size"), Vector3.ONE, MIN_SIZE, MAX_SIZE)
			d["mat"] = sanitize_material(src.get("mat"))
			d["phys"] = sanitize_physics(src.get("phys"))
			d["shadow"] = _bool(src, "shadow", true)
		"model":
			d["asset"] = _safe_id(src.get("asset", ""))
			d["size"] = sanitize_v3(src.get("size"), Vector3.ONE, MIN_SIZE, MAX_SIZE)
			d["phys"] = sanitize_physics(src.get("phys"))
			d["shadow"] = _bool(src, "shadow", true)
		"light":
			d["light"] = sanitize_light(src.get("light"))
		"water":
			d["size"] = sanitize_v3(src.get("size"), Vector3(20, 1, 20), MIN_SIZE, MAX_SIZE)
			d["mat"] = sanitize_material(src.get("mat"), Color(0.15, 0.45, 0.75, 0.7))
		"text":
			d["text"] = _str(src, "text", "Texto", 200)
			d["size"] = sanitize_v3(src.get("size"), Vector3.ONE, MIN_SIZE, MAX_SIZE)
			d["mat"] = sanitize_material(src.get("mat"), Color.WHITE)
	return d


static func sanitize_environment(e: Variant) -> Dictionary:
	var d: Dictionary = e if e is Dictionary else {}
	return {
		"sky": _enum(d, "sky", SKIES, "day"),
		"sun_yaw": _num(d, "sun_yaw", -40.0, -360.0, 360.0),
		"sun_pitch": _num(d, "sun_pitch", -55.0, -90.0, 0.0),
		"sun_energy": _num(d, "sun_energy", 1.0, 0.0, 8.0),
		"ambient": _num(d, "ambient", 0.6, 0.0, 4.0),
		"fog": _bool(d, "fog", false),
		"fog_density": _num(d, "fog_density", 0.01, 0.0, 0.5),
		"gravity": _num(d, "gravity", 9.8, 0.0, 100.0),
	}


static func sanitize_game(g: Variant) -> Dictionary:
	var d: Dictionary = g if g is Dictionary else {}
	return {
		"camera": _enum(d, "camera", CAMERA_MODES, "third"),
		"walk_speed": _num(d, "walk_speed", 6.0, 0.5, 50.0),
		"jump": _num(d, "jump", 7.0, 0.0, 50.0),
		"start_message": _str(d, "start_message", "", 200),
		"respawn_y": _num(d, "respawn_y", -40.0, -1000.0, 1000.0),
	}


static func sanitize_script_entry(s: Variant) -> Dictionary:
	if not (s is Dictionary):
		return {}
	var id := _safe_id(s.get("id"))
	if id == "":
		return {}
	return {
		"id": id,
		"name": _str(s, "name", "Script", MAX_NAME),
		"code": _str(s, "code", "", MAX_CODE),
		"enabled": _bool(s, "enabled", true),
		"global": _bool(s, "global", false),
	}


static func sanitize_asset_entry(a: Variant) -> Dictionary:
	if not (a is Dictionary):
		return {}
	var id := _safe_id(a.get("id"))
	var file := _str(a, "file", "", 128)
	# O arquivo precisa estar dentro da pasta "assets/" do projeto.
	if id == "" or not file.begins_with("assets/") or file.contains("..") or file.contains("\\"):
		return {}
	var type := _enum(a, "type", ASSET_TYPES, "")
	if type == "":
		return {}
	return {
		"id": id,
		"type": type,
		"name": _str(a, "name", "Asset", MAX_NAME),
		"file": file,
		"size": int(_num(a, "size", 0.0, 0.0, 1e10)),
		"sha256": _str(a, "sha256", "", 64),
		"license": _str(a, "license", "Desconhecida", 64),
		"origin": _str(a, "origin", "", 200),
		"author": _str(a, "author", "", 100),
		"original_name": _str(a, "original_name", "", 128),
		"imported": _num(a, "imported", 0.0, 0.0, 1e12),
		"stats": a.get("stats", {}) if a.get("stats", {}) is Dictionary else {},
	}


static func sanitize_terrain(t: Variant) -> Variant:
	if not (t is Dictionary):
		return null
	var d: Dictionary = t
	var size := int(_num(d, "size", 65, 9, 257))
	var heights_b64 := _str(d, "heights", "", 2000000)
	var colors_b64 := _str(d, "colors", "", 2000000)
	var veg: Array = []
	var src_veg = d.get("veg", [])
	if src_veg is Array:
		for group in src_veg:
			if not (group is Dictionary):
				continue
			var kind := _enum(group, "kind", ["tree", "pine", "bush", "rock", "grass"], "")
			if kind == "":
				continue
			var pts: Array = []
			var src_pts = group.get("p", [])
			if src_pts is Array:
				for p in src_pts:
					if p is Array and p.size() >= 5 and pts.size() < 5000:
						pts.append([_f(p[0], 0), _f(p[1], 0), _f(p[2], 0), _f(p[3], 0), clampf(_f(p[4], 1), 0.1, 10.0)])
			veg.append({"kind": kind, "p": pts})
	return {
		"size": size,
		"heights": heights_b64,
		"colors": colors_b64,
		"pos": sanitize_v3(d.get("pos"), Vector3.ZERO, -MAX_COORD, MAX_COORD),
		"veg": veg,
	}


## Corrige um projeto lido do disco. Retorna {} se não for um projeto válido.
static func sanitize_project(p: Variant) -> Dictionary:
	if not (p is Dictionary):
		return {}
	var src: Dictionary = p
	if src.get("format") != FORMAT:
		return {}
	var out := new_project_data(_str(src, "name", "Projeto", MAX_NAME))
	out["format_version"] = FORMAT_VERSION
	out["created"] = _num(src, "created", out["created"], 0.0, 1e12)
	out["modified"] = _num(src, "modified", out["modified"], 0.0, 1e12)
	out["app_version"] = _str(src, "app_version", "0.1.0", 16)
	out["env"] = sanitize_environment(src.get("env"))
	out["game"] = sanitize_game(src.get("game"))
	out["terrain"] = sanitize_terrain(src.get("terrain"))
	out["editor"] = src.get("editor", {}) if src.get("editor", {}) is Dictionary else {}

	var seen := {}
	var objects: Array = []
	var src_objects = src.get("objects", [])
	if src_objects is Array:
		for o in src_objects:
			if objects.size() >= MAX_OBJECTS:
				break
			var clean := sanitize_object(o)
			if clean.is_empty() or seen.has(clean["id"]):
				continue
			# O pai precisa vir antes do filho (ordem em profundidade).
			if clean["parent"] != "" and not seen.has(clean["parent"]):
				clean["parent"] = ""
			seen[clean["id"]] = true
			objects.append(clean)
	out["objects"] = objects

	var scripts: Array = []
	var seen_s := {}
	var src_scripts = src.get("scripts", [])
	if src_scripts is Array:
		for s in src_scripts:
			var clean_s := sanitize_script_entry(s)
			if clean_s.is_empty() or seen_s.has(clean_s["id"]) or scripts.size() >= MAX_SCRIPTS:
				continue
			seen_s[clean_s["id"]] = true
			scripts.append(clean_s)
	out["scripts"] = scripts

	var assets: Array = []
	var seen_a := {}
	var src_assets = src.get("assets", [])
	if src_assets is Array:
		for a in src_assets:
			var clean_a := sanitize_asset_entry(a)
			if clean_a.is_empty() or seen_a.has(clean_a["id"]) or assets.size() >= MAX_ASSETS:
				continue
			seen_a[clean_a["id"]] = true
			assets.append(clean_a)
	out["assets"] = assets
	return out
