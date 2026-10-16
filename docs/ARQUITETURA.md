# Arquitetura

## Visão geral

```
main.gd ──► PSProjectBrowser (lista de projetos)
        ──► PSEditor ─────────► PSWorld (modo EDIT) ◄── PSAssetLibrary
        │     │  câmera, gizmo, gestos, painéis, desfazer, autosave
        │     └─ build_project_data()  ──────────────┐
        └─► PSPlaySession ◄──────────────────────────┘ (cópia dos dados)
              PSWorld (modo PLAY) + PSPlayer + PSScriptRuntime
```

- A interface é montada **em código** (GDScript), sem cenas `.tscn` complexas. Isso deixa o layout responsivo (retrato/paisagem) sob controle total e testável sem o editor visual.
- **Um único formato de dados** (dicionários JSON) descreve o mundo. O editor e o modo de teste constroem nós a partir dele; desfazer/refazer, salvar, versões, backups e o modo de teste usam esse mesmo formato.
- O modo de teste monta uma **cópia nova** do mundo a partir dos dados: testar nunca altera o que está sendo editado, e “Reiniciar” é só reconstruir.

## Pastas

| Pasta | Conteúdo |
|---|---|
| `src/autoload/app.gd` | Singleton `App`: configurações (`user://settings.json`), console/registro, escala da interface, ações de teclado |
| `src/core/ps_data.gd` | Esquema do projeto, valores padrão e **sanitização** de tudo que vem do disco |
| `src/core/project_store.gd` | Arquivos de projeto: gravação atômica, `.bak`, autosave, versões, backup `.zip` |
| `src/core/asset_validator.gd` | Validação de GLB/glTF e imagens |
| `src/core/asset_library.gd` | Assets do projeto: importação, cache de modelos, carregamento progressivo |
| `src/core/prefabs.gd`, `templates.gd` | Biblioteca interna e modelos de projeto |
| `src/world/world.gd` | `PSWorld`: objetos, hierarquia, construção de nós por tipo e por modo, seleção por raio, ambiente |
| `src/world/primitives.gd` | Malhas unitárias, formas de colisão, materiais (com cache) |
| `src/world/terrain.gd` | Terreno em blocos, pincéis, geradores, vegetação, colisão |
| `src/editor/` | `PSEditor` e componentes: câmera orbital, gestos, gizmo, contorno de seleção, grade, desfazer, menu Adicionar |
| `src/editor/panels/` | Painéis Hierarquia, Propriedades, Terreno, Assets, Scripts, Mundo, Console |
| `src/play/` | Sessão de teste, personagem, joystick virtual |
| `src/scripting/` | Analisador, interpretador, tipos de valor, API do jogo, runtime, modelos e documentação |
| `src/ui/` | Tema, ícones SVG, componentes (campo numérico, seções, diálogos), seletor de arquivos, tela de projetos |

## Decisões técnicas

### Renderização e desempenho
- Renderizador **Compatibility** (OpenGL ES 3.0): o que mais roda em celulares de entrada.
- Escala da interface automática (1 unidade ≈ 1 dp no Android) e **resolução 3D separada** (`scaling_3d_scale`, padrão 80% no Android) — interface nítida mesmo renderizando o 3D em resolução menor.
- Editor limitado a 30 FPS (configurável) para economizar bateria; modo de teste a 60.
- Malhas e materiais compartilhados por cache; vegetação com `MultiMesh`; terreno em blocos de 16×16 (um pincel reconstrói só os blocos tocados); colisão do terreno com `HeightMapShape3D`.
- Física com **Jolt** (incluída no Godot 4.7).
- Modelos importados carregam **um por quadro** em segundo plano, com caixa provisória no lugar, para abrir projetos grandes sem travar a interface. (O parse do glTF em si ocorre na thread principal; veja LIMITACOES.)

### Objetos e hierarquia
- Cada objeto é um nó raiz (`Node3D`, ou corpo físico no modo de teste) com nós internos prefixados por `_` (`_visual`, `_pick`, `_shape`...) e os filhos.
- Transformações de hierarquia são **rígidas** (posição + rotação); o **tamanho** de uma peça só afeta a própria peça. Isso evita escalas não uniformes herdadas, que a física não suporta bem, e segue o modelo mental de “peças” de editores como o Roblox Studio.
- No editor, cada objeto tem um corpo de seleção numa camada exclusiva; tocar na tela faz um raio contra essa camada. Objetos travados são ignorados pelo toque.
- No modo de teste, a física escolhida vira `StaticBody3D`, `RigidBody3D`, `AnimatableBody3D` ou nenhum corpo. Filhos de um objeto dinâmico contribuem com suas formas para o corpo do pai (corpo composto).

### Toque
- `PSViewportInput` fica atrás de todos os painéis e só recebe toques que nenhum painel consumiu. Ele traduz eventos em gestos (toque, toque duplo, toque longo, arraste de um dedo, dois dedos com pinça) e ignora eventos de mouse emulados a partir do toque.
- O gizmo testa o toque em **espaço de tela** (distância do dedo até o eixo projetado, tolerância de 26 dp) e mantém tamanho constante na tela.

### Desfazer/refazer
`PSUndo` usa o `UndoRedo` do Godot guardando o **estado completo** (dicionário) de cada objeto afetado antes e depois, incluindo pai e posição entre irmãos. Terreno e ambiente usam instantâneos próprios.

### Salvamento confiável
- Gravação atômica: escreve `arquivo.tmp`, relê e valida o JSON, copia o arquivo atual para `.bak` e só então substitui.
- Autosave periódico e ao ir para segundo plano (`NOTIFICATION_APPLICATION_PAUSED`/`FOCUS_OUT`), num arquivo separado; ao abrir, o app oferece recuperar se ele for mais novo que o salvamento.
- Ao carregar, `PSData.sanitize_project()` corrige ou descarta qualquer campo inválido.

### Segurança
- Assets: só extensões de dados; assinatura binária conferida; limites de tamanho/vértices/nós; glTF sem URLs, caminhos absolutos ou `..`; extensões glTF obrigatórias não suportadas são recusadas; câmeras/luzes do arquivo são descartadas.
- Backups `.zip`: só `project.json`, `backup.json` e `assets/<arquivo>` com extensão permitida; nada fora da pasta do novo projeto.
- Scripts: interpretador próprio, sem acesso ao motor; limites de instruções, recursão, tabelas, textos, objetos criados e temporizadores. Nada roda ao abrir um projeto — só no modo de teste.
- Nenhuma API de rede é usada pelo app (há um teste que verifica isso).

### Linguagem de scripts
`PSLuaParser` gera uma árvore de arrays com códigos inteiros; `PSLuaInterp` a percorre. Escopos são pares `[variáveis, pai]`; closures capturam o escopo. Cada objeto com script tem um ambiente global próprio (bibliotecas copiadas), e cada função lembra o ambiente onde foi criada. Erros são propagados por estado (`_halt`) — GDScript não tem exceções — e chegam ao console com nome do script, linha e trilha de chamadas. Ao fim do teste, `dispose()` quebra os ciclos closure↔escopo para liberar memória.
