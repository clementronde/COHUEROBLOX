# COHUE — Architecture contract

Every domain agent follows this file. If you need a change to something you don't own, **don't edit it**: write it in your report under "Contract requests".

Design source: the design doc (COHUE — Dossier de conception), summarized in `docs/dossier/00-vision.md`. Detailed design per domain: `docs/dossier/NN-<domain>.md` (each domain writes its own).

## 1. Ground rules

- Luau `--!strict` everywhere. No `_G`, no `shared`, no `wait()` / `spawn()` / `delay()` (use `task.*`).
- Server is authoritative for everything that matters: damage, XP, coins, loot, unlocks, currencies. Client sends **inputs only** through `Net.onServerEvent` (rate limited); handlers check the type and range of every argument.
- Movement is **classic mode**: client-driven character + server plausibility checks (MovementGuard). No `AuthorityMode = Server`.
- `init()` never yields. `start()` may yield. Cross-module calls: `Registry.get("Name")` **inside functions**, never at the top of a module (no require cycles). `Registry.find` for optional dependencies.
- Server events between services: `server/Bus.luau` (fire only from the owner listed there).
- All tuning numbers live in `shared/Config/*`. Text shown to players is `{ fr = "...", en = "..." }`.
- Mobile first: 200–300 enemies, low-end phones. No per-enemy Instances on the server, no per-frame allocation in hot loops, pool client visuals, `BulkMoveTo` for many parts.
- No real asset ids invented. Visuals are built from parts/meshes made in code, or `nil` icon placeholders. Product/pass ids are `0` placeholders with a TODO.
- Studio without API access: DataStore/MemoryStore calls must fail gracefully (in-memory fallback in Studio, clear warning).
- Names (classes, weapons, companions, bosses) are original. No Megabonk/Pokémon names.
- Script Sync naming: `X.luau` ModuleScript, `X.legacy.luau` Script, `X.local.luau` LocalScript.

## 2. Ownership

| Domain | Owns (create/edit only these) |
| --- | --- |
| **run** | `server/Services/{RunManager,StageService,EnemyService,BossService}.luau`, `shared/Config/{Enemies,Worlds,Bosses,Run}.luau`, `shared/Heightmap.luau`, `shared/EnemyCodec.luau`, `shared/NetDefs/Run.luau`, `client/Controllers/{EnemyRenderer,BossRenderer}.luau`, `docs/dossier/20-run-mondes-boss.md` |
| **combat** | `server/Services/{StatsService,CardService,WeaponService,PassiveService}.luau`, `server/Services/Weapons/*`, `shared/Config/{Weapons,Grimoires,Items,Cards,Rarities}.luau`, `shared/WeaponFxCodec.luau`, `shared/NetDefs/Combat.luau`, `client/Controllers/WeaponFX.luau`, `docs/dossier/10-combat-armes-grimoires-objets.md` |
| **loot** | `server/Services/{LootService,ShrineService}.luau`, `shared/Config/{Loot,Shrines}.luau`, `shared/LootCodec.luau`, `shared/NetDefs/Loot.luau`, `client/Controllers/{LootRenderer,ShrineFX}.luau`, `docs/dossier/30-butin-autels.md` |
| **companion** | `server/Services/CompanionService.luau`, `shared/Config/Companions.luau`, `shared/NetDefs/Companion.luau`, `client/Controllers/CompanionRenderer.luau`, `docs/dossier/40-compagnons.md` |
| **avatar** | `server/Services/{TraitService,MovementGuard}.luau`, `shared/Config/{Classes,Movement}.luau`, `shared/NetDefs/Avatar.luau`, `client/Controllers/{InputController,MovementController}.luau`, `docs/dossier/50-classes-avatar-mouvement.md` |
| **ui** | `server/Services/PingService.luau`, `client/Controllers/UI/*` (UITheme, HUD, CardUI, ShrineUI, Minimap, PingUI, MobileButtons, LoadoutUI, EndScreen, SettingsUI), `shared/Config/UI.luau`, `docs/dossier/60-ui-ux.md` |
| **data** | `server/Services/{DataService,ProgressionService,MonetizationService,MatchService}.luau`, `shared/Config/{Quests,Products,Cosmetics,Progression}.luau`, `shared/NetDefs/Data.luau`, `docs/dossier/70-donnees-progression-monetisation.md` |
| **lead** (me) | `shared/{Net,Registry,Signal,Types}.luau`, `server/Bus.luau`, both `Main` scripts, `shared/Config/Balance.luau`, `docs/ARCHITECTURE.md`, `docs/dossier/00-vision.md`, `README.md` |

Boot order (server): DataService, ProgressionService, MonetizationService, StatsService, RunManager, StageService, EnemyService, BossService, LootService, ShrineService, CompanionService, CardService, WeaponService, PassiveService, TraitService, MovementGuard, PingService, MatchService.
Boot order (client): InputController, MovementController, EnemyRenderer, BossRenderer, WeaponFX, LootRenderer, ShrineFX, CompanionRenderer, UITheme, HUD, CardUI, ShrineUI, Minimap, PingUI, MobileButtons, LoadoutUI, EndScreen, SettingsUI, DebugHud.
A module with any other name is not booted: make it a plain module required by one of these.

