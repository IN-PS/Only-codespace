class_name PSWorld
extends Node3D
## O mundo 3D: objetos, hierarquia, terreno e ambiente.
##
## O mesmo código monta o mundo em dois modos:
##  - EDIT: cada objeto ganha um corpo de "seleção" (camada exclusiva do editor)
##    e marcadores visuais para luzes e ponto de início;
##  - PLAY: os objetos ganham física de verdade (fixo, dinâmico, móvel por
##    script ou sem colisão). O modo de teste sempre monta uma cópia nova a
##    partir dos dados, então testar nunca altera o que está sendo editado.
##
## Transformações de hierarquia são rígidas (posição + rotação). O "tamanho" de
## uma peça só afeta a própria peça, não os filhos.

signal objects_changed
signal object_updated(id: String)

enum Mode { EDIT, PLAY }

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_TRIGGER := 4
const LAYER_PICK := 512
const LAYER_TERRAIN := 1024


class PSObject:
	extends RefCounted
	var id := ""
	var type := ""
	var data := {}
	var node: Node3D
	var visual: Node3D
	## Corpo que recebe as formas de colisão deste objeto (pode ser de um ancestral).
	var body: CollisionObject3D
	var placeholder := false
	var aabb_local := AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)


var mode := Mode.EDIT
var assets: PSAssetLibrary
var objects := {}
var env_data := PSData.default_environment()
var game_data := PSData.default_game()
var objects_root: Node3D
var terrain: PSTerrain
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var shadows_enabled := true
var _batch_depth := 0
var _batch_dirty := false


func _init(p_mode := Mode.EDIT) -> void:
	mode = p_mode
	name = "World"
	objects_root = Node3D.new()
	objects_root.name = "Objects"
	add_child(objects_root)
	world_env = WorldEnvironment.new()
	world_env.name = "Environment"
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	add_child(sun)


func set_assets(lib: PSAssetLibrary) -> void:
	if assets and assets.model_ready.is_connected(_on_model_ready):
		assets.model_ready.disconnect(_on_model_ready)
	assets = lib
	if assets:
		assets.model_ready.connect(_on_model_ready)


# --------------------------------------------------------------------------
# Carregar / salvar
# --------------------------------------------------------------------------

func load_project(data: Dictionary) -> void:
	begin_batch()
	clear_objects()
	apply_environment(data.get("env", {}))
	game_data = PSData.sanitize_game(data.get("game", {}))
	set_terrain_data(data.get("terrain"))
	for o in data.get("objects", []):
		add_object(o)
	end_batch()


func clear_objects() -> void:
	for child in objects_root.get_children():
		objects_root.remove_child(child)
		child.free()
	objects.clear()
	_notify_changed()


func set_terrain_data(t: Variant) -> void:
	if terrain:
		remove_child(terrain)
		terrain.free()
		terrain = null
	if t is Dictionary:
		terrain = PSTerrain.new()
		terrain.name = "Terrain"
		terrain.play_mode = mode == Mode.PLAY
		add_child(terrain)
		terrain.load_data(t)
	_notify_changed()


func get_terrain_data() -> Variant:
	return terrain.to_data() if terrain else null


## Lista de objetos em profundidade (pais antes dos filhos).
func serialize_objects() -> Array:
	var out: Array = []
	for id in get_root_ids():
		_serialize_rec(id, out)
	return out


func _serialize_rec(id: String, out: Array) -> void:
	out.append(get_object_data(id))
	for c in get_children_ids(id):
		_serialize_rec(c, out)


func write_into(data: Dictionary) -> void:
	data["objects"] = serialize_objects()
	data["env"] = env_data.duplicate(true)
	data["game"] = game_data.duplicate(true)
	data["terrain"] = get_terrain_data()


# --------------------------------------------------------------------------
# Lote de alterações (evita reconstruir a hierarquia a cada objeto)
# --------------------------------------------------------------------------

func begin_batch() -> void:
	_batch_depth += 1


