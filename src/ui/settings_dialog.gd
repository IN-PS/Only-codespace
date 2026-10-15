class_name PSSettingsDialog
extends RefCounted
## Configurações do aplicativo (valem para todos os projetos).


static func open() -> void:
	var m := PSModal.create("Configurações", 480.0)
	var v := PSUI.vbox(8)
	var sc := PSUI.scroll(v)
	sc.custom_minimum_size.y = minf(App.get_ui_size().y * 0.6, 460.0)
	m.body.add_child(sc)

	v.add_child(PSUI.label("INTERFACE", "HeaderLabel"))
	var scales := [0.8, 0.9, 1.0, 1.15, 1.3]
	var scale_opt := PSUI.option(["Muito pequena", "Pequena", "Normal", "Grande", "Muito grande"], maxi(0, scales.find(float(App.get_setting("ui_scale")))))
	if scales.find(float(App.get_setting("ui_scale"))) < 0:
		scale_opt.select(2)
	scale_opt.item_selected.connect(func(i):
		App.set_setting("ui_scale", scales[i])
		PSIcons.clear_cache()
		PSUI.toast("Tamanho da interface alterado. Reabra a tela para atualizar os ícones.", "info", 3.0))
	v.add_child(PSUI.row("Tamanho", scale_opt, 110))

	v.add_child(PSUI.label("DESEMPENHO", "HeaderLabel"))
	var rs := [0.5, 0.67, 0.8, 1.0]
	var rs_idx := rs.find(float(App.get_setting("render_scale")))
	var rs_opt := PSUI.option(["50% (mais rápido)", "67%", "80%", "100% (mais nítido)"], rs_idx if rs_idx >= 0 else 3)
	rs_opt.item_selected.connect(func(i): App.set_setting("render_scale", rs[i]))
	v.add_child(PSUI.row("Resolução 3D", rs_opt, 110))
	var shadows := PSUI.check("Sombras (desligue em celulares modestos)", bool(App.get_setting("shadows")))
	shadows.toggled.connect(func(on): App.set_setting("shadows", on))
	v.add_child(shadows)
	var fps := [20, 30, 60]
	var fps_idx := fps.find(int(App.get_setting("editor_fps")))
	var fps_opt := PSUI.option(["20 FPS (economia)", "30 FPS", "60 FPS"], fps_idx if fps_idx >= 0 else 1)
	fps_opt.item_selected.connect(func(i):
		App.set_setting("editor_fps", fps[i])
		Engine.max_fps = fps[i])
	v.add_child(PSUI.row("FPS do editor", fps_opt, 110))

	v.add_child(PSUI.label("SALVAMENTO", "HeaderLabel"))
	var autos := [20, 45, 90, 180]
	var au_idx := autos.find(int(App.get_setting("autosave_seconds")))
	var au_opt := PSUI.option(["A cada 20 s", "A cada 45 s", "A cada 90 s", "A cada 3 min"], au_idx if au_idx >= 0 else 1)
	au_opt.item_selected.connect(func(i): App.set_setting("autosave_seconds", autos[i]))
	v.add_child(PSUI.row("Automático", au_opt, 110))
	var keep := [5, 15, 30]
	var keep_idx := keep.find(int(App.get_setting("max_versions")))
	var keep_opt := PSUI.option(["5 versões", "15 versões", "30 versões"], keep_idx if keep_idx >= 0 else 1)
	keep_opt.item_selected.connect(func(i): App.set_setting("max_versions", keep[i]))
	v.add_child(PSUI.row("Guardar", keep_opt, 110))

	v.add_child(PSUI.label("MODO DE TESTE", "HeaderLabel"))
	var sens := PSUI.slider(0.3, 3.0, 0.1, float(App.get_setting("look_sensitivity")), "%.1f")
	PSUI.get_slider(sens).drag_ended.connect(func(_c): App.set_setting("look_sensitivity", PSUI.get_slider(sens).value))
	v.add_child(PSUI.row("Sensibilidade", sens, 110))
	var inv := PSUI.check("Inverter eixo vertical da câmera", bool(App.get_setting("invert_look")))
	inv.toggled.connect(func(on): App.set_setting("invert_look", on))
	v.add_child(inv)

	v.add_child(PSUI.label("Dados em: " + ProjectSettings.globalize_path("user://"), "DimLabel", true))
	m.add_button("Fechar", Callable(), "AccentButton")
	m.show_modal()

