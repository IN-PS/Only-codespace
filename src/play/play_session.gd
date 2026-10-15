class_name PSPlaySession
extends Control
## Modo de teste: monta uma cópia jogável do mundo, com física, jogador,
## controles por toque e execução dos scripts (em ambiente isolado).

signal finished

var data := {}
var assets: PSAssetLibrary
var pid := ""
var world: PSWorld
var player: PSPlayer
var runtime: PSScriptRuntime
var paused := false

var _scene3d: Node3D
var _hud: Control
var _look: Control
var _joystick: PSVirtualJoystick
var _jump_btn: Button
var _message: Label
var _hud_text: Label
var _error_btn: Button
var _cam_btn: Button
var _pause_layer: Control
var _look_touch := -1
var _look_start := Vector2.ZERO
var _look_moved := false
var _message_timer := 0.0
var _errors := 0
var _log_start := 0
var _default_gravity := 9.8


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func start(p_data: Dictionary, p_assets: PSAssetLibrary, p_pid: String) -> void:
	data = p_data
	assets = p_assets
	pid = p_pid
	_default_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_build_hud()
	_log_start = App.log_entries.size()
	App.log_added.connect(_on_log_added)
	Engine.max_fps = int(App.get_setting("play_fps", 60))
	_build_world()
	App.log_info("Teste iniciado.", "Jogo")


func _exit_tree() -> void:
	get_tree().paused = false
	if App.log_added.is_connected(_on_log_added):
		App.log_added.disconnect(_on_log_added)
	var space := get_viewport().world_3d.space if get_viewport() else RID()
	if space.is_valid():
		PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, _default_gravity)


# --------------------------------------------------------------------------
# Mundo
# --------------------------------------------------------------------------

func _build_world() -> void:
	if _scene3d:
		_scene3d.queue_free()
		_scene3d = null
		world = null
		player = null
	if runtime:
		runtime.stop()
		runtime = null
	# Garante que os modelos usados já estejam carregados (a física precisa das malhas).
	for o in data.get("objects", []):
		if o.get("type") == "model":
			assets.load_model_now(String(o.get("asset", "")))
	_scene3d = Node3D.new()
	_scene3d.name = "PlayScene"
	_scene3d.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_scene3d)
	move_child(_scene3d, 0)
	world = PSWorld.new(PSWorld.Mode.PLAY)
	world.shadows_enabled = bool(App.get_setting("shadows", true))
	world.set_assets(assets)
	_scene3d.add_child(world)
	world.load_project(data)
	var g := float(world.env_data.get("gravity", 9.8))
	PhysicsServer3D.area_set_param(get_viewport().world_3d.space, PhysicsServer3D.AREA_PARAM_GRAVITY, g)

	player = PSPlayer.new()
	player.setup(world.game_data, g)
	player.spawn_transform = _find_spawn()
	_scene3d.add_child(player)
	player.place_at_spawn()
	player.camera.make_current()
	_connect_water()
	_cam_btn.icon = PSIcons.get_icon("person" if player.camera_mode == "third" else "eye")

	runtime = PSScriptRuntime.new()
	runtime.name = "Scripts"
	runtime.process_mode = Node.PROCESS_MODE_PAUSABLE
	_scene3d.add_child(runtime)
	runtime.setup(self, world, player, data.get("scripts", []))
	runtime.start()

	var msg := String(world.game_data.get("start_message", ""))
	if msg != "":
		show_message(msg, 4.0)


func _find_spawn() -> Transform3D:
	for id in world.objects:
		if world.objects[id].type == "spawn":
			var t := world.get_global_transform_of(id)
			return Transform3D(t.basis, t.origin + Vector3(0, 0.15, 0))
	# Sem ponto de início: acima do centro do mundo (ou do terreno).
	var y := 2.0
	if world.terrain:
		var h := world.terrain.height_at_global(Vector3.ZERO)
		if h != -INF:
			y = h + 1.0
	return Transform3D(Basis.IDENTITY, Vector3(0, y, 3))


func _connect_water() -> void:
	for obj in world.objects.values():
		if obj.type != "water":
			continue
		var area: Area3D = obj.node.get_node_or_null("_water_area")
		if area:
			area.body_entered.connect(func(b): if b == player: player.in_water += 1)
			area.body_exited.connect(func(b): if b == player: player.in_water = maxi(0, player.in_water - 1))


