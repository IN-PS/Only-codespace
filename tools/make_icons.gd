extends SceneTree
## Gera os ícones do Android (PNG) a partir de icon.svg.
## Uso: godot --headless --path . -s res://tools/make_icons.gd

func _init() -> void:
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	_save(svg, 192, "res://assets/android/launcher_192.png")
	# Ícone adaptativo: o desenho ocupa ~60% central (zona segura), fundo separado.
	var fg_svg := svg.replace("<rect x=\"4\" y=\"4\" width=\"120\" height=\"120\" rx=\"24\" fill=\"#16181d\"/>", "").replace("<rect x=\"4\" y=\"4\" width=\"120\" height=\"120\" rx=\"24\" fill=\"none\" stroke=\"#2f3440\" stroke-width=\"4\"/>", "")
	var img := Image.new()
	img.load_svg_from_string(fg_svg, 432.0 / 128.0 * 0.62)
	var canvas := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	canvas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), (Vector2i(432, 432) - img.get_size()) / 2)
	canvas.save_png("res://assets/android/adaptive_foreground_432.png")
	var bg := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	bg.fill(Color("16181d"))
	bg.save_png("res://assets/android/adaptive_background_432.png")
	print("ícones gerados")
	quit()


func _save(svg: String, size: int, path: String) -> void:
	var img := Image.new()
	img.load_svg_from_string(svg, size / 128.0)
	img.save_png(path)
