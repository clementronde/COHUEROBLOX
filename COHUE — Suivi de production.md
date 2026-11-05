# COHUE — Suivi de production

Nov 4, 2026 · @Clément RONDEPIERRE

## Où on en est

La vague 1 (fondations) a démarré le 4 novembre avec 6 conversations d'agents : DA, gameplay, mouvement, UI, menus et anti-triche. Les décisions v2 sont écrites et fwjelaa est installé ; aucun contenu de jeu n'est encore livré.

| Indicateur | Valeur |
| --- | --- |
| Vague en cours | 1 — fondations |
| Conversations lancées | 6 sur 13 (A01, A04, A06, A08, A09, A11) |
| Prochaine porte | Fin de vague 1 : style voxel validé, run jouable en 3e personne avec 4 classes |

Chaque agent met à jour le statut de ses tâches dans la section Tâches. Ce que le côté technique attend de Clément : `docs/attentes-clement.md`. Le chef de projet (la conversation principale) tient ce tableau et le journal à jour.

## Décisions du 4 novembre

Le pilier du jeu est la boucle survie + XP qui mène au classement hebdo du plus grand nombre de KO en une run. Le détail pour les agents est dans `docs/dossier/01-decisions-v2.md`, qui remplace la v1 partout où elles se contredisent.

| Thème | Décision | Impact sur le code existant |
| --- | --- | --- |
| Objectif | Jeu qui rapporte des Robux, monétisation 100 % cosmétique | Boutique cosmétique à construire |
| Public | 9-15 ans, mobile d'abord, solo + coop jusqu'à 4 | Aucun |
| Langue | Anglais seul au lancement | Tous les textes joueur passent en anglais |
| Nom | COHUE reste un nom de travail ; nom anglais à trouver | Aucun |
| Run | 10 min par monde, 3 mondes ; à 0:00 le compte à rebours devient un chronomètre et la difficulté monte sans plafond | RunManager à adapter (Overtime, Cash out) |
| Classement | Classement hebdo des KO en une run, dès le lancement | Nouveau : compteur serveur + OrderedDataStore |
| Classes | Classiques : Knight, Archer, Mage, Guardian, Rogue, Cleric, Barbarian, Tamer | TraitService et Config/Classes remplacés |
| Avatar | L'avatar du joueur est gardé, la classe ajoute un équipement voxel | Accessoires de classe à modéliser |
| Mouvement | Essentiel (bunny-hop, glissade), client + vérif serveur | MovementController et MovementGuard gardés |
| Caméra | 3e personne | CameraController remplacé |
| Compagnons | Pas d'évolution : on bat la créature, on la capture, elle nous accompagne ensuite ; personnalisation en Robux | CompanionService refait |
| Ennemis | Gobelins, zombies, fantômes ; humour absurde | Config/Enemies réécrit |
| Boss | Combat simple, tué avec ses attaques | BossService simplifié |
| Contenu | 16 armes, 14 Runes (ex-grimoires), 40 objets | Contenu des configs réécrit |
| Style | Voxel, palette vive ; références Megabonk, Octopath Traveler, Steal an Egg | Toute la 3D à refaire en voxel |
| UI | Glossy cartoon, maquettes Figma avant intégration | Logique UI gardée, look refait |
| Lobby | Hub 3D | Nouvelle place à construire |
| Son | Ni musique ni voix fournies : bibliothèque audio sous licence du Creator Store | Nouveau |
| Outils | Blender, Meshy avec budget de crédits illimité, vaults LihFolk et fwjelaa | Aucun |

## Points à confirmer

Treize points attendent ta réponse ; en attendant, les agents appliquent la proposition. Écris ta réponse dans la dernière colonne.

| # | Question | Proposition appliquée | Ta réponse |
| --- | --- | --- | --- |
| 1 | Une run enchaîne-t-elle les 3 mondes (10 min chacun), ou une run = 1 monde au choix ? | Les 3 mondes enchaînés, puis Cash out ou Overtime infini |  |
| 2 | Fusion d'armes : une arme au niveau max + une Rune précise assez haute se transforme en version ultime, avec un nouveau look (ex. Longbow + Attack Speed = Storm Bow). On la garde ? | Oui : c'est le moment fort d'une run, et ça se voit en stream |  |
| 3 | Cartes : faites main (même carte à chaque run), semi-procédurales (morceaux faits main, assemblés autrement à chaque run) ou entièrement générées (moins jolies) ? | Semi-procédurales |  |
| 4 | Monde 2 = cimetière ou marais de zombies, monde 3 = Récré Fantôme ; on abandonne le désert ? | Oui |  |
| 5 | Les boss sont-ils capturables ? | Non au lancement, peut-être en live ops |  |
| 6 | Nom anglais du jeu | L'agent marché propose 10 noms en vague 2 |  |
| 7 | Ce qu'il ne faut pas reproduire (ta question 4) | Éviter le début de run lent et le manque de mondes, les deux critiques de Megabonk |  |
| 8 | Organisation (questions 39 à 45, sans réponse) | Travail par vagues, une branche git par agent, intégration par le chef de projet, ta validation à la fin de chaque vague, commits locaux sans GitHub |  |
| 9 | Cash out en coop : toute l'équipe d'un coup, ou chacun pour soi ? Et que perd-on en mourant pendant Keep going ? | Chacun pour soi ; mourir en Keep going garde les gains déjà acquis à la Victory |  |
| 10 | Overtime : +15 % par palier de 30 s (linéaire) ou ×1,15 par palier (composé, beaucoup plus dur après 10 min) ? | Linéaire, la version jouée par A04 |  |
| 11 | Classement : limiter les KO comptés à +20:00 d'Overtime, séparer les classements par taille de groupe, retirer les joueurs inactifs ? | Oui aux trois : sinon un groupe de comptes secondaires en serveur VIP prend la tête sans tricher |  |
| 12 | Coop : un joueur qui n'a pas débloqué un monde gagne-t-il les récompenses de victoire s'il est porté par ses amis ? | Oui, c'est ce qui donne envie de jouer entre amis |  |
| 13 | Cage de capture en coop : une par joueur, ou au premier qui la prend ? | Une par joueur, comme les coffres : pas de vol entre amis |  |

Une chose à savoir sur « aucun ennemi max » : pour le joueur, la horde ne plafonne jamais. Le serveur garde quand même une limite d'ennemis vivants (environ 300). Au-delà, la difficulté monte avec des ennemis plus forts plutôt que plus nombreux, pour que les téléphones ne crashent pas.

## L'équipe d'agents

14 rôles : 13 agents spécialisés, chacun dans sa propre conversation, plus le chef de projet qui intègre leur travail. Un agent ne modifie que les fichiers de son périmètre (`docs/ARCHITECTURE.md`, section Ownership). Depuis le 5 novembre, Cantin fait tout le développement et Clément le design et la 3D ; pour les agents mixtes (A02, A07, A08, A09, A10), Clément fait le visuel et Cantin le code.

