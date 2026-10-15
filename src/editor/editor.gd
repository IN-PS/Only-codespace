class_name PSEditor
extends Control
## Tela do editor 3D.
##
## A vista 3D ocupa a tela inteira; barras e painéis ficam por cima e se
## reorganizam conforme a orientação:
##  - paisagem: painel lateral à direita, abas na barra inferior;
##  - retrato: painel inferior (folha) e uma fileira de abas acima da barra de ferramentas.

signal request_close
signal request_play

const PANEL_ORDER := ["hierarchy", "inspector", "terrain", "assets", "scripts", "world", "console"]

var pid := ""
var project := {}
var world: PSWorld
var assets: PSAssetLibrary
var camera: PSEditorCamera
var gizmo: PSGizmo
var grid: PSGrid
var selbox: PSSelectionBox
var brush_cursor: MeshInstance3D
var undo: PSUndo
var vp_input: PSViewportInput
var selection: Array = []
var tool := "move"
var multi := false
var dirty := false
var brush := {
	"active": false, "tool": "raise", "radius": 4.0, "strength": 0.5,
	"surface": "grass", "veg_kind": "tree", "density": 1.0,
}

var _autosave_dirty := false
var _autosave_timer: Timer
var _drag_kind := ""
var _stroke_before := {}
var _stroke_last := Vector3.INF
var _flatten_height := 0.0
var _scene3d: Node3D

# Interface
var top_bar: PanelContainer
var bottom_bar: PanelContainer
var tab_strip: PanelContainer
var tab_box: BoxContainer
var dock: PanelContainer
var dock_title: Label
var dock_body: MarginContainer
var dock_maximized := false
var title_label: Label
var status_label: Label
var undo_btn: Button
var redo_btn: Button
var tool_buttons := {}
var tab_buttons := {}
var multi_btn: Button
var tools_box: HBoxContainer
var panels := {}
var active_panel := ""
var dock_open := false
var _bottom_inner: HBoxContainer
var _portrait := false
var _keyboard_h := 0.0


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# --------------------------------------------------------------------------
# Abrir / fechar
# --------------------------------------------------------------------------

## Abre o projeto. Se `use_recovery`, carrega o salvamento automático.
func open_project(p_pid: String, use_recovery := false) -> Dictionary:
	pid = p_pid
	var res: Dictionary
	if use_recovery:
		res = PSProjectStore.load_recovery(pid)
	else:
		res = PSProjectStore.load_project(pid)
	if not res["ok"]:
		return res
	project = res["data"]
	_build_scene()
	_build_ui()
	assets.setup(pid, project.get("assets", []))
	world.load_project(project)
	camera.set_state(project.get("editor", {}).get("camera", {}))
	if not project.get("editor", {}).has("camera"):
		_frame_initial_view()
	undo.clear()
	set_dirty(use_recovery or res.get("used_backup", false))
	_on_world_changed()
	set_tool("move")
	_relayout()
	if use_recovery:
		App.log_info("Alterações recuperadas do salvamento automático.", "Projeto")
	if res.get("used_backup", false):
		App.log_warn("O arquivo principal estava danificado; foi aberta a cópia de segurança.", "Projeto")
	App.log_info("Projeto aberto: %s (%d objetos)." % [project["name"], world.count()], "Projeto")
	Engine.max_fps = int(App.get_setting("editor_fps", 30))
	return {"ok": true}


func _frame_initial_view() -> void:
	var spawn := ""
	for id in world.objects:
		if world.objects[id].type == "spawn":
			spawn = id
			break
	if spawn != "":
		camera.pivot = world.get_global_transform_of(spawn).origin
		camera.distance = 16.0
	camera.set_view("iso")


func _build_scene() -> void:
	_scene3d = Node3D.new()
	_scene3d.name = "Scene3D"
	add_child(_scene3d)
	assets = PSAssetLibrary.new()
	assets.name = "Assets"
	add_child(assets)
	world = PSWorld.new(PSWorld.Mode.EDIT)
	world.shadows_enabled = bool(App.get_setting("shadows", true))
	world.set_assets(assets)
	_scene3d.add_child(world)
	world.objects_changed.connect(_on_world_changed)
	world.object_updated.connect(_on_object_updated)
	camera = PSEditorCamera.new()
	camera.name = "EditorCamera"
	_scene3d.add_child(camera)
	camera.make_current()
	grid = PSGrid.new()
	grid.camera = camera
	grid.visible = bool(App.get_setting("show_grid", true))
	_scene3d.add_child(grid)
	selbox = PSSelectionBox.new()
	selbox.world = world
	_scene3d.add_child(selbox)
	gizmo = PSGizmo.new()
	gizmo.world = world
	gizmo.camera = camera
	_scene3d.add_child(gizmo)
	gizmo.drag_finished.connect(_on_gizmo_drag_finished)
	gizmo.drag_updated.connect(_on_gizmo_drag_updated)
	_apply_snap_settings()
	brush_cursor = MeshInstance3D.new()
	brush_cursor.mesh = ImmediateMesh.new()
	brush_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	brush_cursor.extra_cull_margin = 16384.0
	_scene3d.add_child(brush_cursor)
	undo = PSUndo.new(world)
	undo.changed.connect(_on_undo_changed)
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = maxf(10.0, float(App.get_setting("autosave_seconds", 45)))
	_autosave_timer.autostart = true
	_autosave_timer.timeout.connect(autosave_now)
	add_child(_autosave_timer)
	App.settings_changed.connect(_on_settings_changed)


func _on_settings_changed() -> void:
	var sh := bool(App.get_setting("shadows", true))
	if world and world.shadows_enabled != sh:
		world.set_shadows(sh)
	if _autosave_timer:
		_autosave_timer.wait_time = maxf(10.0, float(App.get_setting("autosave_seconds", 45)))
	_apply_snap_settings()


func close_project() -> void:
	autosave_now()
	assets.clear()
	request_close.emit()


func _exit_tree() -> void:
	Engine.max_fps = 0


func _process(_delta: float) -> void:
	if App.is_mobile() and dock_open:
		var kb := DisplayServer.virtual_keyboard_get_height() / maxf(App.ui_scale, 0.01)
		if not is_equal_approx(kb, _keyboard_h):
			_relayout()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			autosave_now()
		NOTIFICATION_RESIZED:
			if is_inside_tree():
				_relayout()


