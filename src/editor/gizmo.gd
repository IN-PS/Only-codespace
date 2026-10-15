class_name PSGizmo
extends Node3D
## Gizmo de transformação para toque.
##
## O teste de toque é feito em espaço de tela (distância do dedo até o eixo
## projetado), com tolerância generosa, e o gizmo mantém tamanho constante na
## tela independentemente da distância da câmera.

signal drag_started
signal drag_updated
signal drag_finished(before: Array, after: Array, label: String)

const HIT_RADIUS := 26.0
const SCREEN_FRACTION := 0.17

var world: PSWorld
var camera: PSEditorCamera
var mode := "move"          # select, move, rotate, scale
var local_space := false
var snap := true
var snap_move := 0.5
var snap_rotate := 15.0
var snap_scale := 0.25
var selection: Array = []

var _root: Node3D
var _handles := {}          # nome -> MeshInstance3D
var _handle_colors := {}
var _active := ""
var _highlight := ""
var _start := {}            # id -> {"global": Transform3D, "size": Vector3, "data": Dictionary}
var _before: Array = []
var _pivot_start := Vector3.ZERO
var _basis_start := Basis.IDENTITY
var _axis := Vector3.ZERO
var _t0 := 0.0
var _prev_angle := 0.0
var _angle_acc := 0.0
var _screen_start := Vector2.ZERO
var _plane_hit0 := Vector3.ZERO
var _surface_mode := false
var _primary_id := ""
var _exclude_ids: Array = []
var _gizmo_len := 1.0


func _ready() -> void:
	_root = Node3D.new()
	add_child(_root)
	_build_handles()
	visible = false


# --------------------------------------------------------------------------
# Construção
# --------------------------------------------------------------------------

func _build_handles() -> void:
	var axes := {"x": [Vector3.RIGHT, PSTheme.AXIS_X], "y": [Vector3.UP, PSTheme.AXIS_Y], "z": [Vector3.BACK, PSTheme.AXIS_Z]}
	for a in axes:
		var dir: Vector3 = axes[a][0]
		var col: Color = axes[a][1]
		var to_axis := _basis_for_axis(dir)
		# Mover: haste + ponta.
		var move := Node3D.new()
		move.add_child(_part("cylinder", Transform3D(to_axis * Basis.from_scale(Vector3(0.06, 0.7, 0.06)), dir * 0.5), col))
		move.add_child(_part("cone", Transform3D(to_axis * Basis.from_scale(Vector3(0.2, 0.28, 0.2)), dir * 0.98), col))
		_register("m" + a, move, col)
		# Girar: anel fino.
		var ring := _part("ring", Transform3D(to_axis, Vector3.ZERO), col)
		_register("r" + a, ring, col)
		# Escalar: haste + cubo.
		var sc := Node3D.new()
		sc.add_child(_part("cylinder", Transform3D(to_axis * Basis.from_scale(Vector3(0.05, 0.72, 0.05)), dir * 0.5), col))
		sc.add_child(_part("box", Transform3D(to_axis * Basis.from_scale(Vector3(0.17, 0.17, 0.17)), dir * 0.94), col))
		_register("s" + a, sc, col)
	_register("mc", _part("sphere", Transform3D(Basis.from_scale(Vector3.ONE * 0.24), Vector3.ZERO), Color(0.95, 0.95, 0.95)), Color(0.95, 0.95, 0.95))
	_register("sc", _part("box", Transform3D(Basis.from_scale(Vector3.ONE * 0.22), Vector3.ZERO), Color(0.95, 0.95, 0.95)), Color(0.95, 0.95, 0.95))


func _basis_for_axis(dir: Vector3) -> Basis:
	# As primitivas apontam para +Y; gira para o eixo pedido.
	if dir == Vector3.RIGHT:
		return Basis(Vector3.BACK, -PI / 2.0)
	if dir == Vector3.BACK:
		return Basis(Vector3.RIGHT, PI / 2.0)
	return Basis.IDENTITY