| ID | Agent | Périmètre | Outils et skills | Vague | Statut | Conversation |
| --- | --- | --- | --- | --- | --- | --- |
| A00 | Chef de projet | Doc de suivi, dossier, intégration des branches, place Studio partagée, portes de vague | Studio, git, Docs | 0 | En cours | Conversation principale |
| A01 | DA et modeling | Guide de style voxel, équipement des 8 classes, créatures, boss, props | Blender, Meshy, Asset Pack, make-model, blender-modeling | 1 | En cours | a01-da-voxel (Clément) : kit d'assets en tenons posé dans COHUE |
| A02 | Mondes et level design | Tuiles voxel des 3 mondes, assemblage semi-procédural, autels, lumière | Studio, make-map, worldbuilding | 2 | En cours | Code A02-01 et A02-08 sur claude/a02-assemblage, attend les tuiles de Clément |
| A03 | Ennemis et boss | Familles d'ennemis, IA, Overtime, variantes capturables, 3 mini-boss, 3 boss | Studio, systems | 2 | En cours | Cantin (code) ; Clément : modèles faits avec Claude Design, fiches écrites par a03-ennemis |
| A04 | Gameplay | 8 classes, 16 armes, 14 Runes, 40 objets, cartes, fusion, run de 3 mondes, compteur de KO | Studio, system-builder | 1 | En cours | Cantin (dev) |
| A05 | Compagnons et capture | Capture, collection, IA des compagnons, personnalisation | Studio, systems | 2 | En cours | Cantin (dev) |
| A06 | Mouvement et caméra | Caméra 3e personne, bunny-hop, glissade, contrôles tactiles, MovementGuard | Studio, make-anim | 1 | En cours | Cantin (dev) |
| A07 | VFX | Armes, impacts, KO, capture, télégraphes de boss, ambiance Overtime | Studio, fwjelaa-vfx, VFX de l'Asset Pack | 2 | À faire | À lancer |
| A08 | UI et HUD | Maquettes Figma puis HUD de run, cartes, chrono, compteur de KO, écran de fin | Figma, Studio, fwjelaa-ui, ui-builder | 1 | En cours | a08-ui-hud (Clément) : UI v3 en briques montée dans COHUE |
| A09 | Menus et lobby | Maquettes Figma puis hub 3D, choix de classe, collection, boutique, tableaux de classement | Figma, Studio, make-map | 1 | En cours | a09-menus-lobby (Clément) : lobby jouable monté dans COHUE |
| A10 | Sound design | Musiques et sons du Creator Store, SoundController, mixage | Studio, fwjelaa-sfx | 2 | En cours | Cantin (code), Clément (sons) |
| A11 | Anti-triche et sécurité | Audit des remotes, de l'économie et des achats ; correctifs ; revue à chaque vague | anti-exploit-review, secure-remotes, agent red-team, /audit | 1 | En cours | Cantin (dev) |
| A12 | Données, progression et monétisation | Sauvegarde, collection, quêtes, classements hebdo, boutique cosmétique, nom anglais | datastore-safety, monetization-compliance, agents revenue-modeler et market-analyst | 2 | À faire | Cantin (dev) |
| A13 | Perf mobile et QA | Budgets de perf, plafond d'ennemis, tests, équilibrage, liste de bugs | performance-audit, debugging, agent scope-auditor | 3 | En cours | Cantin (dev) |
| A14 | Armes : modèles et effets | 16 armes et 16 fusions en pixel art extrudé, effets lisses et lumineux (armes, ennemis, boss) posés en objets | Blender, Studio, fwjelaa-vfx, make-model | 2 | En cours | a14-armes (Clément) : armes et effets v1 dans COHUE, effets v2 prêts |

## Éléments à réaliser

L'inventaire compte environ 140 éléments de contenu. Chaque ligne passe à Fait quand l'élément est jouable dans la place partagée, pas seulement modélisé ou codé.

### Classes (8)

| Classe | Équipement voxel (3 paliers : niv. 10, 20, 30) | Agents | Statut |
| --- | --- | --- | --- |
| Knight | Heaume, épaulettes, cape | A01, A04 | À faire |
| Archer | Capuche, carquois, brassard | A01, A04 | À faire |
| Mage | Chapeau pointu, cape étoilée, orbe flottant | A01, A04 | À faire |
| Guardian | Casque massif, plastron, grand bouclier dorsal | A01, A04 | À faire |
| Rogue | Masque, foulard, ceinture de dagues | A01, A04 | À faire |
| Cleric | Mitre, étole, auréole | A01, A04 | À faire |
| Barbarian | Casque à cornes, fourrures, peintures de guerre | A01, A04 | À faire |
| Tamer | Chapeau de dompteur, sacoche, sifflet | A01, A04 | À faire |

### Armes (16) et fusions

| Arme | Comportement | Agents | Statut |
| --- | --- | --- | --- |
| Broadsword | Arc de taille devant soi (Knight) | A04, A01, A07 | À faire |
| Longbow | Flèches automatiques qui transpercent (Archer) | A04, A01, A07 | À faire |
| Fire Staff | Boule de feu qui explose en zone (Mage) | A04, A01, A07 | À faire |
| Quake Hammer | Onde de choc circulaire au sol (Guardian) | A04, A01, A07 | À faire |
| Throwing Daggers | Éventail de dagues (Rogue) | A04, A01, A07 | À faire |
| Holy Aura | Aura de dégâts autour du joueur (Cleric) | A04, A07 | À faire |
| Spinning Axes | Haches lancées en spirale vers l'extérieur (Barbarian) | A04, A01, A07 | À faire |
| Beast Whip | Balayage à 360° (Tamer) | A04, A01, A07 | À faire |
| Lightning Chain | Éclair qui rebondit entre ennemis | A04, A07 | À faire |
| Frost Nova | Onde de gel autour du joueur | A04, A07 | À faire |
| Boomerang | Aller-retour qui transperce | A04, A01, A07 | À faire |
| Bomb Bag | Bombes lancées qui explosent | A04, A01, A07 | À faire |
| Spear Throw | Lance en ligne droite qui transperce | A04, A01, A07 | À faire |
| Meteor Rain | Météores aléatoires à grande zone | A04, A07 | À faire |
| Orbiting Blades | Lames en orbite autour du joueur | A04, A01, A07 | À faire |
| Crossbow Turret | Pose une arbalète-tourelle 8 s | A04, A01, A07 | À faire |
| 8 fusions | Une par arme de départ, nouveau look à chaque fois (si le point 2 est confirmé) | A04, A01, A07 | À faire |

### Runes et objets

