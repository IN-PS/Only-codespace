class_name PSWorldPanel
extends PSPanel
## Ambiente (céu, sol, neblina, gravidade) e regras do modo de teste.

const SKY_LABELS := ["Dia", "Entardecer", "Noite", "Nublado"]
const CAM_LABELS := ["Terceira pessoa", "Primeira pessoa"]

var _content: VBoxContainer
var _env_before := {}


func _build() -> void:
	_content = PSUI.vbox(8)
	add_child(PSUI.scroll(_content))


func on_shown() -> void:
	_rebuild()


func on_world_changed() -> void:
	if is_visible_in_tree() and not _env_before.size():
		_rebuild.call_deferred()


func _rebuild() -> void:
	PSUI.clear(_content)
	var env: Dictionary = editor.world.env_data
	var game: Dictionary = editor.world.game_data
	_content.add_child(PSUI.label("CÉU E LUZ", "HeaderLabel"))
	var sky := PSUI.option(SKY_LABELS, PSData.SKIES.find(env["sky"]))
	sky.item_selected.connect(func(i): _commit_env("sky", PSData.SKIES[i]))
	_content.add_child(PSUI.row("Céu", sky))
	_env_slider("Sol (altura)", "sun_pitch", -90.0, -5.0, 1.0, float(env["sun_pitch"]), "%.0f°")
	_env_slider("Sol (direção)", "sun_yaw", -180.0, 180.0, 1.0, float(env["sun_yaw"]), "%.0f°")
	_env_slider("Intensidade do sol", "sun_energy", 0.0, 4.0, 0.05, float(env["sun_energy"]))
	_env_slider("Luz ambiente", "ambient", 0.0, 2.0, 0.05, float(env["ambient"]))
	var fog := PSUI.check("Neblina", bool(env["fog"]))
	fog.toggled.connect(func(on): _commit_env("fog", on))
	_content.add_child(fog)
	if env["fog"]:
		_env_slider("Densidade", "fog_density", 0.001, 0.1, 0.001, float(env["fog_density"]), "%.3f")
	_env_slider("Gravidade", "gravity", 0.0, 40.0, 0.1, float(env["gravity"]), "%.1f")

	_content.add_child(PSUI.separator())
	_content.add_child(PSUI.label("MODO DE TESTE", "HeaderLabel"))
	var cam := PSUI.option(CAM_LABELS, PSData.CAMERA_MODES.find(game["camera"]))
	cam.item_selected.connect(func(i): _commit_game("camera", PSData.CAMERA_MODES[i]))
	_content.add_child(PSUI.row("Câmera", cam))
	_game_field("Velocidade", "walk_speed", 0.5, 50.0, 0.5, float(game["walk_speed"]))
	_game_field("Força do pulo", "jump", 0.0, 50.0, 0.5, float(game["jump"]))
	_game_field("Renascer abaixo de Y", "respawn_y", -1000.0, 1000.0, 1.0, float(game["respawn_y"]))
	var msg := PSUI.line_edit(String(game["start_message"]), "Mensagem ao iniciar (opcional)")
	msg.max_length = 200
	msg.text_submitted.connect(func(t): _commit_game("start_message", t))
	msg.focus_exited.connect(func(): _commit_game("start_message", msg.text))
	_content.add_child(PSUI.row("Mensagem", msg))

	_content.add_child(PSUI.separator())
	_content.add_child(PSUI.label("ENCAIXE NA GRADE", "HeaderLabel"))
	for s in [["Mover", "snap_move", 0.05, 10.0, 0.05], ["Girar (°)", "snap_rotate", 1.0, 90.0, 1.0], ["Tamanho", "snap_scale", 0.05, 5.0, 0.05]]:
		var f := PSNumberField.create("", PSTheme.PANEL_3, s[4], 2)
		f.min_value = s[2]
		f.max_value = s[3]
		f.set_value(float(App.get_setting(s[1])))
		var key: String = s[1]
		f.value_committed.connect(func(v):
			App.set_setting(key, v)
			editor._apply_snap_settings())
		_content.add_child(PSUI.row(s[0], f))


func _env_slider(label: String, key: String, lo: float, hi: float, step: float, value: float, fmt := "%.2f") -> void:
	var h := PSUI.slider(lo, hi, step, value, fmt)
	var s := PSUI.get_slider(h)
	s.value_changed.connect(func(v):
		if _env_before.is_empty():
			_env_before = editor.world.env_data.duplicate(true)
		var e: Dictionary = editor.world.env_data.duplicate(true)
		e[key] = v
		editor.world.apply_environment(e))
	s.drag_ended.connect(func(_c): _finish_env_drag())
	_content.add_child(PSUI.row(label, h))


func _finish_env_drag() -> void:
	if _env_before.is_empty():
		return
	var before := _env_before
	var after: Dictionary = editor.world.env_data.duplicate(true)
	_env_before = {}
	editor.undo.custom("Ambiente", func(): editor.world.apply_environment(after), func(): editor.world.apply_environment(before), false)


func _commit_env(key: String, value: Variant) -> void:
	var before: Dictionary = editor.world.env_data.duplicate(true)
	var after := before.duplicate(true)
	after[key] = value
	editor.undo.custom("Ambiente", func(): editor.world.apply_environment(after), func(): editor.world.apply_environment(before))
	_rebuild.call_deferred()


func _game_field(label: String, key: String, lo: float, hi: float, step: float, value: float) -> void:
	var f := PSNumberField.create("", PSTheme.PANEL_3, step, 1)
	f.min_value = lo
	f.max_value = hi
	f.set_value(value)
	f.value_committed.connect(func(v): _commit_game(key, v))
	_content.add_child(PSUI.row(label, f))


func _commit_game(key: String, value: Variant) -> void:
	if editor.world.game_data.get(key) == value:
		return
	var before: Dictionary = editor.world.game_data.duplicate(true)
	var after := before.duplicate(true)
	after[key] = value
	var w := editor.world
	editor.undo.custom("Regras do jogo", func(): w.game_data = after.duplicate(true), func(): w.game_data = before.duplicate(true))
