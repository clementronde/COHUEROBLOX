# Enemy_Zombie — handoff Roblox (pour Claude Code)

| # | Model | Rôle | Taille |
|---|---|---|---|
| 2 | Enemy_Zombie | Melee | 5.4 studs |

Même style que la première version du Voxel Ghost : gros voxels, tête en dôme, yeux noirs avec reflet. Détails volontairement réduits.

## 1. Parts et couleurs
Nom de chaque mesh : `<part>_<matière>_<HEX>`. Le script applique la couleur automatiquement.

| Part | Matières (hex) |
|---|---|
| head | skin_zombie #9CC98A · brain_pink #F29BB5 (dessus de la tête) · eye_black #120C1F (→ Neon #59FF26 en attaque) · eye_glint #FFFFFF (Neon) · mouth_dark #2B1A1E · tooth_yellow #EFE6B8 |
| torso | shirt_teal #3F7F8C · shirt_dark #2C5A63 (déchirure) · pants_brown #5B4636 |
| arm_L / arm_R | shirt_teal #3F7F8C (manche) · skin_zombie #9CC98A |
| leg_L / leg_R | pants_brown #5B4636 · shoe_dark #2E2620 |

Couleurs VFX (Neon) : griffures #C8FF7A · éclats toxiques #9CFF57 #4BD12E #E6FF9C · anneau #9CFF57 / #3FBF2A · nuage #4BD12E.

## 2. Import
1. Dans la preview `Enemy_Zombie.html`, cliquer sur **Download GLB**. L'export est toujours en pose de repos (bras écartés sur les côtés).
2. Studio → **Import 3D**. Garder la hiérarchie et ne pas fusionner les meshes.
3. Mettre `ZombieController.server.lua` dans un Script à l'intérieur du Model.

## 3. Animations
**Shamble** (en boucle, 4 rad/s) : bras tendus vers l'avant, démarche boiteuse (jambe gauche ±0,45 rad, jambe droite traînée ±0,22), balancement du buste, tête penchée.

**Attack — double griffe** (1,4 s) :
- 0–0,4 s : armé. Bras levés et écartés, buste en arrière, yeux vert néon.
- 0,4–0,52 s : fente vers l'avant de 0,22 m. Les bras se croisent en descendant, avec une traînée verte aux mains.
- 0,52 s : impact. Trois griffures diagonales, éclats toxiques, anneau vert au sol, nuage de poison pendant 1,2 s, et dégâts aux Humanoids dans `HitRadius`.
- 0,8–1,4 s : retour.

Pivots en voxels (1 voxel = Height/19), depuis le sol au centre des pieds : hanche (0,4,0) · jambes (±2,4,0) · cou (0,10,0) · épaules (±4.5,8.5,0).

## 4. Notes
- Attributs du Model : `Walking`, `AutoAttack`, `AttackEvery`, `Damage`, `HitRadius`, `Height`. Pour déclencher une attaque : `zombie:SetAttribute("Attack", os.clock())`.
- Le visage regarde vers +Z local. Pour suivre le `LookVector` de Roblox, tourner le Model de 180°.
