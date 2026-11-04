# 10 — Combat : armes, grimoires, objets, cartes, passifs

Domaine **combat**. Source : `00-vision.md` §5.2, §6.2, §8.1–8.3, §12.3. Contrat : `docs/ARCHITECTURE.md`.
Tous les nombres ci-dessous vivent dans `shared/Config/{Weapons,Grimoires,Items,Cards,Rarities}.luau` : ce document décrit, la config fait foi en cas d'écart.

Fichiers : `server/Services/{StatsService,CardService,WeaponService,PassiveService}.luau`, `server/Services/Weapons/{Pool,FxQueue}.luau`, `shared/WeaponFxCodec.luau`, `client/Controllers/WeaponFX.luau`.

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
| XpGain | 0 | — | StatsService.addXp |
| Magnet | 0 | — | LootService (studs ajoutés au rayon) |
| MaxHp | 100 | — | RunManager |
| Armor | 0 | — | RunManager (courbe conseillée `Armor/(Armor+50)`) |
| Regen | 0 | — | RunManager (PV/s) |
| MoveSpeed | 0 | 1 | domaine avatar |
| Dodge | 0 | 0,6 | RunManager |
| Thorns | 0 | 1 | PassiveService (renvoi) |
| Bounces | 0 | 10 | WeaponService (Éclats de prisme) |
| Difficulty | 0 | — | domaine run |
| LootBonus | 0 | — | domaine loot |

Ordre de calcul de `StatsService.get` : base → + grimoires → + objets (× nombre) → + passif de classe (plat + par niveau) → + boosts `addStat` (autels, permanents pour la run) → + boosts temporaires (objets) → multiplicateurs d'objets (ex. Pile usée PV ×0,9) → plafonds. Valeur mise en cache, recalculée seulement si quelque chose change.

## 2. Formule de dégâts (une fonction pure, serveur)

Ordre canonique tiré de la note vault *Damage Formula Pipeline* :

```
coup = base(arme, niveau)
     × (1 + Damage + bonus_rareté_arme + bonus_contexte)      -- un seul seau additif
     × facteurs « more » (fusion, Tentaculos ×0,9, Poing : +1 %/Armure)
     × crit ? (2 + CritDamage) : 1                              -- crit tiré côté serveur
     × objet Ciseaux (8 %/pile : ×2)
-> arrondi une seule fois, minimum 1
```

- `bonus_contexte` : Plumeline en l'air (+25 %), charges du Bélier (Cornu, +0,5 %/ennemi percuté), Petite voiture (en mouvement), Oreiller (immobile), Lunettes de chasseur (élites/boss, si `EnemyService.isElite` existe).
- Chance de crit = `CritChance + critChance de l'arme`, plafonnée à 1. Le crit est tiré par coup, jamais par le client.
- **Armure ennemie : N/A.** Les ennemis n'ont pas d'armure au lancement ; la seule mitigation est côté joueur (RunManager).
- Les dégâts sur la durée (Brûlure, Poison) sont appliqués par EnemyService via `applyStatus` ; leurs paramètres `dps` sont déjà multipliés par `(1 + Damage)` au moment de l'application.

Paramètres envoyés à `EnemyService.applyStatus` (le domaine run les interprète) :
`Burn`/`Poison` : `{ dps, duration, source: Player, maxStacks }` · `Slow` : `{ mult, duration }` · `Freeze`/`Stun` : `{ duration }` · `Knockback` : `{ fromX, fromZ, force }`.

## 3. XP et niveaux

- XP pour passer du niveau L à L+1 : `floor(6 + 4·L + 0,35·L²)` → L1 : 10, L5 : 34, L10 : 81, L20 : 226, L30 : 441. Cumul jusqu'au niveau 30 ≈ 4 900 XP (≈ une run réussie, le trait grandit à 10/20/30).
- Niveau max 99. `addXp(player, n)` applique `× (1 + XpGain)`.
- **Partage coop** (§5.2) : fait **dans** `StatsService.addXp` : chaque coéquipier actif à ≤ 40 studs reçoit 50 % du montant de base (avec son propre XpGain). Le domaine loot appelle `addXp` une seule fois pour le ramasseur, sans partager lui-même.
- Plusieurs niveaux d'un coup : chaque niveau tire `Bus.PlayerLeveledUp` ; CardService les met en file.

## 4. Cartes de niveau (§5.2, §8)

