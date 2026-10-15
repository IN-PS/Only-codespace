class_name PSLuaInterp
extends RefCounted
## Interpretador da linguagem de scripts (estilo Lua), executado em ambiente isolado.
##
## Segurança:
##  - O script só enxerga as funções registradas aqui e na API do jogo:
##    não existe acesso a arquivos, rede, sistema operacional ou ao motor.
##  - Cada execução tem um limite de instruções (evita loops infinitos travarem o app),
##    de profundidade de chamadas, de tamanho de tabelas e de textos.
##  - Erros nunca derrubam o aplicativo: viram mensagens no console.

const P := preload("res://src/scripting/lua_parser.gd")

const MAX_CALL_DEPTH := 64
const MAX_TABLE_SIZE := 100000
const MAX_STRING := 1000000

var genv: Dictionary = {}
var max_steps := 200000
var chunk_name := "script"
var print_handler: Callable

var _steps := 0
var _depth := 0
var _halt := false
var _fatal := false
var _err := ""
var _err_line := 0
var _flow := 0          # 0 normal, 1 break, 2 return
var _ret: Array = []
var _cur_line := 0
var _traceback: Array = []
var _rng := RandomNumberGenerator.new()
var _libs := {}


func _init() -> void:
	_rng.randomize()
	_build_stdlib()


# --------------------------------------------------------------------------
# API para o hospedeiro
# --------------------------------------------------------------------------

## Cria um ambiente global novo com a biblioteca padrão (cópias isoladas).
func new_env() -> Dictionary:
	var env := {}
	for k in _libs:
		var v = _libs[k]
		if v is PSLua.Table:
			var t := PSLua.Table.new()
			t.hash = (v as PSLua.Table).hash.duplicate()
			env[k] = t
		else:
			env[k] = v
	env["_G"] = null
	return env


## Compila o código. Retorna {"ok", "fn"} ou {"ok": false, "error", "line"}.
func compile(code: String, p_name := "script", env: Dictionary = {}) -> Dictionary:
	var res := PSLuaParser.parse(code)
	if not res["ok"]:
		return {"ok": false, "error": "%s:%d: %s" % [p_name, res["line"], res["error"]], "line": res["line"], "message": res["error"]}
	var f := PSLua.Function.new()
	f.body = res["ast"]
	f.params = []
	f.vararg = true
	f.scope = [{}, null]
	f.name = p_name
	f.set_meta("env", env if not env.is_empty() else genv)
	f.set_meta("chunk", p_name)
	_track(f)
	return {"ok": true, "fn": f}


## Guarda referências fracas às funções criadas para poder quebrar ciclos
## (closure -> escopo -> closure) quando o teste termina.
var _functions: Array = []


func _track(f: PSLua.Function) -> void:
	_functions.append(weakref(f))
	if _functions.size() > 4000:
		var alive: Array = []
		for w in _functions:
			if w.get_ref() != null:
				alive.append(w)
		_functions = alive


## Libera tudo que o interpretador criou (evita vazamento de memória entre testes).
func dispose() -> void:
	for w in _functions:
		var f = w.get_ref()
		if f:
			f.scope = []
			f.body = []
			f.remove_meta("env")
	_functions.clear()
	genv.clear()
	_ret = []


## Chama uma função do script com limite de instruções novo.
## Retorna {"ok": true, "values": Array} ou {"ok": false, "error": String}.
## É reentrante: pode ser chamada de dentro de uma função nativa.
func call_protected(f: Variant, args: Array = [], steps := -1) -> Dictionary:
	var saved := [_steps, _depth, _halt, _fatal, _err, _flow, _ret, _cur_line, _traceback, genv, chunk_name, max_steps, _err_line]
	_steps = 0
	_depth = 0
	_halt = false
	_fatal = false
	_err = ""
	_flow = 0
	_ret = []
	_traceback = []
	if steps > 0:
		max_steps = steps
	var vals := _call_value(f, args, _cur_line)
	var result: Dictionary
	if _halt:
		var msg := _err
		if not _traceback.is_empty():
			msg += "\n  em: " + " ← ".join(_traceback.slice(0, 6))
		result = {"ok": false, "error": msg, "fatal": _fatal, "line": _err_line}
	else:
		result = {"ok": true, "values": vals}
	_steps = saved[0]
	_depth = saved[1]
	_halt = saved[2]
	_fatal = saved[3]
	_err = saved[4]
	_flow = saved[5]
	_ret = saved[6]
	_cur_line = saved[7]
	_traceback = saved[8]
	genv = saved[9]
	chunk_name = saved[10]
	max_steps = saved[11]
	_err_line = saved[12]
	return result


func native(p_name: String, fn: Callable) -> PSLua.Native:
	return PSLua.Native.new(p_name, fn)


## Erro gerado por função nativa (aparece com a linha do script).
func rt_error(msg: String) -> void:
	_error(_cur_line, msg)


func is_halted() -> bool:
	return _halt


# --------------------------------------------------------------------------
# Erros e utilidades
# --------------------------------------------------------------------------

func _error(line: int, msg: String, fatal := false) -> void:
	if _halt:
		return
	_halt = true
	_fatal = fatal
	_err_line = line
	_err = "%s:%d: %s" % [chunk_name, line, msg]


func _truthy(v: Variant) -> bool:
	return not (v == null or (typeof(v) == TYPE_BOOL and v == false))


