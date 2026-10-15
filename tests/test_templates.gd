extends PSTestCase
## Cada modelo de projeto deve abrir no editor e rodar no modo de teste sem erros.


func test_templates_play_without_errors() -> void:
	for t in PSTemplates.LIST:
		var data := PSTemplates.create(t["key"], "Modelo " + t["name"])
		var clean := PSData.sanitize_project(JSON.parse_string(JSON.stringify(data)))
		check(not clean.is_empty(), "modelo %s é um projeto válido" % t["key"])
		var lib := PSAssetLibrary.new()
		runner.add_child(lib)
		lib.setup("", [])
		var log_start := App.log_entries.size()
		var s := PSPlaySession.new()
		runner.add_child(s)
		s.start(clean, lib, "")
		await physics_frames(30)
		await frames(5)
		var errors: Array = []
		for i in range(log_start, App.log_entries.size()):
			if int(App.log_entries[i]["level"]) == App.LogLevel.ERROR:
				errors.append(App.log_entries[i]["msg"])
		eq(errors, [], "modelo %s roda sem erros" % t["key"])
		check(s.player.global_position.y > -5.0, "jogador não caiu do mundo no modelo %s" % t["key"])
		s.queue_free()
		lib.queue_free()
		await frames(2)


func test_obby_is_playable() -> void:
	var data := PSData.sanitize_project(JSON.parse_string(JSON.stringify(PSTemplates.create("obby", "Obby"))))
	var lib := PSAssetLibrary.new()
	runner.add_child(lib)
	lib.setup("", [])
	var s := PSPlaySession.new()
	runner.add_child(s)
	s.start(data, lib, "")
	await physics_frames(20)
	var coins := s.world.objects.values().filter(func(o): return o.data.get("name") == "Moeda")
	eq(coins.size(), 6, "seis moedas no percurso")
	# Teleporta o jogador até a primeira moeda: ela deve ser coletada.
	var c: PSWorld.PSObject = coins[0]
	s.player.global_position = c.node.global_position - Vector3(0, 1.0, 0)
	await physics_frames(5)
	await frames(2)
	eq(s.runtime._shared.get_v("moedas"), 1.0, "moeda coletada conta ponto")
	check(s._hud_text.text.contains("Moedas: 1"), "placar no topo da tela: '%s'" % s._hud_text.text)
	# Cair aciona a zona de queda e volta ao início.
	s.player.global_position = Vector3(0, -7.5, -20)
	await physics_frames(4)
	await frames(2)
	check(s.player.global_position.y > -2.0, "zona de queda devolve ao início")
	s.queue_free()
	lib.queue_free()
	await frames(2)