- **3 cartes**, **8 s**, sans pause : `RunManager.setInvulnerable(player, 8)` + `setSlow(player, 0.5, 8)`. À l'expiration : choix auto de la carte **la plus rare** (égalité : la première).
- File : si plusieurs niveaux sont gagnés, les offres s'enchaînent (nouvelle fenêtre de 8 s chacune). Pas d'offre tant que le joueur est à terre ; elle s'ouvre quand il est relevé.
- **Pool** (poids de tirage) : amélioration d'arme possédée 1,2 · nouvelle arme 1,0 · amélioration de grimoire 1,0 · nouveau grimoire 0,9 · **fusion disponible 3,0**. Tirage pondéré sans remise, ids distincts.
- **Compagnon** : chaque emplacement de carte a 25 % de chance d'être tiré dans `CompanionService.getCardOptions` (≈ 1 carte sur 4). Appliqué via `CompanionService.applyCard`.
- **Emplacements pleins** : plus de « nouvelle arme » quand les emplacements d'armes sont pleins, idem grimoires. Une arme niveau 8 sans fusion possible, une arme fusionnée, un grimoire au max sortent du pool. Les ids **bannis** sortent du pool pour la run.
- **Pool vide** : cartes de secours *Goûter* (soin 30 % PV max) et *Tirelire* (+20 pièces × (1 + LootBonus)).
- **Débloquage** : armes/grimoires filtrés par `ProgressionService.isUnlocked` (sans ProgressionService : tout est ouvert sauf le Grimoire Interdit).
- **Bannir** (sur une carte arme/grimoire) : l'id sort du pool, la carte est remplacée. **Passer** : ferme l'offre sans rien prendre. **Relancer** : 3 nouvelles cartes. Chaque action change l'`offerId` ; le temps restant continue. Charges : `ProgressionService.getMetaBonuses` (repli 3/3/3).
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
| Niveaux de grimoire gagnés | 1 | 2 | 3 | 4 |

La carte de fusion est toujours Legendary. Astrel : toutes les 5 offres, au moins une carte est Rare ou mieux.

### 4.2 Emplacements

4 armes / 4 grimoires (méta : `getMetaBonuses`, plafond 6). Tentaculos +1 arme.

## 5. Les 16 armes

Toutes tirent seules côté serveur à 15 Hz (`Balance.SimHz`). Projectiles = données (aucune Part serveur), collisions via `EnemyService.queryRadius`. Cadence finale = `cooldown × (1 − Cooldown) / (1 + AttackSpeed)`, minimum 0,15 s. Rayon/portée × `(1 + Size)`, durées × `(1 + Duration)`, quantité + `Amount`.

Notation des niveaux : `+N dég` (plat), `+N qté`, `+15 % zone`, `−10 % cd`, etc. Niveau 9 = fusion.

