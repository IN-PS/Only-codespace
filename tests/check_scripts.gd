extends Node
## Carrega todos os scripts do projeto e informa erros de compilação.
## Uso: godot --headless --path . res://tests/check_scripts.tscn


func _ready() -> void:
	var failed := 0
	var total := 0
	for path in _find("res://src") + _find("res://tests"):
		total += 1
		var s = load(path)
		if s == null or not (s is Script) or not s.can_instantiate():
			failed += 1
			printerr("FALHOU: ", path)
	print("Scripts verificados: %d, com erro: %d" % [total, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _find(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_find(dir.path_join(sub)))
	return out
