class_name PSTerrain
extends Node3D
## Terreno por mapa de altura com pintura por vértice e vegetação simples.
##
## - Espaçamento fixo de 1 m entre vértices; `size` vértices por lado (33, 65, 129...).
## - A malha é dividida em blocos de 16 x 16 quadrados: um pincel só reconstrói
##   os blocos que tocou, o que mantém a edição fluida em celulares modestos.
## - A colisão usa HeightMapShape3D (física nativa, sem custo de malha).
## - A vegetação usa MultiMesh (uma chamada de desenho por tipo).

signal changed

const CHUNK := 16
const SURFACES := {
	"grass": {"label": "Grama", "color": Color(0.32, 0.54, 0.22)},
	"dry": {"label": "Grama seca", "color": Color(0.62, 0.6, 0.32)},
	"dirt": {"label": "Terra", "color": Color(0.45, 0.33, 0.22)},
	"sand": {"label": "Areia", "color": Color(0.86, 0.79, 0.56)},
	"rock": {"label": "Pedra", "color": Color(0.5, 0.5, 0.52)},
	"snow": {"label": "Neve", "color": Color(0.95, 0.96, 0.98)},
}
const VEG_KINDS := {
	"tree": {"label": "Árvore", "collide": true, "radius": 0.25},
	"pine": {"label": "Pinheiro", "collide": true, "radius": 0.2},
	"bush": {"label": "Arbusto", "collide": false, "radius": 0.0},
	"rock": {"label": "Rocha", "collide": true, "radius": 0.5},
	"grass": {"label": "Capim", "collide": false, "radius": 0.0},
}
const MAX_VEG_PER_KIND := 5000

var size := 65
var heights := PackedFloat32Array()
var colors := PackedByteArray()
var veg := {}                  # kind -> Array de [x, y, z, rot, escala]
var play_mode := false

var _chunks := {}              # Vector2i -> MeshInstance3D
var _material: StandardMaterial3D
var _body: StaticBody3D
var _shape: HeightMapShape3D
var _veg_nodes := {}           # kind -> MultiMeshInstance3D
var _veg_meshes := {}
var _veg_body: StaticBody3D
var _collision_dirty := false
var _collision_timer := 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if _collision_dirty:
		_collision_timer -= delta
		if _collision_timer <= 0.0:
			refresh_collision()


# --------------------------------------------------------------------------
# Dados
# --------------------------------------------------------------------------

static func new_data(p_size := 65, generator := "flat", seed_value := 0) -> Dictionary:
	var t := PSTerrain.new()
	t.create(p_size)
	match generator:
		"hills":
			t.generate_noise(6.0, 0.03, seed_value, false)
			t.auto_paint()
		"mountains":
			t.generate_noise(22.0, 0.02, seed_value, false)
			t.auto_paint()
		"island":
			t.generate_noise(10.0, 0.035, seed_value, true)
			t.auto_paint()
	var d := t.to_data()
	t.free()
	return d


func create(p_size: int) -> void:
	size = clampi(p_size, 9, 257)
	heights = PackedFloat32Array()
	heights.resize(size * size)
	heights.fill(0.0)
	colors = PackedByteArray()
	colors.resize(size * size * 4)
	var c: Color = SURFACES["grass"]["color"]
	for i in size * size:
		colors.encode_u32(i * 4, _pack(c))
	veg = {}


func load_data(d: Dictionary, build := true) -> void:
	size = clampi(int(d.get("size", 65)), 9, 257)
	var n := size * size
	heights = Marshalls.base64_to_raw(String(d.get("heights", ""))).to_float32_array()
	if heights.size() != n:
		heights = PackedFloat32Array()
		heights.resize(n)
		heights.fill(0.0)
	for i in n:
		if not is_finite(heights[i]):
			heights[i] = 0.0
		heights[i] = clampf(heights[i], -500.0, 500.0)
	colors = Marshalls.base64_to_raw(String(d.get("colors", "")))
	if colors.size() != n * 4:
		create_colors_only()
	position = PSData.arr_to_v3(d.get("pos"))
	veg = {}
	for group in d.get("veg", []):
		var kind := String(group.get("kind", ""))
		if VEG_KINDS.has(kind):
			veg[kind] = (group.get("p", []) as Array).duplicate(true)
	if build:
		rebuild_all()


