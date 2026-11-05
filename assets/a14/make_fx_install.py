"""COHUE — A14 : génère le script Studio qui construit les modèles d'effets (ReplicatedStorage.Assets.FX).

    python assets/a14/make_fx_install.py

Entrée : assets/a14/out/fx_shapes.json (export.py). Sortie : assets/a14/install/A14_fx_install.luau.
Le corps du script est dans assets/a14/install/fx_install_body.luau (écrit à la main) ; ce générateur y
ajoute les centres des segments du croissant.
"""

from __future__ import annotations

import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "install", "A14_fx_install.luau")
BODY = os.path.join(HERE, "install", "fx_install_body.luau")


def main():
    shapes = json.load(open(os.path.join(HERE, "out", "fx_shapes.json"), encoding="utf-8"))
    lines = ["local ARC_SEGMENTS = %d" % shapes["arc_segments"], "local ARC_CENTERS = {"]
    for name, c in shapes["arc_centers"].items():
        lines.append("\t%s = Vector3.new(%s, %s, %s)," % (name, c[0], c[1], c[2]))
    lines.append("}")
    body = open(BODY, encoding="utf-8").read()
    head, _, rest = body.partition("-- @@DATA@@\n")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(head + "\n".join(lines) + "\n" + rest)
    print(OUT)


if __name__ == "__main__":
    main()
