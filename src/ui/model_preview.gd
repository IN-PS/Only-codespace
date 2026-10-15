class_name PSModelPreview
extends SubViewportContainer
## Pré-visualização 3D de um modelo, girando devagar, num mundo isolado.

var _vp: SubViewport
var _pivot: Node3D
var _camera: Camera3D
var _model: Node3D


func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(160, 150)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("15171c")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.65)
	e.ambient_light_energy = 0.8
	env.environment = e
	_vp.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	_vp.add_child(light)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_camera = Camera3D.new()
	_camera.fov = 40
	_vp.add_child(_camera)


func set_model(node: Node3D) -> void:
	if _model and is_instance_valid(_model):
		_model.queue_free()
	_model = node
	if node == null:
		return
	_pivot.add_child(node)
	var box := PSAssetLibrary.compute_aabb(node)
	node.position = -box.get_center()
	var radius := maxf(box.size.length() * 0.5, 0.1)
	var dist := radius / sin(deg_to_rad(_camera.fov * 0.5)) * 1.05
	_camera.position = Vector3(0, radius * 0.45, dist)
	_camera.look_at(Vector3.ZERO)


func _process(delta: float) -> void:
	if is_visible_in_tree() and _pivot:
		_pivot.rotate_y(delta * 0.6)
