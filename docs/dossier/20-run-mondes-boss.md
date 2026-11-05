# 20 — Run, mondes, ennemis, boss (domaine **run**)

Domaine : `RunManager`, `StageService`, `EnemyService`, `BossService` (serveur), `EnemyRenderer`, `BossRenderer` (client), configs `Run`, `Worlds`, `Enemies`, `Bosses`, `Heightmap`, `EnemyCodec`, `NetDefs/Run`.
Sources de conception : `00-vision.md` sections 2.1, 5.1-5.3, 9, 12.1-12.2. Contrat : `docs/ARCHITECTURE.md`.
Tous les nombres ci-dessous vivent dans `shared/Config/{Run,Worlds,Enemies,Bosses}.luau` (sauf la courbe de densité et le scaling coop de base, lus dans `Balance.luau`, propriété du lead).

---

## 1. Machine à états de la run (v2, A04-02)

Source : `01-decisions-v2.md` section 2 (remplace la v1 : tiers et stages sont remplacés par des **mondes enchaînés**).

`Types.RunPhase = "Loadout" | "Running" | "Boss" | "BossDefeated" | "FinalWave" | "Ended"`. La phase du contrat `FinalWave` porte l'**Overtime** (le HUD lit déjà `finalWaveSeconds` comme un chrono qui monte) ; `RunState.overtime` le dit en clair.

```
Loadout ──(tous les joueurs ont un loadout, ou délai)──> Running (monde 1, chrono 10:00)
Running ──(Arche trouvée, joueurs dans l'arène ou 20 s)──> Boss
Running / Boss ──(chrono 0:00)──> FinalWave = Overtime (le chrono monte, le boss reste tuable)
Boss / Overtime ──(boss vaincu, monde < WorldsPerRun)──> BossDefeated (portail NEXT WORLD, 60 s)
BossDefeated ──(tous dans le portail, ou 60 s)──> Running (monde suivant, chrono 10:00, nouvelle carte)
Boss / Overtime ──(boss du dernier monde vaincu)──> Victory : FinalWave (Overtime infini) + portail CASH OUT
Victory ──(tous les joueurs actifs dans le portail doré 2 s)──> Ended (victoire, cashedOut)
toute phase ──(plus aucun joueur actif)──> Ended (défaite, ou victoire si le dernier boss est tombé)
Ended ──(Replay de tous, ou 10 s après le premier Replay)──> Running (monde 1)
```