| Élément | Détail | Agents | Statut |
| --- | --- | --- | --- |
| 14 Runes | Damage, Attack Speed, Projectiles, Area, Duration, Cooldown, Crit, Luck, Wisdom, Magnet, Vitality, Armor, Agility, Cursed | A04, A08 (icônes) | À faire |
| Icônes des 14 Runes | Style glossy cartoon, lisibles en 48 px | A08 | À faire |
| 40 objets | 4 raretés, effets passifs ou à déclenchement, liste à écrire | A04 | À faire |
| Icônes des 40 objets | Style glossy cartoon, bordure de rareté | A08 | À faire |

### Ennemis et créatures capturables

Chaque espèce de base a aussi une variante capturable (aura et icône) : environ 15 créatures à collectionner au lancement.

| Ennemi | Monde | Comportement | Agents | Statut |
| --- | --- | --- | --- | --- |
| Goblin Grunt | 1 | Essaim, fonce sur le joueur | A01, A03 | À faire |
| Goblin Archer | 1 | Tireur, flèches lentes et lisibles | A01, A03 | À faire |
| Goblin Shaman | 1 | Soigne et accélère les gobelins proches | A01, A03 | À faire |
| Goblin Bomber | 1 | Fonce et explose (gag : il vole ton XP au passage) | A01, A03 | À faire |
| Faune de la forêt | 1 | Gland Grincheux, Champignon Sauteur, Hibou Plongeur (modèles existants à revoir en voxel) | A01, A03 | À faire |
| Zombie Shambler | 2 | Essaim lent mais très nombreux | A01, A03 | À faire |
| Zombie Runner | 2 | Rapide, faible | A01, A03 | À faire |
| Zombie Bloater | 2 | Lent, lourd, explose en nappe à sa mort | A01, A03 | À faire |
| Gravedigger | 2 | Sauteur qui surgit du sol | A01, A03 | À faire |
| Zombie en tutu | 2 | Gag absurde : danse, puis charge | A01, A03 | À faire |
| Wisp | 3 | Essaim flottant | A01, A03 | À faire |
| Poltergeist | 3 | Tireur qui lance des objets d'école | A01, A03 | À faire |
| Banshee | 3 | Cri qui ralentit en zone | A01, A03 | À faire |
| Armure hantée | 3 | Blindé, bloque les couloirs | A01, A03 | À faire |
| Fantôme de surveillant | 3 | Gag : siffle et rassemble les fantômes | A01, A03 | À faire |
| Élites | Tous | Contour doré, PV x6, lâchent un coffre | A03, A07 | À faire |
| Variantes capturables | Tous | Aura, icône, cage de capture au sol 10 s | A01, A03, A05, A07 | À faire |

### Mini-boss et boss

| Nom de travail | Monde | Rôle | Agents | Statut |
| --- | --- | --- | --- | --- |
| Chef gobelin | 1 | Mini-boss | A01, A03 | À faire |
| Grand Chêne Ronchon | 1 | Boss (modèle existant à revoir en voxel) | A01, A03, A07 | À faire |
| Ogre zombie | 2 | Mini-boss | A01, A03 | À faire |
| Boss du monde 2 | 2 | Boss à inventer | A01, A03, A07 | À faire |
| Le Pion Spectral | 3 | Mini-boss | A01, A03 | À faire |
| La Directrice Éternelle | 3 | Boss final | A01, A03, A07 | À faire |

### Mondes et lobby

| Lieu | Contenu | Agents | Statut |
| --- | --- | --- | --- |
| Lobby (hub 3D) | Village voxel : présentoirs de classes, enclos des compagnons, boutique, tableaux de classement, portail de file | A09, A01, A02 | À faire |
| Monde 1 — Bois Grognon | Tuiles de forêt, falaises, autels, arène du boss | A02, A01 | À faire |
| Monde 2 — cimetière ou marais | Tuiles, tombes, brume, arène du boss | A02, A01 | À faire |
| Monde 3 — Récré Fantôme | École hantée la nuit, toits, préaux, arène du boss | A02, A01 | À faire |
| Portails entre mondes | Transition, écran de chargement | A02, A07, A08 | Code fait (A02-08), attend les gabarits |
| Lumière diorama | Bloom, profondeur de champ, lumière chaude par monde | A02, A07 | À faire |

### Écrans

| Écran | Contenu | Agents | Statut |
| --- | --- | --- | --- |
| HUD de run | PV, bouclier, niveau, barre d'XP, armes et Runes | A08 | À faire |
| Chrono et Overtime | Compte à rebours, bascule en chronomètre rouge qui monte | A08 | À faire |
| Compteur de KO | Gros chiffre visible, record perso affiché | A08 | À faire |
| Cartes de niveau | 3 cartes en bas, rareté visible, 8 s pour choisir | A08 | À faire |
| Mini-carte | Autels, coffres, boss, coéquipiers, capturables | A08 | À faire |
| Boutons mobiles | Saut, Glisser, Capture | A08, A06 | À faire |
| Barre de capture | Progression 2 s, annulée si touché | A08, A05 | À faire |
| Victory | Bannière, choix Cash out ou Keep going | A08 | À faire |
| Écran de fin | KO, dégâts par arme, gains, rang au classement, Play again | A08 | À faire |
| À terre et relève (coop) | 25 s pour être relevé, mode fantôme | A08 | À faire |
| Pings | 6 pings contextuels | A08 | À faire |
| Écran titre et chargement | Logo, chargement entre places | A09 | À faire |
| Choix de classe | Avatar en rotation, équipement qui apparaît | A09 | À faire |
| Collection de compagnons | Créatures capturées, équipement, personnalisation | A09, A05 | À faire |
| Boutique cosmétique | Skins, effets, passes, prix en Robux | A09, A12 | À faire |
| Classements | Hebdo et all-time, KO en une run | A09, A12 | À faire |
| Quêtes | Liste, progression, récompenses | A09, A12 | À faire |
| Réglages | Qualité, son, contrôles, accessibilité | A09 | À faire |
| File et groupe | Solo, amis, public, jusqu'à 4 | A09 | À faire |

### VFX

| Effet | Détail | Agents | Statut |
| --- | --- | --- | --- |
| Effets des 16 armes | Tir, trajectoire, impact | A07 | À faire |
| KO | Éclatement en cubes voxel, sans gore | A07 | À faire |
| XP et niveau | Ramassage, montée de niveau | A07 | À faire |
| Coffres et objets | Ouverture, rareté | A07 | À faire |
| Capture | Cage, chargement, réussite | A07 | À faire |
| Télégraphes de boss | Cercle au sol 1 s avant l'attaque | A07 | À faire |
| Bascule en Overtime | Ciel et lumière qui virent au rouge | A07, A02 | À faire |
| Portail entre mondes | Ouverture, traversée | A07 | À faire |
| Fusion d'arme | Moment fort, plein écran court | A07 | À faire |
| Aura des élites et capturables | Contour doré, aura de capture | A07 | À faire |
| Autels | Charge, récompense | A07 | À faire |
| Effets de KO cosmétiques | Variantes vendues en boutique | A07, A12 | À faire |

