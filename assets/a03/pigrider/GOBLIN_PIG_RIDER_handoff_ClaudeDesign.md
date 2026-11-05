# Enemy_GoblinPigRider — handoff Roblox (pour Claude Code)

| # | Model | Rôle | Taille |
|---|---|---|---|
| 6 | Enemy_GoblinPigRider | Melee · charge | 6 studs (sabots → dôme du gobelin, la lance dépasse au-dessus) |

Style du projet (voir GUIDE_NOUVEL_ENNEMI.md) : gros voxels, tête en dôme, yeux noirs avec reflet, moufles rondes, peu de détails. Le gobelin a le même design que Enemy_GoblinGrunt, sans la marmite. Accessoires : selle + lance.

## 1. Parts et couleurs
Nom de chaque mesh : `<part>_<matière>_<HEX>`. Le script applique la couleur automatiquement.

| Part | Matières (hex) | Matériau Roblox |
|---|---|---|
| pig_body | skin_pig #F4A3A8 · leather_dark #4A2F1B (selle) | SmoothPlastic |
| pig_head | skin_pig #F4A3A8 (dôme) · snout_pink #D9737E (groin + oreilles) · mouth_dark #3A1414 (2 narines) · eye_black #120C1F (→ Neon #FF731A en attaque) · eye_glint #FFFFFF | SmoothPlastic · glint en Neon |
| pig_tail | skin_pig #F4A3A8 (queue en tire-bouchon) | SmoothPlastic |
| pig_leg_FL / FR / BL / BR | skin_pig #F4A3A8 · hoof_dark #5A3A3A (sabots) | SmoothPlastic |
| head | skin_green #6DBE45 (dôme + oreilles) · eye_black #120C1F (→ Neon #FF731A) · eye_glint #FFFFFF · mouth_dark #3A1414 · tooth_white #FFF8E7 | SmoothPlastic · glint en Neon |
| torso | tunic_brown #8A5A33 · leather_dark #4A2F1B (ceinture) | SmoothPlastic |
| arm_L / arm_R | tunic_brown #8A5A33 (manche) · skin_green #6DBE45 (bras + moufle ronde 3×3×3) | SmoothPlastic |
| leg_L / leg_R | tunic_brown #8A5A33 (cuisse sur la selle) · skin_green #6DBE45 (tibia le long du flanc) · leather_dark #4A2F1B (chaussure) | SmoothPlastic |
| spear | wood_brown #7A4E2C (hampe) · leather_dark #4A2F1B (bague) · metal_grey #B9C1C9 (pointe) | Wood · Metal |

Couleurs VFX : traînée #FFF2C0 / #FFE14D (Neon) · étoiles #FFE14D + blanc · éclats #FF8A3D · anneau vertical #FFE14D / #FF8A3D · poussière des sabots #C9A66B / #A8865A · souffle du groin et lignes de vitesse en blanc.

## 2. Import
1. Dans la preview `Enemy_GoblinPigRider.html`, cliquer sur **Download GLB**. L'export est en pose de repos : lance droite dans la moufle droite.
2. Studio → **Import 3D**. Garder la hiérarchie et ne pas fusionner les meshes.
3. Mettre `GoblinPigRiderController.server.lua` dans un Script à l'intérieur du Model. Il le redimensionne à `Height` (6 studs).

## 3. Animations
**Trot** (en boucle, 8 rad/s) : les pattes bougent en diagonale (avant gauche + arrière droite, puis l'inverse) de ±0,5. Petit saut, le corps se balance (roulis ±0,035) et la tête hoche. La queue frétille (Z ±0,5 à 14 rad/s). Le gobelin rebondit sur la selle avec un léger retard (0,6 voxel) et compense le roulis. Main gauche en avant sur les rênes, jambes qui ballottent.

**Attack — charge** (1,34 s) :
- 0–0,4 s : **armé**. Le cochon recule de 2 voxels et se cabre (tangage −0,12), baisse la tête (+0,35) et gratte le sol avec le sabot avant droit (poussière). Il souffle par le groin. Le gobelin se penche en arrière, tourne le buste (−0,35) et couche la lance vers l'avant (bras X → +1,15). Les yeux du cochon et du gobelin passent en orange néon.
- 0,4–0,54 s : **ruée**. Il fonce de 14 voxels vers l'avant. La tête du cochon passe de baissée à relevée, le gobelin se penche en avant (+0,2), et la lance pique devant le groin. Traînée sur la pointe, poussière sous les 4 sabots, lignes de vitesse sur les côtés.
- 0,5 s (70 % de la ruée) : **impact** à la pointe de la lance. Étoiles, éclats, anneau vertical qui s'agrandit (la lance le traverse), poussière au sol, petit flash et léger tremblement de caméra. Dégâts + **knockback vers l'avant** dans `HitRadius`.
- 0,54–0,79 s : tenue. Puis 0,79–1,34 s : retour à la position de départ.

Pivots en voxels (1 voxel = Height / 26), depuis le sol au centre des 4 pattes : corps du cochon (0,8,0) · cou du cochon (0,9,8) · queue (0,10,−8.5) · pattes (±3,4,±5) · jambes du gobelin (±5,13,0) · hanche du gobelin (0,13,0) · cou (0,18,0) · épaules (±4.5,16.5,0) · pointe de la lance au repos (8,34.5,0) · groin (0,8,17.5).

## 4. Notes
- Attributs du Model : `Walking`, `AutoAttack`, `AttackEvery` (2,6 s), `Damage` (20), `HitRadius` (5), `Knockback` (45), `Height` (6). Pour déclencher une attaque : `rider:SetAttribute("Attack", os.clock())`.
- La ruée est purement visuelle : le Model revient à sa place. Pour un vrai déplacement, avancer le Model de 14 × U dans ton script d'IA pendant 0,4–0,54 s.
- Le visage regarde vers +Z local. Pour suivre le `LookVector` de Roblox, tourner le Model de 180°.
