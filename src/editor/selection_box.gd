class_name PSSelectionBox
extends MeshInstance3D
## Desenha o contorno (caixa em arame) dos objetos selecionados.

var world: PSWorld
var ids: Array = []
var _im := ImmediateMesh.new()
var _mat: StandardMaterial3D


func _ready() -> void:
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(1.0, 0.72, 0.2)
	_mat.no_depth_test = true
	_mat.render_priority = 5
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	extra_cull_margin = 16384.0


func _process(_delta: float) -> void:
	_im.clear_surfaces()
	if world == null or ids.is_empty():
		return
	var any := false
	for id in ids:
		if world.has_object(id):
			any = true
			break
	if not any:
		return
	_im.surface_begin(Mesh.PRIMITIVE_LINES, _mat)
	for id in ids:
		var obj := world.get_obj(id)
		if obj == null:
			continue
		var box := world.get_local_aabb(id).grow(0.02)
		var xf := obj.node.global_transform
		if obj.type == "group":
			box = world.get_world_aabb(id).grow(0.05)
			xf = Transform3D.IDENTITY
		_box_lines(xf, box)
	_im.surface_end()


func _box_lines(xf: Transform3D, box: AABB) -> void:
	var c: Array[Vector3] = []
	for i in 8:
		c.append(xf * box.get_endpoint(i))
	# Arestas da AABB (índices de get_endpoint: bit0 = x, bit1 = y, bit2 = z).
	var edges := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
	for e in edges:
		_im.surface_add_vertex(c[e[0]])
		_im.surface_add_vertex(c[e[1]])
