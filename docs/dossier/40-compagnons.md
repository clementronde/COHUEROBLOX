# 40 — Compagnons et capture (domaine companion, A05)

Réécrit le 5 nov. 2026 par l'agent A05 pour la v2 (`01-decisions-v2.md` §5, `docs/security/regles-v2.md` §3). **Remplace entièrement** la version v1 (6 lignées, évolutions, Ultime) : il n'y a plus d'évolution, un compagnon se gagne en **battant puis en capturant** une créature pendant une run.

Fichiers du domaine : `server/Services/CompanionService.luau`, `shared/Config/Companions.luau`, `shared/NetDefs/Companion.luau`, `client/Controllers/CompanionRenderer.luau`, ce dossier. Tous les nombres vivent dans `shared/Config/Companions.luau` ; ce document en est la référence.

## 0. En bref

1. Certains ennemis apparaissent en **variante capturable** (aura + icône, plus résistante). C'est **A03** qui décide lesquels et à quel taux, dans `EnemyService`.
2. Battue, la variante laisse une **cage au sol pendant 10 s**.
3. Un joueur qui reste **2 s dans la cage sans être touché** capture la créature, **à 100 %**. Pas de hasard, pas d'objet, rien de payant. Le Tamer capture **50 % plus vite** (2 s ÷ 1,5 ≈ 1,33 s).
4. La créature rejoint la **collection** du joueur, sauvée dans son profil (**A12**).
5. Avant une run, le joueur **équipe 1 compagnon** de sa collection (**2 pour le Tamer**). En run, le compagnon suit son joueur et attaque seul.
6. Pas d'évolution, pas de renommage. Chaque espèce a son attaque et 2 ou 3 cartes de technique (§5.2) ; la personnalisation (chapeaux, couleurs, auras, Robux, purement visuelle) avec A05-05.

## 1. Espèces

- **Id d'espèce = le champ `name` de l'ennemi dans `shared/Config/Enemies.luau`** (domaine run, A03). Exemple : `GoblinGrunt` quand A03 aura renommé les ennemis v2. Le numéro `kind` peut changer d'une version à l'autre, le `name` non : la collection stocke donc toujours le **nom**, jamais le numéro.
- **Capturables** : toutes les familles sauf les boss (`family ~= "Boss"` et `isBoss ~= true`). Ennemis de base, élites et mini-boss ont donc une variante capturable possible ; les boss non, au lancement.
- Une élite capturée donne **la même espèce** que sa version normale (pas de doublon « doré » au lancement).
- Nom affiché : `Enemies[kind].label` (anglais), le même que l'ennemi.
- Attaque : par défaut celle de sa **famille** (section 5). `Companions.Species[name]` peut la surcharger espèce par espèce (A05-03).

## 2. La cage

| Règle | Valeur (`Companions.Capture`) |
| --- | --- |
| Création | **Uniquement côté serveur**, quand `EnemyService` appelle `CompanionService.onCapturableDefeated` pour un ennemi marqué capturable **à son apparition** (jamais sur un `clearAll`, un changement de monde, une fin de run ou un dépop) |
| Durée de vie | `CageSeconds = 10` s après la mort. Le compte à rebours s'arrête pendant le gel du passage de niveau (`RunManager.isFrozen`, A04-v3) ; les compagnons et la barre de capture aussi, et `Bus.RunFrozen(false, s)` décale les minuteries « sonné » et « blocage après un coup » |
| Rayon « dedans » | `Radius = 6` studs, test 2D, plus une tolérance verticale de `VerticalTolerance = 6` studs entre les pieds du joueur et le sol de la cage |
| Durée de capture | `HoldSeconds = 2` s ; Tamer : `HoldSeconds ÷ Passives.Tamer.captureSpeed` (1,5) |
| Coop | **Une cage commune, une capture par joueur** : chaque joueur de la run peut capturer la créature dans la même cage, chacun avec sa propre barre. Personne ne vole la créature d'un coéquipier (recommandation A11 §3.3, à confirmer par Clément). La cage disparaît à 10 s, ou plus tôt si tous les joueurs de la run l'ont capturée |
| Plafond | `MaxPerRun = 5` captures par joueur et par run (anti-farm, à régler). Au-delà, la cage reste visible mais refuse avec un message |
| Cages simultanées | `MaxCages = 12` dans la run ; au-delà, la plus ancienne disparaît |