| # | Id | Nom FR / EN | Comportement | Base niv. 1 | Stats clés |
| --- | --- | --- | --- | --- | --- |
| 1 | HacheBoomerang | Hache-boomerang / Boomerang Axe | Part vers l'ennemi le plus proche 0,55 s, revient au joueur, transperce tout (chaque passage touche une fois) | 14 dég, cd 1,5 s, rayon 1,8, 1 hache, 34 studs/s | Taille, Quantité |
| 2 | PlumesDards | Plumes-dards / Feather Darts | Rafale (éventail 8°) vers l'ennemi le plus proche, perce 1 | 8 dég, cd 1,1, 2 dards, 70 studs/s, 0,8 s | Quantité, Vit. d'attaque |
| 3 | CleTourelle | Clé-tourelle / Wrench Turret | Pose une tourelle fixe 8 s qui tire un dard toutes les 0,8 s (portée 35) | 7 dég/dard, cd 6, 1 tourelle | Durée, Quantité |
| 4 | GriffesEclair | Griffes éclair / Lightning Claws | Coup en cône 100° devant soi (vers l'ennemi le plus proche), portée 7 ; Quantité = coups supplémentaires alternés | 18 dég, cd 1,0, +10 % crit | Critique |
| 5 | PoingSeisme | Poing-séisme / Quake Fist | Onde circulaire rayon 9, recul 8 ; +1 % dégâts par point d'Armure ; Quantité = ondes en plus (+0,3 s) | 20 dég, cd 2,5 | Taille, Armure |
| 6 | NuageSpores | Nuage de spores / Spore Cloud | Nappe qui suit le joueur 3,5 s, rayon 6, frappe toutes les 0,5 s + Poison (3 dps, 3 s) | 4 dég/tic, cd 5 | Durée, Taille |
| 7 | SouffleBraise | Souffle de braise / Ember Breath | Cône de feu 50°, portée 9, + Brûlure (4 dps, 3 s) | 6 dég, cd 0,45 | Vit. d'attaque |
| 8 | Meteorite | Météorite / Meteorite | Chute 0,7 s après le marquage sur un ennemi à ≤ 35 studs, zone rayon 7 ; chaque point de Chance = +1 % de chance d'une météorite en plus | 40 dég, cd 3,0, 1 météore | Chance, Taille |
| 9 | EclatsPrisme | Éclats de prisme / Prism Shards | Frappe l'ennemi le plus proche (≤ 30) puis rebondit (≤ 12 studs) ; + Rebonds | 11 dég, cd 1,3, 2 rebonds, +5 % crit | Rebonds, Critique |
| 10 | FouetTentacule | Fouet-tentacule / Tentacle Whip | Balayage 360° rayon 8, recul 6 ; Quantité = balayages en plus (+0,25 s) | 15 dég, cd 1,8 | Taille |
| 11 | ToupieScie | Toupie à scie / Saw Top | 2 scies en orbite (rayon 5, 4 rad/s × (1+Vit. d'attaque)) pendant 4 s ; un même ennemi touché toutes les 0,5 s | 8 dég, cd 5 | Quantité, Vitesse |
| 12 | BouleBowling | Boule de bowling / Bowling Ball | Roule tout droit vers l'ennemi le plus proche 2,5 s, transperce tout, recul 10 | 25 dég, cd 2,2, rayon 2,2, 26 studs/s | Taille, Dégâts |
| 13 | CerfVolantLaser | Cerf-volant laser / Laser Kite | Un cerf-volant au-dessus du joueur tire un rayon vers l'ennemi le plus proche (portée 28) : tic toutes les 0,25 s, touche tout le segment (largeur 1,5), 3 s actif | 5 dég/tic, cd 5 | Durée |
| 14 | ParapluieBouclier | Parapluie-bouclier / Umbrella Shield | Une charge : le prochain coup reçu est annulé (PV rendus + 0,5 s d'invulnérabilité) et renvoie une onde rayon 10, recul 12 ; recharge 12 s | 30 dég (onde), 1 charge | Cooldown |
| 15 | BombePaillettes | Bombe à paillettes / Glitter Bomb | Lancée sur un ennemi à ≤ 25, explose après 0,8 s, rayon 6, Étourdit 0,8 s (« aveugle ») | 22 dég, cd 2,6 | Taille, Quantité |
| 16 | PistoletBulles | Pistolet à bulles / Bubble Blaster | Bulle vers l'ennemi le plus proche (éventail 15°), Gel 1 s (« emprisonne »), perce 1 | 9 dég, cd 1,2, 30 studs/s | Quantité |

### 5.1 Niveaux 2 → 8

| Arme | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HacheBoomerang | +1 qté | +6 dég | +15 % zone | +1 qté | +6 dég | −10 % cd | +1 qté, +8 dég |
| PlumesDards | +1 qté | +3 dég | +1 perce | +1 qté | −10 % cd | +3 dég | +2 qté |
| CleTourelle | +3 dég | +2 s durée | −15 % intervalle | +1 tourelle | +3 dég | +1 dard/tir | +1 tourelle, +3 dég |
| GriffesEclair | +5 dég | +15 % zone | +5 % crit | +1 qté | +6 dég | −10 % cd | +50 % dég. crit, +6 dég |
| PoingSeisme | +6 dég | +15 % zone | −10 % cd | +1 onde | +8 dég | +15 % zone | +10 dég, Étourdit 0,3 s |
| NuageSpores | +2 dég | +1 s durée | +15 % zone | +3 dps poison | +1 nuage | +1 s durée | +3 dég, +20 % zone |
| SouffleBraise | +2 dég | +15 % portée | +3 dps brûlure | −10 % cd | +3 dég | +20° d'angle | +4 dps brûlure, +15 % portée |
| Meteorite | +12 dég | +1 qté | +15 % zone | +15 dég | −10 % cd | +1 qté | +20 dég, +20 % zone |
| EclatsPrisme | +1 rebond | +4 dég | +1 qté | +1 rebond | +5 dég | −10 % cd | +2 rebonds, +5 dég |
| FouetTentacule | +5 dég | +15 % zone | +1 qté | +6 dég | +15 % zone | −10 % cd | +8 dég, +20 % zone |
| ToupieScie | +1 scie | +3 dég | +1 s durée | +1 scie | +15 % zone | +3 dég, +25 % vitesse | +1 scie, +1 s durée |
| BouleBowling | +8 dég | +15 % zone | +1 qté | +10 dég | +0,5 s durée | +1 qté | +12 dég, +20 % zone |
| CerfVolantLaser | +2 dég | +1 s durée | +15 % portée | +1 rayon | +2 dég | +1 s durée | +3 dég, −15 % cd |
| ParapluieBouclier | +10 dég | −10 % cd | +15 % zone | +1 charge | +12 dég | −10 % cd | +15 dég, +1 charge |
| BombePaillettes | +7 dég | +15 % zone | +1 qté | +0,4 s étourdi | +8 dég | +1 qté | +10 dég, +20 % zone |
| PistoletBulles | +1 qté | +3 dég | +0,3 s gel | +1 qté | +4 dég | −10 % cd | +2 qté |

### 5.2 Fusions (arme niv. 8 + grimoire précis niv. ≥ 5 → carte Legendary, niveau 9)

| Arme | Grimoire | Fusion FR / EN | Effet |
| --- | --- | --- | --- |
| HacheBoomerang | Taille | Hache Tempête / Storm Axe | ×1,5 dég, +2 haches, +30 % zone |
| PlumesDards | VitesseAttaque | Rafale d'Aigle / Eagle Volley | 2 salves (0,2 s d'écart), +2 perce, ×1,3 dég |
| CleTourelle | Quantite | Atelier Volant / Flying Workshop | les tourelles suivent le joueur, +1 dard/tir, ×1,3 dég |
| GriffesEclair | Critique | Griffe Foudroyante / Thunder Claw | chaque crit fait sauter un éclair sur 3 ennemis proches, ×1,3 dég |
| PoingSeisme | Rempart | Faille Tellurique / Tectonic Rift | +2 % dég par Armure (au lieu de 1 %), Étourdit 0,6 s, ×1,3 dég |
| NuageSpores | Aimant | Marée de Spores / Spore Tide | +40 % zone, ralentit de 50 %, ×1,4 dég |
| SouffleBraise | Degats | Souffle du Dragon / Dragon Breath | +60 % portée, angle 90°, brûlure ×2, ×1,3 dég |
| Meteorite | Chance | Pluie d'Étoiles / Star Shower | +3 météores, +1 % crit par point de Chance |
| EclatsPrisme | Savoir | Prisme du Savant / Scholar Prism | +3 rebonds, chaque ennemi tué donne +1 XP |
| FouetTentacule | Vitalite | Kraken Tourbillon / Kraken Swirl | +1 balayage, soigne 2 % des dégâts infligés (max 5 PV/s) |
| ToupieScie | Agilite | Tornade d'Acier / Steel Tornado | scies permanentes, +2 scies, vitesse ×1,5 |
| BouleBowling | Taille | Boule Titanesque / Titan Ball | rayon ×2, se divise en 3 petites boules en fin de course |
| CerfVolantLaser | Duree | Comète de Papier / Paper Comet | rayon permanent, +1 rayon, ×1,3 dég |
| ParapluieBouclier | Cooldown | Grand Chapiteau / Big Top | l'onde part aussi seule à chaque recharge, zone ×2 |
| BombePaillettes | Quantite | Feu d'Artifice Géant / Grand Fireworks | chaque bombe éclate en 4 mini-bombes (40 % dég.) |
| PistoletBulles | Interdit | Bulles Cosmiques / Cosmic Bubbles | les bulles explosent (rayon 6) en éclatant, ×1,3 dég |

Le Grimoire Interdit étant un déblocage tardif, Bulles Cosmiques est la fusion « de fin de jeu ».

## 6. Les 14 grimoires (max niveau 8, Interdit 5)

Valeurs **par niveau** (cumul linéaire), sauf Quantité.

| Id | FR / EN | Par niveau | Au max |
| --- | --- | --- | --- |
| Degats | Dégâts / Damage | +8 % Damage | +64 % |
| VitesseAttaque | Vitesse d'attaque / Attack Speed | +7 % AttackSpeed | +56 % |
| Quantite | Quantité / Amount | Amount 1,1,2,2,3,3,4,4 ; niveaux pairs +4 % Damage | +4 qté, +16 % |
| Taille | Taille / Size | +8 % Size | +64 % |
| Duree | Durée / Duration | +10 % Duration | +80 % |
| Cooldown | Recharge / Cooldown | +4 % Cooldown | −32 % |
| Critique | Critique / Critical | +4 % CritChance, +10 % CritDamage | +32 %, +80 % |
| Chance | Chance / Luck | +3 Luck | +24 |
| Savoir | Savoir / Knowledge | +10 % XpGain | +80 % |
| Aimant | Aimant / Magnet | +3 Magnet | +24 studs |
| Vitalite | Vitalité / Vitality | +15 MaxHp, +0,1 Regen | +120 PV, +0,8/s |
| Rempart | Rempart / Bulwark | +3 Armor | +24 |
| Agilite | Agilité / Agility | +4 % MoveSpeed, +2 % Dodge | +32 %, +16 % |
| Interdit | Grimoire Interdit / Forbidden Tome | +10 % Difficulty, +12 % LootBonus, +5 % XpGain, +5 % Damage | ×5 |

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

## 8. Passifs des 10 classes (§6.2)

| Classe | Passif | Règle exacte |
| --- | --- | --- |
| Cornu | Bélier / Ram | Quand la vitesse au sol dépasse 21 studs/s (glissade), les ennemis à ≤ 3,5 studs prennent 10 dég. × (1 + Damage) + recul 10 (une fois par seconde par ennemi). Chaque ennemi percuté : +0,5 % dégâts pour la run (max +75 %). Les arcs de recul font partie de la classe (domaine avatar). |
| Plumeline | Vent arrière / Tailwind | +25 % dégâts (seau additif) quand les pieds ne touchent rien (`FloorMaterial == Air`). |
| Mecano | Bricoleur / Tinkerer | Autels chargés 35 % plus vite (lu par ShrineService : classe Mecano) ; les tourelles reçoivent `Amount` en tourelles supplémentaires (au lieu de dards). |
| Felyne | Élan / Momentum | 5 atterrissages d'affilée sans subir de dégâts → griffure éclair rayon 10, 30 dég. × (1 + Damage). Le compteur revient à 0 si le joueur est touché. |
| Rocailleux | Bouclier vivant / Living Shield | +3 Armure par niveau ; Épines +30 % (les coups reçus renvoient 30 % aux 3 ennemis les plus proches à ≤ 6 studs). |
| Sporelin | Contagion | Un ennemi empoisonné par un Sporelin qui meurt applique Poison (4 dps × (1 + Damage), 3 s) à 6 voisins max à ≤ 8 studs. Peut se propager en chaîne. |
| Ecaille | Combustion | Les brûlures du joueur se cumulent sans limite (`maxStacks = 999`) mais durent 2 s. |
| Astrel | Bonne étoile / Lucky Star | +1 Chance par niveau ; toutes les 5 offres de cartes, au moins une carte Rare+. |
| Cristallin | Croissance / Growth | +2 % Taille par niveau. |
| Tentaculos | Multitâche / Multitask | +1 emplacement d'arme ; toutes ses armes font ×0,9. |

Les Épines (stat Thorns) de tous les joueurs suivent la même règle que Rocailleux. Les valeurs sont dans `Config.Weapons.Passives`.

## 9. Coop (§5.2)

- XP individuelle, partage 50 % à 40 studs (section 3). Build, cartes et niveaux individuels.
- Aucune pause : invulnérable + ralenti 50 % pendant le choix.
- Les armes de chaque joueur touchent tous les ennemis ; les dégâts sont crédités au tireur (`EnemyService.damage(id, n, player)`) pour le kill et les stats de fin.
- Rien n'est tiré quand `RunManager.isActive(player)` est faux (à terre, fantôme, hors run).
- `StatsService.getDamageByWeapon(player)` alimente `RunSummary.damageByWeapon` (les objets/passifs offensifs y figurent sous leur id).

## 10. Réseau et budgets mobile

- **WeaponFx** (UnreliableRemoteEvent) : `WeaponFxCodec`, en-tête 6 octets (version u8, tick u32, nombre u8), enregistrement fixe 14 octets, ≤ 900 octets par paquet (63 évènements). Les évènements sont cosmétiques : en perdre un ne change rien au jeu (note vault *RemoteEvents RemoteFunctions and Unreliable Remotes*).
- Types d'évènement : Projectile (le client le simule), Fin de projectile, Zone (onde, cône, explosion avec délai), Segment (rayon, rebond), Attaché (scies, nuage, cerf-volant qui suivent un joueur, identifié par l'attribut `FxSlot` du Player).
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
