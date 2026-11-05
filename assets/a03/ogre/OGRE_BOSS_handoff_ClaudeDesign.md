# Enemy_OgreBoss — handoff Roblox (pour Claude Code)

| # | Model | Rôle | Taille |
|---|---|---|---|
| 5 | Enemy_OgreBoss | **Mini boss** · Melee (zone) | **14.5 studs**, le plus gros ennemi (Gobelin 4.5 · Zombie 5.4 · Squelette 5) |

Style du projet (voir GUIDE_NOUVEL_ENNEMI.md) : gros voxels, tête en dôme, yeux noirs avec reflet, moufles rondes. Formes simplifiées, sans escaliers de pixels : torse en un seul gros bloc arrondi (17 voxels de large) avec un gros ventre clair rectangulaire, petite tête enfoncée dans les épaules, défenses, chignon, pagne. Arme : gros gourdin en bois clouté.

## 1. Parts et couleurs
Nom de chaque mesh : `<part>_<matière>_<HEX>`. Le script applique la couleur automatiquement.

| Part | Matières (hex) | Matériau Roblox |
|---|---|---|
| head | skin_ogre #8AA04E (dôme + oreilles) · eye_black #120C1F (→ Neon #FF3826 en attaque) · eye_glint #FFFFFF · mouth_dark #2A1A1A · tusk_white #F2EBD9 (2 défenses) · hair_dark #3A2616 (chignon) | SmoothPlastic · glint en Neon |
| torso | skin_ogre #8AA04E · belly_light #B4C77A (gros ventre) · cloth_brown #6B4428 (pagne + rabat) · belt_dark #3E2A1A (ceinture) | SmoothPlastic |
| upperarm_L / upperarm_R | skin_ogre #8AA04E (haut du bras 3×6×3) | SmoothPlastic |
| forearm_L / forearm_R | skin_ogre #8AA04E (énorme moufle ronde 5×5×5) · belt_dark #3E2A1A (brassard) | SmoothPlastic |
| thigh_L / thigh_R | skin_ogre #8AA04E (cuisse 3×4×3) | SmoothPlastic |
| shin_L / shin_R | skin_ogre #8AA04E (tibia + pied avec orteil) | SmoothPlastic |
| club | wood_brown #7A4E2C (col 3×3 + tête 5×5) · wood_dark #5A3820 (bout du manche) · stud_iron #A9B1B8 (4 clous) | Wood · Metal |

Couleurs VFX : zone de danger #FF3B2E / #FF7A3D (Neon) · onde de choc #FFB13D / #FF5A2E, puis blanc / #FFD27A · rochers #6F6A63 #8C867C #55514B · poussière #C9A66B #A8865A #8A6D47 · fissures #221A12 · traînée #FFD27A / #FF8A3D.

## 2. Import
1. Dans la preview `Enemy_OgreBoss.html`, cliquer sur **Download GLB**. L'export est en pose de repos (gourdin droit dans la moufle droite).
2. Studio → **Import 3D**. Garder la hiérarchie et ne pas fusionner les meshes.
3. Mettre `OgreBossController.server.lua` dans un Script à l'intérieur du Model. Il le redimensionne à `Height` (14.5 studs).

## 3. Animations
**Walk** (en boucle, 4 rad/s, très lourd) : jambes ±0,4 rad, gros rebond, buste qui roule de ±0,08, respiration. Un nuage de poussière se lève à chaque pas, avec un léger tremblement de caméra.