### 2.1 Progression (10 Hz, serveur)

À chaque tic, pour chaque joueur de la run, le serveur prend la cage la plus proche qu'il n'a pas encore capturée et dont il est dedans. La barre **avance** seulement si **toutes** ces conditions sont vraies :

- le joueur est actif (`RunManager.isActive` : ni à terre, ni fantôme) ;
- la phase de la run est une phase de jeu (`Companions.Capture.Phases`) ;
- il n'est pas en train de choisir une carte (`CardService.isChoosing`) : la barre **se met en pause** sans retomber ;
- il n'a pas pris de strike MovementGuard depuis le début de sa tentative (`MovementGuard.getRunStrikes` n'a pas bougé).

La barre **retombe à 0** si :

- **le joueur est touché** (voir 2.2) : état `Interrupted` (« OUCH! CAPTURE RESET »), puis nouvel essai possible après `InterruptLockout = 0,5` s s'il reste dans la cage ;
- il sort de la cage : état `Idle` ;
- il prend un strike MovementGuard, ou passe à terre ;
- la cage expire.

À `HoldSeconds`, la capture est accordée (section 3).

### 2.2 « Sans être touché »

Touché = **tout coup reçu** : contact, projectile, attaque de boss, **même bloqué** par l'invulnérabilité, l'esquive, le bouclier ou la parade (`regles-v2.md` §3.1.4). L'invulnérabilité ne doit pas aider à capturer.