### Sons et musique

| Son | Détail | Agents | Statut |
| --- | --- | --- | --- |
| Musique du lobby | Joyeuse, en boucle | A10 | À faire |
| Musique des 3 mondes | Une par monde | A10 | À faire |
| Musique de boss | Une par boss ou une commune | A10 | À faire |
| Musique d'Overtime | Intensité qui monte avec le chrono | A10 | À faire |
| Sons des 16 armes | Tir et impact | A10 | À faire |
| KO et ramassage | KO, XP, niveau, cartes | A10 | À faire |
| Interface | Clics, achats, notifications | A10 | À faire |
| Cris des créatures | Par famille (gobelins, zombies, fantômes, boss) | A10 | À faire |
| Capture | Chargement, réussite | A10 | À faire |
| Ambiances et annonces | Par monde ; annonces d'Overtime et de boss | A10 | À faire |

### Animations

| Animation | Détail | Agents | Statut |
| --- | --- | --- | --- |
| Mouvement du joueur | Glissade, bunny-hop, atterrissage lourd, plané | A06 | À faire |
| Attaques du joueur | 5 gestes : taille, tir à l'arc, sort, lancer, frappe au sol | A06 | À faire |
| Capture et victoire | Geste de capture, 3 poses de victoire | A06 | À faire |
| Ennemis | Marche, attaque, mort par espèce | A01, A03 | À faire |
| Boss | Entrée, 2 à 3 attaques, mort | A01, A03 | À faire |
| Compagnons | Suivre, attaquer, être content | A01, A05 | À faire |

### Cosmétiques (boutique)

| Cosmétique | Détail | Agents | Statut |
| --- | --- | --- | --- |
| Skins d'équipement de classe | Variantes de couleur et de forme | A01, A12 | À faire |
| Chapeaux de compagnon | Accessoires voxel | A01, A12 | À faire |
| Couleurs et auras de compagnon | Personnalisation | A01, A07, A12 | À faire |
| Effets de KO | Voir VFX | A07, A12 | À faire |
| Traînées | Derrière le joueur | A07, A12 | À faire |
| Emotes et poses de victoire | Dans le lobby et en fin de run | A06, A12 | À faire |
| Pass VIP | Cosmétique + serveur privé | A12 | À faire |
| Pass saisonnier | Récompenses cosmétiques, gratuit + payant | A12 | À faire |

## Tâches par agent

102 tâches au total, dont 53 bloquantes (P0). Chaque agent passe ses lignes à En cours, À valider ou Fait au fil de l'eau ; « À valider » veut dire que Clément doit regarder le livrable.

### A00 — Chef de projet

| ID | Tâche | Livrable | Dépend de | Priorité | Statut |
| --- | --- | --- | --- | --- | --- |
| A00-01 | Installer fwjelaa et relier l'Asset Pack aux deux plugins | Plugin installé, dossiers liés |  | P0 — bloquant | Fait |
| A00-02 | Écrire les décisions v2 | `docs/dossier/01-decisions-v2.md` |  | P0 — bloquant | Fait |
| A00-03 | Créer ce doc de suivi | Ce doc |  | P0 — bloquant | Fait |
| A00-04 | Lancer les 6 conversations de la vague 1 | Liens dans L'équipe d'agents | A00-02 | P0 — bloquant | Fait |
| A00-05 | Mettre `ARCHITECTURE.md` à jour avec les ids v2 | Contrat v2 | A04-01 | P0 — bloquant | À valider |
| A00-06 | Fusionner les branches de la vague 1 dans main et dans la place partagée | main + `COHUE-test.rbxlx` | Fin de vague 1, A11-05 | P0 — bloquant | En cours |
| A00-07 | Porte de vague 1 : démo jouable pour Clément | Session de test | A00-06 | P0 — bloquant | À faire |
| A00-08 | Lancer les conversations de la vague 2 | 5 conversations | A00-07 | P0 — bloquant | À faire |
| A00-09 | Créer l'univers avec la place lobby et la place de run | 2 places publiées en privé | A09-04 | P1 — lancement | À faire |
| A00-10 | Dossier Select 9-15 et publication | Jeu approuvé et public | Vague 3 | P1 — lancement | À faire |

### A01 — DA et modeling

| ID | Tâche | Livrable | Dépend de | Priorité | Statut |
| --- | --- | --- | --- | --- | --- |
| A01-01 | Guide de style **tout en tenons, formes naturelles** (choix de Clément le 5 nov., piste B ; tenons posés par Resurface) : palette COHUE 16, proportions, règles de lisibilité dans la horde, planches de référence | `docs/dossier/80-direction-artistique.md` + planches |  | P0 — bloquant | À valider |
| A01-02 | Pipeline voxel Blender vers Roblox (échelle, triangles, export, import) testé sur 1 modèle | Note de pipeline + 1 modèle dans Studio | A01-01 | P0 — bloquant | En cours |
| A01-03 | Équipement des 3 classes gratuites (Knight, Archer, Mage), 3 paliers chacun | 9 accessoires | A01-02 | P0 — bloquant | En cours |
| A01-04 | Gobelins du monde 1 : 4 espèces + variante capturable | 4 modèles | A01-02 | P0 — bloquant | En cours |
| A01-05 | Modèles des 8 armes de départ | 8 modèles | A01-02 | P1 — lancement | En cours |
| A01-06 | Kit de props du monde 1 : arbres, rochers, falaises, autels, coffres, pots | Kit | A01-02 | P1 — lancement | À faire |
| A01-07 | Équipement des 5 autres classes | 15 accessoires | A01-03 | P1 — lancement | À faire |
| A01-08 | Zombies et fantômes des mondes 2 et 3 | 10 modèles | A01-04 | P1 — lancement | À faire |
| A01-09 | Mini-boss et boss | 6 modèles | A01-04 | P1 — lancement | À faire |
| A01-10 | Cosmétiques de lancement : skins, chapeaux de compagnon | Lot cosmétique | A12-04 | P2 — après lancement | À faire |

### A04 — Gameplay

