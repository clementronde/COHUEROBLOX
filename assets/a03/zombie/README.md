# Enemy_Zombie (zombie de Clément, fait avec Claude Design)

Modèle importé dans COHUE (5 nov. 2026), depuis `assets/claude-design/Enemy_Zombie/`. La fiche de Claude Design est copiée à côté : `ZOMBIE_handoff_ClaudeDesign.md`.

## Réglages faits dans COHUE par A03 (5 nov.)

| Réglage | Avant | Après |
| --- | --- | --- |
| Place | `Workspace.AuxScene.Enemy_Zombie` | `Workspace.Enemy_Zombie`. Le modèle `AuxScene`, vide après le déplacement, est supprimé |
| Couleurs | gris par défaut | la couleur du code hexadécimal de chaque pièce, Neon pour le reflet des yeux, SmoothPlastic pour le reste |
| Pièces | non ancrées, avec collision | `Anchored`, `CanCollide` et `CanTouch` désactivés |
| Taille | 1,68 × 1,44 × 0,72 studs | ×3,55, soit 5,12 studs de haut, pieds sur le Baseplate, à côté du gobelin (x 318). Attribut `Height` = 5,4 |
| `PrimaryPart` | aucune | `torso_shirt_teal_3F7F8C` |
| Script | absent | `ZombieController`. C'est le script de Claude Design, avec la même correction que pour le gobelin à la ligne `rootCF` : le repère est retourné de 180°, car l'Import 3D tourne le modèle |

## Test en Play (5 nov.)

- La face regarde vers −Z ; la taille est de 5,58 studs en Play.
- Les mains restent devant pendant la marche, entre 0,4 et 1,5 stud devant le torse. Les jambes boitent.
- Pendant l'attaque, le torse avance de 0,8 stud et les griffures éclatent à 2,4 studs devant. Les yeux passent au Neon vert.
- Aucune erreur du script dans la sortie.

## Notes

- Comme pour le fantôme et le gobelin, le script crée ses effets et anime le zombie côté serveur. C'est bien pour un essai ; en jeu, il faudra des objets dans `Assets.FX` et une animation côté client (Ironix).
- Une copie du zombie importée par erreur sous le nom `" Enemy_GoblinGrunt"` reste dans le Workspace, au même endroit qu'avant (x 314). Elle n'a pas été touchée.
