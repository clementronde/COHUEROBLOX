#!/usr/bin/env bash
# Copies the LihFolk Asset Pack models listed in assets/pack-manifest.csv into assets/import/,
# renamed by game role, ready for Studio's 3D Importer (bulk import).
# Usage: bash tools/stage-assets.sh "/path/to/LihFolk Asset Pack"
set -e
PACK="${1:-$LIHFOLK_ASSETS}"
cd "$(dirname "$0")/.."
[ -f "$PACK/INDEX.md" ] || { echo "Asset pack not found: $PACK"; exit 1; }
mkdir -p assets/import
tail -n +2 assets/pack-manifest.csv | while IFS=, read -r name path role; do
  cp "$PACK/$path" "assets/import/$name.glb"
done
ls assets/import | wc -l