| ID | Tâche | Livrable | Dépend de | Priorité | Statut |
| --- | --- | --- | --- | --- | --- |
| A04-01 | Ids v2 des classes, armes et Runes, proposés au chef de projet | Contract request |  | P0 — bloquant | Fait |
| A04-02 | Run de 3 mondes enchaînés, Overtime (chrono qui monte, escalade sans plafond), Cash out ou Keep going | RunManager, Config/Run | A04-01 | P0 — bloquant | À valider |
| A04-03 | Compteur de KO serveur par joueur et par run, exposé aux autres services | API dans StatsService |  | P0 — bloquant | Fait |
| A04-04 | Les 3 classes gratuites jouables (arme + passif) | Config/Classes, PassiveService | A04-01 | P0 — bloquant | À valider |
| A04-05 | Les 8 armes de départ | Config/Weapons, WeaponService | A04-01 | P0 — bloquant | À valider |
| A04-06 | Les 14 Runes | Config des Runes |  | P1 — lancement | Fait |
| A04-07 | Les 8 armes du pool commun | Config/Weapons | A04-05 | P1 — lancement | Fait |
| A04-08 | Les 40 objets | Config/Items |  | P1 — lancement | Fait |
| A04-09 | Les fusions d'armes (si le point 2 est confirmé) | Config/Weapons | A04-07 | P1 — lancement | Bloqué |
| A04-10 | Les 5 classes à débloquer | Config/Classes | A04-04 | P1 — lancement | À valider |
| A04-11 | Tous les textes joueur en anglais | Configs |  | P1 — lancement | Fait |
| A04-12 | Premier équilibrage : un joueur moyen bat le monde 1 dans 70 à 80 % des runs | Rapport | A13-04 | P1 — lancement | À faire |

### A06 — Mouvement et caméra

| ID | Tâche | Livrable | Dépend de | Priorité | Statut |
| --- | --- | --- | --- | --- | --- |
| A06-01 | Caméra 3e personne pensée mobile : dézoom pour lire la horde, pas de caméra dans les murs, sensibilité réglable | CameraController |  | P0 — bloquant | À valider |
| A06-02 | Revoir bunny-hop, glissade, glissade en pente et saut tampon avec la nouvelle caméra | MovementController, Config/Movement | A06-01 | P0 — bloquant | À valider |
| A06-03 | Mouvement par classe : double saut (Rogue), saut haut (Archer), plané (Mage), atterrissage lourd (Guardian) | Config/Movement | A04-01 | P1 — lancement | À valider |
| A06-04 | Contrôles tactiles et manette avec l'Input Action System | InputController |  | P0 — bloquant | À valider |
| A06-05 | MovementGuard calé sur les nouvelles vitesses max | MovementGuard | A06-03 | P0 — bloquant | À valider |
| A06-06 | Animations du joueur : glissade, atterrissage, 5 gestes d'attaque, capture | Animations publiées | A06-02 | P1 — lancement | À faire |
| A06-07 | Tremplins, tyroliennes et geysers pour la verticalité | Modules + fiches pour A02 |  | P2 — après lancement | À valider |

### A08 — UI et HUD

| ID | Tâche | Livrable | Dépend de | Priorité | Statut |
| --- | --- | --- | --- | --- | --- |
| A08-01 | Design system glossy cartoon dans Figma : couleurs, typo, boutons, cadres, icônes, couleurs de rareté | Fichier Figma | A01-01 | P0 — bloquant | Fait |
| A08-02 | Maquettes Figma des 11 écrans de run, mobile et PC | Fichier Figma | A08-01 | P0 — bloquant | Fait |
| A08-03 | Validation des maquettes par Clément | Accord de Clément | A08-02 | P0 — bloquant | À valider |
| A08-04 | Thème studs dans Roblox, UI montée en dur | UITheme | A08-03 | P0 — bloquant | En cours |
| A08-05 | HUD, chrono et Overtime, compteur de KO | HUD | A08-04, A04-02, A04-03 | P0 — bloquant | En cours |
| A08-06 | Cartes de niveau, barre de capture, Victory, écran de fin | CardUI, EndScreen | A08-04 | P1 — lancement | En cours |
| A08-07 | Icônes des 14 Runes, 40 objets et 16 armes | Images | A08-01 | P1 — lancement | À faire |
| A08-08 | Accessibilité : daltonisme, taille de texte, réduction des flashs | SettingsUI | A08-05 | P1 — lancement | À faire |

### A09 — Menus et lobby

| ID | Tâche | Livrable | Dépend de | Priorité | Statut |
| --- | --- | --- | --- | --- | --- |
| A09-01 | Maquettes Figma des 8 écrans de menu, dans le design system de A08 | Fichier Figma | A08-01 | P0 — bloquant | Fait |
| A09-02 | Plan du hub 3D : zones et parcours du joueur de l'arrivée au portail | Plan + note | A01-01 | P0 — bloquant | Fait |
| A09-03 | Validation des maquettes et du plan par Clément | Accord de Clément | A09-01, A09-02 | P0 — bloquant | Fait |
| A09-04 | Construire le hub voxel dans sa propre place | Place lobby | A09-03, A01-06 | P1 — lancement | À faire |
| A09-05 | Choix de classe et file solo, amis ou public, avec téléportation vers la run | LoadoutUI, MatchService | A09-04 | P1 — lancement | À faire |
| A09-06 | Tableaux de classement 3D dans le hub | Module lobby | A12-02 | P1 — lancement | À faire |
| A09-07 | Collection de compagnons et boutique | Écrans du lobby | A05-02, A12-04 | P1 — lancement | À faire |

### A11 — Anti-triche et sécurité

| ID | Tâche | Livrable | Dépend de | Priorité | Statut |
| --- | --- | --- | --- | --- | --- |
| A11-01 | Audit complet du code existant (/audit, anti-exploit-review, agent red-team) | `docs/security/audit-v1.md`, failles classées ; statut réel au 5 nov. (13 corrigées ou fermées, S-06 / S-10 / S-15 chez A12) |  | P0 — bloquant | À valider |
| A11-02 | Corriger les failles critiques des fichiers que personne d'autre ne touche en vague 1 (DataService, MonetizationService, LootService, ShrineService, Net) | Branche `claude/a11-failles` : S-11 (`Net`), S-16 nouvelle (réapparition après reset, `RunManager`) ; S-05, S-07, S-09, S-12 déjà fermées par A04 | A11-01 | P0 — bloquant | À valider |
| A11-03 | Lister les failles des fichiers des autres agents pour le chef de projet | Liste dans le rapport | A11-01 | P0 — bloquant | À valider |
| A11-04 | Règles anti-triche des nouveaux systèmes : KO, capture, Overtime, classement hebdo | Note | A04-02 | P0 — bloquant | À valider |
| A11-05 | Revue de sécurité de chaque branche avant fusion | Verdict par branche : `docs/security/revues-vague2.md` (A03, A05, A10, A12, A14 fusionnables ; A02, A06, A13 pas encore poussés) | Fin de chaque vague | P0 — bloquant | En cours |
| A11-06 | Tests d'exploits en Play : vitesse, téléportation, spam de remotes | Scripts prêts : `docs/security/tests-exploits.md` (T0-T8, à lancer par le chef de projet) ; rapport après le Play | A06-05 | P1 — lancement | En cours |

