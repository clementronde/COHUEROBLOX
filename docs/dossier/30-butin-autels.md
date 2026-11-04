# 30 — Butin et autels (domaine loot)

Domaine : gemmes d'XP, pièces de run, pots, coffres, marchand ambulant, autels.
Fichiers : `server/Services/{LootService,ShrineService}.luau`, `shared/Config/{Loot,Shrines}.luau`, `shared/LootCodec.luau`, `shared/NetDefs/Loot.luau`, `client/Controllers/{LootRenderer,ShrineFX}.luau`.
Tous les nombres ci-dessous vivent dans `Config.Loot` et `Config.Shrines` (ce document = valeurs de départ).

Règles de fond (vision 5.2, 12.4) :
- Le serveur décide de tout : apparition, ramassage, tirages, prix, soldes. Le client ne fait qu'afficher et envoyer des intentions (`LootInteract(id)`, `ShrineChoice(offerId, index)`…), validées côté serveur.
- Gemmes, pièces, pots, coffres = **données serveur** (aucune Part côté serveur). Le client dessine à partir de `LootSnapshot` (binaire, ≤ 900 octets par paquet).
- Coffres **instanciés par joueur** : chaque joueur voit et ouvre sa propre copie, personne ne vole personne.

## 1. Gemmes d'XP (`XpGem`)

| Palier | id kind | FR / EN | Valeur | Couleur |
| --- | --- | --- | --- | --- |
| 1 | `GemSmall` | Petite gemme / Small gem | 1–4 | cyan |
| 2 | `GemMedium` | Gemme / Gem | 5–24 | vert |
| 3 | `GemLarge` | Grosse gemme / Large gem | 25–99 | violet |
| 4 | `GemHuge` | Gemme géante / Huge gem | 100+ | orange |

- `dropXp(x, z, amount)` crée **une** gemme dont le palier dépend de la valeur (seuils `Loot.GemTiers`).
- XP par ennemi : `EnemyDef.xp` sinon défaut par famille (`Loot.XpByFamily` : Swarm 1, Jumper 2, Shooter 2, Armored 4) ; élite ×5 (`Loot.EliteXpMult`).
- **Fusion** (perf mobile) : à partir de `GemMergeThreshold = 250` gemmes au sol, une nouvelle gemme se fond dans la gemme la plus proche à moins de `GemMergeRadius = 12` studs (valeur additionnée, palier recalculé). Au-delà de `MaxGems = 400`, elle se fond dans la plus ancienne gemme. Aucune XP n'est jamais perdue.
- Pas de disparition dans le temps.

### Aimant et ramassage
- Rayon de ramassage = `BaseMagnet = 5` studs + stat `Magnet` (studs à plat, `StatsService.get(p).Magnet`).
- Le serveur teste à 10 Hz la distance gemme ↔ `HumanoidRootPart` des joueurs **actifs** (`RunManager.isActive`). Aucune requête client : rien à falsifier. La gemme part en « vol » chez le client (animation accélérée vers le torse, vault *Collectible Pickup FX*) ; la récompense est déjà donnée côté serveur.
- XP reçue = valeur × (1 + `XpGain`), arrondie au centième, puis `StatsService.addXp(player, xp)`. Hypothèse : `addXp` n'applique pas `XpGain` une seconde fois.

### Partage d'XP coop (vision 5.2)
- Quand un joueur ramasse une gemme de valeur v, **chaque autre joueur actif à 40 studs ou moins** (`XpShareRadius`) reçoit **50 %** de v (`XpShareRatio`) × (1 + son `XpGain`). C'est un bonus : le ramasseur garde 100 %.
- Les joueurs à terre ou fantômes ne reçoivent rien.

## 2. Pièces de run (`Coin`)

- Monnaie **de la run uniquement**, perdue à la fin (vision 11.1). Jamais achetable en Robux (voir §9).
- Pièce simple (`Coin`, valeur 1–4) et tas (`CoinPile`, valeur 5+).
- Gain au ramassage = valeur × (1 + `LootBonus`), arrondi, au ramasseur uniquement (`addCoins`).
- Même aimant que l'XP. Fusion : `CoinMergeThreshold = 120`, `MaxCoins = 160`, rayon 12.

### Pièces par famille d'ennemi (`Loot.CoinsByFamily`)

