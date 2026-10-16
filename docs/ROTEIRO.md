# Roteiro

## Situação por fase

| Fase | Item | Situação |
|---|---|---|
| 1 | Interface do editor, vista 3D, primitivas e transformações, câmera por toque, salvar/abrir | ✅ |
| 2 | Importação GLB/glTF, editor de materiais, terreno, modo de teste | ✅ |
| 3 | Sistema de scripts, física e colisões, biblioteca de assets | ✅ |
| 3 | Exportação de jogos independentes | ❌ ver abaixo |
| 4 | Colaboração online e multiplayer | ❌ não iniciado |
| 4 | Integrações oficiais permitidas | 🔍 pesquisa (abaixo) |

## Próximos passos sugeridos (sem custo)

1. **Validação em aparelhos reais** com o roteiro de [TESTES.md](TESTES.md), começando por um celular de entrada (2–3 GB de RAM).
2. Sons simples (biblioteca interna CC0) e API `sound.play()` para scripts.
3. Checkpoints e placar prontos na biblioteca; mais modelos de projeto.
4. Interface de jogo por script (botões, imagens).
5. “Jogar” um backup recebido direto da tela inicial, sem abrir o editor.
6. Animações de modelos GLB.

## Exportação de jogos independentes

Gerar um APK do *jogo* exige o SDK do Android, os *export templates* do Godot e assinatura — nada disso cabe num app de celular. Alternativas realistas, em ordem de esforço:

1. **Pacote para jogar** (curto prazo): exportar um `.zip` (já existe como backup) e um modo “só jogar” no Pocket Studio.
2. **Exportação pelo computador/CI**: um projeto Godot “player” que lê o `project.json` e roda o jogo; o CI gera um APK com o projeto embutido.
3. **Exportação Web (HTML5)** do mesmo “player”, publicável em sites gratuitos.

## Multiplayer (fase 4) — requisitos antes de implementar

Conforme o pedido, isto exige **servidor autorizado, autenticação segura, sincronização confiável e proteção contra alterações não autorizadas**. Proposta:

- **Colaboração de edição**: servidor de salas (ex.: WebSocket) com contas, convites e papéis (dono, editor, leitor). As alterações do editor já são dicionários de estado completos por objeto (os mesmos do desfazer/refazer), o que facilita enviá-las como operações; o servidor valida (`PSData.sanitize_object`) e define a ordem, e cada cliente aplica.
- **Teste multiplayer**: servidor com autoridade sobre a física (o Godot tem `MultiplayerAPI`/ENet; o mesmo `PSWorld` em modo de jogo roda no servidor).
- **Custos**: um servidor sempre ligado tem custo mensal; pelo orçamento (R$ 197) e pela regra de não contratar serviços pagos sem autorização, **nada foi contratado**. Opções gratuitas para protótipo existem, mas limitadas; a decisão é do responsável pelo projeto.
- **Segurança**: senhas nunca no app; tokens de sessão curtos; scripts continuam isolados e executados só localmente (ou no servidor, nunca vindos de outro cliente sem validação).

## Integração com Roblox — o que se sabe e o que falta verificar

Requisitos do pedido: não usar a marca, não presumir compatibilidade de arquivos, não prometer publicação sem suporte oficial, investigar APIs autorizadas antes, manter separado do motor próprio.

- Situação atual: **nenhuma integração** e nenhum uso de marca; o formato e o motor são próprios.
- O que existe oficialmente (a confirmar na documentação atual da Roblox antes de qualquer implementação): a Roblox oferece APIs **Open Cloud** com chaves de API do próprio usuário, incluindo publicação de versões de *places* a partir de arquivos de place no formato da Roblox. Usar isso exigiria (1) que o usuário tenha conta e experiência na Roblox e crie a própria chave, (2) **converter** o projeto para o formato de place da Roblox — conversão que não é documentada oficialmente e não é garantida, e (3) respeitar os termos de uso da Roblox.
- Recomendação: tratar como módulo opcional e separado (“exportador”), só depois de validar com a documentação oficial e os termos; o editor e o motor do Pocket Studio não dependem disso.
