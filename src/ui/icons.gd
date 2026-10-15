class_name PSIcons
extends RefCounted
## Ícones vetoriais (SVG) renderizados em tempo de execução na resolução
## exata da tela, para ficarem nítidos em qualquer densidade de pixels.

const STROKE := "fill='none' stroke='#e6e8ee' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'"

const PATHS := {
	"menu": "<path d='M4 6h16M4 12h16M4 18h16'/>",
	"back": "<path d='M15 5l-7 7 7 7'/>",
	"close": "<path d='M6 6l12 12M18 6L6 18'/>",
	"check": "<path d='M5 12.5l4.5 4.5L19 7'/>",
	"plus": "<path d='M12 5v14M5 12h14'/>",
	"minus": "<path d='M5 12h14'/>",
	"undo": "<path d='M9 14L4 9l5-5'/><path d='M4 9h10a6 6 0 0 1 0 12h-3'/>",
	"redo": "<path d='M15 14l5-5-5-5'/><path d='M20 9H10a6 6 0 0 0 0 12h3'/>",
	"play": "<path d='M7 4.5v15l12-7.5z' fill='#e6e8ee'/>",
	"pause": "<path d='M8 5v14M16 5v14' stroke-width='3'/>",
	"stop": "<rect x='6' y='6' width='12' height='12' rx='1.5' fill='#e6e8ee'/>",
	"restart": "<path d='M4 12a8 8 0 1 0 2.4-5.7'/><path d='M4 4v5h5'/>",
	"save": "<path d='M5 4h11l3 3v13H5z'/><path d='M8 4v5h7V4M8 20v-6h8v6'/>",
	"folder": "<path d='M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z'/>",
	"trash": "<path d='M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3'/>",
	"copy": "<rect x='8' y='8' width='12' height='12' rx='2'/><path d='M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2'/>",
	"select": "<path d='M5 3l14 7-6 2-2 6z' fill='#e6e8ee' stroke-width='1.5'/>",
	"move": "<path d='M12 3v18M3 12h18M12 3l-3 3M12 3l3 3M12 21l-3-3M12 21l3-3M3 12l3-3M3 12l3 3M21 12l-3-3M21 12l-3 3'/>",
	"rotate": "<path d='M20 12a8 8 0 1 1-3-6.2'/><path d='M20 4v5h-5'/>",
	"scale": "<rect x='3' y='11' width='10' height='10' rx='1'/><path d='M13 3h8v8M21 3l-9 9'/>",
	"layers": "<path d='M12 3l9 5-9 5-9-5z'/><path d='M3 13l9 5 9-5'/>",
	"sliders": "<path d='M4 7h10M18 7h2M4 17h4M12 17h8'/><circle cx='16' cy='7' r='2'/><circle cx='10' cy='17' r='2'/>",
	"palette": "<path d='M12 3a9 9 0 1 0 0 18c1.5 0 2-1 2-2s-1-1.5-1-2.5 1-1.5 2-1.5h2a4 4 0 0 0 4-4c0-4.4-4-8-9-8z'/><circle cx='7.5' cy='11' r='1' fill='#e6e8ee'/><circle cx='10' cy='7' r='1' fill='#e6e8ee'/><circle cx='15' cy='7' r='1' fill='#e6e8ee'/>",
	"mountain": "<path d='M2 20l7-12 4 6 3-4 6 10z'/>",
	"cube": "<path d='M12 2l9 5v10l-9 5-9-5V7z'/><path d='M3 7l9 5 9-5M12 12v10'/>",
	"code": "<path d='M8 7l-5 5 5 5M16 7l5 5-5 5M14 4l-4 16'/>",
	"terminal": "<rect x='3' y='4' width='18' height='16' rx='2'/><path d='M7 9l3 3-3 3M12 15h5'/>",
	"sun": "<circle cx='12' cy='12' r='4'/><path d='M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5L19 19M5 19l1.5-1.5M17.5 6.5L19 5'/>",
	"eye": "<path d='M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z'/><circle cx='12' cy='12' r='3'/>",
	"eye_off": "<path d='M3 3l18 18M10.6 6.1A10 10 0 0 1 12 6c6.5 0 10 6 10 6a17 17 0 0 1-3.2 3.9M6.6 6.6C3.8 8.3 2 12 2 12s3.5 6 10 6c1.6 0 3-.4 4.3-1'/>",
	"lock": "<rect x='5' y='11' width='14' height='10' rx='2'/><path d='M8 11V7a4 4 0 0 1 8 0v4'/>",
	"unlock": "<rect x='5' y='11' width='14' height='10' rx='2'/><path d='M8 11V7a4 4 0 0 1 7.5-2'/>",
	"multi": "<rect x='3' y='3' width='11' height='11' rx='2'/><rect x='10' y='10' width='11' height='11' rx='2'/>",
	"focus": "<circle cx='12' cy='12' r='3'/><path d='M3 8V5a2 2 0 0 1 2-2h3M16 3h3a2 2 0 0 1 2 2v3M21 16v3a2 2 0 0 1-2 2h-3M8 21H5a2 2 0 0 1-2-2v-3'/>",
	"group": "<rect x='3' y='3' width='18' height='18' rx='3' stroke-dasharray='3 3'/><rect x='7' y='7' width='5' height='5'/><rect x='12' y='12' width='5' height='5'/>",
	"ungroup": "<rect x='4' y='4' width='7' height='7' rx='1'/><rect x='13' y='13' width='7' height='7' rx='1'/><path d='M14 5h5v5M10 19H5v-5'/>",
	"magnet": "<path d='M6 3v8a6 6 0 0 0 12 0V3h-4v8a2 2 0 0 1-4 0V3z'/><path d='M6 7h4M14 7h4'/>",
	"grid": "<path d='M3 9h18M3 15h18M9 3v18M15 3v18'/><rect x='3' y='3' width='18' height='18' rx='2'/>",
	"camera": "<path d='M4 8h3l2-3h6l2 3h3v11H4z'/><circle cx='12' cy='13' r='3.5'/>",
	"person": "<circle cx='12' cy='6' r='3'/><path d='M12 9v7M12 16l-4 6M12 16l4 6M6 12h12'/>",
	"jump": "<path d='M12 20V5M6 11l6-6 6 6'/><path d='M5 21h14'/>",
	"settings": "<circle cx='12' cy='12' r='3'/><path d='M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1'/>",
	"import": "<path d='M12 3v12M7 10l5 5 5-5'/><path d='M4 17v3h16v-3'/>",
	"export": "<path d='M12 15V3M7 8l5-5 5 5'/><path d='M4 17v3h16v-3'/>",
	"history": "<path d='M3 12a9 9 0 1 0 3-6.7L3 8'/><path d='M3 3v5h5M12 7v5l3 3'/>",
	"search": "<circle cx='11' cy='11' r='6.5'/><path d='M16 16l5 5'/>",
	"info": "<circle cx='12' cy='12' r='9'/><path d='M12 11v6M12 7.5v.5'/>",
	"warning": "<path d='M12 3l10 18H2z'/><path d='M12 10v5M12 18v.5'/>",
	"error": "<circle cx='12' cy='12' r='9'/><path d='M9 9l6 6M15 9l-6 6'/>",
	"up": "<path d='M6 15l6-6 6 6'/>",
	"down": "<path d='M6 9l6 6 6-6'/>",
	"right": "<path d='M9 6l6 6-6 6'/>",
	"tree": "<path d='M12 3l6 9h-3l4 6H5l4-6H6z'/><path d='M12 18v3'/>",
	"water": "<path d='M2 9c2.5-2 4.5-2 7 0s4.5 2 7 0 4.5-2 6 0M2 15c2.5-2 4.5-2 7 0s4.5 2 7 0 4.5-2 6 0'/>",
	"brush": "<path d='M18 3l3 3-9 9-3-3z'/><path d='M9 12c-3 0-5 2-5 5 0 1.5-1 3-2 3 4 1 9 0 9-5'/>",
	"light": "<path d='M9 18h6M10 21h4M12 3a6 6 0 0 0-3.5 10.9c.6.5 1 1.2 1 2.1h5c0-.9.4-1.6 1-2.1A6 6 0 0 0 12 3z'/>",
	"flag": "<path d='M5 21V4M5 4h11l-2 4 2 4H5'/>",
	"text": "<path d='M5 6V4h14v2M12 4v16M9 20h6'/>",
	"image": "<rect x='3' y='4' width='18' height='16' rx='2'/><circle cx='9' cy='10' r='2'/><path d='M21 16l-5-5-9 9'/>",
	"hierarchy": "<rect x='9' y='3' width='6' height='5' rx='1'/><rect x='3' y='16' width='6' height='5' rx='1'/><rect x='15' y='16' width='6' height='5' rx='1'/><path d='M12 8v4M6 16v-4h12v4'/>",
	"parent": "<path d='M5 19h9a5 5 0 0 0 5-5V5'/><path d='M15 9l4-4 4 4'/>",
	"dot": "<circle cx='12' cy='12' r='4' fill='#e6e8ee'/>",
	"panel": "<rect x='3' y='4' width='18' height='16' rx='2'/><path d='M14 4v16'/>",
	"globe": "<circle cx='12' cy='12' r='9'/><path d='M3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18'/>",
	"wedge": "<path d='M3 19h18L3 7z'/>",
	"sphere": "<circle cx='12' cy='12' r='8'/><path d='M4 12c3 3 13 3 16 0'/>",
	"cylinder": "<ellipse cx='12' cy='6' rx='7' ry='3'/><path d='M5 6v12c0 1.7 3.1 3 7 3s7-1.3 7-3V6'/>",
	"cone": "<path d='M12 3l7 15M12 3L5 18'/><ellipse cx='12' cy='18' rx='7' ry='3'/>",
	"capsule": "<rect x='7' y='3' width='10' height='18' rx='5'/>",
	"torus": "<ellipse cx='12' cy='12' rx='9' ry='5'/><ellipse cx='12' cy='11.5' rx='3.5' ry='1.6'/>",
	"pyramid": "<path d='M12 3l9 16H3z'/><path d='M12 3l2 16'/>",
	"box": "<path d='M12 2l9 5v10l-9 5-9-5V7z'/><path d='M3 7l9 5 9-5M12 12v10'/>",
	"grabber": "<circle cx='12' cy='12' r='9' fill='#e6e8ee' stroke='#3d7eff' stroke-width='3'/>",
	"check_off": "<rect x='3.5' y='3.5' width='17' height='17' rx='4' stroke='#9aa1b2'/>",
	"check_on": "<rect x='3' y='3' width='18' height='18' rx='4' fill='#3d7eff' stroke='#3d7eff'/><path d='M7 12.5l3.2 3.2L17 9' stroke='#ffffff' stroke-width='2.4'/>",
	"world": "<circle cx='12' cy='12' r='9'/><path d='M3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18'/>",
}