## 3. Ids (use exactly these strings)

- **Classes** (passive id = class id): `Cornu`, `Plumeline`, `Mecano`, `Felyne`, `Rocailleux`, `Sporelin`, `Ecaille`, `Astrel`, `Cristallin`, `Tentaculos`. Free: Cornu, Plumeline, Mecano.
- **Weapons**: `HacheBoomerang`, `PlumesDards`, `CleTourelle`, `GriffesEclair`, `PoingSeisme`, `NuageSpores`, `SouffleBraise`, `Meteorite`, `EclatsPrisme`, `FouetTentacule`, `ToupieScie`, `BouleBowling`, `CerfVolantLaser`, `ParapluieBouclier`, `BombePaillettes`, `PistoletBulles`. Class start weapons in that order (Cornu → HacheBoomerang … Tentaculos → FouetTentacule).
- **Grimoires**: `Degats`, `VitesseAttaque`, `Quantite`, `Taille`, `Duree`, `Cooldown`, `Critique`, `Chance`, `Savoir`, `Aimant`, `Vitalite`, `Rempart`, `Agilite`, `Interdit`.
- **Companion lines**: `Braise`, `Ronce`, `Maree`, `Volt`, `Givre`, `Echo` (stages 1–3; stage names in Companions config).
- **Worlds**: `BoisGrognon`, `DunesCroustillantes`, `RecreFantome`. Tiers 1–3.
- **Rarities**: `Common`, `Rare`, `Epic`, `Legendary`.
- **Stats**: see `Types.StatName`.

## 4. Service APIs (cross-domain)

Only these functions may be called from another domain. Owners must implement them with these exact signatures.

**EnemyService** (run): `damage(id, amount, source: Player?) -> boolean` · `queryRadius(x, z, radius, out: {number}) -> count` · `getPosition(id) -> (x?, z?)` · `isAlive(id) -> boolean` · `getCount() -> number` · `spawnAt(kind, x, z, opts: { elite: boolean?, hpMult: number? }?) -> id?` · `applyStatus(id, status: "Burn"|"Poison"|"Slow"|"Freeze"|"Stun"|"Knockback", params: {[string]: any})`
**RunManager** (run): `getPhase() -> RunPhase` · `getTimeLeft() -> number` · `getRunPlayers() -> {Player}` · `getLoadout(player) -> (classId, companionId)` · `damagePlayer(player, amount, source: string) -> number` (applies dodge/armor/shield/invuln, returns damage taken) · `healPlayer(player, amount)` · `isDowned(player) -> boolean` · `isActive(player) -> boolean` (alive and not downed) · `setInvulnerable(player, seconds)` · `setSlow(player, multiplier, seconds)` · `getRunInfo() -> { worldId, tier, stage }`
**StatsService** (combat): `get(player) -> StatBlock` (final values) · `addStat(player, stat, value, source: string)` · `addXp(player, amount)` · `getLevel(player) -> number` · `getBuild(player) -> { weapons: {{id, level}}, grimoires: {{id, level}}, items: {{id, count}} }` · `grantItem(player, itemId)` · `resetRun(player, classId)`
**CardService** (combat): `isChoosing(player) -> boolean`
**LootService** (loot): `dropXp(x, z, amount)` · `dropCoins(x, z, amount)` · `spawnChest(x, z, kind: "Normal"|"Elite"|"Boss"|"Shrine", owner: Player?)` · `addCoins(player, amount)` · `getCoins(player) -> number` · `spendCoins(player, amount) -> boolean`
**ShrineService** (loot): `getShrines() -> {{ id, kind, position: Vector3, state }}` (for Minimap)
**CompanionService** (companion): `getCardOptions(player) -> {Card}` · `applyCard(player, card: Card)` · `chargeUltimate(player, amount)` · `getState(player) -> { line, stage, level }?`
**TraitService** (avatar): `applyClass(player, classId)` · `setTraitStage(player, stage: 1|2|3|4)` · `clear(player)`
**ProgressionService** (data): `getLoadout(player) -> (classId, companionId)` · `isUnlocked(player, kind: "Class"|"Weapon"|"Grimoire"|"Item"|"Companion", id) -> boolean` · `getMetaBonuses(player) -> { weaponSlots, grimoireSlots, banish, skip, reroll }` · `recordStat(player, key: string, amount)` (quest counters) · `grantRunRewards(player, summary: RunSummary) -> RunSummary` (fills silverEarned/questsProgressed)
**DataService** (data): `getProfile(player) -> table?` · `waitForProfile(player, timeout) -> table?`

