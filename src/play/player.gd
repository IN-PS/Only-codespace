class_name PSPlayer
extends CharacterBody3D
## Personagem do modo de teste: anda, pula, nada e empurra objetos dinâmicos.

signal respawned

const AVATAR_LAYER := 2

var walk_speed := 6.0
var jump_velocity := 7.0
var gravity := 9.8
var respawn_y := -40.0
var camera_mode := "third"   # "third" ou "first"
var move_input := Vector2.ZERO
var jump_pressed := false
var yaw := 0.0
var pitch := -12.0
var spawn_transform := Transform3D.IDENTITY
var in_water := 0

var camera: Camera3D
var _arm: SpringArm3D
var _head: Node3D
var _avatar: Node3D
var _coyote := 0.0
var _jump_buffer := 0.0


func _init() -> void:
	name = "Player"
	collision_layer = PSWorld.LAYER_PLAYER
	collision_mask = PSWorld.LAYER_WORLD
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	_build_avatar()
	_head = Node3D.new()
	_head.position = Vector3(0, 1.6, 0)
	add_child(_head)
	_arm = SpringArm3D.new()
	_arm.spring_length = 4.5
	_arm.margin = 0.2
	_arm.collision_mask = PSWorld.LAYER_WORLD
	var arm_shape := SphereShape3D.new()
	arm_shape.radius = 0.2
	_arm.shape = arm_shape
	_arm.add_excluded_object(get_rid())
	_head.add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.near = 0.05
	camera.far = 1500.0
	_arm.add_child(camera)


func _build_avatar() -> void:
	_avatar = Node3D.new()
	_avatar.name = "Avatar"
	add_child(_avatar)
	var body_mat := PSPrimitives.make_material({"color": [0.24, 0.49, 0.95, 1.0], "rough": 0.6})
	var skin_mat := PSPrimitives.make_material({"color": [0.98, 0.8, 0.62, 1.0], "rough": 0.7})
	var parts := [
		["capsule", Vector3(0, 0.75, 0), Vector3(0.7, 1.1, 0.5), body_mat],
		["sphere", Vector3(0, 1.55, 0), Vector3(0.5, 0.5, 0.5), skin_mat],
		["box", Vector3(0.1, 1.6, -0.24), Vector3(0.07, 0.09, 0.03), PSPrimitives.make_material({"color": [0.1, 0.1, 0.12, 1.0]})],
		["box", Vector3(-0.1, 1.6, -0.24), Vector3(0.07, 0.09, 0.03), PSPrimitives.make_material({"color": [0.1, 0.1, 0.12, 1.0]})],
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = PSPrimitives.get_mesh(p[0])
		mi.position = p[1]
		mi.scale = p[2]
		mi.material_override = p[3]
		mi.layers = AVATAR_LAYER
		_avatar.add_child(mi)


func setup(game: Dictionary, p_gravity: float) -> void:
	walk_speed = float(game.get("walk_speed", 6.0))
	jump_velocity = float(game.get("jump", 7.0))
	respawn_y = float(game.get("respawn_y", -40.0))
	gravity = p_gravity
	set_camera_mode(String(game.get("camera", "third")))


func set_camera_mode(m: String) -> void:
	camera_mode = m
	if m == "first":
		_arm.spring_length = 0.0
		camera.cull_mask = 0xFFFFF & ~AVATAR_LAYER
		_head.position = Vector3(0, 1.6, 0)
	else:
		_arm.spring_length = 4.5
		camera.cull_mask = 0xFFFFF
		_head.position = Vector3(0, 1.7, 0)
	_update_camera()


func toggle_camera_mode() -> String:
	set_camera_mode("first" if camera_mode == "third" else "third")
	return camera_mode


func look(dx: float, dy: float) -> void:
	var sens := float(App.get_setting("look_sensitivity", 1.0)) * 0.3
	var inv := -1.0 if App.get_setting("invert_look", false) else 1.0
	yaw -= dx * sens
	pitch = clampf(pitch - dy * sens * inv, -85.0, 70.0 if camera_mode == "third" else 85.0)
	_update_camera()


func _update_camera() -> void:
	_head.rotation_degrees = Vector3(pitch, yaw, 0)
	if camera_mode == "first":
		_avatar.rotation_degrees.y = yaw


func place_at_spawn() -> void:
	global_transform = Transform3D(Basis.IDENTITY, spawn_transform.origin + Vector3(0, 0.1, 0))
	var fwd := -spawn_transform.basis.z
	yaw = rad_to_deg(atan2(-fwd.x, -fwd.z))
	_avatar.rotation_degrees.y = yaw
	velocity = Vector3.ZERO
	_update_camera()
	respawned.emit()


func _process(_delta: float) -> void:
	# Em terceira pessoa, se a câmera encostar no personagem (parede ou morro
	# atrás), esconde o avatar para não tampar a visão.
	if camera_mode == "third":
		_avatar.visible = _arm.get_hit_length() > 1.3


func _physics_process(delta: float) -> void:
	var input := move_input
	var kb := Input.get_vector("ps_left", "ps_right", "ps_forward", "ps_back")
	if kb.length() > 0.0:
		input = kb
	var basis_yaw := Basis(Vector3.UP, deg_to_rad(yaw))
	var dir := basis_yaw * Vector3(input.x, 0, input.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var swimming := in_water > 0
	var speed := walk_speed * (0.6 if swimming else 1.0)
	var target := dir * speed
	var accel := 12.0 if is_on_floor() else (5.0 if not swimming else 4.0)
	velocity.x = move_toward(velocity.x, target.x, accel * speed * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * speed * delta)

	if is_on_floor():
		_coyote = 0.12
	else:
		_coyote -= delta
	if jump_pressed or Input.is_action_just_pressed("ps_jump"):
		_jump_buffer = 0.15
	_jump_buffer -= delta
	var jump_held := jump_pressed or Input.is_action_pressed("ps_jump")
	jump_pressed = false

	if swimming:
		velocity.y -= gravity * 0.25 * delta
		velocity.y *= 1.0 - minf(2.5 * delta, 0.9)
		if jump_held:
			velocity.y = move_toward(velocity.y, 3.0, 12.0 * delta)
	else:
		velocity.y -= gravity * delta
		if _jump_buffer > 0.0 and _coyote > 0.0:
			velocity.y = jump_velocity
			_jump_buffer = 0.0
			_coyote = 0.0

	move_and_slide()

	# Empurra corpos dinâmicos.
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other is RigidBody3D:
			var push := -col.get_normal()
			push.y = 0.0
			(other as RigidBody3D).apply_central_impulse(push.normalized() * 0.6 * maxf(1.0, Vector2(velocity.x, velocity.z).length()) * delta * 10.0)

	if camera_mode == "third" and Vector2(velocity.x, velocity.z).length() > 0.3:
		var target_yaw := rad_to_deg(atan2(-velocity.x, -velocity.z))
		_avatar.rotation_degrees.y = rad_to_deg(lerp_angle(deg_to_rad(_avatar.rotation_degrees.y), deg_to_rad(target_yaw), minf(1.0, 12.0 * delta)))

	if global_position.y < respawn_y:
		App.log_info("Jogador caiu do mundo e voltou ao início.", "Jogo")
		place_at_spawn()


func get_slide_colliders() -> Array:
	var out: Array = []
	for i in get_slide_collision_count():
		out.append(get_slide_collision(i).get_collider())
	return out
