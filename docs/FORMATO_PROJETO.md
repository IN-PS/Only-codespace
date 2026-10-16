# Formato dos projetos

Tudo fica em `user://` (no Android, o armazenamento interno do app; no Linux, `~/.local/share/godot/app_userdata/Pocket Studio 3D/`).

```
user://settings.json                      configurações do app
user://projects/<id>/project.json         projeto salvo
user://projects/<id>/project.json.bak     salvamento anterior
user://projects/<id>/autosave.json        salvamento automático (recuperação)
user://projects/<id>/meta.json            resumo para a lista (nome, data, nº de objetos)
user://projects/<id>/versions/v*.json     versões: {"label", "time", "data": <projeto>}
user://projects/<id>/assets/<id>.<ext>    modelos (.glb) e texturas importados
user://backups/*.zip                      backups exportados
```

## `project.json`

```jsonc
{
  "format": "pocketstudio3d.project",   // obrigatório
  "format_version": 1,
  "app_version": "0.1.0",
  "name": "Meu jogo",
  "created": 1760572800.0,               // segundos Unix
  "modified": 1760572800.0,
  "env": {                               // ambiente
    "sky": "day",                        // day | sunset | night | overcast
    "sun_yaw": -40, "sun_pitch": -55, "sun_energy": 1.0,
    "ambient": 0.6, "fog": false, "fog_density": 0.01, "gravity": 9.8
  },
  "game": {                              // regras do modo de teste
    "camera": "third",                   // third | first
    "walk_speed": 6, "jump": 7, "start_message": "", "respawn_y": -40
  },
  "objects": [ /* ordem em profundidade: o pai sempre antes dos filhos */ ],
  "terrain": null,                       // ou objeto de terreno
  "scripts": [ { "id": "s1", "name": "Moeda", "code": "...", "enabled": true, "global": false } ],
  "assets": [ /* ver abaixo */ ],
  "editor": { "camera": { "pivot": [0,0,0], "yaw": -35, "pitch": -28, "distance": 14 } }
}
```

### Objeto

Campos comuns: `id`, `type`, `name`, `parent` (id ou `""`), `pos` `[x,y,z]` (relativo ao pai), `rot` quaternion `[x,y,z,w]`, `visible`, `locked`, `script` (id ou `""`).

| `type` | Campos extras |
|---|---|
| `part` | `shape` (`box, sphere, cylinder, cone, capsule, wedge, torus, pyramid`), `size` em metros, `mat`, `phys`, `shadow` |
| `model` | `asset` (id), `size` = escala, `phys`, `shadow` |
| `light` | `light`: `{kind: point|spot, color, energy, range, angle, shadow}` |
| `water` | `size` (X/Z = área, Y = profundidade), `mat` (só a cor é usada) |
| `text` | `text`, `size` (escala), `mat` |
| `group`, `spawn` | — |

`mat`: `{color: [r,g,b,a], metal, rough, emit, tex: <id da textura ou "">, uv}` · `phys`: `{mode: static|dynamic|kinematic|none, mass, friction, bounce}`.

### Terreno

```json
{ "size": 65, "heights": "<base64 de float32 size×size>", "colors": "<base64 de RGBA8 size×size>",
  "pos": [0,0,0], "veg": [ {"kind": "tree", "p": [[x, y, z, rotação, escala], ...]} ] }
```

Espaçamento de 1 m entre vértices, centrado em `pos`. `kind`: `tree, pine, bush, rock, grass`.

### Asset

```json
{ "id": "a…", "type": "model|texture", "name": "…", "file": "assets/a….glb",
  "size": 12345, "sha256": "…", "license": "CC0 (domínio público)", "origin": "site/fonte",
  "author": "…", "original_name": "arquivo.glb", "imported": 1760572800.0,
  "stats": {"vertices": 1234, "triangles": 2000, "meshes": 1, "materials": 1, "textures": 0, "animations": 0, "nodes": 2} }
```

Arquivos `.gltf` são convertidos para `.glb` na importação. `file` sempre começa com `assets/` (outros caminhos são descartados ao carregar).

## Backup `.zip`

```
project.json     o projeto
assets/…         arquivos dos assets
backup.json      {"format": "pocketstudio3d.backup", "version": 1, "app_version", "project_name", "created", "files": [...]}
```

A importação aceita **apenas** esses caminhos (assets com extensão `glb/gltf/bin/png/jpg/jpeg/webp`), limita a 600 arquivos e 300 MB, e cria sempre um projeto **novo**.

## Compatibilidade

Arquivos de versões futuras com campos desconhecidos são lidos ignorando esses campos. Valores fora da faixa são limitados (ex.: posições ±10 000, tamanhos 0,01–2 000 m, até 5 000 objetos, 200 scripts, 500 assets).
