# COHUE — Audit de sécurité v1

Agent A11 (anti-triche et sécurité), 4 nov. 2026. Code audité : commit `ef66264` (environ 29 000 lignes de Luau dans `shared/`, `server/`, `client/`).

**Verdict.** Les remotes sont propres : les 17 handlers client → serveur vérifient type, plage et cadence, et aucune récompense ne passe par un remote. Les données et les achats suivent les bonnes règles (verrou de session, `PurchaseId` dans le profil, accorder → sauvegarder → `PurchaseGranted`). Il y avait une exception, corrigée dans cette branche (S-04). Le vrai trou est le **mouvement** : un tricheur qui vole ne subit plus aucun dégât et tue sans limite, ce qui casse le classement des KO (S-01). Trois autres failles de mouvement passent les contrôles actuels (S-02, S-03, S-05).

| Gravité | Nombre | Dans mon périmètre | Corrigées ici |
| --- | --- | --- | --- |
| Critique | 1 | 0 | — |
| Haute | 3 | 1 (S-04) | 1 |
| Moyenne | 3 | 1 (S-06) | 0 (prévue en vague 2, voir `regles-v2.md`) |
| Basse | 6 | 2 | 0 |

## Méthode

1. Checker fwjelaa (`fwjelaa-check.sh --scan`) sur `shared/`, `server/`, `client/` : 75 fichiers, 1 erreur, 1 alerte, 6 infos. Les 8 sont des faux positifs (liste en fin de document).
2. Lecture complète des 6 services de mon périmètre (DataService, ProgressionService, MonetizationService, MatchService, LootService, ShrineService) et de `shared/Net.luau`.
3. Lecture de chaque handler client → serveur des autres services (RunManager, CardService, CompanionService, MovementGuard, PingService) et de tout code serveur qui lit une valeur venant du client : position, vitesse, `FloorMaterial`, `LookVector`.
4. Skills fwjelaa appliqués : `fwjelaa-secure-remotes`, `fwjelaa-datastore-safety`, `fwjelaa-anti-exploit-review`, `fwjelaa-monetization-compliance`, `fwjelaa-performance-audit` (statique, non mesuré).
5. Second regard par l'agent `fwjelaa:red-team` (mouvement et systèmes v2) et par l'agent `roblox-dev:roblox-reviewer` (code). Je n'ai gardé que ce que j'ai revérifié dans le code.

Échelle de gravité :

- **Critique** : casse le pilier du jeu (classement des KO) ou permet une triche facile et invisible.
- **Haute** : perte d'un achat Robux ou de progression, ou un contrôle serveur contourné pour un avantage net.
- **Moyenne** : avantage limité ou sous conditions, ou défense manquante sur un système qui compte.
- **Basse** : hygiène, risque théorique, aucun gain notable aujourd'hui.

## Liste des failles

