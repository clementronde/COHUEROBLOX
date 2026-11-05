# 70 — Données, méta-progression, quêtes, monétisation, lobby ↔ run

Domaine **data**. Fichiers : `server/Services/{DataService,ProgressionService,MonetizationService,MatchService}.luau`, `shared/Config/{Progression,Quests,Cosmetics,Products}.luau`, `shared/NetDefs/Data.luau`.
Sources de conception : dossier 00, sections 6.3, 7.3, 11, 12.1, 12.5, 14.1. Toutes les valeurs ci-dessous vivent dans la config (`shared/Config/*`) : ce document les décrit, la config fait foi.

Principe : tout ce qui donne de la puissance se gagne en jouant. Le serveur calcule toute l'économie ; le client n'envoie que des demandes validées (type, plage, propriété, solde), limitées en débit.

---

## 1. Profil joueur — schéma 2 (v2, A12-01)

Une clé par joueur : `User_<UserId>` dans le DataStore `PlayerData_v1` (≤ 50 caractères, motif statique `{UserId}` pour les demandes d'effacement). En Studio, l'attribut `ServerStorage.TestProfileKey = "nom"` (≤ 20 car.) joue sur `TEST_<nom>_<UserId>` : les tests ne touchent jamais la vraie sauvegarde, et les classements ne sont pas écrits.

L'enregistrement stocké :

```
{ SaveVersion: number, SavedAt: number, Session: { Token, JobId, PlaceId, ExpiresAt, Studio? }?, Data: Profil }
```

Le **Profil** (`Data`), valeurs par défaut d'un nouveau joueur (nouvelle table à chaque fois, jamais un modèle partagé) :

| Champ | Type | Défaut | Rôle |
| --- | --- | --- | --- |
| `schema` | number | 2 | Version de schéma (section 2) |
| `createdAt` | number | `os.time()` | Première connexion (bucket de retour J1/J8-28) |
| `lastJoinAt` | number | `os.time()` | Dernière connexion |
| `sessions` | number | 0 | Nombre de sessions |
| `playSeconds` | number | 0 | Temps de jeu cumulé |
| `silver` | number | 0 | Étoiles d'argent (méta) |
| `questTokens` | number | 0 | Jetons de quête |
| `silverEarnedTotal` | number | 0 | Argent gagné à vie (analytics) |
| `stats` | `{[clé]: number}` | `{}` | Compteurs à vie (somme) et records (max). **Seule source** de progression des quêtes |
| `questsDone` | `{[questId]: number}` | `{}` | Quêtes terminées → horodatage. Les récompenses sont données une seule fois, au passage à « terminé » |
| `unlocks` | `{ Weapon, Grimoire, Item, Companion: {[id]: true} }` | tables vides | Déblocages **achetés** (argent) ou **gagnés** (œufs). Les déblocages gratuits et par quête sont dérivés (section 5), pas stockés |
| `shop` | `{ grimoireSlots, banish, skip, reroll: number }` | tous 0 | Niveaux achetés dans la boutique d'argent |
| `mastery` | `{[classId]: number}` | `{}` | Niveau de maîtrise 1-20 (dérivé de `masteryXp`, stocké pour les lecteurs) |
| `masteryXp` | `{[classId]: number}` | `{}` | XP de maîtrise totale |
| `bond` | `{[line]: number}` | `{}` | Niveau de Lien 1-30 (lu par CompanionService) |
| `bondXp` | `{[line]: number}` | `{}` | XP de Lien totale |
| `bondEggs` | `{[line]: true}` | `{}` | Œuf du niveau 10 déjà donné pour cette lignée |
| `companionStartTech` | `{[line]: techId}` | `{}` | Technique de départ choisie (validée par le niveau de Lien, lue par CompanionService) |
| `eggs` | number | 0 | Œufs gratuits non éclos |
| `eggsHatched` | number | 0 | Compteur |
| `cosmetics` | `{[cosmeticId]: true}` | `{}` | Cosmétiques possédés (hors gratuits, pass et saison, dérivés) |
| `equipped` | `{[slot]: cosmeticId}` | `{}` | Équipement cosmétique |
| `settings` | `{ keepHat, colorblind, reduceFlashes: boolean, textScale: number }` | `false, false, false, 1` | Réglages |
| `loadout` | `{ classId, companionId }` | `Knight`, `""` | Dernier choix (companionId = 1re espèce équipée, compat) |
| `companions` | `{ v, owned, equipped, keys }` | `1, {}, {}, {}` | Collection capturée (section 5, Compagnons v2) |
| `seasons` | `{[seasonId]: number}` | `{}` | XP de pass saisonnier (section 9) |
| `weekly` | `{ week, done, bestSeconds, everDone }` | `-1, false, 0, false` | Défi hebdo (section 10) |
| `boards` | `{ week, kills, bestFinalWave, lastRunKey, best, weekBest, quarantined }` | `-1, 0, 0, "", {}, {}, {}` | Relevés du classement KO en une run (section 13) ; `kills`/`bestFinalWave` : compteurs v1 conservés |
| `receipts` | `{[PurchaseId]: number}` | `{}` | Marqueurs de reçus traités (même document que l'objet accordé) |
| `receiptOrder` | `{string}` | `{}` | Ordre d'arrivée, pour garder les 100 plus récents |
| `purchaseLog` | `{{k, r, t}}` | `{}` | Journal d'achats (clé produit, Robux payés, date), 50 derniers |
| `vipRoomId` | string | `""` | GUID du salon VIP réservé (section 9) |
| `flags` | `{ boardBanned: boolean }` | `false` | Retrait des classements (outil admin) |

Règles de forme (vault « Data Schema Design and Migrations ») : tableaux denses uniquement (`receiptOrder`, `purchaseLog`), tout le reste en dictionnaires à clés texte ; aucun type moteur (Vector3, Color3) ; nombres bornés (pas d'`inf`/`nan`) ; taille mesurée par `#HttpService:JSONEncode(profil)`, avertissement au-delà de 200 000 caractères (limite 4 194 304). Estimation : ~160 stats × 30 o + 160 quêtes × 25 o + 100 reçus × 45 o ≈ 14 Ko.

## 2. Migrations

- `schema` entier sur chaque profil, `CURRENT_SCHEMA = 2` dans `DataService`. **Étape 1 → 2** (A12-01) : `loadout` repasse à une classe v2 (défaut `Knight` si la classe v1 est inconnue) sans compagnon, `companions` créé ; maîtrise, Lien, `unlocks.Companion` et cosmétiques v1 restent dans le profil, ignorés. Un serveur v1 refusera un profil v2 : publier la place de run avant le lobby.
- Chaîne d'étapes `STEPS[n]` (n → n+1) : ordonnées, déterministes, sans `yield`, jamais modifiées après publication ; on ajoute une étape.
- **Schéma plus récent que le serveur → chargement refusé** (statut `failed`, rien n'est écrit, le joueur est renvoyé avec un message). Indispensable avec deux places publiées séparément et les mises à jour progressives.
- Champs **ajoutés** sans changement de structure : `reconcile` les remplit au chargement sans jamais écraser.
- Renommer/déplacer/supprimer un champ : étape de migration, en deux versions (« élargir puis contracter »).
- **Champs inconnus préservés** : le serveur ne supprime jamais une clé qu'il ne connaît pas.
- La migration tourne dans le chemin de chargement ; la prochaine sauvegarde normale écrit la version migrée.
- Lobby et run publiés **ensemble**, la place de run d'abord (côté qui reçoit).

## 3. Verrou de session, sauvegardes, budgets

Choix : **module maison** (pas de bibliothèque : aucune installation réseau, et besoin de contrôle sur les reçus et la libération avant téléportation). Il reprend le schéma du vault « Session Locking and Profile Libraries » : bail (`lease`) + jeton (`fencing token`) écrits et vérifiés dans le **même `UpdateAsync`** que les données.

| Valeur | Choix | Justification (vault) |
| --- | --- | --- |
| Bail (`LeaseSeconds`) | **90 s** | Plage 30-90 s du dossier 12.1 ; jamais < 30 s (décalage d'horloge) |
| Sauvegarde auto | **30 s** + 0-5 s de gigue, décalage initial aléatoire par joueur | « autosave < bail, renouveler au tiers du bail ». Le dossier 00 disait 60 s : avec un bail de 90 s, 60 s ne laisse qu'un essai de marge ; 30 s renouvelle au tiers. |
| « Sauvegarder bientôt » | min 2 s, sinon 8 s depuis la dernière écriture | Après achat boutique / quête / récompense de run |
| Prise du verrou | réessais avec attente `min(8, n×1,5) + aléa` ; si **verrouillé**, on réessaie jusqu'à **100 s** (bail + marge) en prévenant le joueur ; si **erreur**, 6 essais | Arrivée après une téléportation dont la source n'a pas libéré |
| Sauvegarde de départ | 4 essais, recul exponentiel avec gigue (1 → 8 s) | — |
| `BindToClose` | sauvegardes **en parallèle**, attente des sauvegardes en cours (y compris celles de `PlayerRemoving`) jusqu'à **25 s** sur les 30 s du moteur ; en Studio, pas d'attente | « Saving Correctly - Autosave and BindToClose » |

Comportements :
- Chargement : `ready` (jouer) / `locked` (attente puis renvoi « tes données se sauvegardent encore ailleurs, reviens dans une minute ») / `failed` (renvoi, **rien n'est jamais écrit**) / `left`. Un `nil` après une erreur n'est **jamais** traité comme un nouveau joueur : seule une clé absente (ou un enregistrement sans `Data`) l'est.
- Chaque sauvegarde : copie profonde du profil (instantané cohérent), puis `UpdateAsync` qui refuse d'écrire si le jeton n'est plus le nôtre → état `lost`, plus aucune écriture, message au joueur. Une seule écriture à la fois par profil.
- Bail expiré mais jeton toujours à nous (panne du backend) : écriture acceptée.
- Studio : un bail écrit depuis Studio (`Studio = true`) peut être repris par une autre session Studio (piège « 90 s » du vault) ; les serveurs live ne l'honorent jamais comme reprise.
- `UpdateAsync` repasse `keyInfo:GetUserIds()` et `GetMetadata()`, sinon ils sont effacés ; nouvelle clé → `{ UserId }`.
- Mutations : toujours synchrones (pas de `yield` entre deux changements liés), donc tout instantané est cohérent.

**Budget pour un serveur de 4 joueurs** (limites Roblox d'octobre 2026, vault « DataStore Fundamentals ») :
- Par serveur, standard : lecture 60 + 4×40 = **220/min**, écriture 60 + 4×40 = **220/min**. Sauvegarde auto 2/min/joueur = 8 `UpdateAsync` (8 lectures + 8 écritures) → **3,6 %**. Avec départs, libérations de téléportation et achats : < 10 %.
- Par serveur, ordonné : écriture 30 + 4×5 = **50/min**. Classements : 4 tableaux, écriture toutes les 120 s uniquement si changé → au plus 8 `UpdateAsync`/min = **16 %** (règle : rester sous 50 %). Lecture des tops : 4 pages de 50 toutes les 120 s par serveur → liste 5 + 2×4 = 13/min, on en utilise 2.
- Expérience : écriture 300 + 20×CCU/min ; nous consommons ≈ 2×CCU (+ classements ≈ 2×CCU) → ~20 % de la part CCU.
- Par clé : 4 Mo/min arrondis au Ko ; profil ≈ 14 Ko × 2/min ≈ 28 Ko/min (< 1 %).
- Stockage : 500 Mo + 1 Mo × utilisateurs à vie ; ≈ 14 Ko/joueur, très loin.

**Repli Studio sans accès API** : au démarrage, `DataService` fait un appel test (`GetAsync` d'une clé de sonde). En Studio, si l'appel échoue (pas de publication, accès API désactivé), toutes les données passent par un **magasin en mémoire** (même code de bail/jeton), avec un avertissement clair dans la console ; rien n'est écrit sur le vrai DataStore, les classements sont désactivés. En live, il n'y a **jamais** de repli : une erreur reste une erreur (réessais, puis renvoi du joueur). Même logique pour MemoryStore (MatchService) et les appels Marketplace.

## 4. Monnaies

| Monnaie | id | Gain | Usage |
| --- | --- | --- | --- |
| Pièces | (loot) | En run | Perdues en fin de run (domaine loot) |
| Étoiles d'argent | `silver` | Fin de run (ci-dessous), certaines quêtes | Boutique d'argent (section 6) |
| Jetons de quête | `questTokens` | Quêtes, défi hebdo, doublons d'œufs | Cosmétiques gratuits (section 8) |

Aucune monnaie n'est achetable en Robux. Argent par run (`Config.Progression.Silver`) :

| Tier | Base victoire | Base défaite (40 %, min 2) | Bonus par 30 s de Vague Finale |
| --- | --- | --- | --- |
| 1 | 10 | 4 | +2 |
| 2 | 25 | 10 | +5 |
| 3 | 60 | 24 | +12 |

Bonus de Vague Finale plafonné à 20 paliers (10 min). Plafond de sécurité par run = base victoire + 20 × bonus. Les valeurs du `RunSummary` sont bornées avant calcul. Une run ne rapporte qu'une fois (garde par numéro de run, posé à `Bus.RunStarted`).

## 5. Règles de déblocage

Ids : ARCHITECTURE section 3. Un déblocage est **dérivé** des quêtes terminées et de la config, ou **stocké** (achat en argent, œuf). `ProgressionService.isUnlocked(player, kind, id)`.

### Classes v2 (01-decisions-v2 §3, A12-01) — jamais vendues
| Classe | Déblocage | Quête | Condition (clé de stat, objectif) |
| --- | --- | --- | --- |
| Knight, Archer, Mage | Gratuit | — | — |
| Guardian | Quête | `Q_Guardian` | `DamageTaken` ≥ 50 000 |
| Rogue | Quête | `Q_Rogue` | `Kills` ≥ 5 000 |
| Cleric | Quête | `Q_Cleric` | `ShrinesCompleted` ≥ 25 |
| Barbarian | Quête | `Q_Barbarian` | `BossesDefeated` ≥ 5 |
| Tamer | Quête | `Q_Tamer` | `CompanionsCaptured` ≥ 10 |

Les ids v1 envoyés par l'UI (`Cornu`…) sont acceptés par `SelectLoadout` via les alias de `Config.Classes` (transition), stockés en v2. Les quêtes v1 `Q_Felyne`… `Q_Tentaculos`, `Q_Volt`, `Q_Givre`, `Q_Echo` sont retirées (leurs entrées de `questsDone` restent, ignorées).

### Armes (16)
- Gratuites (pool de départ, 6 pour la phase 0) : `HacheBoomerang`, `PlumesDards`, `CleTourelle`, `ToupieScie`, `BouleBowling`, `PistoletBulles`.
- Arme de départ d'une classe à débloquer : entre dans le pool quand la classe est débloquée (`GriffesEclair`, `PoingSeisme`, `NuageSpores`, `SouffleBraise`, `Meteorite`, `EclatsPrisme`, `FouetTentacule`).
- Boutique d'argent : `CerfVolantLaser` 150, `ParapluieBouclier` 150, `BombePaillettes` 200.

### Grimoires (14)
- Gratuits : `Degats`, `VitesseAttaque`, `Quantite`, `Taille`, `Duree`, `Vitalite`.
- Argent : `Cooldown` 60, `Aimant` 60, `Savoir` 80, `Rempart` 80, `Agilite` 100, `Critique` 120, `Chance` 120.
- `Interdit` : quête `Q_GrimoireInterdit` (`WinsTier3` ≥ 1, gagner un Tier 3).

### Objets
Le domaine combat possède `Config.Items`. Règle : un objet sans champ `unlock` ou avec `unlock = "Free"` est dans le pool ; sinon `Common`/`Rare` gratuits, `Epic` 60 et `Legendary` 120 étoiles d'argent dans la boutique (`Shop_Item_<id>`). Si `Config.Items` est absent, tout objet est considéré débloqué (ne jamais bloquer le jeu).

### Compagnons v2 : capture et collection (dossier 40 §3, A12-01)
- Plus de déblocage ni d'œuf : un compagnon se **capture** en run. Collection vide à la première run (défaut, question de Clément au dossier 40 §11.1).
- `profile.companions = { v = 1, owned = {[espèce] = { n, at }}, equipped = { espèce1, espèce2? }, keys = {[captureKey] = os.time} }` ; espèce = `Config.Enemies[kind].name`.
- `ProgressionService.grantCapture(player, speciesId, captureKey) -> ("Granted" | "AlreadyGranted" | "Unavailable", isNew)` : un seul `mutate` (clé d'idempotence + `owned`), puis `saveSoon`. Profil non modifiable → `"Unavailable"` (refusée, jamais différée). 200 clés gardées (`Progression.Collection.MaxKeys`). La première capture est équipée d'office.
- `getCompanionLoadout(player) -> {string}` (possédées, `CompanionService.isSpecies`, sans doublon, ≤ `CompanionService.slotsFor(classe)`), `hasCompanion(player, speciesId)`, `isUnlocked(player, "Companion", id)` = possédée.
- `SelectLoadout(classId, companionId?, companionId2?)` : `""`/nil = aucun ; chaque espèce possédée ; la 2e seulement si `slotsFor == 2` (Tamer). Même contrôle à l'arrivée sur le serveur de run (`MatchService`, la config de run porte `companionId2`). `getLoadout` renvoie `(classId, espèce1 or "")`.
- Œufs v1 encore gagnés : `HatchEgg` donne les jetons de repli (`Eggs.DuplicateTokens`), plus de créature.
- Quêtes `Q_Capture_1..3` (`CompanionsCaptured` 1/10/50) et `Q_Species_1..3` (`CompanionNewSpecies` 3/10/25), clés envoyées par CompanionService. Les quêtes d'évolution, d'Ultime et de Lien sont retirées.

### Mondes et tiers
- `BoisGrognon` : départ. `DunesCroustillantes` : `TrialShrinesCompleted` ≥ 10 (autels d'épreuve, tous mondes, enregistré par ShrineService). `RecreFantome` : `Win_DunesCroustillantes_T2` ≥ 1.
- Tier n+1 d'un monde : `Win_<monde>_T<n>` ≥ 1. API interne `ProgressionService.isWorldUnlocked(player, worldId, tier)` (demande de contrat).

## 6. Boutique d'argent (`ShopBuy`, offre `id`)

| Offre | Effet | Prix par niveau |
| --- | --- | --- |
| `Shop_GrimoireSlot` | Emplacements de Grimoire 4 → 6 | 300, 800 |
| `Shop_Banish` | +1 Bannir par run (max +3) | 100, 250, 500 |
| `Shop_Skip` | +1 Passer par run (max +3) | 80, 200, 400 |
| `Shop_Reroll` | +1 Relancer par run (max +3) | 100, 250, 500 |
| `Shop_Weapon_<id>` | Arme dans le pool | voir 5 |
| `Shop_Grimoire_<id>` | Grimoire dans le pool | voir 5 |
| `Shop_Item_<id>` | Objet dans le pool | voir 5 |
| `Cosmetic_<id>` | Cosmétique en jetons | voir 8 |

`getMetaBonuses(player)` renvoie des **totaux** pour la run : `weaponSlots = 4` (le +1 de Tentaculos est le passif du domaine combat), `grimoireSlots = 4 + niveaux`, `banish = 1 + niveaux`, `skip = 1 + niveaux`, `reroll = 2 + niveaux`. Le domaine combat les prend comme valeurs de départ (remplacent `Cards.DefaultMeta`, qui n'est que le repli sans ProgressionService).

## 7. Maîtrise (1-20) et Lien (1-30)

**Maîtrise par classe** — XP par run : `20 + 10 × stageReached + 30 si victoire + floor(kills / 50)`, plafond 150. XP pour passer du niveau n à n+1 : `100 + 25 × (n − 1)` ; total 1 → 20 = 6 175 (≈ 80-100 runs). Récompenses (cosmétiques, aucune stat) : teinte de trait aux niveaux 3, 6, 9, 12 (`Tint_<classe>_M3`…), pose de victoire aux niveaux 5 et 15 (`Pose_<classe>_M5`, `_M15`), titre aux niveaux 10 et 20 (`Title_<classe>_M10`, `Title_<classe>_M20`).

**Lien par lignée** — XP par run : `20 + 10 × companionStage + 20 si victoire`, plafond 120. Passage n → n+1 : `60 + 10 × (n − 1)` ; total 1 → 30 = 5 800. Récompenses alignées sur `Config.Companions.Bond` (domaine compagnon) : **+1 % de dégâts du compagnon tous les 3 niveaux, plafond +10 % au niveau 30** (appliqué par CompanionService) ; techniques de départ alternatives aux niveaux 1/5/15/25 (`StartTechUnlock`), choisies via `EquipCosmetic("StartTech:<lignée>", techId)` ; teintes de compagnon aux niveaux 4, 10, 20, 28 (`CompanionTint_<lignée>_B4`…) ; pose au niveau 12 (`Pose_<lignée>_B12`) ; titre « Inséparable » au niveau 30 (`Title_<lignée>_B30`) ; un œuf gratuit au premier niveau 10 de chaque lignée. API interne `ProgressionService.getBond(player, line) -> (level, statBonus)` (demande de contrat).

## 8. Cosmétiques (`Config.Cosmetics`)

Emplacements : `Tint:<classId>` (skin d'équipement), `Pose:<classId>` (pose de victoire), `Title`, `Emote`, `Footstep`, `Trail`, `KoEffect`, `CompanionHat`, `CompanionColor`, `Aura` (aura de compagnon) ; les trois derniers s'appliquent à tous les compagnons équipés. Restent de la v1 : `CompanionTint:<line>`, `CompanionPose:<line>` (Lien) et `StartTech:<line>` (id de technique). Un `Tint` ou une `Pose` sans `classId` (premium, saison) va sur toutes les classes. Sources : `Free`, `Mastery`, `Bond`, `Tokens` (jetons), `Quest`, `Weekly`, `Pass` (champ `pass`, rempli depuis `Products.Passes`), `Season` (champs `season`, `tier`, `track`). `EquipCosmetic(slot, id?)` : `nil` déséquipe ; sinon le serveur vérifie emplacement, compatibilité et possession. Le rendu clone un modèle nommé d'après l'id (ex. `Assets.FX.Trail_Comet`, A01/A07/A05) : rien n'est construit par script.

## 9. Monétisation (`Config.Products`, A12-04) — 100 % cosmétique

Interdits (vérifiés à la relecture) : stat payante, résurrection payante, classe vendue, produit aléatoire payant, œuf payant, monnaie achetable, saut de palier de saison payant.

**Tout est vendu en pass de jeu** (corrige S-10) : Roblox refuse lui-même de revendre un pass possédé, même si le client appelle `PromptGamePassPurchase` directement. `Products.Products` (produits développeur) est **vide**, et `MonetizationService` refuse au démarrage un produit qui porterait des cosmétiques. `ProcessReceipt` reste en place (une seule affectation, règles de reçus de `00-vision.md` §11.3) pour un futur produit réachetable.

| Pass (clé) | Contenu | Prix de repli |
| --- | --- | --- |
| `VIP` | Salon privé gratuit (`vipRoomId`, section 15) + `Title_VIP` + `Trail_VIP_Gold` | 299 |
| `Season1` | Piste premium de la saison 1 (rétroactive) | 399 |
| `PremiumSkins` | 6 skins `Tint_Premium_*` (toutes classes) | 199 |
| `FireSkins` / `OceanSkins` | 3 skins chacun | 99 |
| `KoEffects` | `KoEffect_Confetti`, `_Stars`, `_Bubbles` | 149 |
| `Trails` | `Trail_Rainbow`, `_Comet`, `_Leaves` | 129 |
| `VictoryEmotes` | 6 emotes `Emote_*` | 149 |
| `VictoryPoses` | `Pose_Hero`, `_Throne`, `_Flip` | 99 |
| `SparkleSteps` | `Footstep_Etoiles`, `_Bulles` | 79 |
| `CompanionHats` | 4 chapeaux | 129 |
| `CompanionColors` | 4 couleurs | 99 |
| `CompanionAuras` | `Aura_Aurore`, `Aura_Ombre` | 99 |

Ids `0` + TODO (Creator Dashboard). Ordre de la boutique : `Products.ShopOrder` (A09-07). Prix affichés via `GetProductInfoAsync(id, Enum.InfoType.GamePass)` côté client ; le prix de la config n'est qu'un repli. Achat : `RequestPurchase(clé)` → le serveur vérifie (profil modifiable, id ≠ 0, pas déjà possédé, saison en cours pour un pass saisonnier) puis `PromptGamePassPurchase`. Possession : cache serveur par pass, vérifiée à l'arrivée (3 essais), inconnu ≠ faux (revérifié après 30 s), mise à jour par `PromptGamePassPurchaseFinished`. Les cosmétiques de pass sont **dérivés** de la possession, jamais stockés.

**Pass saisonnier** (`Products.Seasons`) : saison `S1`, 30 paliers de 100 XP. XP de saison gagnée **en jouant** à chaque run terminée : `20 + floor(KO / 25) + 10 × mondes finis`, plafond 120 par run (≈ 30-40 runs). Piste gratuite (6 récompenses) pour tous, piste premium (11) avec le pass `Season1`, y compris les paliers déjà atteints. Possession dérivée : `seasons[S1] ≥ palier × 100` (+ pass pour la piste premium), aucune réclamation. Dates `startsAt`/`endsAt` à `0` (= saison ouverte) : **TODO Clément**. Le pass n'est proposé que pendant sa saison ; il faut aussi le retirer de la vente au Dashboard à la fin. Profil : `season = { id, xp, tier, tiers, xpPerTier, premium, endsAt }` ; `RunSummary.seasonXp` en plus.

Réserves : titre doré VIP = statut payant visible (« parent test » du vault), à revalider avant Select 9-15. Abonnement Roblox hors périmètre.

## 10. Défi hebdo

v2 (A12-01) : le défi impose la classe (parmi les 8 classes v2) mais plus le compagnon (`companionId = ""`), puisque chacun a sa propre collection.
Semaine `week = floor((os.time() − 345 600) / 604 800)` (réinitialisation le lundi 00:00 UTC), **une seule formule** (`Config.Progression.weekIndex`) pour le défi et les classements. Le défi est tiré de façon déterministe de `week` : classe (parmi les 10), compagnon (parmi les 6), modificateur (`NoJump`, `OneHitDown`, `LavaFloor`, `DoubleElites`, `GlassCannon`, `Fog`), monde `BoisGrognon` tier 1. Réussite = victoire avec la classe et le compagnon imposés ; récompense une fois par semaine : 1 œuf + 50 jetons + titre `Title_Weekly` la première fois. L'application du modificateur en run appartient au domaine run (demande de contrat : lire `ProgressionService.getWeeklyChallenge()`).

## 11. Quêtes (`Config.Quests`) — 164 quêtes

Chaque quête : `id` stable, `category`, `stat` (clé), `goal`, `reward = { tokens?, silver?, egg?, unlock = { kind, id }?, cosmetic? }`, nom FR/EN. Progression = `stats[stat]` (somme à vie ou record) ; terminée au passage de l'objectif, récompense donnée automatiquement (pas de remote de réclamation, pas d'exploit possible). Toutes les quêtes sont actives dès le départ ; on voit toujours ce qu'on va gagner.

| Catégorie | Quêtes (ids) | Nombre |
| --- | --- | --- |
| `Unlock` | `Q_Felyne`, `Q_Rocailleux`, `Q_Sporelin`, `Q_Ecaille`, `Q_Astrel`, `Q_Cristallin`, `Q_Tentaculos`, `Q_Volt`, `Q_Givre`, `Q_Echo`, `Q_GrimoireInterdit` | 11 |
| `Kill` | `Q_Kill_Total_1..7` (500 → 100 000), `Q_Kill_Elite_1..3` (10/50/200), `Q_Kill_<famille>_1..3` (Swarm, Jumper, Shooter, Armored), `Q_Boss_Total_1..3` (1/10/50), `Q_Boss_<monde>_1..2` (1/10) | 31 |
| `Weapon` | `Q_Weapon_<arme>` : 50 000 dégâts cumulés avec chaque arme (`DamageWeapon_<arme>`) | 16 |
| `Survive` | `Q_FinalWave_Total_1..4` (60/300/900/1 800 s), `Q_FinalWave_Best_1..4` (60/120/180/300 s en une run), `Q_Runs_1..5` (1/10/50/100/250), `Q_Wins_1..3` (1/10/50), `Q_Win_<monde>_T<n>` (9) | 25 |
| `Explore` | `Q_Chests_1..3` (25/250/1 000), `Q_Shrines_1..3` (10/50/200), `Q_Trials_1..2` (25/100), `Q_Coins_1..3` (1 000/10 000/50 000), `Q_Stages_1..3` (5/25/100) | 14 |
| `Mastery` | `Q_BossNoDamage_1..2` (1/5), `Q_BossFast_1..2` (1/5, boss en < 30 s), `Q_Fusion_1..2` (1/10), `Q_RunLevel_1..3` (record 20/30/40), `Q_WinNoDown_1..2` (1/10) | 11 |
| `Class` | `Q_Class_<classe>_Level30` (record de niveau 30), `Q_Class_<classe>_Win_1` (1), `Q_Class_<classe>_Win_2` (10) | 30 |
| `Companion` | `Q_Comp_<lignée>_Stage3` (6), `Q_Comp_<lignée>_Bond10` (6), `Q_Comp_Evolve_1..2` (10/50), `Q_Comp_Ultimate_1..2` (10/100) | 16 |
| `Coop` | `Q_Coop_Revive_1..3` (1/10/50), `Q_Coop_Runs_1..3` (1/10/50), `Q_Coop_Full_1..2` (victoires à 4 : 1/10), `Q_Coop_Shrine_1..2` (autels chargés à plusieurs : 10/50) | 10 |
| **Total** | | **164** (≈ 150 du 00) |

Récompenses typiques : 10 → 100 jetons selon le palier, argent sur certains paliers de survie, œufs sur `Q_Runs_2`, `Q_Wins_2`, `Q_Comp_Evolve_1`, `Q_Coop_Runs_2`, cosmétiques (`Title_*`, `Footstep_*`) sur les derniers paliers. La config fait foi.

## 12. Clés `recordStat` (contrat inter-domaines)

`ProgressionService.recordStat(player, key, amount)` : `amount` nombre fini > 0 (borné à 1 000 000 par appel). **Clé inconnue → ignorée + avertissement une fois par clé.** Clé **automatique** (enregistrée par le domaine data lui-même) appelée depuis un autre domaine → ignorée + avertissement une fois (évite le double comptage).

**Clés à enregistrer par les autres domaines** (`Config.Quests.ExternalKeys`, alignées sur ce que les services appellent déjà) :
| Domaine | Clés |
| --- | --- |
| loot (LootService) | `ChestsOpened`, `CoinsCollected`, `PotsBroken`, `ChestsBought`, `MerchantPurchases` |
| loot (ShrineService) | `TrialShrinesCompleted`, `ShrinesCharged`, `GoldenShrinesCharged`, `AllShrinesCharged`, `BossChallengesAccepted`, `RecessBellsRung`, `TeamTotemsActivated`, `PiggyBanksBroken`, `PranksterUses` |
| companion | `CompanionEvolved`, `CompanionStage3`, `UltimatesUsed`, `CompanionKills`, `CompanionTechsLearned`, `CompanionTreats` |
| avatar | `Hops`, `DistanceTraveled` (par lots), `SlideCharges` |
| combat | `WeaponsFused` (fusion en arme ultime), `CardsPicked` |
| run (BossService) | `BossFast30` (boss tué < 30 s après le début du combat, pour chaque joueur actif) |
| ui | `PingsSent` |

**Clés automatiques** (`Config.Quests.AutoKeys` + préfixes ; le domaine data écoute le Bus et le `RunSummary` ; **ne pas appeler**) :
`Kills`, `KillsElite`, `KillsFamily_<Swarm|Jumper|Shooter|Armored>` (Bus.EnemyKilled + `Config.Enemies[kind].family`, agrégés par seconde), `DamageTaken` (PlayerDamaged), `Revives` (PlayerRevived, sauveteur), `ShrinesCompleted`, `ShrinesCoop` (ShrineCompleted, à ≥ 2 pour Coop), `BossesDefeated`, `BossesDefeated_<monde>`, `StagesCleared`, `FullBuildStageClears` (BossDefeated + `StatsService.getBuild`), `BossNoDamage` (phase `Boss` sans PlayerDamaged), `Companion_<lignée>_Stage3` (CompanionEvolved stade 3), `CoopRuns` (RunStarted à ≥ 2), puis en fin de run (`grantRunRewards`) : `RunsPlayed`, `Wins`, `WinsTier3`, `Win_<monde>_T<n>`, `WinNoDown`, `CoopFullWins`, `FinalWaveSecondsTotal`, `BestFinalWave` (record), `BestRunLevel` (record), `DamageDealt`, `DamageWeapon_<arme>`, `Class_<classe>_Wins`, `Class_<classe>_BestLevel` (record), `Bond_<lignée>` (record du niveau de Lien).

## 13. Classements v2 : KO en une run (A12-02, `regles-v2.md` §4)

Le modèle v1 (somme des KO de la semaine et record de Vague Finale, écrits toutes les 120 s par n'importe quel serveur) est **retiré**. Il reste un seul score : le **plus grand nombre de KO en une run**.

| Tableau (clé `Leaderboards`) | OrderedDataStore | Valeur |
| --- | --- | --- |
| `KoRunWeekly` | `LB_KoRun_W<week>` (`week = Progression.weekIndex`, reset lundi 00:00 UTC par le nom, sans suppression) | Meilleure run de la semaine |
| `KoRunAllTime` | `LB_KoRun_AllTime_v1` | Meilleure run à vie |

**Écriture** (`ProgressionService.scoreRun`) : une fois par run et par joueur, par le serveur de run, au moment où la run se termine pour lui : `grantRunRewards` (fin de run, Cash out) ou départ en cours de run (hook de libération, profil encore modifiable). La valeur est le total serveur de `StatsService.getKills` (A04-03, aussi relayé par `Bus.KOScored`), jamais une valeur du client. Clé `u_<UserId>`, entier 0 → 10 000 000, `UpdateAsync` qui garde le maximum. Ne sont jamais classés : les retardataires (pas dans `Bus.RunStarted`), les profils `flags.boardBanned`, les userIds de `Progression.Leaderboards.BoardBans`, une run en quarantaine.

**Profil = vérité** : le même `mutate` écrit `boards.lastRunKey` (idempotence `JobId:runId`) et, si la run bat le record, `boards.weekBest` / `boards.best` = `{ ko, runKey, seconds, overtimeSeconds, partySize, strikes, worldId, tier, ending, build = {"<arme>:<niveau>"}, at, written, week? }`. `written = false` tant que l'écriture du tableau n'a pas réussi (3 essais) ; au chargement suivant, le relevé est repoussé (idempotent puisque max).

**Quarantaine** (§2.3, §4.5 ; seuils dans `Progression.Leaderboards.Quarantine`) :

| Signal | Source | Effet |
| --- | --- | --- |
| Strikes de mouvement ≥ 3 dans la run | `MovementGuard.getRunStrikes` | Quarantaine |
| Invulnérable > 30 % d'une run d'au moins 60 s | `RunManager.getInvulnerableSeconds` | Quarantaine |
| 3 min sans dégât en étant actif, après +03:00 d'Overtime | `Bus.PlayerDamaged`, `Bus.FinalWaveStarted`, `RunManager.isActive` | Log seul (`NoDamageEnforce = false`) tant que non mesuré |
| KO par minute | durée serveur | `KoPerMinuteCap = 0` (non mesuré) : log au-delà de 600/min |
| KO > ennemis apparus, somme des KO > ennemis apparus | `EnemyService.getRunSpawned` (**contract request**, lu s'il existe) | Quarantaine + log d'erreur |

Run en quarantaine : rien n'est écrit au tableau, le relevé (avec `reasons`) va dans `boards.quarantined` (20 derniers), log serveur, écran de fin normal. **3 quarantaines en 7 jours** → `flags.boardBanned = true` et `RemoveAsync` sur les deux tableaux. Ban manuel : `BoardBans` (filtré à l'écriture **et** à la lecture).

**Fenêtre de score** (§4.3.1, décision de Clément en attente) : `ScoreWindowOvertimeSeconds` (0 = désactivé). Si > 0, seuls les KO faits avant ce cumul d'Overtime comptent. Les tableaux par taille de groupe (§4.3.2) ne sont pas créés ; `partySize` est gardé dans chaque relevé pour les faire plus tard.

**Lecture** : `GetSortedAsync(false, 100)` par tableau, toutes les 120 s + gigue 0-30 s, bannis filtrés, cache serveur, envoyé à tous par `Leaderboards` = `{ KoRunWeekly = {{ userId, value }}, KoRunAllTime = {...} }` et à chaque arrivée. Le client calcule la fin de semaine avec `Progression.weekEndsAt` ; le profil donne `koRecord = { weekly, allTime, weekEndsAt }`. Les noms sont affichés par le client (domaine ui).

**Studio** : toujours un **magasin en mémoire** (même logique, avertissement clair dans la console), jamais d'écriture réelle depuis Studio, avec ou sans accès API. Les scores disparaissent à l'arrêt du serveur.

**Budget ordonné** (4 joueurs) : au plus 2 `UpdateAsync` par joueur et par run (≈ 8 par run de 15 min) contre 50/min ; lecture 2 pages / 120 s.

## 14. Analytics (KPI 14.1)

Serveur uniquement, tout en `pcall`, champs personnalisés à petites listes fixes (jamais d'id utilisateur ni de texte libre), événements fréquents agrégés et vidés toutes les 60 s et au départ.

| KPI | Événement |
| --- | --- |
| Rebond à la première partie | Entonnoir d'accueil `LogOnboardingFunnelStepEvent` (1re session uniquement) : 1 `Joined`, 2 `ProfileLoaded`, 3 `LoadoutSelected`, 4 `RunStarted`, 5 `FirstKill`, 6 `RunEnded`, 7 `SecondRun`, 8 `Minute10` |
| Retour J8-J28, rétention | `ReturnDay` (champ : `D0`, `D1`, `D2-7`, `D8-28`, `D29+`) à chaque arrivée ; tableaux de rétention natifs Roblox |
| Durée de session | `SessionMinutes` (valeur = minutes) au départ |
| Runs par session | `SessionRuns` (valeur = runs) au départ |
| Part de runs en coop | `RunStart` (champs : monde, tier, taille du groupe `1`/`2`/`3`/`4`) |
| Taux de victoire T1 | `RunEnd` (champs : `monde-T<n>`, `Win`/`Loss`, taille) |
| Choix classe / compagnon | `ClassPicked`, `CompanionPicked` (champ : id) |
| Quêtes | `QuestCompleted` (champ : catégorie) ; `Unlock` (champ : type) |
| Économie | `LogEconomyEvent` : source `Silver` (`RunReward`, `Quest`), puits `Silver` (`Shop`), source/puits `QuestTokens` |
| Conversion payeurs | `Purchase` (champ : clé produit ; valeur = `CurrencySpent`) après octroi |
| Données | `DataLoad` (champ : `ready`/`locked`/`failed`), `TeleportFail` (champ : résultat) |

## 15. Lobby ↔ run (MatchService) — actif seulement si `Config.Run.UseLobbyPlace = true`

Ids de places : `Config.Progression.Places.LobbyPlaceId` / `RunPlaceId` (`0` + TODO). Sans place de lobby (phase 0), MatchService ne fait rien.

**Aller (lobby → run)** :
1. Le client envoie `MatchRequest(worldId, tier)` (limité à 1/s). Le serveur vérifie : profil prêt, monde/tier débloqué pour **chaque** membre, sélection de chargement valide (re-validée contre les déblocages). Groupe = le demandeur seul (file solo) ; les groupes d'amis passent par le même chemin avec une liste de membres présents sur ce serveur (TODO UI de groupe).
2. Génère `reservedServerId = HttpService:GenerateGUID(false)` côté serveur (jamais envoyé au client).
3. Écrit la config de run dans la **MemoryStore** `RunConfig` (hash map), clé = `reservedServerId`, valeur `{ v = 1, worldId, tier, members = {UserId}, loadouts = {["<UserId>"] = {classId, companionId}}, sourcePlaceId, createdAt }`, expiration **600 s** (la plus courte sensée). 3 essais ; échec → abandon, message, **rien n'est libéré**.
4. **Libère chaque profil** : sauvegarde finale avec retrait du bail (`DataService.releaseForTeleport`). Le profil passe en état `released` : plus aucune écriture ni achat sur ce serveur. Échec de libération d'un membre → on ré-acquiert ceux déjà libérés et on abandonne.
5. `TeleportAsync(RunPlaceId, groupe, options)` avec `TeleportOptions.ReservedServerId = reservedServerId` (un seul champ de routage), en `pcall`, 4 essais (recul 1, 2, 4, 8 s). Tous échouent → `DataService.reacquire` pour chacun, message.
6. `TeleportInitFailed` (par joueur) : `Flooded`/`Failure` → 2 nouveaux essais avec les **options fournies par l'événement** (même serveur réservé) après 10 s / 2 s ; sinon ou au-delà → `DataService.reacquire(player)` (nouvelle prise du verrou), message, retour à l'état lobby.
7. Chien de garde : joueur encore présent 45 s après un appel réussi → considéré comme échec, `reacquire`.

**Arrivée (serveur de run réservé)** : détecté par `game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0`. Lit `RunConfig[game.PrivateServerId]` (5 essais), cache en mémoire, puis `RemoveAsync` quand tous les membres sont arrivés ou après 60 s. Chaque arrivée : `SourcePlaceId` = place du lobby **et** `UserId` dans `members`, sinon renvoi (refus par défaut, y compris si la lecture échoue). Les choix de classe/compagnon sont réappliqués via `ProgressionService` (re-validés). Le profil se charge normalement (le verrou est libre). **TeleportData n'est jamais lu.** `MatchService.getRunConfig()` donne monde/tier au RunManager (demande de contrat).

**Retour (run → lobby)** : `MatchService.returnToLobby(players)` : récompenses déjà accordées et sauvegardées par `grantRunRewards` + sauvegarde, puis même séquence : libération → `TeleportAsync(LobbyPlaceId, …)` → `TeleportInitFailed`/échec → `reacquire`.

**Salon VIP** : `MatchService.openVipRoom(player)` (pass `VIP`) : `vipRoomId` créé une fois et stocké dans le profil, téléportation vers la place du lobby avec `ReservedServerId = vipRoomId` (même séquence de libération). Sur ce serveur (réservé, sans `RunConfig`), l'accès est réservé au propriétaire et à ses amis (TODO : vérification d'amitié côté serveur ; v1 = propriétaire + membres envoyés par lui).

Budget MemoryStore : 1 000 + 120 × CCU unités/min ; ≈ 3 unités par run (écriture, lecture, suppression). Mémoire : 64 Ko + 1,2 Ko × utilisateurs ; une config ≈ 300 o, expirée en 10 min.

## 16. Remotes du domaine (`shared/NetDefs/Data.luau`)

| Remote | Sens | Charge | Débit |
| --- | --- | --- | --- |
| `Profile` (contrat) | S→C | Vue du profil + champs en plus : `eggs`, `eggOdds`, `shop`, `metaBonuses`, `worlds = {[monde]=tierMax}`, `weekly`, `passes`, `vip` | à chaque changement, regroupé 0,25 s |
| `SelectLoadout` / `EquipCosmetic` / `UpdateSettings` (contrat) | C→S | voir ARCHITECTURE | 2 / 4 / 2 par s |
| `ShopBuy` | C→S | `(offerId: string)` | 3/s |
| `HatchEgg` | C→S | `()` | 1/s |
| `RequestPurchase` | C→S | `(productKey: string)` | 1/s |
| `EggHatched` | S→C | `{ line: string?, tokens: number? }` | — |
| `Leaderboards` | S→C | `{ KoRunWeekly, KoRunAllTime = {{ userId, value }} }` (section 13) | toutes les 120 s |
| `MatchRequest` | C→S | `(worldId: string, tier: number)` | 1/s |
| `MatchState` | S→C | `{ state: "Idle"|"Preparing"|"Teleporting"|"Failed", reason: LocalizedText? }` | — |
| `DataNotice` | S→C | `{ kind: "Waiting"|"Lost"|"Saved"|"QuestDone", text: LocalizedText, questId: string? }` | — |

`SelectLoadout` n'est accepté qu'en phase `Loadout` ou `Ended` (lu sur RunManager s'il existe) pour qu'un changement n'affecte jamais une run en cours.

## 17. Sources vault

- *DataStore Fundamentals* (limites oct. 2026, `UpdateAsync` précisément, erreurs courantes, checklist)
- *Session Locking and Profile Libraries* (bail + jeton, module complet, piège Studio 90 s, chargement raté, pont, bibliothèques)
- *Saving Correctly - Autosave and BindToClose* (moments d'écriture, valeurs de temps, chargeur, `BindToClose` parallèle)
- *Data Schema Design and Migrations* (formes stockables, champ `Schema`, refus des schémas plus récents, `reconcile`)
- *Developer Products and ProcessReceipt* (contrat du reçu, implémentation, erreurs, checklist)
- *Game Passes* (cache serveur, inconnu ≠ faux)
- *Pricing and Store Design* (prix régional 30-100 %, Plus, `GetProductInfoAsync`, `PriceLevel`)
- *Policy and Age Rules 2026*, *Ethical Design and Player Trust*, *Publishing an Experience* (objets aléatoires payants, parent test, Select 9-15)
- *TeleportService - Engine Reference Card*, *Teleporting and Multi-Place Games* (`ReservedServerId`, `TeleportInitFailed`, persistance pendant le saut, données de téléportation non fiables)
- *Reserved and Private Servers in Practice*, *Parties and Group Teleports* (détection de serveur réservé, barrière d'arrivée)
- *MemoryStore Service* (quotas oct. 2026, expirations courtes, suppression explicite)
- *OrderedDataStores and Leaderboards*, *Global Leaderboards End to End* (index ≠ vérité, store par semaine, « ne jamais baisser », budgets)
- *Analytics and Funnels* (module serveur, entonnoirs, champs à faible cardinalité, `CurrencySpent`)
- `SYMPTOMS.md` sections « DataStores, data loss and dupes » et « Monetization and receipts »
