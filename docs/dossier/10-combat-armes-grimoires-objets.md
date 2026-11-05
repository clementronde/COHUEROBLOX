# 10 — Combat : armes, Runes, objets, cartes, passifs

Domaine **combat**. Source : `01-decisions-v2.md` sections 3 et 4 (prioritaire), puis `00-vision.md` §5.2, §8.1–8.3, §12.3. Contrat : `docs/ARCHITECTURE.md`.

**v2 (A04, 4 nov. 2026)** : les « grimoires » s'appellent **Runes** pour le joueur ; le module garde son nom interne `Config/Grimoires` et les champs `grimoires` du Build pour ne pas casser les autres domaines. Les 10 classes v1 sont remplacées par les **8 classes classiques** (section 8), les 16 armes par les armes v2 (section 5). Tout texte joueur est en **anglais** (le champ `fr` des tables porte aussi l'anglais) ; les noms français ci-dessous servent au dossier.
Tous les nombres ci-dessous vivent dans `shared/Config/{Weapons,Grimoires,Items,Cards,Rarities}.luau` : ce document décrit, la config fait foi en cas d'écart.

Fichiers : `server/Services/{StatsService,CardService,WeaponService,PassiveService}.luau`, `shared/WeaponFxCodec.luau`, `client/Controllers/WeaponFX.luau`, configs `shared/Config/{Weapons,Grimoires,Items,Cards,Rarities}.luau` (les nombres des passifs de classe sont dans `Weapons.Passives`).

---

## 1. Statistiques du joueur (StatBlock)

Sémantique (Types.StatName) : stats « pourcent » = bonus additifs, multiplicateur effectif = `1 + valeur`. Stats « plates » = nombres bruts.