| Id (`Config/Run`) | Valeur | Rôle |
| --- | --- | --- |
| `WorldsPerRun` | 3 | Nombre de mondes par run. **Réglage** : Clément doit encore confirmer l'enchaînement |
| `WorldChain` | `BoisGrognon` ×3 | Monde de chaque étape. Vague 1 : on rejoue le stage existant (nouvelle graine, nouvelle carte) avec un paramètre de monde. Vague 2 : ids des mondes 2 et 3 |
| `WorldScaling` | PV ×1 / ×1,8 / ×3 ; dégâts ×1 / ×1,35 / ×1,8 ; vitesse ×1 / ×1,05 / ×1,1 ; densité ×1 / ×1,15 / ×1,3 ; PV du boss ×1 / ×1,8 / ×3 | Force des ennemis par monde (remplace `TierHp`, `StageHpPer`…) |
| `StageSeconds` | 600 s | Chrono par monde (10:00), remis à 10:00 à chaque monde |
| `Overtime.StepSeconds` | 30 s | Un palier d'escalade toutes les 30 s d'Overtime |
| `Overtime.SpawnPerStep` | +15 % | Densité voulue ×(1 + 0,15 k) |
| `Overtime.HpPerStep` | +20 % | PV des ennemis qui apparaissent ×(1 + 0,20 k) |
| `Overtime.DamagePerStep` | +10 % | Dégâts ennemis ×(1 + 0,10 k) |
| `Overtime.ElitePointsPerStep` | +3 points | Part d'élites = `EliteChance` (0,5 %) + 3 % × k ; en Overtime le plafond d'élites vivantes saute. Seules `EliteMaxAlive` (4) élites à la fois sont « à butin » (`Bus.EnemyKilled` isElite = true, coffre) ; les autres sont des **élites de horde** (7e argument `hordeElite` = true) : PV, taille, couronne, KO d'élite, mais pas de coffre, sinon les coffres pleuvraient. Contract request loot : XP et pièces d'élite pour `isElite or hordeElite`, coffre pour `isElite` seulement |
| `Overtime.Compound` | `false` | `true` : ×1,15^k au lieu de ×(1 + 0,15 k). Linéaire par défaut pour que le Keep going reste farmable longtemps |
| `Overtime.CoinsPerStep` | 10 × monde | Pièces de survie par palier et par joueur actif |
| `Overtime.OverflowToHp` | `true` | Au-delà du plafond technique `Balance.MaxEnemies` (300), l'excès de densité devient des PV : PV × (densité voulue / 300). Le joueur voit des ennemis plus forts, pas plus nombreux |
| `CashOut.Radius` / `HoldSeconds` | 10 studs / 2 s | Tous les joueurs actifs dans le portail doré pendant 2 s = Cash out pour toute l'équipe |
| `Waves` | à 360 s et 180 s restantes | Vagues renforcées : 40 ennemis (× densité coop) en 4 s, densité ×1,3 pendant 45 s |
| `ArcheRevealRadius` | 25 studs | Le premier joueur actif à moins de 25 studs de l'Arche la révèle à toute l'équipe |
| `ArenaRadius` | 60 studs | Arène centrée sur l'Arche |
| `ArenaStartSeconds` | 20 s | Le combat démarre quand tous les joueurs actifs sont dans l'arène, ou 20 s après l'entrée du premier |
| `FarmSeconds` | 60 s | Fenêtre après un boss (hors dernier monde) ; l'escalade d'Overtime est gelée jusqu'au portail |
| `PortalRadius` | 8 studs | Tous les joueurs actifs dans le portail = départ immédiat |
| `DifficultyDensityShare` | 0,5 | Rune Cursed : PV ennemis ×(1 + Difficulty moyenne), densité ×(1 + 0,5 × Difficulty moyenne) |
| `LoadoutTimeout` | 45 s (5 s en Studio) | Passé ce délai, un joueur sans loadout reçoit `Knight` + `Braise` |
| `ReplayTimeout` | 10 s | Rejouer : relance quand tout le monde a appuyé, ou 10 s après le premier |

**Après le boss du dernier monde** : bannière `Victory`, portail doré **CASH OUT** sur l'arène. Rester dedans = fin de run, gains sauvés (`RunSummary.cashedOut = true`). S'en éloigner = **Keep going** : l'Overtime continue sans fin (ou démarre tout de suite si le chrono n'était pas à zéro). Mourir après la victoire termine la run en victoire (le dernier boss est tombé).

**Boss** (décisions v2 section 6) : `Bosses.PhaseEnabled = false` (plus de phases 66 / 33 %), télégraphes de 1 s minimum (`Bosses.MinTelegraph`), le Grand Chêne garde 3 attaques (Quake Roots, Acorn Rain, Bark Wave). Plus d'enrage automatique ; seul le défi d'autel rend le boss furieux.

**Flux à une place** (ARCHITECTURE section 7) : `Config.Run.UseLobbyPlace = false`. RunManager écoute aussi `SelectLoadout` (le handler de données traite le choix, RunManager note seulement que le joueur est prêt, puis lit `ProgressionService.getLoadout`). Solo : départ immédiat. MatchService (domaine data) lit `UseLobbyPlace`.

