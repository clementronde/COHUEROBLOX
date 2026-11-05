# Enemy_Bat (chauve-souris de Clément, faite avec Claude Design)

Modèle importé dans COHUE le 5 nov. 2026. Clément a déposé ses fichiers à la racine de `assets/claude-design/` : `BAT.md` et `BatController.server.lua`. Le dossier `Enemy_Chauve souris/` est vide. La fiche de Claude Design est copiée à côté, sous le nom `BAT_handoff_ClaudeDesign.md`.

## Réglages faits dans COHUE par A03 (5 nov.)

| Réglage | Avant | Après |
| --- | --- | --- |
| Place | `Workspace.AuxScene.Enemy_Bat` | `Workspace.A03_ZoneMobs.Enemy_Bat`, au milieu de la zone des mobs (3e socle). Elle vole 2,5 studs au-dessus du socle. Le modèle `AuxScene`, vide après le déplacement, est supprimé |
| Couleurs | gris par défaut | la couleur du code hexadécimal de chaque pièce, Neon pour le reflet des yeux, SmoothPlastic pour le reste |
| Pièces | non ancrées, avec collision | `Anchored`, et `CanCollide` désactivé |
| Taille | 2,64 × 1,20 × 0,80 studs | ×3,33 (le corps fait 11 voxels de large, 1 voxel = 4/15 stud). Elle mesure 4 studs de haut pour 8,8 d'envergure. Attribut `Height` = 4 |
| `PrimaryPart` | aucune | `body_fur_purple_6A4C9C` |
| Script | absent | `BatController`, celui de Claude Design, corrigé à la ligne `rootCF` : le repère est retourné de 180°, car l'Import 3D tourne le modèle |
| `Damage` | 10 | 0 dans la zone des mobs. Remettre 10 pour tester les dégâts |

## Test en Play (5 nov.)

- La face regarde vers −Z.
- Les anneaux soniques partent vers l'avant et éclatent à 8,3 studs devant la chauve-souris (z 771,7, pour une chauve-souris en z 780).
- Aucune erreur du script dans la sortie.
