class_name PSScriptRuntime
extends Node
## Executa os scripts do projeto durante o modo de teste.
##
## Cada objeto com script ganha uma "instância": um ambiente global próprio em
## que `self` é o objeto. Eventos chamados pelo jogo (se o script os definir):
##   on_start()        uma vez, quando o teste começa
##   on_update(dt)     a cada quadro (dt = segundos desde o quadro anterior)
##   on_touch()        quando o jogador encosta no objeto
##   on_leave()        quando o jogador deixa de encostar
##   on_click()        quando o jogador toca no objeto na tela

const STEPS_START := 300000
const STEPS_UPDATE := 30000
const STEPS_EVENT := 60000
const MAX_CREATED := 1000
const MAX_TIMERS := 500
const FRAME_BUDGET_MS := 12.0

class Inst:
	extends RefCounted
	var script_id := ""
	var script_name := ""
	var obj_id := ""
	var env: Dictionary
	var chunk: PSLua.Function
	var alive := true
	var has_update := false

var session: Node
var world: PSWorld
var player: PSPlayer
var interp: PSLuaInterp
var instances: Array = []
var time := 0.0
var _scripts := {}
var _compiled := {}
var _timers: Array = []
var _timer_id := 0
var _created := 0
var _attrs := {}
var _touch := {}               # obj_id -> número de áreas tocando
var _pending_destroy: Array = []
var _warned_slow := false
var _running := false
var _shared := PSLua.Table.new()


func setup(p_session: Node, p_world: PSWorld, p_player: PSPlayer, scripts: Array) -> void:
	session = p_session
	world = p_world
	player = p_player
	interp = PSLuaInterp.new()
	for s in scripts:
		var e := PSData.sanitize_script_entry(s)
		if not e.is_empty():
			_scripts[e["id"]] = e
	for id in world.objects:
		var sid := String(world.objects[id].data.get("script", ""))
		if sid != "" and _scripts.has(sid) and _scripts[sid]["enabled"]:
			_create_instance(sid, id)
	for sid in _scripts:
		var e: Dictionary = _scripts[sid]
		if e["global"] and e["enabled"]:
			_create_instance(sid, "")


func _compile(sid: String) -> Dictionary:
	if _compiled.has(sid):
		return _compiled[sid]
	var e: Dictionary = _scripts[sid]
	var res := PSLuaParser.parse(String(e["code"]))
	_compiled[sid] = res
	if not res["ok"]:
		App.log_error("Erro de sintaxe na linha %d: %s" % [res["line"], res["error"]], "Script: " + String(e["name"]))
	return res


func _create_instance(sid: String, obj_id: String) -> Inst:
	var parsed := _compile(sid)
	if not parsed["ok"]:
		return null
	var e: Dictionary = _scripts[sid]
	var inst := Inst.new()
	inst.script_id = sid
	inst.script_name = String(e["name"])
	inst.obj_id = obj_id
	inst.env = _make_env(inst)
	var f := PSLua.Function.new()
	f.body = parsed["ast"]
	f.vararg = true
	f.scope = [{}, null]
	f.name = inst.script_name
	f.set_meta("env", inst.env)
	f.set_meta("chunk", inst.script_name)
	interp._track(f)
	inst.chunk = f
	instances.append(inst)
	return inst


