# Enemy_WitchBroom — handoff Roblox (pour Claude Code)

| # | Model | Rôle | Taille |
|---|---|---|---|
| 8 | Enemy_WitchBroom | **Flying** · Ranged (lancer de potion) | 6.5 studs (des bottes à la pointe du chapeau), elle vole à 20 voxels du sol |

Style du projet (voir GUIDE_NOUVEL_ENNEMI.md) : gros voxels, tête en dôme, yeux noirs 2×2 avec reflet, bouche plate avec 1 dent, moufles rondes, peu de détails. Accessoires : chapeau pointu (bout replié vers l'arrière, bande dorée) + balai. Elle tient une potion verte dans la main droite.

## 1. Parts et couleurs
Nom de chaque mesh : `<part>_<matière>_<HEX>`. Le script applique la couleur automatiquement.

| Part | Matières (hex) | Matériau Roblox |
|---|---|---|
| head | skin_witch #92C95A (dôme) · hair_orange #E8742E (cheveux sur les côtés et derrière) · eye_black #120C1F (→ Neon #B46CFF en attaque) · eye_glint #FFFFFF · mouth_dark #3A1414 · tooth_white #FFF8E7 | SmoothPlastic · glint en Neon |
| hat | hat_dark #3A2560 (bord + cône) · band_gold #E0A82E | SmoothPlastic · bande en Metal |
| torso | dress_purple #5B3A8C (robe qui retombe des 2 côtés du balai) · hat_dark #3A2560 (ceinture) | SmoothPlastic |
| arm_L | dress_purple #5B3A8C (manche) · skin_witch #92C95A (moufle qui tient le manche du balai) | SmoothPlastic |
| upperarm_R | dress_purple #5B3A8C (haut du bras) | SmoothPlastic |
| forearm_R | dress_purple #5B3A8C (poignet) · skin_witch #92C95A (moufle ronde 3×3×3) | SmoothPlastic |
| potion | potion_green #7FE3A8 (fiole) · cork_tan #A8865A (bouchon) | Neon · SmoothPlastic |
| leg_L / leg_R | stocking_dark #2A1E36 (bas) · leather_dark #4A2F1B (bottes pointues recourbées) | SmoothPlastic |
| broom | wood_brown #7A4E2C (manche + crochet) · leather_dark #4A2F1B (lien) · straw_yellow #E0B04A / straw_dark #B8862E (paille) | Wood · SmoothPlastic |

Couleurs VFX : magie #B46CFF (Neon) · toxique #7FE3A8 / #9BFF6A / #3FD67A · étincelles #FFE14D · éclats de verre #D8F6FF.

## 2. Import
1. Dans la preview `Enemy_WitchBroom.html`, cliquer sur **Download GLB**. L'export est en pose de repos : articulations à 0, balai à 20 voxels du sol, potion dans la main.
2. Studio → **Import 3D**. Garder la hiérarchie et ne pas fusionner les meshes.
3. Mettre `WitchController.server.lua` dans un Script à l'intérieur du Model. Il le redimensionne à `Height` (6.5 studs), en mesurant la longueur du balai (29 voxels).

## 3. Animations
**Vol** (toujours actif) : coude droit légèrement plié vers l'avant (−0,35) pour montrer la potion. elle flotte en montant et descendant (±0,7 voxel, 2,2 rad/s) et le balai tangue doucement. Les jambes se balancent, chacune à son rythme. Le chapeau suit avec un retard (bout qui ballotte), et la tête regarde autour d'elle. Une traînée d'étincelles violettes et jaunes sort de la paille.
**Fly** (`Walking`) : elle dessine un 8 paresseux (±7 voxels en X, ±2 en Z). Le balai s'incline dans les virages (roulis ±0,2, lacet ±0,22), et le buste et la tête accompagnent le mouvement.

**Attack — lancer de potion** (1,34 s + vol de la fiole) :
- 0–0,4 s : **armé**. Le bras droit monte derrière le chapeau (épaule Z +1,3, X −0,75) et le **coude se replie vers l'arrière** (Y +1,5), la potion derrière la tête. Elle se penche en arrière (−0,22) et le nez du balai se relève (−0,14). La potion **brille** et fait des bulles, et les yeux passent en violet néon.
- 0,4–0,54 s : **lancer en coup de fouet**. L'épaule part d'abord (X → +1,45), puis le coude se détend 40 ms plus tard (Y +1,5 → −0,2). La fiole est lâchée à la moitié de ce déplié (environ 0,49 s), et elle se penche en avant (+0,25).
- La fiole vole en arc pendant 0,55 s en tournant sur elle-même, avec une traînée verte et violette. Elle vise le joueur le plus proche (`Range`), sinon elle atterrit 44 voxels devant.
- **Impact** : le verre éclate. Éclaboussure toxique, étincelles, éclats de verre, anneau vert et violet, petit flash, dégâts dans `HitRadius`. Puis une **flaque toxique** bouillonne pendant `PoisonTime` et inflige `PoisonDps`.
- 0,54–0,79 s : tenue. Puis 0,79–1,34 s : retour. Une nouvelle potion apparaît dans la main en grossissant.

Pivots en voxels (1 voxel = Height / 28), depuis le sol sous le siège : siège (0,20,0) · hanches (±2.5,20,1.5) · cou (0,27,1) · base du chapeau (0,35,1) · épaules (±4.5,25.5,1) · coude droit (6.5,24.5,1) · centre de la potion (9,27.5,1) · bout de la paille (0,20,−16).

## 4. Notes
- Attributs du Model : `Walking` (vol en 8), `AutoAttack`, `AttackEvery` (2,6 s), `Damage` (18), `HitRadius` (5), `Range` (60), `PoisonDps` (6), `PoisonTime` (1,9), `Height` (6.5). Pour déclencher une attaque : `witch:SetAttribute("Attack", os.clock())`.
- Le Model est ancré. Ton script d'IA le déplace (vol), et l'animation tourne par-dessus.
- Le visage regarde vers +Z local. Pour suivre le `LookVector` de Roblox, tourner le Model de 180°.
