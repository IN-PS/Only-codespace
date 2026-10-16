# Limitações conhecidas (v0.1.0)

Lista honesta do que **não** existe ou tem restrições. Nada abaixo é simulado na interface: recursos ausentes simplesmente não aparecem.

## Validação no Android

- O APK é gerado e assinado automaticamente pelo CI com o Godot 4.7.2 oficial, e o app foi exercitado por **61 testes automatizados** e por capturas em resolução de celular (1080×2340, escala 2,75, OpenGL por software). **Ele ainda não foi executado num aparelho Android físico** durante este desenvolvimento. Itens que dependem do sistema e só podem ser confirmados no aparelho: seletor de arquivos nativo (SAF), teclado virtual, área segura/entalhe, botão voltar, desempenho e temperatura em celulares de entrada. Use o roteiro em [TESTES.md](TESTES.md).

## Ainda não implementado

- **Multiplayer / colaboração online**: previsto para a fase 4 (exige servidor, autenticação e sincronização). Nada de rede existe no app. Ver [ROTEIRO.md](ROTEIRO.md).
- **Exportar o jogo como app independente (APK do jogo)**: não é possível gerar APKs dentro do celular sem o SDK do Android e os templates do Godot. Hoje o jogo é testado dentro do Pocket Studio e compartilhado como backup `.zip`, que outra pessoa abre no Pocket Studio.
- **Integração com Roblox**: nenhuma. Ver [ROTEIRO.md](ROTEIRO.md).
- **Busca de modelos na internet**: a busca é só na biblioteca interna e nos assets do projeto (o app funciona offline).
- **Edição de malha por vértice**: a modelagem é por peças (8 primitivas + grupos). Não há extrusão, booleanas nem edição de vértices.
- **Áudio**: não há sons, músicas nem efeitos.
- **Animações de modelos GLB**: são importadas no arquivo, mas não são reproduzidas no jogo.
- **Interface de jogo pelos scripts**: só `ui.message` e `ui.text` (sem botões ou imagens personalizadas).
- **Idiomas**: somente português.

## Restrições dos recursos existentes

### Assets
- `.gltf` com arquivos externos (`.bin`, imagens) só pode ser importado a partir de uma pasta comum (computador). No Android, o seletor devolve um arquivo por vez sem acesso aos vizinhos: **use GLB** (arquivo único). glTF com recursos embutidos (`data:`) funciona.
- Limites: modelos até 32 MB e 400 000 vértices; texturas até 8 MB e 4096×4096; compressão Draco/meshopt não suportada.
- O parse do glTF ocorre na thread principal: um modelo grande pode causar uma pausa breve quando carregado (os modelos de um projeto carregam um por quadro).
- A colisão de modelos usa a malha (objeto fixo) ou o envoltório convexo (objeto dinâmico); modelos dinâmicos com buracos colidem como se fossem “cheios”.

### Editor
- O histórico de desfazer não é salvo: fechar o projeto o apaga. A edição de texto dos scripts tem o desfazer próprio do editor de código.
- Escalar um **grupo** só pela alça uniforme (o cubo central); escala por eixo é para peças individuais.
- Mover e girar com o gizmo usam os eixos do mundo; escalar usa os eixos da própria peça.
- Textura em peças usa as coordenadas UV da primitiva (esticam se a peça for esticada); ajuste com “Repetição”.

### Terreno
- Um terreno por mundo, quadrado, até 128 m × 128 m, espaçamento fixo de 1 m. Pintura por cor de vértice (sem texturas de terreno).
- A colisão física do terreno é atualizada a cada 0,25 s durante o arraste e ao final da pincelada (o pincel em si usa o mapa de alturas direto, então acompanha o dedo sem atraso).
- Vegetação: árvores, pinheiros e rochas têm colisão simples; arbustos e capim não colidem.

### Modo de teste
- Água: o jogador nada dentro do volume; objetos dinâmicos não boiam.
- Filhos de um objeto dinâmico formam um corpo único com ele; mover um filho por script não move a forma de colisão dele.
- Personagem único (sem multiplayer, sem NPCs).

### Scripts
- Subconjunto de Lua: sem corrotinas/`wait()` (use `after`/`every`), sem metatables, sem padrões em `string.find/gsub`, sem operadores bit a bit, sem `goto`.
- Limites de segurança descritos em [SCRIPTS.md](SCRIPTS.md#segurança-e-limites).
- Interpretado em GDScript: adequado para lógica de jogo simples; centenas de scripts com `on_update` pesado podem pesar em celulares modestos (o console avisa).

### Plataforma
- Requer Android 7.0+ com OpenGL ES 3.0. Aparelhos só com OpenGL ES 2.0 não são suportados.
- Desinstalar o app apaga os projetos (ficam no armazenamento interno). **Exporte backups.**
- O APK de depuração do CI é assinado com uma chave de depuração; para distribuir use uma chave de release ([COMPILAR_ANDROID.md](COMPILAR_ANDROID.md)).