func create_colors_only() -> void:
	colors = PackedByteArray()
	colors.resize(size * size * 4)
	var c: Color = SURFACES["grass"]["color"]
	for i in size * size:
		colors.encode_u32(i * 4, _pack(c))


func to_data() -> Dictionary:
	var veg_out: Array = []
	for kind in veg:
		if not (veg[kind] as Array).is_empty():
			veg_out.append({"kind": kind, "p": (veg[kind] as Array).duplicate(true)})
	return {
		"size": size,
		"heights": Marshalls.raw_to_base64(heights.to_byte_array()),
		"colors": Marshalls.raw_to_base64(colors),
		"pos": PSData.v3_to_arr(position),
		"veg": veg_out,
	}


## Estado completo para desfazer/refazer.
func snapshot() -> Dictionary:
	var v := {}
	for k in veg:
		v[k] = (veg[k] as Array).duplicate(true)
	return {"heights": heights.duplicate(), "colors": colors.duplicate(), "veg": v}


func restore(snap: Dictionary) -> void:
	heights = (snap["heights"] as PackedFloat32Array).duplicate()
	colors = (snap["colors"] as PackedByteArray).duplicate()
	veg = {}
	for k in snap["veg"]:
		veg[k] = (snap["veg"][k] as Array).duplicate(true)
	rebuild_all()


static func _pack(c: Color) -> int:
	return int(c.r * 255.0) | (int(c.g * 255.0) << 8) | (int(c.b * 255.0) << 16) | (255 << 24)


func _color_at(i: int) -> Color:
	var v := colors.decode_u32(i * 4)
	return Color8(v & 255, (v >> 8) & 255, (v >> 16) & 255)


func half() -> float:
	return (size - 1) * 0.5


func extent() -> float:
	return float(size - 1)


func get_h(x: int, z: int) -> float:
	x = clampi(x, 0, size - 1)
	z = clampi(z, 0, size - 1)
	return heights[z * size + x]


## Altura interpolada em coordenadas locais do terreno.
func height_at_local(lx: float, lz: float) -> float:
	var fx := lx + half()
	var fz := lz + half()
	if fx < 0.0 or fz < 0.0 or fx > extent() or fz > extent():
		return -INF
	var x0 := int(floor(fx))
	var z0 := int(floor(fz))
	var tx := fx - x0
	var tz := fz - z0
	var h00 := get_h(x0, z0)
	var h10 := get_h(x0 + 1, z0)
	var h01 := get_h(x0, z0 + 1)
	var h11 := get_h(x0 + 1, z0 + 1)
	# Mesma diagonal da malha (triângulos 00-10-11 e 00-11-01).
	if tx >= tz:
		return h00 + (h10 - h00) * tx + (h11 - h10) * tz
	return h00 + (h11 - h01) * tx + (h01 - h00) * tz


func height_at_global(p: Vector3) -> float:
	var l := to_local(p) if is_inside_tree() else p - position
	var h := height_at_local(l.x, l.z)
	return h + global_position.y if is_inside_tree() and h != -INF else h


func contains_global(p: Vector3) -> bool:
	var l := to_local(p) if is_inside_tree() else p - position
	return absf(l.x) <= half() and absf(l.z) <= half()


## Raio contra o terreno por marcha + refinamento. Retorna {} se não acertar.
func raycast(from: Vector3, dir: Vector3, max_dist := 2000.0) -> Dictionary:
	var lf := to_local(from) if is_inside_tree() else from - position
	var ld := dir.normalized()
	var box := AABB(Vector3(-half(), -600.0, -half()), Vector3(extent(), 1200.0, extent()))
	var t := 0.0
	if not box.has_point(lf):
		var entry = box.intersects_ray(lf, ld)
		if entry == null:
			return {}
		t = lf.distance_to(entry) + 0.001
	var step := 0.4
	var p := lf + ld * t
	var prev_t := t
	var prev_above := p.y >= _h_clamped(p.x, p.z)
	while t <= max_dist:
		t += step
		p = lf + ld * t
		if absf(p.x) > half() or absf(p.z) > half():
			return {}
		var above := p.y >= height_at_local(p.x, p.z)
		if prev_above and not above:
			var lo := prev_t
			var hi := t
			for _i in 12:
				var mid := (lo + hi) * 0.5
				var pm := lf + ld * mid
				if pm.y >= _h_clamped(pm.x, pm.z):
					lo = mid
				else:
					hi = mid
			var lp := lf + ld * hi
			lp.y = _h_clamped(lp.x, lp.z)
			return {"position": to_global(lp) if is_inside_tree() else lp + position, "local": lp}
		prev_above = above
		prev_t = t
	return {}