func _make_env(inst: Inst) -> Dictionary:
	var env := interp.new_env()
	var me := ref(inst.obj_id) if inst.obj_id != "" else null
	env["self"] = me
	var script_t := PSLua.Table.new()
	script_t.set_v("object", me)
	script_t.set_v("name", inst.script_name)
	env["script"] = script_t
	env["world"] = PSScriptAPI.WorldRef.new(self)
	env["player"] = PSScriptAPI.PlayerRef.new(self)
	env["ui"] = PSScriptAPI.UiRef.new(self)
	env["shared"] = _shared
	var src := "Script: " + inst.script_name
	env["print"] = interp.native("print", func(a):
		var parts: PackedStringArray = []
		for v in a:
			parts.append(interp.tostr(v))
		App.log_info("\t".join(parts), src)
		return null)
	env["warn"] = interp.native("warn", func(a):
		App.log_warn(interp.tostr(a[0]) if a.size() > 0 else "", src)
		return null)
	env["vec"] = interp.native("vec", func(a): return PSLua.Vec3.new(Vector3(interp.opt_num(a, 0, 0.0), interp.opt_num(a, 1, 0.0), interp.opt_num(a, 2, 0.0))))
	env["rgb"] = interp.native("rgb", func(a): return PSLua.ColorV.new(Color(clampf(interp.opt_num(a, 0, 1.0), 0, 1), clampf(interp.opt_num(a, 1, 1.0), 0, 1), clampf(interp.opt_num(a, 2, 1.0), 0, 1), clampf(interp.opt_num(a, 3, 1.0), 0, 1))))
	env["hex"] = interp.native("hex", func(a):
		var c = to_color(interp.arg_str(a, 0, "hex"))
		if c == null:
			interp.rt_error("cor inválida em hex()")
			return null
		return PSLua.ColorV.new(c))
	env["time"] = interp.native("time", func(_a): return time)
	env["after"] = interp.native("after", func(a): return _add_timer(inst, interp.arg_num(a, 0, "after"), interp.arg_fn(a, 1, "after"), false))
	env["every"] = interp.native("every", func(a): return _add_timer(inst, interp.arg_num(a, 0, "every"), interp.arg_fn(a, 1, "every"), true))
	env["cancel"] = interp.native("cancel", func(a):
		var tid := int(interp.opt_num(a, 0, -1.0))
		for t in _timers:
			if t["id"] == tid:
				t["dead"] = true
		return null)
	return env


func start() -> void:
	_running = true
	for inst in instances.duplicate():
		_run_chunk(inst)
	for inst in instances.duplicate():
		if inst.alive:
			inst.has_update = inst.env.get("on_update") != null
			_fire(inst, "on_start", [], STEPS_START)
	for inst in instances.duplicate():
		if inst.alive and inst.obj_id != "" and (inst.env.get("on_touch") != null or inst.env.get("on_leave") != null):
			_add_touch_areas(inst.obj_id)
	if not instances.is_empty():
		App.log_info("%d script(s) em execução." % instances.size(), "Jogo")


func _run_chunk(inst: Inst) -> void:
	interp.chunk_name = inst.script_name
	interp.genv = inst.env
	var r := interp.call_protected(inst.chunk, [], STEPS_START)
	if not r["ok"]:
		_report(inst, r)


func _report(inst: Inst, r: Dictionary) -> void:
	var where := ""
	if inst.obj_id != "":
		var o := world.get_obj(inst.obj_id)
		if o:
			where = " (objeto \"%s\")" % o.data.get("name", "")
	App.log_error(String(r["error"]) + where, "Script: " + inst.script_name)
	if r.get("fatal", false):
		inst.alive = false
		App.log_warn("O script \"%s\"%s foi parado para proteger o jogo." % [inst.script_name, where], "Jogo")


func _fire(inst: Inst, event: String, args: Array, steps: int) -> void:
	if not inst.alive:
		return
	var f = inst.env.get(event)
	if f == null:
		return
	interp.genv = inst.env
	interp.chunk_name = inst.script_name
	var r := interp.call_protected(f, args, steps)
	if not r["ok"]:
		_report(inst, r)
		if event == "on_update":
			inst.has_update = false
			App.log_warn("on_update de \"%s\" foi desativado após um erro." % inst.script_name, "Jogo")


func stop() -> void:
	_running = false
	_timers.clear()
	if interp:
		interp.dispose()
	for inst in instances:
		inst.env.clear()
		inst.chunk = null
	instances.clear()
	_shared.hash.clear()
	_attrs.clear()


func _exit_tree() -> void:
	stop()


func _process(delta: float) -> void:
	if not _running:
		return
	time += delta
	var t0 := Time.get_ticks_usec()
	# Temporizadores
	if not _timers.is_empty():
		var due: Array = []
		for t in _timers:
			if not t["dead"] and time >= t["at"]:
				due.append(t)
		for t in due:
			var inst: Inst = t["inst"]
			if not inst.alive:
				t["dead"] = true
				continue
			if t["repeat"]:
				t["at"] = time + maxf(t["interval"], 0.02)
			else:
				t["dead"] = true
			interp.genv = inst.env
			interp.chunk_name = inst.script_name
			var r := interp.call_protected(t["fn"], [], STEPS_EVENT)
			if not r["ok"]:
				_report(inst, r)
				t["dead"] = true
		_timers = _timers.filter(func(t): return not t["dead"])
	# on_update
	var args := [delta]
	for inst in instances:
		if inst.alive and inst.has_update:
			if inst.obj_id != "" and not world.has_object(inst.obj_id):
				inst.alive = false
				continue
			_fire(inst, "on_update", args, STEPS_UPDATE)
	_flush_destroy()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	if ms > FRAME_BUDGET_MS and not _warned_slow:
		_warned_slow = true
		App.log_warn("Os scripts levaram %.1f ms neste quadro; o jogo pode ficar lento em celulares." % ms, "Jogo")


