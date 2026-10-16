class_name PSTemplates
extends RefCounted
## Modelos iniciais de projeto.

const LIST := [
	{"key": "empty", "name": "Base plana", "desc": "Uma base cinza, luz do sol e ponto de início."},
	{"key": "terrain", "name": "Ilha com terreno", "desc": "Terreno com colinas, água e árvores."},
	{"key": "obby", "name": "Percurso de plataformas", "desc": "Exemplo jogável: pule entre plataformas até a bandeira."},
	{"key": "blank", "name": "Vazio", "desc": "Só o céu. Comece do zero."},
]


static func _add(objects: Array, d: Dictionary) -> Dictionary:
	if String(d.get("id", "")) == "":
		d["id"] = App.new_id("o")
	objects.append(d)
	return d


static func _box(objects: Array, name: String, pos: Vector3, size: Vector3, color: Color, extra := {}) -> Dictionary:
	var d := PSData.new_object("part", {"shape": "box"})
	d["name"] = name
	d["pos"] = PSData.v3_to_arr(pos)
	d["size"] = PSData.v3_to_arr(size)
	d["mat"] = PSData.default_material(color)
	for k in extra:
		d[k] = extra[k]
	return _add(objects, d)


static func _spawn(objects: Array, pos: Vector3) -> void:
	var s := PSData.new_object("spawn")
	s["pos"] = PSData.v3_to_arr(pos)
	_add(objects, s)


static func create(key: String, project_name: String) -> Dictionary:
	var data := PSData.new_project_data(project_name)
	var objects: Array = []
	match key:
		"empty":
			_box(objects, "Base", Vector3(0, -0.5, 0), Vector3(64, 1, 64), Color(0.42, 0.5, 0.42), {"locked": true})
			_spawn(objects, Vector3(0, 0, 4))
		"terrain":
			data["terrain"] = PSTerrain.new_data(129, "island", randi() % 10000)
			var water := PSData.new_object("water")
			water["pos"] = [0.0, 0.0, 0.0]
			water["size"] = [400.0, 4.0, 400.0]
			_add(objects, water)
			_spawn(objects, Vector3(0, 6, 0))
			data["env"]["sky"] = "day"
			_place_spawn_on_terrain(data, objects)
		"obby":
			data["env"]["sky"] = "sunset"
			data["game"]["start_message"] = "Chegue até a bandeira dourada!"
			_box(objects, "Início", Vector3(0, -0.5, 0), Vector3(12, 1, 12), Color(0.4, 0.45, 0.5), {"locked": true})
			_spawn(objects, Vector3(0, 0, 3))
			var coin_script := "s_moeda"
			var colors := [Color(0.95, 0.4, 0.35), Color(0.95, 0.65, 0.25), Color(0.95, 0.85, 0.3), Color(0.45, 0.8, 0.4), Color(0.3, 0.7, 0.95), Color(0.6, 0.45, 0.95)]
			var pos := Vector3(0, 0.5, -9)
			for i in 6:
				var plat := _box(objects, "Plataforma %d" % (i + 1), pos, Vector3(3, 0.5, 3), colors[i])
				if i == 3:
					# Plataforma que vai e volta (movida por script, carrega o jogador).
					plat["phys"]["mode"] = "kinematic"
					plat["script"] = "s_plataforma"
					plat["name"] = "Plataforma móvel"
				var coin: Dictionary = PSPrefabs.instantiate("coin", pos + Vector3(0, 0.2, 0))[0]
				coin["script"] = coin_script
				_add(objects, coin)
				pos += Vector3([-3.0, 3.0, 0.0][i % 3], 1.0, -4.5)
			var fin: Array = PSPrefabs.instantiate("finish", pos + Vector3(0, -0.25, -1.5))
			for d in fin:
				if d.get("name", "") == "Base de chegada":
					d["script"] = "s_chegada"
				_add(objects, d)
			# Cair do percurso leva de volta ao início.
			_box(objects, "Zona de queda", Vector3(0, -12, -18), Vector3(40, 1, 56), Color(0.5, 0.15, 0.15, 0.12), {"script": "s_armadilha", "visible": false, "locked": true})
			objects[-1]["phys"]["mode"] = "none"
			data["scripts"] = [
				{"id": coin_script, "name": "Moeda", "code": PSScriptTemplates.get_code("coin"), "enabled": true, "global": false},
				{"id": "s_plataforma", "name": "Plataforma móvel", "code": PSScriptTemplates.get_code("platform").replace("local distancia = 6", "local distancia = 4").replace("vec(desloc, 0, 0)", "vec(0, 0, desloc)"), "enabled": true, "global": false},
				{"id": "s_chegada", "name": "Chegada", "code": PSScriptTemplates.get_code("finish"), "enabled": true, "global": false},
				{"id": "s_armadilha", "name": "Zona de queda", "code": PSScriptTemplates.get_code("trap"), "enabled": true, "global": false},
				{"id": "s_cronometro", "name": "Cronômetro", "code": PSScriptTemplates.get_code("timer").replace("ui.text(string.format(\"Tempo: %.1f s\", time()))", "ui.text(string.format(\"Tempo: %.0f s · Moedas: %d\", time(), shared.moedas or 0))"), "enabled": true, "global": true},
			]
		"blank":
			pass
	data["objects"] = objects
	return data


static func _place_spawn_on_terrain(data: Dictionary, objects: Array) -> void:
	var t := PSTerrain.new()
	t.load_data(data["terrain"], false)
	var best := Vector3(0, 6, 0)
	# Procura um ponto seco perto do centro.
	for r in range(0, 40, 2):
		var h := t.height_at_local(r, r * 0.5)
		if h > 1.0:
			best = Vector3(r, h + 0.5, r * 0.5)
			break
	for o in objects:
		if o["type"] == "spawn":
			o["pos"] = PSData.v3_to_arr(best)
	# Algumas árvores em terreno seco.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var trees: Array = []
	var pines: Array = []
	for i in 160:
		var x := rng.randf_range(-55, 55)
		var z := rng.randf_range(-55, 55)
		var h := t.height_at_local(x, z)
		if h > 1.2 and h < 14.0:
			var entry := [snappedf(x, 0.01), snappedf(h, 0.01), snappedf(z, 0.01), snappedf(rng.randf() * TAU, 0.01), snappedf(rng.randf_range(0.8, 1.3), 0.01)]
			if i % 3 == 0:
				pines.append(entry)
			else:
				trees.append(entry)
	data["terrain"]["veg"] = [{"kind": "tree", "p": trees}, {"kind": "pine", "p": pines}]
	t.free()