func _h_clamped(lx: float, lz: float) -> float:
	return height_at_local(clampf(lx, -half(), half()), clampf(lz, -half(), half()))


# --------------------------------------------------------------------------
# Geração
# --------------------------------------------------------------------------

func generate_noise(amplitude: float, frequency: float, seed_value: int, island: bool) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	for z in size:
		for x in size:
			var n := noise.get_noise_2d(x, z) * 0.5 + 0.5
			var h := n * n * amplitude * 1.6
			if island:
				var dx := (x - half()) / half()
				var dz := (z - half()) / half()
				var fall := clampf(1.0 - sqrt(dx * dx + dz * dz), 0.0, 1.0)
				h = h * fall * 1.3 + fall * 4.0 - 2.5
			heights[z * size + x] = h


## Pinta por altura e inclinação: areia perto da água, pedra em encostas, neve no alto.
func auto_paint(water_level := 0.0) -> void:
	var max_h := -INF
	for h in heights:
		max_h = maxf(max_h, h)
	for z in size:
		for x in size:
			var h := get_h(x, z)
			var slope := Vector2(get_h(x + 1, z) - get_h(x - 1, z), get_h(x, z + 1) - get_h(x, z - 1)).length() * 0.5
			var key := "grass"
			if h < water_level + 0.6:
				key = "sand"
			elif slope > 0.9:
				key = "rock"
			elif max_h > 10.0 and h > max_h * 0.75:
				key = "snow"
			elif slope > 0.55:
				key = "dirt"
			colors.encode_u32((z * size + x) * 4, _pack(SURFACES[key]["color"]))


# --------------------------------------------------------------------------
# Pincéis
# --------------------------------------------------------------------------

## Aplica um pincel no ponto local (x, z). Retorna o retângulo afetado.
## tool: raise, lower, smooth, flatten, paint
func apply_brush(tool: String, center_local: Vector3, radius: float, strength: float, extra := {}) -> Rect2i:
	var cx := center_local.x + half()
	var cz := center_local.z + half()
	var r := maxf(radius, 0.5)
	var x0 := clampi(int(floor(cx - r)), 0, size - 1)
	var x1 := clampi(int(ceil(cx + r)), 0, size - 1)
	var z0 := clampi(int(floor(cz - r)), 0, size - 1)
	var z1 := clampi(int(ceil(cz + r)), 0, size - 1)
	if x1 < x0 or z1 < z0:
		return Rect2i()
	var target := float(extra.get("target", 0.0))
	var paint := Color(extra.get("color", SURFACES["grass"]["color"]))
	var src := heights.duplicate() if tool == "smooth" else heights
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(x - cx, z - cz).length()
			if d > r:
				continue
			var fall := 1.0 - d / r
			fall = fall * fall * (3.0 - 2.0 * fall)
			var w := clampf(strength * fall, 0.0, 1.0)
			var i := z * size + x
			match tool:
				"raise":
					heights[i] = clampf(heights[i] + strength * fall * 0.6, -500.0, 500.0)
				"lower":
					heights[i] = clampf(heights[i] - strength * fall * 0.6, -500.0, 500.0)
				"smooth":
					var avg := 0.0
					var cnt := 0
					for oz in range(-1, 2):
						for ox in range(-1, 2):
							var nx := clampi(x + ox, 0, size - 1)
							var nz := clampi(z + oz, 0, size - 1)
							avg += src[nz * size + nx]
							cnt += 1
					heights[i] = lerpf(heights[i], avg / cnt, w)
				"flatten":
					heights[i] = lerpf(heights[i], target, w)
				"paint":
					var c := _color_at(i).lerp(paint, w)
					colors.encode_u32(i * 4, _pack(c))
	var rect := Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1)
	if tool != "paint":
		_update_veg_heights_in(rect)
	rebuild_rect(rect)
	if tool != "paint":
		mark_collision_dirty()
	return rect


