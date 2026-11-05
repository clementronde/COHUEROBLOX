# 12 — Armes : modèles et effets (A14)

Domaine **armes, modèles et effets**. Agent A14, branche `claude/a14-armes-5c1460`. État au 5 nov. 2026, **étape 1 : inventaire**, validé par Clément (porte 1, section 11).

Sources lues : `01-decisions-v2.md` (sections 3, 4, 6, 12), `10-combat-armes-grimoires-objets.md` (sections 5, 6, 8, 10), `20-run-mondes-boss.md` (section 4), `80-direction-artistique.md`, `shared/Config/{Weapons,Grimoires,Classes,Items,Enemies,Bosses}.luau`, `shared/WeaponFxCodec.luau`, `server/Services/{WeaponService,PassiveService}.luau`, `client/Controllers/{WeaponFX,EnemyAttackFX,EnemyRenderer,BossRenderer}.luau`. La config fait foi en cas d'écart avec ce document.

Mots utilisés :
- **modèle tenu** : l'arme que le joueur porte ou qui flotte près de lui (dans `ReplicatedStorage.Assets.Weapons`) ;
- **pièce** : l'objet qui vole ou tourne en jeu (flèche, hache, bombe…) ;
- **effet** : particules, traînée, onde, éclats, lumière (dans `ReplicatedStorage.Assets.FX`).

Pour chaque attaque, on décrit quatre moments : le **départ** (l'arme tire), la **trajectoire** (la pièce vole ou la zone s'ouvre), l'**impact** (ça touche) et le **statut** (brûlure, gel…). S'y ajoutent la **montée de niveau** et la **fusion**.

---

## 0. En bref

| | Existe aujourd'hui | Reste à faire |
| --- | --- | --- |
| Modèles tenus | 8 MeshParts voxel v1 dans `Assets.Weapons` (armes de départ), jamais utilisés par le code | 16 modèles en pixel art épaissi (8 refaits, 8 nouveaux) + 16 modèles de fusion |
| Pièces en jeu | Aucune : `WeaponFX` fabrique des Parts Block / Ball / Cylinder de couleur unie | 10 pièces (flèche, dague, hache, boomerang, bombe, lance, météore, lame, tourelle, carreau) + variantes de fusion |
| Effets d'armes | Aucun objet : des Parts plates (anneaux, plaques) fabriquées par script. Ni ParticleEmitter, ni Beam, ni Trail, ni lumière | 41 effets pour les 16 armes (section 8), plus ceux des fusions |
| Autres effets dessinés par `WeaponFX` | 9 visuels spéciaux (parade, soin, fantôme, sifflet…) et le télégraphe rouge, tous en Parts fabriquées par script | 10 effets (section 4) |
| `assets/fx/` | Anneau et icône de capture (A01) | Rien de A14 |

**Fusions.** Aucune n'existe encore dans la config (`Weapons.FusionEnabled = false`). Clément a validé le 5 nov. la liste de la section 3 : A14 fait les 16 modèles et leurs effets, A04 (A04-09) écrit les règles et les chiffres.

**Ennemis et boss.** Leurs attaques visibles (section 7) sont fabriquées par `EnemyAttackFX`, `EnemyRenderer` et `BossRenderer`. Clément les a confiées à A14 le 5 nov. (porte 1).

---

## 1. Comment un effet arrive au client

Le serveur simule tout à 15 Hz et envoie des évènements cosmétiques (`WeaponFx`, UnreliableRemoteEvent, `WeaponFxCodec`). Le client ne voit que ces évènements : un effet ne peut montrer que ce qu'ils portent.

| Évènement | Armes | Ce que le client reçoit | Ce qu'il ne reçoit pas |
| --- | --- | --- | --- |
| Projectile | Longbow, Fire Staff, Throwing Daggers, Spear Throw, Boomerang, carreaux de la tourelle, fantôme Blankie | départ, vitesse, durée de vie, taille, tireur (FxSlot) | les ennemis touchés en chemin |
| Fin de projectile | idem | le projectile s'arrête (perce épuisée, attrapé) | où et quoi il a touché, sauf sa dernière position |
| Zone | Broadsword (cône), Quake Hammer, Beast Whip, Frost Nova (cercle), explosion du Fire Staff, Bomb Bag et Meteor Rain (avec délai), visuels spéciaux | centre, rayon, direction, demi-angle, délai avant impact | **le tireur** (`a = 0`), le niveau, une fusion |
| Segment | Lightning Chain, arcs de critique | les deux bouts | la cible exacte |
| Attaché | Holy Aura (aura), Spinning Axes et Orbiting Blades (orbite), Crossbow Turret (fixe) | tireur, rayon, nombre, durée, vitesse de rotation | les tics de dégâts |

**Limites qui comptent pour les effets** (les contract requests de la section 10 les lèvent) :

1. **Aucun évènement de touche.** Un coup qui perce, une aura qui tique, une orbite qui frappe ne disent rien au client. Les impacts se dessinent donc en fin de projectile, à l'explosion, ou sur la zone entière, pas sur chaque ennemi.
2. **Pas de niveau, pas de fusion.** Le client ne connaît que la taille (rayon) et le nombre. Un palier visuel (liseré or au niveau 8) ou un visuel de fusion demande une information en plus.
3. **Les zones n'ont pas de tireur.** La bombe ne peut pas partir de la main du joueur qui l'a lancée.
4. **Statuts des ennemis.** Le client ne voit qu'un bit « arrêté » (gel et étourdissement confondus, teinte givre de `EnemyRenderer`). Brûlure, ralentissement et poison ne sont pas visibles par ennemi. On les montre au sol, sur la zone touchée, pendant leur durée.
5. **Les critiques ne sont pas envoyés.** Ni Eagle Eye (Archer) ni la Crit Rune n'ont de visuel possible aujourd'hui.

Qualité (`WeaponFX`, inchangée) : *Bas* (téléphone : 60 projectiles, 12 zones, 16 segments, 24 attachés, sans fondu), *Moyen* (150 / 28 / 40 / 48), *Haut* (300 / 56 / 80 / 96). Les télégraphes ne sont jamais coupés.