func _add_timer(inst: Inst, seconds: float, fn: Variant, repeat: bool) -> Variant:
	if fn == null:
		return null
	if _timers.size() >= MAX_TIMERS:
		interp.rt_error("temporizadores demais ativos (limite %d)" % MAX_TIMERS)
		return null
	_timer_id += 1
	_timers.append({"id": _timer_id, "at": time + maxf(seconds, 0.0), "interval": seconds, "fn": fn, "repeat": repeat, "inst": inst, "dead": false})
	return float(_timer_id)


# --------------------------------------------------------------------------
# Eventos vindos do jogo
# --------------------------------------------------------------------------

func _instances_for(id: String, include_ancestors: bool) -> Array:
	var ids := [id]
	if include_ancestors:
		ids.append_array(world.get_ancestors(id))
	var out: Array = []
	for inst in instances:
		if inst.alive and ids.has(inst.obj_id):
			out.append(inst)
	return out


func fire_click(id: String) -> void:
	for inst in _instances_for(id, true):
		_fire(inst, "on_click", [], STEPS_EVENT)
	_flush_destroy()


func _add_touch_areas(owner_id: String) -> void:
	var targets: Array = []
	var o := world.get_obj(owner_id)
	if o == null:
		return
	if o.type in ["part", "model", "text", "water"]:
		targets.append(owner_id)
	else:
		for sub in world.get_subtree_data(owner_id):
			var so := world.get_obj(String(sub["id"]))
			if so and so.type in ["part", "model", "text"]:
				targets.append(String(sub["id"]))
	for tid in targets:
		_make_area(tid, owner_id)


func _make_area(target_id: String, owner_id: String) -> void:
	var t := world.get_obj(target_id)
	if t == null:
		return
	var old := t.node.get_node_or_null("_touch_area")
	if old:
		t.node.remove_child(old)
		old.free()
	var area := Area3D.new()
	area.name = "_touch_area"
	area.collision_layer = PSWorld.LAYER_TRIGGER
	area.collision_mask = PSWorld.LAYER_PLAYER
	area.set_meta("ps_id", target_id)
	area.set_meta("owner", owner_id)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var aabb := world.get_local_aabb(target_id)
	box.size = (aabb.size + Vector3.ONE * 0.12).max(Vector3.ONE * 0.1)
	cs.shape = box
	cs.position = aabb.get_center()
	area.add_child(cs)
	t.node.add_child(area)
	area.body_entered.connect(func(b): _on_touch(owner_id, b, true))
	area.body_exited.connect(func(b): _on_touch(owner_id, b, false))


func refresh_touch_area(id: String) -> void:
	var o := world.get_obj(id)
	if o and o.node.get_node_or_null("_touch_area"):
		_make_area(id, String(o.node.get_node("_touch_area").get_meta("owner", id)))


func _on_touch(owner_id: String, body: Node, entered: bool) -> void:
	if body != player or not _running:
		return
	var n: int = _touch.get(owner_id, 0)
	n = n + 1 if entered else maxi(0, n - 1)
	_touch[owner_id] = n
	# Para grupos com várias peças, só dispara na primeira entrada e na última saída.
	if (entered and n == 1) or (not entered and n == 0):
		for inst in _instances_for(owner_id, false):
			_fire(inst, "on_touch" if entered else "on_leave", [], STEPS_EVENT)
		_flush_destroy.call_deferred()


# --------------------------------------------------------------------------
# Funções usadas pela API
# --------------------------------------------------------------------------

func get_obj(id: String) -> PSWorld.PSObject:
	if _pending_destroy.has(id):
		return null
	return world.get_obj(id)


func ref(id: String) -> PSScriptAPI.ObjRef:
	return PSScriptAPI.ObjRef.new(self, id)