## Planta ou remove vegetação num raio. Retorna quantas instâncias mudaram.
func apply_vegetation(kind: String, center_local: Vector3, radius: float, density: float, remove := false, rng_seed := 0) -> int:
	if not VEG_KINDS.has(kind):
		return 0
	var list: Array = veg.get(kind, [])
	var changed_count := 0
	if remove:
		var kept: Array = []
		for p in list:
			if Vector2(p[0] - center_local.x, p[2] - center_local.z).length() > radius:
				kept.append(p)
			else:
				changed_count += 1
		veg[kind] = kept
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = rng_seed if rng_seed != 0 else randi()
		var area := PI * radius * radius
		var n := clampi(int(area * density * 0.05) + 1, 1, 40)
		for _i in n:
			if list.size() >= MAX_VEG_PER_KIND:
				break
			var a := rng.randf() * TAU
			var rr := sqrt(rng.randf()) * radius
			var x := center_local.x + cos(a) * rr
			var z := center_local.z + sin(a) * rr
			var h := height_at_local(x, z)
			if h == -INF:
				continue
			# Evita amontoar: distância mínima entre instâncias do mesmo tipo.
			var min_d := 0.6 if kind == "grass" else 1.4
			var too_close := false
			for p in list:
				if absf(p[0] - x) < min_d and absf(p[2] - z) < min_d:
					too_close = true
					break
			if too_close:
				continue
			list.append([snappedf(x, 0.01), snappedf(h, 0.01), snappedf(z, 0.01), snappedf(rng.randf() * TAU, 0.01), snappedf(rng.randf_range(0.75, 1.3), 0.01)])
			changed_count += 1
		veg[kind] = list
	if changed_count > 0:
		_rebuild_veg_kind(kind)
		if play_mode:
			_rebuild_veg_collision()
	return changed_count


func _update_veg_heights_in(rect: Rect2i) -> void:
	var touched := {}
	for kind in veg:
		for p in veg[kind]:
			var gx := int(p[0] + half())
			var gz := int(p[2] + half())
			if gx >= rect.position.x - 1 and gx <= rect.end.x and gz >= rect.position.y - 1 and gz <= rect.end.y:
				var h := height_at_local(p[0], p[2])
				if h != -INF:
					p[1] = snappedf(h, 0.01)
					touched[kind] = true
	for kind in touched:
		_rebuild_veg_kind(kind)


func count_vegetation() -> int:
	var n := 0
	for k in veg:
		n += (veg[k] as Array).size()
	return n


# --------------------------------------------------------------------------
# Malha
# --------------------------------------------------------------------------

func _get_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.95
		var noise := FastNoiseLite.new()
		noise.frequency = 0.08
		var tex := NoiseTexture2D.new()
		tex.width = 128
		tex.height = 128
		tex.seamless = true
		tex.noise = noise
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.78, 0.78, 0.78))
		ramp.set_color(1, Color(1.0, 1.0, 1.0))
		tex.color_ramp = ramp
		_material.albedo_texture = tex
		_material.uv1_scale = Vector3(0.25, 0.25, 0.25)
	return _material


func rebuild_all() -> void:
	for c in _chunks.values():
		remove_child(c)
		c.free()
	_chunks.clear()
	rebuild_rect(Rect2i(0, 0, size, size))
	refresh_collision()
	for kind in VEG_KINDS:
		_rebuild_veg_kind(kind)
	if play_mode:
		_rebuild_veg_collision()


