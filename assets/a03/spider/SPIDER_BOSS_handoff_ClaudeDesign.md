# Enemy_SpiderBoss — handoff Roblox (pour Claude Code)

| # | Model | Rôle | Taille |
|---|---|---|---|
| 7 | Enemy_SpiderBoss | **Giga boss** · 3 attaques : mêlée, salve de 6 toiles, invocation | **29 studs** de haut · **55 studs** d'envergure (1 voxel = 0,26 m) |

Style du projet (voir GUIDE_NOUVEL_ENNEMI.md) : gros voxels, dôme, yeux noirs avec reflet, peu de détails. Elle est **poilue** : touffes de poils sur la tête, sur l'abdomen (sauf autour du sablier) et sur toutes les pattes. 2 gros yeux 3×3 + 2 petits, 2 crocs ivoire, 1 sablier rouge, 2 filières. Abdomen géant 21×19×23 voxels. 8 très longues pattes (fémur 13,5 + tibia 29,5 voxels), chacune avec un genou. Le corps est haut sur pattes (13 voxels sous le ventre). Version précédente : `Enemy_SpiderBoss v1.html`.

## 1. Parts et couleurs
Nom de chaque mesh : `<part>_<matière>_<HEX>`. Le script applique la couleur automatiquement.

| Part | Matières (hex) | Matériau Roblox |
|---|---|---|
| head (céphalothorax) | body_purple #553482 · hair_violet #6D4C9A (poils) · eye_black #120C1F (→ Neon #FF2E1F en attaque) · eye_glint #FFFFFF | SmoothPlastic · glint en Neon |
| abdomen | abdomen_purple #432868 · hair_violet #6D4C9A (poils) · mark_red #E0412E (sablier) · claw_dark #1E1430 (filières) | SmoothPlastic · sablier en Neon |
| fang_L / fang_R | fang_ivory #F2EBD9 | SmoothPlastic |
| femur_L1…L4 / R1…R4 | body_purple #553482 · hair_violet #6D4C9A (poils) | SmoothPlastic |
| tibia_L1…L4 / R1…R4 | band_violet #8E66C4 (genou) · hair_violet #6D4C9A (poils) · body_purple #553482 · claw_dark #1E1430 (griffe) | SmoothPlastic |

Bébés araignées (créés par le script, pas dans le GLB) : mini copie du boss. Tête en dôme #553482 avec 2 yeux Neon #9BFF6A et 2 crocs #F2EBD9, abdomen poilu #432868 (poils #6D4C9A) avec un petit sablier Neon #E0412E, **8 pattes avec genou** (fémur + tibia #8E66C4) qui trottinent comme le boss. Œufs : #E8E2F0.

Couleurs VFX : zone de danger #FF3B2E / #FF7A3D · venin #9BFF6A / #3FD65A / #D6FFB0 · toile #F4F1FF / #D6D0EE · lueur de l'abdomen #E0412E · rochers #6F6A63 #8C867C #55514B · poussière #C9A66B #A8865A #8A6D47 · fissures #221A12.

## 2. Import
1. Dans la preview `Enemy_SpiderBoss.html`, cliquer sur **Download GLB**. L'export est en pose de repos : debout, toutes les articulations à 0.
2. Studio → **Import 3D**. Garder la hiérarchie et ne pas fusionner les meshes.
3. Mettre `SpiderBossController.server.lua` dans un Script à l'intérieur du Model. Il le redimensionne à `Height` (29 studs). L'échelle est mesurée sur le sac de l'abdomen, sans les poils.

## 3. Animations
Squelette : chaque patte = **hanche → fémur → genou → tibia**. Ce sont des barres droites avec une inclinaison fixe : fémur à +0,8 rad, tibia calculé pour que la griffe touche le sol. Les pattes s'ouvrent en éventail (lacet 0,6 / 0,2 / −0,25 / −0,65).

**Idle** : le corps respire, l'abdomen se balance et gonfle légèrement, les crocs tressaillent, une griffe tapote le sol de temps en temps.

