# Compilar e instalar no Android

Há três caminhos. O primeiro não exige computador.

## 1. Pelo GitHub Actions (recomendado, já configurado)

O workflow [`.github/workflows/build.yml`](../.github/workflows/build.yml) roda a cada envio (`push`) e também pode ser disparado à mão (**Actions → Testes e APK Android → Run workflow**). Ele:

1. baixa o Godot 4.7.2 oficial e roda `tools/check_scripts.sh` e os testes;
2. baixa os *export templates* oficiais (só os do Android são extraídos);
3. exporta `PocketStudio3D-debug.apk` (arm64-v8a + armeabi-v7a), assinado com uma
   keystore de depuração guardada no cache do Actions e verificado pelo `apksigner`;
4. publica o APK como artefato por 30 dias.

Para instalar:

1. No GitHub (navegador do celular serve), abra **Actions**, a execução mais recente com ✅ e baixe o artefato `PocketStudio3D-<commit>-debug-apk`.
2. Extraia o `.zip` (gerenciadores de arquivos do Android abrem `.zip`).
3. Toque no `.apk`. Se o Android pedir, permita **instalar apps desconhecidos** para o app que está abrindo o arquivo.

> A keystore de depuração é reaproveitada entre execuções (cache do GitHub Actions), então um APK novo instala por cima do anterior mantendo os projetos. Se o cache expirar (o GitHub apaga caches sem uso por 7 dias), uma keystore nova é criada e o Android recusará a atualização: aí é preciso desinstalar a versão antiga — e **desinstalar apaga os projetos guardados no app, então exporte backups antes**. Para distribuição, use uma keystore de release fixa (seção 4).

## 2. Pelo computador, com o editor do Godot

Ferramentas (todas gratuitas):

| Ferramenta | Versão | Onde |
|---|---|---|
| Godot Engine | 4.7.2 (padrão) | godotengine.org/download |
| Export templates | 4.7.2 | no editor: *Editor → Gerenciar modelos de exportação → Baixar* |
| JDK | 17 | adoptium.net (Temurin) |
| Android SDK | platform-tools + build-tools (34 ou mais novo) | Android Studio ou `sdkmanager` (command-line tools) |

Passos:

1. No Godot: *Editor → Configurações do editor → Exportar → Android*: preencha **Java SDK Path** (pasta do JDK 17) e **Android SDK Path**. (Se as variáveis `JAVA_HOME` e `ANDROID_HOME` existirem, o Godot já as usa.)
2. Crie uma keystore de depuração (uma vez):
   ```bash
   keytool -genkeypair -v -keystore debug.keystore -storepass android \
     -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 \
     -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
   ```
   e informe-a em *Configurações do editor → Exportar → Android → Debug Keystore* (usuário `androiddebugkey`, senha `android`).
3. *Projeto → Exportar…* → preset **Android** (já incluído em `export_presets.cfg`) → **Exportar projeto** (marque “Exportar com depuração” para teste).
4. Com o celular no modo desenvolvedor e cabo USB: `adb install -r build/PocketStudio3D.apk`, ou copie o arquivo para o celular.

Linha de comando equivalente:

```bash
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH=$PWD/debug.keystore
export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android
godot --headless --path . --import
godot --headless --path . --export-debug "Android" build/PocketStudio3D-debug.apk
```

## 3. No próprio celular, com o editor do Godot para Android

O Godot tem um editor oficial para Android (*Godot Engine* na Google Play ou o APK em godotengine.org). Dá para abrir este repositório (baixado como `.zip` e extraído) e rodar o projeto direto no aparelho para desenvolver o Pocket Studio 3D sem computador. Exportar APK pelo editor Android exige configuração adicional do Godot; o caminho 1 é mais simples.

## 4. Versão final (release) assinada

Para distribuir (ou atualizar sem desinstalar), use **sempre a mesma** keystore de release:

```bash
keytool -genkeypair -v -keystore release.keystore -alias pocketstudio \
  -keyalg RSA -keysize 2048 -validity 10000
```

Guarde a keystore e as senhas em local seguro (perdê-las impede atualizar o app). Exporte com:

```bash
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$PWD/release.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=pocketstudio
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD='<sua senha>'
godot --headless --path . --export-release "Android" build/PocketStudio3D.apk
```

Para fazer isso no GitHub Actions, salve a keystore em Base64 e as senhas como *Secrets* do repositório e adicione um passo semelhante ao de depuração. **Nunca** coloque keystores ou senhas no repositório (o `.gitignore` já ignora `*.keystore` e `*.jks`).

Antes de publicar numa loja: aumente `version/code` e `version/name` em `export_presets.cfg`, revise o nome do pacote (`package/unique_name`, hoje `com.inps.pocketstudio3d`) e considere exportar AAB (requer a opção *gradle build* e o template de build Android).

## Configuração da exportação (resumo de `export_presets.cfg`)

- Arquiteturas: `arm64-v8a` e `armeabi-v7a` (cobre praticamente todos os celulares, incluindo modelos de entrada 32 bits).
- Nenhuma permissão especial: o app não usa internet e o seletor de arquivos do Android (SAF) não exige permissão de armazenamento.
- Renderizador: *Compatibility* (OpenGL ES 3.0).
- Orientação: segue o sensor (retrato e paisagem).
- Os arquivos de `tests/`, `tools/` e `docs/` não entram no APK.