| Famille | Chance | Pièces |
| --- | --- | --- |
| Swarm (essaim) | 8 % | 1 |
| Jumper (sauteurs) | 12 % | 1 |
| Shooter (tireurs) | 15 % | 1 |
| Armored (blindés) | 30 % | 2 |
| Élite (toute famille) | 100 % | 6 |

Multiplicateur de tier : ×(1 + 0,25 × (tier − 1)) (`CoinTierBonus`). Revenu visé ≈ 250–350 pièces par stage de 10 min (≈ 1 500 kills, pots, élites).

## 3. Pots (`Pot`)

- `PotsPerStage = 40`, positions `StageService.getSpawnPoints("Pot")` (sinon dispersés autour du centre, Y par `Heightmap`).
- Partagés (un pot pour toute l'équipe). Cassés quand un joueur actif passe à moins de `PotBreakRadius = 3,5` studs (test de point serveur, pas de `Touched`).
- Contenu (`Loot.PotTable`, tirage pondéré) :

| Résultat | Poids | Effet |
| --- | --- | --- |
| Pièces | 60 | 2–4 pièces au sol |
| XP | 25 | gemme de 6 XP |
| Aspirateur | 5 | toute l'XP au sol vole vers ce joueur (comme l'autel Aspiration de Megabonk) |
| Rien | 10 | — |

## 4. Coffres (`Chest`)

| kind | FR / EN | Source | Ouverture | Contenu |
| --- | --- | --- | --- | --- |
| `Normal` | Coffre / Chest | `ChestsPerStage = 10` points `"Chest"` | **payant** en pièces, invite « Ouvrir (X) » | 1 objet |
| `Elite` | Coffre d'élite / Elite chest | élite tuée (un coffre par joueur actif) | gratuit, on marche dessus | 1 objet |
| `Boss` | Coffre de boss / Boss chest | `Bus.BossDefeated` (un par joueur, à côté de lui) | gratuit | 2 objets |
| `Shrine` | Coffre d'autel / Shrine chest | autel d'épreuve réussi (un par joueur) | gratuit | 1 objet |

- Ouverture gratuite : le propriétaire passe à moins de `ChestAutoOpenRadius = 3,5` studs.
- Coffre payant : `ProximityPrompt` local (créé par le client sur sa copie), `HoldDuration 0,3 s`, `MaxActivationDistance 8`, puis `LootInteract(id)` ; le serveur revérifie propriétaire, distance (≤ 8 + 4 de marge), solde.
- **Prix** : `ChestBaseCost = 20` × (1 + 0,5 × (stage − 1)), × `ChestCostGrowth = 1,3` par coffre déjà acheté par CE joueur dans le stage, arrondi. Ex. stage 1 : 20, 26, 34, 44, 57…
- Objet : rareté tirée (ci-dessous), puis objet au hasard parmi `Config.Items` de cette rareté (débloqués si `ProgressionService.isUnlocked`) ; `StatsService.grantItem(player, itemId)`. Pas d'objet disponible : rareté inférieure, sinon pièces de remplacement (`ItemFallbackCoins` : 5/10/20/40).
- Chaque ouverture : `Bus.ChestOpened(player, kind)`, `LootReward` au client, `recordStat("ChestsOpened", 1)`.

### Raretés (vision 8.3) et Chance (`Loot.ChestRarity`)

Poids de base (Common / Rare / Epic / Legendary) :

| Coffre | Common | Rare | Epic | Legendary |
| --- | --- | --- | --- | --- |
| Normal | 70 | 22 | 7 | 1 |
| Elite | 45 | 35 | 16 | 4 |
| Boss | 0 | 50 | 38 | 12 |
| Shrine | 40 | 38 | 18 | 4 |

**Définition unique de la Chance** (vault *RNG Drops and Luck Systems* : additive et plafonnée) : L = clamp(`Luck`, 0, `LuckCap = 50`). Chaque poids non commun est multiplié par (1 + k × L) avec k = Rare 0,02, Epic 0,03, Legendary 0,04, puis on renormalise. Exemple coffre Normal avec Luck 10 : 65,5 % / 24,7 % / 8,5 % / 1,3 %. La même fonction (`LootService` → `Config.Loot.rarityWeights`) sert à l'affichage éventuel des chances et au tirage : une seule table.

Couleurs : Common gris, Rare bleu, Epic violet, Legendary or (`Loot.RarityColors`).

## 5. Marchand ambulant (`Merchant`)

