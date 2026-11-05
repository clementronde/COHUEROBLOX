# Enemy_GoblinPigRider (gobelin cavalier de Clément, fait avec Claude Design)

Importé dans COHUE le 5 nov. 2026, depuis le zip `Voxel Ghost for Roblox (4).zip` rangé dans `assets/claude-design/`. La fiche de Claude Design est copiée à côté.

## Réglages faits dans COHUE par A03

| Réglage | Après |
| --- | --- |
| Place | `Workspace.A03_ZoneMobs.Enemy_GoblinPigRider`, 6e socle (x 466). Ce socle fait 10 studs de profondeur au lieu de 7, pour que la charge reste dessus. Le `AuxScene` vide est supprimé |
| Couleurs, ancrage | Couleur du code hexadécimal de chaque pièce : Metal pour la pointe, Wood pour la hampe, Neon pour les reflets. Pièces `Anchored`, `CanCollide` désactivé |
| Taille | ×3,55 (pattes du cochon = 4 voxels, 1 voxel = 6/26 stud). Il fait 6 studs au dôme du gobelin et 8,5 à la pointe de la lance. `Height` = 6 |
| `PrimaryPart` | `pig_body_skin_pig_F4A3A8` |
| Script | `GoblinPigRiderController`, corrigé à 2 endroits : le repère est retourné de 180° (l'Import 3D tourne le modèle), et le recul part vers l'avant (`-rootCF.LookVector`, l'avant du rig étant +Z) |
| Dégâts | `Damage` = 0 et `Knockback` = 0 dans la zone. Valeurs de la fiche : 20 et 45 |

## Test en Play

Face vers −Z. Le coup de lance touche 6,4 studs devant le cochon. Aucune erreur.
