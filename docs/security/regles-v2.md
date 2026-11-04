# COHUE — Règles anti-triche des systèmes v2

Agent A11, 4 nov. 2026. Source : `docs/dossier/01-decisions-v2.md`. Ces règles s'appliquent aux agents de la vague 2 ; la revue de branche (A11-05) les vérifie une par une. Les failles citées (S-xx) sont dans `docs/security/audit-v1.md`.

**En une phrase :** le client envoie des intentions, le serveur compte tout (KO, captures, gains, classement), et un tricheur repéré n'est ni expulsé ni prévenu : son score n'entre simplement pas au classement.

## 0. Principes communs

1. **Le serveur décide.** Aucun remote n'accorde une créature, des KO, des pièces, de l'argent ou une place au classement. Le client envoie au plus une intention sans valeur (« je veux encaisser »), que le serveur accepte ou non.
2. **Une seule source par chiffre.** Les KO d'une run vivent dans RunManager, la collection dans le profil (DataService). Les autres services lisent ces valeurs, ils ne les recopient pas.
3. **Chaque remote nouveau** passe par `Net.onServerEvent` avec une cadence (1 à 5 par seconde) et vérifie type, plage, NaN, phase de la run et état du joueur (actif, ni à terre ni fantôme).
4. **Pas d'expulsion automatique.** Public de 9 à 15 ans : un faux positif fait plus de dégâts qu'un tricheur. Sanction automatique = la run est mise en quarantaine (§4.5), jamais un kick ni un ban sans revue de Clément.
5. **Le tricheur ne voit rien.** L'écran de fin affiche son score normal. Seul le classement l'ignore. Il n'apprend pas quel seuil il a franchi.
6. **Les seuils vivent dans `shared/Config/*`** avec une source de mesure (logs de playtest). Tant qu'un seuil n'est pas mesuré, il ne fait que journaliser.

## 1. Mouvement (A06, MovementGuard)

Le mouvement reste calculé par le client. Ces règles corrigent S-01, S-02, S-03 et S-08 et préparent les passifs v2.

| Règle | Valeur de départ | Pourquoi |
| --- | --- | --- |
| Hauteur max au-dessus du sol (`root.Y - Heightmap.getY(x, z)`) hors tremplin, plané, escalade | 12 studs pendant plus de 2 s → recalage | Bloque le vol, qui rend intouchable (S-01) |
| Vitesse verticale montante | Au-delà du saut haut de la classe + 20 % → strike | Le contrôle actuel ignore Y |
| Bonus de vitesse dans `vmax` | Seulement si le serveur a validé une glissade ou une chaîne de sauts en cours | Sinon 71 studs/s passent sans strike (S-03) |
| `vmax` hors glissade et saut | `base × (1 + MoveSpeed) × 1,15` ; marge 1,2 ; fuite 8 studs/s | Laisse le lag, pas le speedhack |
| Pendant une exemption (tremplin, recalage, téléport serveur) | Déplacement borné à `vmax × dt × 3` + portée connue du lancement | Plus de téléport libre pendant la grâce (S-02) |
| Exemption de tremplin | Une fois par atterrissage, vecteur tiré du layout serveur | Se tenir sur un tremplin ne rend plus intouchable |
| `SlideStart` accepté | Au sol, vitesse horizontale mesurée par le serveur ≥ `SlideMinSpeed`, 1,5 s depuis la dernière glissade | La glissade du Rogue donne 0,5 s d'invulnérabilité (S-08) |
| `Hop` accepté | Atterrissage vu par le serveur (rayon) dans les 0,3 s précédentes | `HopChain` ne doit jamais venir d'une simple déclaration |
| Ralentissements (`SlowMult`, `SlowUntil`) | Multipliés dans `vmax` par le serveur | Sinon un joueur à terre ou en choix de carte court à pleine vitesse (S-14) |
| Grâce d'apparition | Part du point d'apparition imposé par RunManager ; bouton Reset coupé pendant une run | Un reset ne doit pas offrir 3 s de téléport libre (S-02) |
| Strikes | Comptés par run et exposés : `MovementGuard.getRunStrikes(player)` | Alimentent la quarantaine du classement (§4.5) |

Pour les passifs v2 (Archer « Eagle Eye » à plus de 20 studs, Guardian « immunisé au recul », double saut du Rogue, plané du Mage) : distance, vitesse et état « en l'air » viennent des mesures du serveur (positions échantillonnées, attribut `Airborne` posé par MovementGuard). Jamais de `AssemblyLinearVelocity` ni de `FloorMaterial` lus directement (S-07).