func restart() -> void:
	set_paused(false)
	_joystick.reset()
	App.log_info("Teste reiniciado.", "Jogo")
	_build_world()


func set_paused(on: bool) -> void:
	paused = on
	get_tree().paused = on
	_pause_layer.visible = on


func stop() -> void:
	set_paused(false)
	if runtime:
		runtime.stop()
	App.log_info("Teste encerrado.", "Jogo")
	finished.emit()


func handle_back() -> void:
	if paused:
		stop()
	else:
		set_paused(true)


# --------------------------------------------------------------------------
# Interface
# --------------------------------------------------------------------------

func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)

	_look = Control.new()
	_look.mouse_filter = Control.MOUSE_FILTER_STOP
	_look.anchor_left = 0.42
	_look.anchor_right = 1.0
	_look.anchor_bottom = 1.0
	_look.gui_input.connect(_on_look_input)
	_hud.add_child(_look)

	_joystick = PSVirtualJoystick.new()
	_joystick.anchor_right = 0.42
	_joystick.anchor_top = 0.3
	_joystick.anchor_bottom = 1.0
	_joystick.moved.connect(func(v): if player: player.move_input = v)
	_hud.add_child(_joystick)

	_jump_btn = Button.new()
	_jump_btn.icon = PSIcons.get_icon("jump", 34.0)
	_jump_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_jump_btn.add_theme_constant_override("icon_max_width", 36)
	_jump_btn.focus_mode = Control.FOCUS_NONE
	_jump_btn.custom_minimum_size = Vector2(84, 84)
	for st in ["normal", "hover"]:
		_jump_btn.add_theme_stylebox_override(st, PSTheme.box(Color(1, 1, 1, 0.14), 42, Color(1, 1, 1, 0.35), 2))
	_jump_btn.add_theme_stylebox_override("pressed", PSTheme.box(Color(0.24, 0.49, 1.0, 0.5), 42, Color.WHITE, 2))
	_jump_btn.button_down.connect(func(): if player: player.jump_pressed = true)
	_jump_btn.anchor_left = 1.0
	_jump_btn.anchor_right = 1.0
	_jump_btn.anchor_top = 1.0
	_jump_btn.anchor_bottom = 1.0
	_jump_btn.offset_left = -112
	_jump_btn.offset_right = -28
	_jump_btn.offset_top = -124
	_jump_btn.offset_bottom = -40
	_hud.add_child(_jump_btn)

	var top := PSUI.hbox(6)
	top.anchor_right = 1.0
	top.offset_left = 10
	top.offset_right = -10
	top.offset_top = 8 + _safe_top()
	top.offset_bottom = 8 + _safe_top() + PSTheme.TOUCH
	_hud.add_child(top)
	var pause := _hud_button("pause", "Pausar")
	pause.pressed.connect(func(): set_paused(true))
	top.add_child(pause)
	var rs := _hud_button("restart", "Reiniciar")
	rs.pressed.connect(restart)
	top.add_child(rs)
	_cam_btn = _hud_button("person", "Alternar 1ª/3ª pessoa")
	_cam_btn.pressed.connect(func():
		if player:
			var m := player.toggle_camera_mode()
			_cam_btn.icon = PSIcons.get_icon("person" if m == "third" else "eye")
			show_message("Câmera: " + ("terceira pessoa" if m == "third" else "primeira pessoa"), 1.2))
	top.add_child(_cam_btn)
	_hud_text = PSUI.label("", "")
	_hud_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hud_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_text.add_theme_font_size_override("font_size", 18)
	_hud_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_hud_text.add_theme_constant_override("shadow_offset_y", 2)
	_hud_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_hud_text)
	_error_btn = PSUI.button("0", "error", "Erros do teste", "DangerButton")
	_error_btn.visible = false
	_error_btn.pressed.connect(_show_errors)
	top.add_child(_error_btn)
	var stop_btn := _hud_button("stop", "Parar teste")
	stop_btn.pressed.connect(stop)
	top.add_child(stop_btn)

	_message = PSUI.label("", "", true)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.anchor_left = 0.1
	_message.anchor_right = 0.9
	_message.anchor_top = 0.2
	_message.add_theme_font_size_override("font_size", 22)
	_message.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_message.add_theme_constant_override("shadow_offset_y", 2)
	_message.add_theme_constant_override("shadow_offset_x", 1)
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message.visible = false
	_hud.add_child(_message)

	_pause_layer = Control.new()
	_pause_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.visible = false
	_pause_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_pause_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(center)
	var box := PSUI.vbox(10)
	box.custom_minimum_size.x = 260
	center.add_child(box)
	var t := PSUI.label("Pausado", "TitleLabel")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var cont := PSUI.button("Continuar", "play", "", "AccentButton")
	cont.pressed.connect(func(): set_paused(false))
	box.add_child(cont)
	var rb := PSUI.button("Reiniciar", "restart")
	rb.pressed.connect(restart)
	box.add_child(rb)
	var eb := PSUI.button("Ver erros e mensagens", "terminal")
	eb.pressed.connect(_show_errors)
	box.add_child(eb)
	var sb := PSUI.button("Voltar ao editor", "back", "", "DangerButton")
	sb.pressed.connect(stop)
	box.add_child(sb)


