# Enemy_GoblinGrunt (gobelin de Clément, fait avec Claude Design)

Modèle importé dans COHUE sous `Workspace.Enemy_GoblinGrunt` (5 nov. 2026), depuis `Enemy_GoblinGrunt.glb`. La fiche de Claude Design est copiée à côté : `GOBLIN_handoff_ClaudeDesign.md`.

## Réglages faits dans COHUE par A03 (5 nov.)

| Réglage | Avant | Après |
| --- | --- | --- |
| Nom | `" Enemy_GoblinGrunt"` (une espace au début) | `Enemy_GoblinGrunt` |
| Couleurs | gris par défaut (`A3A2A5`) | la couleur du code hexadécimal de chaque pièce. Matière Metal pour la louche, Neon pour le reflet des yeux, SmoothPlastic pour le reste (mêmes règles que le script) |
| Pièces | non ancrées, avec collision | `Anchored`, `CanCollide` et `CanTouch` désactivés |
| Taille | 1,30 × 1,38 × 0,59 studs | ×3,32, soit 4,32 × 4,58 × 1,94 studs, pieds sur le Baseplate (Y = 8). Attribut `Height` = 4,5 |
| `PrimaryPart` | aucune | `torso_tunic_brown_8A5A33` |
| Script | absent | `GoblinController` dans le Model. C'est le script de Claude Design, avec une seule modification, à la ligne `rootCF` : le repère est retourné de 180° |

**Pourquoi retourner le repère.** L'Import 3D tourne le modèle de 180° : la face regarde vers −Z, le bras droit est vers −X. Le script attend l'inverse (la face vers +Z, comme dans l'aperçu). Sans la correction, la louche basculait vers l'arrière et l'impact partait derrière le gobelin. On retourne donc le repère du rig plutôt que le modèle : le gobelin garde la face vers −Z, la convention de Roblox (`LookVector`).

## Test en Play (5 nov.)

- La face regarde vers −Z, les pièces restent ancrées, la taille est de 4,77 studs.
- Les jambes alternent.
- Pendant le coup, la louche passe devant le torse (jusqu'à 2 studs) et l'impact éclate devant le gobelin. Les yeux passent au Neon orange.
- Aucune erreur du script dans la sortie.

## Notes

- Comme pour le fantôme, le script crée lui-même ses effets (cubes Neon, particules) et anime le gobelin côté serveur. C'est bien pour un essai. En jeu, il faudra des effets posés en objets dans `Assets.FX` et une animation côté client (Ironix).
- Le script inflige aussi des dégâts (`Damage` 15, `HitRadius` 4) aux Humanoids proches de l'impact, donc au joueur qui s'approche en Play.
- Une copie du zombie importée par erreur sous le nom `" Enemy_GoblinGrunt"` reste dans le Workspace. Elle n'a pas été touchée.