func _part(shape: String, xf: Transform3D, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if shape == "ring":
		var t := TorusMesh.new()
		t.inner_radius = 0.92
		t.outer_radius = 0.98
		t.rings = 48
		t.ring_segments = 6
		mi.mesh = t
	else:
		mi.mesh = PSPrimitives.get_mesh(shape)
	mi.transform = xf
	mi.material_override = PSPrimitives.marker_material(col, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _register(handle_name: String, node: Node3D, col: Color) -> void:
	node.name = handle_name
	_root.add_child(node)
	_handles[handle_name] = node
	_handle_colors[handle_name] = col


func _set_handle_color(handle_name: String, col: Color) -> void:
	var node: Node3D = _handles.get(handle_name)
	if node == null:
		return
	var nodes: Array = [node]
	nodes.append_array(node.get_children())
	for n in nodes:
		if n is MeshInstance3D:
			n.material_override = PSPrimitives.marker_material(col, true)


# --------------------------------------------------------------------------
# Estado
# --------------------------------------------------------------------------

func set_selection(ids: Array) -> void:
	selection = ids.duplicate()
	refresh()


func set_mode(m: String) -> void:
	mode = m
	refresh()


func is_dragging() -> bool:
	return _active != ""


func _movable_ids() -> Array:
	# Ignora objetos cujo ancestral também está selecionado (já se movem junto).
	var out: Array = []
	for id in selection:
		if not world.has_object(id) or bool(world.get_obj(id).data.get("locked", false)):
			continue
		var skip := false
		for anc in world.get_ancestors(id):
			if selection.has(anc):
				skip = true
				break
		if not skip:
			out.append(id)
	return out


func _can_axis_scale() -> bool:
	var ids := _movable_ids()
	if ids.size() != 1:
		return false
	return world.get_obj(ids[0]).data.has("size")


func _can_uniform_scale() -> bool:
	for id in _movable_ids():
		var obj := world.get_obj(id)
		if obj.data.has("size") or obj.type == "group":
			return true
	return false


func refresh() -> void:
	var ids := _movable_ids()
	if world == null or ids.is_empty() or mode == "select":
		visible = false
		return
	visible = true
	for h in _handles:
		var n: Node3D = _handles[h]
		match h[0]:
			"m":
				n.visible = mode == "move"
			"r":
				n.visible = mode == "rotate"
			"s":
				if h == "sc":
					n.visible = mode == "scale" and _can_uniform_scale()
				else:
					n.visible = mode == "scale" and _can_axis_scale()
	if mode == "scale" and not _can_uniform_scale():
		visible = false
	_update_placement()


func _process(_delta: float) -> void:
	if visible and not is_dragging():
		_update_placement()
	elif visible:
		_update_size()


func _selection_pivot(ids: Array) -> Vector3:
	var p := Vector3.ZERO
	for id in ids:
		p += world.get_global_transform_of(id).origin
	return p / maxf(1.0, ids.size())


func _gizmo_basis(ids: Array) -> Basis:
	if ids.size() == 1 and (local_space or mode == "scale"):
		return world.get_global_transform_of(ids[0]).basis.orthonormalized()
	return Basis.IDENTITY


func _update_placement() -> void:
	var ids := _movable_ids()
	if ids.is_empty():
		visible = false
		return
	global_transform = Transform3D(_gizmo_basis(ids), _selection_pivot(ids))
	_update_size()


func _update_size() -> void:
	if camera == null or not camera.is_inside_tree():
		return
	var d := camera.global_position.distance_to(global_position)
	_gizmo_len = maxf(0.05, 2.0 * d * tan(deg_to_rad(camera.fov * 0.5)) * SCREEN_FRACTION)
	_root.scale = Vector3.ONE * _gizmo_len


# --------------------------------------------------------------------------
# Teste de toque
# --------------------------------------------------------------------------

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0
	if ab.length_squared() > 0.0001:
		t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Retorna o nome do controle sob o ponto da tela, ou "".
func hit_test(screen_pos: Vector2) -> String:
	if not visible or camera == null:
		return ""
	var best := ""
	var best_d := HIT_RADIUS
	var o := global_position
	var b := global_transform.basis
	var c2 := camera.unproject_position(o)
	if camera.is_position_behind(o):
		return ""
	for h in _handles:
		var node: Node3D = _handles[h]
		if not node.visible:
			continue
		var d := INF
		if h == "mc" or h == "sc":
			d = screen_pos.distance_to(c2) * 1.15
		else:
			var axis := _axis_vec(h[1], b)
			if h[0] == "r":
				d = _ring_dist(screen_pos, o, axis)
			else:
				var a2 := camera.unproject_position(o + axis * _gizmo_len * 0.25)
				var t2 := camera.unproject_position(o + axis * _gizmo_len * 1.15)
				if a2.distance_to(t2) < 6.0:
					continue
				d = _seg_dist(screen_pos, a2, t2)
		if d < best_d:
			best_d = d
			best = h
	return best


func _axis_vec(letter: String, b: Basis) -> Vector3:
	match letter:
		"x":
			return b.x.normalized()
		"y":
			return b.y.normalized()
	return b.z.normalized()


func _ring_dist(p: Vector2, o: Vector3, axis: Vector3) -> float:
	var u := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u).normalized()
	var r := _gizmo_len * 0.95
	var best := INF
	var prev := Vector2.ZERO
	for i in 49:
		var a := TAU * i / 48.0
		var w := o + (u * cos(a) + v * sin(a)) * r
		var s := camera.unproject_position(w)
		if i > 0:
			best = minf(best, _seg_dist(p, prev, s))
		prev = s
	return best


func highlight(handle_name: String) -> void:
	if _highlight == handle_name:
		return
	if _highlight != "":
		_set_handle_color(_highlight, _handle_colors[_highlight])
	_highlight = handle_name
	if handle_name != "":
		_set_handle_color(handle_name, Color(1.0, 0.86, 0.3))


# --------------------------------------------------------------------------
# Arraste
# --------------------------------------------------------------------------

func _capture_start(ids: Array) -> void:
	_start.clear()
	_before.clear()
	for id in ids:
		var obj := world.get_obj(id)
		_start[id] = {
			"global": obj.node.global_transform,
			"size": PSData.arr_to_v3(obj.data.get("size"), Vector3.ONE),
		}
		if obj.type == "group" and mode == "scale":
			for sub in world.get_subtree_data(id):
				_before.append(sub)
				var sid := String(sub["id"])
				if sid != id:
					var so := world.get_obj(sid)
					_start[sid] = {"global": so.node.global_transform, "size": PSData.arr_to_v3(so.data.get("size"), Vector3.ONE), "child_of_group": true}
		else:
			_before.append(world.get_object_data(id))


## Começa a arrastar um controle (nome devolvido por hit_test).
func begin_drag(handle_name: String, screen_pos: Vector2) -> bool:
	var ids := _movable_ids()
	if ids.is_empty():
		return false
	_active = handle_name
	_surface_mode = false
	_capture_start(ids)
	_pivot_start = global_position
	_basis_start = global_transform.basis
	_screen_start = screen_pos
	if handle_name.length() == 2 and handle_name[1] in ["x", "y", "z"]:
		_axis = _axis_vec(handle_name[1], _basis_start)
	if handle_name[0] == "m" and handle_name != "mc":
		_t0 = _axis_param(screen_pos)
	elif handle_name == "mc":
		var hit = _ray_plane(screen_pos, Plane(Vector3.UP, _pivot_start.y))
		_plane_hit0 = hit if hit != null else _pivot_start
	elif handle_name[0] == "r":
		_prev_angle = _screen_angle(screen_pos)
		_angle_acc = 0.0
	elif handle_name[0] == "s" and handle_name != "sc":
		_t0 = _axis_param(screen_pos)
		if absf(_t0) < 0.001:
			_t0 = _gizmo_len
	highlight(handle_name)
	drag_started.emit()
	return true


## Arraste livre sobre superfícies (dedo em cima do objeto selecionado).
func begin_surface_drag(primary_id: String, screen_pos: Vector2) -> bool:
	var ids := _movable_ids()
	if ids.is_empty():
		return false
	_active = "surface"
	_surface_mode = true
	_primary_id = primary_id if ids.has(primary_id) else String(ids[0])
	_capture_start(ids)
	_exclude_ids.clear()
	for id in _start:
		for sub in world.get_subtree_data(id):
			_exclude_ids.append(String(sub["id"]))
	_pivot_start = world.get_global_transform_of(_primary_id).origin
	_screen_start = screen_pos
	var hit = _ray_plane(screen_pos, Plane(Vector3.UP, _pivot_start.y))
	_plane_hit0 = hit if hit != null else _pivot_start
	drag_started.emit()
	return true


func _ray_plane(screen_pos: Vector2, plane: Plane) -> Variant:
	var r := camera.ray(screen_pos)
	var hit = plane.intersects_ray(r[0], r[1])
	if hit != null and (hit as Vector3).distance_to(r[0]) > camera.far * 0.5:
		return null
	return hit


## Parâmetro t do ponto do eixo mais próximo do raio da tela.
func _axis_param(screen_pos: Vector2) -> float:
	var r := camera.ray(screen_pos)
	var ro: Vector3 = r[0]
	var rd: Vector3 = r[1]
	var w0 := _pivot_start - ro
	var a := _axis.dot(_axis)
	var b := _axis.dot(rd)
	var c := rd.dot(rd)
	var d := _axis.dot(w0)
	var e := rd.dot(w0)
	var denom := a * c - b * b
	if absf(denom) < 0.00001:
		return _t0
	return (b * e - c * d) / denom


func _screen_angle(screen_pos: Vector2) -> float:
	var c := camera.unproject_position(_pivot_start)
	return (screen_pos - c).angle()


func _snapf(v: float, s: float) -> float:
	return snappedf(v, s) if snap and s > 0.0 else v


func update_drag(screen_pos: Vector2) -> void:
	if _active == "":
		return
	if _surface_mode:
		_drag_surface(screen_pos)
	elif _active == "mc":
		var hit = _ray_plane(screen_pos, Plane(Vector3.UP, _pivot_start.y))
		if hit != null:
			var delta: Vector3 = hit - _plane_hit0
			delta = Vector3(_snapf(delta.x, snap_move), 0.0, _snapf(delta.z, snap_move))
			_apply_translation(delta)
	elif _active[0] == "m":
		var t := _axis_param(screen_pos)
		var delta_t := clampf(t - _t0, -5000.0, 5000.0)
		_apply_translation(_axis * _snapf(delta_t, snap_move))
	elif _active[0] == "r":
		var ang := _screen_angle(screen_pos)
		_angle_acc += wrapf(ang - _prev_angle, -PI, PI)
		_prev_angle = ang
		var toward := _axis.dot(camera.global_position - _pivot_start) > 0.0
		var angle := -_angle_acc if toward else _angle_acc
		angle = deg_to_rad(_snapf(rad_to_deg(angle), snap_rotate))
		_apply_rotation(_axis, angle)
	elif _active == "sc":
		var dv := screen_pos - _screen_start
		var factor := maxf(0.02, 1.0 + (dv.x - dv.y) * 0.006)
		_apply_uniform_scale(factor)
	elif _active[0] == "s":
		var t := _axis_param(screen_pos)
		var factor := t / _t0 if absf(_t0) > 0.0001 else 1.0
		_apply_axis_scale(_active[1], factor)
	drag_updated.emit()


func _apply_translation(delta: Vector3) -> void:
	for id in _start:
		if _start[id].get("child_of_group", false):
			continue
		var g: Transform3D = _start[id]["global"]
		world.set_object_global_transform(id, Transform3D(g.basis, g.origin + delta))
	global_position = _pivot_start + delta


func _apply_rotation(axis: Vector3, angle: float) -> void:
	var rot := Basis(axis, angle)
	for id in _start:
		var g: Transform3D = _start[id]["global"]
		var new_origin := _pivot_start + rot * (g.origin - _pivot_start)
		world.set_object_global_transform(id, Transform3D(rot * g.basis, new_origin))
	global_transform = Transform3D(rot * _basis_start, _pivot_start)


func _size_snap_step(id: String) -> float:
	return 0.1 if world.get_obj(id).type == "model" else snap_scale


func _apply_axis_scale(letter: String, factor: float) -> void:
	var id: String = _start.keys()[0]
	var s: Vector3 = _start[id]["size"]
	var idx := {"x": 0, "y": 1, "z": 2}[letter] as int
	var v := s[idx] * factor
	var step := _size_snap_step(id)
	v = maxf(_snapf(v, step), step if snap else PSData.MIN_SIZE)
	s[idx] = v
	world.set_object_size(id, s)


func _apply_uniform_scale(factor: float) -> void:
	for id in _start:
		var info: Dictionary = _start[id]
		var obj := world.get_obj(id)
		if obj == null:
			continue
		var g: Transform3D = info["global"]
		if obj.data.has("size"):
			var s: Vector3 = info["size"] * factor
			var step := _size_snap_step(id)
			if snap:
				s = Vector3(maxf(snappedf(s.x, step), step), maxf(snappedf(s.y, step), step), maxf(snappedf(s.z, step), step))
			world.set_object_size(id, s.max(Vector3.ONE * PSData.MIN_SIZE))
		# Posições se afastam/aproximam do pivô (seleção múltipla e filhos de grupos).
		if _start.size() > 1:
			world.set_object_global_transform(id, Transform3D(g.basis, _pivot_start + (g.origin - _pivot_start) * factor))


func _drag_surface(screen_pos: Vector2) -> void:
	var r := camera.ray(screen_pos)
	var hit := world.raycast_surface(r[0], r[0] + r[1] * camera.far, _exclude_ids)
	var primary_start: Transform3D = _start[_primary_id]["global"]
	var target := Vector3.ZERO
	if not hit.is_empty() and (hit["normal"] as Vector3).y > 0.5:
		# Apoia a base do objeto na superfície atingida.
		var box := world.get_local_aabb(_primary_id)
		var bottom_offset := -_lowest_point(primary_start.basis, box)
		var p: Vector3 = hit["position"]
		target = Vector3(_snapf(p.x, snap_move), p.y + bottom_offset, _snapf(p.z, snap_move))
	else:
		var ph = _ray_plane(screen_pos, Plane(Vector3.UP, _pivot_start.y))
		if ph == null:
			return
		var d: Vector3 = ph - _plane_hit0
		target = primary_start.origin + Vector3(_snapf(d.x, snap_move), 0.0, _snapf(d.z, snap_move))
	_apply_translation(target - primary_start.origin)


## Menor Y (relativo à origem) da caixa local girada pela base.
func _lowest_point(b: Basis, box: AABB) -> float:
	var lowest := INF
	for i in 8:
		var corner := box.get_endpoint(i)
		lowest = minf(lowest, (b * corner).y)
	return lowest if lowest != INF else 0.0


func end_drag() -> void:
	if _active == "":
		return
	var label := "Mover"
	if _active[0] == "r":
		label = "Girar"
	elif _active[0] == "s":
		label = "Redimensionar"
	var after: Array = []
	for d in _before:
		after.append(world.get_object_data(String(d["id"])))
	var before := _before.duplicate(true)
	highlight("")
	_active = ""
	_surface_mode = false
	_start.clear()
	_before.clear()
	_update_placement()
	if before != after:
		drag_finished.emit(before, after, label)


func cancel_drag() -> void:
	if _active == "":
		return
	for d in _before:
		world.apply_object_data(d)
	highlight("")
	_active = ""
	_start.clear()
	_before.clear()
	_update_placement()