func session_message(text: String, seconds: float) -> void:
	session.show_message(text, clampf(seconds, 0.1, 60.0))


func session_text(text: String) -> void:
	session.set_hud_text(text.substr(0, 120))


func to_color(v: Variant) -> Variant:
	if v is PSLua.ColorV:
		return (v as PSLua.ColorV).c
	if typeof(v) == TYPE_STRING:
		var s := String(v).strip_edges()
		if Color.html_is_valid(s):
			return Color.html(s)
	return null


func set_position(o: PSWorld.PSObject, p: Vector3) -> void:
	o.node.global_position = p
	if o.node is RigidBody3D:
		(o.node as RigidBody3D).linear_velocity = Vector3.ZERO


func set_color(o: PSWorld.PSObject, c: Color) -> void:
	if not o.data.has("mat"):
		return
	var mat: Dictionary = o.data["mat"]
	mat["color"] = PSData.color_to_arr(c)
	if o.visual is MeshInstance3D:
		if o.type == "water":
			(o.visual as MeshInstance3D).material_override = PSPrimitives.get_water_material(mat)
		else:
			var tex: Texture2D = world.assets.get_texture(String(mat.get("tex", ""))) if world.assets else null
			(o.visual as MeshInstance3D).material_override = PSPrimitives.make_material(mat, tex)


func is_solid(o: PSWorld.PSObject) -> bool:
	if o.node is CollisionObject3D:
		return (o.node as CollisionObject3D).collision_layer != 0
	return false


func set_solid(o: PSWorld.PSObject, on: bool) -> void:
	if o.node is CollisionObject3D:
		var co := o.node as CollisionObject3D
		co.collision_layer = PSWorld.LAYER_WORLD if on else 0
		co.collision_mask = (PSWorld.LAYER_WORLD | PSWorld.LAYER_PLAYER) if on else 0


func get_gravity() -> float:
	return float(PhysicsServer3D.area_get_param(get_viewport().world_3d.space, PhysicsServer3D.AREA_PARAM_GRAVITY))


func set_gravity(g: float) -> void:
	PhysicsServer3D.area_set_param(get_viewport().world_3d.space, PhysicsServer3D.AREA_PARAM_GRAVITY, g)
	if player:
		player.gravity = g


func obj_move(id: String, a: Array, it: PSLuaInterp) -> Variant:
	var o := get_obj(id)
	if o == null:
		return null
	var d := it.arg_vec_or_xyz(a, 0, "move")
	if it.is_halted():
		return null
	set_position(o, o.node.global_position + d)
	return null


func obj_rotate(id: String, a: Array, it: PSLuaInterp) -> Variant:
	var o := get_obj(id)
	if o == null:
		return null
	var d := it.arg_vec_or_xyz(a, 0, "rotate")
	if it.is_halted():
		return null
	var b := o.node.global_basis
	b = Basis(Vector3.UP, deg_to_rad(d.y)) * Basis(Vector3.RIGHT, deg_to_rad(d.x)) * Basis(Vector3.BACK, deg_to_rad(d.z)) * b
	o.node.global_basis = b.orthonormalized()
	return null


func obj_destroy(id: String) -> Variant:
	if world.has_object(id) and not _pending_destroy.has(id):
		_pending_destroy.append(id)
	return null


func _flush_destroy() -> void:
	if _pending_destroy.is_empty():
		return
	var ids := _pending_destroy.duplicate()
	_pending_destroy.clear()
	for id in ids:
		if world.has_object(id):
			for sub in world.get_subtree_data(id):
				_touch.erase(String(sub["id"]))
			world.remove_object(id)
	for inst in instances:
		if inst.obj_id != "" and not world.has_object(inst.obj_id):
			inst.alive = false