func end_batch() -> void:
	_batch_depth = maxi(0, _batch_depth - 1)
	if _batch_depth == 0 and _batch_dirty:
		_batch_dirty = false
		objects_changed.emit()


func _notify_changed() -> void:
	if _batch_depth > 0:
		_batch_dirty = true
	else:
		objects_changed.emit()


# --------------------------------------------------------------------------
# Consulta
# --------------------------------------------------------------------------

func has_object(id: String) -> bool:
	return objects.has(id)


func get_obj(id: String) -> PSObject:
	return objects.get(id)


func count() -> int:
	return objects.size()


func get_object_data(id: String) -> Dictionary:
	var obj: PSObject = objects.get(id)
	if obj == null:
		return {}
	var d := obj.data.duplicate(true)
	d["id"] = id
	d["type"] = obj.type
	d["pos"] = PSData.v3_to_arr(obj.node.position)
	d["rot"] = PSData.quat_to_arr(obj.node.quaternion)
	d["parent"] = get_parent_id(id)
	return d


## Dados do objeto e de todos os descendentes (pais primeiro).
func get_subtree_data(id: String) -> Array:
	var out: Array = []
	if objects.has(id):
		_serialize_rec(id, out)
	return out


func get_parent_id(id: String) -> String:
	var obj: PSObject = objects.get(id)
	if obj == null or obj.node.get_parent() == objects_root:
		return ""
	var p := obj.node.get_parent()
	return String(p.get_meta("ps_id", "")) if p else ""


func get_root_ids() -> Array:
	return _object_children_ids(objects_root)


func get_children_ids(id: String) -> Array:
	var obj: PSObject = objects.get(id)
	if obj == null:
		return []
	return _object_children_ids(obj.node)


