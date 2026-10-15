class_name PSScriptTemplates
extends RefCounted
## Modelos de scripts prontos para começar.

const LIST := [
	{"key": "spin", "name": "Girar sem parar", "code": """-- Gira o objeto continuamente.
local velocidade = 90 -- graus por segundo

function on_update(dt)
  self:rotate(0, velocidade * dt, 0)
end
"""},
	{"key": "platform", "name": "Plataforma que vai e volta", "code": """-- Move o objeto para os lados, indo e voltando.
-- Dica: em Propriedades > Física, escolha "Móvel por script"
-- para que o jogador seja carregado junto.
local distancia = 6     -- metros
local velocidade = 1.5
local inicio

function on_start()
  inicio = self.position
end

function on_update(dt)
  local desloc = math.sin(time() * velocidade) * distancia / 2
  self.position = inicio + vec(desloc, 0, 0)
end
"""},
	{"key": "coin", "name": "Moeda coletável", "code": """-- Gira, e ao ser tocada some e conta um ponto.
-- "shared" é uma tabela compartilhada por todos os scripts.
function on_update(dt)
  self:rotate(0, 120 * dt, 0)
end

function on_touch()
  shared.moedas = (shared.moedas or 0) + 1
  ui.text("Moedas: " .. shared.moedas)
  self:destroy()
end
"""},
	{"key": "message", "name": "Mensagem ao tocar", "code": """-- Mostra uma mensagem quando o jogador encosta.
local mensagem = "Olá, explorador!"

function on_touch()
  ui.message(mensagem, 3)
end
"""},
	{"key": "finish", "name": "Chegada (vitória)", "code": """-- Mostra o tempo do percurso quando o jogador chega.
local terminou = false

function on_touch()
  if terminou then return end
  terminou = true
  local segundos = math.floor(time())
  ui.message("Você chegou em " .. segundos .. " segundos!", 6)
  print("Percurso concluído em", segundos, "s")
end
"""},
	{"key": "trap", "name": "Armadilha (volta ao início)", "code": """-- Quem encostar volta para o ponto de início.
function on_touch()
  ui.message("Ops! Tente de novo.", 1.5)
  player:respawn()
end
"""},
	{"key": "teleport", "name": "Teleporte", "code": """-- Leva o jogador até o objeto chamado "Destino".
function on_touch()
  local destino = world.find("Destino")
  if destino then
    player.position = destino.position + vec(0, 2, 0)
  else
    warn("Crie um objeto chamado Destino")
  end
end
"""},
	{"key": "door", "name": "Porta que abre ao tocar na tela", "code": """-- Toque no objeto (na tela) para abrir ou fechar.
local aberta = false

function on_click()
  aberta = not aberta
  self.solid = not aberta
  self.visible = not aberta
  ui.message(aberta and "Porta aberta" or "Porta fechada", 1)
end
"""},
	{"key": "trampoline", "name": "Trampolim", "code": """-- Lança o jogador para cima ao encostar.
local forca = 18

function on_touch()
  local v = player.velocity
  player.velocity = vec(v.x, forca, v.z)
end
"""},
	{"key": "color", "name": "Piscar cores", "code": """-- Troca a cor do objeto a cada meio segundo.
local cores = { rgb(1, 0.3, 0.3), rgb(0.3, 1, 0.4), rgb(0.3, 0.5, 1) }
local i = 1

every(0.5, function()
  i = i % #cores + 1
  self.color = cores[i]
end)
"""},
	{"key": "timer", "name": "Cronômetro na tela", "code": """-- Mostra o tempo de jogo no topo da tela.
-- Funciona bem como script global (sem objeto).
function on_update(dt)
  ui.text(string.format("Tempo: %.1f s", time()))
end
"""},
	{"key": "spawner", "name": "Chuva de bolas", "code": """-- Cria uma bola acima deste objeto a cada 2 segundos.
local maximo = 20
local criadas = 0

every(2, function()
  if criadas >= maximo then return end
  criadas = criadas + 1
  local bola = world.create("sphere", self.position + vec(0, 6, 0), "dynamic")
  bola.color = rgb(math.random(), math.random(), math.random())
end)
"""},
	{"key": "empty", "name": "Vazio (eventos)", "code": """-- Eventos disponíveis (apague os que não usar):

function on_start()
  print("Olá do script de", self and self.name or "mundo")
end

function on_update(dt)
end

function on_touch()
end

function on_click()
end
"""},
]


static func get_code(key: String) -> String:
	for t in LIST:
		if t["key"] == key:
			return t["code"]
	return ""
