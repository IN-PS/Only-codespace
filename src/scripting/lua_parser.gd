class_name PSLuaParser
extends RefCounted
## Analisador léxico e sintático da linguagem de scripts (subconjunto de Lua 5.x).
##
## Suporta: local, atribuição múltipla, if/elseif/else, while, repeat/until,
## for numérico e genérico (pairs/ipairs), funções (com closures, varargs e
## métodos com ":"), tabelas, operadores aritméticos, de comparação, lógicos,
## concatenação (..), comprimento (#) e divisão inteira (//).
## Não suporta: goto, metatables, corrotinas, operadores bit a bit.

# Tipos de token
const T_NAME := 0
const T_NUMBER := 1
const T_STRING := 2
const T_KEYWORD := 3
const T_OP := 4
const T_EOF := 5

const KEYWORDS := ["and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"]

# Nós de expressão
const E_NIL := 0
const E_TRUE := 1
const E_FALSE := 2
const E_NUM := 3
const E_STR := 4
const E_VARARG := 5
const E_NAME := 6
const E_INDEX := 7
const E_CALL := 8
const E_METHOD := 9
const E_FUNC := 10
const E_BIN := 11
const E_AND := 12
const E_OR := 13
const E_UN := 14
const E_TABLE := 15
const E_PAREN := 16

# Nós de comando
const S_LOCAL := 20
const S_ASSIGN := 21
const S_CALL := 22
const S_DO := 23
const S_WHILE := 24
const S_REPEAT := 25
const S_IF := 26
const S_NUMFOR := 27
const S_GENFOR := 28
const S_FUNC := 29
const S_LOCALFUNC := 30
const S_RETURN := 31
const S_BREAK := 32

# Operadores binários
const OP_ADD := 0
const OP_SUB := 1
const OP_MUL := 2
const OP_DIV := 3
const OP_IDIV := 4
const OP_MOD := 5
const OP_POW := 6
const OP_CONCAT := 7
const OP_EQ := 8
const OP_NE := 9
const OP_LT := 10
const OP_LE := 11
const OP_GT := 12
const OP_GE := 13
# Operadores unários
const OP_NEG := 0
const OP_NOT := 1
const OP_LEN := 2

const BINOPS := {
	"+": [OP_ADD, 10, 10], "-": [OP_SUB, 10, 10],
	"*": [OP_MUL, 11, 11], "/": [OP_DIV, 11, 11], "//": [OP_IDIV, 11, 11], "%": [OP_MOD, 11, 11],
	"^": [OP_POW, 14, 13], "..": [OP_CONCAT, 9, 8],
	"==": [OP_EQ, 3, 3], "~=": [OP_NE, 3, 3], "<": [OP_LT, 3, 3], "<=": [OP_LE, 3, 3], ">": [OP_GT, 3, 3], ">=": [OP_GE, 3, 3],
	"and": [-1, 2, 2], "or": [-2, 1, 1],
}
const UNARY_PRIORITY := 12
const MAX_DEPTH := 180

var _toks: Array = []
var _pos := 0
var _err := ""
var _err_line := 0
var _depth := 0


## Analisa o código. Retorna {"ok": true, "ast": bloco} ou {"ok": false, "error": msg, "line": n}.
static func parse(src: String) -> Dictionary:
	var p := PSLuaParser.new()
	return p._parse(src)


func _parse(src: String) -> Dictionary:
	var lex := tokenize(src)
	if not lex["ok"]:
		return lex
	_toks = lex["tokens"]
	_pos = 0
	var block := _block()
	if _err == "" and _peek()[0] != T_EOF:
		_fail("'%s' inesperado" % _tok_text(_peek()))
	if _err != "":
		return {"ok": false, "error": _err, "line": _err_line}
	return {"ok": true, "ast": block}


# --------------------------------------------------------------------------
# Léxico
# --------------------------------------------------------------------------

static func _is_digit(c: int) -> bool:
	return c >= 48 and c <= 57


static func _is_alpha(c: int) -> bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95 or c >= 128


static func _is_hex(c: int) -> bool:
	return _is_digit(c) or (c >= 65 and c <= 70) or (c >= 97 and c <= 102)