# --------------------------------------------------------------------------
# Salvamento
# --------------------------------------------------------------------------

func set_dirty(on: bool) -> void:
	dirty = on
	if on:
		_autosave_dirty = true
	if title_label:
		title_label.text = ("● " if dirty else "") + String(project.get("name", ""))


func mark_changed() -> void:
	set_dirty(true)


func build_project_data() -> Dictionary:
	var data := project.duplicate(true)
	world.write_into(data)
	data["assets"] = assets.to_array()
	var ed: Dictionary = data.get("editor", {})
	ed["camera"] = camera.get_state()
	data["editor"] = ed
	return data


func save_project(make_version := true, label := "") -> bool:
	var data := build_project_data()
	var err := PSProjectStore.save_project(pid, data)
	if err != OK:
		App.log_error("Falha ao salvar: %s" % error_string(err), "Projeto")
		PSUI.toast("Erro ao salvar: %s" % error_string(err), "error", 4.0)
		return false
	project = data
	if make_version:
		PSProjectStore.save_version(pid, data, label)
	set_dirty(false)
	_autosave_dirty = false
	App.log_info("Projeto salvo.", "Projeto")
	PSUI.toast("Projeto salvo", "ok", 1.5)
	return true


func autosave_now() -> void:
	if pid == "" or not _autosave_dirty or world == null:
		return
	var err := PSProjectStore.autosave(pid, build_project_data())
	if err == OK:
		_autosave_dirty = false
	else:
		App.log_error("Falha no salvamento automático: %s" % error_string(err), "Projeto")


# --------------------------------------------------------------------------
# Interface
# --------------------------------------------------------------------------

func _build_ui() -> void:
	vp_input = PSViewportInput.new()
	vp_input.name = "ViewportInput"
	add_child(vp_input)
	vp_input.pointer_down.connect(_on_pointer_down)
	vp_input.pointer_move.connect(_on_pointer_move)
	vp_input.pointer_up.connect(_on_pointer_up)
	vp_input.pointer_cancel.connect(_on_pointer_cancel)
	vp_input.double_tap.connect(_on_double_tap)
	vp_input.long_press.connect(_on_long_press)
	vp_input.two_finger.connect(_on_two_finger)
	vp_input.mouse_orbit.connect(func(rel): camera.orbit(rel.x, rel.y))
	vp_input.mouse_pan.connect(func(rel): camera.pan(rel.x, rel.y))
	vp_input.wheel_zoom.connect(_on_wheel_zoom)
	vp_input.hover.connect(_on_hover)

	# Barra superior
	top_bar = PanelContainer.new()
	top_bar.add_theme_stylebox_override("panel", PSTheme.box(Color(PSTheme.PANEL, 0.94), 0, Color.TRANSPARENT, 0, 6, 4))
	add_child(top_bar)
	var top := PSUI.hbox(4)
	top_bar.add_child(top)
	var menu_btn := PSUI.icon_button("menu", "Menu")
	menu_btn.pressed.connect(_show_menu)
	top.add_child(menu_btn)
	title_label = PSUI.label(String(project.get("name", "")))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.clip_text = true
	top.add_child(title_label)
	var save_btn := PSUI.icon_button("save", "Salvar")
	save_btn.pressed.connect(func(): save_project())
	top.add_child(save_btn)
	undo_btn = PSUI.icon_button("undo", "Desfazer")
	undo_btn.pressed.connect(do_undo)
	top.add_child(undo_btn)
	redo_btn = PSUI.icon_button("redo", "Refazer")
	redo_btn.pressed.connect(do_redo)
	top.add_child(redo_btn)
	var play_btn := PSUI.button("Testar", "play", "Testar o jogo", "AccentButton")
	play_btn.pressed.connect(start_play)
	top.add_child(play_btn)

	# Barra de status (dica/seleção)
	status_label = PSUI.label("", "DimLabel")
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.clip_text = true
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	status_label.add_theme_constant_override("shadow_offset_x", 1)
	status_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(status_label)

	# Barra inferior (ferramentas)
	bottom_bar = PanelContainer.new()
	bottom_bar.add_theme_stylebox_override("panel", PSTheme.box(Color(PSTheme.PANEL, 0.94), 0, Color.TRANSPARENT, 0, 4, 4))
	add_child(bottom_bar)
	_bottom_inner = PSUI.hbox(2)
	bottom_bar.add_child(_bottom_inner)
	var tools_scroll := ScrollContainer.new()
	tools_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tools_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	tools_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools_scroll.custom_minimum_size.y = PSTheme.TOUCH
	_bottom_inner.add_child(tools_scroll)
	tools_box = PSUI.hbox(2)
	tools_scroll.add_child(tools_box)
	var tool_defs := [["select", "select", "Selecionar"], ["move", "move", "Mover"], ["rotate", "rotate", "Girar"], ["scale", "scale", "Redimensionar"]]
	for t in tool_defs:
		var b := PSUI.toggle(_tool_button(t[1], t[2]))
		var tool_name: String = t[0]
		b.pressed.connect(func(): set_tool(tool_name))
		tools_box.add_child(b)
		tool_buttons[tool_name] = b
	var add_btn := _tool_button("plus", "Adicionar objeto")
	add_btn.theme_type_variation = "AccentButton"
	add_btn.pressed.connect(show_add_menu)
	tools_box.add_child(add_btn)
	var dup_btn := _tool_button("copy", "Duplicar")
	dup_btn.pressed.connect(duplicate_selection)
	tools_box.add_child(dup_btn)
	var del_btn := _tool_button("trash", "Excluir")
	del_btn.pressed.connect(delete_selection)
	tools_box.add_child(del_btn)
	multi_btn = PSUI.toggle(_tool_button("multi", "Seleção múltipla"))
	multi_btn.toggled.connect(func(on): multi = on; _update_status())
	tools_box.add_child(multi_btn)
	var view_btn := _tool_button("camera", "Vista, foco e encaixe na grade")
	view_btn.pressed.connect(_show_view_menu)
	tools_box.add_child(view_btn)

	# Abas dos painéis
	tab_strip = PanelContainer.new()
	tab_strip.add_theme_stylebox_override("panel", PSTheme.box(Color(PSTheme.PANEL, 0.94), 0, Color.TRANSPARENT, 0, 4, 2))
	add_child(tab_strip)
	tab_box = HBoxContainer.new()
	tab_box.add_theme_constant_override("separation", 2)
	tab_box.alignment = BoxContainer.ALIGNMENT_CENTER

	# Painel (dock)
	dock = PanelContainer.new()
	dock.add_theme_stylebox_override("panel", PSTheme.box(Color(PSTheme.PANEL, 0.97), 12, PSTheme.BORDER, 1, 10, 8))
	dock.visible = false
	dock.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dock)
	var dv := PSUI.vbox(6)
	dock.add_child(dv)
	var dh := PSUI.hbox(4)
	dv.add_child(dh)
	dock_title = PSUI.label("", "TitleLabel")
	dock_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dh.add_child(dock_title)
	var max_btn := PSUI.icon_button("panel", "Ampliar painel", true, 38)
	max_btn.pressed.connect(func(): dock_maximized = not dock_maximized; _relayout())
	dh.add_child(max_btn)
	var close_btn := PSUI.icon_button("close", "Fechar painel", true, 38)
	close_btn.pressed.connect(func(): set_dock_open(false))
	dh.add_child(close_btn)
	dock_body = MarginContainer.new()
	dock_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dv.add_child(dock_body)

	_create_panels()
	_update_undo_buttons()
	_update_status()
	get_viewport().size_changed.connect(_relayout)