| ID | Gravité | Où | Faille | Propriétaire | Statut |
| --- | --- | --- | --- | --- | --- |
| S-01 | Critique | `shared/Config/Movement.luau:66`, `server/Services/MovementGuard.luau:187` | Le vol n'est jamais corrigé : le joueur qui vole est intouchable et tue sans limite | A06 (+ A04) | À transmettre |
| S-02 | Haute | `server/Services/MovementGuard.luau:111`, `:161-180` | Téléportation libre pendant la grâce qui suit un recalage, et autour des tremplins | A06 | À transmettre |
| S-03 | Haute | `server/Services/MovementGuard.luau:84-85`, `:203-206` | Vitesse tolérée d'environ 4,4 fois la marche, en continu | A06 | À transmettre |
| S-04 | Haute | `server/Services/DataService.luau:363-368`, `:601-608`, `:782-795` | Achat Robux acquitté mais jamais sauvegardé s'il arrive pendant la sauvegarde finale | A11 | **Corrigé** |
| S-05 | Moyenne | `server/Services/CardService.luau:376-379`, `:386-395` | 8 s d'invulnérabilité à chaque niveau, même si la carte est choisie tout de suite | A04 | À transmettre |
| S-06 | Moyenne | `server/Services/ProgressionService.luau:1425-1469` | Classement écrit sans aucun contrôle de plausibilité ; `boardBanned` n'est jamais mis | A11 | Vague 2 |
| S-07 | Moyenne | `server/Services/WeaponService.luau:1130-1134` | Bonus de passifs calculés sur la vitesse et l'état « en l'air » envoyés par le client | A04 | À transmettre |
| S-08 | Basse | `server/Services/MovementGuard.luau:275-297` | `Hop` et `SlideStart` sont crus sur parole (sans effet aujourd'hui) | A06 | Règle v2 |
| S-09 | Basse | `server/Services/RunManager.luau:1268-1293` | En mode une place, n'importe quel joueur choisit monde et tier pour tout le serveur | A04 | Décision de Clément |
| S-10 | Basse | `server/Services/MonetizationService.luau:233-242` | Les packs cosmétiques permanents (produits) peuvent être rachetés | Data (config) | À transmettre |
| S-11 | Basse | `shared/Net.luau:68-79` | Les remotes serveur → client n'ont pas d'écouteur serveur : un client peut les remplir | A11 | Vague 2 |
| S-12 | Basse | `server/Services/RunManager.luau:1268` | En mode lobby, le serveur de run ne lit pas `MatchService.getRunConfig()` | A04 | À transmettre |
| S-13 | Basse | `server/Services/LootService.luau:623-662`, `server/Services/ShrineService.luau:612-624` | Ramassage, coffres et autels se fient à la position du client : ils dépendent de S-01 à S-03 | A06 | Couvert par S-01 à S-03 |

## Détail des failles

### S-01 — Critique — Le vol rend intouchable et donne des KO illimités

**Où.** `shared/Config/Movement.luau:66` (`HoverEnforce = false`, mode « log seul ») ; `server/Services/MovementGuard.luau:187` (le contrôle de vitesse ne mesure que le déplacement horizontal, jamais Y) et `:225-233` (vol stationnaire seulement journalisé).

**Pourquoi c'est grave.** Tous les dégâts subis par le joueur dépendent de sa hauteur, alors que ses armes visent en 2D :

- contact ennemi : `server/Services/RunManager.luau:726` exige que les pieds soient à moins de quelques studs du haut de l'ennemi ;
- projectiles ennemis : `server/Services/EnemyService.luau:412` exige `|Δy| < 4` ;
- attaques du boss : `server/Services/BossService.luau:263-265` passent la hauteur `above` au test de forme ;
- armes du joueur : `server/Services/WeaponService.luau:1123-1124` ne gardent que `x` et `z`, et `EnemyService.queryRadius` est en 2D.

**Scénario.** Un script de vol, ou un simple `HumanoidRootPart.CFrame += Vector3.new(0, 20, 0)` chaque frame, place le joueur 20 studs au-dessus de la horde. MovementGuard ne voit aucun déplacement horizontal anormal et n'applique pas la règle de vol stationnaire. Le joueur ne prend plus aucun dégât, ses armes tuent tout en dessous, il tient l'Overtime à l'infini et prend la première place du classement hebdo des KO.

**Correctif.**

1. (A06) Recaler quand `root.Y - Heightmap.getY(x, z) > 12` studs pendant plus de 2 s, hors tremplin, plané et escalade validés par le serveur. Passer `HoverEnforce` à `true` une fois réglé sur les logs.
2. (A06) Ajouter un contrôle de vitesse verticale montante (studs/s vers le haut au-delà du saut de la classe, du double saut et des tremplins).
3. (A04, défense en profondeur) Pour les dégâts subis, utiliser la hauteur du sol sous le joueur plutôt que son Y quand il est en l'air depuis plus longtemps que le plus long saut légitime (environ 1,5 s). Un joueur qui flotte reste alors touchable.
4. (A11, vague 2) Toute run avec des strikes MovementGuard n'entre pas au classement (`regles-v2.md` §4).

### S-02 — Haute — Téléportation libre après un recalage et autour des tremplins

**Où.** `server/Services/MovementGuard.luau:111` : après un recalage, `exemptUntil = now + 0.6 s + ping` (jusqu'à 1,6 s avec `PingCap = 1`). `:161-170` : à moins de 6 studs d'un tremplin, l'exemption est renouvelée à chaque mesure (2,5 s). `:172-180` : pendant une exemption, la position est **acceptée telle quelle** (`lastPos = pos`), sans aucune borne.

**Scénario.**

1. Le tricheur se téléporte. Le serveur détecte le saut et le recale.
2. Dans les 0,6 s qui suivent, il se téléporte de nouveau au même endroit : le serveur accepte la nouvelle position.

Variante sans recalage : se tenir sur un tremplin, puis se téléporter n'importe où (cage de capture, autel doré, arène du boss). En gonflant son ping (lag switch), la fenêtre monte à 1,6 s.

**Correctif (A06).** Pendant une exemption, garder une borne : déplacement ≤ `vmax × dt × 3` + la portée du lancement connu (tremplin : vecteur et distance tirés du layout serveur). L'exemption d'un tremplin ne vaut qu'une fois par atterrissage. La grâce après recalage ne doit jamais accepter une position plus loin de `lastValid` que ce qu'un pas légitime permet.

### S-03 — Haute — Vitesse tolérée d'environ 4,4 fois la marche

**Où.** `server/Services/MovementGuard.luau:84-85` : `vmax` inclut **toujours** le bonus maximal de glissade ou de bunny-hop (`burst = max(1.6, 2.2, 1.84) = 2.2`), même à l'arrêt de ces mouvements. `:203-206` : marge ×1,35, jeu lié au ping et fuite de 20 studs/s (`shared/Config/Movement.luau:56-58`).

**Calcul.** Marche de base 16 studs/s → `vmax` = 35,2. Par mesure de 0,25 s : 35,2 × 1,35 × 0,25 = 11,9 studs, plus 0,9 de jeu pour 100 ms de ping, plus 5 studs de fuite. Soit environ **71 studs/s tenus sans un seul strike**, 4,4 fois la marche normale.

**Scénario.** Un speedhack ×4 ramasse toute l'XP et les pièces de la carte (`LootService` teste la position du client), arrive le premier aux autels et ne se fait jamais toucher. Ça suffit pour les quêtes « boss sans dégât » et « victoire sans tomber », et pour farmer les KO en Overtime.

**Correctif (A06).** N'appliquer le bonus que si le serveur sait que le joueur glisse ou enchaîne des sauts, à partir d'attributs validés par le serveur (voir S-08). Sinon `vmax = base × (1 + MoveSpeed) × 1,15`. Fuite à 8 studs/s, marge 1,2. Chaque strike est compté pour le classement (`regles-v2.md` §1).

### S-04 — Haute — Achat Robux acquitté sans être sauvegardé (corrigé)

**Où.** `server/Services/DataService.luau:363-368` : une sauvegarde qui attend derrière une sauvegarde de libération renvoie `"saved"` quand la session passe à `released`, alors que son instantané a été pris **avant** les changements qu'elle devait écrire. `:601-608` et `:782-795` : pendant la sauvegarde finale (départ du joueur, fermeture du serveur), `mutate` reste permis, car `releasing` n'est levé que pour les téléportations.

**Scénario.** Le serveur ferme (mise à jour du jeu) juste après un achat. `BindToClose` lance la sauvegarde finale ; le reçu arrive pendant qu'elle tourne. `ProcessReceipt` (`server/Services/MonetizationService.luau:185-202`) accorde la cosmétique dans le profil en mémoire, puis appelle `saveNow`. `saveNow` attend la sauvegarde finale, reçoit `"saved"` et renvoie `PurchaseGranted`. Le profil enregistré ne contient ni l'objet ni le `PurchaseId`. Roblox ne renverra plus le reçu : les Robux sont payés, l'objet est perdu. La même fenêtre existe au départ du joueur.

**Correctif (fait, commit sur la branche A11).**

1. `save()` renvoie `"released"` (et non `"saved"`) à un appelant qui ne libérait pas : `saveNow` renvoie `false`, `ProcessReceipt` renvoie `NotProcessedYet`, et Roblox redonnera le reçu au prochain serveur.
2. La sauvegarde finale (départ et fermeture) lève `releasing` avant de prendre son instantané : plus aucune mutation ne peut se perdre après lui.

### S-05 — Moyenne — Invulnérabilité enchaînée par les cartes de niveau

**Où.** `server/Services/CardService.luau:376-379` donne 8 s d'invulnérabilité à chaque offre de cartes. `:386-395` (`closeOffer`) ne la retire pas quand le joueur choisit. `server/Services/RunManager.luau:1151-1156` ne permet que de l'allonger (`math.max`).

**Scénario.** Avec beaucoup d'XP (Rune Wisdom, pots aspirateurs, partage en coop), un joueur monte d'un niveau toutes les quelques secondes en fin de run. Chaque niveau donne 8 s d'invulnérabilité, même s'il choisit sa carte en 0,2 s. Il devient presque invulnérable pendant l'Overtime. Les décisions v2 gardent « 8 s pour choisir, joueur ralenti et invulnérable » : la protection doit finir avec le choix.

**Correctif (A04).** API RunManager pour retirer une invulnérabilité par source (par exemple `setInvulnerable(player, seconds, source)` et `clearInvulnerable(player, source)`). CardService l'enlève au choix, au passage ou au relancement final. Plafond : 30 % du temps de run passé invulnérable au maximum, toutes sources de cartes confondues.

### S-06 — Moyenne — Classement sans contrôle de plausibilité

**Où.** `server/Services/ProgressionService.luau:1425-1469` (`writeBoards`) écrit toutes les 120 s, depuis n'importe quel serveur, la valeur du profil. `:633-635` additionne tous les KO de la semaine. Le drapeau `flags.boardBanned` est lu (`:1430`) mais rien ne le met jamais.

**Pourquoi Moyenne.** Les valeurs sont calculées par le serveur : sans S-01 ou S-03, on ne peut pas les gonfler. Mais rien ne repère un taux de KO impossible, et rien n'empêche un tricheur détecté d'apparaître en tête.

**Correctif.** Prévu en vague 2, quand le classement passe au modèle v2 (« plus de KO en une run ») : écriture par le serveur de run en fin de run seulement, plafond plausible, quarantaine, liste de bannis. Les règles sont dans `regles-v2.md` §4. Je ne le corrige pas sur le modèle v1, qui va être réécrit.

### S-07 — Moyenne — Passifs calculés sur des valeurs envoyées par le client

**Où.** `server/Services/WeaponService.luau:1130-1134` lit `AssemblyLinearVelocity` et `Humanoid.FloorMaterial`, deux valeurs que le client contrôle. Elles alimentent `server/Services/PassiveService.luau:89-97` (bonus en l'air, bonus en mouvement) et `:150` (charge du Cornu au-dessus d'une vitesse donnée).

**Scénario.** Un client garde `FloorMaterial = Air` en flottant (bonus « en l'air » permanent) ou écrit une vélocité énorme sans bouger (bonus de charge à l'arrêt). Les bonus sont bornés et ces classes disparaissent en v2, d'où Moyenne et non Haute.

**Correctif (A04).** Vitesse = déplacement mesuré par le serveur entre deux mesures (MovementGuard l'a déjà). État en l'air = rayon serveur (MovementGuard publie déjà l'attribut `Airborne`). Règle à reprendre pour les passifs v2 (Archer, Rogue, Barbarian).

### S-08 — Basse — `Hop` et `SlideStart` crus sur parole

**Où.** `server/Services/MovementGuard.luau:275-297`. `SlideStart` n'est refusé qu'en l'air, sans contrôle de vitesse ni de délai. `Hop` incrémente `HopChain` et la statistique `Hops` sans vérifier qu'un saut a eu lieu.

**Aujourd'hui.** Aucun code serveur ne lit `Sliding` ni `HopChain`, et aucune quête n'utilise `Hops` : rien à gagner.

**Risque v2.** Shadowstep du Rogue (la glissade donne 0,5 s d'invulnérabilité) et toute vitesse de bunny-hop deviendraient exploitables. Règle dans `regles-v2.md` §1.

### S-09 — Basse — Un joueur choisit monde et tier pour tout le serveur

**Où.** `server/Services/RunManager.luau:1268-1293`. En mode une place, le dernier `SelectStage` valide gagne. Les autres joueurs reçoivent ensuite `Win_<monde>_T<tier>` (`server/Services/ProgressionService.luau:1072`), qui débloque le tier suivant, sans l'avoir débloqué eux-mêmes.

**Décision à prendre par Clément.** Le « carry » entre amis est courant et peut rester. Sinon : n'accorder `Win_*_T<n>` qu'aux joueurs qui avaient débloqué ce tier.

### S-10 — Basse — Packs cosmétiques permanents rachetables

**Où.** `server/Services/MonetizationService.luau:233-242` refuse d'ouvrir l'achat d'un pack déjà possédé. Mais un client peut appeler `MarketplaceService:PromptProductPurchase` lui-même. Il paie alors une seconde fois et ne reçoit rien de neuf (l'octroi est sans doublon, le reçu est acquitté).

**Risque.** Uniquement contre soi-même, mais pour des 9-15 ans c'est une source de plaintes et de remboursements.

**Correctif (domaine data, `shared/Config/Products.luau`).** Vendre les objets permanents en pass de jeu, ou n'utiliser les produits développeur que pour des objets que le joueur ne possède pas encore et accorder un équivalent en cas de rachat.

### S-11 — Basse — Remotes serveur → client sans écouteur côté serveur

**Où.** `shared/Net.luau:68-79` crée les remotes. Une vingtaine n'ont pas d'`OnServerEvent` (`RunState`, `Profile`, `EnemySnapshot`…). Un client peut les déclencher : Roblox met les appels en file puis jette le surplus avec un avertissement.

**Risque.** Bruit dans les logs, pas de gain.

**Correctif (A11, vague 2).** Dans `Net.publish()`, brancher un écouteur vide sur chaque remote sans handler, et compter les appels pour repérer les clients modifiés.

### S-12 — Basse — Le serveur de run ignore la config du lobby

**Où.** `server/Services/RunManager.luau:1268`. En mode lobby (`Config.Run.UseLobbyPlace = true`), le monde et le tier viennent encore de `SelectStage` envoyé par les clients. `MatchService.getRunConfig()` (écrit par le lobby dans la MemoryStore) n'est appelé nulle part.

**Pourquoi Basse.** `SelectStage` vérifie quand même `isWorldUnlocked`.

**Correctif (A04).** En mode lobby, lire monde, tier et membres dans `getRunConfig()` et ignorer `SelectStage`.

### S-13 — Basse — Ramassage et autels dépendent de la position du client

**Où.** `server/Services/LootService.luau:623-662` (aimant, pots, coffres) et `server/Services/ShrineService.luau:612-624` (charge des autels) testent la position du `HumanoidRootPart`. En mode classique, c'est la seule position disponible ; les tests eux-mêmes sont corrects (rayon serveur, joueur actif, propriétaire du coffre, distance au marchand).

**Correctif.** Rien à faire dans ces fichiers. Ils sont sûrs dès que S-01 à S-03 sont corrigés.

## Ce qui est sain (vérifié)

Ces points serviront de base aux revues de branche (A11-05). Toute régression sur l'un d'eux bloque une fusion.

| Domaine | Vérifié | Où |
| --- | --- | --- |
| Remotes | Les 17 handlers client → serveur passent par `Net.onServerEvent` (seau de jetons par joueur et par remote). Chacun vérifie type, plage, NaN et appartenance. Aucune `RemoteFunction`, aucun `InvokeClient` | `shared/Net.luau:108-129` |
| Remotes | Les choix (cartes, autels, marchand) sont des index vérifiés contre l'offre gardée par le serveur ; aucun remote n'accorde de récompense | `CardService.luau:449-523`, `ShrineService.luau:320-346`, `LootService.luau:850-896` |
| Économie run | Pièces, XP, coffres et objets viennent du serveur ; dépense et marquage « vendu » dans une même étape sans `yield` | `LootService.luau:1080-1091`, `:876-879` |
| Profils | `UpdateAsync` avec bail de 90 s et jeton de session vérifié dans la même transaction ; autosave 30 s ; un profil mal chargé n'est jamais sauvegardé ; schéma plus récent refusé | `DataService.luau:294-412`, `:251-271` |
| Profils | `BindToClose` : sauvegardes parallèles, attente jusqu'à 25 s ; Studio sans accès API = magasin en mémoire, jamais en ligne | `DataService.luau:782-804`, `:121-153` |
| Achats | Un seul `ProcessReceipt` ; `PurchaseId` dans le même profil que l'objet ; accorder → `saveNow` → `PurchaseGranted` ; `NotProcessedYet` si joueur absent, produit inconnu, profil non modifiable ou sauvegarde ratée | `MonetizationService.luau:146-220` |
| Achats | Passes : cache serveur, échec de vérification = « inconnu » (jamais `false`) ; aucun objet aléatoire payant, aucune stat payante | `MonetizationService.luau:71-117` |
| Téléport | Config de run dans la MemoryStore (jamais `TeleportData`) ; profil libéré avant `TeleportAsync`, repris si échec ou chien de garde ; arrivée refusée par défaut (lieu d'origine + liste des membres) | `MatchService.luau:183-252`, `:370-385` |
| Classements | Jamais écrits depuis Studio ni un profil de test ; un score n'est jamais baissé | `ProgressionService.luau:1406-1460` |
| Code | Aucun `wait`, `spawn`, `delay`, `_G` ou `shared` ; toutes les boucles cèdent la main | tout le code |
| Mémoire | Les tables indexées par `Player` sont vidées au départ (statique, non mesuré) | 6 services de mon périmètre |

## Hard gates (rubrique système fwjelaa)

| Gate | Résultat | Ce qui décide |
| --- | --- | --- |
| Tourne sans erreur en Studio | Inconnu | Pas de test en Play dans cette tâche (prévu en A11-06). `bash tools/check.sh` compile tout |
| Serveur autoritaire | **Échec** | Remotes : réussi. Mais les dégâts subis dépendent du Y fourni par le client (S-01) |
| Données et achats | Réussi après S-04 | `DataService.luau` corrigé dans cette branche |
| Objets aléatoires payants | Sans objet | Aucun. Les œufs ne s'achètent pas en Robux et disparaissent en v2 |
| API dépréciées, boucles sans fin | Réussi | Recherche sur tout le code |

Une gate en échec plafonne la note système à 5,0 tant que S-01 n'est pas corrigé. Je ne donne pas d'autre note : pour une note indépendante, lancer `/fwjelaa:council`.

## Faux positifs du checker

| Règle | Où | Raison |
| --- | --- | --- |
| `datastore-no-pcall` | `server/Services/DataService.luau:101` | Chaque appelant enveloppe `backend.update` dans un `pcall` (`:297`, `:331`, `:379`) |
| `datastore-setasync-player` | `server/Services/MatchService.luau:108` | `SetAsync` d'une HashMap MemoryStore indexée par le GUID du serveur réservé, pas des données joueur |
| `findfirstchild-chain` ×6 | `client/Controllers/UI/HUD.luau:408`, `:604`, `:605` ; `client/Controllers/UI/UITheme.luau:485`, `:540`, `:552` | Le résultat est converti (`:: T?`), pas indexé ; il est testé juste après |