static func tokenize(src: String) -> Dictionary:
	var toks: Array = []
	var i := 0
	var n := src.length()
	var line := 1
	while i < n:
		var c := src.unicode_at(i)
		if c == 10:
			line += 1
			i += 1
			continue
		if c == 32 or c == 9 or c == 13:
			i += 1
			continue
		# Comentários
		if c == 45 and i + 1 < n and src.unicode_at(i + 1) == 45:
			i += 2
			var level := _long_bracket_level(src, i)
			if level >= 0:
				var res := _read_long(src, i, level)
				if res.is_empty():
					return {"ok": false, "error": "comentário longo sem fechamento", "line": line}
				line += String(res["text"]).count("\n")
				i = res["end"]
			else:
				while i < n and src.unicode_at(i) != 10:
					i += 1
			continue
		# Nomes e palavras-chave
		if _is_alpha(c):
			var s := i
			while i < n and (_is_alpha(src.unicode_at(i)) or _is_digit(src.unicode_at(i))):
				i += 1
			var word := src.substr(s, i - s)
			toks.append([T_KEYWORD if KEYWORDS.has(word) else T_NAME, word, line])
			continue
		# Números
		if _is_digit(c) or (c == 46 and i + 1 < n and _is_digit(src.unicode_at(i + 1))):
			var s := i
			if c == 48 and i + 1 < n and (src.unicode_at(i + 1) == 120 or src.unicode_at(i + 1) == 88):
				i += 2
				while i < n and _is_hex(src.unicode_at(i)):
					i += 1
				var hex := src.substr(s + 2, i - s - 2)
				if hex.is_empty():
					return {"ok": false, "error": "número hexadecimal malformado", "line": line}
				toks.append([T_NUMBER, float(hex.hex_to_int()), line])
				continue
			while i < n and (_is_digit(src.unicode_at(i)) or src.unicode_at(i) == 46):
				i += 1
			if i < n and (src.unicode_at(i) == 101 or src.unicode_at(i) == 69):
				i += 1
				if i < n and (src.unicode_at(i) == 43 or src.unicode_at(i) == 45):
					i += 1
				while i < n and _is_digit(src.unicode_at(i)):
					i += 1
			var num_text := src.substr(s, i - s)
			if not num_text.is_valid_float() or (i < n and _is_alpha(src.unicode_at(i))):
				return {"ok": false, "error": "número malformado '%s'" % num_text, "line": line}
			toks.append([T_NUMBER, num_text.to_float(), line])
			continue
		# Textos
		if c == 34 or c == 39:
			var res := _read_string(src, i, c)
			if res.has("error"):
				return {"ok": false, "error": res["error"], "line": line}
			toks.append([T_STRING, res["text"], line])
			i = res["end"]
			continue
		if c == 91:
			var level := _long_bracket_level(src, i)
			if level >= 0:
				var res := _read_long(src, i, level)
				if res.is_empty():
					return {"ok": false, "error": "texto longo sem fechamento", "line": line}
				var text: String = res["text"]
				if text.begins_with("\n"):
					text = text.substr(1)
				toks.append([T_STRING, text, line])
				line += String(res["text"]).count("\n")
				i = res["end"]
				continue
		# Operadores
		var three := src.substr(i, 3)
		var two := src.substr(i, 2)
		if three == "...":
			toks.append([T_OP, "...", line])
			i += 3
			continue
		if two in ["==", "~=", "<=", ">=", "..", "//", "::"]:
			toks.append([T_OP, two, line])
			i += 2
			continue
		var one := src.substr(i, 1)
		if "+-*/%^#<>=(){}[];:,.".contains(one):
			toks.append([T_OP, one, line])
			i += 1
			continue
		return {"ok": false, "error": "caractere inesperado '%s'" % one, "line": line}
	toks.append([T_EOF, "<fim>", line])
	return {"ok": true, "tokens": toks}


## Nível de um colchete longo ([[, [=[, ...) em `i`, ou -1.
static func _long_bracket_level(src: String, i: int) -> int:
	if i >= src.length() or src.unicode_at(i) != 91:
		return -1
	var j := i + 1
	var level := 0
	while j < src.length() and src.unicode_at(j) == 61:
		level += 1
		j += 1
	if j < src.length() and src.unicode_at(j) == 91:
		return level
	return -1


static func _read_long(src: String, i: int, level: int) -> Dictionary:
	var open_len := level + 2
	var close := "]" + "=".repeat(level) + "]"
	var start := i + open_len
	var e := src.find(close, start)
	if e < 0:
		return {}
	return {"text": src.substr(start, e - start), "end": e + close.length()}