## 2. KO comptés par le serveur (A04, RunManager et EnemyService)

### 2.1 Ce qui compte comme un KO

- Un ennemi mort dans `EnemyService`, avec `killer` = le joueur à qui appartient la source du coup fatal : son arme, son compagnon, sa tourelle, son passif.
- Un KO va à **un seul** joueur. Pas de KO partagés en coop.
- Ne comptent pas : les ennemis retirés par `clearAll`, le changement de monde, la fin de run, un dépop hors zone.
- Le compteur de la run est `RunManager` (`r.kills`). `ProgressionService`, l'écran de fin et le classement le lisent ; aucun ne le recalcule.

### 2.2 Invariants vérifiés à chaque fin de run

| Invariant | Si faux |
| --- | --- |
| KO du joueur ≤ ennemis apparus pendant sa présence dans la run | Bug : run invalide pour le classement, log d'erreur |
| Somme des KO des joueurs ≤ ennemis apparus dans la run | Bug : run invalide, log d'erreur |
| KO du joueur = 0 s'il n'a été actif à aucun moment | Run invalide |

### 2.3 Taux de KO impossible

Un KO est toujours réel (l'ennemi est mort côté serveur). Un taux « impossible » vient donc d'un joueur intouchable ou trop rapide, pas d'un faux chiffre. On ne juge pas le nombre seul, on juge les conditions qui l'ont produit.

| Signal (mesuré par le serveur, par run) | Seuil de départ | Effet |
| --- | --- | --- |
| Strikes MovementGuard | ≥ 3 dans la run | Quarantaine |
| Temps en l'air hors saut légitime | > 10 % de la run | Quarantaine |
| Aucun dégât subi en Overtime | 3 min d'affilée après +03:00 | Quarantaine |
| Temps invulnérable (cartes, Shadowstep, parade, relève) | > 30 % de la run | Quarantaine |
| Dégâts par seconde | > 1,2 × le maximum théorique du build (armes, Runes, objets connus du serveur) | Quarantaine |
| KO par minute | > `Config.Run.KoPerMinuteCap[monde][palier d'Overtime]`, mesuré en playtest (p99,9 × 1,5) | Log seul tant que le plafond n'est pas mesuré, puis quarantaine |

Que faire d'une run en quarantaine : voir §4.5.

## 3. Capture (A04 pour la cage, data pour la collection)

### 3.1 Règles

1. **Seul le serveur crée une cage**, quand meurt un ennemi marqué « capturable » par `EnemyService` au moment de son apparition. Le marquage n'est jamais lu chez le client.
2. La cage est un état serveur : `{ cageId, runId, species, x, z, expiresAt = mort + 10 s }`. Le client ne reçoit que de quoi l'afficher.
3. **Progression à 10 Hz, côté serveur.** Le joueur doit être actif (ni à terre, ni fantôme, ni en choix de carte), dans le rayon de la cage (test 2D + tolérance verticale comme les autels), et sans strike MovementGuard pendant la capture.
4. **« Sans être touché »** = aucun événement de contact, de projectile ou d'attaque de boss **reçu**, même bloqué par l'invulnérabilité, l'esquive, le bouclier ou la parade. Un tel événement remet le compteur à 0. L'invulnérabilité ne doit donc pas aider à capturer.
5. Durée : 2 s, ou 1 s pour le Tamer (`Classes.Tamer` côté serveur, jamais l'attribut du client).
6. **Aucun remote n'accorde une créature.** Le client n'envoie rien pour capturer : il suffit de rester dans la cage.
7. Écriture dans la collection : `ProgressionService` fait `DataService.mutate` puis `saveSoon`. La clé d'idempotence `capturedIds[runId .. ":" .. cageId]` est stockée dans le profil, pour qu'une nouvelle tentative ou un serveur relancé n'accorde jamais deux fois.
8. Si le profil n'est pas modifiable (téléport en cours, session perdue), la capture est refusée avec un message ; elle n'est jamais mise de côté pour plus tard.
9. Plafond : 5 captures par run et par joueur (à régler).
10. Aucun objet payant, aucun hasard : la capture réussit à 100 % (pas d'objet aléatoire payant, conforme aux règles Roblox).

### 3.2 Équiper un compagnon

`SelectLoadout(classId, companionId)` reste un remote d'intention. Le serveur vérifie que `companionId` est dans la collection du profil, et 2 compagnons seulement pour le Tamer. Même contrôle à l'arrivée sur le serveur de run (`MatchService.applyArrivalLoadout` repasse par `setLoadout`).

### 3.3 À trancher (A04 ou Clément)

En coop, la cage est-elle **une par joueur** (comme les coffres) ou **la première personne qui reste 2 s la prend** ? La règle de sécurité tient dans les deux cas. Je recommande une cage par joueur : il n'y a alors rien à voler à un coéquipier.

## 4. Classement hebdo et all-time (data, ProgressionService)

Le modèle v1 (somme des KO de la semaine, écrite toutes les 120 s par chaque serveur) est remplacé.

### 4.1 Stockage

| Classement | OrderedDataStore | Valeur |
| --- | --- | --- |
| Hebdo | `LB_KoRun_W<semaine>` (semaine = `Progression.weekIndex`, reset lundi 00:00 UTC par le nom, sans suppression) | Meilleur nombre de KO en une run de la semaine |
| All-time | `LB_KoRun_AllTime_v1` | Meilleur nombre de KO en une run |

- Clé `u_<userId>`, valeur entière entre 0 et 10 000 000.
- `UpdateAsync` qui garde le maximum et ne baisse jamais une valeur, comme aujourd'hui.

### 4.2 Qui écrit et quand

- **Seul le serveur de run écrit**, une fois par run et par joueur : à la fin de sa run (Cash out, mort définitive, fin de partie ou départ du joueur en cours de run).
- Jamais le lobby, jamais une valeur venue du client, jamais depuis Studio ni un profil de test (`DataService.isTestSession()`).
- La valeur écrite = `r.kills` de RunManager, après les invariants (§2.2) et les signaux (§2.3).
- La même écriture garde dans le profil un relevé de la run : `boards.best = { ko, runId, seconds, overtimeSeconds, partySize, strikes, build, at }`. C'est ce qui permet de purger plus tard par filtre (taille de groupe, version du jeu, strikes).

### 4.3 Bornes du score (décision de Clément)

Le red-team a trouvé l'attaque la plus rentable, et elle n'a pas besoin de hack. L'Overtime est infini et le score monte avec le temps joué. Un groupe de 4 comptes (dont 3 alts sans rien faire) en serveur VIP farme pendant des heures. Le haut du classement devient hors de portée d'un joueur mobile qui fait des runs de 15 à 25 min.

Je recommande les trois règles ci-dessous. Elles changent le design, donc c'est à Clément de trancher :

1. **Fenêtre de score bornée** : seuls comptent les KO faits jusqu'à +20:00 d'Overtime. Keep going reste jouable au-delà, mais sans gain au classement.
2. **Classements séparés par taille de groupe** (solo, 2, 3, 4), ou au minimum solo et coop.
3. **Joueur inactif** (aucun déplacement mesuré par le serveur ni choix de carte depuis 90 s) : il passe à terre, sort du calcul de densité des ennemis et ses KO suivants ne comptent pas.

### 4.4 Lecture

`GetSortedAsync(false, 100)` toutes les 120 s + délai aléatoire par serveur, mis en cache et envoyé aux clients. Les joueurs bannis sont filtrés **à la lecture aussi** : une entrée écrite avant le ban reste dans l'OrderedDataStore tant qu'on ne l'a pas supprimée.

### 4.5 Quarantaine et bannis

| Situation | Effet |
| --- | --- |
| Run en quarantaine (un signal du §2.3) | Score non écrit au classement. Relevé gardé dans le profil (`boards.quarantined`, 20 derniers) et log serveur. L'écran de fin reste normal |
| 3 runs en quarantaine en 7 jours | `flags.boardBanned = true` : plus aucune écriture, entrées supprimées (`RemoveAsync`) des deux classements |
| Ban manuel ou levée du ban | Par Clément seulement : liste `Config.Moderation.BoardBans` (userId) lue au démarrage, ou outil Open Cloud |
| Bug qui laisse passer des valeurs fausses | Changer de version de magasin (`_v2`), puis recalculer depuis les relevés `boards.best` valides |

## 5. Overtime et escalade (A04, RunManager et EnemyService)

1. Le chrono est serveur (`os.clock`, envoyé dans `RunState`). Le client l'affiche seulement ; aucune valeur de temps ne vient du client.
2. Palier = `floor(secondesOvertime / 30)`. Les multiplicateurs (spawn +15 %, PV +20 %, dégâts +10 %, élites +3 points par palier) sont calculés à partir du palier, dans `Config.Run`. Une limite de valeur évite les nombres infinis : PV et dégâts plafonnés à `1e9`, sinon NaN et inf cassent les tests de mort.
3. Limite serveur des ennemis vivants (environ 300, mesurée par A13). Au-delà, l'escalade passe par la force, jamais par plus d'ennemis.
4. Le boss reste tuable. Sa mort est la seule chose qui ouvre le portail, et elle vient de `BossService`, jamais d'un remote.
5. Un joueur qui rejoint pendant l'Overtime joue, mais sa run ne compte pas pour le classement : il n'a pas fait les mondes.
6. Joueur inactif : règle §4.3.3. Elle évite aussi qu'un serveur tourne des heures avec un téléphone posé.
7. Le compteur `RunState.finalWaveSeconds` (ou son équivalent v2) ne sert qu'à l'affichage et aux gains calculés par le serveur.

## 6. Cash out et Keep going (A04 pour le flux, data pour les gains)

1. **Les gains sont calculés par le serveur** à partir de l'état de la run : mondes finis, tier, secondes d'Overtime, KO. La formule est dans `Config.Progression`. Le `RunSummary` envoyé au client est un affichage, jamais une entrée.
2. Remotes d'intention : `CashOut()` et `KeepGoing()`, **sans argument**, 1 par seconde, acceptés seulement dans la bonne phase (choix après le boss du monde 3, ou pendant Keep going pour `CashOut`) et pour un joueur actif.
3. **Une seule remise de gains par run et par joueur.** `lastRewardedRunId` est stocké dans le profil, dans le même `mutate` que les gains : un serveur relancé ou un double appel n'accorde jamais deux fois (aujourd'hui `rewardedRun` ne vit qu'en mémoire).
4. **Déconnexion = mort** pour les gains : quitter ne doit jamais rapporter plus que mourir, sinon on quitte juste avant de mourir. Les KO déjà faits comptent quand même pour le classement (§4.2).
5. À trancher (Clément) : Cash out **individuel** (le joueur part avec ses gains, les autres continuent) ou **de groupe**. Je recommande individuel : sinon un joueur peut couper la run des trois autres juste après le boss.
6. À trancher (Clément) : que perd-on en mourant pendant Keep going ? Si on ne perd rien, Cash out sert juste à quitter. Si on perd tout, seul l'encaissement protège. La règle 4 vaut dans les deux cas.
7. Plafond de gains par run, en argent : la formule maximale du tier (comme `grantRunRewards` aujourd'hui, qui borne déjà l'argent).

## 7. Remotes attendus en vague 2

| Remote (C → S) | Arguments | Cadence | Validation |
| --- | --- | --- | --- |
| `CashOut` | aucun | 1/s | Phase, joueur actif, une fois par run |
| `KeepGoing` | aucun | 1/s | Phase « choix après le boss du monde 3 », une fois par run |
| `SelectLoadout` | `classId: string`, `companionId: string` ou deux pour le Tamer | 2/s | Classe débloquée, compagnons dans la collection, phase Loadout |
| `EquipCompanionCosmetic` | `slot: string`, `cosmeticId: string?` | 4/s | Slot connu, cosmétique possédée, compagnon possédé |
| `MoveEvent` | `"SlideStart"`, `"SlideEnd"`, `"Hop"`, `"HopReset"` | 8/s | Règles §1 |
| Capture | aucun remote | — | Tout se passe côté serveur (§3) |

Interdits : un remote qui prend un nombre de KO, une durée, un gain, une espèce de créature, un identifiant de cage à accorder, ou un résultat d'achat.

## 8. Checklist de revue (A11-05)

- [ ] Aucun nouveau `RemoteFunction` ni `InvokeClient`.
- [ ] Chaque handler client → serveur passe par `Net.onServerEvent` et vérifie type, plage, NaN, phase et état du joueur.
- [ ] Aucun gain (KO, pièces, argent, créature, cosmétique) ne dépend d'un argument venu du client.
- [ ] Pas de `AssemblyLinearVelocity`, `FloorMaterial` ni attribut posé par le client lus pour un gain ou un bonus.
- [ ] Les dégâts subis ne dépendent pas d'un Y que le client peut garder en l'air (S-01).
- [ ] Les écritures de classement viennent seulement du serveur de run, en fin de run, avec relevé et quarantaine.
- [ ] Les gains et les captures sont accordés dans un seul `DataService.mutate`, avec une clé d'idempotence dans le profil.
- [ ] `ProcessReceipt` reste unique ; aucune cosmétique n'est vendue avec du hasard ; aucune stat n'est payante.
- [ ] Tables indexées par `Player` vidées au départ.