func _object_children_ids(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c.has_meta("ps_obj"):
			out.append(String(c.get_meta("ps_id")))
	return out


func get_index_in_parent(id: String) -> int:
	var pid := get_parent_id(id)
	var siblings := get_children_ids(pid) if pid != "" else get_root_ids()
	return siblings.find(id)


func is_descendant_of(id: String, ancestor_id: String) -> bool:
	var cur := get_parent_id(id)
	while cur != "":
		if cur == ancestor_id:
			return true
		cur = get_parent_id(cur)
	return false


func get_ancestors(id: String) -> Array:
	var out: Array = []
	var cur := get_parent_id(id)
	while cur != "":
		out.append(cur)
		cur = get_parent_id(cur)
	return out


func get_global_transform_of(id: String) -> Transform3D:
	var obj: PSObject = objects.get(id)
	return obj.node.global_transform if obj else Transform3D.IDENTITY


func find_by_name(obj_name: String) -> String:
	for id in objects:
		if String(objects[id].data.get("name", "")) == obj_name:
			return id
	return ""


func make_unique_name(base: String) -> String:
	var names := {}
	for o in objects.values():
		names[String(o.data.get("name", ""))] = true
	if not names.has(base):
		return base
	var i := 2
	while names.has("%s %d" % [base, i]):
		i += 1
	return "%s %d" % [base, i]


## Caixa envolvente do objeto (e descendentes) no espaço global.
func get_world_aabb(id: String, include_children := true) -> AABB:
	var obj: PSObject = objects.get(id)
	if obj == null:
		return AABB()
	var box := obj.node.global_transform * _local_box(obj)
	if include_children:
		for c in get_children_ids(id):
			box = box.merge(get_world_aabb(c, true))
	return box


func _local_box(obj: PSObject) -> AABB:
	match obj.type:
		"group":
			return AABB(Vector3(-0.15, -0.15, -0.15), Vector3(0.3, 0.3, 0.3))
		"light", "spawn":
			return obj.aabb_local
	return obj.aabb_local


func get_local_aabb(id: String) -> AABB:
	var obj: PSObject = objects.get(id)
	return _local_box(obj) if obj else AABB()


# --------------------------------------------------------------------------
# Criação / remoção
# --------------------------------------------------------------------------

## Adiciona um objeto a partir do dicionário. `index` é a posição entre os irmãos.
func add_object(d: Dictionary, index := -1) -> PSObject:
	var data := d.duplicate(true)
	var id := String(data.get("id", ""))
	if id == "" or objects.has(id):
		id = App.new_id("o")
	var type := String(data.get("type", "part"))
	if not PSData.OBJECT_TYPES.has(type):
		return null
	var parent_id := String(data.get("parent", ""))
	var parent_obj: PSObject = objects.get(parent_id)
	var parent_node: Node3D = parent_obj.node if parent_obj else objects_root

	var obj := PSObject.new()
	obj.id = id
	obj.type = type
	for k in ["id", "type", "pos", "rot", "parent"]:
		data.erase(k)
	obj.data = data
	obj.node = _create_root_node(obj, parent_obj)
	obj.node.name = id
	obj.node.set_meta("ps_id", id)
	obj.node.set_meta("ps_obj", true)
	obj.node.transform = Transform3D(Basis(PSData.arr_to_quat(d.get("rot"))), PSData.arr_to_v3(d.get("pos")))
	parent_node.add_child(obj.node)
	objects[id] = obj
	if index >= 0:
		_move_to_index(obj.node, index)
	_build(obj)
	_notify_changed()
	return obj


func _move_to_index(node: Node3D, index: int) -> void:
	var parent := node.get_parent()
	var siblings := _object_children_ids(parent)
	siblings.erase(String(node.get_meta("ps_id")))
	if index >= siblings.size():
		parent.move_child(node, -1)
		return
	var target: Node = parent.get_node(NodePath(siblings[index]))
	parent.move_child(node, target.get_index())


func remove_object(id: String) -> void:
	var obj: PSObject = objects.get(id)
	if obj == null:
		return
	for c in get_children_ids(id):
		_forget_rec(c)
	objects.erase(id)
	var parent := obj.node.get_parent()
	if parent:
		parent.remove_child(obj.node)
	obj.node.free()
	_notify_changed()


func _forget_rec(id: String) -> void:
	for c in get_children_ids(id):
		_forget_rec(c)
	objects.erase(id)


## Move um objeto para outro pai mantendo a posição global.
func reparent_object(id: String, new_parent_id: String, index := -1) -> bool:
	var obj: PSObject = objects.get(id)
	if obj == null or id == new_parent_id:
		return false
	if new_parent_id != "" and (not objects.has(new_parent_id) or is_descendant_of(new_parent_id, id)):
		return false
	var target: Node3D = objects[new_parent_id].node if new_parent_id != "" else objects_root
	if obj.node.get_parent() != target:
		var gt := obj.node.global_transform
		obj.node.get_parent().remove_child(obj.node)
		target.add_child(obj.node)
		obj.node.global_transform = Transform3D(gt.basis.orthonormalized(), gt.origin)
	if index >= 0:
		_move_to_index(obj.node, index)
	_notify_changed()
	return true


## Aplica um estado completo (usado por desfazer/refazer e pelo inspetor).
func apply_object_data(d: Dictionary, index := -1) -> void:
	var id := String(d.get("id", ""))
	var obj: PSObject = objects.get(id)
	if obj == null:
		add_object(d, index)
		return
	var parent_id := String(d.get("parent", ""))
	if parent_id != get_parent_id(id) or (index >= 0 and index != get_index_in_parent(id)):
		reparent_object(id, parent_id, index)
	obj.node.transform = Transform3D(Basis(PSData.arr_to_quat(d.get("rot"))), PSData.arr_to_v3(d.get("pos")))
	var data := d.duplicate(true)
	for k in ["id", "type", "pos", "rot", "parent"]:
		data.erase(k)
	var name_changed: bool = data.get("name") != obj.data.get("name")
	obj.data = data
	_build(obj)
	object_updated.emit(id)
	if name_changed:
		_notify_changed()


## Altera só a transformação local (caminho rápido durante o arraste).
func set_object_transform(id: String, xform: Transform3D) -> void:
	var obj: PSObject = objects.get(id)
	if obj:
		obj.node.transform = Transform3D(xform.basis.orthonormalized(), xform.origin)


func set_object_global_transform(id: String, xform: Transform3D) -> void:
	var obj: PSObject = objects.get(id)
	if obj:
		obj.node.global_transform = Transform3D(xform.basis.orthonormalized(), xform.origin)


## Altera o tamanho reconstruindo apenas visual e colisão.
func set_object_size(id: String, size: Vector3) -> void:
	var obj: PSObject = objects.get(id)
	if obj and obj.data.has("size"):
		obj.data["size"] = PSData.v3_to_arr(size.max(Vector3.ONE * PSData.MIN_SIZE))
		_build(obj)


func set_object_prop(id: String, key: String, value: Variant) -> void:
	var obj: PSObject = objects.get(id)
	if obj == null:
		return
	obj.data[key] = value
	_build(obj)
	object_updated.emit(id)
	if key == "name":
		_notify_changed()


# --------------------------------------------------------------------------
# Montagem dos nós
# --------------------------------------------------------------------------

func _dynamic_ancestor(parent_obj: PSObject) -> PSObject:
	var cur := parent_obj
	while cur != null:
		if cur.node is RigidBody3D:
			return cur
		var pid := get_parent_id(cur.id)
		cur = objects.get(pid) if pid != "" else null
	return null


func _create_root_node(obj: PSObject, parent_obj: PSObject) -> Node3D:
	if mode == Mode.EDIT:
		return Node3D.new()
	var phys: Dictionary = obj.data.get("phys", {})
	var phys_mode := String(phys.get("mode", "none")) if obj.type in ["part", "model"] else "none"
	var dyn := _dynamic_ancestor(parent_obj)
	if dyn != null:
		obj.body = dyn.node as CollisionObject3D if phys_mode != "none" else null
		return Node3D.new()
	var pm := PhysicsMaterial.new()
	pm.friction = float(phys.get("friction", 0.6))
	pm.bounce = float(phys.get("bounce", 0.0))
	match phys_mode:
		"static":
			var b := StaticBody3D.new()
			b.physics_material_override = pm
			obj.body = b
			return b
		"kinematic":
			var k := AnimatableBody3D.new()
			k.sync_to_physics = true
			k.physics_material_override = pm
			obj.body = k
			return k
		"dynamic":
			var r := RigidBody3D.new()
			r.mass = float(phys.get("mass", 1.0))
			r.physics_material_override = pm
			r.continuous_cd = true
			obj.body = r
			return r
	return Node3D.new()


func _clear_internal(obj: PSObject) -> void:
	for c in obj.node.get_children():
		if String(c.name).begins_with("_"):
			obj.node.remove_child(c)
			c.free()
	# Formas que este objeto colocou no corpo de um ancestral dinâmico.
	if obj.body and obj.body != obj.node and is_instance_valid(obj.body):
		for c in obj.body.get_children():
			if c.get_meta("ps_owner", "") == obj.id:
				obj.body.remove_child(c)
				c.free()
	obj.visual = null


func _build(obj: PSObject) -> void:
	_clear_internal(obj)
	obj.placeholder = false
	if obj.node is CollisionObject3D:
		var co := obj.node as CollisionObject3D
		co.collision_layer = LAYER_WORLD
		co.collision_mask = LAYER_WORLD | LAYER_PLAYER
		co.set_meta("ps_id", obj.id)
	match obj.type:
		"part":
			_build_part(obj)
		"model":
			_build_model(obj)
		"light":
			_build_light(obj)
		"spawn":
			_build_spawn(obj)
		"water":
			_build_water(obj)
		"text":
			_build_text(obj)
		"group":
			obj.aabb_local = AABB(Vector3(-0.15, -0.15, -0.15), Vector3(0.3, 0.3, 0.3))
	_apply_visibility(obj)


func _size_of(obj: PSObject) -> Vector3:
	return PSData.arr_to_v3(obj.data.get("size"), Vector3.ONE).abs().max(Vector3.ONE * PSData.MIN_SIZE)


func _apply_visibility(obj: PSObject) -> void:
	if obj.visual == null:
		return
	var vis := bool(obj.data.get("visible", true))
	if mode == Mode.PLAY:
		obj.visual.visible = vis
	elif not vis:
		# No editor, objetos invisíveis aparecem translúcidos para poderem ser selecionados.
		_set_ghost(obj.visual)


func _set_ghost(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).transparency = 0.75
	for c in node.get_children():
		_set_ghost(c)


func _add_pick_shape(obj: PSObject, shape: Shape3D, offset := Transform3D.IDENTITY) -> void:
	if mode == Mode.EDIT:
		var body := StaticBody3D.new()
		body.name = "_pick"
		body.collision_layer = LAYER_PICK
		body.collision_mask = 0
		body.set_meta("ps_id", obj.id)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = offset
		body.add_child(cs)
		obj.node.add_child(body)
	else:
		_add_collision_shape(obj, shape, offset)


func _add_collision_shape(obj: PSObject, shape: Shape3D, offset := Transform3D.IDENTITY) -> void:
	if obj.body == null or not is_instance_valid(obj.body):
		return
	var cs := CollisionShape3D.new()
	cs.shape = shape
	if obj.body == obj.node:
		cs.name = "_shape"
		cs.transform = offset
		obj.node.add_child(cs)
	else:
		# Objeto preso a um ancestral dinâmico: a forma vai para o corpo dele.
		cs.name = "_shape_" + obj.id
		cs.set_meta("ps_owner", obj.id)
		var rel := obj.body.global_transform.affine_inverse() * obj.node.global_transform if obj.node.is_inside_tree() else _relative_to_ancestor(obj, obj.body)
		cs.transform = rel * offset
		obj.body.add_child(cs)


func _relative_to_ancestor(obj: PSObject, ancestor: Node3D) -> Transform3D:
	var xf := obj.node.transform
	var cur := obj.node.get_parent()
	while cur and cur != ancestor and cur is Node3D:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _build_part(obj: PSObject) -> void:
	var shape := String(obj.data.get("shape", "box"))
	var size := _size_of(obj)
	var mi := MeshInstance3D.new()
	mi.name = "_visual"
	mi.mesh = PSPrimitives.get_mesh(shape)
	mi.scale = size
	var mat: Dictionary = obj.data.get("mat", {})
	var tex: Texture2D = assets.get_texture(String(mat.get("tex", ""))) if assets else null
	mi.material_override = PSPrimitives.make_material(mat, tex)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if obj.data.get("shadow", true) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	obj.node.add_child(mi)
	obj.visual = mi
	obj.aabb_local = AABB(-size * 0.5, size)
	var phys_mode := String(obj.data.get("phys", {}).get("mode", "static"))
	if mode == Mode.EDIT or phys_mode != "none":
		var concave_ok := phys_mode != "dynamic" and not (obj.body is RigidBody3D)
		_add_pick_shape(obj, PSPrimitives.make_shape(shape, size, concave_ok))


func _build_model(obj: PSObject) -> void:
	var asset_id := String(obj.data.get("asset", ""))
	var size := _size_of(obj)
	var inst: Node3D = null
	if assets and asset_id != "":
		if assets.is_model_ready(asset_id):
			inst = assets.instantiate_model(asset_id)
		elif not assets.has_model_failed(asset_id):
			assets.request_model(asset_id)
	var box := AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)
	if inst == null:
		# Caixa provisória enquanto o modelo carrega (ou se ele falhou).
		obj.placeholder = true
		var mi := MeshInstance3D.new()
		mi.mesh = PSPrimitives.get_mesh("box")
		mi.position = Vector3(0, 0.5, 0)
		var failed := assets != null and assets.has_model_failed(asset_id)
		mi.material_override = PSPrimitives.marker_material(Color(1.0, 0.35, 0.3, 0.45) if failed else Color(0.6, 0.7, 0.9, 0.35))
		inst = Node3D.new()
		inst.add_child(mi)
	else:
		box = assets.get_model_aabb(asset_id)
		_set_shadow_rec(inst, bool(obj.data.get("shadow", true)))
	inst.name = "_visual"
	inst.scale = size
	obj.node.add_child(inst)
	obj.visual = inst
	var scaled_box := AABB(box.position * size, box.size * size)
	obj.aabb_local = scaled_box
	var phys_mode := String(obj.data.get("phys", {}).get("mode", "static"))
	if mode == Mode.EDIT:
		var b := BoxShape3D.new()
		b.size = scaled_box.size.max(Vector3.ONE * 0.05)
		_add_pick_shape(obj, b, Transform3D(Basis.IDENTITY, scaled_box.get_center()))
	elif phys_mode != "none" and not obj.placeholder:
		var dynamic := phys_mode == "dynamic" or obj.body is RigidBody3D
		var faces := PSAssetLibrary.collect_faces(inst)
		for i in faces.size():
			faces[i] = faces[i] * size
		if faces.is_empty():
			var bb := BoxShape3D.new()
			bb.size = scaled_box.size.max(Vector3.ONE * 0.05)
			_add_collision_shape(obj, bb, Transform3D(Basis.IDENTITY, scaled_box.get_center()))
		elif dynamic:
			var hull := ConvexPolygonShape3D.new()
			hull.points = faces
			_add_collision_shape(obj, hull)
		else:
			var cc := ConcavePolygonShape3D.new()
			cc.set_faces(faces)
			cc.backface_collision = true
			_add_collision_shape(obj, cc)