static func _read_string(src: String, i: int, quote: int) -> Dictionary:
	var out := ""
	var j := i + 1
	var n := src.length()
	while j < n:
		var c := src.unicode_at(j)
		if c == quote:
			return {"text": out, "end": j + 1}
		if c == 10:
			return {"error": "texto não terminado"}
		if c == 92:
			j += 1
			if j >= n:
				break
			var e := src.unicode_at(j)
			match e:
				110:
					out += "\n"
				116:
					out += "\t"
				114:
					out += "\r"
				92:
					out += "\\"
				34:
					out += "\""
				39:
					out += "'"
				10:
					out += "\n"
				97:
					out += char(7)
				98:
					out += char(8)
				120:
					var hx := src.substr(j + 1, 2)
					if hx.length() < 2 or not _is_hex(hx.unicode_at(0)) or not _is_hex(hx.unicode_at(1)):
						return {"error": "escape \\x inválido"}
					out += char(hx.hex_to_int())
					j += 2
				_:
					if _is_digit(e):
						var k := j
						while k < n and k < j + 3 and _is_digit(src.unicode_at(k)):
							k += 1
						var code := src.substr(j, k - j).to_int()
						if code > 255:
							return {"error": "escape decimal grande demais"}
						out += char(code)
						j = k - 1
					else:
						return {"error": "escape inválido '\\%s'" % char(e)}
			j += 1
			continue
		out += char(c)
		j += 1
	return {"error": "texto não terminado"}


# --------------------------------------------------------------------------
# Utilidades do analisador
# --------------------------------------------------------------------------

func _peek() -> Array:
	return _toks[_pos]


func _peek2() -> Array:
	return _toks[mini(_pos + 1, _toks.size() - 1)]


func _next() -> Array:
	var t: Array = _toks[_pos]
	if _pos < _toks.size() - 1:
		_pos += 1
	return t


func _line() -> int:
	return int(_peek()[2])


func _tok_text(t: Array) -> String:
	if t[0] == T_STRING:
		return "\"%s\"" % t[1]
	return str(t[1])


func _is(text: String) -> bool:
	var t := _peek()
	return (t[0] == T_OP or t[0] == T_KEYWORD) and t[1] == text


func _accept(text: String) -> bool:
	if _is(text):
		_next()
		return true
	return false


func _expect(text: String, what := "") -> bool:
	if _accept(text):
		return true
	var msg := "esperado '%s'" % text
	if what != "":
		msg += " " + what
	_fail(msg + " perto de '%s'" % _tok_text(_peek()))
	return false


func _expect_name() -> String:
	var t := _peek()
	if t[0] != T_NAME:
		_fail("esperado um nome perto de '%s'" % _tok_text(t))
		return ""
	_next()
	return t[1]


func _fail(msg: String) -> void:
	if _err == "":
		_err = msg
		_err_line = _line()


func _block_end() -> bool:
	var t := _peek()
	if t[0] == T_EOF:
		return true
	return t[0] == T_KEYWORD and t[1] in ["end", "else", "elseif", "until"]


# --------------------------------------------------------------------------
# Comandos
# --------------------------------------------------------------------------

## Bloco: [precisa_de_escopo, comando1, comando2, ...]. O primeiro item indica
## se o bloco declara variáveis locais (só então o interpretador cria um escopo).
func _block() -> Array:
	var stmts: Array = [false]
	while _err == "" and not _block_end():
		if _is("return"):
			stmts.append(_return_stat())
			break
		var s = _statement()
		if s != null:
			stmts.append(s)
			if s[0] == S_LOCAL or s[0] == S_LOCALFUNC:
				stmts[0] = true
	return stmts


func _return_stat() -> Array:
	var line := _line()
	_next()
	var exprs: Array = []
	if not _block_end() and not _is(";"):
		exprs = _exprlist()
	_accept(";")
	if not _block_end():
		_fail("'return' deve ser o último comando do bloco")
	return [S_RETURN, line, exprs]


func _statement() -> Variant:
	_depth += 1
	if _depth > MAX_DEPTH:
		_fail("código aninhado demais")
		_depth -= 1
		return null
	var r = _statement_inner()
	_depth -= 1
	return r


