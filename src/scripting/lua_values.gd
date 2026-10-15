class_name PSLua
extends RefCounted
## Tipos de valor da linguagem de scripts.
##
## nil -> null, boolean -> bool, number -> float, string -> String.
## Os demais tipos são as classes abaixo.


## Tabela (dicionário + parte de array implícita nas chaves 1..n).
class Table:
	extends RefCounted
	var hash := {}
	var _len_hint := 0

	func get_v(k: Variant) -> Variant:
		if typeof(k) == TYPE_INT:
			k = float(k)
		return hash.get(k)

	func set_v(k: Variant, v: Variant) -> void:
		if typeof(k) == TYPE_INT:
			k = float(k)
		if v == null:
			hash.erase(k)
		else:
			hash[k] = v

	func length() -> int:
		var n := _len_hint
		if n > 0 and not hash.has(float(n)):
			while n > 0 and not hash.has(float(n)):
				n -= 1
		while hash.has(float(n + 1)):
			n += 1
		_len_hint = n
		return n

	func size() -> int:
		return hash.size()


## Função definida no script (closure).
class Function:
	extends RefCounted
	var params: Array = []
	var vararg := false
	var body: Array = []
	var scope: Array          # [vars, pai]
	var name := "função"
	var line := 0


## Função nativa (biblioteca padrão ou API do jogo).
## `fn` recebe (args: Array) e devolve um valor ou um Multi.
class Native:
	extends RefCounted
	var fn: Callable
	var name := ""

	func _init(p_name: String, p_fn: Callable) -> void:
		name = p_name
		fn = p_fn


## Vários valores de retorno.
class Multi:
	extends RefCounted
	var values: Array = []

	func _init(v: Array = []) -> void:
		values = v


## Base para objetos expostos pelo jogo (vetores, objetos do mundo...).
class Userdata:
	extends RefCounted

	func lua_type() -> String:
		return "userdata"

	## Retorna o valor do campo. `interp` permite criar funções nativas.
	func lua_get(_interp: Object, _key: Variant) -> Variant:
		return null

	## Retorna "" se deu certo, ou a mensagem de erro.
	func lua_set(_interp: Object, key: Variant, _value: Variant) -> String:
		return "o campo '%s' não pode ser alterado" % str(key)

	func lua_tostring() -> String:
		return lua_type()

	func lua_eq(other: Variant) -> bool:
		return is_same(self, other)


## Vetor 3D imutável: vec(x, y, z).
class Vec3:
	extends Userdata
	var v := Vector3.ZERO

	func _init(p: Vector3 = Vector3.ZERO) -> void:
		v = p

	func lua_type() -> String:
		return "vector"

	func lua_tostring() -> String:
		return "vec(%s, %s, %s)" % [PSLua.num_str(v.x), PSLua.num_str(v.y), PSLua.num_str(v.z)]

	func lua_eq(other: Variant) -> bool:
		return other is Vec3 and (other as Vec3).v.is_equal_approx(v)

	func lua_get(interp: Object, key: Variant) -> Variant:
		match key:
			"x":
				return v.x
			"y":
				return v.y
			"z":
				return v.z
			"length":
				return interp.native("length", func(a): return (a[0] as Vec3).v.length())
			"normalized":
				return interp.native("normalized", func(a): return Vec3.new((a[0] as Vec3).v.normalized()))
			"dot":
				return interp.native("dot", func(a): return (a[0] as Vec3).v.dot(interp.arg_vec(a, 1, "dot")))
			"cross":
				return interp.native("cross", func(a): return Vec3.new((a[0] as Vec3).v.cross(interp.arg_vec(a, 1, "cross"))))
			"distance":
				return interp.native("distance", func(a): return (a[0] as Vec3).v.distance_to(interp.arg_vec(a, 1, "distance")))
			"lerp":
				return interp.native("lerp", func(a): return Vec3.new((a[0] as Vec3).v.lerp(interp.arg_vec(a, 1, "lerp"), interp.arg_num(a, 2, "lerp"))))
		return null


## Cor: rgb(r, g, b) com componentes de 0 a 1.
class ColorV:
	extends Userdata
	var c := Color.WHITE

	func _init(p: Color = Color.WHITE) -> void:
		c = p

	func lua_type() -> String:
		return "color"

	func lua_tostring() -> String:
		return "rgb(%s, %s, %s)" % [PSLua.num_str(c.r), PSLua.num_str(c.g), PSLua.num_str(c.b)]

	func lua_eq(other: Variant) -> bool:
		return other is ColorV and (other as ColorV).c.is_equal_approx(c)

	func lua_get(_interp: Object, key: Variant) -> Variant:
		match key:
			"r":
				return c.r
			"g":
				return c.g
			"b":
				return c.b
			"a":
				return c.a
		return null


static func num_str(x: float) -> String:
	if is_nan(x):
		return "nan"
	if is_inf(x):
		return "inf" if x > 0 else "-inf"
	if x == floorf(x) and absf(x) < 1e15:
		return str(int(x))
	var s := String.num(x, 10)
	return s


static func type_name(v: Variant) -> String:
	match typeof(v):
		TYPE_NIL:
			return "nil"
		TYPE_BOOL:
			return "boolean"
		TYPE_FLOAT, TYPE_INT:
			return "number"
		TYPE_STRING, TYPE_STRING_NAME:
			return "string"
	if v is Table:
		return "table"
	if v is Function or v is Native:
		return "function"
	if v is Userdata:
		return (v as Userdata).lua_type()
	return "userdata"
