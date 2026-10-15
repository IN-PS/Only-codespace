class_name PSHierarchyPanel
extends PSPanel
## Árvore de objetos com busca, visibilidade, trava, agrupamento e ordem.

const TYPE_ICONS := {"group": "group", "model": "cube", "light": "light", "spawn": "flag", "water": "water", "text": "text"}
const BTN_VISIBLE := 1
const BTN_LOCK := 2

var tree: Tree
var search: LineEdit
var _items := {}          # id -> TreeItem
var _collapsed := {}
var _rebuild_pending := false
var _syncing := false


func _build() -> void:
	search = PSUI.line_edit("", "Buscar objeto…")
	search.right_icon = PSIcons.get_icon("search", 18.0, "#9aa1b2")
	search.text_changed.connect(func(_t): _queue_rebuild())
	add_child(search)

	tree = Tree.new()
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_MULTI
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.focus_mode = Control.FOCUS_NONE
	tree.allow_reselect = true
	tree.columns = 1
	tree.item_mouse_selected.connect(_on_item_clicked)
	tree.item_activated.connect(_on_item_activated)
	tree.button_clicked.connect(_on_button_clicked)
	tree.item_collapsed.connect(_on_item_collapsed)
	tree.empty_clicked.connect(_on_empty_clicked)
	add_child(tree)

	var row1 := PSUI.hbox(4)
	add_child(row1)
	var g := PSUI.button("Agrupar", "group", "Agrupar seleção (Ctrl+G)")
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.pressed.connect(func(): editor.group_selection())
	row1.add_child(g)
	var ug := PSUI.button("Desagrupar", "ungroup", "Desfazer grupo")
	ug.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ug.pressed.connect(func(): editor.ungroup_selection())
	row1.add_child(ug)

	var row2 := PSUI.hbox(4)
	add_child(row2)
	var par := PSUI.button("Definir pai", "parent", "Colocar a seleção dentro de outro objeto")
	par.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	par.pressed.connect(_choose_parent)
	row2.add_child(par)
	var up := PSUI.icon_button("up", "Subir na lista", false)
	up.pressed.connect(func(): editor.move_in_order(-1))
	row2.add_child(up)
	var down := PSUI.icon_button("down", "Descer na lista", false)
	down.pressed.connect(func(): editor.move_in_order(1))
	row2.add_child(down)
	var ren := PSUI.icon_button("text", "Renomear", false)
	ren.pressed.connect(_rename_selected)
	row2.add_child(ren)


func on_shown() -> void:
	_rebuild()


func on_world_changed() -> void:
	_queue_rebuild()


func on_object_updated(id: String) -> void:
	if _items.has(id) and is_visible_in_tree():
		_update_item(_items[id], id)


func on_selection_changed() -> void:
	_sync_selection()


func _queue_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	call_deferred("_rebuild")


func _rebuild() -> void:
	_rebuild_pending = false
	if not is_visible_in_tree():
		return
	tree.clear()
	_items.clear()
	var root := tree.create_item()
	var q := search.text.strip_edges().to_lower()
	for id in editor.world.get_root_ids():
		_add_rec(root, id, q)
	_sync_selection()


func _matches(id: String, q: String) -> bool:
	if q == "":
		return true
	if String(editor.world.get_obj(id).data.get("name", "")).to_lower().contains(q):
		return true
	for c in editor.world.get_children_ids(id):
		if _matches(c, q):
			return true
	return false


func _add_rec(parent: TreeItem, id: String, q: String) -> void:
	if not _matches(id, q):
		return
	var item := tree.create_item(parent)
	item.set_metadata(0, id)
	_items[id] = item
	_update_item(item, id)
	for c in editor.world.get_children_ids(id):
		_add_rec(item, c, q)
	item.collapsed = _collapsed.get(id, false) and q == ""