- FR « Colporteur Grigri » / EN « Trinket Peddler ». Apparaît à `MerchantAppearAt = 120 s` du stage sur un point `"Merchant"`, se déplace vers un autre point toutes les `MerchantMoveEvery = 150 s`.
- Stock **par joueur** (instancié), tiré à la première visite : 3 objets (rareté tirée avec les poids du coffre Elite + Chance) + 1 soin.
- Prix : Common 18, Rare 35, Epic 65, Legendary 120 ; soin (`Heal`, 35 % des PV max via `RunManager.healPlayer`) 12. × (1 + 0,5 × (stage − 1)). Chaque emplacement se vend une fois.
- Interaction : invite locale → `LootInteract(id)` → `MerchantOffer` ; achat `MerchantBuy(slot)` (le serveur vérifie distance ≤ 12, stock, solde). `recordStat("MerchantPurchases", 1)`.

## 6. Autels (vision 8.4)

Commun à tous : position `StageService.getSpawnPoints("Shrine")`, cercle de `Radius = 8` studs, le serveur teste les positions des joueurs à 10 Hz. État envoyé par `ShrineState` (à chaque changement, max 4/s).

### Vitesse de charge coop (vision 5.2)
Chargeurs effectifs e = joueurs actifs dans le cercle + 0,25 × fantômes dans le cercle (les joueurs à terre ne comptent pas).
Multiplicateur (interpolé) : e = 0 → 0 ; 0,25 → 0,25 ; 1 → ×1 ; 2 → ×1,5 ; 3+ → ×2 (`Shrines.CoopSpeed`).
Cercle vide : la progression retombe à 0 en `DecayTime = 1,5 s` (Megabonk : sortir = reset ; on laisse 1,5 s de tolérance pour le lag mobile).

| kind | FR / EN | Nombre / stage | Charge (solo) | Effet |
| --- | --- | --- | --- | --- |
| `Charge` | Autel de charge / Charge shrine | **15** (dont dorés) | 6 s | chaque joueur **actif** dans le cercle reçoit 3 choix de stat (§6.1) |
| `Golden` | Autel doré / Golden shrine | chaque `Charge` a **8 %** de chance d'être doré | 9 s | 3 choix **Legendary** pour tout le cercle ; lueur dorée |
| `Trial` | Autel d'épreuve / Trial shrine | 2 | 3 s | fait apparaître **5 élites** (+2 par joueur en plus) autour de l'autel, `EnemyService.spawnAt(kind, x, z, { elite = true })` ; tous tués en 90 s → un coffre `Shrine` par joueur actif ; échec = autel éteint |
| `BossChallenge` | Autel du défi du boss / Boss challenge shrine | 1 | 4 s | ouvre un **vote** de 20 s pour toute l'équipe ; majorité stricte des joueurs actifs (solo : son oui suffit ; abstention = non). Accepté : 2e boss (demande au domaine run), et à la défaite du boss un **2e coffre de boss** par joueur (récompense ×2) |
| `Prankster` | Distributeur farceur / Prank vending machine | 1 | interaction | paie `25` pièces (+15 par utilisation du même joueur) → 1 objet (poids coffre Normal + Chance) + un **gag d'équipe 20 s** (§6.3). Réutilisable |
| `PiggyBank` | Tirelire avide / Greedy piggy bank | 1 | 3 s | chaque joueur de la run : **+40 pièces** ×(1 + 0,5 (stage − 1)), **+0,25 `LootBonus`** et **+0,10 `Difficulty`** jusqu'à la fin de la run. Visible par tous (malus partagé) |
| `RecessBell` | Cloche de récré / Recess bell | 1 | 3 s | 5 s : tous les ennemis à 40 studs sont **tirés vers la cloche** (`applyStatus(id, "Knockback", { towardX, towardZ, distance })` toutes les 0,5 s) ; ennemis tués dans ce rayon pendant ces 5 s (+1 s) donnent **XP ×2** |
| `TeamTotem` | Totem d'équipe / Team totem | 1 (seulement si ≥ 2 joueurs) | 5 s, **2 joueurs actifs minimum** dans le cercle | buff **60 s** pour toute l'équipe : +15 % `Damage`, +10 % `MoveSpeed`, +3 `Armor` (retirés à la fin) |

Total : 22 autels par stage max. Récompense pour chaque joueur dans le cercle (vision 5.2). Fantômes : ils aident à charger (25 %) mais ne reçoivent pas de stat.

