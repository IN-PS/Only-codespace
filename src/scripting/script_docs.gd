class_name PSScriptDocs
extends RefCounted
## Referência rápida da API de scripts (a versão completa está em docs/SCRIPTS.md).

const TEXT := """[b]Linguagem[/b]
Estilo Lua: [code]local x = 10[/code], [code]if x > 5 then ... end[/code], [code]for i = 1, 10 do ... end[/code], [code]while ... do ... end[/code], [code]function nome(a, b) ... end[/code], tabelas [code]{1, 2, nome = "a"}[/code], textos com [code]..[/code] para juntar.
Comentários começam com [code]--[/code].

[b]Eventos (crie a função com o nome exato)[/b]
[code]on_start()[/code] — quando o teste começa
[code]on_update(dt)[/code] — a cada quadro; dt = segundos
[code]on_touch()[/code] / [code]on_leave()[/code] — jogador encostou / saiu
[code]on_click()[/code] — jogador tocou no objeto na tela

[b]O objeto do script: self[/b]
Campos: [code]name, position, rotation, size, color, visible, solid, velocity, parent, exists[/code]
Métodos: [code]self:move(x, y, z)[/code], [code]self:rotate(x, y, z)[/code] (graus), [code]self:destroy()[/code], [code]self:clone()[/code], [code]self:applyImpulse(x, y, z)[/code], [code]self:children()[/code], [code]self:find(nome)[/code], [code]self:lookAt(vec)[/code], [code]self:set(chave, valor)[/code], [code]self:get(chave)[/code]

[b]Jogador: player[/b]
[code]position, velocity, speed, jumpPower, onGround, inWater, cameraMode[/code]
[code]player:respawn()[/code], [code]player:setSpawn(vec)[/code]

[b]Mundo: world[/b]
[code]world.find(nome)[/code], [code]world.findAll(nome)[/code], [code]world.objects()[/code]
[code]world.create("box", vec(0, 5, 0), "dynamic")[/code] — formas: box, sphere, cylinder, cone, capsule, wedge, torus, pyramid
[code]world.gravity[/code], [code]world.time[/code]

[b]Tela: ui[/b]
[code]ui.message(texto, segundos)[/code], [code]ui.text(texto)[/code] (topo da tela)

[b]Outros[/b]
[code]vec(x, y, z)[/code] — vetor (soma, subtração, [code]v * 2[/code], [code]v:length()[/code], [code]v:normalized()[/code], [code]v:distance(w)[/code])
[code]rgb(r, g, b)[/code] (0 a 1) ou [code]hex("#ff8800")[/code] — cores
[code]time()[/code] — segundos desde o início
[code]after(segundos, função)[/code], [code]every(segundos, função)[/code], [code]cancel(id)[/code]
[code]shared[/code] — tabela compartilhada entre todos os scripts (placar etc.)
[code]print(...)[/code], [code]warn(...)[/code] — mensagens no console
Bibliotecas: [code]math[/code], [code]string[/code], [code]table[/code] (subconjunto), [code]pairs, ipairs, tostring, tonumber, type, pcall, error[/code]

[b]Segurança e limites[/b]
Scripts rodam isolados: não acessam arquivos, internet nem o sistema. Cada chamada tem limite de instruções; um loop infinito é interrompido e o script é parado com uma mensagem no console. Sem corrotinas/wait(): use [code]after[/code] e [code]every[/code]."""


static func open() -> void:
	var m := PSModal.create("Referência da API de scripts", 600.0)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.text = TEXT
	rt.custom_minimum_size = Vector2(0, minf(App.get_ui_size().y * 0.62, 520.0))
	rt.add_theme_font_size_override("normal_font_size", 14)
	rt.add_theme_font_size_override("mono_font_size", 13)
	rt.add_theme_color_override("default_color", PSTheme.TEXT)
	rt.selection_enabled = true
	m.body.add_child(rt)
	m.add_button("Fechar", Callable(), "AccentButton")
	m.show_modal()
