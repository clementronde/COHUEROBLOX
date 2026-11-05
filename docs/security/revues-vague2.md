# COHUE — Revues de sécurité, vague 2 (A11-05)

Agent A11, 5 nov. 2026. Checklist : `docs/security/regles-v2.md` §8. Base : `origin/main` = `851322e`. Branches lues après `git fetch` ; seules celles qui ont des commits au-dessus de main sont relues. Chaque branche a été compilée seule (`tools/check.sh`, worktree temporaire). Aucun test en Play (voir `tests-exploits.md`).

## Verdicts

| Branche | Commit relu | Ce qui change | Compile | Verdict |
| --- | --- | --- | --- | --- |
| `claude/a12-data-7c41` | `84b23d9` | Classements v2 « KO en une run », quarantaine, bannis ; S-06 et S-15 | 84 ok | **Fusionnable**, 3 remarques non bloquantes |
| `claude/a03-familles-comportements` | `03cbbaa` | Familles d'ennemis v2 (config, tirage des familles, invocations du boss) | 84 ok | **Fusionnable** |
| `claude/a05-compagnons` | `7fb2ca4` | Documentation seule (dossier 40, règles de capture et APIs) | — | **Conforme** aux règles §3 ; à revoir quand le code arrive |
| `claude/a10-son` | `d626883` | `SoundController` et `Config/Sounds` (client seulement) | 86 ok | **Fusionnable** |
| `claude/a14-armes-5c1460` | `f98bcef` | `WeaponFX` (client), scripts d'installation d'effets, Bloom | 83 ok | **Fusionnable** (aucun code serveur) |
| `claude/a11-failles` | — | Ma branche (S-11, S-16, docs) : à relire par le chef de projet | 84 ok | — |

Branches sans commit au-dessus de main : `a03-ennemis-2b1e1e`, `a06-movement-fff4cd`, `a09-lobby-9fc3de` (déjà fusionnées). Pas encore poussées : A02, A06 (validation), A13.

## `claude/a12-data-7c41` — fusionnable

| Point de la checklist | Résultat |
| --- | --- |
| Aucun `RemoteFunction` / `InvokeClient` | OK : aucun remote ajouté |
| Handlers C → S | Aucun nouveau |
| Aucun gain venu d'un argument client | OK : le score vient de `summary.kills` (résumé bâti par RunManager) et de `StatsService.getKills` ; borné à `MaxValue = 10 000 000` |
| Pas de `AssemblyLinearVelocity`, `FloorMaterial`, attribut client | OK |
| Classement écrit seulement par le serveur de run, en fin de run, avec relevé et quarantaine | OK : `scoreRun` une fois par run (fin, Cash out, départ en cours de run), relevé `boards.best` / `weekBest` dans le profil, quarantaine sur strikes ≥ 3 et invulnérabilité > 30 %, ban après 3 quarantaines en 7 jours (`RemoveAsync` des deux tableaux), bannis manuels filtrés à l'écriture et à la lecture. Studio, profil de test et magasin en mémoire n'écrivent jamais en ligne. Retardataires jamais classés (§5.5) |
| Un seul `mutate` avec clé d'idempotence | OK : `boards.lastRunKey = JobId:runId` vérifié et posé dans le même `mutate` |
| `ProcessReceipt` unique, pas de hasard payant | Non touché |
| Tables par `Player` vidées | OK : `lastWritten` supprimé (S-15) ; `DataService` n'écrit plus `lastSaveAt` pour une session partie (S-15) |
| Ancien profil sans les nouveaux champs | OK : `reconcile` remplit `boards.best`, `weekBest`, `quarantined` depuis `newProfile()` |

Remarques (non bloquantes, à suivre par A12 ou le chef de projet) :

