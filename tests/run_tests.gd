extends Node
## Executa todos os testes (tests/test_*.gd) e sai com código 0 (ok) ou 1 (falhas).
## Uso: godot --headless --path . res://tests/run_tests.tscn [-- --only=nome]

var only := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.get_slice("=", 1)
	# No modo headless a janela tem 64x64: define um tamanho de tela realista.
	get_tree().root.size = Vector2i(1280, 720)
	App.overlay = Control.new()
	App.overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	App.overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(App.overlay)
	await get_tree().process_frame
	var total := 0
	var failed := 0
	var files: Array = []
	var dir := DirAccess.open("res://tests")
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			if only == "" or f.contains(only):
				files.append(f)
	files.sort()
	var started := Time.get_ticks_msec()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		var suite: PSTestCase = script.new()
		suite.runner = self
		await suite.before_all()
		var methods: Array = []
		for m in script.get_script_method_list():
			if String(m["name"]).begins_with("test_") and not methods.has(m["name"]):
				methods.append(m["name"])
		for m in methods:
			total += 1
			suite.current = "%s::%s" % [f.get_basename(), m]
			var before := suite.failures.size()
			var t0 := Time.get_ticks_msec()
			await suite.call(m)
			var ok := suite.failures.size() == before
			if not ok:
				failed += 1
			print("%s %s (%d ms)" % ["[OK]  " if ok else "[FALHA]", suite.current, Time.get_ticks_msec() - t0])
			for i in range(before, suite.failures.size()):
				printerr("        " + String(suite.failures[i]))
		await suite.after_all()
	print("")
	print("Testes: %d · falhas: %d · tempo: %.1f s" % [total, failed, (Time.get_ticks_msec() - started) / 1000.0])
	get_tree().quit(1 if failed > 0 or total == 0 else 0)
