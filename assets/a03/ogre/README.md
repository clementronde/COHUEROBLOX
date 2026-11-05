# Enemy_OgreBoss (ogre mini-boss de Clément, fait avec Claude Design)

Importé dans COHUE le 5 nov. 2026, depuis le zip `Voxel Ghost for Roblox (4).zip` rangé dans `assets/claude-design/`. La fiche de Claude Design est copiée à côté.

## Réglages faits dans COHUE par A03

| Réglage | Après |
| --- | --- |
| Place | `Workspace.A03_ZoneMobs.Enemy_OgreBoss`, directement sur le sol des boss (x 500, z 780), avec une plaque à son nom devant lui (z 765). Il n'a pas de socle : le trou de sa sortie du sol et l'onde de choc de son coup de gourdin doivent tomber sur un sol opaque |
| Couleurs, ancrage | Couleur du code hexadécimal de chaque pièce : Metal pour les clous, Wood pour le gourdin, Neon pour les reflets. Pièces `Anchored`, `CanCollide` désactivé |
| Taille | ×3,55 (jambes = 8 voxels, 1 voxel = 14,5/34 stud). Il fait 14,2 studs de haut et 12,4 de large. `Height` = 14,5 |
| `PrimaryPart` | `torso_skin_ogre_8AA04E` |
| Script | `OgreBossController`, corrigé à la ligne `rootCF` : le repère est retourné de 180°, car l'Import 3D tourne le modèle |
| Dégâts | `Damage` = 0 et `Knockback` = 0 dans la zone. Valeurs de la fiche : 45 et 75 |

## Test en Play

- **Sortie du sol** : elle se joue au lancement. Je l'ai relancée à la main avec l'attribut `Rise` : la tête passe sous le sol (8,0 pour un sol à 8,5), puis l'ogre ressort. Le trou est posé au niveau du sol.
- **Coup de gourdin** : il frappe le sol 11 studs devant l'ogre, côté main droite.
- Aucune erreur.
