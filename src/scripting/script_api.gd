class_name PSScriptAPI
extends RefCounted
## Objetos da API do jogo vistos pelos scripts (documentados em docs/SCRIPTS.md).
## Tudo aqui age somente sobre o mundo do modo de teste.
##
## Métodos funcionam com ":" ou "." (obj:move(1,0,0) e obj.move(1,0,0)).


## Remove o próprio objeto do início dos argumentos (chamada com ":").
static func strip_self(a: Array, me: Object) -> Array:
	if a.size() > 0 and a[0] is PSLua.Userdata and (a[0] as PSLua.Userdata).lua_eq(me):
		return a.slice(1)
	return a


## Referência a um objeto do mundo.
class ObjRef:
	extends PSLua.Userdata
	var rt: Object      # PSScriptRuntime
	var id := ""

	func _init(p_rt: Object, p_id: String) -> void:
		rt = p_rt
		id = p_id

	func lua_type() -> String:
		return "object"

	func lua_tostring() -> String:
		var o = rt.get_obj(id)
		return "objeto(%s)" % (String(o.data.get("name", id)) if o else "removido")

	func lua_eq(other: Variant) -> bool:
		return other is ObjRef and (other as ObjRef).id == id

	func _m(interp: Object, mname: String, fn: Callable) -> PSLua.Native:
		var me := self
		return interp.native(mname, func(a): return fn.call(PSScriptAPI.strip_self(a, me)))

	func lua_get(interp: Object, key: Variant) -> Variant:
		var o = rt.get_obj(id)
		if key == "exists":
			return o != null
		if o == null:
			interp.rt_error("o objeto foi removido do mundo")
			return null
		match key:
			"name":
				return String(o.data.get("name", ""))
			"id":
				return id
			"type":
				return o.type
			"position":
				return PSLua.Vec3.new(o.node.global_position)
			"rotation":
				return PSLua.Vec3.new(o.node.global_rotation_degrees)
			"size":
				return PSLua.Vec3.new(PSData.arr_to_v3(o.data.get("size"), Vector3.ONE))
			"color":
				var mat: Dictionary = o.data.get("mat", {})
				return PSLua.ColorV.new(PSData.arr_to_color(mat.get("color"), Color.WHITE))
			"visible":
				return o.visual.visible if o.visual else bool(o.data.get("visible", true))
			"solid":
				return rt.is_solid(o)
			"velocity":
				if o.node is RigidBody3D:
					return PSLua.Vec3.new((o.node as RigidBody3D).linear_velocity)
				return PSLua.Vec3.new(Vector3.ZERO)
			"parent":
				var pid: String = rt.world.get_parent_id(id)
				return rt.ref(pid) if pid != "" else null
			"move":
				return _m(interp, "move", func(a): return rt.obj_move(id, a, interp))
			"rotate":
				return _m(interp, "rotate", func(a): return rt.obj_rotate(id, a, interp))
			"destroy":
				return _m(interp, "destroy", func(_a): return rt.obj_destroy(id))
			"clone":
				return _m(interp, "clone", func(_a): return rt.obj_clone(id, interp))
			"applyImpulse":
				return _m(interp, "applyImpulse", func(a): return rt.obj_impulse(id, a, interp))
			"children":
				return _m(interp, "children", func(_a): return rt.obj_children(id))
			"find":
				return _m(interp, "find", func(a): return rt.obj_find(id, interp.arg_str(a, 0, "find")))
			"lookAt":
				return _m(interp, "lookAt", func(a): return rt.obj_look_at(id, interp.arg_vec(a, 0, "lookAt")))
			"get":
				return _m(interp, "get", func(a): return rt.attr_get(id, interp.arg_str(a, 0, "get")))
			"set":
				return _m(interp, "set", func(a): return rt.attr_set(id, interp.arg_str(a, 0, "set"), a[1] if a.size() > 1 else null, interp))
		return null

	func lua_set(_interp: Object, key: Variant, value: Variant) -> String:
		var o = rt.get_obj(id)
		if o == null:
			return "o objeto foi removido do mundo"
		match key:
			"name":
				if typeof(value) != TYPE_STRING:
					return "name precisa ser um texto"
				o.data["name"] = String(value).substr(0, PSData.MAX_NAME)
				return ""
			"position":
				if not (value is PSLua.Vec3):
					return "position precisa ser um vec(x, y, z)"
				rt.set_position(o, (value as PSLua.Vec3).v)
				return ""
			"rotation":
				if not (value is PSLua.Vec3):
					return "rotation precisa ser um vec(x, y, z) em graus"
				o.node.global_rotation_degrees = (value as PSLua.Vec3).v
				return ""
			"size":
				if not (value is PSLua.Vec3):
					return "size precisa ser um vec(x, y, z)"
				if not o.data.has("size"):
					return "este objeto não tem tamanho"
				rt.world.set_object_size(id, (value as PSLua.Vec3).v.abs().clamp(Vector3.ONE * PSData.MIN_SIZE, Vector3.ONE * PSData.MAX_SIZE))
				rt.refresh_touch_area(id)
				return ""
			"color":
				var c: Variant = rt.to_color(value)
				if c == null:
					return "color precisa ser rgb(r, g, b) ou um texto como \"#ff8800\""
				rt.set_color(o, c)
				return ""
			"visible":
				if typeof(value) != TYPE_BOOL:
					return "visible precisa ser true ou false"
				if o.visual:
					o.visual.visible = value
				return ""
			"solid":
				if typeof(value) != TYPE_BOOL:
					return "solid precisa ser true ou false"
				rt.set_solid(o, value)
				return ""
			"velocity":
				if not (value is PSLua.Vec3):
					return "velocity precisa ser um vec(x, y, z)"
				if o.node is RigidBody3D:
					(o.node as RigidBody3D).linear_velocity = (value as PSLua.Vec3).v
					return ""
				return "só objetos dinâmicos têm velocidade"
		return "o campo '%s' não existe ou não pode ser alterado" % str(key)