---

## 2. Les 16 armes

Niveaux : la config a 7 deltas par arme (niveaux 2 à 8). Ne sont listés que ceux qui changent ce qu'on voit (rayon, nombre, angle, durée, statut). La taille et le nombre suivent seuls, car le serveur les envoie.

### 2.1 Broadsword — Knight (arme de départ)

`kind` Cone · évènement Zone (cône) · scaling Size, Damage

| Attaque | Règle | Départ | Trajectoire | Impact |
| --- | --- | --- | --- | --- |
| Coup de taille | cône 140° vers l'ennemi le plus proche, rayon 8, recul 4, 16 dégâts, 1,1 s | la lame tenue scintille | croissant de lumière (bord blanc, corps Sky, halo) qui balaie le cône en 0,15 s | éclat blanc et étincelles sur chaque ennemi touché |
| Revers (niv. 4) | 2e coup, 0,18 s après, derrière le joueur (`swingBack`) | — | même croissant, à l'opposé | idem |
| Niveaux | niv. 3 et 8 : rayon +15 % · niv. 7 : angle +40° (180°) | | le croissant suit rayon et angle | |
| Niveau 8 | | | liseré Gold sur le croissant (palier, section 10) | |
| Fusion | « Royal Greatsword » (section 3) | | | |

- **Existe** : `Weapon_Broadsword` (v1 voxel, pommeau en canard). Effet : plaque plate grise fabriquée par script.
- **À faire** : modèle tenu en pixel art ; effet `Swing` (croissant) ; effet `Impact` ; accent Gold du niveau 8 ; fusion.

### 2.2 Longbow — Archer (arme de départ)

`kind` Shot · évènements Projectile, Fin · scaling Amount, AttackSpeed

| Attaque | Règle | Départ | Trajectoire | Impact |
| --- | --- | --- | --- | --- |
| Flèche | auto vers l'ennemi le plus proche (portée 55), 80 studs/s, perce 3, 12 dégâts, 1 s | éclat Leaf à la corde de l'arc tenu | flèche (pièce) et traînée courte Cream | plumes et éclats à la fin de course |
| Niveaux | niv. 2 et 8 : +1 flèche (éventail de 6°) · niv. 4 et 8 : perce +2 · niv. 5 : 2e volée 0,15 s après | | | |
| Niveau 8 | 3 flèches × 2 volées, perce 7 | | pointe Gold | |
| Fusion | « Storm Bow » (exemple des décisions v2) | | | |

- **Existe** : `Weapon_Longbow` (v1, une feuille pousse au bout). Effet : bâton crème de 2,4 studs fabriqué par script.
- **À faire** : modèle tenu ; pièce `Arrow` ; effets `Cast`, `Trail`, `Impact` ; accent du niveau 8 ; fusion.

### 2.3 Fire Staff — Mage (arme de départ)

`kind` Shot + explosion (`popRadius`, `endBlast`) · statut Brûlure · évènements Projectile, Fin, Zone · scaling Size, Damage

| Attaque | Règle | Départ | Trajectoire | Impact |
| --- | --- | --- | --- | --- |
| Boule de feu | 42 studs/s, explose au 1er ennemi ou en fin de course (1,3 s), 14 dégâts, 1,4 s | flash Ember au cristal du bâton | boule de lumière blanc-or, halo braise, traînée (Trail), petite lumière en qualité Haute | explosion de rayon 5 : flash blanc, onde de choc orange au sol, étincelles, fumée douce |
| Brûlure | 4 dégâts/s pendant 2 s | | | flammèches au sol dans la zone pendant 2 s (limite 4 de la section 1) |
| Niveaux | niv. 3 : explosion +20 % · niv. 4 : 2 boules · niv. 5 : brûlure +3/s · niv. 8 : explosion +25 % | | | l'explosion suit le rayon |
| Fusion | « Sun Staff » | | | |

- **Existe** : `Weapon_FireStaff` (v1, une guimauve grille sous la flamme). Effet : boule orange et anneau plat orange fabriqués par script.
- **À faire** : modèle tenu ; effets `Cast`, `Fireball`, `Explosion`, `Burn` ; fusion.

### 2.4 Quake Hammer — Guardian (arme de départ)

`kind` Nova · statut Étourdi (niv. 8) · évènement Zone (cercle) · scaling Size, Armor

