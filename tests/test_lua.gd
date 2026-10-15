extends PSTestCase
## Linguagem de scripts: semântica, biblioteca padrão e isolamento (sandbox).

var it: PSLuaInterp
var out: Array = []


func before_all() -> void:
	it = PSLuaInterp.new()
	it.genv = it.new_env()
	it.genv["vec"] = it.native("vec", func(a): return PSLua.Vec3.new(Vector3(it.opt_num(a, 0, 0), it.opt_num(a, 1, 0), it.opt_num(a, 2, 0))))
	it.print_handler = func(t): out.append(t)


func after_all() -> void:
	it.dispose()


## Executa e devolve os valores de retorno (ou a mensagem de erro).
func run(code: String, steps := 100000) -> Variant:
	var c := it.compile(code, "t")
	if not c["ok"]:
		return "SINTAXE: " + String(c["error"])
	var r := it.call_protected(c["fn"], [], steps)
	if not r["ok"]:
		return "ERRO: " + String(r["error"])
	var v: Array = r["values"]
	return v[0] if v.size() == 1 else v


func test_arithmetic_and_precedence() -> void:
	eq(run("return 1 + 2 * 3"), 7.0, "precedência * sobre +")
	eq(run("return (1 + 2) * 3"), 9.0, "parênteses")
	eq(run("return 2 ^ 3 ^ 2"), 512.0, "^ associa à direita")
	eq(run("return -2 ^ 2"), -4.0, "unário menos abaixo de ^")
	eq(run("return 7 // 2, 7 % 3, -7 % 3"), [3.0, 1.0, 2.0], "divisão inteira e módulo (Lua)")
	eq(run("return 10 / 4"), 2.5, "divisão real")
	eq(run("return \"10\" + 5"), 15.0, "texto numérico vira número")
	eq(run("return 1 .. 2"), "12", "concatenação de números")
	eq(run("return #\"olá\""), 3.0, "tamanho de texto")
	eq(run("return 0x1F"), 31.0, "hexadecimal")
	eq(run("return 1e3"), 1000.0, "notação científica")


func test_logic_and_comparison() -> void:
	eq(run("return nil or 5, false and 1, 3 and 4"), [5.0, false, 4.0], "and/or retornam operandos")
	eq(run("return not nil, not 0"), [true, false], "0 é verdadeiro em Lua")
	eq(run("return 1 < 2, 'a' < 'b', 2 == 2.0, 'x' ~= 'y'"), [true, true, true, true], "comparações")
	check(String(run("return 1 < 'a'")).begins_with("ERRO"), "comparar número com texto é erro")


func test_control_flow() -> void:
	eq(run("local s = 0 for i = 1, 10 do s = s + i end return s"), 55.0, "for numérico")
	eq(run("local s = 0 for i = 10, 1, -2 do s = s + i end return s"), 30.0, "for com passo negativo")
	eq(run("local i, s = 0, 0 while i < 5 do i = i + 1 if i == 3 then break end s = s + i end return s"), 3.0, "while + break")
	eq(run("local i = 0 repeat local j = i i = i + 1 until j >= 3 return i"), 4.0, "repeat enxerga locais no until")
	eq(run("local x = 5 if x > 10 then return 'a' elseif x > 3 then return 'b' else return 'c' end"), "b", "elseif")
	eq(run("local t = {} for k, v in pairs({a=1, b=2}) do t[#t+1] = k .. v end table.sort(t) return table.concat(t, ',')"), "a1,b2", "pairs")
	eq(run("local s = '' for i, v in ipairs({'x','y','z'}) do s = s .. i .. v end return s"), "1x2y3z", "ipairs")


func test_functions_closures_varargs() -> void:
	eq(run("local function fib(n) if n < 2 then return n end return fib(n-1) + fib(n-2) end return fib(15)"), 610.0, "recursão")
	eq(run("local function c() local n = 0 return function() n = n + 1 return n end end local f = c() f() f() return f()"), 3.0, "closure com estado")
	eq(run("local fs = {} for i = 1, 3 do fs[i] = function() return i end end return fs[1]() + fs[3]()"), 4.0, "cada iteração tem sua variável")
	eq(run("local function f(...) return select('#', ...), ... end return f(1, nil, 3)"), [3.0, 1.0, null, 3.0], "varargs")
	eq(run("local function f() return 1, 2, 3 end local t = {f()} return #t, (f())"), [3.0, 1.0], "expansão e truncamento de múltiplos valores")
	eq(run("local a, b, c = (function() return 1, 2 end)() return c"), null, "valores faltantes viram nil")
	eq(run("local o = {v = 2} function o:dobro(x) return self.v * x end return o:dobro(21)"), 42.0, "método com :")