func _tool_button(icon: String, tip: String) -> Button:
	var b := PSUI.icon_button(icon, tip, true, PSTheme.TOUCH)
	b.custom_minimum_size = Vector2(40, PSTheme.TOUCH)
	return b


func _vsep() -> Control:
	var c := ColorRect.new()
	c.color = PSTheme.BORDER
	c.custom_minimum_size = Vector2(1, 28)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _create_panels() -> void:
	var defs := {
		"hierarchy": [PSHierarchyPanel, "Hierarquia", "hierarchy"],
		"inspector": [PSInspectorPanel, "Propriedades", "sliders"],
		"terrain": [PSTerrainPanel, "Terreno", "mountain"],
		"assets": [PSAssetsPanel, "Assets", "cube"],
		"scripts": [PSScriptsPanel, "Scripts", "code"],
		"world": [PSWorldPanel, "Mundo", "sun"],
		"console": [PSConsolePanel, "Console", "terminal"],
	}
	for key in PANEL_ORDER:
		var def: Array = defs[key]
		var p: PSPanel = (def[0] as GDScript).new()
		p.panel_title = def[1]
		p.panel_icon = def[2]
		p.name = key
		p.setup(self)
		p.visible = false
		dock_body.add_child(p)
		panels[key] = p
		var b := PSUI.toggle(PSUI.icon_button(def[2], def[1]))
		var k: String = key
		b.pressed.connect(func(): _on_tab_pressed(k))
		tab_buttons[key] = b
		tab_box.add_child(b)


func _on_tab_pressed(key: String) -> void:
	if dock_open and active_panel == key:
		set_dock_open(false)
	else:
		show_panel(key)


func show_panel(key: String) -> void:
	if not panels.has(key):
		return
	if active_panel != "" and active_panel != key and panels.has(active_panel):
		panels[active_panel].visible = false
		panels[active_panel].on_hidden()
	active_panel = key
	var p: PSPanel = panels[key]
	p.visible = true
	dock_title.text = p.panel_title
	dock_maximized = p.prefers_maximized
	set_dock_open(true)
	p.on_shown()


func set_dock_open(on: bool) -> void:
	dock_open = on
	dock.visible = on
	for k in tab_buttons:
		tab_buttons[k].set_pressed_no_signal(on and k == active_panel)
	if not on and active_panel != "" and panels.has(active_panel):
		panels[active_panel].on_hidden()
		if active_panel == "terrain":
			set_brush_active(false)
	_relayout()


