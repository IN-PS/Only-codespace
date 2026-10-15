extends PSTestCase
## Mundo, editor, desfazer/refazer, gizmo e gestos de toque (integração).

var pid := ""
var ed: PSEditor


func before_all() -> void:
	pid = temp_project("empty", "Editor teste")
	ed = PSEditor.new()
	runner.add_child(ed)
	var res := ed.open_project(pid)
	check(res["ok"], "editor abre projeto")
	await frames(3)
	await physics_frames(2)


func after_all() -> void:
	if ed:
		ed.queue_free()
	await frames(2)
	PSProjectStore.delete_project(pid)


func _add_part(shape := "box", pos := Vector3(0, 0.5, 0), size := Vector3.ONE) -> String:
	var d := PSData.new_object("part", {"shape": shape})
	d["id"] = App.new_id("o")
	d["pos"] = PSData.v3_to_arr(pos)
	d["size"] = PSData.v3_to_arr(size)
	ed.add_objects([d], "Adicionar")
	return d["id"]


func _touch(pos: Vector2, pressed: bool, index := 0) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	runner.get_viewport().push_input(ev)


func _drag(pos: Vector2, rel: Vector2, index := 0) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	ev.relative = rel
	runner.get_viewport().push_input(ev)


func _screen(p: Vector3) -> Vector2:
	return ed.camera.unproject_position(p)


func test_template_loaded() -> void:
	check(ed.world.count() >= 2, "modelo tem base e ponto de início")
	var types := ed.world.objects.values().map(func(o): return o.type)
	check(types.has("spawn"), "tem ponto de início")


func test_add_duplicate_delete_undo() -> void:
	var n0 := ed.world.count()
	var id := _add_part()
	eq(ed.world.count(), n0 + 1, "adicionou")
	eq(ed.selection, [id], "novo objeto selecionado")
	ed.duplicate_selection()
	eq(ed.world.count(), n0 + 2, "duplicou")
	var copy: String = ed.selection[0]
	check(copy != id, "cópia selecionada")
	var p1 := ed.world.get_global_transform_of(id).origin
	var p2 := ed.world.get_global_transform_of(copy).origin
	check(not p1.is_equal_approx(p2), "cópia deslocada")
	ed.delete_selection()
	eq(ed.world.count(), n0 + 1, "excluiu")
	ed.do_undo()
	eq(ed.world.count(), n0 + 2, "desfazer exclusão")
	check(ed.world.has_object(copy), "cópia voltou com o mesmo id")
	ed.do_undo()
	eq(ed.world.count(), n0 + 1, "desfazer duplicação")
	ed.do_redo()
	eq(ed.world.count(), n0 + 2, "refazer duplicação")
	ed.do_undo()
	ed.do_undo()
	eq(ed.world.count(), n0, "desfazer adição")


func test_group_ungroup_hierarchy() -> void:
	var a := _add_part("box", Vector3(2, 0.5, 0))
	var b := _add_part("sphere", Vector3(4, 0.5, 0))
	var a_global := ed.world.get_global_transform_of(a).origin
	ed.set_selection([a, b])
	ed.group_selection()
	var g: String = ed.selection[0]
	eq(ed.world.get_obj(g).type, "group", "grupo criado")
	eq(ed.world.get_parent_id(a), g, "a dentro do grupo")
	eq(ed.world.get_parent_id(b), g, "b dentro do grupo")
	eq(ed.world.get_global_transform_of(a).origin, a_global, "posição global mantida")
	# Mover o grupo leva os filhos.
	ed.world.set_object_global_transform(g, Transform3D(Basis.IDENTITY, ed.world.get_global_transform_of(g).origin + Vector3(0, 0, 3)))
	eq(ed.world.get_global_transform_of(a).origin, a_global + Vector3(0, 0, 3), "filho acompanha o grupo")
	ed.set_selection([g])
	ed.ungroup_selection()
	check(not ed.world.has_object(g), "grupo removido")
	eq(ed.world.get_parent_id(a), "", "a voltou para a raiz")
	eq(ed.world.get_global_transform_of(a).origin, a_global + Vector3(0, 0, 3), "posição global mantida ao desagrupar")
	ed.do_undo()
	check(ed.world.has_object(g), "desfazer desagrupar recria o grupo")
	eq(ed.world.get_parent_id(b), g, "b de volta ao grupo")
	ed.do_undo()
	check(not ed.world.has_object(g), "desfazer agrupar")
	eq(ed.world.get_parent_id(a), "", "a na raiz após desfazer")