## O jogador.
class PlayerRef:
	extends PSLua.Userdata
	var rt: Object

	func _init(p_rt: Object) -> void:
		rt = p_rt

	func lua_type() -> String:
		return "player"

	func lua_tostring() -> String:
		return "jogador"

	func lua_eq(other: Variant) -> bool:
		return other is PlayerRef

	func lua_get(interp: Object, key: Variant) -> Variant:
		var p: PSPlayer = rt.player
		if p == null:
			return null
		var me := self
		match key:
			"position":
				return PSLua.Vec3.new(p.global_position)
			"velocity":
				return PSLua.Vec3.new(p.velocity)
			"speed":
				return p.walk_speed
			"jumpPower":
				return p.jump_velocity
			"onGround":
				return p.is_on_floor()
			"inWater":
				return p.in_water > 0
			"cameraMode":
				return p.camera_mode
			"respawn":
				return interp.native("respawn", func(_a):
					p.place_at_spawn()
					return null)
			"setSpawn":
				return interp.native("setSpawn", func(a):
					var args := PSScriptAPI.strip_self(a, me)
					p.spawn_transform = Transform3D(p.spawn_transform.basis, interp.arg_vec(args, 0, "setSpawn"))
					return null)
		return null

	func lua_set(interp: Object, key: Variant, value: Variant) -> String:
		var p: PSPlayer = rt.player
		if p == null:
			return "jogador indisponível"
		match key:
			"position":
				if not (value is PSLua.Vec3):
					return "position precisa ser um vec(x, y, z)"
				p.global_position = (value as PSLua.Vec3).v
				p.velocity = Vector3.ZERO
				return ""
			"velocity":
				if not (value is PSLua.Vec3):
					return "velocity precisa ser um vec(x, y, z)"
				p.velocity = (value as PSLua.Vec3).v
				return ""
			"speed":
				var n = interp._tonum(value)
				if n == null:
					return "speed precisa ser um número"
				p.walk_speed = clampf(n, 0.0, 100.0)
				return ""
			"jumpPower":
				var n = interp._tonum(value)
				if n == null:
					return "jumpPower precisa ser um número"
				p.jump_velocity = clampf(n, 0.0, 100.0)
				return ""
			"cameraMode":
				if not (value in ["first", "third"]):
					return "cameraMode precisa ser \"first\" ou \"third\""
				p.set_camera_mode(value)
				return ""
		return "o campo '%s' do jogador não pode ser alterado" % str(key)


## Funções do mundo.
class WorldRef:
	extends PSLua.Userdata
	var rt: Object

	func _init(p_rt: Object) -> void:
		rt = p_rt

	func lua_type() -> String:
		return "world"

	func lua_tostring() -> String:
		return "mundo"

	func lua_eq(other: Variant) -> bool:
		return other is WorldRef

	func lua_get(interp: Object, key: Variant) -> Variant:
		var me := self
		match key:
			"gravity":
				return rt.get_gravity()
			"time":
				return rt.time
			"find":
				return interp.native("world.find", func(a):
					var id: String = rt.world.find_by_name(interp.arg_str(PSScriptAPI.strip_self(a, me), 0, "world.find"))
					return rt.ref(id) if id != "" else null)
			"findAll":
				return interp.native("world.findAll", func(a): return rt.world_find_all(interp.arg_str(PSScriptAPI.strip_self(a, me), 0, "world.findAll")))
			"objects":
				return interp.native("world.objects", func(_a): return rt.world_objects())
			"create":
				return interp.native("world.create", func(a): return rt.world_create(PSScriptAPI.strip_self(a, me), interp))
		return null

	func lua_set(interp: Object, key: Variant, value: Variant) -> String:
		if key == "gravity":
			var n = interp._tonum(value)
			if n == null:
				return "gravity precisa ser um número"
			rt.set_gravity(clampf(n, -100.0, 100.0))
			return ""
		return "o campo '%s' do mundo não pode ser alterado" % str(key)


## Interface na tela durante o jogo.
class UiRef:
	extends PSLua.Userdata
	var rt: Object

	func _init(p_rt: Object) -> void:
		rt = p_rt

	func lua_type() -> String:
		return "ui"

	func lua_eq(other: Variant) -> bool:
		return other is UiRef

	func lua_get(interp: Object, key: Variant) -> Variant:
		var me := self
		match key:
			"message":
				return interp.native("ui.message", func(a):
					var args := PSScriptAPI.strip_self(a, me)
					rt.session_message(interp.tostr(args[0]) if args.size() > 0 else "", interp.opt_num(args, 1, 3.0))
					return null)
			"text":
				return interp.native("ui.text", func(a):
					var args := PSScriptAPI.strip_self(a, me)
					rt.session_text(interp.tostr(args[0]) if args.size() > 0 and args[0] != null else "")
					return null)
		return null