`SelectStage (C→S) (worldId, tier)` reste écouté (pour ne pas casser l'UI v1) mais n'a plus d'effet : la run part toujours du monde 1 de `WorldChain`.

## 2. Joueurs : PV, dégâts, coop

### 2.1 `RunManager.damagePlayer(player, amount, source)`

Ordre appliqué (serveur, une seule fonction, d'après « Downed, Revive and Bleed-Out States » : tous les dégâts passent par un seul cœur) :

1. Joueur non actif (à terre, fantôme, hors run) → 0.
2. Invulnérable (`setInvulnerable`, choix de carte, relève) → 0.
3. **Parade** (Knight / Valor) : un coup annulé toutes les 8 s (`PassiveService.tryBlock`).
4. **Esquive** : `random() < min(Dodge, 0,6)` → 0 (plafond `DodgeCap = 0,6`).
5. **Armure** : `dégâts × 100 / (100 + Armor)` (rendements décroissants ; 100 d'armure = −50 %).
6. **Bouclier** : absorbe d'abord (`shield`), le reste va aux PV.
7. **PV** : si PV ≤ 0 → **à terre** (jamais de mort du Humanoid).
8. Retourne les dégâts réellement pris (bouclier + PV), fire `Bus.PlayerDamaged(player, taken, source)`. Les épines (Guardian, objets) ne répondent qu'à `source == "Contact"` (mêlée), dans PassiveService.

| Stat | Base (sans StatsService) | Source |
| --- | --- | --- |
| MaxHp | 100 | `StatsService.get(player).MaxHp` |
| Armor | 0 | idem |
| Dodge | 0 | idem |
| Regen | 0 PV/s | appliquée toutes les 0,25 s |
| Thorns | 0 | part des dégâts de contact renvoyée à l'ennemi qui touche |

Bouclier : `RunManager.addShield(player, amount, cap?)` (API ajoutée, voir « Contract requests »).

### 2.2 Dégâts de contact

RunManager, 15 Hz : `EnemyService.queryRadius(x, z, 1,5 + rayonMax + 0,5)` autour de chaque joueur actif, puis test exact (rayon de l'ennemi + 1,5) et écart vertical < hauteur ennemi + 2 studs (sauter au-dessus marche). Somme des dégâts des **3 premiers** ennemis au contact, puis **0,5 s** de répit de contact (les projectiles et le boss frappent toujours). Élites : dégâts ×1,5.

### 2.3 À terre, relève, fantôme

| Id | Valeur |
| --- | --- |
| `DownedSeconds` | 25 s pour être relevé |
| `ReviveRadius` | 6 studs |
| `ReviveSeconds` | 3 s cumulées à côté (la jauge redescend 2× plus vite si personne) |
| `ReviveHpFraction` | 30 % des PV max |
| `ReviveInvulnerable` | 2 s |
| `DownedSlow` | ×0,35 (rampe) |
| `GhostShrineRate` | 0,25 (lu par ShrineService, domaine **loot**) |

- À terre : PV figés, plus ciblé par les ennemis, pas de dégâts, attribut joueur `Downed = true`.
- 25 s sans relève → **fantôme** : attribut `Ghost = true`, personnage semi-transparent, sans collision avec les ennemis, peut encore charger les autels à 25 % (ShrineService lit l'attribut `Ghost` ou `RunManager.isActive`).
- Équipe entièrement à terre ou fantôme → défaite immédiate (pas d'attente inutile).
- Le fantôme revit au stage suivant (portail) avec 50 % des PV.

### 2.4 Scaling coop (n = joueurs dans la run)

- PV ennemis × (1 + 0,6 (n − 1)) — `Balance.HpPerExtraPlayer`
- Densité × (1 + 0,4 (n − 1)) — `Balance.DensityPerExtraPlayer`, plafond 300 (75 par joueur à 4)
- PV boss × (1 + 0,8 (n − 1)) — `Bosses.HpPerExtraPlayer`
- **XP partagée à 50 % dans 40 studs** : ce n'est PAS le domaine run. Le domaine **loot** (ramassage) / **combat** (`StatsService.addXp`) s'en charge.

### 2.5 Ralentissement

`RunManager.setSlow(player, mult, seconds)` pose deux attributs sur le **Player** : `SlowMult` (number) et `SlowUntil` (`workspace:GetServerTimeNow()` + seconds). Le `MovementController` (domaine avatar) les lit. Le plus fort ralentissement en cours gagne.

## 3. Les trois mondes

Cartes semi-procédurales construites en Parts au démarrage de chaque stage (`StageService`), à partir d'un **layout déterministe** (`Heightmap.generateLayout(worldId, stage, seed)`, `Random.new(seed)` par usage, d'après « Procedural World Generation »). Le serveur publie `worldId`, `stage` et `seed` en attributs de `Workspace` (`CohueWorld`, `CohueStage`, `CohueSeed`) : chaque client régénère le même layout et la même grille de hauteurs, même si le streaming n'a pas envoyé les Parts (« Instance Streaming »).

Grille de hauteurs : cellules de 2 studs, `buffer` f32, interpolation bilinéaire, aucune requête physique par ennemi (doc 12.2).

| Id | Nom FR / EN | Taille | Sol | Relief | Aléa |
| --- | --- | --- | --- | --- | --- |
| `BoisGrognon` | Bois Grognon / Grumpy Woods | 560 × 560 | herbe 2 verts en damier | 14 plateaux (6-16 studs), collines à 2 niveaux, falaises sans rampe + tremplins | **Brouillard** : à 1:30 puis toutes les 100 s, 30 s, vue 55 studs |
| `DunesCroustillantes` | Dunes Croustillantes / Crunchy Dunes | 640 × 640 | sable 2 tons | 12 dunes-plateaux bas, ruines (piliers, murets) | **Tempête de sable** : à 2:00 puis toutes les 120 s, 20 s, pousse 6 studs/s dans une direction tirée au sort, vue 90 studs |
| `RecreFantome` | Récré Fantôme / Haunted Recess | 520 × 520 | bitume + marelles | préaux et toits (plateaux 8-14 studs avec rampes), escaliers | **Coupure de courant** : à 2:30 puis toutes les 110 s, 20 s, ennemis invisibles au-delà de 20 studs d'un joueur ou 22 d'un lampadaire |

Éléments communs : bordure de falaises, arène plate (rayon 60 + 10) autour de l'Arche, au moins 180 studs du centre ; tremplins (`JumpPad`, propulsion verticale 90 studs/s, appliquée par le client local, le serveur ne fait que poser la Part) ; décor non bloquant au-dessus de 3 studs (cimes `CanCollide = false`).

**Budget de Parts** (vault « Art Budgets », rule of thumb : une zone habillée 3k-10k instances ; on vise mobile bas de gamme) : **≤ 900 Parts par stage**, avertissement si dépassé. Décor : `CastShadow = false` sur les petites pièces, `CanQuery/CanTouch = false` sur tout le visuel (« Physics Performance »).

Points d'apparition fournis au domaine loot : `StageService.getSpawnPoints(kind)` avec `kind` ∈ `Shrine` (8), `Chest` (18), `Pot` (40), `Merchant` (2), `Player` (4, au centre). Tous au sol (Y = hauteur réelle), hors arène, espacés.

### 3.1 Déblocages (lus par le domaine data)

| Cible | Condition |
| --- | --- |
| `BoisGrognon` T1 | Libre |
| `DunesCroustillantes` | Réussir 10 autels d'épreuve au total (tous mondes, tous tiers) |
| `RecreFantome` | Finir un Tier 2 de `DunesCroustillantes` (`victory = true`, tier 2) |
| Tier 2 d'un monde | Battre le boss du stage 1 en T1 de ce monde (`RunSummary.victory`, tier 1) |
| Tier 3 d'un monde | Battre le boss du stage 2 en T2 de ce monde (`stageReached ≥ 2` et `victory`, tier 2) |

Données dans `Worlds[id].unlock` et `Run.TierUnlock`.

## 4. Ennemis

### 4.1 Familles (communes)

| Famille | Comportement | Part des spawns |
| --- | --- | --- |
| `Swarm` (Essaim) | Fonce droit sur le joueur | 80 % |
| `Jumper` (Sauteurs) | Marche, puis à < 22 studs bondit (0,4 s de préparation, 0,8 s en l'air) vers la position **verrouillée** du joueur ; punit l'immobilité. Pas de contact en l'air | dès 0:30 |
| `Shooter` (Tireurs) | Reste à 26 studs ; charge 0,6 s (bit d'état « action », clignote) puis tire un projectile **lent et lisible** (18-20 studs/s, rayon 1,2, durée 4 s) toutes les 3,2 s | dès 2:00 |
| `Armored` (Blindés) | Lent, armure (réduction des dégâts 30-40 %), pousse les autres en se déplaçant (poids ×4 dans la séparation), résiste aux reculs (×0,3) | dès 3:30 |
| Élite | ×6 PV, ×1,5 dégâts, ×1,3 taille, **contour doré** (anneau doré néon + couronne), lâche un coffre (`Bus.EnemyKilled` avec `isElite = true` → LootService) | une garantie toutes les 75 s dès 1:30, + 0,5 % par spawn, max 4 en vie |

Bits d'état (3 bits sur le réseau) : `1` élite, `2` action (saut / charge de tir), `4` gelé ou étourdi (teinte bleue).

### 4.2 Roster (Tier 1, stage 1, solo)

| Kind | Id | Monde | Famille | PV | Vitesse | Dégâts | XP |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `GlandGrincheux` (Gland grincheux / Grumpy Acorn) | Bois | Swarm | 10 | 10 | 6 | 1 |
| 2 | `ChampignonSauteur` (Champignon sauteur / Hopshroom) | Bois | Jumper | 18 | 8 | 10 | 2 |
| 3 | `HibouPlongeur` (Hibou plongeur / Diving Owl) | Bois | Shooter | 14 | 9 | 5 (projectile 9) | 3 |
| 4 | `BogueBlindee` (Bogue blindée / Armored Burr) | Bois | Armored (30 %) | 60 | 6 | 14 | 4 |
| 5 | `MomiePQ` (Momie en papier toilette / TP Mummy) | Dunes | Swarm | 14 | 11 | 8 | 1 |
| 6 | `CactusCoureur` (Cactus coureur / Dash Cactus) | Dunes | Jumper | 22 | 9 | 12 | 2 |
| 7 | `VautourCaillou` (Vautour à cailloux / Pebble Vulture) | Dunes | Shooter | 18 | 10 | 6 (projectile 10) | 3 |
| 8 | `ScarabeeBlinde` (Scarabée blindé / Armored Scarab) | Dunes | Armored (35 %) | 80 | 6,5 | 16 | 4 |
| 9 | `CraieVivante` (Craie vivante / Living Chalk) | Récré | Swarm | 16 | 12 | 9 | 1 |
| 10 | `CartableMordeur` (Cartable mordeur / Biting Backpack) | Récré | Jumper | 26 | 9 | 14 | 2 |
| 11 | `SurveillantFantome` (Fantôme de surveillant / Hall Monitor Ghost) | Récré | Shooter | 22 | 10 | 7 (projectile 11) | 3 |
| 12 | `CasierArmoire` (Casier-armoire / Locker Brute) | Récré | Armored (40 %) | 100 | 6 | 18 | 4 |
| 13 | `SoucheGeante` (Souche géante / Giant Stump) | Bois | Mini-boss | 900 | 7 | 22 | 40 |
| 14 | `ChameauTirelire` (Chameau-Tirelire / Piggy Camel) | Dunes | Mini-boss, lâche 1 pièce par coup (max 1 / 0,3 s) | 1100 | 8 | 24 | 40 |
| 15 | `PionSpectral` (Le Pion Spectral / Spectral Proctor) | Récré | Mini-boss | 1200 | 9 | 26 | 40 |
| 16-19 | boss (voir section 5) | | | Bosses | | 20 | 200 |

Mini-boss : un à 3:00 écoulées, un à 7:00, apparaissent comme élites (coffre) sans le ×6.

Multiplicateurs : tier PV `{1; 1,8; 3}`, dégâts `{1; 1,35; 1,8}`, vitesse `{1; 1,05; 1,1}` ; stage PV × (1 + 0,4 (stage − 1)), dégâts × (1 + 0,2 (stage − 1)).

### 4.3 Courbe de spawn

Cible solo (Balance.DensityCurve) : 10 à 0:00, 40 à 1:00, 120 à 5:00, 200 à 9:00. × densité tier `{1; 1,15; 1,3}` × coop. Plafond 300. Max 10 spawns par tick, anneau 60-90 studs autour d'un joueur actif tiré en tourniquet, borné à la carte. Phase `Boss` : densité ×0,4 ; `BossDefeated` : ×1 (farm) ; `FinalWave` : plafond.

### 4.4 Statuts (`EnemyService.applyStatus`)

| Statut | Paramètres | Effet |
| --- | --- | --- |
| `Burn` | `dps`, `duration`, `source` | Dégâts toutes les 0,5 s ; un nouveau Burn remplace s'il est plus fort |
| `Poison` | `dps`, `duration`, `source` | Cumulable jusqu'à 5× le dps de base appliqué |
| `Slow` | `mult` (0-1), `duration` | Vitesse × mult, le plus fort gagne |
| `Freeze` | `duration` | Immobile, pas d'attaque, teinte bleue |
| `Stun` | `duration` | Immobile, pas d'attaque |
| `Knockback` | `fromX`, `fromZ`, `force` (studs) ou `dirX`, `dirZ`, `force` | Recul sur 0,25 s ; ×0,3 pour Blindés, ×0 pour boss |

Les boss réduisent Freeze/Stun à 25 % de la durée (sauf faiblesse de terrain).

### 4.5 Projectiles ennemis

Simulés côté serveur (points, mouvement en ligne droite, plafond 150), envoyés au client à la création sur `EnemyProjectiles` (RemoteEvent fiable, buffer : id, x, y, z, direction, vitesse, heure serveur) ; le client les rejoue en forme fermée (`origine + dir × vitesse × (t − t0)`), vault « Projectiles and Ballistics ». Une liste d'ids détruits suit dans le même paquet.

## 5. Boss

> **v2 (5 nov., A03-06) : les tableaux 5.1 à 5.3 ci-dessous sont ceux de la v1.** Ce qui est codé aujourd'hui : dossier 13 §11.5. En bref :
> - une seule phase ;
> - 3 attaques par boss, chacune annoncée au sol au moins 1 s avant (`Bosses.MinTelegraph`) ;
> - le boss du monde 2 est The Hungry Coffin (`CercueilAffame`), qui remplace le Pharaon ;
> - tout s'arrête pendant le gel `Workspace.RunFrozen`, horloges comprises.
>
> `BossState.telegraphs[]` porte en plus `attack` (id), `uid` et `fx` (objet d'impact facultatif).

Le boss est une entité d'`EnemyService` (pour que les armes du domaine combat le touchent via `queryRadius` / `damage`), pilotée par `BossService` (mouvement, attaques, phases). PV × tier × (1 + 0,8 (n − 1)). Phases 100 / 66 / 33 %. Chaque attaque a un **télégraphe au sol** (rouge = normal, violet = invocation, doré = faiblesse), d'au moins **0,6 s** (vault « Boss Animation and Phases » : minimum 0,5 s ; les marqueurs qui suivent se **verrouillent 0,5 s** avant l'impact), et passe le test d'esquive `R ≤ 16 × (t − 0,25)` (« Combat Arena and Encounter Layout ») sauf mention. Les ondes en anneau (`Ring`) peuvent être **sautées** (pieds > sol + 4 studs). Phase 2 : cooldowns ×0,85 ; phase 3 : ×0,7 (le télégraphe ne descend jamais sous 0,6 s).

Envoi : `BossState` à 10 Hz pendant le combat + immédiatement à chaque nouveau télégraphe. Champ `telegraph` = le premier, champ ajouté `telegraphs` = tous (format : `{ kind = "Circle"|"Ring"|"Line", position, radius, inner?, dir?, length?, at, color }`).

### 5.1 Le Grand Chêne Ronchon / The Grumpy Great Oak (`GrandCheneRonchon`, Bois Grognon)

PV 5000. Enraciné au centre de l'arène, se déplace lentement (3 studs/s).

| Attaque | Phases | Télégraphe | Dégâts | Cooldown |
| --- | --- | --- | --- | --- |
| `RacinesSismiques` | 1-3 | cercle r 8 sous un joueur, 1,0 s, verrouillé à 0,5 s | 25 | 5 s |
| `PluieDeGlands` | 1-3 | 5 cercles r 5 près des joueurs, 1,2 s | 18 | 8 s |
| `OndeEcorce` | 2-3 | anneau 10-30 autour du boss, 1,5 s, sautable | 30 | 10 s |
| `Rejetons` | 2-3 | violet r 6, 1,0 s, 6 `GlandGrincheux` | — | 15 s |

**Faiblesse de terrain** `Enracinement` (phases 2-3, toutes les 25 s) : le chêne s'enracine 8 s (n'attaque qu'avec `RacinesSismiques`) ; 4 **branches-rampes** (construites dans l'arène, sommet à 8 studs) permettent de monter : tout dégât venant d'un joueur dont les pieds sont à ≥ 5 studs au-dessus du sol, à moins de 22 studs du tronc, est **×3** pendant l'enracinement (le cœur est exposé).

### 5.2 Le Pharaon-Grille-Pain / The Toaster Pharaoh (`PharaonGrillePain`, Dunes)

PV 6000. Marche vers le joueur le plus proche (6 studs/s).

| Attaque | Phases | Télégraphe | Dégâts | Cooldown |
| --- | --- | --- | --- | --- |
| `TartinesBrulantes` | 1-3 | ligne 6 × 40 vers un joueur, 1,0 s | 22 | 5 s |
| `Miettes` | 1-3 | cercle r 5 sur le boss 0,6 s puis éventail de 7 projectiles (60°, 18 studs/s) | 10 / projectile | 6 s |
| `GrilleArdente` | 2-3 | cercle r 14 autour du boss, 1,2 s | 30 | 9 s |
| `Momification` | 2-3 | violet, 5 `MomiePQ` | — | 15 s |
| `Ruee` | 3 | ligne 8 × 50, 1,2 s, puis le boss charge | 28 | 8 s |

**Faiblesse** : 4 **piliers de ruine** dans l'arène. Si la `Ruee` traverse un pilier, le Pharaon s'y encastre : **étourdi 5 s, dégâts subis ×2**. Attirer la charge dans un pilier.

### 5.3 La Directrice Éternelle / The Eternal Headmistress (`DirectriceEternelle`, Récré Fantôme)

PV 6500. Se déplace à 7 studs/s.

| Attaque | Phases | Télégraphe | Dégâts | Cooldown |
| --- | --- | --- | --- | --- |
| `RegleTapante` | 1-3 | cercle r 9 sous un joueur, 1,0 s, verrouillé à 0,5 s | 26 | 4,5 s |
| `AvionsEnPapier` | 1-3 | cercle r 5 sur le boss 0,6 s, 5 projectiles (50°, 20 studs/s) | 11 | 5 s |
| `RetenueGenerale` | 2-3 | anneau 16-40 autour d'elle, 1,6 s, sautable | 28 | 11 s |
| `AppelEnRang` | 2-3 | violet, 6 `CraieVivante` | — | 14 s |

**Faiblesse** `Sonnerie` : un **clocher** (plateforme à 10 studs, rampe) dans l'arène. Un joueur qui reste 2 s sur la cloche (5 studs) la fait sonner : Directrice **étourdie 6 s, dégâts ×2**. Recharge 30 s.

### 5.4 Boss final de monde (T3, stage 3) : Le Grand Brouhaha / The Great Hubbub (`GrandBrouhaha`)

PV 12000, 3 phases, mêmes règles. Se déplace à 6 studs/s.

| Attaque | Phases | Télégraphe | Dégâts | Cooldown |
| --- | --- | --- | --- | --- |
| `CohueTonnerre` | 1-3 | 3 cercles r 10 sous les joueurs, 1,2 s | 30 | 6 s |
| `Spirale` | 1-3 | cercle r 6 sur le boss 0,6 s, 12 projectiles à 360° (16 studs/s) | 12 | 7 s |
| `Barrage` | 2-3 | ligne 10 × 60, 1,2 s | 32 | 8 s |
| `Vague` | 2-3 | anneau 12-45, 1,8 s, sautable | 35 | 12 s |
| `Renforts` | 2-3 | violet, 2 élites du monde | — | 20 s |

**Faiblesse** `Gongs` : 4 gongs sur estrades (6 studs, rampe) au bord de l'arène. Rester 2 s sur un gong : boss étourdi 5 s, dégâts ×2. Recharge 35 s.

Stage 2 des T2/T3 : le boss du monde en version **Furieux** (PV ×1,6, cooldowns ×0,85, nom suffixé « furieux / Enraged »).

Mort du boss : `Bus.BossDefeated(bossId, stage)`, un coffre `Boss` par joueur (`LootService.spawnChest(x, z, "Boss", player)`), passage en `BossDefeated`.

## 6. Compteur de KO (A04-03)

Pilier du jeu : le **classement hebdo du plus grand nombre de KO en une run**. Les KO sont comptés par le serveur uniquement.

- Source unique : `Bus.EnemyKilled(id, kind, x, z, killer, isElite)`, tiré par `EnemyService.damage` quand un ennemi meurt. `killer` est le `source: Player` passé par le code serveur (armes, brûlure, poison, épines, passifs, compagnons). Aucun remote client ne touche au compteur.
- `StatsService.getKills(player)`, `getEliteKills(player)`, `getRunKills() -> { [Player]: number }` ; remis à 0 par `resetRun`.
- `Bus.KOScored(player, runKills, enemyKind, isElite)` à chaque KO (quêtes, classement, effets de KO).
- Attribut joueur `RunKills` (serveur, répliqué, mis à jour à 5 Hz) et champ `kills` de `PlayerProgress` pour le HUD.
- Fin de run : `RunSummary.kills` (lu chez StatsService) dans `Bus.RunEnded` : c'est la valeur que le domaine data envoie au classement.
- Le boss compte pour 1 KO. Les ennemis retirés sans mort (changement de monde, recyclage) ne comptent pas.

L'ancien mode Survie v1 est retiré : le **Keep going** après le dernier boss le remplace.

## 7. Remotes

| Remote | Sens | Contenu |
| --- | --- | --- |
| `RunState` | S→C | contrat + changement et toutes les 1 s ; champs v2 : `worldIndex`, `worldCount`, `overtime`, `overtimeSeconds`, `overtimeStep`, `victory`, `cashOutPosition` (`stage` = `worldIndex`, `tier` = 1) |
| `Announce` | S→C | `{ kind, text, duration }` ; kinds : `StageStart`, `Wave`, `ArcheRevealed`, `ArenaCountdown`, `BossStart`, `BossDefeated`, `Portal`, `Overtime`, `OvertimeStep`, `Victory`, `CashOut`, `Defeat`, `Hazard`, `Downed`, `Revived`, `Died`, `Elite`, `MiniBoss` |
| `PlayerVitals` | S→C | contrat ; le même paquet contient `team` |
| `BossState` | S→C | contrat + `telegraphs`, `stunned` |
| `RunSummary` | S→C | `Types.RunSummary` après `ProgressionService.grantRunRewards` |
| `Replay` | C→S | `()` |
| `EnemyProjectiles` | S→C | buffer (interne au domaine) |
| `SelectStage` | C→S | `(worldId, tier)` (interne, voir contrat) |

## 8. Rendu client

- `EnemyRenderer` : modèles low-poly en Parts par kind (2 à 5 Parts), pool par (kind, LOD, élite), un seul `BulkMoveTo` par frame. LOD : < 80 studs modèle complet, 80-150 une Part simplifiée, > 150 un petit imposteur (une Part plate ; un BillboardGui par ennemi coûterait plus cher). Hystérésis 6 studs. Élite : anneau doré néon + couronne (pas de `Highlight` : 1 Highlight par élite reconstruirait la géométrie à chaque apparition, vault « Highlights and Selection Effects »). Sauteurs : arc parabolique pendant le bit d'action. Projectiles ennemis : sphères néon pool, 2,4 studs, couleur vive par monde.
- `BossRenderer` : modèle du boss (10-16 Parts), interpolation des `BossState`, télégraphes au sol (disque translucide + remplissage qui grandit jusqu'à l'impact, vault « Boss Animation and Phases »), pilier lumineux sur l'Arche révélée, aléas du stage (brouillard, tempête qui pousse le personnage local, coupure de courant), tremplins (le client local applique la vitesse).

## 9. Sources vault (LihFolk Vault V2)

- *Luau Performance Patterns with Benchmarks* ; *Physics Performance* (§6 BulkMoveTo, flags `CanQuery/CanTouch` off sur le visuel)
- *Genre Playbook - Zombie and Wave Survival Co-op* (§3 scaling coop, §4 à terre / relève / wipe, §7 ennemis simulés serveur, rendus client)
- *Downed, Revive and Bleed-Out States* (un seul cœur de dégâts, l'état appartient au serveur, minuteurs en temps serveur)
- *Spawning Teams and Rounds* ; *Arena Rounds with Teams and Spectating End to End* (machine à états serveur, un identifiant de run pour annuler les `task.delay` périmés)
- *Boss Animation and Phases* (télégraphes ≥ 0,5 s, verrouillage 0,45 s, couleurs rouge / doré / violet) ; *Combat Arena and Encounter Layout* (test d'esquive `R ≤ s (t − 0,25)`, rayon d'arène)
- *Projectiles and Ballistics* (points simulés, mouvement en forme fermée partagé)
- *Procedural World Generation* (`Random.new(seed)` par usage) ; *Instance Streaming* (le client ne dépend pas des Parts streamées)
- *Art Budgets - Triangles Draw Calls Memory* (budgets d'instances par zone, rule of thumb) ; *Low-Poly and Stylized Modeling* (proportions exagérées, une forme dominante)
- *Highlights and Selection Effects* (coût de création des Highlights, Docs)
- *Interest Management and Per-Player Replication* (rayons proche / lointain, hystérésis)
