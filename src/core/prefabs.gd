class_name PSPrefabs
extends RefCounted
## Biblioteca interna de modelos montados com primitivas.
## Todos foram criados para o Pocket Studio 3D e são de domínio público (CC0).

const LICENSE := "CC0 (domínio público)"
const ORIGIN := "Biblioteca interna do Pocket Studio 3D"

const CATALOG := [
	{"key": "tree", "name": "Árvore", "tags": "natureza planta"},
	{"key": "pine", "name": "Pinheiro", "tags": "natureza planta"},
	{"key": "rock", "name": "Pedra", "tags": "natureza"},
	{"key": "house", "name": "Casa simples", "tags": "construção"},
	{"key": "stairs", "name": "Escada", "tags": "construção"},
	{"key": "bridge", "name": "Ponte", "tags": "construção"},
	{"key": "fence", "name": "Cerca", "tags": "construção"},
	{"key": "table", "name": "Mesa", "tags": "móveis"},
	{"key": "platform", "name": "Plataforma", "tags": "jogo obby"},
	{"key": "coin", "name": "Moeda", "tags": "jogo coletável"},
	{"key": "lamp", "name": "Poste de luz", "tags": "luz cidade"},
	{"key": "finish", "name": "Bandeira de chegada", "tags": "jogo"},
]


static func _part(shape: String, pos: Vector3, size: Vector3, color: Color, extra := {}) -> Dictionary:
	var d := PSData.new_object("part", {"shape": shape})
	d["pos"] = PSData.v3_to_arr(pos)
	d["size"] = PSData.v3_to_arr(size)
	d["mat"] = PSData.default_material(color)
	for k in extra:
		d[k] = extra[k]
	return d


static func _rot(d: Dictionary, euler_deg: Vector3) -> Dictionary:
	d["rot"] = PSData.quat_to_arr(Quaternion.from_euler(euler_deg * (PI / 180.0)))
	return d


static func _named(d: Dictionary, n: String) -> Dictionary:
	d["name"] = n
	return d


