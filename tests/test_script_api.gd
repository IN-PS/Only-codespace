extends PSTestCase
## Verifica, num teste de jogo real, as funções documentadas em docs/SCRIPTS.md.

var session: PSPlaySession
var lib: PSAssetLibrary


func _obj(type: String, id: String, pos: Vector3, extra := {}) -> Dictionary:
	var d := PSData.new_object(type, extra)
	d["id"] = id
	d["pos"] = PSData.v3_to_arr(pos)
	return d


func before_all() -> void:
	var data := PSData.new_project_data("api")
	var base := _obj("part", "base", Vector3(0, -0.5, 0), {"size": [60.0, 1.0, 60.0]})
	var spawn := _obj("spawn", "spawn", Vector3.ZERO)
	var api := _obj("part", "api", Vector3(5, 1, 5), {"script": "api", "name": "Tester"})
	var child := _obj("part", "child", Vector3(6, 1, 5), {"parent": "api", "name": "Filho"})
	var grp := _obj("group", "grp", Vector3(-6, 0, -6), {"script": "grp_click", "name": "Grupo"})
	var inner := _obj("part", "inner", Vector3(-6, 1, -6), {"parent": "grp", "name": "Peça do grupo"})
	var dyn := _obj("part", "dyn", Vector3(10, 3, -10), {"name": "Caixa"})
	dyn["phys"]["mode"] = "dynamic"
	data["objects"] = [base, spawn, api, child, grp, inner, dyn]
	data["scripts"] = [
		{"id": "api", "name": "api", "enabled": true, "global": false, "code": """
local r = {}
function on_start()
  r.name = self.name
  r.child = self:find("Filho") ~= nil
  r.nchildren = #self:children()
  local c = hex("#ff8800")
  self.color = c
  r.color_ok = self.color == rgb(1, 136/255, 0)
  self:set("vidas", 3)
  r.vidas = self:get("vidas")
  self:move(1, 0, 0)
  self:move(vec(0, 0, 1))
  r.pos = self.position
  self:lookAt(self.position + vec(0, 0, -5))
  local b = world.create("sphere", vec(0, 10, 0), "dynamic")
  r.created = b ~= nil and b.exists
  local copia = world.find("Caixa"):clone()
  r.clone = copia.name == "Caixa" and copia.id ~= world.find("Caixa").id
  r.findall = #world.findAll("Caixa")
  local id = after(10, function() r.never = true end)
  cancel(id)
  after(0.05, function() r.after = true end)
  r.gravity = world.gravity
  world.gravity = 20
  r.gravity2 = world.gravity
  player:setSpawn(vec(3, 1, 3))
  player.speed = 9
  r.speed = player.speed
  self.solid = false
  r.solid = self.solid
  shared.api = r
end
"""},
		{"id": "grp_click", "name": "grp", "enabled": true, "global": false, "code": "function on_click() shared.grupo_clicado = true end"},
	]
	lib = PSAssetLibrary.new()
	runner.add_child(lib)
	lib.setup("", [])
	session = PSPlaySession.new()
	runner.add_child(session)
	session.start(data, lib, "")
	await physics_frames(3)


func after_all() -> void:
	session.queue_free()
	lib.queue_free()
	await frames(2)


func _r(key: String) -> Variant:
	var t: PSLua.Table = session.runtime._shared.get_v("api")
	return t.get_v(key) if t else null


func test_object_api() -> void:
	check(session.runtime._shared.get_v("api") != null, "script rodou on_start")
	eq(_r("name"), "Tester", "self.name")
	eq(_r("child"), true, "self:find")
	eq(_r("nchildren"), 1.0, "self:children")
	eq(_r("color_ok"), true, "hex() e comparação de cores")
	eq(_r("vidas"), 3.0, "set/get")
	var pos: PSLua.Vec3 = _r("pos")
	check(pos != null and pos.v.is_equal_approx(Vector3(6, 1, 6)), "move(x,y,z) e move(vec)")
	eq(_r("solid"), false, "solid = false")


func test_world_and_player_api() -> void:
	eq(_r("created"), true, "world.create")
	eq(_r("clone"), true, "clone")
	eq(_r("findall"), 2.0, "findAll encontra original e cópia")
	near(float(_r("gravity")), 9.8, 0.01, "world.gravity padrão")
	near(float(_r("gravity2")), 20.0, 0.01, "world.gravity alterada")
	eq(_r("speed"), 9.0, "player.speed")
	session.player.place_at_spawn()
	near(session.player.global_position.x, 3.0, 0.01, "player:setSpawn define o novo ponto de início")


func test_timers_and_click() -> void:
	await tree().create_timer(0.2).timeout
	eq(_r("after"), true, "after() dispara")
	eq(_r("never"), null, "cancel() cancela")
	session.runtime.fire_click("inner")
	eq(session.runtime._shared.get_v("grupo_clicado"), true, "on_click do grupo ao tocar numa peça dele")