| Attaque | Règle | Départ | Trajectoire | Impact |
| --- | --- | --- | --- | --- |
| Onde de choc | cercle de rayon 9 autour du joueur, recul 8, 22 dégâts (+1 %/armure), 2,4 s | poussière sous le marteau tenu | onde de choc au sol (anneau lumineux et poussière douce) qui s'élargit | poussière et étincelles au bord de l'onde |
| Niveaux | niv. 3 et 7 : rayon +15 % · niv. 5 : 2e onde 0,3 s après | | | |
| Niveau 8 | étourdit 0,3 s | | | étoiles au-dessus de la zone (teinte givre de `EnemyRenderer` aujourd'hui, limite 4) |
| Fusion | « Mountain Maul » | | | |

- **Existe** : `Weapon_QuakeHammer` (v1, pansement en croix). Effet : disque plat marron fabriqué par script.
- **À faire** : modèle tenu ; effets `Slam`, `Shockwave`, `Stun` ; fusion.

### 2.5 Throwing Daggers — Rogue (arme de départ)

`kind` Shot · évènements Projectile, Fin · scaling Amount, AttackSpeed

| Attaque | Règle | Départ | Trajectoire | Impact |
| --- | --- | --- | --- | --- |
| Éventail de dagues | 3 dagues sur 14°, 65 studs/s, portée 35, perce 1, 7 dégâts, 0,9 s | petit éclat Plum devant le joueur | dague (pièce, ruban rouge) et traînée fine Plum | tintement d'étincelles en fin de course |
| Niveaux | niv. 2, 5 : +1 dague · niv. 8 : +2 (7 dagues) · niv. 4 : perce +1 | | | |
| Fusion | « Dagger Flurry » | | | |

- **Existe** : `Weapon_ThrowingDagger` (v1, ruban rouge au pommeau). Effet : bâtonnet gris fabriqué par script.
- **À faire** : modèle tenu (ceinture de dagues ?) ; pièce `Dagger` ; effets `Trail`, `Impact` ; fusion.

### 2.6 Holy Aura — Cleric (arme de départ)

`kind` Cloud permanent · évènement Attaché (aura) · scaling Size, Damage

| Attaque | Règle | Départ | Trajectoire | Impact |
| --- | --- | --- | --- | --- |
| Aura | anneau permanent de rayon 6 qui suit le joueur, tic toutes les 0,5 s, 5 dégâts | la clochette tenue sonne | disque au sol Gold translucide, bord Neon Gold, qui pulse au rythme des tics | petites étincelles dorées dans la zone |
| Soin du Cleric (Blessing) | 1,5 PV par tic aux joueurs dans l'aura | | | visuel spécial `Blessing` (section 4) |
| Niveaux | niv. 3, 6 : rayon +15 % · niv. 8 : +20 % · niv. 4 : tic −15 % | | le disque suit le rayon | |
| Fusion | « Grand Chime » | | | |

- **Existe** : `Weapon_HolyBell` (v1, clochette de cantine en porcelaine). Effet : disque plat doré transparent fabriqué par script.
- **À faire** : modèle tenu ; effets `Aura` (disque et bord), `Pulse` ; fusion.
- **Note** : le client ne reçoit pas les tics. Il pulse sur la cadence de la config (0,5 s, puis −15 % au niv. 4), sans la vitesse d'attaque du joueur.

### 2.7 Spinning Axes — Barbarian (arme de départ)

`kind` Orbit · évènement Attaché (orbite) · scaling Amount, Duration

| Attaque | Règle | Départ | Trajectoire | Impact |
| --- | --- | --- | --- | --- |
| Haches en orbite | 2 haches, rayon d'orbite 6, pendant 3,5 s, recul 5, 10 dégâts, recharge 5 s | les haches apparaissent avec un pop de copeaux | hache (pièce, smiley gravé) qui tourne sur elle-même, traînée en qualité Haute | éclats de bois sur la trajectoire |
| Niveaux | niv. 2, 6, 8 : +1 hache (5) · niv. 4, 8 : +1 s · niv. 5 : rayon +15 % · niv. 7 : rotation +25 % | | | |
| Fin | les haches s'en vont au bout de la durée | | | pop de disparition |
| Fusion | « Axe Tornado » | | | |

- **Existe** : `Weapon_SpinningAxe` (v1, smiley gravé sur le fer). Effet : plaques marron fabriquées par script.
- **À faire** : modèle tenu ; pièce `Axe` ; effets `Spawn`, `Trail`, `Despawn` ; fusion.

### 2.8 Beast Whip — Tamer (arme de départ)

`kind` Nova · évènement Zone (cercle) · scaling Size

| Attaque | Règle | Départ | Trajectoire | Impact |
| --- | --- | --- | --- | --- |
| Claque à 360° | cercle de rayon 8,5, recul 6, 15 dégâts, 1,7 s | le fouet tenu se déroule | traînée de lumière Ember qui fait un tour complet en 0,2 s, pompon de cirque au bout | étoile « crack » Ember au bout de la lanière |
| Niveaux | niv. 3, 6 : rayon +15 % · niv. 8 : +20 % · niv. 4 : 2e claque 0,25 s après | | | |
| Fusion | « Ringmaster Lash » | | | |

- **Existe** : `Weapon_BeastWhip` (v1, fouet enroulé à pompon). Effet : disque plat brique fabriqué par script.
- **À faire** : modèle tenu ; effets `Lash` (tour de lanière), `Crack` ; fusion.

### 2.9 Lightning Chain — pool commun

`kind` Chain · évènement Segment · scaling Bounces, CritChance

| Attaque | Règle | Départ | Trajectoire | Impact |
| --- | --- | --- | --- | --- |
| Éclair qui rebondit | frappe l'ennemi le plus proche (≤ 30 studs) puis rebondit 2 fois (≤ 12 studs), 11 dégâts, 1,3 s | le porteur (à créer) crépite | arc en zigzag Neon Sky (Beam), 0,15 s par segment | étoile électrique au bout de chaque segment |
| Niveaux | niv. 2, 5 : +1 rebond · niv. 8 : +2 (6 rebonds) · niv. 4 : 2 chaînes · stat Bounces (Trombone tordu) jusqu'à +10 | | un segment de plus par rebond | |
| Fusion | « Thunder Web » | | | |

- **Existe** : rien comme modèle. Effet : barre bleu clair étirée fabriquée par script.
- **À faire** : modèle porteur (proposition : paratonnerre de poche, à juger sur la planche) ; effets `Bolt`, `Spark` ; fusion.

### 2.10 Frost Nova — pool commun

`kind` Nova · statuts Ralenti, Gel (niv. 4+) · évènement Zone (cercle) · scaling Size, Duration

| Attaque | Règle | Départ | Trajectoire | Impact |
| --- | --- | --- | --- | --- |
| Onde de givre | cercle de rayon 10, ralentit de 50 % pendant 1 s, 10 dégâts, 3 s | le porteur souffle du froid | anneau de cristaux Sky qui sort, givre au sol | flocons ; le sol reste givré 1 s (durée du ralenti) |
| Gel | niv. 4 : 0,4 s · niv. 8 : 0,8 s | | | teinte givre de `EnemyRenderer` (existe, A03) |
| Niveaux | niv. 3, 7 : rayon +15 % | | | |
| Fusion | « Blizzard Globe » | | | |

- **Existe** : rien comme modèle. Effet : disque plat bleu glace fabriqué par script. Teinte givre des ennemis arrêtés (A03).
- **À faire** : modèle porteur (proposition : boule à neige) ; effets `Nova`, `Frost` (sol givré) ; fusion.

### 2.11 Boomerang — pool commun

`kind` Boomerang · évènements Projectile, Fin · scaling Size, Amount

| Attaque | Règle | Départ | Trajectoire | Impact |
| --- | --- | --- | --- | --- |
| Aller-retour | part 0,55 s vers l'ennemi le plus proche, revient vers le joueur, transperce tout, 13 dégâts, 1,5 s | — | boomerang (pièce) qui tourne, traînée Gold ; le client imite le retour vers le tireur | pop quand le joueur le rattrape |
| Niveaux | niv. 2, 5, 8 : +1 boomerang (4) · niv. 4 : taille +15 % | | | |
| Fusion | « Comeback Rang » | | | |

- **Existe** : rien comme modèle. Effet : plaque orange qui tourne, fabriquée par script.
- **À faire** : modèle tenu (le boomerang lui-même) ; pièce `Boomerang` ; effets `Trail`, `Catch` ; fusion.

### 2.12 Bomb Bag — pool commun

`kind` Strike · évènement Zone avec délai 0,8 s · scaling Size, Amount

| Attaque | Règle | Départ | Trajectoire | Impact |
| --- | --- | --- | --- | --- |
| Bombe | sur un ennemi à ≤ 25 studs, explose après 0,8 s, rayon 6, recul 6, 24 dégâts, 2,6 s | la bombe sort du sac | bombe Ink à mèche (pièce) qui vole en cloche pendant 0,8 s (le point de départ manque, limite 3) ; télégraphe au sol, toujours dessiné | explosion : flash blanc, onde orange, étincelles, fumée douce |
| Niveaux | niv. 4, 7 : +1 bombe (3) · niv. 3 : rayon +15 % · niv. 8 : +20 % | | | l'explosion suit le rayon |
| Fusion | « Cluster Sack » (mini-bombes : le moteur `cluster` et le visuel `MiniBomb` existent) | | | |

- **Existe** : rien comme modèle. Effets : anneau orange plat et télégraphe rouge, fabriqués par script.
- **À faire** : modèle tenu (sac) ; pièce `Bomb` ; effets `Telegraph`, `Explosion` ; fusion.

### 2.13 Spear Throw — pool commun

`kind` Shot, perce infinie · évènements Projectile, Fin · scaling Damage, Amount

| Attaque | Règle | Départ | Trajectoire | Impact |
| --- | --- | --- | --- | --- |
| Lance | 75 studs/s, portée 50, traverse tout, recul 3, 20 dégâts, 1,8 s | — | lance (pièce, 4 studs) et traînée Leather | en fin de course, la lance se plante dans le sol puis disparaît |
| Niveaux | niv. 3, 7 : +1 lance · niv. 4 : taille +20 % · niv. 8 : +30 % | | | |
| Fusion | « Comet Javelin » | | | |

- **Existe** : rien comme modèle. Effet : barre de 4 studs fabriquée par script.
- **À faire** : modèle tenu ; pièce `Spear` ; effets `Trail`, `Stuck` ; fusion.

### 2.14 Meteor Rain — pool commun

`kind` Strike · statut Brûlure · évènement Zone avec délai 0,9 s · scaling Luck, Size

| Attaque | Règle | Départ | Trajectoire | Impact |
| --- | --- | --- | --- | --- |
| Météores | 2 météores sur des ennemis au hasard (≤ 35 studs), 0,9 s de télégraphe, rayon 7, 40 dégâts, 3,2 s ; +1 % de météore par point de Chance | — | télégraphe au sol (toujours dessiné) ; météore (pièce en pixel art) en feu, avec traînée lumineuse, qui tombe du ciel pendant ces 0,9 s (calcul client) | cratère, éclats, flammes |
| Brûlure | 3 dégâts/s pendant 2 s | | | flammes au sol dans la zone pendant 2 s |
| Niveaux | niv. 3, 7 : +1 météore (4) · niv. 4 : rayon +15 % · niv. 8 : +20 % | | | |
| Fusion | « Star Shower » | | | |

- **Existe** : rien comme modèle. Effets : anneau rouge plat et télégraphe rouge, fabriqués par script.
- **À faire** : modèle porteur (à juger sur la planche) ; pièce `Meteor` ; effets `Telegraph`, `Fall`, `Impact`, `Burn` ; fusion.
- **Note** : la couleur actuelle (255, 80, 50) est presque Tomato, la couleur du danger ennemi. Voir la section 9.

### 2.15 Orbiting Blades — pool commun

`kind` Orbit permanent · évènement Attaché (orbite) · scaling Amount, AttackSpeed

| Attaque | Règle | Départ | Trajectoire | Impact |
| --- | --- | --- | --- | --- |
| Lames en orbite | 3 petites lames permanentes, orbite serrée (rayon 3,5), 6 dégâts toutes les 0,35 s par ennemi | apparition à l'équipement | lame (pièce, disque de scie en pixel art Steel) qui tourne, traînée légère en qualité Haute | étincelles sur l'orbite |
| Niveaux | niv. 2, 5 : +1 lame · niv. 8 : +2 (7 lames) · niv. 4 : rotation +20 % · niv. 7 : rayon +15 % | | | |
| Fusion | « Buzzsaw Halo » | | | |

- **Existe** : rien comme modèle. Effet : disques gris fabriqués par script.
- **À faire** : modèle tenu ; pièce `Blade` ; effets `Trail`, `Spark` ; fusion.

### 2.16 Crossbow Turret — pool commun

`kind` Turret · évènements Attaché (fixe) et Projectile (carreaux) · scaling Duration, Amount

| Attaque | Règle | Départ | Trajectoire | Impact |
| --- | --- | --- | --- | --- |
| Pose de la tourelle | arbalète fixe à 3 studs du joueur, pendant 8 s, recharge 6 s | la tourelle tombe et se déplie avec de la poussière | tourelle (pièce) qui pivote vers sa cible | la tourelle se replie et disparaît |
| Carreaux | toutes les 0,8 s, portée 38, 70 studs/s, perce 2, 8 dégâts | petit recul de l'arbalète | carreau (pièce) et traînée courte | éclats en fin de course |
| Niveaux | niv. 3 : +2 s · niv. 4 : cadence −15 % · niv. 5, 8 : +1 tourelle (3) · niv. 7 : +1 carreau (la stat Amount ajoute aussi des carreaux) | | | |
| Fusion | « Siege Ballista » | | | |

- **Existe** : rien comme modèle. Effet : bloc marron fabriqué par script. **Bug visuel** : les carreaux utilisent le même style que la tourelle, donc chaque carreau est dessiné comme un bloc de 1,6 × 2,2 × 1,6 studs. Je le corrige côté client (style par type d'évènement), sans toucher au serveur.
- **À faire** : pièces `Turret` et `Bolt` ; effets `Deploy`, `Trail`, `Impact`, `Despawn` ; fusion.

---

## 3. Fusions (liste validée par Clément le 5 nov.)

Règle du moteur (`Config/Weapons`) : une arme au niveau 8 + une Rune précise au niveau 5 donnent une version ultime au niveau 9 (carte Legendary). Le moteur existe, mais aucune fusion v2 n'est écrite et `FusionEnabled = false`. Cette liste fixe les **noms, les paires et le visuel** ; les chiffres de jeu restent à A04 (A04-09).

Chaque Rune vient d'une stat qui fait briller l'arme (colonne « Brille avec » du dossier 10). Wisdom et Cursed ne servent à aucune fusion.

| Arme | Rune (niv. 5) | Nom proposé | Idée visuelle |
| --- | --- | --- | --- |
| Broadsword | Area | Royal Greatsword | lame double bleu roi bordée d'or, deux croissants superposés |
| Longbow | Attack Speed | Storm Bow | arc en nuage, flèches-éclairs Sky |
| Fire Staff | Damage | Sun Staff | soleil miniature au bout du bâton, explosion plus large qui laisse une flaque de feu |
| Quake Hammer | Armor | Mountain Maul | tête en rocher, l'onde soulève des piliers de pierre |
| Throwing Daggers | Projectiles | Dagger Flurry | dagues en cercle complet, rubans multicolores |
| Holy Aura | Vitality | Grand Chime | grande cloche dorée, double anneau au sol |
| Spinning Axes | Duration | Axe Tornado | haches prises dans un tourbillon de feuilles |
| Beast Whip | Agility | Ringmaster Lash | double lanière, confettis de cirque à l'impact |
| Lightning Chain | Crit | Thunder Web | arcs ramifiés, une toile d'éclairs entre les cibles |
| Frost Nova | Cooldown | Blizzard Globe | boule à neige géante, la nova laisse une tempête de flocons |
| Boomerang | Magnet | Comeback Rang | boomerang double qui aspire les gemmes d'XP au retour (visuel seulement) |
| Bomb Bag | Projectiles | Cluster Sack | grosse bombe qui éclate en mini-bombes (`cluster`, `MiniBomb`) |
| Spear Throw | Damage | Comet Javelin | lance à queue de comète, cratère en fin de course |
| Meteor Rain | Luck | Star Shower | étoiles dorées au lieu de rochers, pluie d'étincelles |
| Orbiting Blades | Area | Buzzsaw Halo | anneau de scies plus large, halo Neon |
| Crossbow Turret | Duration | Siege Ballista | baliste sur roues, gros carreaux |

Effets d'une fusion : un **éclair de transformation** sur le joueur au moment du choix (commun aux 16, couleur de l'arme), puis les effets de l'arme refaits avec le modèle de fusion.

Champs v1 du moteur que A04 peut réutiliser pour les fusions : `chainOnCrit` (arcs de critique, visuel `ChainBolt`), `cluster` (mini-bombes, visuel `MiniBomb`), `splitOnEnd`, `follow`, `xpOnKill`, `lifesteal`.

---

## 4. Autres effets dessinés par `WeaponFX`

Ces visuels ne sont pas des armes, mais `WeaponFX` les fabrique. Pour que `WeaponFX` ne fabrique plus rien de visible, ils doivent tous devenir des objets de `Assets.FX`.

| Visuel (id réseau) | Source | Quand | Existe (Parts fabriquées par script) | À faire |
| --- | --- | --- | --- | --- |
| Parry (20) | Knight, Valor | parade d'un coup, toutes les 8 s ; zone de rayon 3,5 | anneau jaune | bouclier de lumière Royal qui s'ouvre, étincelle « ting » |
| Blessing (21) | Cleric, Blessing | soin d'un allié dans l'aura, au plus toutes les 1,5 s ; zone de rayon 2,5 | anneau doré | croix Gold qui monte au-dessus de l'allié |
| Ghost (22) | objet Blankie Ghost (Legendary) | tous les 50 studs parcourus, projectile guidé | boule blanche | petit fantôme-doudou en pixel art Cream |
| Whistle (23) | objet Recess Whistle | toutes les 20 s, recul à 14 studs | anneau blanc | onde de sifflet (anneau et notes) |
| Megaphone (24) | objet Megaphone | toutes les 12 s, étourdit à 10 studs | anneau jaune | cône de son, lettres « !! » |
| Thorns (25) | Guardian Bulwark, objet Thumbtack | renvoi des coups de mêlée, rayon 6 | anneau marron | piques de pierre qui sortent autour du joueur |
| Shadowstep (26) | Rogue, Shadowstep | début de glissade, 0,5 s d'invulnérabilité ; zone de rayon 3 | anneau violet | fumée Plum et silhouette fantôme |
| ChainBolt (27) | champ `chainOnCrit` (v1) | arcs de critique | barre jaune | aucun contenu v2 ne l'utilise ; servira si une fusion le reprend |
| MiniBomb (28) | champ `cluster` (v1) | mini-bombes | anneau rose | aucun contenu v2 ; **le rose est réservé à la capture** (DA §4), à changer ; servira pour Cluster Sack |
| Télégraphe | Bomb Bag, Meteor Rain | avant l'impact | anneau rouge | voir la couleur, section 9 |

Effets de classe ou d'objet **sans visuel aujourd'hui** (aucun évènement envoyé) : Eagle Eye (Archer), Arcane Surge (Mage), Rage (Barbarian), Flashlight (étourdit sur critique), Safety Scissors (coup double). Ils resteront sans effet tant que le serveur ne les envoie pas.

---

## 5. Les 14 Runes

Les Runes n'attaquent pas : elles changent les stats. Ce qu'elles montrent passe par les effets des armes, que le serveur envoie déjà à la bonne taille :

| Rune | Ce qui change à l'écran | Effet à faire |
| --- | --- | --- |
| Area | zones, ondes, explosions et pièces plus grandes | rien : suit le rayon |
| Projectiles | plus de flèches, dagues, lances, bombes, météores, haches | rien : suit le nombre |
| Duration | haches, tourelles et zones durent plus | rien : suit la durée |
| Attack Speed, Cooldown | tirs plus fréquents | rien |
| Crit | coups critiques | impossible aujourd'hui : les critiques ne sont pas envoyés (section 1, limite 5) |
| Damage, Luck, Wisdom, Magnet, Vitality, Armor, Agility, Cursed | rien sur les armes | rien |

Ce qui reste visible côté Runes : l'**éclair de fusion** (section 3) et les icônes des cartes (A08). Je ne prévois pas d'effet de prise de Rune, sauf si Clément en veut un.

---

## 6. Capacités de classe

| Classe | Arme de départ | Passif | Effet visible | Où |
| --- | --- | --- | --- | --- |
| Knight | Broadsword | Valor | parade toutes les 8 s | `Parry`, section 4 |
| Archer | Longbow | Eagle Eye | aucun (critique non envoyé) | — |
| Mage | Fire Staff | Arcane Surge | aucun : la zone grandit d'elle-même | — |
| Guardian | Quake Hammer | Bulwark | renvoi de dégâts ; atterrissage lourd | `Thorns`, section 4 ; l'onde d'atterrissage vient de `MovementController` (A06), hors armes |
| Rogue | Throwing Daggers | Shadowstep | glissade intouchable | `Shadowstep`, section 4 |
| Cleric | Holy Aura | Blessing | soin dans l'aura | `Blessing`, section 4 |
| Barbarian | Spinning Axes | Rage | aucun aujourd'hui | — |
| Tamer | Beast Whip | Pack Leader | compagnons | A05 |

**Arme tenue en main (validé par Clément le 5 nov.).** Aucun code n'attache aujourd'hui de modèle d'arme au personnage : les 8 MeshParts v1 ne servent à rien en jeu. La DA (§8) dit pourtant qu'« avant le niveau 10, l'arme de départ suffit à reconnaître la classe ». Le client accroche donc l'arme de départ de la classe (attribut `ClassId`, déjà posé sur le Player par `TraitService`) à la main droite de chaque joueur. Les armes du pool commun n'ont pas de place sur le corps : leur modèle sert aux pièces en jeu et aux icônes.

---

## 7. Attaques des ennemis et des boss (A14, décision de Clément du 5 nov.)

Aujourd'hui, tout est fabriqué par script : éclats de `EnemyAttackFX` (Parts Neon en pool), projectiles ennemis en boules (`EnemyRenderer`), télégraphes des boss (`BossRenderer`).

**Partage avec A03.** A14 fait les objets (`Assets.FX.Enemies.<Famille>.<Rôle>`, `Assets.FX.Bosses.<Boss>.<Attaque>`) et convertit `EnemyAttackFX`. Les projectiles ennemis et les télégraphes vivent dans `EnemyRenderer` et `BossRenderer`, les fichiers de A03 : je les convertis seulement avec l'accord du coordinateur, un agent à la fois sur ces fichiers (contract request, section 10).

**Rosters en transition.** `Config/Enemies` contient encore les ennemis v1 (glands, momies, craies…). Les décisions v2 veulent des gobelins, des zombies et des fantômes, et le monde 2 devient un cimetière. Les attaques ci-dessous sont celles du code actuel.

### 7.1 Familles

| Famille | Attaque | Visuel actuel |
| --- | --- | --- |
| Swarm (essaim) | contact | éclats `EnemyAttackFX` mode « contact » |
| Jumper (sauteur) | prépare 0,4 s (clignote), bondit 0,8 s, atterrit | éclats mode « land », anneau au sol |
| Shooter (tireur) | vise 0,6 s, tire un projectile lent (18-20 studs/s, rayon 1,2) toutes les 3,2 s | mode « aim » puis « shot » ; projectile en boule (`EnemyRenderer`) |
| Armored (blindé) | contact, pousse les autres | éclats mode « contact » |
| Élite | ×6 PV, ×1,3 taille | anneau et couronne or en Neon (`EnemyRenderer`, A03) |
| Mini-boss (Giant Stump, Piggy Camel, Spectral Proctor) | contact seulement ; Piggy Camel lâche des pièces | comme un ennemi |
| Capturable | anneau et cage Bubblegum | `FX_CaptureRing`, `FX_CaptureIcon` (A01) |

À venir avec les rosters v2 (rien dans le code) : bomber gobelin (explosion), shaman (soin ?), bloater zombie, gravedigger (lance de la terre), poltergeist (lance des objets), banshee (cri).

### 7.2 Boss

Avec `Bosses.PhaseEnabled = false`, seules les attaques de phase 1 servent. Les autres sont listées entre parenthèses.

| Boss | Attaques actives | Inactives (phases 2-3) | Point faible |
| --- | --- | --- | --- |
| The Grumpy Great Oak | Quake Roots (cercle sous un joueur, rayon 8) · Acorn Rain (5 cercles, rayon 5) · Bark Wave (anneau de 10 à 30, se saute) | Saplings (invocation) | Height (phase 2, inactif) |
| The Toaster Pharaoh (monde 2 v1) | Burning Toast (ligne 6 × 40) · Crumbs (éventail de 7 projectiles) | Red-Hot Grill, Mummify, Rush | Pillar (phase 3, inactif) |
| The Eternal Headmistress | Ruler Smack (cercle sous un joueur, rayon 9) · Paper Planes (éventail de 5) | Detention for All, Line Up! | Platform : la cloche sonne |
| The Great Hubbub | Thunder Crowd (3 cercles, rayon 10) · Spiral (12 projectiles à 360°) | Barrage, Wave, Reinforcements | Platform : le gong sonne |

Effets nécessaires par attaque de boss : télégraphe (zone et remplissage qui grandit, toujours en Tomato), impact (éclats en mode « boss »), projectiles d'éventail, et un objet propre à chaque attaque (racines, glands, tartines, avions en papier, règle…). Cela fait **8 attaques actives** et 9 inactives.

---

## 8. Récapitulatif à produire

Noms proposés : `Assets.Weapons.<Id>` pour le modèle tenu, `Assets.Weapons.<FusionId>` pour la fusion, `Assets.FX.Weapons.<Id>.<Rôle>` pour les pièces et effets (section 9).

| # | Arme | Modèle tenu | Pièces en jeu | Effets | Nb d'effets |
| --- | --- | --- | --- | --- | --- |
| 1 | Broadsword | à refaire | — | Swing, Impact | 2 |
| 2 | Longbow | à refaire | Arrow | Cast, Trail, Impact | 3 |
| 3 | Fire Staff | à refaire | (Fireball = effet) | Cast, Fireball, Explosion, Burn | 4 |
| 4 | Quake Hammer | à refaire | — | Slam, Shockwave, Stun | 3 |
| 5 | Throwing Daggers | à refaire | Dagger | Trail, Impact | 2 |
| 6 | Holy Aura | à refaire (clochette) | — | Aura, Pulse | 2 |
| 7 | Spinning Axes | à refaire | Axe | Spawn, Trail, Despawn | 3 |
| 8 | Beast Whip | à refaire | — | Lash, Crack | 2 |
| 9 | Lightning Chain | nouveau (porteur) | — | Bolt, Spark | 2 |
| 10 | Frost Nova | nouveau (porteur) | — | Nova, Frost | 2 |
| 11 | Boomerang | nouveau | Boomerang | Trail, Catch | 2 |
| 12 | Bomb Bag | nouveau (sac) | Bomb | Telegraph, Explosion | 2 |
| 13 | Spear Throw | nouveau | Spear | Trail, Stuck | 2 |
| 14 | Meteor Rain | nouveau (porteur) | Meteor | Telegraph, Fall, Impact, Burn | 4 |
| 15 | Orbiting Blades | nouveau | Blade | Trail, Spark | 2 |
| 16 | Crossbow Turret | nouveau | Turret, Bolt | Deploy, Trail, Impact, Despawn | 4 |
| | **Armes** | **16** | **10 pièces** | | **41** |
| | Fusions | 16 | variantes des pièces | éclair de fusion commun + effets recolorés ou remplacés | 1 + ≈ 16 |
| | Autres (section 4) | — | Ghost | Parry, Blessing, Ghost, Whistle, Megaphone, Thorns, Shadowstep, ChainBolt, MiniBomb, Telegraph | 10 |
| | Ennemis et boss (section 7) | — | objets d'attaque (projectiles, glands, avions en papier…) | 4 familles + 8 attaques de boss actives | 12 |

Le niveau 8 ne demande pas d'objet en plus : les accents Gold sont des pièces masquées dans le modèle ou l'effet, que le code rend visibles (le code a le droit de changer la visibilité, décisions v2 §12).

---

## 9. Conventions (DA des armes du 5 nov., 2e version)

Le 5 nov., Clément a changé la DA des armes et des effets (« oui a tous ») : « Les armes sont en pixel mais avec des détails, par contre les effets sont réalistes, pas en pixel. » Les armes ne sont ni en voxels ni à tenons. Le décor, les créatures et l'équipement de classe restent dans la DA de A01 (plastique à tenons). Règle : **« des blocs pour ce qui existe, de la lumière pour ce qui se passe »**. Planche concept : `assets/a14/09-armes-effets-concept.jpg`, scripts `assets/a14/concept.py` (Blender 5.2) et `assets/a14/board.py`.

**Armes et pièces en jeu** (`Assets.Weapons.<Id>`, flèche, dague, hache, bombe…) :
- un sprite en pixels à plat, sur une grille de 24 à 32 px, dessiné dans `concept.py` (classe `Sprite`) ;
- contour Ink de 1 px, volume dans les pixels (reflet clair en haut à gauche, ombre en bas à droite), détails peints à la main (reflets, gravures, gemme, gag) ;
- une couleur dominante par arme, un seul petit accent Neon (gemme, cristal, corde, mèche) ;
- épaissi de 2 à 6 px, la garde, la poignée et les objets ronds plus épais ;
- 1 px = 0,125 stud, soit 32 px = 4 studs ;
- une seule maille fusionnée par arme (maille gloutonne étanche de A01, couleur par sommet), plus une MeshPart Neon séparée ;
- 400 à 1 400 triangles mesurés sur les 6 modèles de la planche, plafond fixé à 1 500 ;
- pas de tenons ;
- à téléverser : pas d'EditableMesh, qui ne s'enregistre pas ;
- la prise est l'origine du modèle, l'arme pointe vers +Y, attribut `GripOffset` (convention A01) ;
- au niveau 8, des accents Gold, posés dans un sous-dossier `Max` masqué par défaut ;
- le même sprite sert d'icône : `assets/a14/sprites/<Arme>.png` (natif) et `<Arme>@8x.png`, à livrer à A08.

**Effets** (`Assets.FX.Weapons.<Id>.<Rôle>`) : de la lumière seulement, jamais de cubes ni de pixels.
- **Particules douces** : ParticleEmitter à textures rondes et floues (halo, flamme, fumée, étincelle étirée), posés éteints (`Enabled = false`) ; le code appelle `:Emit(n)`.
- **Traînées et éclairs** : Beam et Trail avec dégradé de transparence, posés avec leurs Attachments.
- **Anneaux et zones au sol** : plans ou anneaux Neon fins avec bloom (onde de choc, alerte, aura).
- **Couleur des lumières** : un cœur blanc très lumineux, puis la couleur de l'arme en halo à intensité modérée, sinon l'orange vire au jaune et le jaune au blanc.

**Budget mobile**, pour tenir avec 300 ennemis :
- au plus 1 ParticleEmitter allumé en continu par arme ;
- rafales de 12 particules au plus ;
- lumières en qualité Haute seulement, 4 à la fois au plus ;
- sans particules au-delà de 80 studs de la caméra (comme `EnemyRenderer`, 82 studs) ;
- en qualité Basse : les pièces et les ondes seulement, sans particules ni traînées.

**Couleurs**, d'après la DA §4 et §6 :
- les effets du joueur brillent (Neon), ceux des ennemis restent Tomato sans Neon ;
- Bubblegum est réservé à la capture : `MiniBomb` (rose aujourd'hui) change de couleur ;
- **télégraphes** (validé par Clément le 5 nov.) : le cercle de la bombe et du météore du joueur passe du rouge à Ember ou Gold, en pointillé. Le rouge reste au danger des ennemis ;
- Meteor Rain passe de son rouge-Tomato à Ember ;
- **code au sol proposé sur la planche** : anneau Gold en pointillé qui se remplit = alerte du joueur ; onde orange pleine avec flash blanc = coup du joueur ; rouge Tomato mat, sans lumière = ennemis.

**Couleurs dominantes de la planche** : Broadsword bleu roi, Longbow vert feuille, Fire Staff braise, Bomb Bag raisin (bombe à bande raisin, pour la distinguer de la bombe noire du gobelin Bomber).

**Une couleur par arme** (validé par Clément le 5 nov.). La DA §6 disait « tirs du joueur aux couleurs de la classe ». Mais les 16 armes sont équipables par toutes les classes : chaque arme a donc sa couleur (feu Ember, givre et éclair Sky, sacré Gold…), plus lisible quand on porte 4 armes. Contract request à A01 pour mettre la DA §6 à jour.

---

## 10. Contract requests

Je ne touche pas aux fichiers de ces agents. Chaque demande est petite et sans risque pour le jeu (les évènements sont cosmétiques).

| Pour | Demande | Pourquoi |
| --- | --- | --- |
| A04 (`WeaponService`) | Mettre le FxSlot du tireur dans le champ `a` des évènements Zone (aujourd'hui 0) | la bombe part de la main du joueur ; effets de fusion et de palier par joueur |
| A04 | Donner au client le niveau de chaque arme de chaque joueur, par exemple un attribut Player `WeaponLevels` (« index:niveau » séparés par des virgules), mis à jour à chaque carte | palier visuel du niveau 8, fusion (niveau 9) |
| A04 (A04-09) | Clément a validé les 16 fusions de la section 3 (noms et paires) : écrire leurs règles et chiffres, puis `FusionEnabled = true` | modèles et effets de fusion |
| A03 | Convertir en objets A14 les projectiles ennemis (`EnemyRenderer`) et les télégraphes des boss (`BossRenderer`) : soit A14 le fait avec l'accord du coordinateur, soit A03 branche les objets que A14 pose | Clément a confié les effets des ennemis et des boss à A14 |
| A01 | DA §6 : « une couleur par arme » au lieu de « aux couleurs de la classe » ; télégraphes du joueur en Ember ou Gold | décision de Clément du 5 nov. |
| A04 (option) | Envoyer les coups critiques (un bit dans un évènement existant) | effet de critique pour l'Archer et la Crit Rune |
| A03 (option) | Distinguer gel et étourdissement (aujourd'hui un seul bit « arrêté », teinte givre) | le Quake Hammer et le Megaphone étourdissent, ils ne gèlent pas |
| A08 | Icônes d'armes : utiliser les sprites de A14 (`assets/a14/sprites/<Arme>.png`, 32 px, et `@8x`, fond transparent, filtrage au plus proche), téléversés par A14 à la porte 3 ; 4 armes livrées avec la planche, les autres suivent | Clément : « le même sprite sert d'icône » |
| A06 | Aucune ; l'arme tenue s'accroche à `RightGripAttachment` sans toucher à l'animation | — |

Ce que je corrige moi-même dans `WeaponFX` (client, mon domaine, étape 4) : le style des carreaux de la tourelle, la couleur de `MiniBomb`, les télégraphes, et le clonage des objets au lieu des Parts fabriquées par script.

---

## 11. Porte 1 : décisions de Clément (5 nov. 2026)

| Question | Réponse |
| --- | --- |
| Liste des 16 armes, attaques et effets (sections 2 et 8) | Validée |
| Effets des attaques des ennemis et des boss (section 7) | A14 les fait |
| Fusions | Oui, la liste de la section 3 |
| Arme de départ tenue en main | Oui |
| Couleurs | Une couleur par arme ; télégraphes du joueur en Ember ou Gold, le rouge reste aux ennemis |

## 12. Porte 2 : planche concept (5 nov. 2026)

Planche : `assets/a14/09-armes-effets-concept.jpg`, dans la DA du 5 nov. (2e version, section 9). Elle montre :
- 4 armes : Broadsword, Longbow, Fire Staff, Bomb Bag ;
- 2 pièces : la bombe et la flèche ;
- leurs icônes ;
- 3 effets en vue rapprochée et en vue de jeu : coup de taille, boule de feu et explosion, alerte puis explosion de la bombe ;
- le code couleur au sol, testé sur l'herbe et sur le sable ;
- une séquence en 4 temps ;
- un test avec 70 gobelins et 5 effets à la fois.

Une première version « tout en tenons » a été abandonnée après le changement de DA. Ses relectures à l'aveugle ont laissé des règles qu'on garde : un sens par couleur et par forme au sol, des effets plus grands que nécessaire sur téléphone, le danger ennemi testé dans la horde.

En attente : validation de Clément (porte 2).