1. **Invariants §2.2 inactifs** tant que `EnemyService.getRunSpawned` n'existe pas (le code le teste avec `safeCall`). À demander à A03 ou A04.
2. **Signaux encore en « log seul »** : `KoPerMinuteCap = 0` et `NoDamageEnforce = false`, comme le prévoit §0.6 (seuils non mesurés). Les mesurer en playtest (A13) puis les activer. La règle du joueur inactif (§4.3.3) et la fenêtre de score (`ScoreWindowOvertimeSeconds = 0`) attendent la décision de Clément.
3. **Petite fuite vers le tricheur** (§0.5) : une run en quarantaine ne met pas à jour `koRecord` dans le profil envoyé au client. Un tricheur attentif voit que son record perso n'a pas bougé. Acceptable aujourd'hui ; si on veut le cacher, afficher le meilleur entre `best` et le dernier relevé en quarantaine.

## `claude/a03-familles-comportements` — fusionnable

- `EnemyService.pickKind` : nouvelles familles (Support, Kamikaze) tirées par le serveur, tampons réutilisés ; aucune entrée client.
- `BossService` : l'invocation retombe sur `roster.Swarm` si le monde n'a ni `Armored` ni `Jumper` (pas de `spawnAt(nil)`).
- Aucun remote, aucun gain, pas de lecture de la position du client nouvelle. Les comportements Kamikaze et Support (dégâts aux joueurs) ne sont pas encore codés côté serveur : à relire quand ils arrivent (dégâts subis avec `RunManager.getDamageFeetY`, S-01).

## `claude/a05-compagnons` — conforme (documentation)

Le dossier 40 suit §3 : cage créée par le serveur seulement, aucun remote de capture, progression serveur avec joueur actif, hors choix de carte et sans nouveau strike, plafond de 5 par run, `grantCapture` dans un seul `mutate` avec `captureKey` dans le profil, refus si le profil n'est pas modifiable, Tamer lu côté serveur. Une cage commune avec une capture par joueur (ma recommandation §3.3).

À surveiller à la revue du code :

- le « touché même bloqué » dépend de `Bus.PlayerHit` (à fournir par RunManager) ; le repli `Bus.PlayerDamaged` laisse l'invulnérabilité aider à capturer (trou connu, documenté) ;
- le repli « collection en mémoire » ne doit tourner qu'en Studio ou sans A12, jamais en ligne.

## `claude/a10-son` — fusionnable

Client seulement. Le seul envoi au serveur est `UpdateSettings` (volumes), coupé par `Sounds.Volumes.Persist = false`. Le handler serveur rejette toute clé inconnue : rien à risquer. Avant de passer `Persist` à `true`, A12 doit ajouter `masterVolume`, `musicVolume`, `sfxVolume` (nombres finis bornés à 0..1) dans `onUpdateSettings`.

## `claude/a14-armes-5c1460` — fusionnable

`WeaponFX` (client) et des scripts d'installation à lancer en mode Edit. Aucun remote envoyé, aucun code serveur. La branche part d'une base plus ancienne (83 fichiers) : fusionner main dedans avant.

## Vague 3 (revue après fusion)

Agent A11, 5 nov. 2026. Code relu : `origin/main` = `d55ddd2` (vague 3 fusionnée sans relecture : A03 rendu et perf de la horde, A04 pause de niveau / lobby / Cash out par joueur, A05 techniques des compagnons, A12 profil v1 → v2 et record de KO). Diff `81c5135..d55ddd2` sur `server/`, `shared/`, `client/`. Branche `claude/a11-revue-v3`, 95 fichiers compilent (`tools/check.sh`). Aucun test en Play : les scripts T9 à T13 sont dans `tests-exploits.md`. La branche `claude/raccords-v3` (pas encore fusionnée, relue à `4e2bd63`) fige déjà le butin, les autels et le mouvement pendant le gel.

**Verdict global : aucune faille haute ni critique.** Dans mon périmètre (`ProgressionService`), une faille moyenne et une basse sont corrigées ici (S-17, S-18). Deux failles moyennes sont décrites pour leurs propriétaires (S-19, S-20).