func test_reparent_and_cycles() -> void:
	var a := _add_part("box", Vector3(-3, 0.5, 0))
	var b := _add_part("box", Vector3(-5, 0.5, 0))
	ed.set_selection([b])
	ed.reparent_selection(a)
	eq(ed.world.get_parent_id(b), a, "b filho de a")
	check(not ed.world.reparent_object(a, b), "não permite ciclo")
	ed.do_undo()
	eq(ed.world.get_parent_id(b), "", "desfazer definir pai")


func test_serialize_roundtrip() -> void:
	var a := _add_part("cylinder", Vector3(1, 2, 3), Vector3(2, 1, 2))
	ed.world.set_object_global_transform(a, Transform3D(Basis(Vector3.UP, 0.7), Vector3(1, 2, 3)))
	var data := ed.build_project_data()
	var json := JSON.stringify(data)
	var back := PSData.sanitize_project(JSON.parse_string(json))
	eq(back["objects"].size(), data["objects"].size(), "mesma quantidade de objetos")
	var w := PSWorld.new(PSWorld.Mode.EDIT)
	runner.add_child(w)
	w.load_project(back)
	eq(w.count(), ed.world.count(), "mundo reconstruído")
	var t1 := ed.world.get_global_transform_of(a)
	var t2 := w.get_global_transform_of(a)
	check(t1.origin.is_equal_approx(t2.origin) and t1.basis.is_equal_approx(t2.basis), "transformação preservada")
	w.queue_free()


func test_save_and_reopen() -> void:
	var a := _add_part("torus", Vector3(7, 1, 7))
	check(ed.save_project(), "salva")
	var res := PSProjectStore.load_project(pid)
	var found := false
	for o in res["data"]["objects"]:
		if o["id"] == a:
			found = true
			eq(o["shape"], "torus", "forma salva")
	check(found, "objeto salvo no arquivo")
	check(not ed.dirty, "sem alterações pendentes")


func test_tap_selects_object() -> void:
	ed.camera.pivot = Vector3(0, 0.5, 20)
	ed.camera.distance = 10
	ed.camera.set_view("iso")
	var id := _add_part("box", Vector3(0, 1, 20), Vector3(2, 2, 2))
	ed.clear_selection()
	await physics_frames(2)
	var sp := _screen(Vector3(0, 1, 20))
	_touch(sp, true)
	_touch(sp, false)
	await frames(1)
	eq(ed.selection, [id], "toque selecionou o objeto")
	# Toque no céu limpa a seleção.
	_touch(Vector2(20, 80), true)
	_touch(Vector2(20, 80), false)
	await frames(1)
	eq(ed.selection.size(), 0, "toque no vazio limpa a seleção")


func test_drag_orbits_camera_and_pinch_zooms() -> void:
	var yaw0 := ed.camera.yaw
	var start := Vector2(30, 90)
	_touch(start, true)
	for i in 10:
		_drag(start + Vector2(10 * (i + 1), 0), Vector2(10, 0))
	_touch(start + Vector2(100, 0), false)
	await frames(1)
	check(absf(ed.camera.yaw - yaw0) > 10.0, "arrastar com um dedo gira a câmera")
	var d0 := ed.camera.distance
	_touch(Vector2(300, 300), true, 0)
	_touch(Vector2(400, 300), true, 1)
	for i in 8:
		_drag(Vector2(300 - 10 * (i + 1), 300), Vector2(-10, 0), 0)
		_drag(Vector2(400 + 10 * (i + 1), 300), Vector2(10, 0), 1)
	_touch(Vector2(220, 300), false, 0)
	_touch(Vector2(480, 300), false, 1)
	await frames(1)
	check(ed.camera.distance < d0 * 0.8, "pinça aproxima a câmera (%.2f -> %.2f)" % [d0, ed.camera.distance])


func test_gizmo_drag_moves_along_axis_with_snap() -> void:
	ed.camera.pivot = Vector3(0, 0.5, -20)
	ed.camera.distance = 12
	ed.camera.set_view("iso")
	var id := _add_part("box", Vector3(0, 0.5, -20))
	ed.set_tool("move")
	ed.set_selection([id])
	await frames(2)
	var g := ed.gizmo
	check(g.visible, "gizmo visível")
	var o := g.global_position
	var tip := _screen(o + Vector3.RIGHT * g._gizmo_len * 0.75)
	eq(g.hit_test(tip), "mx", "toque na seta X acerta o eixo X")
	var dir := (_screen(o + Vector3.RIGHT * g._gizmo_len) - _screen(o)).normalized()
	_touch(tip, true)
	var pos := tip
	for i in 12:
		pos += dir * 15.0
		_drag(pos, dir * 15.0)
	_touch(pos, false)
	await frames(1)
	var p := ed.world.get_global_transform_of(id).origin
	check(p.x > 0.4, "objeto andou em X (%.2f)" % p.x)
	near(p.y, 0.5, 0.001, "Y não mudou")
	near(p.z, -20.0, 0.001, "Z não mudou")
	near(fmod(p.x, ed.gizmo.snap_move), 0.0, 0.001, "posição encaixada na grade")
	ed.do_undo()
	eq(ed.world.get_global_transform_of(id).origin, Vector3(0, 0.5, -20), "desfazer movimento")