func _set_shadow_rec(node: Node, on: bool) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_set_shadow_rec(c, on)


func _on_model_ready(asset_id: String) -> void:
	for obj in objects.values():
		if obj.type == "model" and String(obj.data.get("asset", "")) == asset_id:
			_build(obj)
			object_updated.emit(obj.id)


func _build_light(obj: PSObject) -> void:
	var l: Dictionary = obj.data.get("light", PSData.default_light())
	var light: Light3D
	if l.get("kind", "point") == "spot":
		var s := SpotLight3D.new()
		s.spot_range = float(l.get("range", 8.0))
		s.spot_angle = float(l.get("angle", 35.0))
		light = s
	else:
		var o := OmniLight3D.new()
		o.omni_range = float(l.get("range", 8.0))
		light = o
	light.name = "_light"
	light.light_color = PSData.arr_to_color(l.get("color"), Color.WHITE)
	light.light_energy = float(l.get("energy", 2.0))
	light.shadow_enabled = bool(l.get("shadow", false)) and shadows_enabled
	light.visible = bool(obj.data.get("visible", true)) or mode == Mode.EDIT
	obj.node.add_child(light)
	obj.aabb_local = AABB(Vector3(-0.25, -0.25, -0.25), Vector3(0.5, 0.5, 0.5))
	if mode == Mode.EDIT:
		var mi := MeshInstance3D.new()
		mi.name = "_visual"
		mi.mesh = PSPrimitives.get_mesh("sphere")
		mi.scale = Vector3.ONE * 0.35
		mi.material_override = PSPrimitives.marker_material(Color(1.0, 0.85, 0.3))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		obj.node.add_child(mi)
		if light is SpotLight3D:
			var cone := MeshInstance3D.new()
			cone.name = "_visual_dir"
			cone.mesh = PSPrimitives.get_mesh("cone")
			cone.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0) * Basis.from_scale(Vector3(0.3, 0.4, 0.3)), Vector3(0, 0, -0.35))
			cone.material_override = PSPrimitives.marker_material(Color(1.0, 0.85, 0.3, 0.6))
			cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			obj.node.add_child(cone)
		obj.visual = mi
		var sp := SphereShape3D.new()
		sp.radius = 0.3
		_add_pick_shape(obj, sp)


