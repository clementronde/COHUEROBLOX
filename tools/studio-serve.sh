#!/usr/bin/env bash
# Sert les scripts de ce dossier (main ou un worktree) à Roblox Studio, en local seulement.
# Usage : bash tools/studio-serve.sh 8787   puis exécuter tools/studio-load.luau dans Studio (execute_luau, Edit).
# Arrêt : Ctrl-C, ou arrêter le process python qui écoute sur ce port (pas les autres).
set -e
PORT="${1:-8787}"
cd "$(dirname "$0")/.."
find shared server client -type f -name '*.luau' | sort > .studio-files.txt
echo "$(wc -l < .studio-files.txt) fichiers, http://127.0.0.1:$PORT"
exec python -m http.server "$PORT" --bind 127.0.0.1 --directory "$(pwd -W 2>/dev/null || pwd)"