## Recalcula posições conforme tamanho e orientação da tela.
func _relayout() -> void:
	if top_bar == null:
		return
	var s := App.get_ui_size()
	var safe := _safe_margins()
	_portrait = s.y > s.x
	var top_h := 52.0
	var bar_h := 54.0
	top_bar.position = Vector2(0, 0)
	top_bar.size = Vector2(s.x, top_h + safe.position.y)
	(top_bar.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_top = 4 + safe.position.y
	(top_bar.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left = 6 + safe.position.x
	(top_bar.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = 6 + safe.size.x
	var bottom_pad := safe.size.y
	# Abas: em paisagem ficam na barra inferior; em retrato, numa fileira própria.
	if tab_box.get_parent():
		tab_box.get_parent().remove_child(tab_box)
	var bottom_total := bar_h + bottom_pad
	if _portrait:
		tab_strip.visible = true
		tab_strip.add_child(tab_box)
		bottom_bar.position = Vector2(0, s.y - bottom_total)
		bottom_bar.size = Vector2(s.x, bottom_total)
		tab_strip.position = Vector2(0, s.y - bottom_total - 48)
		tab_strip.size = Vector2(s.x, 48)
	else:
		tab_strip.visible = false
		_bottom_inner.add_child(tab_box)
		bottom_bar.position = Vector2(0, s.y - bottom_total)
		bottom_bar.size = Vector2(s.x, bottom_total)
	(bottom_bar.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_bottom = 4 + bottom_pad
	(bottom_bar.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left = 4 + safe.position.x
	(bottom_bar.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = 4 + safe.size.x
	var content_top := top_bar.size.y
	var content_bottom := bottom_bar.position.y - (48.0 if _portrait else 0.0)
	# Teclado virtual aberto: o painel sobe para não ficar escondido atrás dele.
	_keyboard_h = DisplayServer.virtual_keyboard_get_height() / maxf(App.ui_scale, 0.01) if App.is_mobile() else 0.0
	if _keyboard_h > 0.0 and dock_open:
		content_bottom = minf(content_bottom, s.y - _keyboard_h - 4.0)
	if _portrait:
		var h := (content_bottom - content_top) * (0.92 if dock_maximized else 0.5)
		dock.position = Vector2(6 + safe.position.x, content_bottom - h - 4)
		dock.size = Vector2(s.x - 12 - safe.position.x - safe.size.x, h)
		status_label.position = Vector2(12 + safe.position.x, (dock.position.y if dock_open else content_bottom) - 26)
	else:
		var w := clampf(s.x * (0.62 if dock_maximized else 0.4), 300.0, s.x - 120.0)
		dock.position = Vector2(s.x - w - 6 - safe.size.x, content_top + 6)
		dock.size = Vector2(w, content_bottom - content_top - 12)
		status_label.position = Vector2(12 + safe.position.x, content_bottom - 26)
	status_label.size = Vector2(s.x * 0.7, 22)


## Margens da área segura (entalhes, barra de gestos) em unidades de interface:
## position = (esquerda, topo), size = (direita, baixo).
func _safe_margins() -> Rect2:
	if not App.is_mobile():
		return Rect2()
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or screen.x <= 0:
		return Rect2()
	var k := 1.0 / maxf(App.ui_scale, 0.01)
	return Rect2(safe.position.x * k, safe.position.y * k, (screen.x - safe.end.x) * k, (screen.y - safe.end.y) * k)


func _update_undo_buttons() -> void:
	if undo_btn == null:
		return
	undo_btn.disabled = not undo.can_undo()
	redo_btn.disabled = not undo.can_redo()
	undo_btn.tooltip_text = "Desfazer " + undo.undo_name() if undo.can_undo() else "Desfazer"


func _update_status() -> void:
	if status_label == null:
		return
	var t := ""
	if brush.get("active", false):
		t = "Pincel de terreno ativo: arraste sobre o terreno. Dois dedos movem a câmera."
	elif selection.size() == 1 and world.has_object(selection[0]):
		var obj := world.get_obj(selection[0])
		t = "%s (%s)" % [obj.data.get("name", ""), PSData.TYPE_LABELS.get(obj.type, obj.type)]
		if obj.data.get("locked", false):
			t += " · travado"
	elif selection.size() > 1:
		t = "%d objetos selecionados" % selection.size()
	else:
		t = "Toque para selecionar · arraste para girar a câmera · dois dedos: mover/zoom"
	if multi:
		t = "[Seleção múltipla] " + t
	status_label.text = t


# --------------------------------------------------------------------------
# Ferramentas e seleção
# --------------------------------------------------------------------------

func set_tool(t: String) -> void:
	tool = t
	for k in tool_buttons:
		tool_buttons[k].set_pressed_no_signal(k == t)
	gizmo.set_mode(t)
	if brush.get("active", false) and t != "select":
		set_brush_active(false)


func _apply_snap_settings() -> void:
	gizmo.snap = bool(App.get_setting("snap_enabled", true))
	gizmo.snap_move = float(App.get_setting("snap_move", 0.5))
	gizmo.snap_rotate = float(App.get_setting("snap_rotate", 15.0))
	gizmo.snap_scale = float(App.get_setting("snap_scale", 0.25))


func set_selection(ids: Array) -> void:
	var clean: Array = []
	for id in ids:
		if world.has_object(id) and not clean.has(id):
			clean.append(id)
	selection = clean
	selbox.ids = selection
	gizmo.set_selection(selection)
	_update_status()
	for p in panels.values():
		p.on_selection_changed()


func clear_selection() -> void:
	set_selection([])


func toggle_in_selection(id: String) -> void:
	var s := selection.duplicate()
	if s.has(id):
		s.erase(id)
	else:
		s.append(id)
	set_selection(s)


## Objeto sob o ponto da tela.
func pick_at(screen_pos: Vector2, include_locked := false) -> String:
	var r := camera.ray(screen_pos)
	return world.pick(r[0], r[0] + r[1] * camera.far, include_locked)


## Toque em um objeto dentro de grupos: o primeiro toque seleciona o grupo
## mais externo; toques seguintes descem na hierarquia.
func _resolve_tap_target(id: String) -> String:
	var chain: Array = []
	for anc in world.get_ancestors(id):
		if world.get_obj(anc).type == "group":
			chain.push_front(anc)
	chain.append(id)
	for i in range(chain.size() - 1, -1, -1):
		if selection.has(chain[i]):
			return chain[mini(i + 1, chain.size() - 1)]
	return chain[0]


func select_at(screen_pos: Vector2) -> void:
	var id := pick_at(screen_pos)
	if id == "":
		if not multi:
			clear_selection()
		return
	var target := _resolve_tap_target(id)
	if multi:
		toggle_in_selection(target)
	else:
		set_selection([target])


func focus_selection() -> void:
	if selection.is_empty():
		camera.focus_on(AABB(Vector3(-5, 0, -5), Vector3(10, 2, 10)))
		return
	var box := world.get_world_aabb(selection[0])
	for id in selection:
		box = box.merge(world.get_world_aabb(id))
	camera.focus_on(box)


# --------------------------------------------------------------------------
# Gestos na vista 3D
# --------------------------------------------------------------------------

func _on_pointer_down(pos: Vector2) -> void:
	_drag_kind = ""
	if brush.get("active", false) and world.terrain:
		var hit := _terrain_hit(pos)
		if not hit.is_empty():
			_begin_stroke(hit)
			return
	var h := gizmo.hit_test(pos)
	if h != "":
		if gizmo.begin_drag(h, pos):
			_drag_kind = "gizmo"
		return
	if tool == "move" and not selection.is_empty():
		var id := pick_at(pos)
		if id != "" and (selection.has(id) or _has_selected_ancestor(id)):
			var primary := id
			if not selection.has(id):
				for anc in world.get_ancestors(id):
					if selection.has(anc):
						primary = anc
						break
			if gizmo.begin_surface_drag(primary, pos):
				_drag_kind = "surface"


func _has_selected_ancestor(id: String) -> bool:
	for anc in world.get_ancestors(id):
		if selection.has(anc):
			return true
	return false


func _on_pointer_move(pos: Vector2, rel: Vector2) -> void:
	match _drag_kind:
		"gizmo", "surface":
			gizmo.update_drag(pos)
		"brush":
			var hit := _terrain_hit(pos)
			if not hit.is_empty():
				_continue_stroke(hit)
		_:
			_drag_kind = "orbit"
			camera.orbit(rel.x, rel.y)


func _on_pointer_up(pos: Vector2, was_tap: bool) -> void:
	match _drag_kind:
		"gizmo", "surface":
			gizmo.end_drag()
			if was_tap and _drag_kind == "surface":
				select_at(pos)
		"brush":
			_end_stroke()
		_:
			if was_tap:
				select_at(pos)
	_drag_kind = ""


func _on_pointer_cancel() -> void:
	match _drag_kind:
		"gizmo", "surface":
			gizmo.end_drag()
		"brush":
			_end_stroke()
	_drag_kind = ""


func _on_double_tap(pos: Vector2) -> void:
	var id := pick_at(pos, true)
	if id != "":
		var box := world.get_world_aabb(id)
		camera.focus_on(box)
	else:
		focus_selection()


func _on_long_press(pos: Vector2) -> void:
	if _drag_kind != "":
		return
	var id := pick_at(pos, true)
	if id == "":
		return
	var target := _resolve_tap_target(id)
	if not selection.has(target):
		set_selection([target])
	var obj := world.get_obj(target)
	var actions := ["Duplicar", "Excluir", "Focar", "Propriedades", "Travar" if not obj.data.get("locked", false) else "Destravar"]
	var parent := world.get_parent_id(target)
	if parent != "":
		actions.append("Selecionar grupo pai")
	PSModal.pick_list(String(obj.data.get("name", "Objeto")), actions, func(i): _on_context_action(String(actions[i]), target, parent))


func _on_context_action(action: String, target: String, parent: String) -> void:
	match action:
		"Duplicar":
			duplicate_selection()
		"Excluir":
			delete_selection()
		"Focar":
			focus_selection()
		"Propriedades":
			show_panel("inspector")
		"Travar", "Destravar":
			toggle_flag([target], "locked", false, "Travar")
		"Selecionar grupo pai":
			set_selection([parent])


func _on_two_finger(_center: Vector2, pan: Vector2, zoom_factor: float) -> void:
	if _drag_kind in ["gizmo", "surface"]:
		gizmo.cancel_drag()
	elif _drag_kind == "brush":
		_end_stroke()
	_drag_kind = "camera"
	camera.pan(pan.x, pan.y)
	if not is_equal_approx(zoom_factor, 1.0):
		camera.zoom(clampf(zoom_factor, 0.8, 1.25))


func _on_wheel_zoom(factor: float, pos: Vector2) -> void:
	var r := camera.ray(pos)
	var hit := world.raycast_surface(r[0], r[0] + r[1] * camera.far)
	camera.zoom_at(factor, hit.get("position") if not hit.is_empty() else null)


func _on_hover(pos: Vector2) -> void:
	if _drag_kind != "":
		return
	if brush.get("active", false) and world.terrain:
		var hit := _terrain_hit(pos)
		_draw_brush_cursor(hit)
		return
	gizmo.highlight(gizmo.hit_test(pos))


func _unhandled_key_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo or not is_visible_in_tree():
		return
	var k: InputEventKey = ev
	if k.ctrl_pressed or k.meta_pressed:
		match k.keycode:
			KEY_Z:
				if k.shift_pressed:
					do_redo()
				else:
					do_undo()
			KEY_Y:
				do_redo()
			KEY_S:
				save_project()
			KEY_D:
				duplicate_selection()
			KEY_G:
				if k.shift_pressed:
					ungroup_selection()
				else:
					group_selection()
			_:
				return
		get_viewport().set_input_as_handled()
		return
	if get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit:
		return
	match k.keycode:
		KEY_Q:
			set_tool("select")
		KEY_W:
			set_tool("move")
		KEY_E:
			set_tool("rotate")
		KEY_R:
			set_tool("scale")
		KEY_DELETE, KEY_BACKSPACE:
			delete_selection()
		KEY_F:
			focus_selection()
		KEY_ESCAPE:
			clear_selection()
		_:
			return
	get_viewport().set_input_as_handled()


## Botão "voltar" do Android: fecha o painel; se já estiver fechado, volta à lista.
func handle_back() -> void:
	if dock_open:
		set_dock_open(false)
	elif not selection.is_empty():
		clear_selection()
	else:
		_confirm_close()


func _confirm_close() -> void:
	if not dirty:
		close_project()
		return
	var on_save := func():
		if save_project():
			close_project()
	var on_discard := func():
		# Mantém o salvamento automático para recuperação posterior.
		_autosave_dirty = true
		autosave_now()
		request_close.emit()
	PSModal.choice3("Fechar projeto", "Há alterações não salvas. Deseja salvar antes de fechar?",
		"Salvar", on_save, "Não salvar", on_discard)


# --------------------------------------------------------------------------
# Undo / alterações de propriedades
# --------------------------------------------------------------------------

func do_undo() -> void:
	if gizmo.is_dragging():
		return
	var n := undo.undo()
	if n != "":
		PSUI.toast("Desfeito: " + n, "info", 1.0)


func do_redo() -> void:
	if gizmo.is_dragging():
		return
	var n := undo.redo()
	if n != "":
		PSUI.toast("Refeito: " + n, "info", 1.0)


func _on_undo_changed(_n: String) -> void:
	mark_changed()
	_update_undo_buttons()
	# Remove da seleção objetos que deixaram de existir.
	set_selection(selection)
	for p in panels.values():
		p.on_world_changed()


func _on_gizmo_drag_finished(before: Array, after: Array, label: String) -> void:
	undo.modify(label, before, after)
	for p in panels.values():
		p.on_selection_changed()


func _on_gizmo_drag_updated() -> void:
	if active_panel == "inspector" and dock_open:
		panels["inspector"].refresh_transform()


func _on_world_changed() -> void:
	for p in panels.values():
		p.on_world_changed()


func _on_object_updated(id: String) -> void:
	for p in panels.values():
		p.on_object_updated(id)


## Altera dados de objetos com desfazer. `mutate` recebe o dicionário completo do objeto.
func edit_objects(ids: Array, mutate: Callable, label: String) -> void:
	var before: Array = []
	var after: Array = []
	for id in ids:
		if not world.has_object(id):
			continue
		var d := world.get_object_data(id)
		before.append(d.duplicate(true))
		mutate.call(d)
		after.append(d)
	if before.is_empty() or before == after:
		return
	world.begin_batch()
	for d in after:
		world.apply_object_data(d)
	world.end_batch()
	undo.modify(label, before, after)
	gizmo.refresh()


## Inverte um campo booleano dos objetos (com desfazer).
func toggle_flag(ids: Array, key: String, default_value: bool, label: String) -> void:
	edit_objects(ids, func(d): d[key] = not bool(d.get(key, default_value)), label)


## Define um campo dos objetos (com desfazer).
func set_field(ids: Array, key: String, value: Variant, label: String) -> void:
	edit_objects(ids, func(d): d[key] = value, label)


var _preview_before := {}


## Pré-visualização ao vivo (sem desfazer) — use commit_preview ao soltar.
func preview_objects(ids: Array, mutate: Callable) -> void:
	for id in ids:
		if not world.has_object(id):
			continue
		if not _preview_before.has(id):
			_preview_before[id] = world.get_object_data(id)
		var d := world.get_object_data(id)
		mutate.call(d)
		world.apply_object_data(d)
	gizmo.refresh()


func commit_preview(label: String) -> void:
	if _preview_before.is_empty():
		return
	var before: Array = []
	var after: Array = []
	for id in _preview_before:
		if world.has_object(id):
			before.append(_preview_before[id])
			after.append(world.get_object_data(id))
	_preview_before.clear()
	undo.modify(label, before, after)


# --------------------------------------------------------------------------
# Ações de objetos
# --------------------------------------------------------------------------

## Ponto onde novos objetos aparecem: superfície no centro da tela ou chão à frente.
func _spawn_point() -> Vector3:
	var s := App.get_ui_size()
	var center := Vector2(s.x * 0.5, s.y * 0.45)
	var r := camera.ray(center)
	var hit := world.raycast_surface(r[0], r[0] + r[1] * 200.0)
	var p: Vector3
	if not hit.is_empty() and (hit["normal"] as Vector3).y > 0.5:
		p = hit["position"]
	else:
		var g = camera.ray_to_plane_y(center, 0.0)
		if g != null and (g as Vector3).distance_to(camera.global_position) < 80.0:
			p = g
		else:
			p = camera.pivot
	if gizmo.snap:
		p = Vector3(snappedf(p.x, gizmo.snap_move), p.y, snappedf(p.z, gizmo.snap_move))
	return p


## Adiciona objetos (lista de dicionários com ids) com desfazer e seleciona a raiz.
func add_objects(datas: Array, label := "Adicionar") -> void:
	if datas.is_empty():
		return
	if world.count() + datas.size() > PSData.MAX_OBJECTS:
		PSUI.toast("Limite de %d objetos atingido." % PSData.MAX_OBJECTS, "warn")
		return
	undo.add(label, datas)
	var roots: Array = []
	var ids := {}
	for d in datas:
		ids[d["id"]] = true
	for d in datas:
		if not ids.has(d.get("parent", "")):
			roots.append(d["id"])
	set_selection(roots)
	if tool == "select":
		set_tool("move")


func add_primitive(type: String, extra := {}) -> void:
	var d := PSData.new_object(type, extra)
	d["id"] = App.new_id("o")
	d["name"] = world.make_unique_name(String(d["name"]))
	var p := _spawn_point()
	var half_h := 0.0
	if d.has("size") and type in ["part", "model", "text"]:
		half_h = PSData.arr_to_v3(d["size"]).y * 0.5
	if type == "light":
		half_h = 2.0
	if type == "water":
		half_h = 0.0
	d["pos"] = PSData.v3_to_arr(p + Vector3(0, half_h, 0))
	add_objects([d], "Adicionar " + String(d["name"]))


func add_prefab(key: String) -> void:
	var datas := PSPrefabs.instantiate(key, _spawn_point())
	if datas.size() > 0:
		datas[0]["name"] = world.make_unique_name(String(datas[0]["name"]))
	add_objects(datas, "Adicionar " + PSPrefabs.display_name(key))


func add_model(asset_id: String) -> void:
	var e := assets.get_entry(asset_id)
	if e.is_empty():
		return
	var d := PSData.new_object("model", {"asset": asset_id, "name": world.make_unique_name(String(e["name"]))})
	d["id"] = App.new_id("o")
	var p := _spawn_point()
	if assets.is_model_ready(asset_id):
		p.y -= assets.get_model_aabb(asset_id).position.y
	d["pos"] = PSData.v3_to_arr(p)
	add_objects([d], "Adicionar modelo")


## Raízes da seleção (sem objetos cujo ancestral também está selecionado).
func selection_roots() -> Array:
	var out: Array = []
	for id in selection:
		var skip := false
		for anc in world.get_ancestors(id):
			if selection.has(anc):
				skip = true
				break
		if not skip:
			out.append(id)
	return out


func duplicate_selection() -> void:
	var roots := selection_roots()
	if roots.is_empty():
		PSUI.toast("Selecione algo para duplicar.", "info", 1.5)
		return
	var all: Array = []
	var new_roots: Array = []
	var offset := Vector3(gizmo.snap_move * 2.0 if gizmo.snap else 1.0, 0, 0)
	for r in roots:
		var map := {}
		var sub := world.get_subtree_data(r)
		for d in sub:
			map[d["id"]] = App.new_id("o")
		for d in sub:
			var c: Dictionary = d.duplicate(true)
			c["id"] = map[d["id"]]
			if map.has(c["parent"]):
				c["parent"] = map[c["parent"]]
			else:
				c["_index"] = world.get_index_in_parent(r) + 1
				var pos := PSData.arr_to_v3(c["pos"])
				# Desloca no espaço do pai para que a cópia não fique sobreposta.
				c["pos"] = PSData.v3_to_arr(pos + offset)
				c["name"] = world.make_unique_name(String(c["name"]))
				new_roots.append(c["id"])
			all.append(c)
	undo.add("Duplicar", all)
	set_selection(new_roots)


func delete_selection() -> void:
	var roots := selection_roots()
	if roots.is_empty():
		return
	var datas: Array = []
	for r in roots:
		var sub := world.get_subtree_data(r)
		if sub.is_empty():
			continue
		sub[0]["_index"] = world.get_index_in_parent(r)
		datas.append_array(sub)
	clear_selection()
	undo.remove("Excluir", datas)


func group_selection() -> void:
	var roots := selection_roots()
	if roots.is_empty():
		PSUI.toast("Selecione objetos para agrupar.", "info", 1.5)
		return
	var parent := world.get_parent_id(roots[0])
	for r in roots:
		if world.get_parent_id(r) != parent:
			parent = ""
			break
	var center := Vector3.ZERO
	for r in roots:
		center += world.get_global_transform_of(r).origin
	center /= roots.size()
	var group := PSData.new_object("group")
	group["id"] = App.new_id("o")
	group["name"] = world.make_unique_name("Grupo")
	group["parent"] = parent
	var local_center := center
	if parent != "":
		local_center = world.get_global_transform_of(parent).affine_inverse() * center
	group["pos"] = PSData.v3_to_arr(local_center)
	var group_index := world.get_index_in_parent(roots[0])
	var before: Array = []
	for r in roots:
		var d := world.get_object_data(r)
		d["_index"] = world.get_index_in_parent(r)
		before.append(d)
	before.sort_custom(func(a, b): return int(a["_index"]) < int(b["_index"]))
	var gid: String = group["id"]
	var do_call := func():
		world.begin_batch()
		world.add_object(group, group_index)
		for d in before:
			world.reparent_object(String(d["id"]), gid)
		world.end_batch()
	var undo_call := func():
		world.begin_batch()
		for d in before:
			world.apply_object_data(d, int(d["_index"]))
		world.remove_object(gid)
		world.end_batch()
	undo.custom("Agrupar", do_call, undo_call)
	set_selection([gid])


func ungroup_selection() -> void:
	var groups: Array = []
	for id in selection_roots():
		if world.get_obj(id).type == "group":
			groups.append(id)
	if groups.is_empty():
		PSUI.toast("Selecione um grupo para desagrupar.", "info", 1.5)
		return
	var records: Array = []
	var freed: Array = []
	for g in groups:
		var gd := world.get_object_data(g)
		gd["_index"] = world.get_index_in_parent(g)
		var kids: Array = []
		for c in world.get_children_ids(g):
			var cd := world.get_object_data(c)
			cd["_index"] = world.get_index_in_parent(c)
			kids.append(cd)
			freed.append(c)
		records.append({"group": gd, "children": kids})
	var do_call := func():
		world.begin_batch()
		for rec in records:
			var g: Dictionary = rec["group"]
			var idx := int(g["_index"])
			for cd in rec["children"]:
				world.reparent_object(String(cd["id"]), String(g["parent"]), idx)
				idx += 1
			world.remove_object(String(g["id"]))
		world.end_batch()
	var undo_call := func():
		world.begin_batch()
		for rec in records:
			var g: Dictionary = (rec["group"] as Dictionary).duplicate(true)
			var idx := int(g["_index"])
			g.erase("_index")
			world.add_object(g, idx)
			for cd in rec["children"]:
				world.apply_object_data(cd, int(cd["_index"]))
		world.end_batch()
	undo.custom("Desagrupar", do_call, undo_call)
	set_selection(freed)


## Move a seleção para outro pai (mantém a posição global).
func reparent_selection(new_parent: String) -> void:
	var roots := selection_roots()
	var before: Array = []
	var after: Array = []
	for r in roots:
		if r == new_parent or (new_parent != "" and world.is_descendant_of(new_parent, r)):
			continue
		var d := world.get_object_data(r)
		d["_index"] = world.get_index_in_parent(r)
		before.append(d)
	if before.is_empty():
		return
	world.begin_batch()
	for d in before:
		world.reparent_object(String(d["id"]), new_parent)
	world.end_batch()
	for d in before:
		var a := world.get_object_data(String(d["id"]))
		a["_index"] = world.get_index_in_parent(String(d["id"]))
		after.append(a)
	undo.modify("Definir pai", before, after)
	set_selection(selection)


## Muda a ordem entre irmãos (dir = -1 sobe, +1 desce).
func move_in_order(dir: int) -> void:
	if selection.size() != 1:
		return
	var id: String = selection[0]
	var idx := world.get_index_in_parent(id)
	var pid_ := world.get_parent_id(id)
	var siblings := world.get_children_ids(pid_) if pid_ != "" else world.get_root_ids()
	var new_idx := clampi(idx + dir, 0, siblings.size() - 1)
	if new_idx == idx:
		return
	var before := world.get_object_data(id)
	before["_index"] = idx
	var after := before.duplicate(true)
	after["_index"] = new_idx
	world.apply_object_data(after.duplicate(true), new_idx)
	undo.modify("Reordenar", [before], [after])


# --------------------------------------------------------------------------
# Pincel de terreno
# --------------------------------------------------------------------------

func set_brush_active(on: bool) -> void:
	brush["active"] = on and world.terrain != null
	if brush["active"]:
		if tool != "select":
			set_tool("select")
		clear_selection()
	(brush_cursor.mesh as ImmediateMesh).clear_surfaces()
	_update_status()
	if panels.has("terrain"):
		panels["terrain"].on_brush_state()


func _terrain_hit(screen_pos: Vector2) -> Dictionary:
	if world.terrain == null:
		return {}
	var r := camera.ray(screen_pos)
	return world.terrain.raycast(r[0], r[1], camera.far)


func _begin_stroke(hit: Dictionary) -> void:
	_drag_kind = "brush"
	_stroke_before = world.terrain.snapshot()
	_stroke_last = Vector3.INF
	_flatten_height = (hit["local"] as Vector3).y
	_continue_stroke(hit)


func _continue_stroke(hit: Dictionary) -> void:
	var lp: Vector3 = hit["local"]
	var radius := float(brush["radius"])
	_draw_brush_cursor(hit)
	if _stroke_last != Vector3.INF and lp.distance_to(_stroke_last) < radius * 0.25:
		return
	_stroke_last = lp
	var t := String(brush["tool"])
	var strength := float(brush["strength"])
	match t:
		"veg_add":
			world.terrain.apply_vegetation(String(brush["veg_kind"]), lp, radius, float(brush["density"]))
		"veg_remove":
			world.terrain.apply_vegetation(String(brush["veg_kind"]), lp, radius, 0.0, true)
		"paint":
			world.terrain.apply_brush("paint", lp, radius, strength, {"color": PSTerrain.SURFACES[brush["surface"]]["color"]})
		"flatten":
			world.terrain.apply_brush("flatten", lp, radius, strength, {"target": _flatten_height})
		_:
			world.terrain.apply_brush(t, lp, radius, strength)


func _end_stroke() -> void:
	if world.terrain == null or _stroke_before.is_empty():
		_drag_kind = ""
		return
	world.terrain.refresh_collision()
	var after := world.terrain.snapshot()
	var before := _stroke_before
	_stroke_before = {}
	var redo_call := func():
		if world.terrain:
			world.terrain.restore(after)
	var undo_call := func():
		if world.terrain:
			world.terrain.restore(before)
	undo.custom("Pincel de terreno", redo_call, undo_call, false)
	(brush_cursor.mesh as ImmediateMesh).clear_surfaces()


func _draw_brush_cursor(hit: Dictionary) -> void:
	var im := brush_cursor.mesh as ImmediateMesh
	im.clear_surfaces()
	if hit.is_empty() or world.terrain == null:
		return
	var lp: Vector3 = hit["local"]
	var r := float(brush["radius"])
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, PSPrimitives.marker_material(Color(1, 0.85, 0.3), true))
	for i in 49:
		var a := TAU * i / 48.0
		var x := lp.x + cos(a) * r
		var z := lp.z + sin(a) * r
		var h := world.terrain.height_at_local(clampf(x, -world.terrain.half(), world.terrain.half()), clampf(z, -world.terrain.half(), world.terrain.half()))
		im.surface_add_vertex(world.terrain.to_global(Vector3(x, h + 0.08, z)))
	im.surface_end()


# --------------------------------------------------------------------------
# Menus
# --------------------------------------------------------------------------

func show_add_menu() -> void:
	PSAddMenu.open(self)


func _show_view_menu() -> void:
	var snap_on := bool(App.get_setting("snap_enabled", true))
	var opts := [
		"Focar seleção",
		("Desligar" if snap_on else "Ligar") + " encaixe na grade (agora: %s)" % ("ligado" if snap_on else "desligado"),
		("Ocultar" if grid.visible else "Mostrar") + " grade",
		"Vista em perspectiva", "Vista de cima", "Vista de frente", "Vista lateral",
	]
	PSModal.pick_list("Vista e encaixe", opts, _on_view_pick)


func _on_view_pick(i: int) -> void:
	match i:
		0:
			focus_selection()
		1:
			set_snap(not bool(App.get_setting("snap_enabled", true)))
		2:
			grid.visible = not grid.visible
			App.set_setting("show_grid", grid.visible)
		3:
			camera.set_view("iso")
		4:
			camera.set_view("top")
		5:
			camera.set_view("front")
		6:
			camera.set_view("right")


func set_snap(on: bool) -> void:
	App.set_setting("snap_enabled", on)
	_apply_snap_settings()
	PSUI.toast("Encaixe na grade: " + ("ligado" if on else "desligado"), "info", 1.2)


func _show_menu() -> void:
	var opts := ["Salvar", "Salvar versão com nome…", "Versões salvas…", "Exportar backup (.zip)", "Configurações", "Sobre / ajuda", "Fechar projeto"]
	PSModal.pick_list("Menu", opts, _on_menu_pick)


func _on_menu_pick(i: int) -> void:
	match i:
		0:
			save_project()
		1:
			PSModal.prompt("Salvar versão", "Nome da versão:", "Versão", func(t): save_project(true, t))
		2:
			PSVersionsDialog.open(self)
		3:
			_export_backup()
		4:
			PSSettingsDialog.open()
		5:
			PSAboutDialog.open()
		6:
			_confirm_close()


func _export_backup() -> void:
	if dirty:
		save_project(false)
	var path := PSProjectStore.export_backup(pid)
	if path == "":
		PSUI.toast("Falha ao gerar o backup.", "error")
		return
	PSFileAccessHelper.offer_export(path, path.get_file())


## Restaura uma versão (substitui o mundo; pode ser desfeito salvando outra versão antes).
func restore_version(data: Dictionary) -> void:
	_autosave_dirty = true
	autosave_now()
	project["env"] = data.get("env", project.get("env"))
	project["game"] = data.get("game", project.get("game"))
	project["scripts"] = data.get("scripts", [])
	for a in data.get("assets", []):
		if assets.get_entry(a["id"]).is_empty() and FileAccess.file_exists(PSProjectStore.project_dir(pid).path_join(a["file"])):
			assets.entries[a["id"]] = a
			assets._order.append(a["id"])
	clear_selection()
	world.load_project(data)
	undo.clear()
	set_dirty(true)
	_on_world_changed()
	PSUI.toast("Versão restaurada (ainda não salva).", "ok")


# --------------------------------------------------------------------------
# Teste do jogo
# --------------------------------------------------------------------------

func start_play() -> void:
	if gizmo.is_dragging():
		gizmo.end_drag()
	request_play.emit()


## Chamado pela cena principal ao entrar/sair do modo de teste.
func set_editor_active(on: bool) -> void:
	visible = on
	_scene3d.visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if on:
		camera.make_current()
		Engine.max_fps = int(App.get_setting("editor_fps", 30))
		# Os corpos de seleção voltam a valer.
		world.process_mode = Node.PROCESS_MODE_INHERIT
	_set_pick_bodies_enabled(on)


func _set_pick_bodies_enabled(on: bool) -> void:
	for obj in world.objects.values():
		var pick: Node = obj.node.get_node_or_null("_pick")
		if pick is CollisionObject3D:
			(pick as CollisionObject3D).collision_layer = PSWorld.LAYER_PICK if on else 0
	if world.terrain and world.terrain._body:
		world.terrain._body.collision_layer = PSWorld.LAYER_TERRAIN if on else 0