### A02 — Mondes et level design (vague 2)

| ID | Tâche | Livrable | Dépend de | Priorité | Statut |
| --- | --- | --- | --- | --- | --- |
| A02-01 | Format des tuiles et règles d'assemblage semi-procédural | Note + prototype | A01-01 | P0 — bloquant | Fait (note 21 + WorldBuilder, branche claude/a02-assemblage) |
| A02-02 | Monde 1 : 12 tuiles, arène du boss, point d'apparition | Monde 1 jouable | A01-06 | P0 — bloquant | À faire |
| A02-03 | Environ 15 autels par monde, en hauteur et en recoins | Placement | A02-02 | P1 — lancement | À faire |
| A02-04 | Heightmap des tuiles pour la horde | Heightmap | A02-02 | P0 — bloquant | Code fait (TileLayout), à tester avec les tuiles |
| A02-05 | Lumière diorama par monde | Réglages Lighting | A02-02 | P1 — lancement | À faire |
| A02-06 | Monde 2 | Monde 2 jouable | A02-02, A01-08 | P1 — lancement | À faire |
| A02-07 | Monde 3 | Monde 3 jouable | A02-06 | P1 — lancement | À faire |
| A02-08 | Portails entre mondes | Portails | A04-02 | P1 — lancement | Code fait (WorldPortals + WorldTransition), attend les gabarits |

### A03 — Ennemis et boss (vague 2)

| ID | Tâche | Livrable | Dépend de | Priorité | Statut |
| --- | --- | --- | --- | --- | --- |
| A03-01 | Familles d'ennemis v2 : gobelins, zombies, fantômes | Config/Enemies | A01-04 | P0 — bloquant | Fait (branche claude/a03-familles-comportements, à tester en Play) : roster v2 de 16 ennemis, champ `asset` cherché dans Assets puis EnemyVisualRigs, repli bloc si absent |
| A03-02 | Escalade d'Overtime sans plafond visible, avec le plafond technique | EnemyService | A04-02, A13-01 | P0 — bloquant | À faire |
| A03-03 | Variantes capturables : taux d'apparition, aura, cage | EnemyService + API pour A05 | A05-01 | P0 — bloquant | Fait côté A03 (branche claude/a03-familles-comportements, à tester en Play quand A05-02 expose isSpecies et onCapturableDefeated) : taux et PV dans Run.Capturable, remote EnemyCapturable, aura FX_CaptureRing / FX_CaptureIcon |
| A03-04 | Comportements spéciaux (shaman qui soigne, bomber qui vole l'XP, banshee qui ralentit…) | EnemyService | A03-01 | P1 — lancement | Fait (branche claude/a03-familles-comportements, à tester en Play) : Support (soin, hâte, ralenti, rassemblement), Kamikaze (mèche, explosion, vol d'XP si StatsService.takeXp), surgissement, nappe, tir en éventail ; tout en données |
| A03-05 | Les 3 mini-boss | Config + comportement | A01-09 | P1 — lancement | À faire |
| A03-06 | Les 3 boss simples, 2 à 3 attaques télégraphiées | BossService | A01-09 | P1 — lancement | À faire |

### A05 — Compagnons et capture (vague 2)

| ID | Tâche | Livrable | Dépend de | Priorité | Statut |
| --- | --- | --- | --- | --- | --- |
| A05-01 | Règles de la capture : cage, 2 s, interruption, sauvegarde | Note : `docs/dossier/40-compagnons.md` (APIs pour A03 §6.1 et A12 §3.2) |  | P0 — bloquant | À valider |
| A05-02 | Refaire CompanionService : capture, collection, équipement, suivi et attaque | CompanionService | A05-01, A03-03 | P0 — bloquant | À valider |
| A05-03 | Une attaque et 2 à 3 cartes de technique par espèce | Config/Companions | A05-02 | P1 — lancement | À faire |
| A05-04 | Tamer : 2 compagnons, capture plus rapide | CompanionService | A04-10 | P1 — lancement | À valider |
| A05-05 | Emplacements de personnalisation : chapeaux, couleurs, auras | CompanionRenderer | A12-04 | P1 — lancement | À faire |

### A07 — VFX (vague 2)

| ID | Tâche | Livrable | Dépend de | Priorité | Statut |
| --- | --- | --- | --- | --- | --- |
| A07-01 | Bibliothèque VFX voxel avec budget de particules mobile et réglage de qualité | Module + note | A01-01 | P0 — bloquant | À faire |
| A07-02 | Effets des 8 armes de départ | WeaponFX | A04-05 | P0 — bloquant | À faire |
| A07-03 | KO en cubes voxel, XP, montée de niveau | Effets | A07-01 | P0 — bloquant | À faire |
| A07-04 | Capture, télégraphes de boss, Overtime, portails | Effets | A05-02, A03-06 | P1 — lancement | À faire |
| A07-05 | 8 armes du pool et fusions | Effets | A04-07 | P1 — lancement | À faire |
| A07-06 | Effets de KO et traînées cosmétiques | Effets | A12-04 | P2 — après lancement | À faire |

### A10 — Sound design (vague 2)

| ID | Tâche | Livrable | Dépend de | Priorité | Statut |
| --- | --- | --- | --- | --- | --- |
| A10-01 | Liste des sons et musiques, avec le style de chaque monde | Note | A01-01 | P0 — bloquant | À faire |
| A10-02 | Recherche dans le Creator Store, chaque id noté avec sa licence | Config des sons | A10-01 | P0 — bloquant | À faire |
| A10-03 | SoundController : pool, limite de sons simultanés, volumes | Module |  | P0 — bloquant | Codé (branche claude/a10-son), à tester en Play |
| A10-04 | Musique dynamique d'Overtime | Module | A04-02 | P1 — lancement | Codé (branche claude/a10-son), à tester en Play |
| A10-05 | Mixage et réglages de volume | Réglages | A10-03 | P1 — lancement | Codé, réglages locaux ; curseurs et sauvegarde en contract request |

### A12 — Données, progression et monétisation (vague 2)

| ID | Tâche | Livrable | Dépend de | Priorité | Statut |
| --- | --- | --- | --- | --- | --- |
| A12-01 | Sauvegarde v2 (collection, classes débloquées, cosmétiques, records de KO) et migration | DataService | A05-01 | P0 — bloquant | À valider |
| A12-02 | Classements hebdo et all-time des KO, reset lundi 00:00 UTC | Service de classement | A04-03 | P0 — bloquant | À valider |
| A12-03 | Environ 150 quêtes liées aux nouveaux contenus | Config/Quests | A04-10 | P1 — lancement | À faire |
| A12-04 | Boutique cosmétique, pass VIP et pass saisonnier conformes aux règles Roblox | MonetizationService, Products |  | P1 — lancement | À valider |
| A12-05 | Modèle de revenus et grille de prix (agent revenue-modeler) | Note | A12-04 | P1 — lancement | À faire |
| A12-06 | 10 propositions de nom anglais (agent market-analyst) | Note |  | P1 — lancement | À faire |

