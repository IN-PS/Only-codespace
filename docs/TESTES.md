# Testes

## Automatizados

```bash
godot --headless --path . --import
GODOT=godot tools/check_scripts.sh                       # compila todos os scripts
godot --headless --path . res://tests/run_tests.tscn     # roda a suíte
godot --headless --path . res://tests/run_tests.tscn -- --only=lua   # só um arquivo
```

Rodam no CI (GitHub Actions) com o Godot 4.7.2 oficial a cada envio. Resultado atual: **61 testes, 0 falhas**.

| Arquivo | O que cobre |
|---|---|
| `test_data_store.gd` | sanitização de arquivos ruins/maliciosos, salvar/carregar, cópia `.bak` após corrupção, autosave e recuperação, versões, renomear/duplicar/excluir, backup `.zip` ida e volta, backups maliciosos recusados |
| `test_editor.gd` | modelos carregados, adicionar/duplicar/excluir com desfazer/refazer, agrupar/desagrupar mantendo posições, definir pai e bloqueio de ciclos, serialização, salvar; **toques simulados**: tocar seleciona, um dedo gira a câmera, pinça aproxima, arrastar a seta do gizmo move em X com encaixe; girar e escalar; arrastar sobre superfícies; campo numérico com conta; todos os painéis abrem |
| `test_terrain_assets.gd` | pincéis do terreno, raio contra o terreno, vegetação, geradores, validação de assinaturas/tamanhos/URLs/Draco, importação de GLB e textura (inclusive sem extensão, como URIs do Android), modelo com colisão no modo de teste |
| `test_lua.gd` | aritmética e precedência, lógica, laços, closures, varargs, métodos, tabelas e textos, erros com linha, `pcall`, erros de sintaxe, **isolamento** (sem `os`, `io`, `load`...), loop infinito/recursão/tabelas e textos gigantes interrompidos, vetores |
| `test_script_api.gd` | API documentada em `SCRIPTS.md` num teste de jogo real |
| `test_play.gd` | jogador nasce e fica no chão, anda e pula, objeto dinâmico cai, scripts rodam, erros não derrubam o jogo, moeda coletada ao encostar, `on_click`, natação, reiniciar e pausar |
| `test_templates.gd` | todos os modelos de projeto rodam sem erros; o percurso é jogável (moeda conta ponto, placar, zona de queda) |
| `test_acceptance.gd` | critérios de aceitação do pedido (ver abaixo) |

### Critérios de aceitação

| Critério | Como é verificado |
|---|---|
| Criar um projeto sem computador | `test_create_project_and_move_with_finger` (fluxo do app) + roteiro manual |
| Adicionar e mover objetos com os dedos | mesmo teste: toque e arraste simulados movem a peça |
| Importar um modelo 3D compatível | `test_import_model_into_world` |
| Salvar e reabrir o projeto | `test_save_and_reopen_everything` (objetos, terreno, ambiente, scripts) |
| Testar um cenário jogável | `test_obby_is_playable` |
| Recuperar um projeto após fechar o aplicativo | `test_recover_after_app_closed` (simula ir para segundo plano e o processo morrer) |
| Funcionar sem conexão | `test_no_network_apis_used` (o código não usa nenhuma API de rede) |

## Visuais (capturas)

`tools/screenshot.tscn` abre o app, percorre as telas e salva capturas. Com Xvfb e OpenGL por software:

```bash
xvfb-run -a -s "-screen 0 2560x2560x24" godot --path . --rendering-driver opengl3 \
  --resolution 1080x2340 res://tools/screenshot.tscn -- --shots=/tmp/capturas --ui-scale=2.75 --mobile
```

As imagens em `docs/img/` foram geradas assim (retrato 1080×2340 e paisagem 2340×1080, escala 2,75 como num celular de ~420 dpi).

## Roteiro manual no celular

O que os testes automatizados **não** conseguem verificar e precisa ser conferido num aparelho real:

1. Instalar o APK e abrir: a lista de projetos aparece com textos legíveis e botões fáceis de tocar.
2. **Novo projeto → Percurso de plataformas**. Girar a câmera com um dedo, aproximar com pinça, mover com dois dedos.
3. Tocar no botão **+** e adicionar um Cubo; arrastar o cubo com o dedo; usar as setas do gizmo; girar e escalar.
4. Abrir **Propriedades**: tocar no campo X e digitar um número (o teclado numérico deve aparecer); trocar a cor.
5. Girar o celular: o layout passa para paisagem (painel à direita) e volta.
6. **Testar**: andar com o joystick, olhar arrastando à direita, pular, pegar moedas, cair e voltar ao início; pausar, reiniciar e voltar.
7. Aba **Assets → Modelo**: o seletor de arquivos do Android abre; importar um `.glb` (ex.: de Downloads) e inserir no mundo.
8. Aba **Scripts**: criar um script a partir de um modelo, editar com o teclado (o painel deve subir acima do teclado) e anexar a um objeto.
9. Salvar, fechar o app pelo gerenciador de tarefas, reabrir: o projeto continua lá.
10. Fazer uma alteração e, **sem salvar**, mandar o app para segundo plano e encerrá-lo; ao reabrir o projeto, deve aparecer **Recuperar alterações?**.
11. **Menu → Exportar backup**: o seletor do Android pede onde salvar o `.zip`; depois, **Importar** na tela inicial.
12. Botão **voltar** do Android: fecha diálogos e painéis, e no editor pergunta se deseja salvar antes de sair.
13. Modo avião: tudo acima continua funcionando.
14. Observar aquecimento e fluidez num aparelho de entrada; se necessário, em **Configurações** reduzir a resolução 3D e desligar sombras.
