# Scripts — linguagem e API do jogo

Os scripts do Pocket Studio 3D usam uma linguagem **no estilo Lua**, executada por um interpretador escrito para o app (`src/scripting/`). Ele roda **isolado**: o script só enxerga as funções listadas aqui.

## Como usar

1. Aba **Scripts** (ícone `</>`) → **+** → escolha um modelo.
2. Selecione objetos na vista e toque em **Anexar à seleção** (ou, em **Propriedades → Script**, escolha o script do objeto).
3. Toque em **Testar**. Mensagens de `print` e erros aparecem no **Console** e no botão vermelho de erros durante o teste.

Cada objeto com script ganha uma **instância própria**: variáveis `local` e globais de um objeto não afetam outro. Para compartilhar dados entre scripts use a tabela `shared`.

Um script marcado como **global** (menu ☰ do script) roda uma vez, sem objeto (`self` é `nil`) — útil para placar, cronômetro e regras do jogo.

## Eventos

Defina funções com estes nomes exatos; o jogo as chama quando acontece o evento.

| Função | Quando |
|---|---|
| `on_start()` | uma vez, quando o teste começa |
| `on_update(dt)` | a cada quadro; `dt` = segundos desde o quadro anterior |
| `on_touch()` | o jogador encostou no objeto (ou em qualquer peça do grupo) |
| `on_leave()` | o jogador deixou de encostar |
| `on_click()` | o jogador tocou no objeto na tela (também vale para scripts de grupos que contêm a peça tocada) |

O código fora das funções roda uma vez antes de `on_start` (bom para variáveis e `every(...)`).

## A linguagem

```lua
-- comentário de uma linha
--[[ comentário
     de várias linhas ]]
local vida = 3                  -- variável local
pontos = 0                      -- global (desta instância)
local nome = "Ana" .. " " .. 1  -- .. junta textos

if vida > 0 and not morto then
  print("vivo")
elseif vida == 0 then
  print("fim")
else
  print("?")
end

for i = 1, 10 do end            -- for numérico (passo opcional: for i = 10, 1, -1)
for k, v in pairs(t) do end     -- percorre uma tabela
for i, v in ipairs(lista) do end
while cond do end
repeat ... until cond

local function soma(a, b) return a + b end
local f = function(...) return select("#", ...) end

local t = {1, 2, 3, nome = "x", [10] = "dez"}
print(#t, t.nome, t[10])

local obj = {v = 2}
function obj:dobro(x) return self.v * x end   -- método com ':'
```

Operadores: `+ - * / // % ^ ..`, `== ~= < <= > >=`, `and or not`, `#` (tamanho). `//` é divisão inteira; `%` segue a regra do Lua (resultado com o sinal do divisor).

Diferenças em relação ao Lua 5.x: **não há** `goto`, metatables, corrotinas (`coroutine`, `wait`), operadores bit a bit, `load`/`require`/`io`/`os`. `string.find` e `string.gsub` fazem busca **simples** de texto (sem padrões `%a`, `.*` etc.). Todos os números são de ponto flutuante.

## Objetos do mundo

`self` é o objeto do script. Outros objetos vêm de `world.find(nome)`, `self.parent`, `self:children()` etc.

### Campos

| Campo | Leitura | Escrita | Observação |
|---|:-:|:-:|---|
| `name` | ✅ | ✅ | texto |
| `id`, `type` | ✅ | | `type`: part, group, model, light, spawn, water, text |
| `position` | ✅ | ✅ | `vec(x, y, z)` no mundo; objetos dinâmicos são teleportados |
| `rotation` | ✅ | ✅ | ângulos em graus |
| `size` | ✅ | ✅ | peças e água: tamanho em metros; modelos e texto: escala |
| `color` | ✅ | ✅ | `rgb(r, g, b)` ou `"#rrggbb"` |
| `visible` | ✅ | ✅ | esconde só o visual (a colisão continua) |
| `solid` | ✅ | ✅ | liga/desliga a colisão (portas, passagens secretas) |
| `velocity` | ✅ | ✅ | só objetos com física **Dinâmico** |
| `parent` | ✅ | | objeto pai ou `nil` |
| `exists` | ✅ | | `false` depois de `destroy()` |

### Métodos

Funcionam com `:` (recomendado) ou `.`.

| Método | Faz |
|---|---|
| `obj:move(x, y, z)` ou `obj:move(vec)` | desloca |
| `obj:rotate(x, y, z)` | gira em graus (eixos do mundo) |
| `obj:lookAt(vec)` | aponta a frente (−Z) para um ponto |
| `obj:destroy()` | remove do mundo (com os filhos) no fim do quadro |
| `obj:clone()` | cria uma cópia (os scripts da cópia também rodam) e a retorna |
| `obj:applyImpulse(x, y, z)` | empurrão (objetos dinâmicos) |
| `obj:children()` | tabela com os filhos diretos |
| `obj:find(nome)` | procura um descendente pelo nome |
| `obj:set(chave, valor)` / `obj:get(chave)` | guarda/lê valores no objeto (números, textos, booleanos, vetores, cores) |

