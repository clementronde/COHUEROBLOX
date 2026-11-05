# COHUE — Plan de test et liste de bugs (A13-03)

Agent A13, 5 nov. 2026. Base : `main` au commit `851322e`.

Ce plan sert au chef de projet après chaque fusion dans `main` et à chaque porte. Un parcours est **OK** quand toutes ses vérifications passent. Un échec devient une ligne dans la liste de bugs (section 3), avec le parcours, l'appareil et la vidéo ou la capture.

## 0. Outils de test

| Outil | Comment | Où |
| --- | --- | --- |
| Commandes de run (Studio) | En Play, barre de commande sur la vue **Server**, puis `game.ServerStorage.CohueRunDebug:Invoke("state")`. Autres commandes : `skip`, `xp`, `weapon`, `rune`, `arche`, `killboss`, `world`, `class` | `server/Services/RunManager.luau:1635-1646` |
| Horde fixe | `Balance.Debug.ForceAlive = 150` dans le fichier, ou le script de mesure | `shared/Config/Balance.luau:40` |
| Mesure de horde par paliers | `tools/perf/HordeStress.server.luau` + `HordeStressClient.client.luau` | `docs/qa/mesure-horde.md` |
| FPS et ennemis affichés | DebugHud en haut de l'écran (Studio seulement) | `client/Controllers/DebugHud.luau` |
| Coop locale | Onglet Test > Clients and Servers > 4 joueurs > Start | Studio |
| Émulation mobile | Onglet Test > Device > un téléphone (ex. iPhone 14), orientation paysage | Studio |
| Vrai téléphone | Place publiée en privé, appli Roblox, console avec F9 ou le chat `/console` | voir `mesure-horde.md` |

**Règle** : on teste dans la place COHUE publiée seulement pour les tests sur téléphone et les tests à 4 vrais joueurs. Le reste se fait en Play dans Studio.

**Notes** : `OK`, `KO` (bug ouvert), `—` (pas encore jouable). Chaque campagne recopie la grille de la section 2 avec la date et le commit.

## 1. Parcours

### P1 — Lobby

| # | Ce qu'on vérifie | Comment | Attendu |
| --- | --- | --- | --- |
| P1.1 | Arrivée | Rejoindre la place | Apparition au village en moins de 10 s sur téléphone (`StreamingEnabled`, rayon 64 : `docs/dossier/65-lobby.md:322`) ; écran de chargement avec une astuce |
| P1.2 | Bouton Play | Toucher Play | Choix Solo / Friends / Public. Chaque choix lance la file prévue (`01-decisions-v2.md` §7) |
| P1.3 | Barre du bas | Ouvrir chaque menu (Upgrades, Inventory, Class, Shop, Quests, Pass, Companions) | Le menu s'ouvre et se ferme ; aucun menu ne reste ouvert sous un autre ; retour au lobby sans bouton bloqué |
| P1.4 | Classes | Choisir Knight, Archer, Mage ; essayer une classe verrouillée | Les 3 gratuites passent ; une classe à quête affiche la quête, jamais un prix en Robux (`01-decisions-v2.md` §3) |
| P1.5 | Compagnon | Équiper 1 compagnon (2 pour le Tamer) | Le compagnon suit dans le lobby et à l'entrée de la run |
| P1.6 | Classements | Lire les tableaux hebdo et all-time | Le joueur s'y voit après une run ; reset lundi 00:00 UTC (`01-decisions-v2.md` §2) |
| P1.7 | Profil | Quitter et revenir | Monnaies, déblocages, collection et réglages identiques ; en Studio sans accès API, avertissement clair et données en mémoire (`ARCHITECTURE.md` §1) |
| P1.8 | Perf du lobby | DebugHud + console Memory | ≥ 55 FPS sur le téléphone cible, mémoire ≤ 900 Mo (`budgets-perf.md` §5) |

### P2 — Run : monde 1, 2 et 3

À faire une fois par monde (`Invoke("world", 2)` et `3` pour aller plus vite), puis une fois en run complète sans commande.