func _build_spawn(obj: PSObject) -> void:
	obj.aabb_local = AABB(Vector3(-0.7, 0, -0.7), Vector3(1.4, 0.3, 1.4))
	if mode != Mode.EDIT:
		return
	var root := Node3D.new()
	root.name = "_visual"
	var pad := MeshInstance3D.new()
	pad.mesh = PSPrimitives.get_mesh("cylinder")
	pad.scale = Vector3(1.4, 0.1, 1.4)
	pad.position = Vector3(0, 0.05, 0)
	pad.material_override = PSPrimitives.make_material({"color": [0.2, 0.75, 0.4, 1.0], "rough": 0.6})
	root.add_child(pad)
	var arrow := MeshInstance3D.new()
	arrow.mesh = PSPrimitives.get_mesh("cone")
	arrow.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0) * Basis.from_scale(Vector3(0.35, 0.5, 0.15)), Vector3(0, 0.2, -0.35))
	arrow.material_override = PSPrimitives.marker_material(Color(0.95, 1.0, 0.95))
	root.add_child(arrow)
	obj.node.add_child(root)
	obj.visual = root
	var b := BoxShape3D.new()
	b.size = Vector3(1.4, 0.3, 1.4)
	_add_pick_shape(obj, b, Transform3D(Basis.IDENTITY, Vector3(0, 0.15, 0)))