**Attack — coup de gourdin au sol, annoncé** (1,9 s) :
- 0–0,6 s : **armé et avertissement**. Le bras droit monte au-dessus de la tête (épaule −2,7, coude −1,3) et le gourdin pend dans le dos. Les genoux se chargent (0,3), le buste tourne, et le bras gauche se lève devant pour l'équilibre. Les yeux deviennent rouge néon et un anneau rouge pulse au sol.
- 0,6–0,75 s : **frappe** en accélération (ease-in). Le gourdin passe par-dessus la tête et s'abat devant (épaule −0,7, coude −0,15). Le poignet est calculé pour que la tête du gourdin touche le sol. L'ogre s'accroupit profondément (hanches −0,6, genoux 1,1), avec une traînée orange.
- 0,75 s : **impact**. Double onde de choc (jusqu'à environ 2,7 m), rochers, poussière, 14 fissures, petit flash au sol, gros tremblement de caméra, puis dégâts et **knockback** dans `HitRadius` (10 studs).
- 0,75–1,2 s : tenue. Puis 1,2–1,9 s : retour.

### Squelette (genoux + coudes)
hanche → **cuisse → genou → tibia** · épaule → **haut du bras → coude → avant-bras** (moufle) → **poignet → gourdin**. Pieds plantés : la hauteur du corps vient de la jambe la plus longue (4·cos h + 4·cos(h+g)). Les accroupissements se font donc en pliant les genoux. Toutes les poses (idle, attaque, sortie du sol) sont des pistes de clés sur 19 paramètres (`IX`), identiques dans la preview et dans le script.

### Idle
Genoux souples (0,14). Gourdin posé sur l'épaule droite : coude plié −1,5, poignet −0,42. Respiration sur le buste, les épaules et le coude gauche.

### Marche (naturelle)
Cycle de 1,75 s (phase = T × 3,6). Les cuisses balancent de ±0,45. Le genou de la jambe qui avance se plie (jusqu'à 0,85), puis se tend avant de retoucher le sol. Le bassin glisse au-dessus de la jambe d'appui (±0,35 voxel) et le buste penche du même côté (±0,07). Les épaules tournent à l'inverse des hanches (±0,08). Le bras gauche balance à l'opposé avec un retard (0,4) et le coude se plie quand le bras passe devant. Le gourdin rebondit sur l'épaule. La tête compense le roulis. La poussière apparaît quand le pied qui avance touche le sol.

### Sortie du sol (mort-vivant) · 5,8 s
Jouée au spawn (`RiseOnSpawn`) ou via `ogre:SetAttribute("Rise", os.clock())`. Le sol doit être opaque (Terrain ou Baseplate).
- 0–0,9 s : **grondement**. Un trou sombre s'ouvre (#1E140D / #2A1C12) avec un bord de terre (#4A3626 #6B4F36 #2E2118). Des fissures s'étendent, une lueur verte (#9BFF6A) monte et des particules vertes flottent.
- 1,15 s : **éruption**. Les deux mains et le gourdin jaillissent, bras tendus vers le ciel. Les yeux sont rouge néon et les mains tremblent.
- 1,75 s : les deux mains **frappent le sol** devant le trou, avec de la terre sous les moufles.
- 2,05 → 2,35 s : il **se hisse avec les bras**. Les coudes se plient pour prendre appui, puis se tendent et le corps sort du trou, avec une gerbe de terre à chaque poussée.
- 2,65 s : les jambes sortent.
- 3,0 s : **à genoux**. Genou droit au sol (poussière + secousse), pied gauche devant, main gauche sur le genou, gourdin posé en appui. La tête est baissée, puis il relève les yeux à 3,5 s.
- 3,9 s : **il se relève** en poussant sur sa jambe avant.
- 4,3–5,0 s : **rugissement**. Il se cambre, coude gauche fléchi et gourdin levé. Double onde de choc et anneau de poussière.
- 5,0–5,7 s : retour à l'idle, puis la marche reprend. Le trou disparaît en 2,5 s.

Clés (t, profondeur en voxels, lean, roll, tête X/Z, bras G z/x, bras D z/x, jambes G/D) : identiques dans la preview et le script (`RISE`).

Pivots en voxels (1 voxel = Height / 34), depuis le sol au centre des pieds : hanche (0,8,0) · hanches G/D (±4,8,0) · genoux (±4,4,0) · cou (0,22.3,1.5) · épaules (±10,22.5,0) · coudes (±10,17,0) · poignet droit (10,12,0) · centre de la tête du gourdin au repos (12,12,16). Le point d'impact est calculé au lancement (environ 11,5 / 25,8 voxels devant).

## 4. Notes
- Attributs du Model : `Walking`, `AutoAttack`, `AttackEvery` (3 s), `Damage` (45), `HitRadius` (10), `Knockback` (75), `Height` (14.5), `RiseOnSpawn` (true). Pour déclencher une attaque : `ogre:SetAttribute("Attack", os.clock())`.
- Le visage regarde vers +Z local. Pour suivre le `LookVector` de Roblox, tourner le Model de 180°.
