# Voxel Ghost — handoff Roblox (pour Claude Code)

## 1. Parts et couleurs
Chaque mesh exporté porte son code hex à la fin du nom (`<part>_<matière>_<HEX>`). Le script lit ce suffixe et applique la couleur automatiquement.

| Mesh (nom dans le GLB/OBJ) | Hex | Matériau Roblox |
|---|---|---|
| body_ghost_white_F3F1FF | #F3F1FF | SmoothPlastic |
| body_ghost_shade_C9C0F4 | #C9C0F4 | SmoothPlastic |
| body_eye_black_120C1F | #120C1F | SmoothPlastic → Neon #B259FF pendant l'attaque |
| body_eye_glint_FFFFFF | #FFFFFF | Neon |
| body_mouth_2B1440 | #2B1440 | SmoothPlastic |
| body_cheek_pink_FF9CCF | #FF9CCF | SmoothPlastic |
| arm_R_ghost_white_F3F1FF / arm_L_ghost_white_F3F1FF | #F3F1FF | SmoothPlastic |
| tail_1 … tail_4 _ghost_shade_C9C0F4 | #C9C0F4 | SmoothPlastic |

Couleurs VFX (Neon) : orbe #B26BFF · étincelles #6EF3FF · traînée #D59BFF · fumée de queue #8F7CFF.

## 2. Import
1. Dans la preview, cliquer sur **Download GLB**.
2. Roblox Studio → Avatar/Home → **Import 3D** → `voxel_ghost.glb`. Garder la hiérarchie et ne pas fusionner les meshes.
3. Le résultat est un Model qui contient des MeshParts `body_*`, `arm_R`, `arm_L`, `tail_1..4`.
4. Placer `GhostController.server.lua` dans un **Script** à l'intérieur du Model.

## 3. Animations (gérées par le script)
**Fly** (en boucle) : rebond vertical ±0,9 voxel (2 rad/s), dérive latérale ±2,5 voxels, roulis et lacet légers, bras qui battent (±0,18 rad), queue en vague chaînée (4 segments déphasés), fumée violette depuis le bout de la queue.

**Attack** (1,9 s) :
- 0–0,55 s : charge. Les bras se tendent vers l'avant, l'orbe grossit entre les mains, des étincelles cyan sont aspirées et les yeux deviennent Neon.
- 0,55 s : tir. L'orbe part tout droit (42 voxels/s) avec une traînée de particules.
- 23 voxels plus loin : explosion. Anneau de 28 cubes néon qui s'agrandit, gerbe de particules et flash lumineux.

**Contrôle via attributs du Model** : `Flying`, `AutoAttack`, `AttackEvery`. Pour déclencher une attaque : `ghost:SetAttribute("Attack", os.clock())`.

## 4. À vérifier
- Si l'orbe part vers l'arrière : passer `FRONT` à `Vector3.new(0, 0, -1)` en haut du script.
- Le script anime des parts ancrées. Pour un PNJ qui se déplace, déplacer le Model avec `ghost:PivotTo()` : le script repart de `baseCF`, il faut donc le mettre à jour (ou remplacer `baseCF` par la position de déplacement du PNJ).
