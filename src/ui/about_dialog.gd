class_name PSAboutDialog
extends RefCounted
## Ajuda rápida, créditos e avisos legais.

const HELP := """[b]Gestos na vista 3D[/b]
• Toque: seleciona. Toque de novo em um grupo para entrar nele.
• Um dedo arrastando no vazio: gira a câmera.
• Dois dedos: arrastam a vista e aproximam/afastam (pinça).
• Toque duplo: centraliza no objeto.
• Toque longo em um objeto: menu rápido (duplicar, excluir, travar…).
• Ferramenta Mover: arraste o próprio objeto para deslizá-lo sobre as superfícies, ou use as setas coloridas para mover em um eixo. A bolinha branca move no plano do chão.
• Girar: arraste um dos anéis. Escalar: arraste os cubinhos (ou o cubo central para escala uniforme).
• O ímã liga/desliga o encaixe na grade.

[b]Painéis[/b]
Hierarquia, Propriedades, Terreno, Assets, Scripts, Mundo e Console ficam nas abas. Toque na aba ativa para recolher o painel.

[b]Salvamento[/b]
O projeto fica salvo só no aparelho, sem precisar de internet. Há salvamento automático; se o aplicativo fechar de repente, ao reabrir o projeto você poderá recuperar as alterações. Use o menu para guardar versões e exportar backups (.zip).
"""

const LEGAL := """[b]Pocket Studio 3D %s[/b]
Feito com o motor Godot Engine (licença MIT, © Juan Linietsky, Ariel Manzur e colaboradores).

O Pocket Studio 3D é um projeto independente. [b]Não é o Roblox Studio[/b], não é afiliado à Roblox Corporation e não lê nem publica arquivos do Roblox. O motor de jogo e o formato de projeto são próprios.

Os modelos da biblioteca interna foram criados para este aplicativo e são de domínio público (CC0). Assets importados pertencem aos seus autores: confira a licença registrada em cada um antes de publicar um jogo."""


static func open() -> void:
	var m := PSModal.create("Ajuda e sobre", 560.0)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = false
	rt.scroll_active = true
	rt.text = HELP + "\n" + (LEGAL % App.VERSION)
	rt.custom_minimum_size = Vector2(0, minf(App.get_ui_size().y * 0.6, 460.0))
	rt.add_theme_font_size_override("normal_font_size", 14)
	rt.add_theme_font_size_override("bold_font_size", 15)
	m.body.add_child(rt)
	m.add_button("Fechar", Callable(), "AccentButton")
	m.show_modal()
