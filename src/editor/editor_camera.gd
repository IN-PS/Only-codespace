class_name PSEditorCamera
extends Camera3D
## Câmera orbital do editor: um dedo gira, dois dedos arrastam e fazem pinça.

var pivot := Vector3(0, 0.5, 0)
var yaw := -35.0
var pitch := -28.0
var distance := 14.0
var min_distance := 0.4
var max_distance := 600.0
var sensitivity := 1.0


func _ready() -> void:
	fov = 60.0
	near = 0.05
	far = 2000.0
	_update()


func _update() -> void:
	pitch = clampf(pitch, -89.0, 89.0)
	distance = clampf(distance, min_distance, max_distance)
	var b := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0))
	transform = Transform3D(b, pivot + b * Vector3(0, 0, distance))


## Gira em torno do pivô. dx/dy em unidades de interface.
func orbit(dx: float, dy: float) -> void:
	yaw -= dx * 0.35 * sensitivity
	pitch -= dy * 0.35 * sensitivity
	_update()


## Arrasta a vista no plano da câmera.
func pan(dx: float, dy: float) -> void:
	var k := distance * 0.0022 * tan(deg_to_rad(fov * 0.5)) * 1.7
	pivot += (-global_basis.x * dx + global_basis.y * dy) * k
	_update()


func zoom(factor: float) -> void:
	distance *= factor
	_update()


## Aproxima mantendo o ponto sob o dedo aproximadamente fixo.
func zoom_at(factor: float, world_point: Variant) -> void:
	if world_point is Vector3:
		var t := 1.0 - factor
		pivot = pivot.lerp(world_point, clampf(t, -1.0, 0.6))
	zoom(factor)


func focus_on(box: AABB) -> void:
	pivot = box.get_center()
	var radius := maxf(box.size.length() * 0.5, 0.5)
	distance = radius / sin(deg_to_rad(fov * 0.5)) * 1.1
	_update()


func set_view(view: String) -> void:
	match view:
		"top":
			yaw = 0.0
			pitch = -89.0
		"front":
			yaw = 0.0
			pitch = 0.0
		"right":
			yaw = 90.0
			pitch = 0.0
		"iso":
			yaw = -35.0
			pitch = -28.0
	_update()


func get_state() -> Dictionary:
	return {"pivot": PSData.v3_to_arr(pivot), "yaw": yaw, "pitch": pitch, "distance": distance}


func set_state(s: Dictionary) -> void:
	if s.is_empty():
		return
	pivot = PSData.arr_to_v3(s.get("pivot"), pivot)
	yaw = PSData._f(s.get("yaw"), yaw)
	pitch = PSData._f(s.get("pitch"), pitch)
	distance = PSData._f(s.get("distance"), distance)
	_update()


## Raio a partir de um ponto da tela (coordenadas de interface).
func ray(screen_pos: Vector2) -> Array:
	var from := project_ray_origin(screen_pos)
	var dir := project_ray_normal(screen_pos)
	return [from, dir]


## Interseção do raio com um plano horizontal na altura y.
func ray_to_plane_y(screen_pos: Vector2, y := 0.0) -> Variant:
	var r := ray(screen_pos)
	var plane := Plane(Vector3.UP, y)
	return plane.intersects_ray(r[0], r[1])