Key flows:
- Run start: RunManager waits for loadouts (SelectLoadout → ProgressionService) then calls `StatsService.resetRun`, `TraitService.applyClass`, CompanionService (via Bus.RunStarted), fires `Bus.RunStarted`.
- Kill: EnemyService fires `EnemyKilled` → LootService drops XP/coins (elites: chest) → pickup calls `StatsService.addXp` → level up fires `PlayerLeveledUp` → CardService sends `CardOffer` (pauses nothing; calls `RunManager.setInvulnerable(player, 8)` + `setSlow(player, 0.5, 8)`) and TraitService grows the trait at 10/20/30. Companion cards come from `CompanionService.getCardOptions` (~1 in 4).
- Contact damage: RunManager queries EnemyService around each player at 15 Hz and calls its own `damagePlayer`.
- Quests: every domain calls `ProgressionService.recordStat(player, key, n)` with keys listed in `shared/Config/Quests.luau` (data domain publishes the key list in its dossier).
- End: RunManager builds a `RunSummary` per player → `ProgressionService.grantRunRewards` → sends `RunSummary` remote.

## 5. Bus events

See `server/Bus.luau` (arguments documented there).

## 6. Remotes and payloads (server → client unless marked C→S)

| Remote | Owner | Payload |
| --- | --- | --- |
| EnemySnapshot (U) | run | buffer, `EnemyCodec` |
| RunState | run | `{ phase: RunPhase, timeLeft: number, worldId, tier, stage, bossRevealed: boolean, bossPosition: Vector3?, finalWaveSeconds: number }` — on change and every 1 s |
| Announce | run | `{ kind: string, text: LocalizedText, duration: number }` |
| PlayerVitals | run | `{ hp, maxHp, shield, downed: boolean, downedTimeLeft: number?, ghost: boolean, reviveProgress: number? }` — on change, max 10/s; also team vitals: `{ team = { [userId]: { hp, maxHp, downed, ghost } } }` |
| BossState | run | `{ bossId, name: LocalizedText, hpFrac, phase, position: Vector3, telegraph: { kind, position: Vector3, radius, at: number }? }` |
| RunSummary | run | `Types.RunSummary` (after ProgressionService) |
| Replay (C→S) | run | `()` |
| PlayerProgress | combat | `{ level, xp, xpNext }` |
| Build | combat | `{ weapons = {{id, level}}, grimoires = {{id, level}}, items = {{id, count}}, stats: StatBlock, banish, skip, reroll, weaponSlots, grimoireSlots }` |
| CardOffer | combat | `{ offerId: number, cards: {Card}, expiresIn: number, banish, skip, reroll }`; `{ offerId, closed = true }` when resolved |
| CardChoice (C→S) | combat | `(offerId: number, action: "pick"|"ban"|"skip"|"reroll", index: number?)` |
| WeaponFx (U) | combat | buffer, `WeaponFxCodec` |
| LootSnapshot (U) | loot | buffer, `LootCodec` |
| Coins | loot | `{ coins: number }` |
| ShrineState | loot | `{ shrines = {{ id, kind, position: Vector3, state, progress, chargers }} }` |
| ShrineOffer / ShrineChoice (C→S) | loot | `{ offerId, choices = {{ stat, value, rarity }} }` / `(offerId, index)` |
| CompanionState | companion | `{ line, stage, level, name: LocalizedText, ultimateCharge: number, stunned: boolean, techs = {{ id, level }} }` |
| CompanionSnapshot (U) | companion | buffer (companion-owned format) |
| CompanionUltimate (C→S) | companion | `()` |
| Ping (C→S) / PingBroadcast | ui | `(kind: string, position: Vector3)` / `{ userId, kind, position }` |
| Profile | data | `{ silver, questTokens, unlocks = { Class = {[id]=true}, ... }, quests = {{id, progress, goal, completed}}, mastery = {[classId]=n}, bond = {[line]=n}, cosmetics, equipped, settings, loadout = { classId, companionId } }` |
| SelectLoadout (C→S) | data | `(classId: string, companionId: string)` |
| EquipCosmetic (C→S) | data | `(slot: string, cosmeticId: string?)` |
| UpdateSettings (C→S) | data | `(settings: { keepHat: boolean?, colorblind: boolean?, reduceFlashes: boolean?, textScale: number? })` |

Unreliable payloads must stay under 900 bytes per packet (chunk them like `EnemyCodec`).

## 7. Single-place test flow (until the lobby place exists)

Join → `LoadoutUI` (class + companion from unlocked ones) → `SelectLoadout` → RunManager starts the run when every player in the server has a loadout (solo: immediately) → run → `EndScreen` → `Replay` restarts the same world/tier. MatchService (lobby → run teleport, MemoryStore handoff, profile release) is written but only active when `Config.Run.UseLobbyPlace = true`.

## 8. Definition of done (per domain)

1. `docs/dossier/NN-*.md` written first: every element with id, FR/EN name, numbers, and the vault notes it relies on.
2. Code implements that dossier and the APIs above. Config holds the numbers.
3. Every owned file compiles (loadstring check, see README) and passes the LihFolk Write hook with no errors.
4. Report: files, APIs exposed, assumptions, vault notes used, contract requests, known gaps.