func obj_clone(id: String, it: PSLuaInterp) -> Variant:
	if get_obj(id) == null:
		return null
	var sub := world.get_subtree_data(id)
	if _created + sub.size() > MAX_CREATED:
		it.rt_error("limite de %d objetos criados por scripts atingido" % MAX_CREATED)
		return null
	_created += sub.size()
	var map := {}
	for d in sub:
		map[d["id"]] = App.new_id("o")
	var new_root := ""
	for d in sub:
		var c: Dictionary = d.duplicate(true)
		c["id"] = map[d["id"]]
		if map.has(c["parent"]):
			c["parent"] = map[c["parent"]]
		else:
			new_root = c["id"]
		world.add_object(c)
	# Scripts dos objetos copiados também passam a rodar.
	for d in sub:
		var sid := String(d.get("script", ""))
		if sid != "" and _scripts.has(sid) and _scripts[sid]["enabled"]:
			var inst := _create_instance(sid, map[d["id"]])
			if inst:
				_run_chunk(inst)
				inst.has_update = inst.env.get("on_update") != null
				_fire(inst, "on_start", [], STEPS_START)
				if inst.alive and (inst.env.get("on_touch") != null or inst.env.get("on_leave") != null):
					_add_touch_areas(inst.obj_id)
	return ref(new_root)


func obj_impulse(id: String, a: Array, it: PSLuaInterp) -> Variant:
	var o := get_obj(id)
	if o == null:
		return null
	var v := it.arg_vec_or_xyz(a, 0, "applyImpulse")
	if o.node is RigidBody3D:
		(o.node as RigidBody3D).apply_central_impulse(v)
	return null


func obj_children(id: String) -> Variant:
	var t := PSLua.Table.new()
	var i := 1
	for c in world.get_children_ids(id):
		if not _pending_destroy.has(c):
			t.set_v(float(i), ref(c))
			i += 1
	return t


func obj_find(id: String, child_name: String) -> Variant:
	for sub in world.get_subtree_data(id):
		if String(sub["id"]) != id and String(sub.get("name", "")) == child_name and not _pending_destroy.has(String(sub["id"])):
			return ref(String(sub["id"]))
	return null


func obj_look_at(id: String, target: Vector3) -> Variant:
	var o := get_obj(id)
	if o and o.node.global_position.distance_to(target) > 0.001:
		var up := Vector3.UP if absf((target - o.node.global_position).normalized().y) < 0.99 else Vector3.BACK
		o.node.look_at(target, up)
	return null


func attr_get(id: String, key: String) -> Variant:
	return _attrs.get(id, {}).get(key)


func attr_set(id: String, key: String, value: Variant, it: PSLuaInterp) -> Variant:
	if not (value == null or typeof(value) in [TYPE_BOOL, TYPE_FLOAT, TYPE_INT, TYPE_STRING] or value is PSLua.Vec3 or value is PSLua.ColorV):
		it.rt_error("set() só guarda números, textos, booleanos, vetores e cores")
		return null
	if not _attrs.has(id):
		_attrs[id] = {}
	if value == null:
		_attrs[id].erase(key)
	else:
		_attrs[id][key] = value
	return null


func world_find_all(obj_name: String) -> Variant:
	var t := PSLua.Table.new()
	var i := 1
	for id in world.objects:
		if String(world.objects[id].data.get("name", "")) == obj_name and not _pending_destroy.has(id):
			t.set_v(float(i), ref(id))
			i += 1
	return t


func world_objects() -> Variant:
	var t := PSLua.Table.new()
	var i := 1
	for id in world.objects:
		if not _pending_destroy.has(id):
			t.set_v(float(i), ref(id))
			i += 1
	return t


## world.create("box", vec(0, 5, 0)) ou world.create("sphere", x, y, z, "dynamic")
func world_create(a: Array, it: PSLuaInterp) -> Variant:
	var shape := it.arg_str(a, 0, "world.create")
	if it.is_halted():
		return null
	if not PSData.SHAPES.has(shape):
		it.rt_error("forma desconhecida '%s' (use: %s)" % [shape, ", ".join(PSData.SHAPES)])
		return null
	if _created >= MAX_CREATED:
		it.rt_error("limite de %d objetos criados por scripts atingido" % MAX_CREATED)
		return null
	var pos := Vector3.ZERO
	if a.size() > 1 and not (typeof(a[1]) == TYPE_STRING):
		pos = it.arg_vec_or_xyz(a, 1, "world.create")
	var phys := "static"
	for i in range(1, a.size()):
		if typeof(a[i]) == TYPE_STRING and PSData.PHYS_MODES.has(a[i]):
			phys = a[i]
	if it.is_halted():
		return null
	_created += 1
	var d := PSData.new_object("part", {"shape": shape})
	d["id"] = App.new_id("o")
	d["pos"] = PSData.v3_to_arr(pos)
	d["phys"]["mode"] = phys
	var o := world.add_object(d)
	return ref(o.id) if o else null