func _build_water(obj: PSObject) -> void:
	var size := _size_of(obj)
	var mi := MeshInstance3D.new()
	mi.name = "_visual"
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE
	pm.subdivide_width = 24
	pm.subdivide_depth = 24
	mi.mesh = pm
	mi.scale = Vector3(size.x, 1.0, size.z)
	mi.material_override = PSPrimitives.get_water_material(obj.data.get("mat", {}))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	obj.node.add_child(mi)
	obj.visual = mi
	obj.aabb_local = AABB(Vector3(-size.x * 0.5, -size.y, -size.z * 0.5), Vector3(size.x, size.y, size.z))
	var b := BoxShape3D.new()
	if mode == Mode.EDIT:
		b.size = Vector3(size.x, 0.2, size.z)
		_add_pick_shape(obj, b)
	else:
		# Volume de água: o jogador nada quando entra nele.
		var area := Area3D.new()
		area.name = "_water_area"
		area.collision_layer = LAYER_TRIGGER
		area.collision_mask = LAYER_PLAYER
		area.monitorable = false
		area.set_meta("ps_water", true)
		var cs := CollisionShape3D.new()
		b.size = Vector3(size.x, size.y, size.z)
		cs.shape = b
		cs.position = Vector3(0, -size.y * 0.5, 0)
		area.add_child(cs)
		obj.node.add_child(area)