func test_gizmo_rotate_and_scale() -> void:
	var id := _add_part("box", Vector3(10, 0.5, 10), Vector3(1, 1, 1))
	ed.set_selection([id])
	ed.camera.focus_on(ed.world.get_world_aabb(id))
	ed.set_tool("rotate")
	await frames(1)
	var g := ed.gizmo
	check(g.begin_drag("ry", _screen(g.global_position) + Vector2(80, 0)), "inicia rotação")
	var c := _screen(g.global_position)
	for i in 10:
		g.update_drag(c + Vector2(80, 0).rotated(-0.16 * (i + 1)))
	g.end_drag()
	var e := ed.world.get_obj(id).node.basis.get_euler()
	check(absf(rad_to_deg(e.y)) > 10.0, "girou em Y (%.1f°)" % rad_to_deg(e.y))
	near(fmod(absf(rad_to_deg(e.y)) + 0.001, 15.0), 0.0, 0.01, "rotação encaixada em 15°")
	ed.set_tool("scale")
	await frames(1)
	var o := g.global_position
	var axis := g.global_transform.basis.x.normalized()
	var start := _screen(o + axis * g._gizmo_len * 0.9)
	var dir := (_screen(o + axis * g._gizmo_len * 1.5) - start).normalized()
	check(g.begin_drag("sx", start), "inicia escala")
	g.update_drag(start + dir * 120.0)
	g.end_drag()
	var s := PSData.arr_to_v3(ed.world.get_obj(id).data["size"])
	check(s.x > 1.2, "tamanho X aumentou (%.2f)" % s.x)
	eq(s.y, 1.0, "Y igual")


func test_surface_drag_places_on_top() -> void:
	ed.camera.pivot = Vector3(30, 0.5, 30)
	ed.camera.distance = 14
	ed.camera.set_view("iso")
	var base := _add_part("box", Vector3(30, 1, 30), Vector3(6, 2, 6))
	var cube := _add_part("box", Vector3(36, 0.5, 34))
	ed.set_tool("move")
	ed.set_selection([cube])
	await physics_frames(2)
	var g := ed.gizmo
	check(g.begin_surface_drag(cube, _screen(Vector3(36, 0.5, 34))), "inicia arraste livre")
	g.update_drag(_screen(Vector3(30, 2, 30)))
	g.end_drag()
	var p := ed.world.get_global_transform_of(cube).origin
	near(p.y, 2.5, 0.05, "cubo apoiado sobre a base (y = topo + meia altura)")
	var _b := base


func test_inspector_number_field_commit() -> void:
	var id := _add_part("box", Vector3(0, 0.5, 40))
	ed.set_selection([id])
	ed.show_panel("inspector")
	await frames(2)
	var insp: PSInspectorPanel = ed.panels["inspector"]
	var fx: PSNumberField = insp._pos_fields[0]
	fx._edit.text = "2*3"
	fx._commit_text()
	near(ed.world.get_global_transform_of(id).origin.x, 6.0, 0.001, "campo aceita conta simples")
	ed.do_undo()
	near(ed.world.get_global_transform_of(id).origin.x, 0.0, 0.001, "desfazer edição numérica")
	ed.set_dock_open(false)


func test_all_panels_open() -> void:
	for k in PSEditor.PANEL_ORDER:
		ed.show_panel(k)
		await frames(1)
		check(ed.dock.visible and ed.active_panel == k, "painel %s abre" % k)
	ed.set_dock_open(false)
	check(not ed.dock.visible, "painel recolhe")


func test_add_prefabs_and_specials() -> void:
	var n0 := ed.world.count()
	for e in PSPrefabs.CATALOG:
		ed.add_prefab(e["key"])
	for t in ["light", "water", "text", "spawn", "group"]:
		ed.add_primitive(t)
	for s in PSData.SHAPES:
		ed.add_primitive("part", {"shape": s})
	check(ed.world.count() > n0 + PSPrefabs.CATALOG.size() + 5, "prefabs e especiais adicionados")
	# Todos serializam e voltam.
	var back := PSData.sanitize_project(JSON.parse_string(JSON.stringify(ed.build_project_data())))
	eq(back["objects"].size(), ed.world.count(), "tudo serializa")