### A13 — Perf mobile et QA (vague 3, mesures dès la vague 2)

| ID | Tâche | Livrable | Dépend de | Priorité | Statut |
| --- | --- | --- | --- | --- | --- |
| A13-01 | Mesurer le plafond d'ennemis sur un téléphone milieu de gamme | Rapport |  | P0 — bloquant | En cours (scripts prêts : tools/perf, docs/qa/mesure-horde.md ; mesure téléphone à faire par Cantin) |
| A13-02 | Budgets de perf par domaine : mémoire, triangles, particules, réseau | Note |  | P0 — bloquant | Fait (docs/qa/budgets-perf.md) |
| A13-03 | Plan de test et liste de bugs | Doc de test |  | P0 — bloquant | Fait (docs/qa/plan-de-test.md, 11 bugs ouverts) |
| A13-04 | Playtests d'équilibrage : taux de victoire par classe | Rapport | A04-12 | P1 — lancement | À faire |
| A13-05 | Test de charge à 4 joueurs et téléportations | Rapport | A09-05 | P1 — lancement | À faire |
| A13-06 | Checklist de lancement : Select 9-15, monétisation, miniatures | Checklist |  | P1 — lancement | Fait (docs/qa/checklist-lancement.md) |

## Vagues et jalons

&#91;embedded content: feuille de route · 4 vagues, 4 portes\]

La vague 1 pose les fondations dont tout le reste dépend : le style voxel, la boucle de run et le mouvement. La vague 2 démarre quand tu as validé la porte 1 sur une démo jouable.

## Règles de travail communes

Tous les agents suivent ces règles ; elles sont recopiées dans chaque brief de conversation.

- **Sources** : `docs/dossier/01-decisions-v2.md` d'abord, puis `00-vision.md`, puis `docs/ARCHITECTURE.md`.
- **Fichiers** : un agent ne modifie que son périmètre. Pour le reste, il écrit une « Contract request » dans son rapport.
- **Git** : chaque conversation travaille dans sa propre branche, commite à chaque tâche terminée et ne pousse rien. Le chef de projet fusionne après la revue de A11.
- **Studio** : un seul jeu, la place COHUE (placeId 132257920785923). Aucune copie de place par agent. Après chaque fusion, le chef de projet recharge les scripts de main dans COHUE (`tools/studio-load.luau`). Un seul agent teste dans COHUE à la fois, après avoir prévenu le chef de projet, et on ne modifie jamais un script directement dans Studio.
- **Rien construit par script** (décidé par Clément les 4 et 5 nov., UI et effets compris) : tout ce que le joueur voit existe comme objet dans COHUE (StarterGui pour les écrans, ReplicatedStorage.Assets pour UI, FX, créatures, équipement, props, sons). Le code clone et pilote ; il ne crée que l'invisible (remotes, bindables, contraintes, inputs). Règles et liste des modules à convertir : section 12 de `docs/dossier/01-decisions-v2.md`.
- **Blender** : une seule conversation à la fois (A01 en vague 1). Clément lance Blender avec l'addon MCP.
- **Meshy** : budget illimité accordé par Clément ; chaque agent note les crédits dépensés dans son rapport.
- **Figma** : A08 crée le design system, A09 le réutilise.
- **Langue** : textes du jeu en anglais ; doc, dossier et commentaires de code en français.
- **Assets** : d'abord les lignes livrables de l'Asset Pack, ensuite Blender ou Meshy. Jamais d'asset de la Toolbox non vérifié, jamais de nom, de visuel ou de son de Megabonk ou de Pokémon.
- **Suivi** : chaque agent met ses lignes à jour dans ce doc. S'il n'a pas accès au doc, il donne ses statuts dans son rapport et le chef de projet les reporte.

### Checklist anti-AI-slop (avant « À valider »)

1. Respecte le guide de style : palette, taille de voxel, proportions.
2. Lisible à 20 studs au milieu de 100 ennemis, sur un écran de téléphone.
3. Silhouette reconnaissable remplie en noir.
4. Aucune sortie brute non retouchée : modèle Meshy, police par défaut, dégradé par défaut.
5. Au moins une touche d'humour ou de personnalité par élément.
6. Note du skill quality-score d'au moins 8 sur 10.
7. Vérifié en jeu avec une capture Studio, pas seulement dans Blender ou Figma.
8. Budget de perf respecté : triangles, particules, mémoire.

## Risques et parades

Le plus gros risque est que plusieurs agents écrivent en même temps dans la même place Studio ; la règle d'une place par agent le règle.

| Risque | Effet | Parade |
| --- | --- | --- |
| Plusieurs agents dans la même place Studio | Scripts écrasés | Une copie de place par agent, intégration par A00 |
| Branches qui touchent les mêmes fichiers | Fusions longues et cassées | Périmètres stricts, fusion à chaque fin de vague |
| Style différent d'un agent à l'autre | Rendu « AI slop » | Guide de style A01-01 avant toute production, checklist ci-dessus |
| Horde trop lourde pour les téléphones | Crashs, avis négatifs | Plafond technique mesuré (A13-01), escalade par la force des ennemis |
| Capture perçue comme du hasard payant | Refus par Roblox | Capture gratuite et sans hasard |
| Noms ou visuels trop proches de Megabonk ou Pokémon | Retrait du jeu | Noms originaux, revue avant publication |
| Classement truqué | Joueurs dégoûtés | KO comptés par le serveur, règles A11-04 |
| Aucune musique fournie | Jeu muet | Bibliothèque sous licence du Creator Store (A10) |
| Blender non connecté | Modeling bloqué | Clément lance Blender avec l'addon MCP |
| Délai d'évaluation Select 9-15 | Lancement retardé | Dossier préparé dès la vague 3 (A13-06, A00-10) |

## Journal