### 6.1 Choix de stat (`ShrineOffer` / `ShrineChoice`)
- 3 stats différentes tirées dans `Shrines.StatPool`, chacune avec sa rareté (poids 60/28/10/2 + Chance ; `Golden` = Legendary).
- Le joueur a `OfferTimeout = 15 s` (sinon la carte la plus rare est prise). Un seul choix par offre, `offerId` vérifié, index ∈ {1,2,3}, offre au bon joueur — sinon ignoré.
- `StatsService.addStat(player, stat, value, "Shrine")`.

| Stat | Common | Rare | Epic | Legendary |
| --- | --- | --- | --- | --- |
| Damage (%) | 0,05 | 0,08 | 0,12 | 0,18 |
| AttackSpeed (%) | 0,05 | 0,08 | 0,12 | 0,18 |
| MaxHp | 10 | 16 | 25 | 40 |
| Armor | 1 | 2 | 3 | 5 |
| MoveSpeed (%) | 0,04 | 0,06 | 0,09 | 0,13 |
| CritChance | 0,02 | 0,035 | 0,05 | 0,08 |
| Luck | 1 | 2 | 3 | 5 |
| XpGain (%) | 0,06 | 0,10 | 0,15 | 0,22 |
| Magnet (studs) | 2 | 3 | 5 | 8 |
| Size (%) | 0,05 | 0,08 | 0,12 | 0,18 |
| Regen (PV/s) | 0,2 | 0,35 | 0,5 | 0,8 |
| Dodge | 0,015 | 0,025 | 0,04 | 0,06 |

### 6.2 Vote du défi du boss
`ShrineOffer` avec `kind = "Vote"` et deux choix (`stat = "Yes"` / `"No"`), réponse via `ShrineChoice(offerId, 1|2)`. Un vote par joueur actif, 20 s.

### 6.3 Distributeur farceur : gags sans toucher l'avatar
**Règle de design : l'avatar n'est jamais modifié** (seul le trait de classe le change). Les gags de la vision (« tête géante, voix aiguë ») sont **remplacés** par des gags d'écran, de caméra et de lumière, joués côté client par `ShrineFX` (remote `ShrineGag`), pour toute l'équipe, 20 s :

| id | FR / EN | Effet client |
| --- | --- | --- |
| `CameraTilt` | Caméra de travers / Tilted camera | roulis de 7° qui oscille lentement |
| `Disco` | Mode disco / Disco mode | `ColorCorrectionEffect` local dont la teinte tourne lentement (cycle 4 s, pas de flash) ; atténué si `reduceFlashes` |
| `Confetti` | Pluie de confettis / Confetti rain | 40 confettis 2D poolés qui tombent sur l'écran (hors zone centrale) |