func _build_text(obj: PSObject) -> void:
	var size := _size_of(obj)
	var mi := MeshInstance3D.new()
	mi.name = "_visual"
	var tm := TextMesh.new()
	tm.text = String(obj.data.get("text", "Texto"))
	tm.font_size = 64
	tm.pixel_size = 0.01
	tm.depth = 0.05
	mi.mesh = tm
	mi.scale = size
	mi.material_override = PSPrimitives.make_material(obj.data.get("mat", {}))
	obj.node.add_child(mi)
	obj.visual = mi
	var box := tm.get_aabb()
	if box.size.length() < 0.01:
		box = AABB(Vector3(-0.5, -0.3, -0.05), Vector3(1, 0.6, 0.1))
	obj.aabb_local = AABB(box.position * size, box.size * size)
	if mode == Mode.EDIT:
		var b := BoxShape3D.new()
		b.size = obj.aabb_local.size.max(Vector3.ONE * 0.05)
		_add_pick_shape(obj, b, Transform3D(Basis.IDENTITY, obj.aabb_local.get_center()))


# --------------------------------------------------------------------------
# Seleção por raio
# --------------------------------------------------------------------------

## Retorna o id do objeto atingido pelo raio (ou "").
func pick(from: Vector3, to: Vector3, include_locked := false) -> String:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	for _i in 16:
		var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_PICK, exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return ""
		var id := String(hit["collider"].get_meta("ps_id", ""))
		if id != "" and objects.has(id) and (include_locked or not bool(objects[id].data.get("locked", false))):
			return id
		exclude.append(hit["rid"])
	return ""


