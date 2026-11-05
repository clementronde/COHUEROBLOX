# Enemy_SpiderBoss (araignée géante de Clément, faite avec Claude Design)

Importée dans COHUE le 5 nov. 2026, depuis le zip `Voxel Ghost for Roblox (4).zip` rangé dans `assets/claude-design/`. La fiche de Claude Design est copiée à côté.

## Réglages faits dans COHUE par A03

| Réglage | Après |
| --- | --- |
| Place | `Workspace.A03_ZoneMobs.Enemy_SpiderBoss`, directement sur le sol des boss : x 548, le point sous le corps en z 798. Une plaque à son nom est posée devant elle (z 765) |
| Couleurs, ancrage | Couleur du code hexadécimal de chaque pièce : Neon pour les reflets et le sablier. Pièces `Anchored`, `CanCollide` désactivé |
| Taille | ×3,6 (sac de l'abdomen = 19 voxels, 1 voxel = 29/31 stud). Elle fait 30,8 studs de haut et 54,6 d'envergure. `Height` = 29 |
| `PrimaryPart` | `head_body_purple_553482` |
| Script | `SpiderBossController`, avec 3 corrections (voir plus bas) |
| Dégâts | Dans la zone : `Damage` 0, `Knockback` 0, `PoolDps` 0, `WebDamage` 0, `SpiderlingDamage` 0, et `WebSlow` = 16 (la vitesse normale, donc pas de ralentissement). Valeurs de la fiche : 60, 90, 12, 10, 8 et 4 |

## Corrections du script de Claude Design

1. **Repère retourné de 180°** à la ligne `rootCF`, comme pour les autres modèles.
2. **`updateSpiderlings` était défini deux fois.** La 2e copie, sans pattes et qui déplaçait les bébés avec `PivotTo`, masquait la 1re. Résultat : les pièces des bébés restaient à l'origine du monde. Seule la version animée, avec les pattes à genoux, est gardée.
3. **Direction des bébés à l'éclosion, et recul de secours** : ils partaient du `LookVector` de Roblox, qui regarde derrière le rig. Ils partent maintenant de l'avant du rig (+Z).

## Test en Play

- **Empalement** : il touche 41 studs devant l'araignée, sur le sol.
- **Toiles** : elles tombent entre z 730 et 772, devant elle, sur le sol.
- **Bébés** : 5 bébés éclosent, toutes leurs pièces en place, et au plus 10 en même temps.
- Aucune erreur.