func _statement_inner() -> Variant:
	var line := _line()
	var t := _peek()
	if t[0] == T_OP and t[1] == ";":
		_next()
		return null
	if t[0] == T_OP and t[1] == "::":
		_fail("rótulos (goto) não são suportados")
		return null
	if t[0] == T_KEYWORD:
		match t[1]:
			"if":
				return _if_stat()
			"while":
				_next()
				var cond = _expr()
				_expect("do", "depois da condição do 'while'")
				var body := _block()
				_expect("end", "para fechar o 'while' (linha %d)" % line)
				return [S_WHILE, line, cond, body]
			"do":
				_next()
				var body := _block()
				_expect("end", "para fechar o 'do' (linha %d)" % line)
				return [S_DO, line, body]
			"for":
				return _for_stat()
			"repeat":
				_next()
				var body := _block()
				_expect("until", "para fechar o 'repeat' (linha %d)" % line)
				var cond = _expr()
				return [S_REPEAT, line, body, cond]
			"function":
				_next()
				var target = [E_NAME, line, _expect_name()]
				var fname := String(target[2])
				var is_method := false
				while _is(".") or _is(":"):
					var sep := String(_next()[1])
					var key := _expect_name()
					fname += sep + key
					target = [E_INDEX, line, target, [E_STR, line, key]]
					if sep == ":":
						is_method = true
						break
				var f := _func_body(line, is_method, fname)
				return [S_FUNC, line, target, f]
			"local":
				_next()
				if _accept("function"):
					var lname := _expect_name()
					return [S_LOCALFUNC, line, lname, _func_body(line, false, lname)]
				var names: Array = [_expect_name()]
				while _accept(","):
					names.append(_expect_name())
				var exprs: Array = []
				if _accept("="):
					exprs = _exprlist()
				return [S_LOCAL, line, names, exprs]
			"return":
				return _return_stat()
			"break":
				_next()
				return [S_BREAK, line]
			"goto":
				_fail("'goto' não é suportado")
				return null
	# Chamada ou atribuição
	var e = _suffixed_expr()
	if _err != "":
		return null
	if _is("=") or _is(","):
		var targets: Array = [e]
		while _accept(","):
			targets.append(_suffixed_expr())
		for tg in targets:
			if tg == null or not (tg[0] == E_NAME or tg[0] == E_INDEX):
				_fail("não é possível atribuir a esta expressão")
				return null
		_expect("=")
		return [S_ASSIGN, line, targets, _exprlist()]
	if e == null or not (e[0] == E_CALL or e[0] == E_METHOD):
		_fail("comando incompleto (esperava uma chamada de função ou atribuição)")
		return null
	return [S_CALL, line, e]


func _if_stat() -> Array:
	var line := _line()
	_next()
	var conds: Array = [_expr()]
	_expect("then", "depois da condição do 'if'")
	var blocks: Array = [_block()]
	var else_block = null
	while _err == "":
		if _accept("elseif"):
			conds.append(_expr())
			_expect("then", "depois da condição do 'elseif'")
			blocks.append(_block())
		elif _accept("else"):
			else_block = _block()
			_expect("end", "para fechar o 'if' (linha %d)" % line)
			break
		else:
			_expect("end", "para fechar o 'if' (linha %d)" % line)
			break
	return [S_IF, line, conds, blocks, else_block]


func _for_stat() -> Variant:
	var line := _line()
	_next()
	var n1 := _expect_name()
	if _accept("="):
		var start = _expr()
		_expect(",", "no 'for'")
		var stop = _expr()
		var step = null
		if _accept(","):
			step = _expr()
		_expect("do", "no 'for'")
		var body := _block()
		_expect("end", "para fechar o 'for' (linha %d)" % line)
		return [S_NUMFOR, line, n1, start, stop, step, body]
	var names: Array = [n1]
	while _accept(","):
		names.append(_expect_name())
	_expect("in", "no 'for'")
	var exprs := _exprlist()
	_expect("do", "no 'for'")
	var body := _block()
	_expect("end", "para fechar o 'for' (linha %d)" % line)
	return [S_GENFOR, line, names, exprs, body]


func _func_body(line: int, is_method: bool, fname: String) -> Array:
	var params: Array = []
	if is_method:
		params.append("self")
	var vararg := false
	_expect("(", "para iniciar os parâmetros")
	if not _is(")"):
		while _err == "":
			if _accept("..."):
				vararg = true
				break
			params.append(_expect_name())
			if not _accept(","):
				break
	_expect(")", "para fechar os parâmetros")
	var body := _block()
	_expect("end", "para fechar a função (linha %d)" % line)
	return [E_FUNC, line, params, vararg, body, fname]


# --------------------------------------------------------------------------
# Expressões
# --------------------------------------------------------------------------

func _exprlist() -> Array:
	var out: Array = [_expr()]
	while _accept(","):
		out.append(_expr())
	return out


