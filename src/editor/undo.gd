class_name PSUndo
extends RefCounted
## Histórico de desfazer/refazer baseado em estados.
##
## Cada ação guarda o estado completo (dicionário) dos objetos afetados antes e
## depois, então desfazer/refazer é sempre exato, inclusive para hierarquia.

signal changed(action_name: String)

const MAX_STEPS := 120

var ur := UndoRedo.new()
var world: PSWorld


func _init(p_world: PSWorld) -> void:
	world = p_world
	ur.max_steps = MAX_STEPS


func clear() -> void:
	ur.clear_history()
	changed.emit("")


func can_undo() -> bool:
	return ur.has_undo()


func can_redo() -> bool:
	return ur.has_redo()


func undo_name() -> String:
	return ur.get_current_action_name() if ur.has_undo() else ""


func undo() -> String:
	if not ur.has_undo():
		return ""
	var n := ur.get_current_action_name()
	ur.undo()
	changed.emit(n)
	return n


func redo() -> String:
	if not ur.has_redo():
		return ""
	ur.redo()
	var n := ur.get_current_action_name()
	changed.emit(n)
	return n


## Alteração de objetos existentes (já aplicada).
func modify(label: String, before: Array, after: Array) -> void:
	if before == after or before.is_empty():
		return
	ur.create_action(label)
	ur.add_do_method(_apply_list.bind(after.duplicate(true)))
	ur.add_undo_method(_apply_list.bind(before.duplicate(true)))
	ur.commit_action(false)
	changed.emit(label)


## Criação de objetos. `datas` em profundidade (pais primeiro).
func add(label: String, datas: Array, execute := true) -> void:
	if datas.is_empty():
		return
	var copy := datas.duplicate(true)
	ur.create_action(label)
	ur.add_do_method(_add_list.bind(copy))
	ur.add_undo_method(_remove_list.bind(_root_ids(copy)))
	ur.commit_action(execute)
	changed.emit(label)


## Remoção de objetos. `datas` deve conter as subárvores, com "_index" nas raízes.
func remove(label: String, datas: Array, execute := true) -> void:
	if datas.is_empty():
		return
	var copy := datas.duplicate(true)
	ur.create_action(label)
	ur.add_do_method(_remove_list.bind(_root_ids(copy)))
	ur.add_undo_method(_add_list.bind(copy))
	ur.commit_action(execute)
	changed.emit(label)


## Ação genérica com funções próprias (terreno, ambiente, scripts...).
func custom(label: String, do_call: Callable, undo_call: Callable, execute := true) -> void:
	ur.create_action(label)
	ur.add_do_method(do_call)
	ur.add_undo_method(undo_call)
	ur.commit_action(execute)
	changed.emit(label)


func _root_ids(datas: Array) -> Array:
	var ids := {}
	for d in datas:
		ids[String(d["id"])] = true
	var roots: Array = []
	for d in datas:
		if not ids.has(String(d.get("parent", ""))):
			roots.append(String(d["id"]))
	return roots


func _apply_list(datas: Array) -> void:
	world.begin_batch()
	for d in datas:
		var clean: Dictionary = d.duplicate(true)
		var idx := int(clean.get("_index", -1))
		clean.erase("_index")
		world.apply_object_data(clean, idx)
	world.end_batch()


func _add_list(datas: Array) -> void:
	# Recria as subárvores em ordem crescente de posição para restaurar a ordem dos irmãos.
	var roots := _root_ids(datas)
	var by_root := {}
	var current := ""
	for d in datas:
		var id := String(d["id"])
		if roots.has(id):
			current = id
			by_root[current] = []
		if current != "":
			by_root[current].append(d)
	roots.sort_custom(func(a, b):
		var da: Dictionary = by_root[a][0]
		var db: Dictionary = by_root[b][0]
		return int(da.get("_index", -1)) < int(db.get("_index", -1)))
	world.begin_batch()
	for r in roots:
		for d in by_root[r]:
			var clean: Dictionary = d.duplicate(true)
			var idx := int(clean.get("_index", -1))
			clean.erase("_index")
			world.add_object(clean, idx)
	world.end_batch()


func _remove_list(ids: Array) -> void:
	world.begin_batch()
	for id in ids:
		world.remove_object(String(id))
	world.end_batch()
