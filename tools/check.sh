#!/usr/bin/env bash
# Compiles every .luau file (syntax check, nothing is executed).
# Usage: bash tools/check.sh [files...]   (default: all of shared/ server/ client/)
set -e
LUAU="${LUAU:-$HOME/.rokit/tool-storage/luau-lang/luau/0.743.0/luau.exe}"
cd "$(dirname "$0")/.."
FILES=("$@")
[ ${#FILES[@]} -eq 0 ] && mapfile -t FILES < <(find shared server client -name "*.luau" | sort)
TMP="$(mktemp -d)/check.luau"
for f in "${FILES[@]}"; do
  printf 'do local f, e = loadstring([=======[\n' >> "$TMP"
  cat "$f" >> "$TMP"
  printf '\n]=======], "%s") print(if f then "ok  %s" else ("ERR " .. tostring(e))) end\n' "$f" "$f" >> "$TMP"
done
OUT="$("$LUAU" "$TMP")"
echo "$OUT"
echo "$OUT" | grep -q "^ERR" && exit 1 || exit 0