func rebuild_rect(rect: Rect2i) -> void:
	var quads := size - 1
	var chunks_n := int(ceil(float(quads) / CHUNK))
	# Um vértice alterado muda a normal dos vizinhos: expande 1 vértice.
	var cx0 := clampi((rect.position.x - 1) / CHUNK, 0, chunks_n - 1)
	var cz0 := clampi((rect.position.y - 1) / CHUNK, 0, chunks_n - 1)
	var cx1 := clampi((rect.end.x + 1) / CHUNK, 0, chunks_n - 1)
	var cz1 := clampi((rect.end.y + 1) / CHUNK, 0, chunks_n - 1)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			_build_chunk(cx, cz)
	changed.emit()


func _normal_at(x: int, z: int) -> Vector3:
	var hl := get_h(x - 1, z)
	var hr := get_h(x + 1, z)
	var hd := get_h(x, z - 1)
	var hu := get_h(x, z + 1)
	return Vector3(hl - hr, 2.0, hd - hu).normalized()


func _build_chunk(cx: int, cz: int) -> void:
	var x0 := cx * CHUNK
	var z0 := cz * CHUNK
	var x1 := mini(x0 + CHUNK, size - 1)
	var z1 := mini(z0 + CHUNK, size - 1)
	var w := x1 - x0 + 1
	var dpt := z1 - z0 + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(w * dpt)
	normals.resize(w * dpt)
	cols.resize(w * dpt)
	uvs.resize(w * dpt)
	var hf := half()
	var k := 0
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			verts[k] = Vector3(x - hf, heights[z * size + x], z - hf)
			normals[k] = _normal_at(x, z)
			cols[k] = _color_at(z * size + x)
			uvs[k] = Vector2(x, z)
			k += 1
	var idx := PackedInt32Array()
	idx.resize((w - 1) * (dpt - 1) * 6)
	k = 0
	for z in dpt - 1:
		for x in w - 1:
			var a := z * w + x
			var b := a + 1
			var c := a + w
			var d := c + 1
			# Godot usa ordem horária para a face da frente: a-b-d é horário visto de cima.
			idx[k] = a
			idx[k + 1] = b
			idx[k + 2] = d
			idx[k + 3] = a
			idx[k + 4] = d
			idx[k + 5] = c
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _get_material())
	var key := Vector2i(cx, cz)
	var mi: MeshInstance3D = _chunks.get(key)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Chunk_%d_%d" % [cx, cz]
		add_child(mi)
		_chunks[key] = mi
	mi.mesh = mesh


# --------------------------------------------------------------------------
# Colisão
# --------------------------------------------------------------------------

func mark_collision_dirty() -> void:
	_collision_dirty = true
	_collision_timer = 0.25


func refresh_collision() -> void:
	_collision_dirty = false
	if _body == null:
		_body = StaticBody3D.new()
		_body.name = "Body"
		_body.set_meta("ps_terrain", true)
		var cs := CollisionShape3D.new()
		_shape = HeightMapShape3D.new()
		cs.shape = _shape
		_body.add_child(cs)
		add_child(_body)
	_body.collision_layer = PSWorld.LAYER_WORLD if play_mode else PSWorld.LAYER_TERRAIN
	_body.collision_mask = 0 if not play_mode else PSWorld.LAYER_WORLD | PSWorld.LAYER_PLAYER
	_shape.map_width = size
	_shape.map_depth = size
	_shape.map_data = heights


# --------------------------------------------------------------------------
# Vegetação
# --------------------------------------------------------------------------