| # | Point | Verdict | Détail |
| --- | --- | --- | --- |
| 1 | Remotes A04 : `ReturnToLobby`, `VictoryChoice`, PLAY du lobby | **OK** | §1 |
| 2 | Gel du passage de niveau (S-05) | **S-05 reste fermé** ; 3 trous moyens : S-17 (corrigé), S-19, S-20 | §2 |
| 3 | Migration du profil v1 → v2 (schéma 3), `UpdateSettings` | **OK** | §3 |
| 4 | `EnemyCodec`, `EnemyAttackVisual` | **OK** | §4 |
| 5 | Techniques des compagnons (A05) | **OK** | §5 |
| 6 | `bestKills`, `weeklyRank` et quarantaine | `bestKills` **OK** ; `weeklyRank` trahissait la quarantaine (S-18, corrigé) | §6 |

Checklist §8 : aucun `RemoteFunction` ni `InvokeClient` ajouté. Deux remotes client → serveur ajoutés (`ReturnToLobby`, `VictoryChoice`), tous deux par `Net.onServerEvent` avec une cadence. Aucun gain ne dépend d'un argument du client. Les écritures de classement restent dans `scoreRun` (un seul `mutate`, `lastRunKey`). La seule table par `Player` ajoutée (`choosers` de RunManager) est vidée au départ (`RunManager.luau:2082`).

### 1. Remotes client → serveur d'A04 — OK

- `ReturnToLobby` (`server/Services/RunManager.luau:2020`) : aucun argument, cadence 2/s. N'agit que si `r.lobbyAt` est posé, c'est-à-dire après `finishPlayer` (`:768`, fin de sa run ou Cash out). Il avance le retour au lobby de ce joueur seul et ne fait rien pendant une run. Impossible de partir en gardant des gains indus : les gains sont accordés avant, par `rewardSummary`.
- `VictoryChoice` (`:2029`) : seules les chaînes `"CashOut"` et `"KeepGoing"` passent, à 2/s au plus. Refusé hors run (`r.inRun`), avant la victoire (`state.victory`) et pendant le gel (`state.frozenAt`). Aucun argument ne désigne un joueur : impossible de faire partir quelqu'un d'autre. `cashOutPlayer` (`:941`) revérifie victoire, `inRun` et phase. Il accorde les gains une seule fois (`ProgressionService.grantRunRewards` refuse un 2e appel par `rewardedRun`), retire le joueur de `runPlayers` et pose `finishedRunId`.
- Revenir dans la même run après un Cash out est refusé (`:1944`, `r.finishedRunId ~= state.runId`). Un joueur qui quitte le serveur puis revient est un nouveau `Player` sans `runInfo` : il entre en retardataire, mais `grantRunRewards` ne lui donne ni victoire ni argent (`ProgressionService.luau:1313`) et il n'est jamais classé (§5.5).
- Le PLAY du lobby est `SelectLoadout` (`:1959`, chaînes de 40 caractères au plus, 4/s ; classe et espèces validées par `ProgressionService.setLoadout`). Il ne marque prêt que l'appelant. La run part avec les seuls joueurs prêts (`stepRun`, `Run.Lobby.StartDelay`) : personne ne peut lancer la run d'un autre ni la forcer pour tout le serveur.
- Un joueur resté au lobby pendant une run n'a aucun effet sur elle : `RunManager.isActive` exige `inRun` (`:1779`), et Loot, Shrine et Card s'en servent.
- `ReturnToLobby` et `VictoryChoice` sont aussi couverts par T7 (valeurs pourries sur tous les remotes).

### 2. Gel du passage de niveau — S-05 fermé, trois trous moyens