Sons : à ajouter plus tard (aucun id d'asset inventé).

## 7. Positions
`StageService.getSpawnPoints(kind: "Shrine"|"Chest"|"Pot"|"Merchant") -> {Vector3}` via `Registry.find`. Absent ou vide : points dispersés entre 40 et 260 studs du centre (0, 0), Y = `Heightmap.getY`, graine par stage.

## 8. Réseau

| Remote | Sens | Contenu |
| --- | --- | --- |
| `LootSnapshot` (U) | S→C | buffer `LootCodec` : en-tête 8 o (tick u32, chunk u8, chunkCount u8, count u8, mode u8 0=delta/1=complet), enregistrement 7 o (id u16, x i16, z i16, kind 4 bits + état 4 bits) ; ≤ 900 o par paquet |
| `Coins` | S→C | `{ coins, chestCost }` (`chestCost` ajouté) |
| `ShrineState` | S→C | `{ shrines = {{ id, kind, position, state, progress, chargers, cost? }} }` |
| `ShrineOffer` / `ShrineChoice` | S→C / C→S | voir 6.1–6.2 ; `{ offerId, closed = true }` à la fermeture |
| `LootInteract` | C→S | `(id: number)` coffre payant / gratuit / marchand (5/s) |
| `MerchantOffer` / `MerchantBuy` | S→C / C→S | `{ merchantId, offers = {{ slot, kind, itemId?, rarity, price, sold }} }` / `(slot: number)` |
| `LootReward` | S→C | `{ source, chestKind?, itemId?, rarity?, coins? }` (pour l'UI) |
| `ShrineInteract` | C→S | `(shrineId: number)` distributeur farceur |
| `ShrineGag` | S→C | `{ gag, duration }` |

Deltas (apparitions, ramassages, ouvertures) envoyés à 10 Hz quand il y en a, **état complet toutes les 1 s** dans 160 studs (les paquets non fiables peuvent se perdre : le complet répare). Coffres instanciés : un joueur ne reçoit que ses propres coffres.

## 9. Politique « objets aléatoires payants » (vérifiée vault, oct. 2026)
Un objet aléatoire payant = tout résultat aléatoire obtenu **directement ou indirectement avec des Robux**, y compris via une monnaie achetable en Robux. Les récompenses aléatoires gagnées sans Robux ni monnaie payante sont **exemptées**.
Coffres payants, marchand et Distributeur farceur coûtent des **pièces de run gagnées en jouant** et remises à zéro à chaque run : ils sont exemptés **tant que** cette règle tient :

> **Règle de garde** : aucun produit Robux (dev product, pass, abonnement, carte, bonus de chance) ne peut donner de pièces de run, de `Luck`, de `LootBonus`, de relance de coffre, ni accélérer l'apparition de coffres. Si un jour c'est le cas, coffres, marchand et distributeur deviennent des objets aléatoires payants : chances affichées avant achat (somme 100 %, bouton avec un mot), `PolicyService.ArePaidRandomItemsRestricted` vérifié côté serveur en échec fermé.

On garde aussi : pas de pile-ou-face ni de « double ou rien » avec les pièces (erreur listée par le vault).

## 10. Statistiques de quête (`ProgressionService.recordStat`)

| Clé | Quand |
| --- | --- |
| `ChestsOpened` | tout coffre ouvert |
| `ChestsBought` | coffre payant ouvert |
| `PotsBroken` | pot cassé |
| `CoinsCollected` | pièces ramassées (montant) |
| `MerchantPurchases` | achat chez le marchand |
| `ShrinesCharged` | autel `Charge` ou `Golden` terminé (chaque joueur récompensé) |
| `GoldenShrinesCharged` | autel doré terminé |
| `TrialShrinesCompleted` | autel d'épreuve réussi (déblocage Dunes : 10 au total) |
| `BossChallengesAccepted` | défi du boss accepté |
| `PranksterUses` | distributeur utilisé |
| `PiggyBanksBroken` | tirelire activée |
| `RecessBellsRung` | cloche activée |
| `TeamTotemsActivated` | totem activé |
| `AllShrinesCharged` | les 15 autels de charge d'un stage terminés (chaque joueur actif) |

`Bus.ShrineCompleted(players, kind)` est tiré pour chaque autel terminé.

## 11. Sources vault (LihFolk Vault V2)
- *RNG Drops and Luck Systems* — §3 Luck multipliers : chance additive plafonnée, une seule définition, tirages serveur.
- *Drop Tables Rarity and Pity Systems* — tables de butin en données, poids et chances séparés.
- *Collectible Pickup FX - Idle Glint, Magnet Pull and Collect Pop* — pas de pièces serveur ni `Touched`, une boucle d'animation partagée, aimant accéléré visé au torse, pools.
- *Clickable and Interactive Parts - ClickDetector, ProximityPrompt and Touched* et *ProximityPrompt - Engine Reference Card* — prompt pour les actions choisies (coffres payants, marchand), test de point pour « marcher dessus », vérification serveur distance + état ; `HoldDuration` pour ce qui coûte.
- *ProximityPrompt Gamepad Keys and the Hidden PlayerList Tab* — touche manette en conflit possible (à remapper par l'InputController).
- *Roblox Policies Ratings and Compliance* §2 (Docs, oct. 2026) et *Regional Compliance - Paid Random Items and Country Rules* — définition « directement ou indirectement avec des Robux », exemption des récompenses gagnées, échec fermé.
- *RemoteEvent - Engine Reference Card* (Limits) et *RemoteEvents RemoteFunctions and Unreliable Remotes* — non fiable > 1 000 o jeté, l'état ne passe pas en non fiable (offres, pièces, autels en fiable).
- *AI Pitfalls - Networking and Security*, SYMPTOMS (NaN, prix pris dans le payload) — type, `math.isfinite`, plage, propriétaire, débit ; jamais de prix venant du client.
- *Economies and Currencies* §3 — dépense vérifiée et déduite en une étape sans yield.
- *VFX Performance Budgets and Culling* — pools, plafond visible, pas de lumières multiples (une seule `PointLight` par autel doré).
- *Camera Systems* (SYMPTOMS FOV) — un seul propriétaire du FOV : les gags n'y touchent pas.
