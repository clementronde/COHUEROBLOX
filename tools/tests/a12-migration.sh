#!/usr/bin/env bash
# A12 — test de migration des profils, HORS Studio (luau CLI, moteur simulé).
# Usage : bash tools/tests/a12-migration.sh
# Assemble : sources de shared/Config/Progression.luau et server/Services/DataService.luau (en texte),
# puis tools/tests/a12-migration.luau (stubs du moteur + profils v1 / v2 fabriqués + asserts).
set -e
LUAU="${LUAU:-$HOME/.rokit/tool-storage/luau-lang/luau/0.743.0/luau.exe}"
cd "$(dirname "$0")/../.."
TMP="$(mktemp -d)/a12-migration.luau"
{
	printf 'PROGRESSION_SRC = [=======[\n'
	cat shared/Config/Progression.luau
	printf '\n]=======]\nDATASERVICE_SRC = [=======[\n'
	cat server/Services/DataService.luau
	printf '\n]=======]\n'
	cat tools/tests/a12-migration.luau
} > "$TMP"
"$LUAU" "$TMP"