func test_tables_and_strings() -> void:
	eq(run("local t = {1, 2, 3, x = 'a', [10] = 'b'} return #t, t.x, t[10]"), [3.0, "a", "b"], "construtor de tabela")
	eq(run("local t = {} table.insert(t, 'a') table.insert(t, 1, 'b') return table.concat(t, '-')"), "b-a", "table.insert")
	eq(run("local t = {5, 1, 4} table.sort(t, function(a, b) return a > b end) return table.concat(t, ',')"), "5,4,1", "table.sort com comparador")
	eq(run("local t = {1, 2, 3} local r = table.remove(t) return r, #t"), [3.0, 2.0], "table.remove")
	eq(run("return ('Olá'):upper(), string.sub('abcdef', 2, 4), string.sub('abcdef', -2)"), ["OLÁ", "bcd", "ef"], "métodos de texto")
	eq(run("return string.format('%d|%.2f|%s|%5.1f', 7, 3.14159, 'x', 2)"), "7|3.14|x|  2.0", "string.format")
	eq(run("return string.find('procura agulha', 'agulha')"), [9.0, 14.0], "string.find simples")
	eq(run("return string.rep('ab', 3, ',')"), "ab,ab,ab", "string.rep")
	eq(run("return tostring(1.5), tostring(10), tostring(true), type({})"), ["1.5", "10", "true", "table"], "tostring/type")
	eq(run("return tonumber('42'), tonumber('ff', 16), tonumber('x')"), [42.0, 255.0, null], "tonumber")


func test_errors_and_pcall() -> void:
	var e := String(run("local x = nil\nreturn x.campo"))
	check(e.contains("t:2:") and e.contains("nil"), "erro com linha: " + e)
	e = String(run("naoexiste()"))
	check(e.contains("'naoexiste' não existe"), "função inexistente explicada: " + e)
	eq(run("local ok, msg = pcall(function() error('falhou') end) return ok, string.find(msg, 'falhou') ~= nil"), [false, true], "pcall captura erro")
	eq(run("local ok, v = pcall(function() return 7 end) return ok, v"), [true, 7.0], "pcall sucesso")
	e = String(run("return 1 + {}"))
	check(e.contains("conta com um valor table"), "conta com tabela: " + e)


func test_syntax_errors_have_lines() -> void:
	var r := PSLuaParser.parse("local x = 1\nif x then\n  print(x)\n")
	check(not r["ok"], "falta 'end'")
	check(String(r["error"]).contains("end"), "mensagem cita 'end': " + String(r["error"]))
	r = PSLuaParser.parse("x = = 2")
	check(not r["ok"] and int(r["line"]) == 1, "erro na linha 1")
	r = PSLuaParser.parse("local s = 'sem fim")
	check(not r["ok"], "texto não terminado")
	r = PSLuaParser.parse("goto fim")
	check(not r["ok"], "goto não suportado")
	r = PSLuaParser.parse("--[[ comentário\nlongo ]] local a = [[texto\nlongo]] return a")
	check(r["ok"], "comentários e textos longos")


func test_sandbox_has_no_dangerous_globals() -> void:
	for name in ["os", "io", "require", "load", "loadstring", "dofile", "loadfile", "debug", "package", "collectgarbage", "setmetatable", "getmetatable", "rawset", "coroutine", "OS", "FileAccess", "Engine", "ClassDB", "JavaScriptBridge"]:
		eq(run("return %s" % name), null, "global '%s' não existe" % name)
	check(String(run("return io.open('x')")).begins_with("ERRO"), "io.open falha")


func test_infinite_loop_is_stopped() -> void:
	var t0 := Time.get_ticks_msec()
	var e := String(run("while true do end", 50000))
	check(e.contains("limite"), "loop infinito interrompido: " + e)
	check(Time.get_ticks_msec() - t0 < 5000, "interrompe rápido")
	e = String(run("local function f() return f() + 1 end return f()"))
	check(e.contains("recursão"), "recursão infinita interrompida: " + e)
	e = String(run("local t = {} for i = 1, 200000 do t[i] = i end", 5000000))
	check(e.contains("grande demais"), "tabela gigante bloqueada: " + e)
	e = String(run("local s = 'x' while true do s = s .. s end", 5000000))
	check(e.contains("grande demais"), "texto gigante bloqueado: " + e)
	# Depois de um erro fatal o interpretador continua utilizável.
	eq(run("return 1 + 1"), 2.0, "interpretador segue funcionando")


func test_vectors() -> void:
	eq(run("local v = vec(1, 2, 3) + vec(1, 1, 1) return v.x, v.y, v.z"), [2.0, 3.0, 4.0], "soma de vetores")
	eq(run("return (vec(3, 4, 0)):length()"), 5.0, "comprimento")
	eq(run("local v = vec(1, 0, 0) * 3 return v.x"), 3.0, "vetor * número")
	eq(run("return vec(1, 2, 3) == vec(1, 2, 3)"), true, "igualdade por valor")
	eq(run("return tostring(vec(1, 2.5, 0))"), "vec(1, 2.5, 0)", "tostring de vetor")


func test_print_goes_to_handler() -> void:
	out.clear()
	run("print('olá', 1, nil, true)")
	eq(out, ["olá\t1\tnil\ttrue"], "print usa o console")


func test_parser_handles_all_templates() -> void:
	for t in PSScriptTemplates.LIST:
		var r := PSLuaParser.parse(String(t["code"]))
		check(r["ok"], "modelo '%s' sem erros: %s" % [t["name"], r.get("error", "")])
