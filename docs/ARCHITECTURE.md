# COHUE — Contrat d'architecture (v2)

Tout agent suit ce fichier. Pour changer quelque chose qui n'est pas à toi, **ne le modifie pas** : écris-le dans ton rapport sous « Contract requests », adressé à **Ironix** (décisions v2 §13).

Sources de design : `docs/dossier/00-vision.md` (le dossier de conception), `docs/dossier/01-decisions-v2.md` (ce qui change en v2, prioritaire), puis un `docs/dossier/NN-<domaine>.md` par domaine. Ce fichier décrit le code réel de `main` ; si le code et ce fichier divergent, le signaler au lead.

## 1. Règles de base

- Luau `--!strict` partout. Pas de `_G`, pas de `shared`, pas de `wait()` / `spawn()` / `delay()` (utiliser `task.*`).
- Le serveur fait autorité sur tout ce qui compte : dégâts, XP, pièces, butin, captures, déblocages, monnaies. Le client n'envoie **que des entrées**, via `Net.onServerEvent` (limité par joueur) ; le handler vérifie le type et la plage de chaque argument.
- Mouvement en **mode classique** : personnage piloté par le client + contrôles de vraisemblance serveur (`MovementGuard`, `TraversalGuard`). Pas d'`AuthorityMode = Server`.
- `init()` ne cède jamais. `start()` peut céder. Appels entre modules : `Registry.get("Nom")` **dans les fonctions**, jamais en haut d'un module (pas de cycle de require). `Registry.find` pour une dépendance facultative.
- Événements serveur entre services : `server/Bus.luau` (tiré seulement par le propriétaire indiqué, section 7).
- Tous les nombres de réglage vivent dans `shared/Config/*`. Texte joueur : forme `{ fr = "...", en = "..." }`, **anglais seul au lancement** (décisions v2 §1, `fr` = copie de `en`). Doc et commentaires en français.
- Mobile d'abord : 200–300 ennemis, téléphones modestes. Pas d'Instance par ennemi côté serveur, pas d'allocation par frame dans les boucles chaudes, visuels client en pool, `BulkMoveTo` pour beaucoup de parts.
- **Rien construit par script côté visuel** (décisions v2 §12) : modèles, effets et écrans d'UI sont posés dans la place COHUE (`ReplicatedStorage.Assets`, `StarterGui`) ; les scripts les clonent et les branchent. Pas d'id d'asset inventé ; ids de produits et de passes = `0` + TODO tant qu'ils n'existent pas.
- Studio sans accès API : DataStore et MemoryStore échouent proprement (repli en mémoire dans Studio, avertissement clair).
- Noms originaux (classes, armes, compagnons, boss). Aucun nom de Megabonk ou de Pokémon.

## 2. Partage du travail (Ownership)

Depuis le 5 nov. 2026 (décisions v2 §13) : Clément fait le créatif, **Ironix fait tout le technique**.

| Côté | Qui | Possède |
| --- | --- | --- |
| **Créatif** | Clément et ses agents (A01 art, A03 ennemis visuels, A08 UI, A09 lobby, A14 armes et effets) | Modèles 3D posés dans COHUE (armes, ennemis, boss, équipement, kit de décor) ; effets posés en objets (`ReplicatedStorage.Assets.FX`) ; écrans d'UI posés en objets (`StarterGui.COHUE_*`, `ReplicatedStorage.Assets.UI`) ; leurs scripts d'affichage côté client : `client/Controllers/UI/*` et `client/Controllers/Lobby/*` ; les outils de montage `tools/ui/*` et `assets/*` ; leurs dossiers (`12`, `13`, `60`, `65`, `80`) |
| **Technique** | Ironix (et les agents qu'il lance : A00, A02, A04, A05, A06, A10, A11, A12, A13) | Tout le reste : `server/*` (services, `Bus`, `Main`), `shared/*` (Config, Net, NetDefs, codecs, Types, Registry), `client/Main.local.luau` et tous les contrôleurs hors `UI/` et `Lobby/` (rendu, caméra, mouvement, son, FX d'armes), le branchement des modèles et des effets, l'assemblage des mondes, `tools/check.sh`, ce fichier, `README.md` |

