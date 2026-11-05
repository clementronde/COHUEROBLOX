# Enemy_Skeleton (squelette de Clément, fait avec Claude Design)

Modèle importé dans COHUE le 5 nov. 2026. Clément a déposé ses fichiers à la racine de `assets/claude-design/` : `SKELETON.md` et `SkeletonController.server.lua`. La fiche de Claude Design est copiée à côté, sous le nom `SKELETON_handoff_ClaudeDesign.md`.

## Réglages faits dans COHUE par A03 (5 nov.)

| Réglage | Avant | Après |
| --- | --- | --- |
| Place | `Workspace.AuxScene.Enemy_Skeleton` | `Workspace.A03_ZoneMobs.Enemy_Skeleton`, sur le 4e socle de la zone des mobs. Le modèle `AuxScene`, vide après le déplacement, est supprimé |
| Couleurs | gris par défaut | la couleur du code hexadécimal de chaque pièce : Metal pour la lame `B9C1C9`, Neon pour le reflet des yeux, SmoothPlastic pour le reste |
| Pièces | non ancrées, avec collision | `Anchored`, et `CanCollide` désactivé |
| Taille | 1,48 × 1,55 × 0,67 studs | Mise à l'échelle par la hauteur des jambes (4 voxels, 1 voxel = 5/19 stud). Le crâne est à 5 studs, la pointe de l'épée à 5,5. Attribut `Height` = 5 |
| `PrimaryPart` | aucune | `torso_bone_white_EDE6D3` |
| Script | absent | `SkeletonController`, celui de Claude Design, corrigé à la ligne `rootCF` : le repère est retourné de 180°, car l'Import 3D tourne le modèle (même correction que pour le gobelin et le zombie) |
| `Damage` | 18 | 0 dans la zone des mobs, pour pouvoir s'approcher sans mourir. Remettre 18 pour tester les dégâts |

## Test en Play (5 nov.)

- La face regarde vers −Z. Le bras droit, qui tient l'épée, est côté −X.
- Le coup d'épée touche à 1,7 stud devant le squelette (x 440,5, z 778,3, pour un squelette en x 442, z 780).
- Aucune erreur du script dans la sortie.
