extends Node
## Singleton global do Pocket Studio 3D.
##
## Guarda configurações do usuário, o registro de mensagens (console),
## a escala da interface e utilidades compartilhadas entre as telas.

signal log_added(entry: Dictionary)
signal settings_changed
signal ui_scale_changed(scale: float)

const VERSION := "0.1.0"
const SETTINGS_PATH := "user://settings.json"
const MAX_LOG_ENTRIES := 500

enum LogLevel { INFO, WARN, ERROR }

const DEFAULT_SETTINGS := {
	"ui_scale": 1.0,          # Multiplicador sobre a escala automática (DPI).
	"render_scale": 1.0,      # Resolução 3D relativa (0.5 a 1.0).
	"shadows": true,
	"editor_fps": 30,
	"play_fps": 60,
	"autosave_seconds": 45,
	"snap_enabled": true,
	"snap_move": 0.5,
	"snap_rotate": 15.0,
	"snap_scale": 0.25,
	"show_grid": true,
	"look_sensitivity": 1.0,
	"invert_look": false,
	"max_versions": 15,
}

var settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
var log_entries: Array[Dictionary] = []
var ui_scale: float = 1.0
## Força o layout de celular no computador (útil para testes).
var force_mobile := false
## Camada de interface por cima de tudo (diálogos e avisos). Definida pela cena principal.
var overlay: Control
var _id_counter := 0
var _cmdline_scale := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_cmdline()
	load_settings()
	_register_input_actions()
	apply_ui_scale()
	get_tree().root.size_changed.connect(_on_root_resized)


func _parse_cmdline() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-scale="):
			var v := arg.get_slice("=", 1).to_float()
			if v > 0.0:
				_cmdline_scale = v
		elif arg == "--mobile":
			force_mobile = true



# --------------------------------------------------------------------------
# Plataforma
# --------------------------------------------------------------------------

func is_mobile() -> bool:
	return force_mobile or OS.has_feature("mobile") or OS.has_feature("android")


func is_android() -> bool:
	return OS.has_feature("android")


func has_touchscreen() -> bool:
	return is_mobile() or DisplayServer.is_touchscreen_available()


# --------------------------------------------------------------------------
# Escala da interface
# --------------------------------------------------------------------------

## Escala automática: 1 unidade de interface ~= 1 dp no Android.
func get_auto_scale() -> float:
	if _cmdline_scale > 0.0:
		return _cmdline_scale
	var s := 1.0
	if OS.has_feature("android"):
		s = DisplayServer.screen_get_scale()
		if s <= 0.0:
			s = DisplayServer.screen_get_dpi() / 160.0
	else:
		s = DisplayServer.screen_get_scale()
	return clampf(s, 0.75, 4.0)


func apply_ui_scale() -> void:
	var mult := clampf(float(settings.get("ui_scale", 1.0)), 0.6, 2.0)
	ui_scale = get_auto_scale() * mult
	var root := get_tree().root
	root.content_scale_factor = ui_scale
	root.scaling_3d_scale = clampf(float(settings.get("render_scale", 1.0)), 0.4, 1.0)
	ui_scale_changed.emit(ui_scale)


## Tamanho da área útil em unidades de interface (dp).
func get_ui_size() -> Vector2:
	var root := get_tree().root
	return Vector2(root.size) / maxf(root.content_scale_factor, 0.01)


func is_portrait() -> bool:
	var s := get_ui_size()
	return s.y > s.x


func _on_root_resized() -> void:
	ui_scale_changed.emit(ui_scale)


# --------------------------------------------------------------------------
# Configurações
# --------------------------------------------------------------------------

func load_settings() -> void:
	settings = DEFAULT_SETTINGS.duplicate(true)
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var text := FileAccess.get_file_as_string(SETTINGS_PATH)
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		for key in DEFAULT_SETTINGS.keys():
			if parsed.has(key) and typeof(parsed[key]) in [TYPE_FLOAT, TYPE_INT, TYPE_BOOL]:
				settings[key] = parsed[key]
	else:
		log_warn("Arquivo de configurações inválido; usando padrões.", "Config")


func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		log_error("Não foi possível salvar as configurações (%s)." % error_string(FileAccess.get_open_error()), "Config")
		return
	f.store_string(JSON.stringify(settings, "\t"))
	f.close()


func get_setting(key: String, fallback: Variant = null) -> Variant:
	return settings.get(key, DEFAULT_SETTINGS.get(key, fallback))


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	save_settings()
	if key == "ui_scale" or key == "render_scale":
		apply_ui_scale()
	settings_changed.emit()


# --------------------------------------------------------------------------
# Console / registro
# --------------------------------------------------------------------------

func log_info(msg: String, source := "") -> void:
	_add_log(LogLevel.INFO, msg, source)


func log_warn(msg: String, source := "") -> void:
	_add_log(LogLevel.WARN, msg, source)


func log_error(msg: String, source := "") -> void:
	_add_log(LogLevel.ERROR, msg, source)


func _add_log(level: int, msg: String, source: String) -> void:
	var entry := {
		"level": level,
		"msg": msg,
		"source": source,
		"time": Time.get_unix_time_from_system(),
	}
	log_entries.append(entry)
	if log_entries.size() > MAX_LOG_ENTRIES:
		log_entries.remove_at(0)
	var prefix: String = ["", "[aviso] ", "[erro] "][level]
	var src := ("[%s] " % source) if source != "" else ""
	if level == LogLevel.ERROR:
		printerr(src + prefix + msg)
	else:
		print(src + prefix + msg)
	log_added.emit(entry)


func clear_log() -> void:
	log_entries.clear()
	log_added.emit({})


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

## Gera um identificador curto e único (para objetos, assets, scripts).
func new_id(prefix := "o") -> String:
	_id_counter += 1
	var t := int(Time.get_unix_time_from_system() * 1000.0) % 100000000
	return "%s%x%x%04x" % [prefix, t, _id_counter, randi() % 0xffff]


func format_time(unix: float) -> String:
	if unix <= 0:
		return "—"
	var bias := Time.get_time_zone_from_system().get("bias", 0) as int
	var d := Time.get_datetime_dict_from_unix_time(int(unix) + bias * 60)
	return "%02d/%02d/%04d %02d:%02d" % [d.day, d.month, d.year, d.hour, d.minute]


func format_bytes(n: int) -> String:
	if n < 1024:
		return "%d B" % n
	if n < 1024 * 1024:
		return "%.1f KB" % (n / 1024.0)
	return "%.1f MB" % (n / 1048576.0)


func _register_input_actions() -> void:
	var keys := {
		"ps_forward": [KEY_W, KEY_UP],
		"ps_back": [KEY_S, KEY_DOWN],
		"ps_left": [KEY_A, KEY_LEFT],
		"ps_right": [KEY_D, KEY_RIGHT],
		"ps_jump": [KEY_SPACE],
		"ps_sprint": [KEY_SHIFT],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