func _update_item(item: TreeItem, id: String) -> void:
	var obj := editor.world.get_obj(id)
	if obj == null:
		return
	item.set_text(0, String(obj.data.get("name", id)))
	var icon_name: String = TYPE_ICONS.get(obj.type, "")
	if obj.type == "part":
		icon_name = String(obj.data.get("shape", "box"))
	item.set_icon(0, PSIcons.get_icon(icon_name, 18.0, "#9aa1b2"))
	item.set_icon_max_width(0, 18)
	while item.get_button_count(0) > 0:
		item.erase_button(0, 0)
	var vis := bool(obj.data.get("visible", true))
	item.add_button(0, PSIcons.get_icon("eye" if vis else "eye_off", 18.0, "#9aa1b2" if vis else "#6b7283"), BTN_VISIBLE, false, "Visível")
	var locked := bool(obj.data.get("locked", false))
	item.add_button(0, PSIcons.get_icon("lock" if locked else "unlock", 18.0, "#e3b341" if locked else "#4a5060"), BTN_LOCK, false, "Travado")
	item.set_custom_color(0, PSTheme.TEXT if vis else PSTheme.TEXT_FAINT)


func _sync_selection() -> void:
	if tree == null or not is_visible_in_tree():
		return
	_syncing = true
	for id in _items:
		var item: TreeItem = _items[id]
		if editor.selection.has(id):
			item.select(0)
		else:
			item.deselect(0)
	_syncing = false
	if editor.selection.size() > 0 and _items.has(editor.selection[0]):
		var it: TreeItem = _items[editor.selection[0]]
		var p := it.get_parent()
		while p:
			p.collapsed = false
			p = p.get_parent()
		tree.scroll_to_item(it)


func _on_item_clicked(pos: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	var item := tree.get_item_at_position(pos)
	if item == null:
		return
	var id := String(item.get_metadata(0))
	if editor.multi:
		editor.toggle_in_selection(id)
	else:
		editor.set_selection([id])
	_sync_selection.call_deferred()


func _on_empty_clicked(_pos: Vector2, _button: int) -> void:
	if not editor.multi:
		editor.clear_selection()


func _on_item_activated() -> void:
	var item := tree.get_selected()
	if item:
		editor.set_selection([String(item.get_metadata(0))])
		editor.focus_selection()


func _on_button_clicked(item: TreeItem, _column: int, id: int, _button: int) -> void:
	var oid := String(item.get_metadata(0))
	match id:
		BTN_VISIBLE:
			editor.edit_objects([oid], func(d): d["visible"] = not d.get("visible", true), "Visibilidade")
		BTN_LOCK:
			editor.edit_objects([oid], func(d): d["locked"] = not d.get("locked", false), "Travar")
	_sync_selection.call_deferred()


func _on_item_collapsed(item: TreeItem) -> void:
	_collapsed[String(item.get_metadata(0))] = item.collapsed


func _choose_parent() -> void:
	var roots := editor.selection_roots()
	if roots.is_empty():
		PSUI.toast("Selecione o(s) objeto(s) que vão mudar de pai.", "info", 2.0)
		return
	var options: Array = ["(Nenhum — raiz do mundo)"]
	var ids: Array = [""]
	for id in editor.world.serialize_objects().map(func(d): return d["id"]):
		if roots.has(id):
			continue
		var invalid := false
		for r in roots:
			if editor.world.is_descendant_of(id, r):
				invalid = true
		if invalid:
			continue
		var depth := editor.world.get_ancestors(id).size()
		var obj := editor.world.get_obj(id)
		options.append("    ".repeat(depth) + String(obj.data.get("name", id)) + "  (" + PSData.TYPE_LABELS.get(obj.type, "") + ")")
		ids.append(id)
	PSModal.pick_list("Novo pai", options, func(i): editor.reparent_selection(ids[i]))


func _rename_selected() -> void:
	if editor.selection.size() != 1:
		PSUI.toast("Selecione um objeto para renomear.", "info", 1.5)
		return
	var id: String = editor.selection[0]
	var current := String(editor.world.get_obj(id).data.get("name", ""))
	PSModal.prompt("Renomear", "", current, func(t): editor.edit_objects([id], func(d): d["name"] = t, "Renomear"))
