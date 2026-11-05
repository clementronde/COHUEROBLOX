#!/usr/bin/env bash
# A04-12 — modèle d'équilibrage du monde 1, HORS Studio (luau CLI, rien de Roblox n'est lancé).
# Usage : bash tools/tests/a04-balance.sh [runs par classe] [graine] ["AVG.exposure = 0.05; ..."]
# Assemble les sources des configs (en texte) puis tools/tests/a04-balance.luau, qui les charge avec
# des bouchons du moteur et simule des runs de 10 min (voir l'en-tête du .luau).
set -e
LUAU="${LUAU:-$HOME/.rokit/tool-storage/luau-lang/luau/0.743.0/luau.exe}"
cd "$(dirname "$0")/../.."
TMP="$(mktemp -d)/a04-balance.luau"
{
	printf 'RUNS = %s\nSEED = %s\nAVG_OVERRIDE = [[%s]]\nSRC = {}\n' "${1:-200}" "${2:-12}" "${3:-}"
	for name in Weapons Grimoires Cards Run Balance Enemies Items Bosses Worlds Rarities Loot; do
		printf 'SRC.%s = [=======[\n' "$name"
		cat "shared/Config/$name.luau"
		printf '\n]=======]\n'
	done
	cat tools/tests/a04-balance.luau
} > "$TMP"
"$LUAU" "$TMP"