| # | Ce qu'on vérifie | Comment | Attendu |
| --- | --- | --- | --- |
| P2.1 | Départ | Lancer en solo | Chrono à 10:00, arme de départ de la classe active, HUD complet |
| P2.2 | Boucle XP | Tuer, ramasser, monter de niveau | Les gemmes viennent à l'aimant ; carte à 3 choix avec rareté visible ; en solo le jeu attend le choix |
| P2.3 | Bannir / Passer / Relancer | Utiliser chacun jusqu'à 0 | Le compteur baisse et le bouton se grise à 0 |
| P2.4 | Densité | `Invoke("skip", 300)` puis `540` | Environ 120 puis 200 ennemis (`Balance.luau:19-25`), lus dans `Invoke("state").enemies` |
| P2.5 | Familles | Attendre ou `skip` | Sauteurs, tireurs, blindés apparaissent ; les tirs se voient 0,6 s avant (`Config/Enemies.luau`) |
| P2.6 | Élites | Attendre la 1re élite | Anneau doré + couronne ; coffre à la mort ; au plus 4 élites à butin hors Overtime (`Config/Run.luau:113`) |
| P2.7 | Autels, coffres, marchand | Utiliser chacun | Ils marchent ; le coffre payant retire les pièces une seule fois |
| P2.8 | Boss | `Invoke("arche")` puis combat | 2 à 3 attaques annoncées 1 s avant par un cercle au sol ; le boss meurt sous les armes ; le portail s'ouvre |
| P2.9 | Passage au monde suivant | Entrer dans le portail | Monde suivant, chrono à 10:00, build gardée, ennemis du monde précédent effacés |
| P2.10 | Mort | Se laisser tuer | Joueur à terre puis fantôme ; écran de fin si tout le monde est mort |
| P2.11 | Écran de fin | Fin de run | KO, dégâts par arme, gains ; Play again relance |
| P2.12 | Textes | Lire tout ce qui s'affiche | Tout en anglais (`01-decisions-v2.md` §1) |
| P2.13 | Perf | DebugHud pendant toute la run | ≥ 45 FPS en moyenne, jamais sous 30 sur le téléphone cible (`budgets-perf.md` §2) |

### P3 — Overtime

