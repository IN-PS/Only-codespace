class_name PSGrid
extends MeshInstance3D
## Grade infinita do editor (linhas de 1 m, destaque a cada 10 m e eixos X/Z).

var camera: Camera3D

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
uniform float fade_distance = 60.0;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
float line(vec2 coord, float width) {
	vec2 g = abs(fract(coord - 0.5) - 0.5) / fwidth(coord);
	return 1.0 - min(min(g.x, g.y) / width, 1.0);
}
void fragment() {
	vec2 c = wpos.xz;
	float minor = line(c, 1.0);
	float major = line(c / 10.0, 1.4);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(fade_distance * 0.4, fade_distance, dist);
	vec3 col = vec3(0.55, 0.58, 0.65);
	float a = max(minor * 0.22, major * 0.45);
	vec2 axis = abs(c) / fwidth(c);
	if (axis.y < 1.5) { col = vec3(0.94, 0.33, 0.31); a = 0.8; }
	if (axis.x < 1.5) { col = vec3(0.26, 0.65, 0.96); a = 0.8; }
	ALBEDO = col;
	ALPHA = a * fade;
}
"""


func _ready() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	mesh = pm
	var sh := Shader.new()
	sh.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position.y = 0.001


func _process(_delta: float) -> void:
	if camera:
		var p := camera.global_position
		position = Vector3(snappedf(p.x, 10.0), 0.001, snappedf(p.z, 10.0))
		var h := absf(p.y)
		(material_override as ShaderMaterial).set_shader_parameter("fade_distance", clampf(h * 4.0 + 30.0, 30.0, 190.0))
