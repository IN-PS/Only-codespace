class_name PSVersionsDialog
extends RefCounted
## Lista de versões salvas do projeto, com restaurar e excluir.


static func open(editor: PSEditor) -> void:
	var m := PSModal.create("Versões salvas", 520.0)
	var list := PSUI.vbox(6)
	var sc := PSUI.scroll(list)
	sc.custom_minimum_size.y = minf(App.get_ui_size().y * 0.55, 400.0)
	m.body.add_child(PSUI.label("Cada salvamento guarda uma versão (as %d mais recentes). Restaurar substitui o mundo atual; salve antes se quiser manter o estado de agora." % int(App.get_setting("max_versions", 15)), "DimLabel", true))
	m.body.add_child(sc)
	var fill := func(self_ref: Callable):
		PSUI.clear(list)
		var versions := PSProjectStore.list_versions(editor.pid)
		if versions.is_empty():
			list.add_child(PSUI.label("Nenhuma versão ainda. Use \"Salvar\" para criar a primeira.", "DimLabel", true))
		for v in versions:
			var row := PSUI.hbox(6)
			var label := String(v["label"]) if String(v["label"]) != "" else "Salvamento"
			var info := PSUI.label("%s\n%s · %d objetos · %s" % [label, App.format_time(v["time"]), v["objects"], App.format_bytes(v["bytes"])], "", false)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.add_theme_font_size_override("font_size", 14)
			row.add_child(info)
			var file: String = v["file"]
			var restore := PSUI.button("Restaurar")
			restore.pressed.connect(func():
				var res := PSProjectStore.load_version(editor.pid, file)
				if res["ok"]:
					editor.restore_version(res["data"])
					m.close()
				else:
					PSUI.toast(res["error"], "error"))
			row.add_child(restore)
			var del := PSUI.icon_button("trash", "Excluir versão", false)
			del.pressed.connect(func():
				PSProjectStore.delete_version(editor.pid, file)
				self_ref.call(self_ref))
			row.add_child(del)
			list.add_child(row)
	fill.call(fill)
	m.add_button("Fechar")
	m.show_modal()