| Date | Événement |
| --- | --- |
| 2026-11-05 | Côté créatif (Clément) : Clément fait les modèles d'ennemis avec Claude Design. Le premier, le fantôme, est dans COHUE (`Workspace.Ghostenemy`) : couleurs posées, taille ×2, il vole et tire son orbe. A03 écrit une fiche Claude Design par ennemi (`docs/dossier/fiches-claude-design/`, Goblin Grunt prêt, 20 à suivre). A14 a ses effets v2 prêts (ruban d'épée, traits de lumière, Bloom) et attend l'accord de Clément pour les écrire dans COHUE. |
| 2026-11-05 | Côté créatif monté dans COHUE et fusionné : armes A14 en pixel art extrudé (35 modèles, 86 mailles) et leurs effets ; UI v3 en vraies briques d'A08 (HUD, écran à terre, fenêtre de niveau et gel coop, icônes des 32 armes) ; lobby jouable d'A09 (PLAY, barre du bas, choix Solo / Friends / Public, apparition au lobby). Décisions v2 §12 (rien construit par script, UI et effets compris) et §13 (créatif chez Clément, technique chez Cantin). |
| 2026-11-05 | Vague dev de Cantin fusionnée dans main (600d5e3) : A02 (assemblage des tuiles, portails), A03 (familles v2, comportements, capturables), A05 (capture, CompanionService, Tamer), A06 (validation, tremplins et tyroliennes), A10 (SoundController), A11 (failles S-11 et S-16, tests d'exploits, revues), A12 (classements, boutique, sauvegarde v2), A13 (budgets de perf, plan de test, checklist). 95 fichiers passent tools/check.sh. Script Sync actif chez Cantin seulement, sur la racine du dépôt ; les deux Main renommés en Main.legacy.luau et Main.local.luau (noms de Studio). Play : apparition OK, aucune erreur de script. Reste : contract requests du lead (Bus.PlayerHit, RunManager.isFrozen, ARCHITECTURE.md), gabarits visuels et sons à fournir par Clément. |
| 2026-11-05 | Partage du travail : Cantin reprend tout le développement (A03 à A06, A11 à A13, et la partie code de A02, A07 à A10) ; Clément garde le design et la 3D. A06 (garde serveur durci, suivis A11, relecture 3) et A03 (dossier 13) fusionnés dans main (384fc3c), 84 fichiers passent tools/check.sh. Les 5 scripts A06 rechargés dans COHUE, identiques à main. Play test : apparition OK, MovementGuard actif sans strike, aucune erreur de script. A14 (effets v2 non testés en Play) laissé à Clément. |
| 2026-11-05 | Clément étend la règle « rien construit par script » à l'UI et aux effets. 23 modules fabriquent encore du visible (UI A08, rendus A03 et A05, équipement A04, mondes A02, effets A07) : chaque agent convertit les siens à son tour. Lobby Hubbub Village sauvegardé dans COHUE ; A01 prépare le test Resurface (style tout en tenons). |
| 2026-11-04 | Un seul jeu : tout fusionné dans main (A04, A06, A01, A08, A09, plus le travail de Codex) et chargé dans la place COHUE. Run de test sans erreur : HUD glossy, World 1/3, KO, cartes. main poussé sur GitHub (5acfa4d). |
| 2026-11-04 | main poussé sur github.com/clementronde/COHUEROBLOX (dd65a9c). A04 (a1e45bb) et A06 (145ade3) ont corrigé les failles de A11 ; A11 relit les deux branches. A01, A06 et A08 relancés après la limite d'usage. |
| 2026-11-04 | A04 et A11 fusionnés dans main après la revue A11-05 (fusionnable). 75 fichiers passent tools/check.sh. Failles de A11 transmises à A04 et A06. La place COHUE dans Studio n'a pas encore les nouveaux scripts (Script Sync inactif). |
| 2026-11-04 | Vague 1 lancée : a01-da-voxel, a04-gameplay, a06-mouvement, a08-ui-hud, a09-menus-lobby, a11-anti-triche |
| 2026-11-04 | Doc de suivi créé ; décisions v2 écrites dans `docs/dossier/01-decisions-v2.md` |
| 2026-11-04 | fwjelaa installé dans `C:\Vaults\fwjelaa` ; Asset Pack relié aux plugins fwjelaa et LihFolk |
| 2026-11-04 | Questionnaire : 38 réponses de Clément, 7 questions laissées aux valeurs par défaut |
| 2026-11-04 | Avant la v2 : architecture, 75 fichiers Luau et 15 créatures générées |
| 2026-11-04 | A08 : fichier Figma du design system UI (couleurs + mode daltonien, typo, boutons, cadres, barres, badges, 24 icônes, cartes de rareté) et des 33 maquettes de run (11 écrans × paysage, portrait, PC) : [COHUE — UI Design System & Run Screens](https://www.figma.com/design/0Yq5m1skq5dzgOQXZ9bG6D). A09 : réutiliser ses variables, styles et composants pour les menus. |
| 2026-11-04 | A08 : design system + 33 maquettes à valider par Clément. Note quality-score : 7,9/10 (médiane de 3 relecteurs à l'aveugle après 3 tours, contre 5,0 au départ), critères bloquants OK. Il manque 0,1 sous le seuil de 8 : petits libellés sur la horde et densité du HUD, qui demandent un choix de Clément. Bibliothèque Figma à publier par Clément pour A09 (Assets → Publish). |
| 2026-11-04 | Clément valide les maquettes UI A08. Questions ouvertes laissées aux choix des maquettes : Victory = choix par joueur, fantôme = retour au monde suivant, raccourcis R/S/B et C/K, monnaie « Silver ». A08 passe à l'intégration Roblox. |
| 2026-11-05 | A08 : virage demandé par Clément, DA en studs et UI montée en dur dans Studio (plus générée par le code). Figma restylé en studs avec la texture kek\_stud de son pack : boutons, boutons tactiles carrés, cartes, barres, badges, pings, et nouvelle barre de titre de fenêtre (WindowHeader + croix rouge) pour Victory, À terre et Fin de run. Les 33 maquettes sont à revalider par Clément. Ensuite : envoi de la tuile de studs sur Roblox, montage des ScreenGui dans le place COHUE (avec accord du lead), scripts UI branchés sur les instances. Le pack KekUIEssentials n'a pas de fichier de licence : Clément confirme le droit d'usage. |
| 2026-11-05 | A08 : la v2 studs a été jugée « AI slop » par Clément. Concept v3.2 « vraies briques » à la place (icônes montées en briques avec les outils d'A01, Fredoka One, HUD sans pastilles, Victory en cartes, aperçu animé « Clic de brique »). Relecture à l'aveugle de la v3.1 : 6,7/10. Nouvel écran de passage de niveau, décidé par Clément : le jeu se fige pour tout le monde en coop, fenêtre au centre (offres), inventaire à gauche, stats à droite. Contract request à A04 : pause globale de la run, remote LevelUpPause, 15 s de choix en coop (proposition). |
| 2026-11-05 | A08 : direction v3 « vraies briques » étendue à toute l'UI de run (13 écrans × téléphone paysage, portrait et PC) et au lobby validé par Clément (gros bouton PLAY, barre de 7 menus, choix Solo / Friends / Public). La bibliothèque « Components v3 — briques » est réutilisable par A09. Relecture à l'aveugle en deux passes : médiane 7,5/10 ; défauts corrigés après, sans nouvelle notation. Il reste à décider : formes de fenêtres plus variées et moins de chiffres affichés. Branche claude/a08-ui-00ecaf (576b84e). |
