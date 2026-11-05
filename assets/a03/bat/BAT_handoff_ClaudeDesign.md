# Enemy_Bat — handoff Roblox (pour Claude Code)

| # | Model | Rôle | Taille |
|---|---|---|---|
| 3 | Enemy_Bat | Flying (Ranged) | 4 studs (des pieds au bout des oreilles) · envergure ≈ 8,8 studs |

Style du projet (voir GUIDE_NOUVEL_ENNEMI.md) : gros voxels, corps en dôme, yeux noirs avec reflet, peu de détails. Accessoires d'identité : oreilles pointues, ailes, 2 crocs.

## 1. Parts et couleurs
Nom de chaque mesh : `<part>_<matière>_<HEX>`. Le script applique la couleur automatiquement.

| Part | Matières (hex) | Matériau Roblox |
|---|---|---|
| body | fur_purple #6A4C9C (dôme + oreilles) · belly_lilac #C7B0EC · eye_black #120C1F (→ Neon #C08CFF en attaque) · eye_glint #FFFFFF · mouth_dark #2A1430 · fang_white #FFF8E7 | SmoothPlastic · glint en Neon |
| wing_L_1 / wing_R_1 (aile intérieure) | wing_membrane #A58AD6 · wing_bone #3E2A63 (bord du haut) | SmoothPlastic |
| wing_L_2 / wing_R_2 (aile extérieure) | wing_membrane #A58AD6 · wing_bone #3E2A63 | SmoothPlastic |
| leg_L / leg_R (griffes) | wing_bone #3E2A63 | SmoothPlastic |

Couleurs VFX (Neon) : anneaux sonores #C08CFF / #6EF3FF · étincelles de charge #C08CFF · impact #C08CFF + #6EF3FF + blanc.

## 2. Import
1. Dans la preview `Enemy_Bat.html`, cliquer sur **Download GLB**. L'export est en pose de repos (ailes à plat, droites).
2. Studio → **Import 3D**. Garder la hiérarchie et ne pas fusionner les meshes.
3. Mettre `BatController.server.lua` dans un Script à l'intérieur du Model.

## 3. Animations
**Fly** (en boucle) : battement rapide des ailes (9 rad/s, aile intérieure de 0,15 ± 0,65 rad, aile extérieure en retard de 0,7 rad à ±0,45), le corps monte et descend à l'opposé du battement, légère dérive gauche-droite, pieds qui pendent et se balancent.

**Attack — cri sonique** (1,4 s) :
- 0–0,4 s : armé. Le corps se cabre (pitch −0,4), recule et monte un peu. Les ailes s'ouvrent vers le haut et se figent, les étincelles sont aspirées vers la bouche, les yeux deviennent violet néon.
- 0,4–0,55 s : fente vers l'avant (pitch +0,3) et coup d'ailes vers le bas. Premier anneau sonore à mi-fente.
- 0,6 s et 0,68 s : 2e et 3e anneaux. Chaque anneau = 22 cubes néon, avance de 3,2 m/s (≈ 40 voxels/s) en grandissant pendant 0,6 s et fait des dégâts sur son trajet (`HitRadius`, une seule fois par cible et par attaque).
- Fin du 3e anneau : éclat de particules et petit flash.
- 0,85–1,4 s : retour.

Pivots en voxels (1 voxel = Height / 15), depuis le bas du corps au centre : ailes intérieures (±5.5, 6, 0) · ailes extérieures (±10.5, 6, 0) · pieds (±2, 0, 0) · bouche (0, 4, 5).

## 4. Notes
- Attributs du Model : `Flying`, `AutoAttack`, `AttackEvery`, `Damage`, `HitRadius`, `Height`. Pour déclencher une attaque : `bat:SetAttribute("Attack", os.clock())`.
- Le visage regarde vers +Z local. Pour suivre le `LookVector` de Roblox, tourner le Model de 180°.
- Ennemi volant : place le Model en hauteur (2 à 4 studs du sol). Le script ne gère pas la gravité.
