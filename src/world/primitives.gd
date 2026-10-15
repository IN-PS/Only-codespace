class_name PSPrimitives
extends RefCounted
## Malhas, formas de colisão e materiais das primitivas.
##
## Todas as malhas têm caixa envolvente unitária (1 x 1 x 1) centrada na origem,
## de modo que o campo "size" de uma peça é exatamente o tamanho dela em metros.
## As malhas e materiais idênticos são compartilhados (cache) para economizar memória.

static var _mesh_cache := {}
static var _points_cache := {}
static var _faces_cache := {}
static var _material_cache := {}
static var _water_shader: Shader
static var _marker_materials := {}


static func get_mesh(shape: String) -> Mesh:
	if _mesh_cache.has(shape):
		return _mesh_cache[shape]
	var mesh: Mesh
	match shape:
		"box":
			var m := BoxMesh.new()
			m.size = Vector3.ONE
			mesh = m
		"sphere":
			var m := SphereMesh.new()
			m.radius = 0.5
			m.height = 1.0
			m.radial_segments = 24
			m.rings = 12
			mesh = m
		"cylinder":
			var m := CylinderMesh.new()
			m.top_radius = 0.5
			m.bottom_radius = 0.5
			m.height = 1.0
			m.radial_segments = 24
			m.rings = 1
			mesh = m
		"cone":
			var m := CylinderMesh.new()
			m.top_radius = 0.0
			m.bottom_radius = 0.5
			m.height = 1.0
			m.radial_segments = 24
			m.rings = 1
			mesh = m
		"capsule":
			var m := CapsuleMesh.new()
			m.radius = 0.5
			m.height = 2.0
			m.radial_segments = 20
			m.rings = 6
			# Achata para caber na caixa unitária (o tamanho padrão é 1 x 2 x 1).
			mesh = _bake(m, Transform3D(Basis.from_scale(Vector3(1.0, 0.5, 1.0)), Vector3.ZERO))
		"wedge":
			var m := PrismMesh.new()
			m.left_to_right = 0.0
			m.size = Vector3.ONE
			mesh = m
		"torus":
			var m := TorusMesh.new()
			m.inner_radius = 0.3
			m.outer_radius = 0.5
			m.rings = 24
			m.ring_segments = 12
			# A espessura do toro (0.2) é esticada até 1 para a caixa ser unitária.
			mesh = _bake(m, Transform3D(Basis.from_scale(Vector3(1.0, 5.0, 1.0)), Vector3.ZERO))
		"pyramid":
			var m := CylinderMesh.new()
			m.top_radius = 0.0
			m.bottom_radius = 0.5 * sqrt(2.0)
			m.height = 1.0
			m.radial_segments = 4
			m.rings = 1
			mesh = _bake(m, Transform3D(Basis(Vector3.UP, PI / 4.0), Vector3.ZERO))
		_:
			return get_mesh("box")
	_mesh_cache[shape] = mesh
	return mesh