## Ponto de superfície atingido (objetos e terreno). Retorna {} se nada.
func raycast_surface(from: Vector3, to: Vector3, exclude_ids: Array = []) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	for id in exclude_ids:
		var obj: PSObject = objects.get(id)
		if obj:
			_collect_rids(obj.node, exclude)
	var mask := LAYER_PICK | LAYER_TERRAIN if mode == Mode.EDIT else LAYER_WORLD
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {}
	return {"position": hit["position"], "normal": hit["normal"], "id": String(hit["collider"].get_meta("ps_id", ""))}


func _collect_rids(node: Node, out: Array[RID]) -> void:
	if node is CollisionObject3D:
		out.append((node as CollisionObject3D).get_rid())
	for c in node.get_children():
		_collect_rids(c, out)


# --------------------------------------------------------------------------
# Ambiente
# --------------------------------------------------------------------------

const SKY_PRESETS := {
	"day": {"top": Color(0.22, 0.45, 0.85), "horizon": Color(0.66, 0.78, 0.92), "ground": Color(0.25, 0.23, 0.21), "sun": Color(1.0, 0.96, 0.9), "sun_mult": 1.0, "amb": Color(0.62, 0.66, 0.72), "amb_mult": 1.0},
	"sunset": {"top": Color(0.22, 0.24, 0.5), "horizon": Color(0.98, 0.58, 0.32), "ground": Color(0.22, 0.17, 0.16), "sun": Color(1.0, 0.7, 0.45), "sun_mult": 0.9, "amb": Color(0.62, 0.5, 0.5), "amb_mult": 0.9},
	"night": {"top": Color(0.01, 0.02, 0.06), "horizon": Color(0.07, 0.09, 0.17), "ground": Color(0.03, 0.03, 0.04), "sun": Color(0.6, 0.7, 1.0), "sun_mult": 0.18, "amb": Color(0.3, 0.36, 0.55), "amb_mult": 0.5},
	"overcast": {"top": Color(0.52, 0.55, 0.6), "horizon": Color(0.72, 0.74, 0.77), "ground": Color(0.3, 0.3, 0.3), "sun": Color(0.9, 0.92, 0.95), "sun_mult": 0.35, "amb": Color(0.72, 0.74, 0.77), "amb_mult": 1.3},
}


func apply_environment(e: Variant) -> void:
	env_data = PSData.sanitize_environment(e)
	var preset: Dictionary = SKY_PRESETS.get(env_data["sky"], SKY_PRESETS["day"])
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = preset["top"]
	sky_mat.sky_horizon_color = preset["horizon"]
	sky_mat.ground_bottom_color = preset["ground"]
	sky_mat.ground_horizon_color = preset["horizon"].darkened(0.2)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Luz ambiente de cor neutra (a do céu deixava tudo azulado demais).
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = preset["amb"]
	env.ambient_light_energy = float(env_data["ambient"]) * float(preset["amb_mult"])
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.fog_enabled = bool(env_data["fog"])
	env.fog_density = float(env_data["fog_density"])
	env.fog_light_color = preset["horizon"]
	world_env.environment = env
	sun.rotation_degrees = Vector3(float(env_data["sun_pitch"]), float(env_data["sun_yaw"]), 0.0)
	sun.light_color = preset["sun"]
	sun.light_energy = float(env_data["sun_energy"]) * float(preset["sun_mult"])
	sun.shadow_enabled = shadows_enabled
	sun.directional_shadow_max_distance = 60.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 2.0
	sun.shadow_blur = 1.5


func set_shadows(on: bool) -> void:
	shadows_enabled = on
	sun.shadow_enabled = on
	for obj in objects.values():
		if obj.type == "light":
			_build(obj)
