# 70 — Données, méta-progression, quêtes, monétisation, lobby ↔ run

Domaine **data**. Fichiers : `server/Services/{DataService,ProgressionService,MonetizationService,MatchService}.luau`, `shared/Config/{Progression,Quests,Cosmetics,Products}.luau`, `shared/NetDefs/Data.luau`.
Sources de conception : dossier 00, sections 6.3, 7.3, 11, 12.1, 12.5, 14.1. Toutes les valeurs ci-dessous vivent dans la config (`shared/Config/*`) : ce document les décrit, la config fait foi.

Principe : tout ce qui donne de la puissance se gagne en jouant. Le serveur calcule toute l'économie ; le client n'envoie que des demandes validées (type, plage, propriété, solde), limitées en débit.

---

## 1. Profil joueur — schéma v1

Une clé par joueur : `User_<UserId>` dans le DataStore `PlayerData_v1` (≤ 50 caractères, motif statique `{UserId}` pour les demandes d'effacement). En Studio, l'attribut `ServerStorage.TestProfileKey = "nom"` (≤ 20 car.) joue sur `TEST_<nom>_<UserId>` : les tests ne touchent jamais la vraie sauvegarde, et les classements ne sont pas écrits.

L'enregistrement stocké :

```
{ SaveVersion: number, SavedAt: number, Session: { Token, JobId, PlaceId, ExpiresAt, Studio? }?, Data: Profil }
```

Le **Profil** (`Data`), valeurs par défaut d'un nouveau joueur (nouvelle table à chaque fois, jamais un modèle partagé) :

| Champ | Type | Défaut | Rôle |
| --- | --- | --- | --- |
| `schema` | number | 1 | Version de schéma (section 2) |
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
| `mastery` | `{[classId]: number}` | `{}` | XP de maîtrise **totale** par classe ; le niveau 1-20 est calculé |
| `bond` | `{[line]: number}` | `{}` | XP de Lien **totale** par lignée ; niveau 1-30 calculé |
| `eggs` | number | 0 | Œufs gratuits non éclos |
| `eggsHatched` | number | 0 | Compteur |
| `cosmetics` | `{[cosmeticId]: true}` | `{}` | Cosmétiques possédés (hors gratuits et pass, dérivés) |
| `equipped` | `{[slot]: cosmeticId}` | `{}` | Équipement cosmétique |
| `settings` | `{ keepHat, colorblind, reduceFlashes: boolean, textScale: number }` | `false, false, false, 1` | Réglages |
| `loadout` | `{ classId, companionId }` | `Cornu`, `Braise` | Dernier choix |
| `weekly` | `{ week, done, bestSeconds }` | `-1, false, 0` | Défi hebdo (section 10) |
| `boards` | `{ week, kills, bestFinalWave }` | `-1, 0, 0` | Compteurs de la semaine pour les classements |
| `receipts` | `{[PurchaseId]: number}` | `{}` | Marqueurs de reçus traités (même document que l'objet accordé) |
| `receiptOrder` | `{string}` | `{}` | Ordre d'arrivée, pour garder les 100 plus récents |
| `purchaseLog` | `{{k, r, t}}` | `{}` | Journal d'achats (clé produit, Robux payés, date), 50 derniers |
| `vipRoomId` | string | `""` | GUID du salon VIP réservé (section 9) |
| `flags` | `{ boardBanned: boolean }` | `false` | Retrait des classements (outil admin) |

Règles de forme (vault « Data Schema Design and Migrations ») : tableaux denses uniquement (`receiptOrder`, `purchaseLog`), tout le reste en dictionnaires à clés texte ; aucun type moteur (Vector3, Color3) ; nombres bornés (pas d'`inf`/`nan`) ; taille mesurée par `#HttpService:JSONEncode(profil)`, avertissement au-delà de 200 000 caractères (limite 4 194 304). Estimation : ~160 stats × 30 o + 160 quêtes × 25 o + 100 reçus × 45 o ≈ 14 Ko.

## 2. Migrations

- `schema` entier sur chaque profil, `CURRENT_SCHEMA = 1` dans `DataService`.
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

### Classes (6.3) — jamais vendues
| Classe | Déblocage | Quête | Condition (clé de stat, objectif) |
| --- | --- | --- | --- |
| Cornu, Plumeline, Mecano | Gratuit | — | — |
| Felyne | Quête | `Q_Felyne` | `Kills` ≥ 5 000 |
| Rocailleux | Quête | `Q_Rocailleux` | `DamageTaken` ≥ 50 000 |
| Sporelin | Quête | `Q_Sporelin` | `ShrinesCompleted` ≥ 25 |
| Ecaille | Quête | `Q_Ecaille` | `BossesDefeated` ≥ 5 |
| Astrel | Quête | `Q_Astrel` | `ChestsOpened` ≥ 100 |
| Cristallin | Quête | `Q_Cristallin` | `BestRunLevel` ≥ 30 (record) |
| Tentaculos | Quête | `Q_Tentaculos` | `FullBuildStageClears` ≥ 1 (boss battu avec 4 armes **et** 4 Grimoires) |

Écart assumé avec l'exemple du 00 (« finir un stage avec 5 armes ») : 4 armes max hors Tentaculos (00, 8), donc impossible avant de l'avoir.

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

### Compagnons (7.3)
- Départ : `Braise`, `Ronce`, `Maree`.
- `Volt` : quête `Q_Volt` (`DamageDealt` ≥ 250 000) ; `Givre` : `Q_Givre` (`FinalWaveSecondsTotal` ≥ 600) ; `Echo` : `Q_Echo` (`RunsPlayed` ≥ 25).
- Ou **œuf gratuit** : éclosion uniforme parmi les lignées non possédées (taux affichés = 1/N, calculés par le serveur et envoyés dans `Profile.eggOdds`). Si tout est possédé : 40 jetons. Œufs gagnés par quêtes, Lien niveau 10 (première fois par lignée) et défi hebdo. **Aucun œuf n'est jamais vendu**, ni en Robux, ni en argent, ni en jetons.

### Mondes et tiers
- `BoisGrognon` : départ. `DunesCroustillantes` : `ShrinesTrialCompleted` ≥ 10 (autels d'épreuve, tous mondes). `RecreFantome` : `Win_DunesCroustillantes_T2` ≥ 1.
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

`getMetaBonuses(player)` renvoie des **totaux** pour la run : `weaponSlots = 4` (le +1 de Tentaculos est le passif du domaine combat), `grimoireSlots = 4 + niveaux`, `banish = 0 + niveaux`, `skip = 0 + niveaux`, `reroll = 1 + niveaux`. Le domaine combat les prend comme valeurs de départ (pas d'ajout à ses propres bases).

## 7. Maîtrise (1-20) et Lien (1-30)

**Maîtrise par classe** — XP par run : `20 + 10 × stageReached + 30 si victoire + floor(kills / 50)`, plafond 150. XP pour passer du niveau n à n+1 : `100 + 25 × (n − 1)` ; total 1 → 20 = 6 175 (≈ 80-100 runs). Récompenses (cosmétiques, aucune stat) : teinte de trait aux niveaux 3, 6, 9, 12 (`Tint_<classe>_M3`…), pose de victoire aux niveaux 5 et 15 (`Pose_<classe>_M5`, `_M15`), titre aux niveaux 10 et 20 (`Title_<classe>_M10`, `Title_<classe>_M20`).

**Lien par lignée** — XP par run : `20 + 10 × companionStage + 20 si victoire`, plafond 120. Passage n → n+1 : `60 + 10 × (n − 1)` ; total 1 → 30 = 5 800. Récompenses : **+1 % de stats du compagnon tous les 3 niveaux, plafond +10 % au niveau 30** ; technique de départ alternative aux niveaux 10 et 20 (`AltTech_<lignée>_B10`, `_B20`, sidegrade géré par le domaine compagnon) ; teinte de compagnon aux niveaux 5, 15, 25 ; pose au niveau 30 ; un œuf gratuit au premier niveau 10 de chaque lignée. API interne `ProgressionService.getBond(player, line) -> (level, statBonus)` (demande de contrat).

## 8. Cosmétiques (`Config.Cosmetics`)

Emplacements (`slot`) : `Tint:<classId>`, `Pose:<classId>`, `CompanionTint:<line>`, `CompanionPose:<line>`, `AltTech:<line>`, `Title`, `Emote`, `Footstep`, `Aura`. Un cosmétique a `slot` de base (`Tint`, `Pose`, `CompanionTint`, `CompanionPose`, `AltTech`, `Title`, `Emote`, `Footstep`, `Aura`), une `source` et une restriction optionnelle `classId`/`line`. Sources : `Free` (3 teintes par classe, `Tint_<classe>_Base1..3`), `Mastery`, `Bond`, `Tokens` (prix en jetons), `Quest`, `Weekly`, `Pass` (`TeintesPremium`, `Emotes`, `VIP`), `Product`. Les teintes premium s'appliquent à n'importe quelle classe. `EquipCosmetic(slot, id?)` : `nil` déséquipe ; sinon le serveur vérifie que l'emplacement existe, que l'objet est possédé et compatible.

## 9. Monétisation (`Config.Products`) — conforme 11.3

Interdits (vérifiés à la relecture) : aucun objet aléatoire payant, aucune résurrection payante, classes jamais vendues, aucune puissance vendue (pas de relance de carte, pas de stat, pas d'XP), aucun œuf payant, aucune monnaie achetable.

**Pass** (ids `0` + TODO, icônes personnalisées à fournir) :
| Clé | Contenu | Prix de repli affiché si la lecture échoue |
| --- | --- | --- |
| `TeintesPremium` | 6 teintes universelles `Tint_Premium_*` | 199 |
| `Emotes` | 6 emotes de victoire `Emote_*` | 149 |
| `VIP` | Salon privé gratuit (serveur réservé persistant, `vipRoomId`) + titre doré `Title_VIP` | 299 |

**Produits développeur** (cosmétiques permanents, une fois par joueur, refusés **au moment de l'invite** si déjà possédés) : `PackTeintesFeu`, `PackTeintesOcean` (3 teintes chacun), `EffetPasEtoiles`, `EffetPasBulles` (effets de pas), `AuraCompagnonAurore`, `AuraCompagnonOmbre` (auras purement visuelles).

Règles :
- **Prix affichés via `GetProductInfoAsync`** côté client (prix régional, tests de prix, réduction Plus) ; le prix de la config n'est qu'un repli. Les cosmétiques payants ne s'échangent pas (pas de commerce), donc pas de garde de `PriceLevel`. Prix régional des produits : opt-in possible plus tard.
- Achat : le client demande `RequestPurchase(clé)`, le serveur vérifie (profil prêt, id ≠ 0, pas déjà possédé) puis appelle `PromptProductPurchase` / `PromptGamePassPurchase`.
- **`ProcessReceipt` : une seule affectation** (MonetizationService). Ordre : produit inconnu → `NotProcessedYet` ; joueur absent du serveur → `NotProcessedYet` ; attente du profil (15 s) ; profil non modifiable (non chargé, libéré pour téléportation, perdu) → `NotProcessedYet` ; marqueur `PurchaseId` déjà dans le profil → sauvegarde immédiate puis `PurchaseGranted` ; sinon **octroi + marqueur + journal dans le même profil sans `yield`**, puis **sauvegarde immédiate** (`DataService.saveNow`), puis `PurchaseGranted` ; échec de sauvegarde → `NotProcessedYet` (le marqueur reste en mémoire, le prochain passage sauvegarde). Garde `inFlight` par `PurchaseId`. Les produits retirés gardent leur code d'octroi.
- Pass : cache serveur par joueur, vérifié à l'arrivée (3 essais, recul 1-2 s), inconnu ≠ faux (revérifié après 30 s), mis à jour par `PromptGamePassPurchaseFinished` côté serveur.
- Analytics de revenu : `receiptInfo.CurrencySpent`, jamais le prix de la config.
- Réserve de conception (« parent test » du vault) : le **titre doré VIP** est un statut visible qui ne dépend que de l'argent. Demandé par le 00 ; à revalider avant la candidature Select 9-15.
- Abonnement Roblox : hors périmètre v1 (TODO).

## 10. Défi hebdo

Semaine `week = floor((os.time() − 345 600) / 604 800)` (réinitialisation le lundi 00:00 UTC), **une seule formule** (`Config.Progression.weekIndex`) pour le défi et les classements. Le défi est tiré de façon déterministe de `week` : classe (parmi les 10), compagnon (parmi les 6), modificateur (`NoJump`, `OneHitDown`, `LavaFloor`, `DoubleElites`, `GlassCannon`, `Fog`), monde `BoisGrognon` tier 1. Réussite = victoire avec la classe et le compagnon imposés ; récompense une fois par semaine : 1 œuf + 50 jetons + titre `Title_Weekly` la première fois. L'application du modificateur en run appartient au domaine run (demande de contrat : lire `ProgressionService.getWeeklyChallenge()`).

## 11. Quêtes (`Config.Quests`) — 163 quêtes

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
| **Total** | | **163** (≈ 150 du 00) |

Récompenses typiques : 10 → 100 jetons selon le palier, argent sur certains paliers de survie, œufs sur `Q_Runs_2`, `Q_Wins_2`, `Q_Comp_Evolve_1`, `Q_Coop_Runs_2`, cosmétiques (`Title_*`, `Footstep_*`) sur les derniers paliers. La config fait foi.

## 12. Clés `recordStat` (contrat inter-domaines)

`ProgressionService.recordStat(player, key, amount)` : `amount` nombre fini > 0 (borné à 1 000 000 par appel). **Clé inconnue → ignorée + avertissement une fois par clé.** Clé **automatique** (enregistrée par le domaine data lui-même) appelée depuis un autre domaine → ignorée + avertissement une fois (évite le double comptage).

**Clés à enregistrer par les autres domaines** (`Config.Quests.ExternalKeys`) :
| Clé | Qui | Quand |
| --- | --- | --- |
| `WeaponsFused` | combat | Une arme fusionne en version ultime |
| `CardsPicked` | combat | Carte choisie |
| `BossFast30` | run (BossService) | Boss tué moins de 30 s après le début du combat, pour chaque joueur actif |
| `UltimatesUsed` | companion | Ultime déclenché |
| `CompanionTreats` | companion | Friandise prise |
| `PingsSent` | ui | Ping envoyé |
| `DistanceTraveled` | avatar | Studs parcourus (par lots, ex. toutes les 5 s) |
| `SlideCharges` | avatar | Charge de glissade (Cornu) |

**Clés automatiques** (le domaine data écoute le Bus et le `RunSummary` ; **ne pas appeler**) :
`Kills`, `KillsElite`, `KillsFamily_<Swarm|Jumper|Shooter|Armored>` (Bus.EnemyKilled + `Config.Enemies[kind].family`), `DamageTaken` (PlayerDamaged), `Revives` (PlayerRevived, sauveteur), `ChestsOpened` (ChestOpened), `ShrinesCompleted`, `ShrinesTrialCompleted` (kinds `Trial`/`Epreuve`), `ShrinesCoop` (ShrineCompleted à ≥ 2), `BossesDefeated`, `BossesDefeated_<monde>`, `StagesCleared`, `FullBuildStageClears` (BossDefeated + `StatsService.getBuild`), `BossNoDamage` (phase Boss sans PlayerDamaged), `CompanionEvolutions`, `Companion_<lignée>_Stage3` (CompanionEvolved), `CoopRuns` (RunStarted à ≥ 2), puis en fin de run : `RunsPlayed`, `Wins`, `WinsTier3`, `Win_<monde>_T<n>`, `WinNoDown`, `CoopFullWins`, `FinalWaveSecondsTotal`, `BestFinalWave` (record), `BestRunLevel` (record), `CoinsEarned`, `DamageDealt`, `DamageWeapon_<arme>`, `Class_<classe>_Wins`, `Class_<classe>_BestLevel` (record), `Bond_<lignée>` (record du niveau de Lien).

## 13. Classements (OrderedDataStore)

| Tableau | Store | Valeur |
| --- | --- | --- |
| Kills à vie | `LB_Kills_AllTime_v1` | `stats.Kills` |
| Kills semaine | `LB_Kills_v1_W<week>` (nouveau store chaque semaine) | `boards.kills` |
| Vague Finale record à vie | `LB_FinalWave_AllTime_v1` | `stats.BestFinalWave` (s) |
| Vague Finale record semaine | `LB_FinalWave_v1_W<week>` | `boards.bestFinalWave` |

Le profil est la vérité, le tableau un index. Écriture toutes les 120 s (+ au départ), uniquement profils chargés, uniquement si changé, valeur entière > 0, `UpdateAsync` qui **ne baisse jamais** (score monotone dans sa période), clé `u_<UserId>`, jamais depuis Studio ni avec un `TestProfileKey`, jamais si `flags.boardBanned`. Lecture : top 50 par tableau, cache par serveur, rafraîchi toutes les 120 s + gigue 0-30 s, envoyé aux clients par `Leaderboards` ; noms via `UserService` non utilisé (le client affiche les noms avec `Players:GetNameFromUserIdAsync` — domaine ui). Mode Survie : tableaux à ajouter quand le mode existe.

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
| `Leaderboards` | S→C | `{ [board] = {{ userId, value }} }` | toutes les 120 s |
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