Para um objeto ser **movido por script e carregar o jogador** (plataformas), escolha a física **Móvel por script** em Propriedades.

## Jogador — `player`

| Campo/método | |
|---|---|
| `player.position` | lê/teleporta (`vec`) |
| `player.velocity` | lê/define (ex.: trampolim) |
| `player.speed`, `player.jumpPower` | velocidade de caminhada e força do pulo |
| `player.onGround`, `player.inWater` | somente leitura |
| `player.cameraMode` | `"first"` ou `"third"` |
| `player:respawn()` | volta ao ponto de início |
| `player:setSpawn(vec)` | muda o ponto de reaparecimento (checkpoint) |

## Mundo — `world`

| | |
|---|---|
| `world.find(nome)` | primeiro objeto com o nome, ou `nil` |
| `world.findAll(nome)` | tabela com todos os objetos com o nome |
| `world.objects()` | todos os objetos |
| `world.create(forma, vec, física)` | cria uma peça: formas `box, sphere, cylinder, cone, capsule, wedge, torus, pyramid`; física opcional `"static"`, `"dynamic"`, `"kinematic"`, `"none"` |
| `world.gravity` | lê/altera a gravidade |
| `world.time` | segundos desde o início |

## Tela — `ui`

| | |
|---|---|
| `ui.message(texto, segundos)` | mensagem grande no centro |
| `ui.text(texto)` | texto fixo no topo (placar, tempo) |

## Funções globais

| | |
|---|---|
| `vec(x, y, z)` | vetor; soma/subtração entre vetores, `v * n`, `v / n`, `-v`, `v.x`, `v:length()`, `v:normalized()`, `v:distance(w)`, `v:dot(w)`, `v:cross(w)`, `v:lerp(w, t)` |
| `rgb(r, g, b [, a])` | cor com componentes de 0 a 1; `hex("#ff8800")` também cria cor |
| `time()` | segundos desde o início do teste |
| `after(seg, função)` | chama uma vez depois de `seg` segundos; retorna um id |
| `every(seg, função)` | chama repetidamente; retorna um id |
| `cancel(id)` | cancela um temporizador |
| `print(...)`, `warn(...)` | mensagens no console |
| `shared` | tabela compartilhada entre todos os scripts |
| `pairs, ipairs, select, type, tostring, tonumber, pcall, error, assert, unpack` | como no Lua |

Bibliotecas:

- `math`: `abs, floor, ceil, round, sqrt, sin, cos, tan, asin, acos, atan(y, x), exp, log, fmod, deg, rad, min, max, clamp, lerp, sign, random, randomseed, pi, huge`
- `string` (também como método, `("abc"):upper()`): `len, upper, lower, rep, reverse, sub, find, gsub, format, byte, char, split, trim`
- `table`: `insert, remove, concat, sort, unpack`

`string.format` aceita `%d %i %f %.Nf %s %x %X %%`.

## Exemplos

**Moeda com placar**

```lua
function on_update(dt)
  self:rotate(0, 120 * dt, 0)
end

function on_touch()
  shared.moedas = (shared.moedas or 0) + 1
  ui.text("Moedas: " .. shared.moedas)
  self:destroy()
end
```

**Plataforma que vai e volta** (física *Móvel por script*)

```lua
local inicio
function on_start() inicio = self.position end
function on_update(dt)
  self.position = inicio + vec(math.sin(time() * 1.5) * 3, 0, 0)
end
```

**Checkpoint**

```lua
function on_touch()
  player:setSpawn(self.position + vec(0, 1, 0))
  ui.message("Checkpoint!", 1.5)
end
```

**Porta por toque na tela**

```lua
local aberta = false
function on_click()
  aberta = not aberta
  self.solid = not aberta
  self.visible = not aberta
end
```

## Segurança e limites

- Sem acesso a arquivos, internet, sistema operacional ou ao motor Godot: só existe o que está nesta página. Assets e projetos importados nunca executam código automaticamente; scripts só rodam no **modo de teste**.
- Limite de instruções por chamada: 300 000 no código inicial e `on_start`, 30 000 por `on_update`, 60 000 por evento ou temporizador. Um loop infinito é interrompido, o erro vai para o console e **o script é parado** para proteger o jogo.
- Profundidade de chamadas: 64 (recursão infinita é interrompida). Tabelas: até 100 000 itens. Textos: até 1 000 000 de caracteres.
- Até 1 000 objetos criados por scripts (`world.create` + `clone`) e 500 temporizadores ativos por teste.
- Um erro em `on_update` desativa só o `on_update` daquele script; o resto do jogo continua.
- Se os scripts levarem mais de 12 ms num quadro, o console avisa que o jogo pode ficar lento em celulares.