**Marche** (4,2 rad/s) : démarche tétrapode (L1 R2 L3 R4, puis R1 L2 R3 L4). La patte qui avance se lève (0,3) et avance (±0,22), le corps rebondit et l'abdomen suit avec un retard. De la poussière apparaît à chaque appui.

**Attaque 1 — Empalement** (mêlée, 2,15 s) :
- 0–0,8 s : elle se cabre (−0,55, +4 voxels), lève très haut les 2 pattes avant, ouvre les crocs (du venin goutte), et ses yeux passent au rouge. Un anneau rouge apparaît au sol.
- 0,8–0,95 s : les 2 griffes avant se plantent dans le sol, devant elle (environ 44 voxels). Le genou est calculé au lancement pour qu'elles touchent le sol.
- 0,94 s : impact. Double onde de choc, rochers, fissures, puis **flaque de venin** (`PoolDps` pendant `PoolTime`). Dégâts + knockback dans `HitRadius`.

**Attaque 2 — Salve de 6 toiles** (distance, 2,4 s) :
- 0–0,55 s : elle s'accroupit, écarte les pattes avant, ouvre grand les crocs, et de la soie se rassemble devant la bouche. Le corps se tourne vers la gauche (−0,5).
- 0,68 / 0,8 / 0,92 / 1,04 / 1,16 / 1,28 s : **6 crachats**. À chaque fois la tête part vers l'avant, et le corps balaie de gauche à droite.
- Chaque boule vole en arc pendant 0,6 s. Les 6 cibles forment un **éventail** (angles ±0,62, distances 46 à 64 voxels) centré sur le joueur le plus proche (`WebRange`), sinon devant elle.
- À l'arrivée : 6 **toiles** collées au sol, de rayon `WebRadius`. Les joueurs dedans prennent `WebDamage` et sont **ralentis** (`WalkSpeed` = `WebSlow` pendant `WebTime`, une seule fois même s'ils sont pris dans plusieurs toiles).

**Attaque 3 — Bébés araignées** (invocation, 2,8 s) :
- 0–0,6 s : l'abdomen gonfle (+16 %) et le sablier brille (lumière rouge qui pulse).
- 1,0 s : elle pose l'abdomen au sol et l'abdomen pompe 3 fois.
- 1,05 → 1,6 s : **5 œufs** tombent des filières, rebondissent et tremblent.
- 1,9 → 2,14 s : les œufs **éclosent**. Chaque bébé trottine sur ses 8 pattes (démarche tétrapode, genoux), part sur le côté pendant 0,8 s, puis **poursuit le joueur le plus proche** : morsure `SpiderlingDamage` toutes les 0,8 s, `SpiderlingHP` de vie (Humanoid, donc les armes normales le touchent). Il disparaît après `SpiderlingLife`. Au maximum `MaxSpiderlings` bébés en même temps.

Mode auto : Empalement → Toile → Bébés, avec `AttackEvery` secondes entre deux attaques.

Pivots en voxels (1 voxel = Height / 31), depuis le sol au centre sous le corps : corps (0,18,0) · taille/abdomen (0,19,−1) · crocs (±2.5,15.5,12.5) · bouche (0,14,13) · filières (0,19,−24) · hanches (±6.5, 17, z = 9 / 6 / 3 / 0) · genou = hanche + 13,5 voxels le long du fémur · griffe = genou + 29,5 voxels le long du tibia.

## 4. Notes
- Attributs : `Walking`, `AutoAttack`, `AttackEvery` (2,6), `Height` (29) · Empalement : `Damage` (60), `HitRadius` (20), `Knockback` (90), `PoolDps` (12), `PoolTime` (2,6) · Toiles : `WebRange` (110), `WebRadius` (10), `WebSlow` (4), `WebTime` (3), `WebDamage` (10) · Bébés : `SpawnCount` (5), `MaxSpiderlings` (10), `SpiderlingHP` (40), `SpiderlingDamage` (8), `SpiderlingSpeed` (16), `SpiderlingLife` (25).
- Déclencher une attaque : `spider:SetAttribute("Impale" | "Web" | "Spawn", os.clock())`.
- La marche est sur place. Ton script d'IA déplace le Model. Le visage regarde vers +Z local : tourner le Model de 180° pour suivre le `LookVector` de Roblox.
