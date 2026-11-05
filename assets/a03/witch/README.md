# Enemy_WitchBroom (sorcière de Clément, faite avec Claude Design)

Importée dans COHUE le 5 nov. 2026, depuis le zip `Voxel Ghost for Roblox (4).zip` rangé dans `assets/claude-design/`. La fiche de Claude Design est copiée à côté.

## Réglages faits dans COHUE par A03

| Réglage | Après |
| --- | --- |
| Place | `Workspace.A03_ZoneMobs.Enemy_WitchBroom`, 7e socle (x 478). Son « sol » (20,5 voxels sous le balai) est le sol de la zone, pas le dessus du socle : la potion et la flaque tombent donc par terre. Elle vole 2,1 studs au-dessus du socle |
| Couleurs, ancrage | Couleur du code hexadécimal de chaque pièce : Neon pour les reflets et la potion, Metal pour la bande du chapeau, Wood pour le manche. Pièces `Anchored`, `CanCollide` désactivé |
| Taille | ×3,57 (balai = 29 voxels, 1 voxel = 6,5/28 stud). Elle fait 6,5 studs, des bottes à la pointe du chapeau. `Height` = 6,5 |
| `PrimaryPart` | `torso_dress_purple_5B3A8C` |
| Script | `WitchController`, corrigé à la ligne `rootCF` : le repère est retourné de 180°, car l'Import 3D tourne le modèle |
| Dégâts | `Damage` = 0 et `PoisonDps` = 0 dans la zone. Valeurs de la fiche : 18 et 6 |

## Test en Play

- Sans joueur à portée, la potion tombe 10,2 studs devant elle, sur le sol. Elle vise le joueur le plus proche à moins de 60 studs (`Range`).
- Aucune erreur.
