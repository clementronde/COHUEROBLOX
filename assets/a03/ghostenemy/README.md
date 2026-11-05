# Ghostenemy (fantôme de Clément, fait avec Claude Design)

Modèle importé dans COHUE sous `Workspace.Ghostenemy` (5 nov. 2026). Source : le paquet « Voxel Ghost for Roblox » de Clément (README et `GhostController.server.lua`).

## Réglages faits dans COHUE par A03 (5 nov.)

| Réglage | Avant | Après |
| --- | --- | --- |
| Pièces | non ancrées, avec collision (en Play, elles tombaient avant que le script les ancre) | `Anchored`, `CanCollide` et `CanTouch` désactivés |
| `PrimaryPart` | aucune | `body_ghost_white_F3F1FF` |
| Échelle | 1,72 × 2,08 × 1,07 studs | ×2 : 3,45 × 4,16 × 2,13 studs (attribut `Height` = 4,16). Pour revenir en arrière : `Ghostenemy:ScaleTo(1)` |
| Script `FRONT` | `(0, 0, 1)` | `(0, 0, -1)` : la face du modèle importé regarde vers −Z. Sinon les bras se tendaient et l'orbe partait vers l'arrière (cas prévu par le README de Claude Design) |

Les couleurs venaient déjà de l'import : chaque pièce porte son code hexadécimal à la fin de son nom.

## Test en Play (5 nov.)

- Le corps monte, descend et dérive ; les bras battent ; la queue ondule ; les pièces restent ancrées.
- L'orbe part tous les 2,2 s, devant le fantôme, du côté de la face.
- Aucune erreur du script dans la sortie.

## À trancher plus tard (DA et partage du travail)

- Les effets sont créés par le script (cubes Neon, particules). Or la règle « rien construit par script » (décisions v2 §12) veut des objets posés dans `Assets.FX`. Le branchement en jeu revient à Ironix.
- Deux couleurs touchent des réserves du guide DA :
  - les étincelles cyan (`#6EF3FF`) sont proches de la couleur de l'XP ;
  - les joues roses (`#FF9CCF`) sont proches du rose réservé à la capture.
- Le script anime les pièces côté serveur, à chaque frame. Pour un fantôme d'essai, c'est bien. Pour une horde, l'animation doit passer côté client (Ironix).