func _expr() -> Variant:
	_depth += 1
	if _depth > MAX_DEPTH:
		_fail("expressão aninhada demais")
		_depth -= 1
		return [E_NIL, _line()]
	var r = _subexpr(0)
	_depth -= 1
	return r


func _subexpr(limit: int) -> Variant:
	var line := _line()
	var e = null
	var t := _peek()
	if (t[0] == T_KEYWORD and t[1] == "not") or (t[0] == T_OP and (t[1] == "-" or t[1] == "#")):
		_next()
		var op := OP_NOT if t[1] == "not" else (OP_NEG if t[1] == "-" else OP_LEN)
		var operand = _subexpr(UNARY_PRIORITY)
		# Dobra constantes negativas: -5
		if op == OP_NEG and operand != null and operand[0] == E_NUM:
			e = [E_NUM, line, -float(operand[2])]
		else:
			e = [E_UN, line, op, operand]
	else:
		e = _simple_expr()
	while _err == "":
		var tk := _peek()
		if not (tk[0] == T_OP or tk[0] == T_KEYWORD):
			break
		var info = BINOPS.get(tk[1])
		if info == null or int(info[1]) <= limit:
			break
		var oline := int(tk[2])
		_next()
		var rhs = _subexpr(int(info[2]))
		match int(info[0]):
			-1:
				e = [E_AND, oline, e, rhs]
			-2:
				e = [E_OR, oline, e, rhs]
			_:
				e = [E_BIN, oline, int(info[0]), e, rhs]
	return e


func _simple_expr() -> Variant:
	var line := _line()
	var t := _peek()
	match t[0]:
		T_NUMBER:
			_next()
			return [E_NUM, line, float(t[1])]
		T_STRING:
			_next()
			return [E_STR, line, String(t[1])]
		T_KEYWORD:
			match t[1]:
				"nil":
					_next()
					return [E_NIL, line]
				"true":
					_next()
					return [E_TRUE, line]
				"false":
					_next()
					return [E_FALSE, line]
				"function":
					_next()
					return _func_body(line, false, "função anônima")
		T_OP:
			if t[1] == "...":
				_next()
				return [E_VARARG, line]
			if t[1] == "{":
				return _table()
	return _suffixed_expr()


func _primary_expr() -> Variant:
	var line := _line()
	var t := _peek()
	if t[0] == T_NAME:
		_next()
		return [E_NAME, line, t[1]]
	if t[0] == T_OP and t[1] == "(":
		_next()
		var e = _expr()
		_expect(")", "para fechar o parêntese")
		return [E_PAREN, line, e]
	_fail("símbolo inesperado '%s'" % _tok_text(t))
	_next()
	return null


func _suffixed_expr() -> Variant:
	var e = _primary_expr()
	while _err == "":
		var line := _line()
		if _accept("."):
			e = [E_INDEX, line, e, [E_STR, line, _expect_name()]]
		elif _accept("["):
			var k = _expr()
			_expect("]")
			e = [E_INDEX, line, e, k]
		elif _accept(":"):
			var mname := _expect_name()
			e = [E_METHOD, line, e, mname, _call_args()]
		elif _is("(") or _is("{") or _peek()[0] == T_STRING:
			# Na mesma linha, para evitar ambiguidade com o próximo comando.
			if _is("(") and _pos > 0 and int(_toks[_pos - 1][2]) != line:
				_fail("chamada ambígua: coloque o '(' na mesma linha da função")
				return e
			e = [E_CALL, line, e, _call_args()]
		else:
			break
	return e


func _call_args() -> Array:
	var t := _peek()
	if t[0] == T_STRING:
		_next()
		return [[E_STR, int(t[2]), String(t[1])]]
	if _is("{"):
		return [_table()]
	_expect("(", "para os argumentos")
	var args: Array = []
	if not _is(")"):
		args = _exprlist()
	_expect(")", "para fechar os argumentos")
	return args


func _table() -> Array:
	var line := _line()
	_expect("{")
	var items: Array = []
	while _err == "" and not _is("}"):
		if _is("["):
			_next()
			var k = _expr()
			_expect("]")
			_expect("=")
			items.append([k, _expr()])
		elif _peek()[0] == T_NAME and _peek2()[0] == T_OP and _peek2()[1] == "=":
			var key := String(_next()[1])
			_next()
			items.append([[E_STR, line, key], _expr()])
		else:
			items.append([null, _expr()])
		if not (_accept(",") or _accept(";")):
			break
	_expect("}", "para fechar a tabela (linha %d)" % line)
	return [E_TABLE, line, items]