| # | Ce qu'on vérifie | Comment | Attendu |
| --- | --- | --- | --- |
| P3.1 | Début | `Invoke("skip", 600)` | À 0:00 le chrono devient +00:01, +00:02… ; annonce « OVERTIME! » |
| P3.2 | Escalade | `skip` de 30 s en 30 s | Toutes les 30 s : spawn +15 %, PV +20 %, dégâts +10 %, élites +3 points (`01-decisions-v2.md` §2) ; annonce « Overtime level k! » |
| P3.3 | Plafond technique | `skip` jusqu'à ce que `state.enemies` reste à 300 | Le compte ne dépasse pas 300 ; les ennemis deviennent plus durs à tuer (`EnemyService.luau:337-349`) |
| P3.4 | Coffres en Overtime | Tuer beaucoup d'élites | Pas de pluie de coffres : les élites au-delà de 4 sortent sans coffre (`EnemyService.luau:58-61`) |
| P3.5 | Valeurs extrêmes | `skip` 3 600 (1 h d'Overtime) | Pas de `inf` ni de `NaN` dans les PV et dégâts (`EnemyService.luau:388-391`) ; le serveur tient |
| P3.6 | Boss en Overtime | Tuer le boss pendant l'Overtime | Le portail s'ouvre ; l'escalade s'arrête jusqu'au portail (`RunManager.luau:92`) |
| P3.7 | Perf à 300 | 10 min à 300 ennemis | FPS dans le budget ; mémoire stable (pas de hausse continue = pas de fuite) |

### P4 — Cash out et Keep going

| # | Ce qu'on vérifie | Comment | Attendu |
| --- | --- | --- | --- |
| P4.1 | Victoire | Tuer le boss du monde 3 (`Invoke("world", 3)`, `arche`, `killboss`) | Bannière Victory, puis choix Cash out / Keep going |
| P4.2 | Cash out | Rester dans le portail doré | Barre de progression ; à 100 % fin de run, annonce « Cashed out! Rewards saved. » (`RunManager.luau:668`), gains sauvés |
| P4.3 | Keep going | Choisir de continuer | Overtime infini, KO qui montent, classement mis à jour à la fin |
| P4.4 | Sauvegarde | Cash out, quitter, revenir | Les gains et les KO sont dans le profil et le classement |
| P4.5 | Coupure | Quitter pendant Keep going | Le joueur garde ce que la règle prévoit (à confirmer par A12) ; aucune perte de profil |

### P5 — Coop à 4

| # | Ce qu'on vérifie | Comment | Attendu |
| --- | --- | --- | --- |
| P5.1 | Départ | 4 clients dans Studio, puis 4 vrais joueurs | La run part quand les 4 ont un loadout |
| P5.2 | Densité et PV | `Invoke("state")` à 5 et 9 min | +40 % d'ennemis et +60 % de PV par joueur en plus (`Balance.luau:26-27`) ; plafond de 300 tenu |
| P5.3 | Cartes figées | Un joueur monte de niveau | **Toute l'équipe se fige** ; celui qui choisit voit un compte à rebours de 15 s, les autres voient qui choisit (`01-decisions-v2.md` §4) |
| P5.4 | Choix en parallèle | 2 joueurs montent en même temps | Ils choisissent en même temps ; le jeu repart quand les deux ont fini |
| P5.5 | Relève | Un joueur tombe, un autre le relève | Relève marche ; le Cleric relève 2× plus vite |
| P5.6 | KO par joueur | Fin de run | Chacun a ses propres KO, comptés par le serveur |
| P5.7 | Départ d'un joueur | Un joueur quitte en pleine run | La run continue ; ses ennemis repartent vers les autres ; pas d'erreur dans la sortie |
| P5.8 | Réseau | Ping (Shift+F3) et Performance Stats des 4 joueurs | Ping stable ; débit reçu ≤ 50 Ko/s en moyenne (`budgets-perf.md` §3.2) |
| P5.9 | Serveur | Console, onglet Server Jobs, ligne Heartbeat | ≥ 55 pas par seconde à 300 ennemis et 4 joueurs |
| P5.10 | Téléportation | Lobby → run → lobby (A13-05) | Profil gardé, groupe gardé, pas de double apparition |

### P6 — Mobile tactile

Sur l'émulateur de Studio d'abord, puis sur un vrai téléphone (Android milieu de gamme + iPhone).

| # | Ce qu'on vérifie | Comment | Attendu |
| --- | --- | --- | --- |
| P6.1 | Déplacement | Joystick au pouce gauche | Le personnage suit sans retard visible |
| P6.2 | Mouvement essentiel | Saut, glissade, glissade en pente, bunny-hop, saut tampon | Tout se fait au toucher (`01-decisions-v2.md` §10) |
| P6.3 | Caméra | Glisser au pouce droit | Rotation à la sensibilité réglable ; la caméra ne rentre pas dans les murs ; dézoom suffisant pour lire la horde |
| P6.4 | Boutons | Toucher chaque bouton du HUD et des menus | Zone de toucher ≥ 44 px ; aucun bouton caché par l'encoche ou la barre système |
| P6.5 | Cartes | Choisir une carte au pouce | Pas de choix par erreur en jouant (délai ou zone séparée) |
| P6.6 | Textes | Lire HUD et cartes à bout de bras | Lisibles ; réglage de taille de texte appliqué |
| P6.7 | Qualité | Lire le palier choisi par WeaponFX | Low sur téléphone (`WeaponFX.luau:166-171`) |
| P6.8 | Chaleur et batterie | 20 min de run | FPS qui ne s'effondre pas après 10 min (chauffe) ; noter la batterie perdue |
| P6.9 | Interruption | Appel, mise en veille, retour | La run reprend ou le joueur est relevé proprement |
| P6.10 | Réseau mobile | Passer en 4G | Jouable ; pas de saut d'ennemis plus d'une fois par minute |

## 2. Grille de campagne

À recopier pour chaque campagne :

| Parcours | PC Studio | Émulateur mobile | Android | iPhone | Commit | Date |
| --- | --- | --- | --- | --- | --- | --- |
| P1 Lobby | | | | | | |
| P2 Monde 1 | | | | | | |
| P2 Monde 2 | | | | | | |
| P2 Monde 3 | | | | | | |
| P3 Overtime | | | | | | |
| P4 Cash out | | | | | | |
| P5 Coop à 4 | | | | | | |
| P6 Tactile | | | | | | |

## 3. Liste de bugs

Gravité : **B** bloquant (crash, perte de données, injouable), **M** majeur (perf hors budget, règle de design cassée), **m** mineur.

Les lignes PERF viennent de la relecture du code du 5 nov. (pas encore mesurées). La mesure A13-01 dira lesquelles se voient vraiment sur téléphone. A13 ne modifie pas le code : chaque ligne est pour le propriétaire du fichier (`ARCHITECTURE.md` §2).

| ID | Gravité | Fichier:ligne | Problème | Proposition | Pour | Statut |
| --- | --- | --- | --- | --- | --- | --- |
| PERF-01 | M | `server/Services/EnemyService.luau:803-813` | À 300 ennemis à moins de 80 studs, EnemySnapshot envoie 2 121 octets par tick, soit 31,8 Ko/s par client à lui seul (budget total : 50 Ko/s). Tous les ennemis proches partent à chaque tick, même ceux qui n'ont pas bougé | Envoyer à 15 Hz seulement les 40 plus proches, le reste à 7,5 Hz ; ou un format delta (id + dx, dz sur 1 octet chacun) | A03 / A04 (run) | Ouvert |
| PERF-02 | M | `server/Services/WeaponService.luau:30` | `FX_MAX_PER_PLAYER = 126` effets par tick, soit jusqu'à 26,6 Ko/s par client. Avec PERF-01, le pire cas dépasse 58 Ko/s | Plafond de 40 effets par tick par client ; regrouper les impacts d'une même zone en un seul effet | A04 (combat) | Ouvert |
| PERF-03 | M | `server/Services/EnemyService.luau:886` | `queryRadius` ajoute 8 studs au rayon : une recherche de rayon 1 parcourt 5 × 5 = 25 cases au lieu de 3 × 3. WeaponService l'appelle jusqu'à 6 fois par projectile et par tick (`WeaponService.luau:587-591`), pour 400 projectiles : jusqu'à 60 000 cases par tick | Marge égale au plus grand rayon d'ennemi ordinaire (~2 studs), les boss restant gérés à part ; ou une recherche par case unique pour les petits rayons | A03 / A04 (run) | Ouvert |
| PERF-04 | m | `server/Services/EnemyService.luau:490-497` | `rebuildGrid` vide la grille et recrée une table par case à chaque tick : ~150 tables par tick à 300 ennemis (règle « pas d'allocation dans les boucles chaudes », `ARCHITECTURE.md` §1). Même chose pour `gatherTargets` (`:264-293`) et les buffers de `EnemyCodec.encode` (`shared/EnemyCodec.luau:56`) | Garder les tables des cases et les vider avec `table.clear` ; réutiliser des buffers par taille | A03 / A04 (run) | Ouvert |
| PERF-05 | M | `client/Controllers/EnemyRenderer.luau:191-195` | Pas de pré-chauffe des pools : le 1er ennemi d'une espèce, ou un changement de LOD, fabrique le modèle pendant l'image (clone + `ScaleTo` pour les mailles riggées, `:142-157`). Une vague de 10 nouvelles espèces ou d'élites peut faire un à-coup visible | Pré-remplir les pools au début de chaque monde (roster de `Worlds`) avec 30 nuées, 10 spéciaux, 4 élites | A03 (run) | Ouvert |
| PERF-06 | m | `client/Controllers/EnemyRenderer.luau:521` | `BulkMoveTo` avec `FireCFrameChanged` : chaque pièce déplacée déclenche l'événement de changement de CFrame, que personne n'écoute | `Enum.BulkMoveMode.FireCFrameNotChanged`, si aucun code n'écoute ces pièces | A03 (run) | Ouvert |
| PERF-07 | m | `server/Services/EnemyService.luau:406` | `EnemyAttackVisual` part vers **tous** les clients avec deux textes (nom et mode), alors que le client jette ce qui est à plus de 82 studs (`EnemyRenderer.luau:386`) | Envoyer seulement aux joueurs à moins de 90 studs ; remplacer les textes par le kind (1 octet) et un code de mode | A03 / A04 (run) | Ouvert |
| PERF-08 | m | `client/Controllers/EnemyRenderer.luau:441` et `:343-360` | En hasard Blackout, chaque ennemi parcourt toutes les lampes à chaque image (300 ennemis × N lampes) | Pré-calculer une grille de cases éclairées au chargement du monde | A03 (run) | Ouvert |
| PERF-09 | m | `server/Services/LootService.luau:713-751` | L'envoi complet du butin (toutes les 10 ticks) peut faire 5 paquets non fiables d'un coup (400 gemmes + 160 pièces), qui se perdent ensemble sur un réseau mobile | Étaler l'envoi complet sur plusieurs ticks (un paquet par tick) | A04 (loot) | Ouvert |
| DES-01 | M | `shared/EnemyCodec.luau:5` | Les 3 bits d'état de chaque ennemi sont déjà pris (élite, action, arrêté). La variante **Capturable** (A03-03, `01-decisions-v2.md` §5) n'a pas de bit pour l'aura côté client | Le kind ne peut pas céder de bit (22 kinds, 4 bits n'en codent que 15). Donc : un octet de plus par ennemi (8 octets : +14 % de débit, voir PERF-01) ; ou une liste à part des ids capturables, envoyée en fiable à l'apparition | A03 + A05 | Ouvert |
| QA-01 | m | `server/Services/EnemyService.luau:338-341` (valeur : `shared/Config/Balance.luau:40`) | `Debug.ForceAlive` est borné par `MaxEnemies` : on ne peut pas tester 400 ennemis sans monter aussi le plafond. Le script de mesure le fait, mais un test à la main à 400 donne 300 sans prévenir | Avertir dans la sortie quand `ForceAlive > MaxEnemies` | A03 / A04 (run) | Ouvert |

### Modèle de ligne

| ID | Gravité | Fichier:ligne | Problème | Proposition | Pour | Statut |
| --- | --- | --- | --- | --- | --- | --- |
| BUG-xx | B/M/m | chemin:ligne, ou parcours P*.* | ce qu'on voit, sur quel appareil, comment le refaire | | agent | Ouvert / Corrigé (commit) / Fermé |