| Stat | Base | Plafond | Lu par |
| --- | --- | --- | --- |
| Damage | 0 | — | WeaponService |
| AttackSpeed | 0 | 3 | WeaponService (cadence) |
| Amount | 0 | 10 | WeaponService (+ projectiles / instances) |
| Size | 0 | 3 | WeaponService (zones, rayons) |
| Duration | 0 | 3 | WeaponService (durées) |
| Cooldown | 0 | **0,6** (−60 % max) | WeaponService |
| CritChance | 0,05 | 1 | WeaponService |
| CritDamage | 0 | — | crit = ×(2 + CritDamage) |
| Luck | 0 | 100 (effet rareté) | CardService, LootService |
| XpGain | 0 | — | LootService (avant addXp) |
| Magnet | 0 | — | LootService (studs ajoutés au rayon) |
| MaxHp | 140 (A04-12) | — | RunManager |
| Armor | 0 | — | RunManager (courbe conseillée `Armor/(Armor+50)`) |
| Regen | 0,5 (A04-12) | — | RunManager (PV/s) |
| MoveSpeed | 0 | 1 | domaine avatar |
| Dodge | 0 | 0,6 | RunManager |
| Thorns | 0 | 1 | PassiveService (renvoi des coups de mêlée) |
| Bounces | 0 | 10 | WeaponService (Lightning Chain) |
| Difficulty | 0 | — | RunManager (moyenne de l'équipe → PV et densité de la horde) |
| LootBonus | 0 | — | domaine loot |

Ordre de calcul de `StatsService.get` : base → + Runes → + objets (× nombre) → + passif de classe (plat + par niveau) → + boosts `addStat` (autels, permanents pour la run) → + boosts temporaires (objets) → multiplicateurs d'objets (ex. Pile usée PV ×0,9) → plafonds. Valeur mise en cache, recalculée seulement si quelque chose change.

## 2. Formule de dégâts (une fonction pure, serveur)

Ordre canonique tiré de la note vault *Damage Formula Pipeline* :

```
coup = base(arme, niveau)
     × (1 + Damage + bonus_rareté_arme + bonus_contexte)      -- un seul seau additif
     × facteurs « more » (fusion, Quake Hammer : +1 %/Armure)
     × crit ? (2 + CritDamage) : 1                              -- crit tiré côté serveur
     × objet Ciseaux (8 %/pile : ×2)
-> arrondi une seule fois, minimum 1
```

- `bonus_contexte` : Valor du Knight (+1 %/ennemi à ≤ 10 studs, max +30 %), Rage du Barbarian (jusqu'à +50 %), Petite voiture (en mouvement), Oreiller (immobile), Lunettes de chasseur (élites/boss, si `EnemyService.isElite` existe).
- Chance de crit = `CritChance + critChance de l'arme` (+ 25 % au-delà de 20 studs pour l'Archer), plafonnée à 1 avant le bonus de distance. Le crit est tiré par coup, jamais par le client.
- **Armure ennemie : N/A.** Les ennemis n'ont pas d'armure au lancement ; la seule mitigation est côté joueur (RunManager).
- Les dégâts sur la durée (Brûlure, Poison) sont appliqués par EnemyService via `applyStatus` ; leurs paramètres `dps` sont déjà multipliés par `(1 + Damage)` au moment de l'application.

Paramètres envoyés à `EnemyService.applyStatus` (le domaine run les interprète) :
`Burn`/`Poison` : `{ dps, duration, source: Player, maxStacks }` · `Slow` : `{ mult, duration }` · `Freeze`/`Stun` : `{ duration }` · `Knockback` : `{ fromX, fromZ, force }`.

## 3. XP et niveaux

- XP pour passer du niveau L à L+1 : `floor(6 + 4·L + 0,6·L²)` (A04-12, était 0,35) → L1 : 10, L5 : 41, L10 : 106, L20 : 326, L30 : 666. Cumul jusqu'au niveau 30 ≈ 7 000 XP (≈ une run réussie, le trait grandit à 10/20/30).
- Niveau max 99. `addXp(player, n)` prend `n` tel quel : **LootService** applique déjà `× (1 + XpGain)` et le **partage coop** (§5.2 : 50 % aux coéquipiers actifs à ≤ 40 studs) avant d'appeler `addXp` pour chacun. Les autres sources (fusion Prisme du Savant) appellent `addXp` directement.
- Plusieurs niveaux d'un coup : chaque niveau tire `Bus.PlayerLeveledUp` ; CardService les met en file.

## 4. Cartes de niveau (§5.2, §8)

- **3 cartes**, **8 s**, sans pause : `RunManager.setInvulnerable(player, 8)` + `setSlow(player, 0.5, 8)`. À l'expiration : choix auto de la carte **la plus rare** (égalité : la première).
- File : si plusieurs niveaux sont gagnés, les offres s'enchaînent (nouvelle fenêtre de 8 s chacune). Pas d'offre tant que le joueur est à terre ; elle s'ouvre quand il est relevé.
- **Pool** (poids de tirage) : amélioration d'arme possédée 1,2 · nouvelle arme 1,0 · amélioration de Rune 1,0 · nouvelle Rune 0,9 · **fusion disponible 3,0**. Tirage pondéré sans remise, ids distincts.
- **Compagnon** : chaque emplacement de carte a 25 % de chance d'être tiré dans `CompanionService.getCardOptions` (≈ 1 carte sur 4). Appliqué via `CompanionService.applyCard`.
- **Emplacements pleins** : plus de « nouvelle arme » quand les emplacements d'armes sont pleins, idem Runes. Une arme niveau 8 sans fusion possible, une arme fusionnée, une Rune au max sortent du pool. Les ids **bannis** sortent du pool pour la run.
- **Pool vide** : cartes de secours *Goûter* (soin 30 % PV max) et *Tirelire* (+20 pièces × (1 + LootBonus)).
- **Déblocage** : v2, toutes les armes et Runes sont dans le tirage (`unlock` absent ou `"Free"`). Une arme ou Rune verrouillée (`unlock` ≠ `"Free"`, `unlockGated`) demanderait `ProgressionService.isUnlocked`. Les règles du domaine data portent encore les ids v1 : contract request A04.
- **Bannir** (sur une carte arme / Rune) : l'id sort du pool, la carte est remplacée. **Passer** : ferme l'offre sans rien prendre. **Relancer** : 3 nouvelles cartes. Chaque action change l'`offerId` ; le temps restant continue. Charges : `ProgressionService.getMetaBonuses` (repli 3/3/3).
- **Validation `CardChoice`** (C→S, 5/s) : `offerId` entier égal à l'offre ouverte, `action ∈ {pick, ban, skip, reroll}`, `index` entier 1..#cartes pour pick/ban, charge disponible. Tout le reste est ignoré sans log.

### 4.1 Raretés

| Rareté | Couleur | Poids de base | Facteur Chance (par point) |
| --- | --- | --- | --- |
| Common | gris | 60 | 0 |
| Rare | bleu | 26 | +2 % |
| Epic | violet | 10 | +3,5 % |
| Legendary | or | 4 | +5 % |

Poids effectif = `poids × (1 + min(Luck,100) × facteur)`, puis normalisation (implémentation « table pondérée » de la note vault *Genre Playbook - RNG and Collection Games*). Exemples : Luck 0 → 60/26/10/4 % ; Luck 20 → 49/30/14/6,6 % ; Luck 100 → 29/38/22/12 %.

Effet de la rareté d'une carte :

| | Common | Rare | Epic | Legendary |
| --- | --- | --- | --- | --- |
| Niveaux d'arme gagnés | 1 | 1 | 2 | 2 |
| Bonus de dégâts de l'arme (cumulatif) | 0 | +10 % | +10 % | +25 % |
| Niveaux de Rune gagnés | 1 | 2 | 3 | 4 |

La carte de fusion est toujours Legendary (fusions désactivées en vague 1 : `Weapons.FusionEnabled = false`, A04-09 attend Clément). Mage : toutes les 5 offres, au moins une carte est Rare ou mieux.

Textes des cartes (anglais, `Cards.Locale = "en"`) : `New weapon: Longbow`, `Longbow Lv 3` + deltas (`+2 pierce`, `+15% area`, mots dans `Cards.WeaponStatWords`), `New Rune: Damage Rune`, `Damage Rune Lv 2` + `+8% damage`.

### 4.2 Emplacements

4 armes / 4 Runes (méta : `getMetaBonuses`, plafond 6).

## 5. Les 16 armes (v2, A04-05 et A04-07)

Toutes tirent seules côté serveur à 15 Hz (`Balance.SimHz`). Projectiles = données (aucune Part serveur), collisions via `EnemyService.queryRadius`. Cadence finale = `cooldown × (1 − Cooldown) / (1 + AttackSpeed)`, minimum 0,15 s. Rayon / portée × `(1 + Size)`, durées × `(1 + Duration)`, quantité + `Amount`. Toutes équipables par toutes les classes. Les numéros sont l'index réseau de `WeaponFx` (1..16).

| # | Id | EN / FR | Comportement (`kind`) | Base niv. 1 | Brille avec |
| --- | --- | --- | --- | --- | --- |
| 1 | `Broadsword` | Broadsword / Épée large | Cône 140° devant soi (vers l'ennemi le plus proche), rayon 8, recul 4 ; un coup sur deux part derrière (`swingBack`) | 16 dég, cd 1,1 s | Taille, Dégâts |
| 2 | `Longbow` | Longbow / Arc long | Flèches auto vers l'ennemi le plus proche (portée 55), perce 3 | 12 dég, cd 1,0, 80 studs/s | Quantité, Vit. d'attaque |
| 3 | `FireStaff` | Fire Staff / Bâton de feu | Boule de feu qui explose au premier ennemi (rayon 5 × Taille) ou en fin de course, + brûlure 4 dps 2 s | 13 dég, cd 1,0 (A04-12), 42 studs/s | Taille, Dégâts |
| 4 | `QuakeHammer` | Quake Hammer / Marteau séisme | Onde circulaire rayon 9, recul 8, +1 % dégâts par point d'armure ; étourdit 0,3 s au niv. 8 | 22 dég, cd 2,4 | Taille, Armure |
| 5 | `ThrowingDaggers` | Throwing Daggers / Dagues de lancer | Éventail de 3 dagues (14°), perce 1 | 7 dég, cd 0,9 | Quantité, Vit. d'attaque |
| 6 | `HolyAura` | Holy Aura / Aura sacrée | Anneau permanent rayon 6 autour du joueur, tic toutes les 0,5 s ; soigne les alliés si porté par un Cleric | 5 dég/tic | Taille, Dégâts |
| 7 | `SpinningAxes` | Spinning Axes / Haches tournoyantes | 2 grosses haches en orbite (rayon 6) pendant 3,5 s, recul 5 | 10 dég, cd 5 | Quantité, Durée |
| 8 | `BeastWhip` | Beast Whip / Fouet de dompteur | Balayage 360° rayon 8,5, recul 6 | 15 dég, cd 1,7 | Taille |
| 9 | `LightningChain` | Lightning Chain / Chaîne d'éclairs | Frappe l'ennemi le plus proche (≤ 30) puis rebondit 2 fois (≤ 12 studs) | 11 dég, cd 1,3 | Rebonds, Critique |
| 10 | `FrostNova` | Frost Nova / Nova de givre | Onde rayon 10 qui ralentit de 50 % 1 s ; gel 0,4 puis 0,8 s aux niv. 4 et 8 | 10 dég, cd 3,0 | Taille, Durée |
| 11 | `Boomerang` | Boomerang / Boomerang | Part 0,55 s vers l'ennemi le plus proche, revient, transperce tout | 13 dég, cd 1,5 | Taille, Quantité |
| 12 | `BombBag` | Bomb Bag / Sac de bombes | Bombe sur un ennemi à ≤ 25, explose après 0,8 s (cercle rouge au sol), rayon 6 | 24 dég, cd 2,6 | Taille, Quantité |
| 13 | `SpearThrow` | Spear Throw / Lancer de lance | Lance rapide qui traverse tout (perce infini), portée 50 | 20 dég, cd 1,8, 75 studs/s | Dégâts, Quantité |
| 14 | `MeteorRain` | Meteor Rain / Pluie de météores | 2 météores sur des ennemis au hasard (≤ 35), 0,9 s de télégraphe, rayon 7, brûlure ; +1 % de météore en plus par point de Chance | 40 dég, cd 3,2 | Chance, Taille |
| 15 | `OrbitingBlades` | Orbiting Blades / Lames en orbite | 3 petites lames permanentes en orbite serrée (rayon 3,5) | 6 dég, toutes les 0,35 s par ennemi | Quantité, Vit. d'attaque |
| 16 | `CrossbowTurret` | Crossbow Turret / Tourelle arbalète | Pose une arbalète fixe 8 s qui tire toutes les 0,8 s (portée 38, perce 2) | 8 dég/carreau, cd 6 | Durée, Quantité |

Les niveaux 2 → 8 de chaque arme sont dans `Config/Weapons` (`levels`), 7 deltas par arme : environ deux paliers de dégâts, un de zone ou de portée, un de quantité, un de recharge, un spécifique (perce, rebonds, gel…).

**Visuels provisoires** (vague 1) : chaque arme décrit son style dans `Weapons.Defs[id].fx` (forme, couleur, taille, rotation, orbite, aura au sol). `WeaponFX` ne contient plus aucun index d'arme en dur : la vague 2 (A07) remplace les pièces sans toucher au serveur. Lisibilité : flèches et lances longues et claires, boule de feu orange pleine, haches marron en orbite, aura dorée au sol, ondes au sol de la couleur de l'arme, télégraphes rouges des bombes et météores toujours dessinés.

**Moteur** (`WeaponService`) : aucun id d'arme ni de classe n'y est écrit. Comportements par `kind` (Shot, Boomerang, Cone, Nova, Cloud, Turret, Strike, Chain, Orbit, Beam, Shield) et drapeaux de stats (`popRadius`, `endBlast`, `permanent`, `swingBack`…). Les kinds Beam et Shield n'ont plus d'arme en v2 mais restent disponibles.

### 5.2 Fusions (A04-09, en attente)

Proposition des décisions v2 : une arme au niveau 8 + une Rune précise au niveau 5 → version ultime (exemple : Longbow + Attack Speed Rune → Storm Bow). Le moteur existe (niveau 9 = base + niveaux + `fusion.delta`, carte Legendary) ; `Weapons.FusionEnabled = false` et aucune arme v2 n'a encore de `fusion` tant que Clément n'a pas confirmé.

## 6. Les 14 Runes (max niveau 8, Cursed 5) (A04-06)

Valeurs **par niveau** (cumul linéaire), sauf Projectiles. Id = nom anglais ; nom affiché « X Rune ».

| Id | EN / FR | Par niveau | Au max |
| --- | --- | --- | --- |
| `Damage` | Damage Rune / Rune de dégâts | +8 % Damage | +64 % |
| `AttackSpeed` | Attack Speed Rune / Rune de vitesse d'attaque | +7 % AttackSpeed | +56 % |
| `Projectiles` | Projectile Rune / Rune de projectiles | Amount 1,1,2,2,3,3,4,4 ; niveaux pairs +4 % Damage | +4 projectiles, +16 % |
| `Area` | Area Rune / Rune de zone | +8 % Size | +64 % |
| `Duration` | Duration Rune / Rune de durée | +10 % Duration | +80 % |
| `Cooldown` | Cooldown Rune / Rune de recharge | +4 % Cooldown | −32 % |
| `Crit` | Crit Rune / Rune critique | +4 % CritChance, +10 % CritDamage | +32 %, +80 % |
| `Luck` | Luck Rune / Rune de chance | +3 Luck | +24 |
| `Wisdom` | Wisdom Rune / Rune de sagesse | +10 % XpGain | +80 % |
| `Magnet` | Magnet Rune / Rune aimant | +3 Magnet | +24 studs |
| `Vitality` | Vitality Rune / Rune de vitalité | +15 MaxHp, +0,2 Regen (A04-12) | +120 PV, +1,6/s |
| `Armor` | Armor Rune / Rune d'armure | +3 Armor | +24 |
| `Agility` | Agility Rune / Rune d'agilité | +4 % MoveSpeed, +2 % Dodge | +32 %, +16 % |
| `Cursed` | Cursed Rune / Rune maudite | +10 % Difficulty, +12 % LootBonus, +5 % XpGain, +5 % Damage | ×5 |

**Difficulty** (Rune Cursed, tirelire gourmande des autels) agit enfin sur la horde : RunManager prend la moyenne des joueurs de la run, PV ennemis ×(1 + moyenne), densité ×(1 + 0,5 × moyenne) (`Run.DifficultyDensityShare`).

## 7. Les 40 objets (coffres, `grantItem`)

Tous se cumulent (nombre de piles). Le domaine loot choisit l'objet ; il peut tirer la rareté avec `Rarities` (mêmes poids et même effet de la Chance que les cartes).

| Id | FR / EN | Rareté | Effet (par pile) |
| --- | --- | --- | --- |
| MagicShoelace | Lacet magique / Magic Shoelace | Common | +8 % XP |
| LuckySock | Chaussette porte-bonheur / Lucky Sock | Common | +3 Chance |
| StickyEraser | Gomme collante / Sticky Eraser | Common | 10 % des coups ralentissent de 40 % pendant 1,5 s (max 50 %) |
| ReinforcedPencilCase | Trousse renforcée / Sturdy Pencil Case | Rare | annule jusqu'à 15 dégâts d'un coup toutes les 10 s (+10 par pile) |
| RecessWhistle | Sifflet de récré / Recess Whistle | Rare | toutes les 20 s (−2 s par pile, min 10), repousse les ennemis à 14 studs |
| Wrench | Clé à molette / Wrench | Rare | autels +5 % vitesse, +8 % récompense (lu par ShrineService via `getBuild`) |
| BlankieGhost | Fantôme de doudou / Blankie Ghost | Legendary | tous les 50 studs parcourus, un mini-fantôme fonce sur l'ennemi le plus proche (25 dég., +1 fantôme par pile) |
| FridgeMagnet | Aimant de frigo / Fridge Magnet | Epic | toutes les 45 s (−5 s par pile, min 25), Aimant +400 pendant 1,5 s (aspire toute l'XP) |
| OldBattery | Pile usée / Old Battery | Rare | PV max ×0,9, +15 % dégâts |
| HunterGlasses | Lunettes de chasseur / Hunter Glasses | Rare | +15 % dégâts contre élites et boss |
| ChalkStick | Craie magique / Magic Chalk | Common | +5 % dégâts |
| Ruler | Règle graduée / Long Ruler | Common | +6 % Taille |
| GymStopwatch | Chronomètre de gym / Gym Stopwatch | Common | +6 % Vitesse d'attaque |
| GlueStick | Bâton de colle / Glue Stick | Common | +8 % Durée |
| VelcroSneakers | Baskets à scratch / Velcro Sneakers | Common | +6 % vitesse de déplacement |
| LunchBox | Boîte à goûter / Lunch Box | Common | +15 PV max |
| DinoBandage | Pansement dino / Dino Bandage | Common | +0,4 PV/s |
| ComicBook | BD cornée / Dog-eared Comic | Common | +4 % crit |
| BentPaperclip | Trombone tordu / Bent Paperclip | Common | +1 rebond |
| HomeworkFolder | Classeur de devoirs / Homework Folder | Common | +2 Armure |
| SandTimer | Sablier de brosse à dents / Toothbrush Timer | Common | +4 % Recharge |
| StickyNote | Pense-bête / Sticky Note | Common | +4 Aimant |
| StarSticker | Autocollant étoile / Star Sticker | Common | +3 % dégâts, +3 % XP |
| GeometryCompass | Compas pointu / Pointy Compass | Rare | +3 % crit, +15 % dégâts critiques |
| BubbleWrap | Papier bulle / Bubble Wrap | Rare | +4 % esquive |
| FluffySlippers | Chaussons moelleux / Fluffy Slippers | Rare | +8 % vitesse, +2 % esquive |
| HotChocolate | Chocolat chaud / Hot Chocolate | Rare | soigne 20 PV à chaque niveau |
| LuckyCoin | Pièce porte-bonheur / Lucky Coin | Rare | 3 % des ennemis tués lâchent 1 pièce en plus |
| Thumbtack | Punaise / Thumbtack | Rare | +10 % Épines (dégâts reçus renvoyés) |
| SolarCalculator | Calculatrice solaire / Solar Calculator | Rare | +12 % XP, +2 Chance |
| WaterBottle | Gourde / Water Bottle | Rare | +1 PV/s |
| RoundScissors | Ciseaux à bouts ronds / Safety Scissors | Rare | 8 % des coups font ×2 (indépendant du crit) |
| TinyCar | Petite voiture / Tiny Car | Rare | +10 % dégâts en mouvement |
| CozyPillow | Oreiller douillet / Cozy Pillow | Rare | +20 % dégâts à l'arrêt |
| ColoringPencils | Crayons de couleur / Coloring Pencils | Epic | +1 Quantité |
| Megaphone | Mégaphone / Megaphone | Epic | toutes les 12 s (−1 s par pile, min 6), étourdit 1 s les ennemis à 10 studs |
| Flashlight | Lampe de poche / Flashlight | Epic | les crits étourdissent 0,4 s |
| RainbowLollipop | Sucette arc-en-ciel / Rainbow Lollipop | Epic | chaque ennemi tué soigne 1 PV (max 5 PV/s par pile) |
| ChampionBackpack | Cartable de champion / Champion Backpack | Legendary | +15 % Taille, +15 % Durée, +10 % dégâts |
| GoldStar | Bon point doré / Gold Star | Legendary | +1 Quantité, +10 % dégâts |

Répartition : 16 Common, 16 Rare, 5 Epic, 3 Legendary.

## 8. Les 8 classes et leurs passifs (A04-04, A04-10)

Décisions v2 section 3. L'avatar Roblox reste intact ; la classe ajoute un **équipement voxel** (TraitService, pièces provisoires en blocs en attendant les Accessories de A01) qui grandit aux niveaux 10, 20 et 30. Les stats viennent de la classe, jamais de l'apparence. Classes jamais vendues.

| Id | EN / FR | Arme de départ | Passif (id = classe) | Règle exacte (`Weapons.Passives`) | Mouvement (`Config/Classes`, lu par A06) | Déblocage |
| --- | --- | --- | --- | --- | --- | --- |
| `Knight` | Knight / Chevalier | Broadsword | Valor | +1 % dégâts par ennemi à ≤ 10 studs (max +30 %, seau additif, compté à 15 Hz) ; pare un coup toutes les 15 s (A04-12, était 8 ; `PassiveService.tryBlock`, avant esquive et armure) | normal | Gratuit |
| `Archer` | Archer / Archère | Longbow | Eagle Eye | +25 % de chance de critique sur les ennemis à ≥ 20 studs du joueur | saut haut (`jumpHeight` 10) | Gratuit |
| `Mage` | Mage / Mage | Fire Staff | Arcane Surge | +2 % Taille par niveau ; toutes les 5 offres, au moins une carte Rare ou mieux | plané court (`glide`, `glideSeconds` 1,2) | Gratuit |
| `Guardian` | Guardian / Gardien | Quake Hammer | Bulwark | +3 armure par niveau ; renvoie 30 % des dégâts de **mêlée** aux 3 ennemis les plus proches (≤ 6 studs) ; immunisé au recul (`knockbackImmune`) | lent (14), atterrissage lourd (`heavyLanding`) | Quête |
| `Rogue` | Rogue / Voleuse | Throwing Daggers | Shadowstep | Le début d'une glissade validée par MovementGuard (attribut `Sliding`) donne 0,5 s d'invulnérabilité (une fois toutes les 2 s) ; +10 % esquive | double saut (`airJumps` 1), 17 de vitesse | Quête |
| `Cleric` | Cleric / Clerc | Holy Aura | Blessing | L'aura (Holy Aura) soigne de 1,5 PV par tic les joueurs actifs dedans, le Cleric compris ; relève 2× plus vite | normal | Quête |
| `Barbarian` | Barbarian / Barbare | Spinning Axes | Rage | +50 % × (1 − PV / PV max) de dégâts (0 % à PV pleins, +50 % à 0) | charge en glissade (`slideBoost` 1,6) | Quête |
| `Tamer` | Tamer / Dompteuse | Beast Whip | Pack Leader | 2 compagnons, capture 50 % plus rapide, compagnons +20 % dégâts : données pour le domaine compagnons (vague 2), sans effet en vague 1 | normal | Quête |

Équipement provisoire (paliers 1 → 4) : Knight casque ouvert, cape rouge au niveau 10, crête dorée, armure dorée ; Archer capuche et carquois, plume, carquois plein, flèches dorées ; Mage chapeau pointu en blocs, étoile, rune flottante, chapeau lumineux ; Guardian épaulières de pierre, rivets, bords en fusion ; Rogue masque, capuche, nœud, fumée ; Cleric auréole carrée, plus brillante, double ; Barbarian casque à cornes, cornes plus longues, fourrure, cornes en flammes ; Tamer chapeau de dompteuse, badge patte, plume, bande dorée.

**Transition des ids** : le domaine data (`Config/Progression`) et l'UI (`Config/UI`) envoient encore les ids v1. `Config/Classes` résout en lecture `Cornu → Knight`, `Plumeline → Archer`, `Mecano → Mage`, `Rocailleux → Guardian`, `Felyne → Rogue`, `Sporelin → Cleric`, `Ecaille → Barbarian`, `Tentaculos → Tamer` (métatable, l'itération ne voit que les 8 classes v2). Le code utilise toujours `def.id`. À retirer quand le contrat v2 est fusionné.

Épines : la stat Thorns de tous les joueurs ne répond qu'aux coups de mêlée (`Bus.PlayerDamaged` source `"Contact"`).

## 9. Coop (§5.2)

- XP individuelle, partage 50 % à 40 studs (fait par LootService, section 3). Build, cartes et niveaux individuels.
- Aucune pause : invulnérable + ralenti 50 % pendant le choix.
- Les armes de chaque joueur touchent tous les ennemis ; les dégâts sont crédités au tireur (`EnemyService.damage(id, n, player)`) pour le kill et les stats de fin.
- Rien n'est tiré quand `RunManager.isActive(player)` est faux (à terre, fantôme, hors run).
- `StatsService.getDamageByWeapon(player)` alimente `RunSummary.damageByWeapon` (les objets/passifs offensifs y figurent sous leur id).

## 10. Réseau et budgets mobile

- **WeaponFx** (UnreliableRemoteEvent) : `WeaponFxCodec`, en-tête 6 octets (version u8, tick u32, nombre u8), enregistrement fixe 14 octets, ≤ 900 octets par paquet (63 évènements). Les évènements sont cosmétiques : en perdre un ne change rien au jeu (note vault *RemoteEvents RemoteFunctions and Unreliable Remotes*).
- Types d'évènement : Projectile (le client le simule), Fin de projectile, Zone (onde, cône, explosion avec délai), Segment (éclair, rebond), Attaché (haches et lames en orbite, aura qui suivent un joueur, identifié par l'attribut `FxSlot` du Player ; tourelles fixes avec le bit 128 du champ nombre). Visuels spéciaux : `Parry`, `Shadowstep`, `Thorns`, `Ghost`, `Whistle`, `Megaphone`, `ChainBolt`, `MiniBomb`.
- Les textes des cartes (`Card.title`/`desc`) sont des chaînes simples (type du contrat) : anglais (`Cards.Locale = "en"`).
- Intérêt : chaque joueur reçoit les évènements à ≤ 160 studs ; max 126 évènements par joueur et par tick (2 paquets), le surplus est jeté.
- **Serveur** : ≤ 400 projectiles vivants, ≤ 96 zones ; enregistrements réutilisés (pool), aucune table créée par ennemi dans les boucles, cibles par grille (`queryRadius`).
- **Client** : pools de Parts par style, un `BulkMoveTo` par image, qualité auto : téléphone → *Bas* (60 projectiles, 12 zones, 16 segments, SmoothPlastic, sans fondu), tablette/PC moyen → *Moyen* (150/28/40), PC → *Haut* (300/56/80, Neon). Les zones de gameplay lisibles (télégraphes de météore) ne sont jamais coupées, seulement simplifiées.
- **PlayerProgress** et **Build** (fiables) : regroupés et envoyés au plus 5 fois/s.

## 11. Sources vault

- Damage Formula Pipeline - Armor, Resistances, Crits and Order of Operations
- Probability and Statistics for Designers
- Genre Playbook - RNG and Collection Games (Luck)
- Projectiles and Ballistics
- Luau Performance and Native Codegen
- Luau Performance Patterns with Benchmarks
- Luau Garbage Collection and the Memory Model
- Buffers and Binary Data
- RemoteEvents RemoteFunctions and Unreliable Remotes
- RemoteEvent - Engine Reference Card
- Remote Abuse Patterns and Rate Limiting in Practice
- AI Pitfalls - Networking and Security
- Replicating VFX - Server Validates, Clients Render
- VFX Performance Budgets and Culling
- Mobile and Low-End Optimization
- Status Effects Buffs and Stacking Rules
- SYMPTOMS.md (unreliable > 1 000 octets jeté, état jamais sur unreliable)