static var _cache := {}


static func svg(name: String, color := "#e6e8ee") -> String:
	var body: String = PATHS.get(name, PATHS["dot"])
	if color != "#e6e8ee":
		body = body.replace("#e6e8ee", color)
	var stroke := STROKE.replace("#e6e8ee", color)
	return "<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24'><g %s>%s</g></svg>" % [stroke, body]


## Textura do ícone. `size` em unidades de interface (o tamanho em pixels
## leva em conta a escala da tela).
static func get_icon(name: String, size := 22.0, color := "#e6e8ee") -> Texture2D:
	var px_scale := maxf(1.0, App.ui_scale) if Engine.get_main_loop() else 1.0
	var key := "%s|%s|%s|%s" % [name, size, color, px_scale]
	if _cache.has(key):
		return _cache[key]
	var img := Image.new()
	var err := img.load_svg_from_string(svg(name, color), size * px_scale / 24.0)
	if err != OK:
		return null
	var tex := ImageTexture.create_from_image(img)
	# A imagem tem a resolução real da tela, mas a textura informa o tamanho
	# lógico: assim o ícone fica nítido e do tamanho certo em qualquer controle.
	tex.set_size_override(Vector2i(roundi(size), roundi(size)))
	_cache[key] = tex
	return tex


static func clear_cache() -> void:
	_cache.clear()