func tostr(v: Variant) -> String:
	match typeof(v):
		TYPE_NIL:
			return "nil"
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_FLOAT, TYPE_INT:
			return PSLua.num_str(float(v))
		TYPE_STRING, TYPE_STRING_NAME:
			return String(v)
	if v is PSLua.Table:
		return "table: %x" % (v as Object).get_instance_id()
	if v is PSLua.Function:
		return "function: %s" % (v as PSLua.Function).name
	if v is PSLua.Native:
		return "function: builtin %s" % (v as PSLua.Native).name
	if v is PSLua.Userdata:
		return (v as PSLua.Userdata).lua_tostring()
	return str(v)


func _type(v: Variant) -> String:
	return PSLua.type_name(v)


func _tonum(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return v
		TYPE_INT:
			return float(v)
		TYPE_STRING:
			var s := String(v).strip_edges()
			if s.is_valid_float():
				return s.to_float()
			if s.begins_with("0x") and s.substr(2).is_valid_hex_number():
				return float(s.substr(2).hex_to_int())
	return null


func _norm(v: Variant) -> Variant:
	if typeof(v) == TYPE_INT:
		return float(v)
	if typeof(v) == TYPE_STRING_NAME:
		return String(v)
	return v


# --------------------------------------------------------------------------
# Execução
# --------------------------------------------------------------------------

func _find_scope(scope: Array, var_name: String) -> Variant:
	var s = scope
	while s != null:
		if (s[0] as Dictionary).has(var_name):
			return s
		s = s[1]
	return null


func _exec_block(block: Array, scope: Array) -> void:
	var sc := [{}, scope] if block[0] else scope
	for i in range(1, block.size()):
		_exec(block[i], sc)
		if _halt or _flow != 0:
			return


func _exec(s: Array, scope: Array) -> void:
	_steps += 1
	if _steps > max_steps:
		_error(int(s[1]), "o script passou do limite de %d instruções nesta execução (possível loop infinito)" % max_steps, true)
		return
	_cur_line = int(s[1])
	match int(s[0]):
		P.S_LOCAL:
			var names: Array = s[2]
			var vals := _eval_list(s[3], scope, names.size())
			if _halt:
				return
			var vars: Dictionary = scope[0]
			for i in names.size():
				vars[names[i]] = vals[i] if i < vals.size() else null
		P.S_ASSIGN:
			_exec_assign(s, scope)
		P.S_CALL:
			_eval_multi(s[2], scope)
		P.S_DO:
			_exec_block(s[2], scope)
		P.S_WHILE:
			while true:
				var c = _eval(s[2], scope)
				if _halt or not _truthy(c):
					return
				_exec_block(s[3], scope)
				if _halt:
					return
				if _flow == 1:
					_flow = 0
					return
				if _flow == 2:
					return
				_steps += 1
				if _steps > max_steps:
					_error(int(s[1]), "o script passou do limite de %d instruções nesta execução (possível loop infinito)" % max_steps, true)
					return
		P.S_REPEAT:
			while true:
				# O 'until' enxerga as locais do corpo.
				var body: Array = s[2]
				var sc := [{}, scope]
				for i in range(1, body.size()):
					_exec(body[i], sc)
					if _halt or _flow != 0:
						break
				if _halt:
					return
				if _flow == 1:
					_flow = 0
					return
				if _flow == 2:
					return
				var c = _eval(s[3], sc)
				if _halt or _truthy(c):
					return
		P.S_IF:
			var conds: Array = s[2]
			for i in conds.size():
				var c = _eval(conds[i], scope)
				if _halt:
					return
				if _truthy(c):
					_exec_block(s[3][i], scope)
					return
			if s[4] != null:
				_exec_block(s[4], scope)
		P.S_NUMFOR:
			_exec_numfor(s, scope)
		P.S_GENFOR:
			_exec_genfor(s, scope)
		P.S_FUNC:
			var f := _make_function(s[3], scope)
			_assign_to(s[2], f, scope)
		P.S_LOCALFUNC:
			var vars: Dictionary = scope[0]
			vars[s[2]] = null
			vars[s[2]] = _make_function(s[3], scope)
		P.S_RETURN:
			var exprs: Array = s[2]
			if exprs.size() == 1 and (exprs[0][0] == P.E_CALL or exprs[0][0] == P.E_METHOD):
				_ret = _eval_multi(exprs[0], scope)
			else:
				_ret = _eval_list(exprs, scope, -1)
			if not _halt:
				_flow = 2
		P.S_BREAK:
			_flow = 1


func _exec_assign(s: Array, scope: Array) -> void:
	var targets: Array = s[2]
	# Avalia os destinos (objeto e chave) antes dos valores, como em Lua.
	var prepared: Array = []
	for t in targets:
		if t[0] == P.E_INDEX:
			var obj = _eval(t[2], scope)
			var key = _eval(t[3], scope)
			prepared.append([obj, key])
		else:
			prepared.append(null)
		if _halt:
			return
	var vals := _eval_list(s[3], scope, targets.size())
	if _halt:
		return
	for i in targets.size():
		var v = vals[i] if i < vals.size() else null
		if prepared[i] == null:
			_set_name(targets[i][2], v, scope)
		else:
			_setindex(prepared[i][0], prepared[i][1], v, int(s[1]))
		if _halt:
			return


func _assign_to(target: Array, value: Variant, scope: Array) -> void:
	if target[0] == P.E_NAME:
		_set_name(target[2], value, scope)
	else:
		var obj = _eval(target[2], scope)
		var key = _eval(target[3], scope)
		if not _halt:
			_setindex(obj, key, value, int(target[1]))


func _set_name(var_name: String, value: Variant, scope: Array) -> void:
	var sc = _find_scope(scope, var_name)
	if sc != null:
		sc[0][var_name] = value
	else:
		if value == null:
			genv.erase(var_name)
		else:
			genv[var_name] = value


func _exec_numfor(s: Array, scope: Array) -> void:
	var line := int(s[1])
	var a = _tonum(_eval(s[3], scope))
	var b = _tonum(_eval(s[4], scope))
	var st = 1.0 if s[5] == null else _tonum(_eval(s[5], scope))
	if _halt:
		return
	if a == null or b == null or st == null:
		_error(line, "os limites do 'for' precisam ser números")
		return
	if st == 0.0:
		_error(line, "o passo do 'for' não pode ser zero")
		return
	var i: float = a
	var stop: float = b
	var step: float = st
	var var_name: String = s[2]
	var body: Array = s[6]
	while (step > 0.0 and i <= stop) or (step < 0.0 and i >= stop):
		var sc := [{var_name: i}, scope]
		_exec_block(body, sc)
		if _halt:
			return
		if _flow == 1:
			_flow = 0
			return
		if _flow == 2:
			return
		i += step
		_steps += 1
		if _steps > max_steps:
			_error(line, "o script passou do limite de %d instruções nesta execução (possível loop infinito)" % max_steps, true)
			return


func _exec_genfor(s: Array, scope: Array) -> void:
	var line := int(s[1])
	var init := _eval_list(s[3], scope, 3)
	if _halt:
		return
	var f = init[0]
	var state = init[1]
	var ctrl = init[2]
	var names: Array = s[2]
	var body: Array = s[4]
	while true:
		var r := _call_value(f, [state, ctrl], line)
		if _halt:
			return
		var first = r[0] if r.size() > 0 else null
		if first == null:
			return
		ctrl = first
		var vars := {}
		for i in names.size():
			vars[names[i]] = r[i] if i < r.size() else null
		_exec_block(body, [vars, scope])
		if _halt:
			return
		if _flow == 1:
			_flow = 0
			return
		if _flow == 2:
			return
		_steps += 1
		if _steps > max_steps:
			_error(line, "o script passou do limite de %d instruções nesta execução (possível loop infinito)" % max_steps, true)
			return


func _make_function(e: Array, scope: Array) -> PSLua.Function:
	var f := PSLua.Function.new()
	f.params = e[2]
	f.vararg = e[3]
	f.body = e[4]
	f.name = e[5]
	f.line = int(e[1])
	f.scope = scope
	f.set_meta("env", genv)
	f.set_meta("chunk", chunk_name)
	_track(f)
	return f


# --------------------------------------------------------------------------
# Chamadas
# --------------------------------------------------------------------------

func _call_value(f: Variant, args: Array, line: int) -> Array:
	if _halt:
		return []
	if f is PSLua.Function:
		return _call_lua(f, args, line)
	if f is PSLua.Native:
		var n: PSLua.Native = f
		_steps += 1
		var saved_line := _cur_line
		_cur_line = line
		var r = n.fn.call(args)
		_cur_line = saved_line
		if _halt:
			if _traceback.size() < 8:
				_traceback.append(n.name)
			return []
		if r is PSLua.Multi:
			var out: Array = []
			for v in (r as PSLua.Multi).values:
				out.append(_norm(v))
			return out
		# Função nativa sem retorno devolve um nil (como tonumber("x") em Lua).
		return [_norm(r)]
	_error(line, "tentativa de chamar um valor %s" % _type(f))
	return []


func _call_lua(f: PSLua.Function, args: Array, line: int) -> Array:
	_depth += 1
	if _depth > MAX_CALL_DEPTH:
		_depth -= 1
		_error(line, "chamadas aninhadas demais (recursão infinita?)", true)
		return []
	var vars := {}
	var params: Array = f.params
	for i in params.size():
		vars[params[i]] = args[i] if i < args.size() else null
	if f.vararg:
		vars["..."] = args.slice(params.size()) if args.size() > params.size() else []
	var saved_env := genv
	var saved_chunk := chunk_name
	var env = f.get_meta("env", null)
	if env is Dictionary:
		genv = env
	chunk_name = String(f.get_meta("chunk", chunk_name))
	var saved_line := _cur_line
	if f.body.is_empty():
		_error(line, "função descartada (o teste foi encerrado)")
	else:
		_exec_block(f.body, [vars, f.scope])
	genv = saved_env
	_cur_line = saved_line
	chunk_name = saved_chunk
	_depth -= 1
	if _halt:
		if _traceback.size() < 8:
			_traceback.append("%s (linha %d)" % [f.name, f.line])
		return []
	if _flow == 2:
		_flow = 0
		var r := _ret
		_ret = []
		return r
	_flow = 0
	return []


# --------------------------------------------------------------------------
# Expressões
# --------------------------------------------------------------------------

## Avalia uma lista de expressões; a última pode expandir para vários valores.
## `want` = quantidade desejada (-1 = todas).
func _eval_list(exprs: Array, scope: Array, want: int) -> Array:
	var out: Array = []
	var n := exprs.size()
	for i in n:
		var e: Array = exprs[i]
		if i == n - 1 and (e[0] == P.E_CALL or e[0] == P.E_METHOD or e[0] == P.E_VARARG):
			out.append_array(_eval_multi(e, scope))
		else:
			out.append(_eval(e, scope))
		if _halt:
			return out
	if want >= 0:
		while out.size() < want:
			out.append(null)
	return out


func _eval_multi(e: Array, scope: Array) -> Array:
	match int(e[0]):
		P.E_CALL:
			var f = _eval(e[2], scope)
			if _halt:
				return []
			var args := _eval_list(e[3], scope, -1)
			if _halt:
				return []
			if f == null:
				var what := ""
				if e[2][0] == P.E_NAME:
					what = " ('%s' não existe)" % e[2][2]
				elif e[2][0] == P.E_INDEX and e[2][3][0] == P.E_STR:
					what = " (campo '%s')" % e[2][3][2]
				_error(int(e[1]), "tentativa de chamar um valor nil" + what)
				return []
			return _call_value(f, args, int(e[1]))
		P.E_METHOD:
			var obj = _eval(e[2], scope)
			if _halt:
				return []
			var m = _index(obj, e[3], int(e[1]))
			if _halt:
				return []
			if m == null:
				_error(int(e[1]), "o método '%s' não existe para um valor %s" % [e[3], _type(obj)])
				return []
			var args: Array = [obj]
			args.append_array(_eval_list(e[4], scope, -1))
			if _halt:
				return []
			return _call_value(m, args, int(e[1]))
		P.E_VARARG:
			var sc = _find_scope(scope, "...")
			if sc == null:
				_error(int(e[1]), "'...' fora de uma função com parâmetros variáveis")
				return []
			return (sc[0]["..."] as Array).duplicate()
	return [_eval(e, scope)]


func _eval(e: Variant, scope: Array) -> Variant:
	if _halt or e == null:
		return null
	match int(e[0]):
		P.E_NUM:
			return e[2]
		P.E_STR:
			return e[2]
		P.E_NIL:
			return null
		P.E_TRUE:
			return true
		P.E_FALSE:
			return false
		P.E_NAME:
			var name: String = e[2]
			var s = scope
			while s != null:
				var vars: Dictionary = s[0]
				if vars.has(name):
					return vars[name]
				s = s[1]
			return genv.get(name)
		P.E_INDEX:
			var obj = _eval(e[2], scope)
			var key = _eval(e[3], scope)
			if _halt:
				return null
			if obj == null:
				var what := ""
				if e[2][0] == P.E_NAME:
					what = " ('%s' é nil)" % e[2][2]
				_error(int(e[1]), "tentativa de acessar o campo '%s' de um valor nil%s" % [tostr(key), what])
				return null
			return _index(obj, key, int(e[1]))
		P.E_CALL, P.E_METHOD, P.E_VARARG:
			var r := _eval_multi(e, scope)
			return r[0] if r.size() > 0 else null
		P.E_PAREN:
			return _eval(e[2], scope)
		P.E_AND:
			var a = _eval(e[2], scope)
			if not _truthy(a):
				return a
			return _eval(e[3], scope)
		P.E_OR:
			var a = _eval(e[2], scope)
			if _truthy(a):
				return a
			return _eval(e[3], scope)
		P.E_BIN:
			var a = _eval(e[3], scope)
			var b = _eval(e[4], scope)
			if _halt:
				return null
			return _binop(int(e[2]), a, b, int(e[1]))
		P.E_UN:
			var a = _eval(e[3], scope)
			if _halt:
				return null
			match int(e[2]):
				P.OP_NOT:
					return not _truthy(a)
				P.OP_NEG:
					var n = _tonum(a)
					if n != null:
						return -float(n)
					if a is PSLua.Vec3:
						return PSLua.Vec3.new(-(a as PSLua.Vec3).v)
					_error(int(e[1]), "tentativa de negar um valor %s" % _type(a))
					return null
				P.OP_LEN:
					if typeof(a) == TYPE_STRING:
						return float(String(a).length())
					if a is PSLua.Table:
						return float((a as PSLua.Table).length())
					_error(int(e[1]), "tentativa de obter o tamanho de um valor %s" % _type(a))
					return null
		P.E_FUNC:
			return _make_function(e, scope)
		P.E_TABLE:
			var t := PSLua.Table.new()
			var items: Array = e[2]
			var n := 1
			for i in items.size():
				var item: Array = items[i]
				if item[0] == null:
					var ve: Array = item[1]
					if i == items.size() - 1 and (ve[0] == P.E_CALL or ve[0] == P.E_METHOD or ve[0] == P.E_VARARG):
						for v in _eval_multi(ve, scope):
							t.set_v(float(n), v)
							n += 1
					else:
						t.set_v(float(n), _eval(ve, scope))
						n += 1
				else:
					var k = _eval(item[0], scope)
					var v = _eval(item[1], scope)
					if _halt:
						return null
					if k == null:
						_error(int(e[1]), "chave nil na tabela")
						return null
					t.set_v(_norm(k), v)
				if _halt:
					return null
			if t.size() > MAX_TABLE_SIZE:
				_error(int(e[1]), "tabela grande demais", true)
				return null
			return t
	return null


func _index(obj: Variant, key: Variant, line: int) -> Variant:
	if obj is PSLua.Table:
		return (obj as PSLua.Table).get_v(key)
	if typeof(obj) == TYPE_STRING:
		var lib = genv.get("string")
		if lib is PSLua.Table:
			return (lib as PSLua.Table).get_v(key)
		return null
	if obj is PSLua.Userdata:
		return (obj as PSLua.Userdata).lua_get(self, key)
	_error(line, "tentativa de acessar o campo '%s' de um valor %s" % [tostr(key), _type(obj)])
	return null


func _setindex(obj: Variant, key: Variant, value: Variant, line: int) -> void:
	if obj is PSLua.Table:
		if key == null:
			_error(line, "chave nil na tabela")
			return
		if typeof(key) == TYPE_FLOAT and is_nan(key):
			_error(line, "chave NaN na tabela")
			return
		var t := obj as PSLua.Table
		if value != null and t.size() >= MAX_TABLE_SIZE and t.get_v(key) == null:
			_error(line, "tabela grande demais (limite de %d itens)" % MAX_TABLE_SIZE, true)
			return
		t.set_v(_norm(key), value)
		return
	if obj is PSLua.Userdata:
		var err := (obj as PSLua.Userdata).lua_set(self, key, value)
		if err != "":
			_error(line, err)
		return
	if obj == null:
		_error(line, "tentativa de alterar o campo '%s' de um valor nil" % tostr(key))
		return
	_error(line, "tentativa de alterar o campo '%s' de um valor %s" % [tostr(key), _type(obj)])


func _eq(a: Variant, b: Variant) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	if (ta == TYPE_FLOAT or ta == TYPE_INT) and (tb == TYPE_FLOAT or tb == TYPE_INT):
		return float(a) == float(b)
	if ta != tb:
		return false
	if ta == TYPE_OBJECT:
		if a is PSLua.Userdata:
			return (a as PSLua.Userdata).lua_eq(b)
		return is_same(a, b)
	return a == b


func _binop(op: int, a: Variant, b: Variant, line: int) -> Variant:
	match op:
		P.OP_EQ:
			return _eq(a, b)
		P.OP_NE:
			return not _eq(a, b)
		P.OP_CONCAT:
			var ta := typeof(a)
			var tb := typeof(b)
			if (ta == TYPE_STRING or ta == TYPE_FLOAT or ta == TYPE_INT) and (tb == TYPE_STRING or tb == TYPE_FLOAT or tb == TYPE_INT):
				var s := tostr(a) + tostr(b)
				if s.length() > MAX_STRING:
					_error(line, "texto grande demais", true)
					return null
				return s
			_error(line, "tentativa de concatenar um valor %s" % _type(a if not (ta == TYPE_STRING or ta == TYPE_FLOAT) else b))
			return null
		P.OP_LT, P.OP_LE, P.OP_GT, P.OP_GE:
			var ta := typeof(a)
			var tb := typeof(b)
			var na := ta == TYPE_FLOAT or ta == TYPE_INT
			var nb := tb == TYPE_FLOAT or tb == TYPE_INT
			if not ((na and nb) or (ta == TYPE_STRING and tb == TYPE_STRING)):
				_error(line, "tentativa de comparar %s com %s" % [_type(a), _type(b)])
				return null
			match op:
				P.OP_LT:
					return a < b
				P.OP_LE:
					return a <= b
				P.OP_GT:
					return a > b
			return a >= b
	# Aritmética
	if a is PSLua.Vec3 or b is PSLua.Vec3:
		return _vec_arith(op, a, b, line)
	var x = _tonum(a)
	var y = _tonum(b)
	if x == null or y == null:
		_error(line, "tentativa de fazer conta com um valor %s" % _type(a if x == null else b))
		return null
	var fx: float = x
	var fy: float = y
	match op:
		P.OP_ADD:
			return fx + fy
		P.OP_SUB:
			return fx - fy
		P.OP_MUL:
			return fx * fy
		P.OP_DIV:
			if fy == 0.0:
				return INF if fx > 0 else (-INF if fx < 0 else NAN)
			return fx / fy
		P.OP_IDIV:
			if fy == 0.0:
				return INF if fx > 0 else (-INF if fx < 0 else NAN)
			return floorf(fx / fy)
		P.OP_MOD:
			if fy == 0.0:
				return NAN
			return fx - floorf(fx / fy) * fy
		P.OP_POW:
			return pow(fx, fy)
	return null


func _vec_arith(op: int, a: Variant, b: Variant, line: int) -> Variant:
	var va: Variant = (a as PSLua.Vec3).v if a is PSLua.Vec3 else _tonum(a)
	var vb: Variant = (b as PSLua.Vec3).v if b is PSLua.Vec3 else _tonum(b)
	if va == null or vb == null:
		_error(line, "operação inválida com vetor")
		return null
	match op:
		P.OP_ADD:
			if va is Vector3 and vb is Vector3:
				return PSLua.Vec3.new(va + vb)
		P.OP_SUB:
			if va is Vector3 and vb is Vector3:
				return PSLua.Vec3.new(va - vb)
		P.OP_MUL:
			if va is Vector3 and vb is Vector3:
				return PSLua.Vec3.new(va * vb)
			if va is Vector3:
				return PSLua.Vec3.new(va * float(vb))
			return PSLua.Vec3.new(vb * float(va))
		P.OP_DIV:
			if va is Vector3 and not (vb is Vector3) and float(vb) != 0.0:
				return PSLua.Vec3.new(va / float(vb))
	_error(line, "operação inválida com vetor")
	return null


# --------------------------------------------------------------------------
# Argumentos de funções nativas
# --------------------------------------------------------------------------

func arg_num(a: Array, i: int, fname: String) -> float:
	var v = _tonum(a[i]) if i < a.size() else null
	if v == null:
		rt_error("argumento %d de '%s' deve ser um número (recebeu %s)" % [i + 1, fname, _type(a[i] if i < a.size() else null)])
		return 0.0
	return v


func opt_num(a: Array, i: int, fallback: float) -> float:
	if i >= a.size() or a[i] == null:
		return fallback
	var v = _tonum(a[i])
	return v if v != null else fallback


func arg_str(a: Array, i: int, fname: String) -> String:
	if i < a.size():
		var v = a[i]
		if typeof(v) == TYPE_STRING:
			return v
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			return tostr(v)
	rt_error("argumento %d de '%s' deve ser um texto (recebeu %s)" % [i + 1, fname, _type(a[i] if i < a.size() else null)])
	return ""


func arg_table(a: Array, i: int, fname: String) -> PSLua.Table:
	if i < a.size() and a[i] is PSLua.Table:
		return a[i]
	rt_error("argumento %d de '%s' deve ser uma tabela (recebeu %s)" % [i + 1, fname, _type(a[i] if i < a.size() else null)])
	return null


func arg_fn(a: Array, i: int, fname: String) -> Variant:
	if i < a.size() and (a[i] is PSLua.Function or a[i] is PSLua.Native):
		return a[i]
	rt_error("argumento %d de '%s' deve ser uma função (recebeu %s)" % [i + 1, fname, _type(a[i] if i < a.size() else null)])
	return null


func arg_vec(a: Array, i: int, fname: String) -> Vector3:
	if i < a.size() and a[i] is PSLua.Vec3:
		return (a[i] as PSLua.Vec3).v
	rt_error("argumento %d de '%s' deve ser um vetor vec(x, y, z) (recebeu %s)" % [i + 1, fname, _type(a[i] if i < a.size() else null)])
	return Vector3.ZERO


## Aceita vec(x,y,z) ou três números a partir do índice i.
func arg_vec_or_xyz(a: Array, i: int, fname: String) -> Vector3:
	if i < a.size() and a[i] is PSLua.Vec3:
		return (a[i] as PSLua.Vec3).v
	return Vector3(arg_num(a, i, fname), opt_num(a, i + 1, 0.0), opt_num(a, i + 2, 0.0))


func call_function(f: Variant, args: Array) -> Array:
	return _call_value(f, args, _cur_line)


# --------------------------------------------------------------------------
# Biblioteca padrão
# --------------------------------------------------------------------------

func _lib(entries: Dictionary) -> PSLua.Table:
	var t := PSLua.Table.new()
	for k in entries:
		var v = entries[k]
		if v is Callable:
			t.set_v(k, native(k, v))
		else:
			t.set_v(k, v)
	return t


func _build_stdlib() -> void:
	_libs["print"] = native("print", _f_print)
	_libs["tostring"] = native("tostring", func(a): return tostr(a[0] if a.size() > 0 else null))
	_libs["tonumber"] = native("tonumber", _f_tonumber)
	_libs["type"] = native("type", func(a): return _type(a[0] if a.size() > 0 else null))
	_libs["pairs"] = native("pairs", _f_pairs)
	_libs["ipairs"] = native("ipairs", _f_ipairs)
	_libs["select"] = native("select", _f_select)
	_libs["error"] = native("error", func(a):
		var msg = a[0] if a.size() > 0 else "erro"
		rt_error(tostr(msg))
		return null)
	_libs["assert"] = native("assert", func(a):
		if a.size() == 0 or not _truthy(a[0]):
			rt_error(tostr(a[1]) if a.size() > 1 and a[1] != null else "assert falhou")
			return null
		return PSLua.Multi.new(a))
	_libs["pcall"] = native("pcall", _f_pcall)
	_libs["unpack"] = native("unpack", _f_unpack)
	_libs["math"] = _lib({
		"pi": PI, "huge": INF,
		"abs": func(a): return absf(arg_num(a, 0, "math.abs")),
		"floor": func(a): return floorf(arg_num(a, 0, "math.floor")),
		"ceil": func(a): return ceilf(arg_num(a, 0, "math.ceil")),
		"round": func(a): return roundf(arg_num(a, 0, "math.round")),
		"sqrt": func(a): return sqrt(arg_num(a, 0, "math.sqrt")),
		"sin": func(a): return sin(arg_num(a, 0, "math.sin")),
		"cos": func(a): return cos(arg_num(a, 0, "math.cos")),
		"tan": func(a): return tan(arg_num(a, 0, "math.tan")),
		"asin": func(a): return asin(arg_num(a, 0, "math.asin")),
		"acos": func(a): return acos(arg_num(a, 0, "math.acos")),
		"atan": func(a): return atan2(arg_num(a, 0, "math.atan"), opt_num(a, 1, 1.0)),
		"exp": func(a): return exp(arg_num(a, 0, "math.exp")),
		"log": func(a):
			var x := arg_num(a, 0, "math.log")
			if a.size() > 1 and a[1] != null:
				return log(x) / log(arg_num(a, 1, "math.log"))
			return log(x),
		"fmod": func(a): return fmod(arg_num(a, 0, "math.fmod"), arg_num(a, 1, "math.fmod")),
		"deg": func(a): return rad_to_deg(arg_num(a, 0, "math.deg")),
		"rad": func(a): return deg_to_rad(arg_num(a, 0, "math.rad")),
		"min": _f_min,
		"max": _f_max,
		"clamp": func(a): return clampf(arg_num(a, 0, "math.clamp"), arg_num(a, 1, "math.clamp"), arg_num(a, 2, "math.clamp")),
		"lerp": func(a): return lerpf(arg_num(a, 0, "math.lerp"), arg_num(a, 1, "math.lerp"), arg_num(a, 2, "math.lerp")),
		"sign": func(a): return signf(arg_num(a, 0, "math.sign")),
		"random": _f_random,
		"randomseed": func(a):
			_rng.seed = int(arg_num(a, 0, "math.randomseed"))
			return null,
	})
	_libs["string"] = _lib({
		"len": func(a): return float(arg_str(a, 0, "string.len").length()),
		"upper": func(a): return arg_str(a, 0, "string.upper").to_upper(),
		"lower": func(a): return arg_str(a, 0, "string.lower").to_lower(),
		"rep": _f_rep,
		"reverse": func(a): return arg_str(a, 0, "string.reverse").reverse(),
		"sub": _f_sub,
		"find": _f_find,
		"format": _f_format,
		"byte": func(a):
			var s := arg_str(a, 0, "string.byte")
			var i := int(opt_num(a, 1, 1.0)) - 1
			if i < 0 or i >= s.length():
				return null
			return float(s.unicode_at(i)),
		"char": func(a):
			var out := ""
			for v in a:
				var code := int(_tonum(v) if _tonum(v) != null else 63)
				out += char(clampi(code, 1, 0x10FFFF))
			return out,
		"gsub": _f_gsub,
		"split": _f_split,
		"trim": func(a): return arg_str(a, 0, "string.trim").strip_edges(),
	})
	_libs["table"] = _lib({
		"insert": _f_tinsert,
		"remove": _f_tremove,
		"concat": _f_tconcat,
		"sort": _f_tsort,
		"unpack": _f_unpack,
	})


func _f_print(a: Array) -> Variant:
	var parts: PackedStringArray = []
	for v in a:
		parts.append(tostr(v))
	var text := "\t".join(parts)
	if print_handler.is_valid():
		print_handler.call(text)
	else:
		print(text)
	return null


func _f_tonumber(a: Array) -> Variant:
	if a.size() == 0:
		return null
	if a.size() > 1 and a[1] != null:
		var base := int(arg_num(a, 1, "tonumber"))
		var s := tostr(a[0]).strip_edges().to_lower()
		if base == 16 and s.is_valid_hex_number():
			return float(s.hex_to_int())
		if base == 2 and s.is_valid_int():
			return float(s.bin_to_int())
		if base == 10 and s.is_valid_float():
			return s.to_float()
		return null
	return _tonum(a[0])


func _f_pairs(a: Array) -> Variant:
	var t := arg_table(a, 0, "pairs")
	if t == null:
		return null
	var keys: Array = t.hash.keys()
	var state := {"i": 0}
	var iter := native("pairs_iter", func(_args):
		while state["i"] < keys.size():
			var k = keys[state["i"]]
			state["i"] += 1
			if t.hash.has(k):
				return PSLua.Multi.new([k, t.hash[k]])
		return null)
	return PSLua.Multi.new([iter, t, null])


func _f_ipairs(a: Array) -> Variant:
	var t := arg_table(a, 0, "ipairs")
	if t == null:
		return null
	var iter := native("ipairs_iter", func(args):
		var i := float(args[1]) + 1.0
		var v = t.get_v(i)
		if v == null:
			return null
		return PSLua.Multi.new([i, v]))
	return PSLua.Multi.new([iter, t, 0.0])


func _f_select(a: Array) -> Variant:
	if a.size() == 0:
		rt_error("select precisa de argumentos")
		return null
	if typeof(a[0]) == TYPE_STRING and a[0] == "#":
		return float(a.size() - 1)
	var n := int(arg_num(a, 0, "select"))
	if n < 0:
		n = a.size() + n
	if n < 1:
		rt_error("índice inválido em select")
		return null
	return PSLua.Multi.new(a.slice(n))


func _f_pcall(a: Array) -> Variant:
	if a.size() == 0:
		rt_error("pcall precisa de uma função")
		return null
	var saved_depth := _depth
	var saved_tb := _traceback.size()
	var r := _call_value(a[0], a.slice(1), _cur_line)
	if _halt:
		if _fatal:
			return null
		_halt = false
		_flow = 0
		_depth = saved_depth
		_traceback.resize(saved_tb)
		var msg := _err
		_err = ""
		return PSLua.Multi.new([false, msg])
	var out: Array = [true]
	out.append_array(r)
	return PSLua.Multi.new(out)


func _f_unpack(a: Array) -> Variant:
	var t := arg_table(a, 0, "unpack")
	if t == null:
		return null
	var i := int(opt_num(a, 1, 1.0))
	var j := int(opt_num(a, 2, float(t.length())))
	if j - i > 10000:
		rt_error("valores demais para unpack")
		return null
	var out: Array = []
	for k in range(i, j + 1):
		out.append(t.get_v(float(k)))
	return PSLua.Multi.new(out)


func _f_min(a: Array) -> Variant:
	var m := arg_num(a, 0, "math.min")
	for i in range(1, a.size()):
		m = minf(m, arg_num(a, i, "math.min"))
	return m


func _f_max(a: Array) -> Variant:
	var m := arg_num(a, 0, "math.max")
	for i in range(1, a.size()):
		m = maxf(m, arg_num(a, i, "math.max"))
	return m


func _f_random(a: Array) -> Variant:
	if a.size() == 0:
		return _rng.randf()
	var lo := 1
	var hi := int(arg_num(a, 0, "math.random"))
	if a.size() > 1:
		lo = hi
		hi = int(arg_num(a, 1, "math.random"))
	if hi < lo:
		rt_error("intervalo vazio em math.random")
		return null
	return float(_rng.randi_range(lo, hi))


func _f_rep(a: Array) -> Variant:
	var s := arg_str(a, 0, "string.rep")
	var n := int(arg_num(a, 1, "string.rep"))
	var sep := arg_str(a, 2, "string.rep") if a.size() > 2 and a[2] != null else ""
	if n <= 0:
		return ""
	if (s.length() + sep.length()) * n > MAX_STRING:
		rt_error("texto grande demais em string.rep")
		return null
	if sep == "":
		return s.repeat(n)
	var parts: PackedStringArray = []
	for _i in n:
		parts.append(s)
	return sep.join(parts)


func _str_index(i: int, length: int) -> int:
	if i < 0:
		return maxi(length + i + 1, 1)
	return i


func _f_sub(a: Array) -> Variant:
	var s := arg_str(a, 0, "string.sub")
	var n := s.length()
	var i := _str_index(int(opt_num(a, 1, 1.0)), n)
	var j := int(opt_num(a, 2, -1.0))
	j = n + j + 1 if j < 0 else mini(j, n)
	i = maxi(i, 1)
	if i > j:
		return ""
	return s.substr(i - 1, j - i + 1)


## string.find com busca simples (sem padrões Lua): retorna início e fim (base 1).
func _f_find(a: Array) -> Variant:
	var s := arg_str(a, 0, "string.find")
	var pat := arg_str(a, 1, "string.find")
	var init := _str_index(int(opt_num(a, 2, 1.0)), s.length())
	var idx := s.find(pat, maxi(init - 1, 0))
	if idx < 0:
		return null
	return PSLua.Multi.new([float(idx + 1), float(idx + pat.length())])


## string.gsub com substituição simples de texto (sem padrões Lua).
func _f_gsub(a: Array) -> Variant:
	var s := arg_str(a, 0, "string.gsub")
	var pat := arg_str(a, 1, "string.gsub")
	var rep := arg_str(a, 2, "string.gsub")
	if pat == "":
		return PSLua.Multi.new([s, 0.0])
	var count := s.count(pat)
	var out := s.replace(pat, rep)
	if out.length() > MAX_STRING:
		rt_error("texto grande demais em string.gsub")
		return null
	return PSLua.Multi.new([out, float(count)])


func _f_split(a: Array) -> Variant:
	var s := arg_str(a, 0, "string.split")
	var sep := arg_str(a, 1, "string.split") if a.size() > 1 and a[1] != null else " "
	var t := PSLua.Table.new()
	var parts := s.split(sep, false) if sep != "" else PackedStringArray([s])
	for i in parts.size():
		t.set_v(float(i + 1), parts[i])
	return t


func _f_format(a: Array) -> Variant:
	var fmt := arg_str(a, 0, "string.format")
	var out := ""
	var arg_i := 1
	var i := 0
	while i < fmt.length():
		var c := fmt[i]
		if c != "%":
			out += c
			i += 1
			continue
		i += 1
		if i >= fmt.length():
			break
		if fmt[i] == "%":
			out += "%"
			i += 1
			continue
		var spec := "%"
		while i < fmt.length() and "-+ #0123456789.".contains(fmt[i]):
			spec += fmt[i]
			i += 1
		if i >= fmt.length():
			break
		var conv := fmt[i]
		i += 1
		var v = a[arg_i] if arg_i < a.size() else null
		arg_i += 1
		match conv:
			"d", "i":
				out += (spec + "d") % int(_tonum(v) if _tonum(v) != null else 0)
			"f", "g", "e":
				out += (spec + "f") % float(_tonum(v) if _tonum(v) != null else 0.0)
			"x":
				out += (spec + "x") % int(_tonum(v) if _tonum(v) != null else 0)
			"X":
				out += (spec + "X") % int(_tonum(v) if _tonum(v) != null else 0)
			"s", "q":
				out += (spec + "s") % tostr(v)
			_:
				rt_error("formato '%%%s' não suportado em string.format" % conv)
				return null
	return out


func _f_tinsert(a: Array) -> Variant:
	var t := arg_table(a, 0, "table.insert")
	if t == null:
		return null
	if t.size() >= MAX_TABLE_SIZE:
		rt_error("tabela grande demais (limite de %d itens)" % MAX_TABLE_SIZE)
		return null
	var n := t.length()
	if a.size() >= 3:
		var pos := int(arg_num(a, 1, "table.insert"))
		if pos < 1 or pos > n + 1:
			rt_error("posição inválida em table.insert")
			return null
		for k in range(n, pos - 1, -1):
			t.set_v(float(k + 1), t.get_v(float(k)))
		t.set_v(float(pos), a[2])
	else:
		t.set_v(float(n + 1), a[1] if a.size() > 1 else null)
	return null


func _f_tremove(a: Array) -> Variant:
	var t := arg_table(a, 0, "table.remove")
	if t == null:
		return null
	var n := t.length()
	if n == 0:
		return null
	var pos := int(opt_num(a, 1, float(n)))
	if pos < 1 or pos > n:
		return null
	var v = t.get_v(float(pos))
	for k in range(pos, n):
		t.set_v(float(k), t.get_v(float(k + 1)))
	t.set_v(float(n), null)
	return v


func _f_tconcat(a: Array) -> Variant:
	var t := arg_table(a, 0, "table.concat")
	if t == null:
		return null
	var sep := arg_str(a, 1, "table.concat") if a.size() > 1 and a[1] != null else ""
	var parts: PackedStringArray = []
	var total := 0
	for k in range(1, t.length() + 1):
		var v = t.get_v(float(k))
		var s := tostr(v)
		total += s.length() + sep.length()
		if total > MAX_STRING:
			rt_error("texto grande demais em table.concat")
			return null
		parts.append(s)
	return sep.join(parts)


func _f_tsort(a: Array) -> Variant:
	var t := arg_table(a, 0, "table.sort")
	if t == null:
		return null
	var n := t.length()
	var arr: Array = []
	for k in range(1, n + 1):
		arr.append(t.get_v(float(k)))
	var cmp = a[1] if a.size() > 1 else null
	var failed := [false]
	arr.sort_custom(func(x, y):
		if failed[0] or _halt:
			return false
		if cmp != null:
			var r := _call_value(cmp, [x, y], _cur_line)
			if _halt:
				failed[0] = true
				return false
			return _truthy(r[0] if r.size() > 0 else null)
		var lt = _binop(P.OP_LT, x, y, _cur_line)
		if _halt:
			failed[0] = true
			return false
		return bool(lt))
	if _halt:
		return null
	for k in n:
		t.set_v(float(k + 1), arr[k])
	return null
