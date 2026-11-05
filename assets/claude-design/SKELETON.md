# Enemy_Skeleton — handoff Roblox (pour Claude Code)

| # | Model | Rôle | Taille |
|---|---|---|---|
| 4 | Enemy_Skeleton | Melee | 5 studs (des pieds au haut du crâne) |

Style du projet (voir GUIDE_NOUVEL_ENNEMI.md) : gros voxels, crâne en dôme, yeux noirs avec reflet, moufles rondes, peu de détails. Accessoires d'identité : côtes, mâchoire qui claque, épée.

## 1. Parts et couleurs
Nom de chaque mesh : `<part>_<matière>_<HEX>`. Le script applique la couleur automatiquement.

| Part | Matières (hex) | Matériau Roblox |
|---|---|---|
| head (crâne) | bone_white #EDE6D3 · eye_black #120C1F (→ Neon #6EF3FF en attaque) · eye_glint #FFFFFF · mouth_dark #2A2420 (entre les dents) | SmoothPlastic · glint en Neon |
| jaw (mâchoire) | bone_white #EDE6D3 · mouth_dark #2A2420 | SmoothPlastic |
| torso | bone_white #EDE6D3 (colonne, 2 côtes, sternum, épaules) · bone_shade #BFB49A (bassin) | SmoothPlastic |
| arm_L / arm_R | bone_shade #BFB49A (épaule) · bone_white #EDE6D3 (os + moufle ronde 3×3×3) | SmoothPlastic |
| leg_L / leg_R | bone_white #EDE6D3 (os) · bone_shade #BFB49A (pied) | SmoothPlastic |
| sword | blade_grey #B9C1C9 (lame) · grip_brown #5A3A22 (poignée + garde) | Metal / SmoothPlastic |

Couleurs VFX : traînée et anneau #6EF3FF + blanc (Neon) · éclats d'os #EDE6D3 / #BFB49A (non lumineux, avec gravité) · étincelles d'âme #6EF3FF.

## 2. Import
1. Dans la preview `Enemy_Skeleton.html`, cliquer sur **Download GLB**. L'export est en pose de repos (épée droite dans la moufle droite).
2. Studio → **Import 3D**. Garder la hiérarchie et ne pas fusionner les meshes.
3. Mettre `SkeletonController.server.lua` dans un Script à l'intérieur du Model.

## 3. Animations
**Walk** (en boucle, 6 rad/s) : démarche raide (jambes ±0,5 rad), petit rebond, balancement du buste (±0,05 rad), tête qui oscille. La mâchoire claque à 16 rad/s (ouverture jusqu'à 0,16 rad).

**Attack — coup d'épée en diagonale, de droite à gauche** (vu de face, 1,3 s) :
- 0–0,35 s : armé. L'épée passe au-dessus de l'épaule, en arrière (rotation X du bras −0,8, rotation Z +0,25) et le buste tourne (yaw +0,6). La mâchoire s'ouvre (0,35 rad) et les yeux passent en cyan néon, avec des flammes d'âme qui montent des orbites.
- 0,35–0,5 s : la lame descend en travers (X −0,8 → +1,7, yaw +0,6 → −0,7), avec une traînée cyan et blanche à la pointe.
- À 55 % du coup : impact au milieu de la lame. Éclats d'os qui tombent, étincelles cyan, anneau vertical qui s'agrandit, petit flash, et dégâts aux Humanoids dans `HitRadius`.
- 0,5–0,75 s : tenue. Puis 0,75–1,3 s : retour.

Pivots en voxels (1 voxel = Height / 19), depuis le sol au centre des pieds : hanche (0,4,0) · jambes (±2,4,0) · cou (0,10,0) · mâchoire (0,12,−2) · épaules (±4.5,8.5,0) · pointe de l'épée au repos (8,20,0) · milieu de la lame (8,16,0).

## 4. Notes
- Attributs du Model : `Walking`, `AutoAttack`, `AttackEvery`, `Damage`, `HitRadius`, `Height`. Pour déclencher une attaque : `skeleton:SetAttribute("Attack", os.clock())`.
- Le visage regarde vers +Z local. Pour suivre le `LookVector` de Roblox, tourner le Model de 180°.