## Peças do prefab (posições relativas ao grupo). Sem ids.
static func parts(key: String) -> Array:
	var wood := Color(0.55, 0.38, 0.22)
	var dark_wood := Color(0.4, 0.27, 0.16)
	var leaf := Color(0.25, 0.55, 0.22)
	var stone := Color(0.55, 0.55, 0.57)
	var wall := Color(0.9, 0.86, 0.78)
	var roof := Color(0.7, 0.25, 0.2)
	match key:
		"tree":
			return [
				_named(_part("cylinder", Vector3(0, 1.0, 0), Vector3(0.45, 2.0, 0.45), wood), "Tronco"),
				_named(_part("sphere", Vector3(0, 2.9, 0), Vector3(2.4, 2.2, 2.4), leaf), "Copa"),
			]
		"pine":
			return [
				_named(_part("cylinder", Vector3(0, 0.75, 0), Vector3(0.35, 1.5, 0.35), dark_wood), "Tronco"),
				_named(_part("cone", Vector3(0, 2.2, 0), Vector3(2.2, 2.2, 2.2), Color(0.13, 0.4, 0.22)), "Galhos 1"),
				_named(_part("cone", Vector3(0, 3.3, 0), Vector3(1.6, 1.8, 1.6), Color(0.15, 0.45, 0.24)), "Galhos 2"),
			]
		"rock":
			return [_rot(_named(_part("sphere", Vector3(0, 0.35, 0), Vector3(1.6, 1.0, 1.3), stone), "Pedra"), Vector3(8, 25, 5))]
		"house":
			var p: Array = []
			p.append(_named(_part("box", Vector3(0, 0.1, 0), Vector3(6, 0.2, 5), Color(0.5, 0.45, 0.4)), "Piso"))
			p.append(_named(_part("box", Vector3(0, 1.6, -2.4), Vector3(6, 3, 0.2), wall), "Parede fundo"))
			p.append(_named(_part("box", Vector3(-2.9, 1.6, 0), Vector3(0.2, 3, 5), wall), "Parede esquerda"))
			p.append(_named(_part("box", Vector3(2.9, 1.6, 0), Vector3(0.2, 3, 5), wall), "Parede direita"))
			p.append(_named(_part("box", Vector3(-2.0, 1.6, 2.4), Vector3(2.0, 3, 0.2), wall), "Frente esquerda"))
			p.append(_named(_part("box", Vector3(2.0, 1.6, 2.4), Vector3(2.0, 3, 0.2), wall), "Frente direita"))
			p.append(_named(_part("box", Vector3(0, 2.75, 2.4), Vector3(2.0, 0.7, 0.2), wall), "Sobre a porta"))
			# A rampa tem a face vertical à esquerda; a peça esquerda é girada para a cumeeira ficar no centro.
			p.append(_rot(_named(_part("wedge", Vector3(-1.6, 3.8, 0), Vector3(3.2, 1.4, 5.6), roof), "Telhado esquerdo"), Vector3(0, 180, 0)))
			p.append(_named(_part("wedge", Vector3(1.6, 3.8, 0), Vector3(3.2, 1.4, 5.6), roof), "Telhado direito"))
			return p
		"stairs":
			var s: Array = []
			for i in 6:
				s.append(_named(_part("box", Vector3(0, 0.25 + i * 0.5, -i * 0.6), Vector3(2, 0.5, 0.6), stone), "Degrau %d" % (i + 1)))
			return s
		"bridge":
			var b: Array = []
			for i in 9:
				b.append(_named(_part("box", Vector3(0, 0.1, -4 + i), Vector3(3, 0.2, 0.8), wood), "Tábua %d" % (i + 1)))
			b.append(_named(_part("box", Vector3(-1.45, 0.7, 0), Vector3(0.1, 0.1, 9), dark_wood), "Corrimão esquerdo"))
			b.append(_named(_part("box", Vector3(1.45, 0.7, 0), Vector3(0.1, 0.1, 9), dark_wood), "Corrimão direito"))
			for z in [-4, 0, 4]:
				b.append(_named(_part("box", Vector3(-1.45, 0.4, z), Vector3(0.15, 0.7, 0.15), dark_wood), "Poste"))
				b.append(_named(_part("box", Vector3(1.45, 0.4, z), Vector3(0.15, 0.7, 0.15), dark_wood), "Poste"))
			return b
		"fence":
			var f: Array = []
			for i in 4:
				f.append(_named(_part("box", Vector3(-3 + i * 2, 0.5, 0), Vector3(0.18, 1.0, 0.18), wood), "Poste %d" % (i + 1)))
			f.append(_named(_part("box", Vector3(0, 0.75, 0), Vector3(6.2, 0.12, 0.08), wood), "Travessa alta"))
			f.append(_named(_part("box", Vector3(0, 0.4, 0), Vector3(6.2, 0.12, 0.08), wood), "Travessa baixa"))
			return f
		"table":
			var t: Array = [_named(_part("box", Vector3(0, 0.8, 0), Vector3(1.6, 0.1, 0.9), wood), "Tampo")]
			for x in [-0.7, 0.7]:
				for z in [-0.35, 0.35]:
					t.append(_named(_part("box", Vector3(x, 0.38, z), Vector3(0.1, 0.75, 0.1), dark_wood), "Perna"))
			return t
		"platform":
			return [_named(_part("box", Vector3(0, 0.25, 0), Vector3(4, 0.5, 4), Color(0.35, 0.6, 0.95)), "Plataforma")]
		"coin":
			var c := _part("cylinder", Vector3(0, 1.0, 0), Vector3(0.8, 0.12, 0.8), Color(1.0, 0.8, 0.2))
			c["mat"]["metal"] = 0.8
			c["mat"]["rough"] = 0.3
			c["mat"]["emit"] = 0.4
			c["phys"]["mode"] = "none"
			return [_rot(_named(c, "Moeda"), Vector3(90, 0, 0))]
		"lamp":
			var light := PSData.new_object("light")
			light["pos"] = [0.0, 3.6, 0.0]
			light["name"] = "Luz"
			return [
				_named(_part("cylinder", Vector3(0, 1.8, 0), Vector3(0.15, 3.6, 0.15), Color(0.2, 0.2, 0.22)), "Poste"),
				_named(_part("sphere", Vector3(0, 3.7, 0), Vector3(0.5, 0.5, 0.5), Color(1, 0.95, 0.75), {"mat": PSData.default_material(Color(1, 0.95, 0.75)).merged({"emit": 2.0}, true)}), "Lâmpada"),
				light,
			]
		"finish":
			return [
				_named(_part("cylinder", Vector3(0, 1.5, 0), Vector3(0.12, 3.0, 0.12), Color(0.85, 0.85, 0.88)), "Mastro"),
				_named(_part("box", Vector3(0.6, 2.6, 0), Vector3(1.1, 0.7, 0.05), Color(0.95, 0.95, 0.95)), "Bandeira"),
				_named(_part("box", Vector3(0, 0.1, 0), Vector3(3, 0.2, 3), Color(0.95, 0.85, 0.2)), "Base de chegada"),
			]
	return []


static func display_name(key: String) -> String:
	for e in CATALOG:
		if e["key"] == key:
			return e["name"]
	return key


## Cria a lista de objetos (grupo + peças) com ids novos, pronta para o mundo.
static func instantiate(key: String, position := Vector3.ZERO, parent_id := "") -> Array:
	var ps := parts(key)
	if ps.is_empty():
		return []
	if ps.size() == 1:
		var single: Dictionary = ps[0].duplicate(true)
		single["id"] = App.new_id("o")
		single["parent"] = parent_id
		single["pos"] = PSData.v3_to_arr(PSData.arr_to_v3(single["pos"]) + position)
		single["name"] = display_name(key)
		return [single]
	var group := PSData.new_object("group")
	group["id"] = App.new_id("o")
	group["name"] = display_name(key)
	group["parent"] = parent_id
	group["pos"] = PSData.v3_to_arr(position)
	var out: Array = [group]
	for p in ps:
		var d: Dictionary = p.duplicate(true)
		d["id"] = App.new_id("o")
		d["parent"] = group["id"]
		out.append(d)
	return out
