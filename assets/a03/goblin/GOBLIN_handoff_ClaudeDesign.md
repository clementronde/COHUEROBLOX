# Enemy_GoblinGrunt — handoff Roblox (pour Claude Code)

| # | Model | Rôle | Taille |
|---|---|---|---|
| 1 | Enemy_GoblinGrunt | Melee | 4.5 studs |

Style du projet (voir GUIDE_NOUVEL_ENNEMI.md) : gros voxels, tête en dôme, yeux noirs avec reflet, moufles rondes, peu de détails. Accessoires : marmite rouge + louche.

## 1. Parts et couleurs
Nom de chaque mesh : `<part>_<matière>_<HEX>`. Le script applique la couleur automatiquement.

| Part | Matières (hex) | Matériau Roblox |
|---|---|---|
| head | skin_green #6DBE45 (dôme + oreilles) · eye_black #120C1F (→ Neon #FF731A en attaque) · eye_glint #FFFFFF · mouth_dark #3A1414 · tooth_white #FFF8E7 | SmoothPlastic · glint en Neon |
| pot | pot_red #D63A2F · pot_rim #9E2420 · mouth_dark #3A1414 (intérieur) | SmoothPlastic |
| torso | tunic_brown #8A5A33 · leather_dark #4A2F1B (ceinture) | SmoothPlastic |
| arm_L / arm_R | tunic_brown #8A5A33 (manche) · skin_green #6DBE45 (bras + moufle ronde 3×3×3) | SmoothPlastic |
| leg_L / leg_R | skin_green #6DBE45 · leather_dark #4A2F1B (chaussures) | SmoothPlastic |
| ladle | metal_grey #B9C1C9 · metal_dark #4A5058 (intérieur du creux) | Metal |

Couleurs VFX (Neon) : traînée #FFF2C0 / #FFE14D · étoiles #FFE14D + blanc · éclats #FF8A3D · anneau #FFE14D / #FF8A3D.

## 2. Import
1. Dans la preview, cliquer sur **Download GLB**. L'export est en pose de repos : la louche est droite, le manche passe au centre de la moufle droite et le creux est en haut, ouvert vers l'avant.
2. Studio → **Import 3D**. Garder la hiérarchie et ne pas fusionner les meshes.
3. Mettre `GoblinController.server.lua` dans un Script à l'intérieur du Model.

## 3. Animations
**Walk** (en boucle, 7 rad/s) : jambes ±0,55 rad, petit rebond, buste qui tourne de ±0,08, bras gauche en balancier.

**Attack — coup horizontal de gauche à droite** (vu de face, 1,3 s) :
- 0–0,35 s : armé. La louche bascule vers l'avant (rotation X du bras 0 → +1,5) et le buste tourne vers la gauche (yaw 0 → −1,0). Les yeux deviennent orange néon.
- 0,35–0,5 s : balayage. Le buste tourne de −1,0 à +0,95, avec une traînée de cubes le long de l'arc.
- À mi-balayage : impact devant le gobelin. Étoiles, éclats, anneau horizontal, petit flash, et dégâts aux Humanoids dans `HitRadius`.
- 0,5–0,75 s : tenue. Puis 0,75–1,3 s : retour.

Pivots en voxels (1 voxel = Height / 20.85), depuis le sol au centre des pieds : hanche (0,3,0) · jambes (±2,3,0) · cou (0,8,0) · épaules (±4.5,6.5,0) · creux de la louche (8,16.5,1).

## 4. Notes
- Attributs du Model : `Walking`, `AutoAttack`, `AttackEvery`, `Damage`, `HitRadius`, `Height`. Pour déclencher une attaque : `goblin:SetAttribute("Attack", os.clock())`.
- Le visage regarde vers +Z local. Pour suivre le `LookVector` de Roblox, tourner le Model de 180°.