## Aplica uma transformação aos vértices de uma malha e devolve uma ArrayMesh.
static func _bake(src: Mesh, xform: Transform3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	var normal_basis := xform.basis.inverse().transposed()
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			verts[i] = xform * verts[i]
		arrays[Mesh.ARRAY_VERTEX] = verts
		if arrays[Mesh.ARRAY_NORMAL] != null:
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in normals.size():
				normals[i] = (normal_basis * normals[i]).normalized()
			arrays[Mesh.ARRAY_NORMAL] = normals
		if arrays[Mesh.ARRAY_TANGENT] != null:
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			for i in range(0, tangents.size(), 4):
				var t := (xform.basis * Vector3(tangents[i], tangents[i + 1], tangents[i + 2])).normalized()
				tangents[i] = t.x
				tangents[i + 1] = t.y
				tangents[i + 2] = t.z
			arrays[Mesh.ARRAY_TANGENT] = tangents
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


static func _unit_points(shape: String) -> PackedVector3Array:
	if not _points_cache.has(shape):
		var pts := PackedVector3Array()
		var mesh := get_mesh(shape)
		for s in mesh.get_surface_count():
			pts.append_array(mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
		_points_cache[shape] = pts
	return _points_cache[shape]


static func _unit_faces(shape: String) -> PackedVector3Array:
	if not _faces_cache.has(shape):
		_faces_cache[shape] = get_mesh(shape).get_faces()
	return _faces_cache[shape]


static func _scaled(points: PackedVector3Array, size: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = points[i] * size
	return out


static func _uniform_xz(size: Vector3) -> bool:
	return absf(size.x - size.z) < 0.0001


## Forma de colisão para uma primitiva com o tamanho dado.
## `concave_ok` permite malha côncava (só para corpos fixos/móveis por script).
static func make_shape(shape: String, size: Vector3, concave_ok := true) -> Shape3D:
	size = size.abs().max(Vector3.ONE * PSData.MIN_SIZE)
	match shape:
		"box":
			var b := BoxShape3D.new()
			b.size = size
			return b
		"sphere":
			if absf(size.x - size.y) < 0.0001 and _uniform_xz(size):
				var sp := SphereShape3D.new()
				sp.radius = size.x * 0.5
				return sp
		"cylinder":
			if _uniform_xz(size):
				var c := CylinderShape3D.new()
				c.radius = size.x * 0.5
				c.height = size.y
				return c
		"capsule":
			if _uniform_xz(size) and size.y >= size.x:
				var cap := CapsuleShape3D.new()
				cap.radius = size.x * 0.5
				cap.height = size.y
				return cap
		"torus":
			if concave_ok:
				var cc := ConcavePolygonShape3D.new()
				cc.set_faces(_scaled(_unit_faces(shape), size))
				cc.backface_collision = true
				return cc
	var hull := ConvexPolygonShape3D.new()
	hull.points = _scaled(_unit_points(shape), size)
	return hull


# --------------------------------------------------------------------------
# Materiais
# --------------------------------------------------------------------------

## Material de uma peça. `texture` é a textura já carregada (ou null).
static func make_material(mat: Dictionary, texture: Texture2D = null) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s|%s" % [str(mat.get("color")), mat.get("metal", 0.0), mat.get("rough", 0.8), mat.get("emit", 0.0), mat.get("uv", 1.0), texture.get_instance_id() if texture else 0]
	if _material_cache.has(key):
		return _material_cache[key]
	var m := StandardMaterial3D.new()
	var color := PSData.arr_to_color(mat.get("color"), Color(0.8, 0.8, 0.8))
	m.albedo_color = color
	if color.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = float(mat.get("metal", 0.0))
	m.roughness = float(mat.get("rough", 0.8))
	var emit := float(mat.get("emit", 0.0))
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = Color(color.r, color.g, color.b)
		m.emission_energy_multiplier = emit
	if texture:
		m.albedo_texture = texture
		var uv := float(mat.get("uv", 1.0))
		m.uv1_scale = Vector3(uv, uv, uv)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _material_cache.size() > 512:
		_material_cache.clear()
	_material_cache[key] = m
	return m


static func get_water_material(mat: Dictionary) -> ShaderMaterial:
	if _water_shader == null:
		_water_shader = Shader.new()
		_water_shader.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;
uniform vec4 water_color : source_color = vec4(0.15, 0.45, 0.75, 0.7);
uniform float wave_speed = 1.0;
varying vec3 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(world_pos.x * 0.8 + TIME * wave_speed) * 0.04 + cos(world_pos.z * 0.6 + TIME * wave_speed * 1.3) * 0.04;
}
void fragment() {
	float ripple = sin(world_pos.x * 2.0 + TIME * 1.7) * cos(world_pos.z * 2.3 - TIME * 1.1);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = water_color.rgb * (0.85 + ripple * 0.05) + vec3(fres * 0.08);
	ALPHA = clamp(water_color.a + fres * 0.15, 0.0, 1.0);
	ROUGHNESS = 0.15;
	METALLIC = 0.0;
	SPECULAR = 0.4;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _water_shader
	m.set_shader_parameter("water_color", PSData.arr_to_color(mat.get("color"), Color(0.15, 0.45, 0.75, 0.7)))
	return m


## Material sem iluminação para marcadores do editor (luzes, ponto de início).
static func marker_material(color: Color, on_top := false) -> StandardMaterial3D:
	var key := "%s|%s" % [color, on_top]
	if _marker_materials.has(key):
		return _marker_materials[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if color.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if on_top:
		m.no_depth_test = true
		m.render_priority = 10
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_marker_materials[key] = m
	return m
