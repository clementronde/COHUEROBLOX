"""A14 : écrit out/A14_push_scripts.luau, qui pousse les scripts d'A14 dans COHUE sans studio-load.

studio-load ne marche plus (le pont MCP de Studio refuse les requêtes HTTP vers 127.0.0.1). Ce générateur
met la source de chaque fichier dans une chaîne longue Luau. Le script produit garde l'ancienne version de
chaque module dans ServerStorage.A14_Backup, puis remplace la source avec ScriptEditorService:UpdateSourceAsync.
À lancer avec execute_luau (datamodel Edit) sur COHUE, quand le coordinateur a donné le créneau.

Usage : python assets/a14/make_push.py [fichiers...]   (par défaut, les deux contrôleurs d'A14)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "out", "A14_push_scripts.luau")
DEFAULT = ["client/Controllers/WeaponFX.luau", "client/Controllers/EnemyAttackFX.luau"]
ROOTS = {
    "shared": 'game:GetService("ReplicatedStorage"):WaitForChild("Shared")',
    "server": 'game:GetService("ServerScriptService"):WaitForChild("Server")',
    "client": 'game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("Client")',
}


def long_string(src: str) -> str:
    level = 1
    while ("]" + "=" * level + "]") in src:
        level += 1
    eq = "=" * level
    # Luau saute un saut de ligne juste après l'ouverture : on en met un pour garder la source exacte
    return "[" + eq + "[\n" + src + "]" + eq + "]"


def main() -> None:
    files = sys.argv[1:] or DEFAULT
    lines = [
        "-- Généré par assets/a14/make_push.py : ne pas modifier à la main.",
        'local SES = game:GetService("ScriptEditorService")',
        'local backup = game:GetService("ServerStorage"):FindFirstChild("A14_Backup") or Instance.new("Folder")',
        'backup.Name = "A14_Backup"',
        'backup.Parent = game:GetService("ServerStorage")',
        "local done, failed = {}, {}",
        "local function push(root: Instance, path: { string }, class: string, src: string)",
        "\tlocal parent = root",
        "\tfor i = 1, #path - 1 do",
        "\t\tparent = parent:FindFirstChild(path[i]) :: Instance",
        "\t\tif not parent then",
        '\t\t\ttable.insert(failed, table.concat(path, "/") .. " : dossier introuvable")',
        "\t\t\treturn",
        "\t\tend",
        "\tend",
        "\tlocal name = path[#path]",
        "\tlocal inst = parent:FindFirstChild(name)",
        "\tif not inst or inst.ClassName ~= class then",
        '\t\ttable.insert(failed, table.concat(path, "/") .. " : script introuvable (" .. class .. ")")',
        "\t\treturn",
        "\tend",
        '\tlocal old = inst:Clone()',
        '\told.Name = name .. "_" .. os.date("!%H%M%S")',
        "\told.Parent = backup",
        "\tSES:UpdateSourceAsync(inst, function()",
        "\t\treturn src",
        "\tend)",
        '\ttable.insert(done, table.concat(path, "/"))',
        "end",
    ]
    for rel in files:
        rel = rel.replace("\\", "/")
        src = open(os.path.join(REPO, rel), encoding="utf-8").read().replace("\r\n", "\n")
        parts = rel.split("/")
        root = ROOTS[parts[0]]
        last = parts[-1]
        if last.endswith(".server.luau"):
            cls, name = "Script", last[: -len(".server.luau")]
        elif last.endswith(".client.luau"):
            cls, name = "LocalScript", last[: -len(".client.luau")]
        else:
            cls, name = "ModuleScript", last[: -len(".luau")]
        path = parts[1:-1] + [name]
        lua_path = "{ " + ", ".join('"' + p + '"' for p in path) + " }"
        lines.append(f'push({root}, {lua_path}, "{cls}", {long_string(src)})')
    lines.append("return { pushed = done, failed = failed }")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(OUT, len(files), "fichiers")


if __name__ == "__main__":
    main()