func _veg_mesh(kind: String) -> Mesh:
	if _veg_meshes.has(kind):
		return _veg_meshes[kind]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"tree":
			_add_prim(st, PSPrimitives.get_mesh("cylinder"), Transform3D(Basis.from_scale(Vector3(0.3, 1.4, 0.3)), Vector3(0, 0.7, 0)), Color(0.42, 0.28, 0.16))
			_add_prim(st, PSPrimitives.get_mesh("sphere"), Transform3D(Basis.from_scale(Vector3(1.8, 1.6, 1.8)), Vector3(0, 2.1, 0)), Color(0.24, 0.52, 0.2))
		"pine":
			_add_prim(st, PSPrimitives.get_mesh("cylinder"), Transform3D(Basis.from_scale(Vector3(0.25, 1.0, 0.25)), Vector3(0, 0.5, 0)), Color(0.38, 0.25, 0.15))
			_add_prim(st, PSPrimitives.get_mesh("cone"), Transform3D(Basis.from_scale(Vector3(1.6, 1.6, 1.6)), Vector3(0, 1.6, 0)), Color(0.13, 0.38, 0.2))
			_add_prim(st, PSPrimitives.get_mesh("cone"), Transform3D(Basis.from_scale(Vector3(1.15, 1.3, 1.15)), Vector3(0, 2.5, 0)), Color(0.15, 0.42, 0.22))
		"bush":
			_add_prim(st, PSPrimitives.get_mesh("sphere"), Transform3D(Basis.from_scale(Vector3(1.0, 0.7, 1.0)), Vector3(0, 0.3, 0)), Color(0.28, 0.5, 0.22))
			_add_prim(st, PSPrimitives.get_mesh("sphere"), Transform3D(Basis.from_scale(Vector3(0.6, 0.5, 0.6)), Vector3(0.35, 0.35, 0.2)), Color(0.32, 0.56, 0.24))
		"rock":
			_add_prim(st, PSPrimitives.get_mesh("sphere"), Transform3D(Basis(Vector3(0.3, 1, 0.1).normalized(), 0.4) * Basis.from_scale(Vector3(1.2, 0.7, 0.9)), Vector3(0, 0.15, 0)), Color(0.5, 0.5, 0.5))
		"grass":
			for i in 3:
				var b := Basis(Vector3.UP, i * TAU / 3.0) * Basis(Vector3.RIGHT, 0.25) * Basis.from_scale(Vector3(0.12, 0.5, 0.12))
				_add_prim(st, PSPrimitives.get_mesh("cone"), Transform3D(b, Vector3(0, 0.22, 0)), Color(0.36, 0.6, 0.24))
	st.generate_normals()
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	mesh.surface_set_material(0, m)
	_veg_meshes[kind] = mesh
	return mesh


func _add_prim(st: SurfaceTool, mesh: Mesh, xf: Transform3D, color: Color) -> void:
	var faces := mesh.get_faces()
	st.set_color(color)
	for i in range(0, faces.size(), 3):
		st.add_vertex(xf * faces[i])
		st.add_vertex(xf * faces[i + 1])
		st.add_vertex(xf * faces[i + 2])


func _rebuild_veg_kind(kind: String) -> void:
	var list: Array = veg.get(kind, [])
	var mmi: MultiMeshInstance3D = _veg_nodes.get(kind)
	if list.is_empty():
		if mmi:
			remove_child(mmi)
			mmi.free()
			_veg_nodes.erase(kind)
		return
	if mmi == null:
		mmi = MultiMeshInstance3D.new()
		mmi.name = "Veg_" + kind
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind in ["tree", "pine", "rock"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_veg_nodes[kind] = mmi
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _veg_mesh(kind)
	mm.instance_count = list.size()
	for i in list.size():
		var p: Array = list[i]
		var s := float(p[4])
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(p[3])).scaled(Vector3(s, s, s)), Vector3(p[0], p[1], p[2])))
	mmi.multimesh = mm


func _rebuild_veg_collision() -> void:
	if _veg_body:
		remove_child(_veg_body)
		_veg_body.free()
		_veg_body = null
	_veg_body = StaticBody3D.new()
	_veg_body.name = "VegBody"
	_veg_body.collision_layer = PSWorld.LAYER_WORLD
	_veg_body.collision_mask = 0
	var shapes := 0
	for kind in veg:
		if not VEG_KINDS[kind]["collide"]:
			continue
		for p in veg[kind]:
			if shapes > 2000:
				break
			var s := float(p[4])
			var cs := CollisionShape3D.new()
			if kind == "rock":
				var sp := SphereShape3D.new()
				sp.radius = 0.5 * s
				cs.shape = sp
				cs.position = Vector3(p[0], p[1] + 0.1 * s, p[2])
			else:
				var cyl := CylinderShape3D.new()
				cyl.radius = VEG_KINDS[kind]["radius"] * s
				cyl.height = 2.0 * s
				cs.shape = cyl
				cs.position = Vector3(p[0], p[1] + s, p[2])
			_veg_body.add_child(cs)
			shapes += 1
	add_child(_veg_body)
