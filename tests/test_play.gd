extends PSTestCase
## Modo de teste: física, jogador, água e scripts rodando no mundo.

var session: PSPlaySession
var lib: PSAssetLibrary


func _obj(type: String, id: String, pos: Vector3, extra := {}) -> Dictionary:
	var d := PSData.new_object(type, extra)
	d["id"] = id
	d["pos"] = PSData.v3_to_arr(pos)
	return d


func _script(id: String, code: String, global := false) -> Dictionary:
	return {"id": id, "name": id, "code": code, "enabled": true, "global": global}


func _data() -> Dictionary:
	var data := PSData.new_project_data("play")
	var base := _obj("part", "base", Vector3(0, -0.5, 0), {"size": [40.0, 1.0, 40.0]})
	var spawn := _obj("spawn", "spawn", Vector3(0, 0, 0))
	var ball := _obj("part", "ball", Vector3(8, 6, 8), {"shape": "sphere"})
	ball["phys"]["mode"] = "dynamic"
	var spinner := _obj("part", "spinner", Vector3(-8, 1, -8), {"script": "spin"})
	var coin := _obj("part", "coin", Vector3(5, 1, 0), {"script": "coin", "name": "Moeda"})
	coin["phys"]["mode"] = "none"
	var plat := _obj("part", "plat", Vector3(-8, 0.5, 8), {"script": "mover", "size": [3.0, 0.5, 3.0]})
	plat["phys"]["mode"] = "kinematic"
	var broken := _obj("part", "broken", Vector3(12, 1, -12), {"script": "broken"})
	var looper := _obj("part", "looper", Vector3(14, 1, -12), {"script": "looper"})
	var water := _obj("water", "water", Vector3(-15, 2, -15), {"size": [6.0, 3.0, 6.0]})
	var clicker := _obj("part", "clicker", Vector3(0, 1, -10), {"script": "click"})
	data["objects"] = [base, spawn, ball, spinner, coin, plat, broken, looper, water, clicker]
	data["scripts"] = [
		_script("spin", "function on_update(dt) self:rotate(0, 90 * dt, 0) end"),
		_script("coin", "function on_touch() shared.moedas = (shared.moedas or 0) + 1 self:destroy() end"),
		_script("mover", "local p0\nfunction on_start() p0 = self.position end\nfunction on_update(dt) self.position = p0 + vec(time() * 2, 0, 0) end"),
		_script("broken", "function on_update(dt) local x = nil x.y = 1 end"),
		_script("looper", "function on_start() while true do end end"),
		_script("click", "function on_click() self.color = rgb(1, 0, 0) shared.clicked = true end"),
		_script("global", "after(0.2, function() shared.timer = true end)\nfunction on_start() shared.started = world.find('Moeda') ~= nil end", true),
	]
	return data


func before_all() -> void:
	lib = PSAssetLibrary.new()
	runner.add_child(lib)
	lib.setup("", [])
	session = PSPlaySession.new()
	runner.add_child(session)
	session.start(_data(), lib, "")
	await physics_frames(5)


func after_all() -> void:
	session.queue_free()
	lib.queue_free()
	await frames(2)


func _shared(key: String) -> Variant:
	return session.runtime._shared.get_v(key)


func test_player_spawns_and_lands() -> void:
	await physics_frames(40)
	var p := session.player.global_position
	near(p.x, 0.0, 0.2, "nasce no ponto de início (x)")
	near(p.y, 0.0, 0.15, "fica em pé sobre a base")
	check(session.player.is_on_floor(), "está no chão")


func test_player_walks_and_jumps() -> void:
	var p0 := session.player.global_position
	session.player.move_input = Vector2(0, -1)
	await physics_frames(30)
	session.player.move_input = Vector2.ZERO
	var p1 := session.player.global_position
	check(p0.distance_to(p1) > 1.5, "anda com o joystick (%.2f m)" % p0.distance_to(p1))
	session.player.jump_pressed = true
	await physics_frames(8)
	check(session.player.global_position.y > 0.5, "pula")
	await physics_frames(60)


func test_dynamic_body_falls() -> void:
	var ball := session.world.get_obj("ball")
	check(ball.node is RigidBody3D, "objeto dinâmico vira corpo rígido")
	await physics_frames(90)
	near(ball.node.global_position.y, 0.5, 0.2, "bola caiu e parou na base")


func test_scripts_run() -> void:
	await frames(10)
	var spinner := session.world.get_obj("spinner")
	check(absf(spinner.node.global_rotation_degrees.y) > 1.0, "on_update girou o objeto")
	eq(_shared("started"), true, "script global rodou on_start e achou a moeda")
	var plat := session.world.get_obj("plat")
	check(plat.node is AnimatableBody3D, "plataforma móvel por script")
	check(plat.node.global_position.x > -7.9, "script moveu a plataforma")
	await tree().create_timer(0.3).timeout
	eq(_shared("timer"), true, "after() disparou")


func test_script_errors_do_not_crash() -> void:
	var errors := App.log_entries.filter(func(e): return int(e["level"]) == App.LogLevel.ERROR and String(e["source"]).begins_with("Script"))
	check(errors.size() >= 2, "erros registrados no console")
	var msgs := " ".join(errors.map(func(e): return String(e["msg"])))
	check(msgs.contains("broken:1:"), "erro do script com nome e linha")
	check(msgs.contains("limite"), "loop infinito foi interrompido")
	check(session.world.has_object("broken"), "o jogo continua")


func test_touch_event_collects_coin() -> void:
	check(session.world.has_object("coin"), "moeda existe")
	session.player.global_position = Vector3(5, 0.1, 0)
	await physics_frames(6)
	await frames(2)
	check(not session.world.has_object("coin"), "moeda coletada ao encostar")
	eq(_shared("moedas"), 1.0, "contador de moedas")


func test_click_event() -> void:
	session.runtime.fire_click("clicker")
	eq(_shared("clicked"), true, "on_click rodou")
	var c := PSData.arr_to_color(session.world.get_obj("clicker").data["mat"]["color"])
	eq(c, Color(1, 0, 0, 1), "script mudou a cor")


func test_water_swimming() -> void:
	session.player.global_position = Vector3(-15, 0.5, -15)
	await physics_frames(6)
	check(session.player.in_water > 0, "jogador detecta a água")
	session.player.global_position = Vector3(0, 0.2, 5)
	await physics_frames(6)
	eq(session.player.in_water, 0, "saiu da água")


func test_restart_rebuilds_world() -> void:
	session.restart()
	await physics_frames(3)
	check(session.world.has_object("coin"), "reiniciar traz a moeda de volta")
	eq(_shared("moedas"), null, "estado compartilhado zerado")
	session.set_paused(true)
	check(tree().paused, "pausa")
	session.set_paused(false)
	check(not tree().paused, "continua")