func _hud_button(icon: String, tip: String) -> Button:
	var b := PSUI.icon_button(icon, tip, false)
	b.add_theme_stylebox_override("normal", PSTheme.box(Color(0, 0, 0, 0.4), 10, Color(1, 1, 1, 0.2), 1))
	return b


func _safe_top() -> float:
	if not App.is_mobile():
		return 0.0
	return DisplayServer.get_display_safe_area().position.y / maxf(App.ui_scale, 0.01)


func show_message(text: String, seconds := 3.0) -> void:
	_message.text = text
	_message.visible = text != ""
	_message_timer = seconds


func set_hud_text(text: String) -> void:
	_hud_text.text = text


func _process(delta: float) -> void:
	if _message_timer > 0.0 and not paused:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_message.visible = false


func _on_look_input(ev: InputEvent) -> void:
	if player == null:
		return
	if ev is InputEventScreenTouch:
		if ev.pressed and _look_touch == -1:
			_look_touch = ev.index
			_look_start = ev.position
			_look_moved = false
		elif not ev.pressed and ev.index == _look_touch:
			_look_touch = -1
			if not _look_moved:
				_click_at(ev.position + _look.global_position)
	elif ev is InputEventScreenDrag and ev.index == _look_touch:
		if ev.position.distance_to(_look_start) > 10.0:
			_look_moved = true
		player.look(ev.relative.x, ev.relative.y)
	elif ev is InputEventMouseButton and ev.device != InputEvent.DEVICE_ID_EMULATION and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_look_touch = -2
			_look_start = ev.position
			_look_moved = false
		elif _look_touch == -2:
			_look_touch = -1
			if not _look_moved:
				_click_at(ev.position + _look.global_position)
	elif ev is InputEventMouseMotion and _look_touch == -2 and ev.device != InputEvent.DEVICE_ID_EMULATION:
		if ev.position.distance_to(_look_start) > 6.0:
			_look_moved = true
		player.look(ev.relative.x, ev.relative.y)


func _click_at(screen_pos: Vector2) -> void:
	if runtime == null or player == null:
		return
	var cam := player.camera
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0, PSWorld.LAYER_WORLD | PSWorld.LAYER_TRIGGER, [player.get_rid()])
	q.collide_with_areas = true
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var id := String(hit["collider"].get_meta("ps_id", ""))
	if id != "":
		runtime.fire_click(id)


func _on_log_added(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	if int(entry.get("level", 0)) == App.LogLevel.ERROR:
		_errors += 1
		_error_btn.visible = true
		_error_btn.text = str(_errors)


func _show_errors() -> void:
	var m := PSModal.create("Mensagens do teste", 560.0)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.custom_minimum_size = Vector2(0, minf(App.get_ui_size().y * 0.55, 420.0))
	rt.add_theme_font_size_override("normal_font_size", 14)
	var lines: PackedStringArray = []
	for i in range(_log_start, App.log_entries.size()):
		var e: Dictionary = App.log_entries[i]
		var color := ["#c9d1d9", "#e3b341", "#ff7b72"][int(e["level"])] as String
		lines.append("[color=%s][%s] %s[/color]" % [color, String(e["source"]), String(e["msg"]).replace("[", "[lb]")])
	rt.text = "\n".join(lines) if not lines.is_empty() else "Nenhuma mensagem."
	m.body.add_child(rt)
	m.add_button("Fechar", Callable(), "AccentButton")
	m.show_modal()
