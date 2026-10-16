#!/usr/bin/env bash
# Verifica erros de compilação de todos os scripts GDScript do projeto.
# Uso: tools/check_scripts.sh   (variável GODOT aponta para o executável)
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.." || exit 1
"$GODOT" --headless --path . res://tests/check_scripts.tscn 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Compile Error|FALHOU|Scripts verificados|GDScript::reload"
exit "${PIPESTATUS[0]}"