- Les agents créatifs ne touchent ni au code serveur ni aux mécaniques. Pour le reste : « Contract request » à Ironix.
- Les **noms des modèles et des effets** dans COHUE sont le contrat entre les deux côtés : chaque agent créatif les note dans son dossier.
- Un fichier, un agent à la fois. Chaque agent ne modifie que les fichiers de sa tâche.

## 3. Studio et Git

- **Script Sync** sur les 3 dossiers, **chez Ironix seulement** : `ReplicatedStorage/Shared` ↔ `shared/`, `ServerScriptService/Server` ↔ `server/`, `StarterPlayer/StarterPlayerScripts/Client` ↔ `client/`, synchronisés avec `F:\CohueRoblox` (branche `main`). Une seule personne synchronise la place COHUE partagée.
- Noms de fichiers : `X.luau` = ModuleScript, `X.legacy.luau` = Script, `X.local.luau` = LocalScript (d'où `server/Main.legacy.luau` et `client/Main.local.luau`).
- **Ne jamais modifier un script dans Studio** : on modifie le disque (via Git), Script Sync le pousse dans Studio.
- **Aucun modèle dans les dossiers synchronisés** (seulement des scripts et des dossiers ; pas d'attributs ni de tags sur les scripts, Script Sync les perd). **Aucun script dans les modèles** posés par le côté créatif.
- Les agents travaillent chacun dans un worktree `F:\CohueRoblox-agents\<id>` sur leur branche `claude/<id>-...`, jamais dans `F:\CohueRoblox`, jamais directement sur `main`, jamais de force push. Le lead fusionne dans un worktree temporaire puis avance `main` en `--ff-only`.
- Vérification : `bash tools/check.sh` (tous les fichiers) ou `bash tools/check.sh chemin/fichier.luau`.

## 4. Démarrage

Les deux `Main` démarrent en deux temps : `require` + `Registry.register` de chaque module de la liste, puis `init()` de tous (sans céder), puis `start()` de chacun dans un `task.spawn`. Un module absent ou qui plante est sauté avec un avertissement. Un module dont le nom n'est pas dans la liste n'est pas démarré : c'est un module simple, requis par un module de la liste.

**Serveur** (`server/Main.legacy.luau`) : `Net.create()`, puis require et init de :
DataService, ProgressionService, MonetizationService, StatsService, RunManager, StageService, EnemyService, BossService, LootService, ShrineService, CompanionService, CardService, WeaponService, PassiveService, TraitService, MovementGuard, PingService, MatchService ;
puis `Net.publish()` (le dossier `Remotes` apparaît pour les clients), puis tous les `start()`.
Modules simples : `WorldBuilder` et `WorldPortals` (requis par StageService et RunManager), `TraversalGuard` (requis par MovementGuard).

**Client** (`client/Main.local.luau`, recherche récursive sous `Controllers`) :
CameraController, InputController, MovementController, EnemyRenderer, BossRenderer, WeaponFX, LootRenderer, ShrineFX, CompanionRenderer, UITheme, HUD, CardUI, ShrineUI, Minimap, PingUI, MobileButtons, LoadoutUI, LobbyController, EndScreen, SettingsUI, SoundController, WorldTransition, DebugHud.
Modules simples : `EnemyMotion`, `EnemyAttackFX`, `EnemyRigMotion` (EnemyRenderer, BossRenderer), `PlayerAnimator` et `TraversalController` (démarrés par MovementController), `UI/UIKit`, `UI/UIInput`, `UI/VictoryBanner` et `UI/CaptureUI` (démarrés par HUD).
`LobbyController` est aussi lancé par `LoadoutUI` quand `StarterGui.COHUE_Lobby` est posé ; son `start()` est protégé (`started`), le double lancement est sans effet.

## 5. Ids (utiliser exactement ces chaînes)

- **Classes** (`Config/Classes`, id du passif = id de classe, `Config/Weapons.Passives`) : `Knight`, `Archer`, `Mage`, `Guardian`, `Rogue`, `Cleric`, `Barbarian`, `Tamer`. Gratuites : Knight, Archer, Mage ; les autres par quête `Q_<Classe>`. Transition : `Classes["Cornu"]` etc. renvoient encore la classe v2 (alias en lecture seule, l'itération ne voit que les 8) ; toujours utiliser `def.id`.
- **Armes** (`Config/Weapons.Order`, 16). Départ, une par classe dans l'ordre des classes : `Broadsword` (Knight), `Longbow` (Archer), `FireStaff` (Mage), `QuakeHammer` (Guardian), `ThrowingDaggers` (Rogue), `HolyAura` (Cleric), `SpinningAxes` (Barbarian), `BeastWhip` (Tamer). Pool commun : `LightningChain`, `FrostNova`, `Boomerang`, `BombBag`, `SpearThrow`, `MeteorRain`, `OrbitingBlades`, `CrossbowTurret`. Niveaux 1–8 ; fusion au niveau 9 coupée (`FusionEnabled = false`).
- **Runes** (ex-grimoires ; module `Config/Grimoires`, champ `grimoires` du Build, « Rune » à l'écran), 14 : `Damage`, `AttackSpeed`, `Projectiles`, `Area`, `Duration`, `Cooldown`, `Crit`, `Luck`, `Wisdom`, `Magnet`, `Vitality`, `Armor`, `Agility`, `Cursed`.
- **Compagnons** : plus de lignées ni d'évolution. Un compagnon est une créature battue puis capturée ; **id d'espèce = `Config/Enemies[kind].name`** (tout ennemi qui n'est pas un boss, `CompanionService.isSpecies`). 1 emplacement, 2 pour le Tamer (`CompanionService.slotsFor`). Espèces actuelles :
  - Swarm : `GlandGrincheux`, `ZombieShambler`, `GhostWisp`, `GoblinGrunt` · Jumper : `ChampignonSauteur`, `ZombieRunner` · Shooter : `HibouPlongeur`, `ZombieGravedigger`, `GhostPoltergeist`, `GoblinArcher` · Support : `GoblinShaman`, `GhostHallMonitor`, `GhostBanshee` · Armored : `HauntedArmor` · Kamikaze : `ZombieBloater`, `GoblinBomber` · MiniBoss : `SoucheGeante`, `ChameauTirelire`, `PionSpectral`.
- **Boss** (`Config/Bosses`, pas capturables) : `GrandCheneRonchon`, `PharaonGrillePain`, `DirectriceEternelle`, `GrandBrouhaha`.
- **Mondes** (`Config/Worlds`) : `BoisGrognon` (gratuit), `DunesCroustillantes` (10 autels d'épreuve), `RecreFantome` (Dunes palier 2). Paliers 1–3.
- **Raretés** : `Common`, `Rare`, `Epic`, `Legendary`.
- **Phases de run** (`Types.RunPhase`) : `Loadout`, `Running`, `Boss`, `BossDefeated`, `FinalWave`, `Ended`.
- **Stats** : voir `Types.StatName`.

## 6. APIs des services (entre domaines)

Seules ces fonctions s'appellent d'un autre module. Les fonctions qui commencent par `_` sont internes.

**RunManager** : `getPhase() -> RunPhase` · `getTimeLeft() -> number` · `getRunPlayers() -> {Player}` · `getLoadout(player) -> (classId, companionId)` · `getRunInfo() -> { worldId, tier, stage }` · `damagePlayer(player, amount, source) -> number` (esquive, armure, bouclier, invulnérabilité ; renvoie les dégâts pris) · `healPlayer(player, amount)` · `addShield(player, amount, cap?)` · `getHpFraction(player) -> number` · `isDowned(player)` · `isActive(player)` (vivant et pas à terre) · `isGhost(player)` · `setInvulnerable(player, seconds, source?)` · `clearInvulnerable(player, source)` · `getInvulnerableSeconds(player) -> number` · `getDamageFeetY(player) -> number?` · `setSlow(player, multiplier, seconds)`
**StageService** : `buildStage(worldId, stage, seed, bossId) -> Layout?` · `clear()` · `getWorld() -> World?` · `getSpawnPoints(kind) -> {Vector3}` · `getArche() -> Vector3?` · `getPortalPoint() -> Vector3?` · `showPortal(position)` · `showCashOut(position)` · `updateHazard(elapsed) -> string` · `stopHazard()` · `getPartCount() -> number`
**EnemyService** : `damage(id, amount, source: Player?) -> boolean` · `queryRadius(x, z, radius, out) -> count` · `getPosition(id) -> (x?, z?)` · `isAlive(id)` · `isElite(id)` · `isCapturable(id)` · `getCount() -> number` · `spawnAt(kind, x, z, opts: { elite?, hpMult? }?) -> id?` · `applyStatus(id, status: "Burn"|"Poison"|"Slow"|"Freeze"|"Stun"|"Knockback", params)` · `beginStage(worldId, tier, stage)` · `setDirector(opts)` · `getOverflowMult() -> number` · `burst(size, seconds)` · `forceEliteSoon()` · `clearAll()` · `clearNonBoss()`
**BossService** : `spawnBoss(bossId, centre, stage, tier, nPlayers, enraged) -> boolean` · `despawn()` · `isActive()` · `getPosition() -> Vector3?`
**StatsService** : `get(player) -> StatBlock` · `addStat(player, stat, value, source)` · `addTimedStat(player, stat, value, seconds)` · `addXp(player, amount)` · `getLevel(player)` · `getBuild(player) -> { weapons, grimoires, items }` · `grantItem(player, itemId)` · `getItemCount(player, itemId)` · `resetRun(player, classId)` · `getState(player)` · `getClass(player) -> string?` · `getWeaponLevel / getWeaponBonus(player, weaponId)` · `getGrimoireLevel(player, runeId)` · `upgradeWeapon(player, weaponId, toLevel, bonus) -> boolean` · `upgradeGrimoire(player, runeId, toLevel) -> boolean` · `useCharge(player, kind) -> boolean` · `banishId(player, id)` · `recordDamage(player, key, amount)` · `getDamageByWeapon(player) -> {[weaponId]: number}` · `getKills(player)` · `getEliteKills(player)` · `getRunKills() -> {[Player]: number}`
**CardService** : `isChoosing(player) -> boolean`
**WeaponService** : `dealDamage(player, key, visual, id, damage, fromX, fromZ, knockback) -> boolean` · `statusArea(x, z, radius, status, params)` · `spawnGhost(player, damage, speed, life, radius)` · `pushFx(...)` · `areaFx(visual, x, z, radius)` · `getMotion(player)` · `getPoisoner(id) -> Player?` · `markPoison(id, player, duration)` · `getSlot(player) -> number` · `resetPlayer(player)`
**PassiveService** : `getDamageBonus(player) -> number` · `tryBlock(player, amount, source) -> boolean` · `reviveSpeed(player) -> number` · `resetPlayer(player)`
**LootService** : `dropXp(x, z, amount)` · `dropCoins(x, z, amount)` · `spawnChest(x, z, kind: "Normal"|"Elite"|"Boss"|"Shrine", owner?)` · `addCoins(player, amount)` · `getCoins(player)` · `spendCoins(player, amount) -> boolean` · `getRunStats(player) -> { coinsEarned, chestsOpened }`
**ShrineService** : `getShrines() -> {{ id, kind, position, state }}` · `isBossChallengeActive() -> boolean`
**CompanionService** (dossier 40 §6) : pour EnemyService `isSpecies(kind | speciesId) -> boolean` (au spawn, avant de marquer capturable) et `onCapturableDefeated(kind, x, z, killer?) -> cageId?` (une fois, à la mort sous les coups d'un capturable, juste après `Bus.EnemyKilled` ; jamais pour `clearAll`, dépop ou fin de run ; ne cède jamais) · pour les données `slotsFor(classId) -> number`, `speciesName(speciesId) -> LocalizedText?` · pour les autres `getCardOptions(player) -> {Card}`, `applyCard(player, card)`, `getState(player) -> { line, stage, level }?` (`line` = espèce du 1er compagnon, `stage` = 1), `ensure(player)` (arrivée en cours de run), `getCages() -> {{ id, species, x, z, expiresAt }}` (Minimap), `chargeUltimate(player, n)` (gardé, sans effet : pas d'Ultime)
**TraitService** : `applyClass(player, classId)` · `setTraitStage(player, stage: 1..4)` · `clear(player)`
**MovementGuard** : `exempt(player, seconds, reason?)` · `endExempt(player, after?)` · `getLastValidPosition(player) -> Vector3?` · `getStrikes(player)` · `getRunStrikes(player)`
**ProgressionService** : `getLoadout(player) -> (classId, companionId)` · `getCompanionLoadout(player) -> {speciesId}` · `hasSelectedLoadout(player)` · `setLoadout(player, classId, companionId, companionId2?) -> boolean` · `hasCompanion(player, speciesId)` · `grantCapture(player, speciesId, captureKey) -> (status, isNew)` · `isUnlocked(player, kind: "Class"|"Weapon"|"Grimoire"|"Item"|"Companion", id)` · `isWorldUnlocked(player, worldId, tier)` · `getMetaBonuses(player) -> { weaponSlots, grimoireSlots, banish, skip, reroll }` · `getBond(player, line) -> (number, number)` · `getWeeklyChallenge()` · `recordStat(player, key, amount)` (clés : `Config/Quests`) · `grantRunRewards(player, summary) -> RunSummary` · `logCustom(player, eventName, amount?, fields?)`
**DataService** : `getProfile(player)` · `waitForProfile(player, timeout)` · `peek(player)` · `getStatus(player)` · `canMutate(player)` · `mutate(player, fn) -> boolean` · `saveNow(player)` · `saveSoon(player)` · `addReleaseHook(fn)` · `releaseForTeleport(player)` · `reacquire(player)` · `isMemoryBackend()` · `isTestSession()`
**MonetizationService** : `ownsPass(player, key)` · `isVip(player)`
**MatchService** : `startRun(group, worldId, tier) -> boolean` · `returnToLobby(players) -> boolean` · `openVipRoom(player)` · `getRunConfig() -> { worldId, tier, members }?` · `isActive()` (actif seulement avec `Config.Run.UseLobbyPlace = true`)
**PingService** : pas d'API (remote `Ping` seulement).

Côté client, APIs des contrôleurs utilisées ailleurs : `InputController.onAction / bindButton / trigger / isDown / getVector / getHint / getContext / setEnabled`, `CameraController.getYaw / setEnabled / shake / ...`, `MovementController.isSliding / cancelSlide / externalLaunch / ...`, `SoundController.play / playSound / weapon / enemy / setMusicOverride / ...`, `EnemyRenderer.getVisibleCount`, `LootRenderer.getChests / getChestCost`, `CompanionRenderer.getState / onStateChanged`, `UITheme.watch / last / phase / inRun / profile / ...`, `UIKit.screen / find / clone / ...`, `HUD.feed / setTeam`, `CardUI.isOpen / ...`, `PingUI.send / quickPing / openWheel`, `SettingsUI.open / close`, `Minimap.getBottom / getSize`, `WeaponFX.setQuality`.

Flux clés :
- **Début de run** : RunManager attend les loadouts (`SelectLoadout` → ProgressionService), puis `StatsService.resetRun`, `TraitService.applyClass`, tire `Bus.RunStarted` (CompanionService pose les compagnons).
- **KO** : EnemyService tire `EnemyKilled` (+ `CompanionService.onCapturableDefeated` pour un capturable) → LootService lâche XP et pièces (élite : coffre) → ramassage → `StatsService.addXp` → `PlayerLeveledUp` → CardService envoie `CardOffer` ; TraitService fait grandir l'équipement aux niveaux 10/20/30. StatsService tire `KOScored`.
- **Capture** : la cage dure `Companions.CageSeconds` ; rester dedans sans être touché → `ProgressionService.grantCapture` → `CaptureState` au joueur, `CageState` à tous.
- **Dégâts de contact** : RunManager interroge EnemyService autour de chaque joueur à 15 Hz et appelle son propre `damagePlayer`.
- **Fin** : RunManager construit un `RunSummary` par joueur → `ProgressionService.grantRunRewards` → remote `RunSummary`.

## 7. Événements du Bus (`server/Bus.luau`)

| Événement | Tiré par | Arguments |
| --- | --- | --- |
| `EnemyKilled` | EnemyService | `(id, kind, x, z, killer: Player?, isElite, hordeElite)` — `isElite` = élite à coffre ; `hordeElite` = élite d'Overtime sans coffre |
| `KOScored` | StatsService | `(player, runKills, enemyKind, isElite)` |
| `PlayerLeveledUp` | StatsService | `(player, level)` |
| `RunStarted` | RunManager | `(players, worldId, tier)` |
| `StageStarted` | RunManager | `(stage, worldId)` |
| `BossRevealed` | RunManager | `(position: Vector3)` |
| `BossDefeated` | BossService | `(bossId, stage)` |
| `FinalWaveStarted` | RunManager | `()` |
| `RunEnded` | RunManager | `(summaries: {[Player]: RunSummary})` |
| `PlayerDamaged` | RunManager | `(player, amount, source)` — `"Contact"` = mêlée |
| `PlayerDowned` / `PlayerDied` | RunManager | `(player)` |
| `PlayerRevived` | RunManager | `(player, rescuer)` |
| `ChestOpened` | LootService | `(player, chestKind)` |
| `ShrineCompleted` | ShrineService | `(players, shrineKind)` |
| `CompanionEvolved` | CompanionService | `(player, stage)` — reste de la v1, plus tiré en v2 (ProgressionService l'écoute encore) |
| `ProfileLoaded` | DataService | `(player)` |

## 8. Remotes (`shared/Net.luau` + `shared/NetDefs/*`)

Serveur → client sauf « C→S ». (U) = `UnreliableRemoteEvent`, paquets ≤ 900 octets (découper comme `EnemyCodec`). Un remote serveur → client appelé par un client est jeté et compté (`Net.getStrayCalls`). Les noms doivent être uniques entre `Net` et les `NetDefs` (assert au chargement).

| Remote | Fichier, domaine | Payload |
| --- | --- | --- |
| EnemySnapshot (U) | Net, run | buffer `EnemyCodec` |
| RunState | Net, run | `{ phase, timeLeft, worldId, tier, stage, bossRevealed, bossPosition?, finalWaveSeconds, ... }` — à chaque changement et chaque seconde |
| Announce | Net, run | `{ kind, text: LocalizedText, duration }` |
| PlayerVitals | Net, run | `{ hp, maxHp, shield, downed, downedTimeLeft?, ghost, reviveProgress? }` ; aussi `{ team = { [userId]: { hp, maxHp, downed, ghost } } }` |
| BossState | Net, run | `{ bossId, name, hpFrac, phase, position, telegraph? }` |
| RunSummary | Net, run | `Types.RunSummary` (après ProgressionService) |
| Replay (C→S) | Net, run | `()` |
| EnemyAttackVisual (U) | NetDefs/Run | indices visuels d'attaque |
| EnemyProjectiles | NetDefs/Run | buffer `EnemyCodec.encodeProjectiles` |
| EnemyCapturable | NetDefs/Run | `(id, on: boolean)` |
| SelectStage (C→S) | NetDefs/Run | `(worldId, tier)` |
| PlayerProgress | Net, combat | `{ level, xp, xpNext }` |
| Build | Net, combat | `{ weapons, grimoires, items, stats, banish, skip, reroll, weaponSlots, grimoireSlots }` |
| CardOffer | Net, combat | `{ offerId, cards, expiresIn, banish, skip, reroll }` ; `{ offerId, closed = true }` à la fin |
| CardChoice (C→S) | Net, combat | `(offerId, action: "pick"\|"ban"\|"skip"\|"reroll", index?)` |
| WeaponFx (U) | Net, combat | buffer `WeaponFxCodec` |
| LootSnapshot (U) | Net, loot | buffer `LootCodec` |
| Coins | Net, loot | `{ coins }` |
| ShrineState | Net, loot | `{ shrines = {{ id, kind, position, state, progress, chargers }} }` |
| ShrineOffer / ShrineChoice (C→S) | Net, loot | `{ offerId, choices = {{ stat, value, rarity }} }` / `(offerId, index)` |
| LootInteract (C→S) | NetDefs/Loot | `(id)` |
| MerchantOffer / MerchantBuy (C→S) | NetDefs/Loot | offre du marchand / `(slot)` |
| LootReward | NetDefs/Loot | récompense de coffre (dossier 30 §8) |
| ShrineInteract (C→S) | NetDefs/Loot | `(shrineId)` |
| ShrineGag | NetDefs/Loot | gags de l'autel Farceur |
| CompanionState | Net, companion | `{ line, stage = 1, level, name, ultimateCharge = 0, stunned, techs = {}, companions = {{ species, name, slot }} }` → propriétaire |
| CompanionSnapshot (U) | Net, companion | 10 Hz ; en-tête 5 octets + 25 octets par compagnon (dossier 40 §7) |
| CompanionUltimate (C→S) | Net, companion | `()` — sans effet en v2 |
| CaptureState | NetDefs/Companion | `{ state = "Idle"\|"Capturing"\|"Interrupted"\|"Captured"\|"Refused", progress, holdSeconds, name?, isNew?, reason? }` → le joueur qui capture, ≤ 10/s ; `reason` : `"Cap"` ou `"Unavailable"` |
| CageState | NetDefs/Companion | `{ cages = {{ id, species, kind, x, y, z, expiresIn, done = { userId } }} }` → tous |
| MoveEvent (C→S) | NetDefs/Avatar | `(kind: "SlideStart"\|"SlideEnd"\|"Hop"\|"HopReset")` ; MovementGuard pose les attributs `Sliding`, `SlideCharge`, `HopChain`, `Airborne`, `HeavyLandAt` |
| Ping (C→S) / PingBroadcast | Net, ui | `(kind, position)` / `{ userId, kind, position }` |
| Profile | Net, data | `{ silver, questTokens, unlocks, quests, mastery, bond, cosmetics, equipped, settings, loadout, shop, worlds, weekly, passes, vip, companions = { owned = {[espèce]: { n, at }}, equipped = { espèce1, espèce2? } }, koRecord, season, ... }` |
| SelectLoadout (C→S) | Net, data | `(classId, companionId, companionId2?)` |
| EquipCosmetic (C→S) | Net, data | `(slot, cosmeticId?)` |
| UpdateSettings (C→S) | Net, data | `(settings: { keepHat?, colorblind?, reduceFlashes?, textScale?, ... })` |
| ShopBuy / HatchEgg / RequestPurchase (C→S) | NetDefs/Data | `(offerId)` / `()` / `(productKey)` |
| EggHatched | NetDefs/Data | `{ line?, tokens? }` |
| Leaderboards | NetDefs/Data | `{ [boardKey]: {{ userId, value }} }` |
| MatchRequest (C→S) / MatchState | NetDefs/Data | `(worldId, tier)` / `{ state, reason? }` |
| DataNotice | NetDefs/Data | `{ kind, text, questId? }` |

Le détail de chaque payload est dans le dossier du domaine (20 §7, 30 §8, 40 §7, 50, 70 §16).

## 9. Test dans la place unique COHUE

Arrivée → lobby (`LobbyController`, si `StarterGui.COHUE_Lobby` est posé ; sinon l'ancien écran `LoadoutUI`) → `SelectLoadout` → RunManager lance la run → run → `EndScreen` → `Replay` ou retour au lobby. MatchService (téléportation lobby → run, MemoryStore, libération du profil) n'est actif qu'avec `Config.Run.UseLobbyPlace = true`. `DebugHud` (fps, ennemis) ne s'affiche que dans Studio (`Balance.Debug.ShowStats`), en bas à gauche, sous le reste de l'UI.

## 10. Écarts connus et demandes en attente

- `Config/Progression.Unlocks.Weapon` est encore en ids v1 (`HacheBoomerang`...) : à passer aux 16 armes v2 (Ironix, données).
- Les mondes gardent leurs ids v1 (`DunesCroustillantes`...) : ce sont les ids réels du code tant que le dossier 20 ne les renomme pas.
- Dossier 40 §10 : `Bus.PlayerHit(player, source)`, tiré au début de `RunManager.damagePlayer` pour tout coup reçu par un joueur actif, avant invulnérabilité, parade, esquive et bouclier — **pas encore dans `Bus.luau`** (CompanionService l'écoute déjà s'il existe). `RunManager.isFrozen()` (gel coop du choix de carte) — **pas encore fait** (CompanionService l'appelle déjà s'il existe).
- Dossier 65 §10 : attribut joueur `InRun` (RunManager) ; départ avec les seuls joueurs prêts ; retour au lobby après victoire ou Cash out.

## 11. Fini (par tâche)

1. Le dossier du domaine est écrit d'abord : chaque élément avec id, nom, nombres, notes du vault utilisées.
2. Le code suit ce dossier et les APIs ci-dessus. Les nombres sont dans Config.
3. Chaque fichier touché compile (`bash tools/check.sh`).
4. Rapport : fichiers, APIs exposées, hypothèses, notes du vault, contract requests, manques connus.