- Source : `Bus.PlayerHit(player, source)`, tiré au début de `RunManager.damagePlayer`, **avant** invulnérabilité, parade, esquive et bouclier. Ajouté par A04 sur `claude/a04-v3` (commit 6d7f564, pas encore dans main le 5 nov.) ; CompanionService s'y branche dès qu'il existe.
- Repli tant qu'il n'est pas dans main : `Bus.PlayerDamaged` (ne voit que les coups qui font des dégâts : un coup bloqué n'interrompt pas encore la capture, trou connu).

### 2.3 Rien côté client

**Aucun remote n'accorde une créature, aucun remote ne démarre une capture.** Le client ne fait que rester dans la cage. Le bouton Capture du HUD mobile (A08) n'envoie rien au serveur : il peut être retiré ou servir d'indice visuel.

## 3. Collection et sauvegarde (A12)

### 3.1 Données dans le profil (proposition à A12)

```lua
profile.companions = {
	v = 1,
	owned = { [speciesId] = { n = number, at = number } }, -- n = nombre de captures, at = 1re capture (os.time)
	equipped = { speciesId?, speciesId? },                 -- emplacement 1, emplacement 2 (Tamer seulement)
	keys = { [captureKey] = number },                      -- idempotence : clé -> os.time, garder les 200 plus récentes
}
```

- `captureKey = "<JobId>:<runSerial>:<cageId>"`, construite par CompanionService. Elle est unique par serveur, par run et par cage ; comme elle est rangée dans le profil du joueur, elle identifie une capture par joueur.
- Une espèce déjà possédée peut être recapturée : `n` augmente (statistique, quêtes), rien d'autre. Elle compte dans le plafond de 5.
- Migration v1 → v2 : les anciennes lignées (`unlocks.Companion.Braise`…) n'existent plus comme espèces. A12 peut les supprimer ; CompanionService ignore tout id qui n'est pas une espèce capturable.
- Pas de compagnon de départ (collection vide à la première run) : **question pour Clément**, section 11.

### 3.2 API que A12 implémente dans `ProgressionService`

| Fonction | Rôle |
| --- | --- |
| `grantCapture(player, speciesId: string, captureKey: string) -> (result: "Granted" \| "AlreadyGranted" \| "Unavailable", isNew: boolean)` | Un seul `DataService.mutate` : si `keys[captureKey]` existe → `"AlreadyGranted"` sans rien changer ; sinon ajoute la clé, crée ou incrémente `owned[speciesId]`, puis `saveSoon`. Profil non modifiable (téléport, session perdue) → `"Unavailable"` : la capture est **refusée**, jamais mise de côté. `isNew` = première capture de cette espèce. Peut céder (yield) : CompanionService l'appelle dans un thread à part |
| `getCompanionLoadout(player) -> { string }` | Les espèces équipées, déjà validées : possédées, capturables (`CompanionService.isSpecies`), au plus `CompanionService.slotsFor(classId)` |
| `hasCompanion(player, speciesId) -> boolean` | Pour l'écran de collection et `SelectLoadout` |

Et côté remotes (A12) :

- `SelectLoadout(classId, companionId, companionId2?)` : chaque id doit être possédé ; `companionId2` accepté seulement si `CompanionService.slotsFor(classId) == 2` ; pas deux fois la même espèce. Même contrôle à l'arrivée sur le serveur de run (`MatchService.applyArrivalLoadout`).
- Payload `Profile` : ajouter `companions = { owned, equipped }` (pas `keys`) pour l'écran de collection (A09-07).
- Clés de quêtes (section 9) à ajouter à `Config/Quests`.

### 3.3 Repli (Studio, A12 pas encore livré)

Si `ProgressionService.grantCapture` n'existe pas, CompanionService garde la collection **en mémoire** (perdue au départ du joueur) et avertit une fois dans la sortie. Si `getCompanionLoadout` n'existe pas, il lit le 2e retour de `ProgressionService.getLoadout` (un seul compagnon), s'il désigne une espèce, sinon la dernière espèce capturée en mémoire.

## 4. Équipement

- Emplacements : `CompanionService.slotsFor(classId)` = `Weapons.Passives[classId].companionSlots` ou 1. Tamer = 2. La classe vient toujours du serveur (`RunManager.getLoadout`), jamais d'un attribut client.
- Au `Bus.RunStarted` (et pour un joueur qui arrive en cours de run, via `CompanionService.ensure`), CompanionService crée un compagnon par espèce équipée.
- Capturer pendant la run **n'ajoute pas** de compagnon à la run en cours : la créature attend dans la collection. (Exception de test : avec le repli en mémoire de 3.3, un joueur sans aucun compagnon reçoit tout de suite sa capture, pour voir le suivi en Studio.)

## 5. En run : suivi et attaque

- **Ne peut pas mourir, ne prend pas de dégâts.** Propriétaire à terre : compagnon **sonné 5 s**, puis il garde le joueur à terre en attaquant autour de lui. Relevé : sonné annulé. Mort définitive : sonné jusqu'à la fin de la run.
- **Suivi** : 5 studs derrière le joueur, 2,5 studs sur le côté (gauche pour l'emplacement 1, droite pour le 2), 24 studs/s, téléporté derrière le joueur au-delà de 60 studs. S'écarte au plus de 14 studs de ce point pour aller frapper une cible.
- **Cible** : l'ennemi le plus proche à portée ; en coop, une cible déjà prise par un autre compagnon est évitée s'il en existe une autre.
- **Kills crédités au propriétaire** : `EnemyService.damage(id, n, owner)`. XP, butin, KO et quêtes vont au joueur.

### 5.1 Attaque par famille (défaut, `Companions.Families`)

| Famille | Attaque | Dégâts | Intervalle | Portée | Zone | Effet |
| --- | --- | --- | --- | --- | --- | --- |
| `Swarm` | Morsure (va au contact) | 8 | 0,9 s | 5 | — | — |
| `Jumper` | Bond | 14 | 1,6 s | 14 | 4 | — |
| `Shooter` | Tir | 7 | 1,1 s | 24 | — | — |
| `Armored` | Charge | 10 | 1,3 s | 5 | 3 | Recul 4 studs |
| `MiniBoss` | Coup lourd | 24 | 1,4 s | 8 | 6 | Étourdit 0,5 s |

**Dégâts finaux** = base × (1 + 0,5 × `Damage` du propriétaire) × (1 + 0,04 × (niveau de run − 1)) × (1 + Friandise Puissance) × (1 + bonus Tamer 0,2) × (1 + techniques Power de ce compagnon). Vitesse d'attaque et portée : 1 + Friandise + technique. Le niveau de run remplace l'ancienne évolution : le compagnon grandit avec son joueur sans changer de forme.

### 5.2 Attaque et techniques par espèce (A05-03, fait le 5 nov.)

Chaque espèce v2 a sa propre attaque et 2 ou 3 **techniques** (`Companions.Species[nom]`). Une technique est une carte de niveau : « apprendre » (`CompanionTech`, rareté Rare) puis « améliorer » (`CompanionTechUp`, Commune), jusqu'au niveau 3. Elle ne touche que le compagnon de cette espèce. `getCardOptions` propose au plus 2 techniques des compagnons équipés, le reste en Friandises ; `applyCard` revalide tout (espèce équipée, niveau attendu, plafond).

Genres de technique (`TechDef.stat`) : `Power` / `Haste` / `Reach` (+ % pour ce compagnon), `Splash` (studs de zone en plus), `Multishot` (ennemis en plus touchés à 60 % des dégâts, `TechShare`), `Status` (ajoute ou remplace un statut du même genre), `Pulse` (onde autour du compagnon toutes les N s).

Valeurs par niveau : Power 15 / 25 / 40 %, Haste 12 / 20 / 30 %, Reach 15 / 25 / 40 % ; les autres sont dans le tableau.

| Espèce | Attaque (dégâts / intervalle / portée, zone) | DPS de base | Techniques (niveaux 1 / 2 / 3) |
| --- | --- | --- | --- |
| GoblinGrunt | Ladle Bonk 9 / 1,0 s / 5, mêlée | 9 | Big Ladle (zone 2 / 3 / 4) · Soup's On (Haste) |
| GoblinArcher | Slow Arrow 8 / 1,2 s / 26 | 6,7 | Split Shot (+1 / 2 / 3 cibles) · Sharp Tips (Power) · Eagle Eye (Reach) |
| GoblinShaman | Spirit Bolt 6 / 1,2 s / 20, ralenti ×0,85 | 5 | Hex (ralenti ×0,75 / 0,65 / 0,55, 2 s) · Spirit Circle (onde r 8 toutes les 4 s : 10 / 14 / 18) |
| GoblinBomber | Fizzle Bomb 16 / 2,2 s / 14, zone 5 | 7,3 en zone | Bigger Boom (Reach) · Short Fuse (Haste) · Sticky Tar (ralenti ×0,8 / 0,7 / 0,6) |
| GlandGrincheux | Grumpy Headbutt 8 / 0,9 s / 5, mêlée, recul 2 | 8,9 | Grudge (Power) · Bonk (étourdit 0,3 / 0,4 / 0,5 s) |
| ChampignonSauteur | Spore Pounce 14 / 1,6 s / 14, zone 4 | 8,8 en zone | Spore Cloud (poison 3 / 4 / 6 par s, 3 s) · Bouncy Cap (Haste) |
| HibouPlongeur (vole) | Feather Dart 7 / 1,0 s / 24 | 7 | Feather Storm (+1 / 2 / 3 cibles) · Night Eyes (Reach) |
| ZombieShambler | Grabby Swipe 10 / 1,1 s / 5, mêlée | 9,1 | Rotten Touch (poison 2 / 3 / 4) · Shamble Faster (Haste) |
| ZombieRunner | Grand Jete 12 / 1,5 s / 16, zone 4 | 8 en zone | Pirouette (zone +1,5 / 2,5 / 3,5) · Encore (Haste) · Prima Ballerina (Power) |
| ZombieGravedigger | Dirt Clod 9 / 1,4 s / 22, zone 2,5 | 6,4 en zone | Fresh Grave (ralenti ×0,7 / 0,6 / 0,5) · Bigger Shovel (Power) |
| ZombieBloater | Belly Bump 9 / 1,2 s / 5, mêlée, zone 3 | 7,5 en zone | Stink Cloud (onde r 7 toutes les 3 s : 6 / 9 / 12) · Gassy (poison 2 / 3 / 4) |
| GhostWisp (vole) | Spooky Nip 7 / 0,75 s / 5, mêlée | 9,3 | Chill Touch (ralenti ×0,8 / 0,7 / 0,6) · Flicker (Haste) |
| GhostPoltergeist (vole) | Book Toss 6 / 1,3 s / 22, +1 cible | 4,6 + 2,8 | Homework Pile (+1 / 2 / 3 cibles) · Heavy Dictionary (étourdit 0,25 / 0,35 / 0,5 s) |
| GhostBanshee (vole) | Wail 5 / 1,4 s / 12, zone 6, ralenti ×0,75 | 3,6 en grande zone | Shriek (Power) · Haunting Echo (Reach) |
| GhostHallMonitor (vole) | Whistle Blast 7 / 1,3 s / 16, zone 3, étourdit 0,2 s | 5,4 en zone | Detention (étourdit 0,35 / 0,5 / 0,7 s) · Hall Pass (Haste) |
| HauntedArmor | Pointer Lance 11 / 1,3 s / 5, mêlée, zone 3, recul 4 | 8,5 en zone | Iron Charge (Power) · Ruler Sweep (zone +1,5 / 2,5 / 3,5) · Shove (recul 6 / 8 / 10) |

Les mini-boss capturables (SoucheGeante, ChameauTirelire, PionSpectral) gardent l'attaque `MiniBoss` de la famille, sans technique au lancement.

**Équilibrage** : environ 9 DPS en mêlée sur une cible, 7 à distance (plus sûr), 4 à 6 en zone ou avec un statut. Une technique au niveau 3 vaut à peu près +35 à +45 % de valeur. Rien n'a été mesuré en jeu : à régler après les premiers essais.

**Textes** : titres et descriptions en anglais, pris dans la config. Une amélioration s'affiche « Lv 2: +15% -> +25% damage ». `CompanionState.techs` liste `{ id, species, name, level, maxLevel }`. Clé de quête `CompanionTechsLearned` (1 par technique apprise).

### 5.3 Friandises

`getCardOptions` complète avec les **Friandises** génériques (cumulables 10 fois, Commune 60 % / Rare 30 % / Épique 10 %), qui touchent tous les compagnons du joueur :

| id | Nom (EN) | Commune / Rare / Épique |
| --- | --- | --- |
| `TreatPower` | Hearty Biscuit | +8 % / +12 % / +18 % dégâts |
| `TreatHaste` | Fizzy Candy | +6 % / +9 % / +14 % vitesse d'attaque |
| `TreatReach` | Spyglass Berry | +8 % / +12 % / +18 % portée et zones |



### 5.4 Pas d'Ultime

Les décisions v2 ne gardent ni évolution ni Ultime. Le remote `CompanionUltimate` (déclaré dans `shared/Net`, domaine lead) n'est plus écouté ; `CompanionState.ultimateCharge` vaut toujours 0. **Question pour Clément** (section 11).

## 6. API de CompanionService

### 6.1 Pour A03 (`EnemyService`)

| Fonction | Quand l'appeler |
| --- | --- |
| `CompanionService.isSpecies(kind: number) -> boolean` | Au spawn, avant de marquer un ennemi capturable : vrai si l'espèce existe dans `Config/Enemies` et n'est pas un boss. Ne pas marquer si faux |
| `CompanionService.onCapturableDefeated(kind: number, x: number, z: number, killer: Player?) -> number?` | **Une fois**, dans `EnemyService.damage`, quand un ennemi marqué capturable **meurt sous les coups** (juste après `Bus.EnemyKilled`). Jamais pour `clearAll`, `clearNonBoss`, `_remove`, dépop ou fin de run. Renvoie l'id de cage (ou nil si refusée : phase hors jeu, espèce inconnue). Ne cède jamais |

Le reste est à A03 : taux d'apparition, PV en plus (« plus résistante »), marquage serveur au spawn (jamais lu chez le client), aura et icône sur l'ennemi (`ArtLibrary.cloneCaptureMarker`, bit « capturable » dans `EnemyCodec`). Appel conseillé : `Registry.find("CompanionService")` dans la fonction, protégé par `pcall`.

### 6.2 Pour A12 (`ProgressionService`, `DataService`)

| Fonction | Rôle |
| --- | --- |
| `CompanionService.slotsFor(classId: string) -> number` | 1, ou 2 pour le Tamer (règle unique, lue dans `Config/Weapons.Passives`) |
| `CompanionService.isSpecies(speciesId: string \| number) -> boolean` | Valider un id d'espèce (nom) ou un `kind` |
| `CompanionService.speciesName(speciesId: string) -> LocalizedText?` | Nom affichable |

Et CompanionService appelle chez A12 : `grantCapture`, `getCompanionLoadout` (section 3.2), `recordStat` (section 9).

### 6.3 Pour les autres

| Fonction | Pour | Rôle |
| --- | --- | --- |
| `getCardOptions(player) -> {Card}` · `applyCard(player, card)` | CardService (A04) | Contrat inchangé |
| `getState(player) -> { line, stage, level }?` | RunManager (résumé) | `line` = espèce du 1er compagnon, `stage` = 1 toujours |
| `ensure(player)` | RunManager | Arrivée en cours de run |
| `chargeUltimate(player, n)` | autels, objets | Gardé pour le contrat ; sans effet (pas d'Ultime) |
| `getCages() -> {{ id, species, x, z, expiresAt }}` | Minimap (A08) | Cages vivantes |
| `getRunCaptures(player) -> { string }` | RunManager (`RunSummary.captured`) | Espèces capturées pendant la run, dans l'ordre |

## 7. Remotes (`shared/NetDefs/Companion.luau`)

| Remote | Sens | Payload |
| --- | --- | --- |
| `CaptureState` | serveur → le joueur concerné | `{ state = "Idle" \| "Available" \| "Capturing" \| "Interrupted" \| "Captured" \| "Refused", progress: 0..1, holdSeconds: number, name: LocalizedText?, isNew: boolean?, reason: string? }` — forme demandée par `60-ui-ux.md` et lue par `CaptureUI`, plus `Refused`, `isNew` et `reason`. Au plus 10/s, envoyé seulement quand l'état ou la barre (au 1/10) change. `reason` (Refused) : `"Cap"` (5 captures) ou `"Unavailable"` (profil non modifiable). `Available` : une cage à capturer à moins de `Capture.AvailableRadius = 18` studs, hors de la cage (bouton Capture du HUD, sans panneau). `Interrupted`, `Captured` et `Refused` restent au moins `StickySeconds = 1,5` s avant de céder la place à `Available` ou `Idle` |
| `CageState` | serveur → tous | `{ cages = {{ id, species, kind, x, y, z, expiresIn, done = { userId } }} }` — à chaque création, capture ou disparition |
| `CompanionState` (existant) | serveur → propriétaire | `{ line, stage = 1, level, name, ultimateCharge = 0, stunned, techs = {}, companions = {{ species, name, slot }} }` |
| `CompanionSnapshot` (existant, non fiable) | serveur → tous | 10 Hz. En-tête 5 octets (`tick u32`, `count u8`) + 25 octets par compagnon : `userId f64`, `slot u8`, `kind u8`, `x/y/z i16` au 1/4 de stud, `yaw u8`, `flags u8` (bit 0 sonné), `evSeq u8`, `evKind u8`, `evX/evZ i16`, `evRadius u8`. 35 compagnons par paquet ≤ 900 octets |

## 8. Rendu (client) et gabarits visuels

Règle « rien n'est construit par script » (`01-decisions-v2.md` §12) : `CompanionRenderer` **clone des gabarits** de `ReplicatedStorage.Assets` (recherche par nom, `ArtLibrary.find`) et, si un gabarit manque, **ne fabrique rien** : il l'écrit une fois dans la sortie et n'affiche rien à la place.

| Gabarit (nom exact) | Rangé dans | Utilisé pour | Si absent |
| --- | --- | --- | --- |
| `Companion_<espèce>` | `Assets.Creatures` | Le compagnon (maille unique, mise à la hauteur de l'ennemi × 0,8) | Repli sur `Enemy_<espèce>` (la maille de l'ennemi) |
| `Enemy_<espèce>` | `Assets.Creatures` (déjà fourni par A01/A03) | Repli du compagnon | Compagnon invisible + avertissement |
| `FX_CaptureCage` | `Assets.FX` | La cage au sol (modèle posé tel quel : à construire à 12 studs de large, rayon 6) | Cage invisible ; la barre de CaptureUI reste |
| `FX_CaptureSuccess` | `Assets.FX` | Éclat de réussite, 1,5 s | Rien |
| `FX_CompanionStun` | `Assets.FX` | Étoiles au-dessus d'un compagnon sonné | Rien |
| `FX_CompanionHit` | `Assets.FX` | Impact d'une attaque (petite pièce, pool de 24) | Rien |

La cage clignote (transparence) pendant ses 3 dernières secondes. Le compagnon sautille (procédural, aucune Instance créée) et s'oriente vers sa cible.

### 8.1 Mode lobby (client seul, fait le 5 nov. ; `65-lobby.md` §10)

Hors run, `CompanionRenderer` affiche la collection du joueur local, sans rien demander au serveur ni lui envoyer :

- **Suiveurs** : les espèces de `Profile.companions.equipped` (1, ou 2 pour le Tamer) suivent le joueur local comme en run (`Companions.Follow` : 5 studs derrière, 2,5 sur le côté, 24 studs/s, téléportés au-delà de 60 studs).
- **Enclos** : le reste de `Profile.companions.owned` (au plus `Lobby.MaxPenPets = 12`, les plus récentes d'abord) se promène dans l'objet qui porte `LobbyRole = "CritterPen"` (`Workspace.HubbubVillage`). Zone de promenade : la Part `CritterRoam` de l'enclos si elle existe, sinon la Part `Meadow`, sinon la boîte de l'enclos, moins 3 studs de bord. Trajets à 6 studs/s, pauses de 1 à 4 s. Joueur à plus de 120 studs de l'enclos : plus rien ne bouge.
- **Qui le voit** : chacun ne voit que les siens (positions locales). Les compagnons équipés des autres joueurs ne sont pas visibles au lobby : il faudrait que le serveur les publie (par exemple un attribut joueur), à décider plus tard.
- **En run ou pas** : l'attribut joueur `InRun` s'il existe (contract request de `65-lobby.md` §10 n° 4), sinon la phase de `RunState` (`Capture.Phases`), et dans tous les cas « en run » dès que le snapshot serveur contient un compagnon du joueur local. En run, les créatures du lobby sont détruites.
- Mêmes gabarits qu'en run (`Companion_<espèce>`, repli `Enemy_<espèce>`) ; rien n'est construit.

## 9. Clés de quêtes

`ProgressionService.recordStat(player, key, n)` : `CompanionsCaptured` (1 par capture), `CompanionNewSpecies` (1 par nouvelle espèce), `CompanionKills` (n), `CompanionTreats` (1). `CompanionTechsLearned` (1 par technique apprise, §5.2). Les clés v1 `CompanionEvolved`, `CompanionStage3`, `UltimatesUsed` ne sont plus envoyées.

## 10. Contract requests

| Pour | Demande |
| --- | --- |
| Lead + A04 | ~~`Bus.PlayerHit`~~ : fait sur `claude/a04-v3` (6d7f564), à fusionner |
| A04 | ~~`RunManager.isFrozen()`~~ et `Bus.RunFrozen` : faits sur `claude/a04-v3` (6d7f564), à fusionner |
| A03 (`EnemyService`) | Appeler `isSpecies` au spawn et `onCapturableDefeated` à la mort d'un capturable (6.1) |
| A12 (`ProgressionService`) | `grantCapture`, `getCompanionLoadout`, `hasCompanion`, `profile.companions`, `SelectLoadout` à 2 compagnons, payload `Profile`, clés de quêtes (sections 3 et 9) |
| A08 (`CaptureUI`) | Gérer l'état `Refused` (`reason = "Cap"` : « Collection full for this run », `"Unavailable"` : « Can't save right now ») et `isNew` (« NEW! ») ; le bouton Capture mobile n'envoie rien |
| A08 (`Minimap`) | Les cages via le remote `CageState` ou `CompanionService.getCages` |
| Ironix (combat, `RunManager`) | `RunSummary.captured = CompanionService.getRunCaptures(player)` (demandé par `60-ui-ux.md`) |
| Lead (`ARCHITECTURE.md` §3, §4, §6) | Remplacer les lignées par « espèce = `Enemies[].name` », ajouter les APIs de 6.1 et 6.2 et les remotes de la section 7 |

## 11. Questions pour Clément

1. **Compagnon de départ** : collection vide à la première run (on capture son premier compagnon pendant la run) ou une espèce offerte ? Par défaut : collection vide.
2. **Ultime** : on le supprime (par défaut) ou on garde une jauge et un gros coup par espèce ?
3. **Coop** : une capture par joueur dans la même cage (par défaut, recommandé par A11) ou « le premier qui tient 2 s la prend » ?
4. **Tamer** : « 50 % plus rapide » = 1,33 s (par défaut, `captureSpeed = 1,5`) ; `regles-v2.md` disait 1 s (= 2× plus rapide).

## 12. Sources

- `01-decisions-v2.md` §3 (Tamer), §5 (capture), §12 (rien construit par script).
- `docs/security/regles-v2.md` §0 et §3 (cage serveur, touché même bloqué, idempotence, plafond, aucun remote).
- `docs/dossier/13-ennemis-boss.md` (roster v2, noms de mailles `Enemy_<nom>`, marqueur de capture d'A01).
- Vault : *Pet Hatching and Following End to End* (suivi client, parts ancrées sans requête), *Snapshot Interpolation for Custom Replication*, *Paid Random Items and Odds Disclosure in Practice* (capture sans hasard ni paiement : hors du champ des objets aléatoires payants).

## 13. Tests en Studio (`Companions.Debug`, jamais en jeu publié)

- `TestSpecies` : un joueur sans compagnon valide reçoit cette espèce, pour voir le suivi.
- `CageEveryNthKill = 15` : tant qu'A03 n'appelle pas `onCapturableDefeated`, un ennemi non boss sur 15 laisse une cage. Coupé dès le premier appel d'A03.
