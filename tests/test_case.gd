class_name PSTestCase
extends RefCounted
## Base dos testes automatizados. Cada método que começa com "test_" é executado.

var runner: Node
var failures: Array = []
var current := ""


func tree() -> SceneTree:
	return runner.get_tree()


func frames(n := 1) -> void:
	for _i in n:
		await tree().process_frame


func physics_frames(n := 1) -> void:
	for _i in n:
		await tree().physics_frame


func check(cond: bool, msg: String) -> bool:
	if not cond:
		failures.append("%s: %s" % [current, msg])
	return cond


func eq(a: Variant, b: Variant, msg: String) -> bool:
	var ok := false
	if (typeof(a) == TYPE_FLOAT or typeof(a) == TYPE_INT) and (typeof(b) == TYPE_FLOAT or typeof(b) == TYPE_INT):
		ok = is_equal_approx(float(a), float(b))
	elif a is Vector3 and b is Vector3:
		ok = (a as Vector3).is_equal_approx(b)
	else:
		ok = a == b
	if not ok:
		failures.append("%s: %s (esperado %s, obtido %s)" % [current, msg, str(b), str(a)])
	return ok


func near(a: float, b: float, tol: float, msg: String) -> bool:
	if absf(a - b) > tol:
		failures.append("%s: %s (esperado %s ± %s, obtido %s)" % [current, msg, b, tol, a])
		return false
	return true


## Cria um projeto temporário e devolve o id.
func temp_project(template := "empty", project_name := "Teste automatizado") -> String:
	var data := PSTemplates.create(template, project_name)
	return PSProjectStore.create_project(project_name, data)


func before_all() -> void:
	pass


func after_all() -> void:
	pass