- **S-05 reste fermé.** En mode pause, `CardService.tryOpen` (`server/Services/CardService.luau:395-400`) ne donne plus ni invulnérabilité ni ralenti. Pendant le gel, `RunManager.damagePlayer` renvoie 0 pour tout le monde (`RunManager.luau:1720`), mais rien n'avance non plus : armes (`WeaponService.luau:1571`), horde (`EnemyService.luau:1815`), chrono et Overtime (`RunManager.luau:1448`). Le budget d'invulnérabilité ne compte pas le gel (`unfreeze`, `:399`, décale `runStart`), et `invulnSeconds` n'augmente pas pendant le gel.
- **Prolonger le gel en coop.** Chaque offre dure `Run.LevelUpPause.CoopSeconds` = 15 s, puis le serveur prend la 1re carte (`CardService.luau:623`). Reroll, ban et skip ne remettent pas le délai à zéro. Un départ pendant le choix libère le gel (`RunManager.luau:2082`), la fin de run et le Cash out aussi (`dropOffer`, `CardService.luau:436`). Un client ne peut donc pas geler une run coop plus de 15 s par niveau gagné. Gêne connue : un joueur absent gèle ses coéquipiers 15 s à chaque niveau (décision de design de Clément).
- **S-19 (Moyenne, A04).** Une offre ouverte en solo n'a pas de limite (`SoloSeconds = 0`, `CardService.luau:397`, `expiresAt = math.huge`). Si un retardataire arrive pendant ce choix, la run devient coop mais l'offre reste sans limite : le retardataire reste figé (`initPlayerForRun`, `RunManager.luau:637`) tant que le premier joueur ne choisit pas. Détail et correctif dans `audit-v1.md`.
- **S-20 (Moyenne, A06 / raccords-v3).** Même quand MovementGuard lit l'attribut `Frozen` (`claude/raccords-v3`, `4e2bd63`), un client modifié avance encore d'environ 4 à 5 studs/s pendant le gel (`SlackStuds` 0,6 par échantillon + `LeakPerSecond` 1,5, `MovementGuard.luau:570`). En solo, le gel n'a pas de limite : il se replace où il veut sans danger. raccords-v3 fige le butin et les autels, il n'y gagne donc qu'une position. Détail dans `audit-v1.md`.
- **S-17 (Moyenne, corrigé ici, `a52bf20`).** La durée de run du classement (`ProgressionService.luau:1925`) comptait le temps figé. Une offre laissée ouverte en solo diluait les signaux de quarantaine (KO par minute, part d'invulnérabilité) et la durée minimale des gains. À l'inverse, un joueur honnête qui choisit sa carte en Overtime accumulait du temps « sans dégât » (signal `NoDamageOvertime`, en log seul aujourd'hui). `ProgressionService.onRunFrozen` (`:1188`) décale maintenant `startedAt`, `lastDamagedAt` et `overtimeSince` à la reprise, et `checkNoDamage` ne tourne pas pendant le gel.
- Remarque hors sécurité (pour A04 / raccords-v3) : `BossService` ne lit pas le gel. Le boss continue ses télégraphes et ses invocations pendant la pause : les dégâts sont à 0, mais les attaques sont consommées et les ennemis invoqués arrivent à la reprise.

### 3. Migration du profil v1 → v2 et `UpdateSettings` — OK

- `STEPS[2]` (`DataService.luau:344`, schéma 2 → 3) ne lit que le profil sauvegardé par le serveur ; aucun champ ne vient du client. Les nombres passent par `num` (NaN et infini → 0) et `storable`. La maîtrise est recalculée puis bornée (`math.clamp(..., 1, MaxLevel)`).
- **Pas de gain.** `Progression.LegacyClassIds` va d'une classe à une classe (8 classes v1 → 8 classes v2 distinctes) : deux classes v1 ne fusionnent jamais leur XP sous le même id. L'XP v1 et v2 d'une même classe s'additionnent, ce qui correspond à du progrès réellement gagné sous deux noms. Les quêtes sont copiées sans récompense, et seulement si elles manquent. Monnaies (`silver`, `questTokens`, `eggs`), reçus et collection de compagnons ne sont pas touchés.
- **Pas de perte.** Chaque valeur déplacée est recopiée dans `legacy.classesV1` ; Astrel et Cristallin (sans équivalent v2) y restent. Les clés sont triées, donc la migration donne toujours le même résultat.
- `boards.bestKills` part du plus grand de `best.ko` et `weekBest.ko` : il ne peut pas dépasser un relevé déjà validé.
- `UpdateSettings` (`ProgressionService.luau:1567`) : 8 clés au plus, une clé inconnue fait rejeter toute la requête, booléens typés, `textScale` borné à 0,8..1,5. `masterVolume`, `musicVolume` et `sfxVolume` doivent être finis ; ils sont arrondis au centième et bornés à 0..1 (ma demande de la vague 2 est faite). Cadence 2/s ; un réglage de volume seul ne renvoie pas le profil.

### 4. `EnemyCodec` et `EnemyAttackVisual` — OK

- Instantanés (`shared/EnemyCodec.luau:83`) : le chunk 0 réserve la place des ids retirés (100 au plus) avant les enregistrements. Il fait au plus 8 + 2 × 100 + 98 × 7 = 894 octets, les autres chunks 8 + 127 × 7 = 897 octets. Tout reste sous 900.
- `EnemyAttackVisual` : 14 octets fixes, direction normalisée, rayon et id bornés, rayon NaN ramené à 0 (`encodeAttack`). `CompanionSnapshot` : 5 + 35 × 25 = 880 octets au plus. `WeaponFx` : le nombre d'effets par client reste borné par `FX_MAX_PER_PLAYER` (PERF-02), encodage inchangé.
- Côté client, `readHeader` (`:121`) et `decodeAttack` (`:294`) refusent toute taille incohérente et tout mode inconnu. `EnemyRenderer` vérifie `typeof(payload) == "buffer"` (`client/Controllers/EnemyRenderer.luau:747`) et ignore un `kind` inconnu (`:517`) ou un rang d'attaque de boss absent (`:592`). Ces remotes vont du serveur au client : un autre client ne peut rien y envoyer (S-11).

### 5. Techniques des compagnons (A05) — OK

- Les cartes sont tirées par le serveur (`CompanionService.getCardOptions`) et gardées dans l'offre de `CardService`. Le client n'envoie qu'un index, vérifié par `onChoice`.
- `CompanionService.applyCard` (`server/Services/CompanionService.luau:1239`) et `applyTech` (`:1210`) revalident tout : technique connue, espèce équipée par le joueur, niveau suivant exact (apprendre 0 → 1, améliorer n → n+1), plafond `TechMaxLevel`. Une Friandise revérifie `maxStacks`. Les effets (zone, statuts, Pulse) sont calculés par le serveur depuis la position du compagnon, qu'il simule lui-même ; aucune technique ne lit une valeur envoyée par le client.

### 6. Classement : `bestKills` et `weeklyRank` — S-18 corrigé

- `bestKills` (`ProgressionService.luau:1997`) monte pour toute run, même en quarantaine ou banni, et les classements ne le lisent jamais : il ne trahit rien.
- **S-18 (Basse, corrigé ici, `5d1afa7`).** `weeklyRankOf` (`:2072`) calculait le rang sur le seul relevé validé. Un tricheur en quarantaine avec 5 000 KO voyait « pas de rang » (ou son ancien rang) au lieu de la 1re place. Le rang prend maintenant le meilleur entre le relevé de la semaine et les KO de cette run ; le classement n'est pas modifié.
- Reste (Basse, déjà noté en vague 2) : `koRecord.allTime` et `koRecord.weekly` du profil (`:551`) ne bougent pas en quarantaine. L'UI ne les affiche plus (elle lit `bestKills`), mais ils restent visibles dans le paquet `Profile`. À retirer du profil envoyé, ou à remplacer par `bestKills`, la prochaine fois qu'A12 touche ce code.
- Reste (Basse) : un joueur banni (`boardBanned`) voit toujours `weeklyRank = nil`. Acceptable : le ban se voit déjà (il n'est plus dans le tableau).

### Autres remarques

- `CompanionUltimate` est envoyé par le client (`client/Controllers/UI/UIInput.luau:101`) mais n'a pas de handler serveur : chaque appui compte comme un appel sur un remote sans écouteur (S-11). Un joueur honnête qui appuie 20 fois déclenche le log `[Net] ... appels sur des remotes serveur -> client`. Ne pas faire de `Net.getStrayCalls` un signal de quarantaine tant que ce remote n'a pas de handler (A05).
- `loadoutChangeAllowed` (`ProgressionService.luau:871`) refuse un changement de classe pendant toute run du serveur, y compris pour un joueur resté au lobby (place unique). C'est une gêne de jeu, pas une faille (A04 / A12).
