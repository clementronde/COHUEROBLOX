# 65 — Lobby : hub 3D et menus (domaine A09)

Statut : **5 nov. 2026 : le lobby passe à un bouton Play et une barre de menus** (décision de Clément, `01-decisions-v2.md` §7). Ce dossier est réécrit pour ce flux. Restent valables : les 8 écrans de menu et leur habillage (validés le 4 nov.), et les réponses du 4 nov. (§12). Rien n'est construit en vague 1.
Sources : `01-decisions-v2.md` (fait foi), `80-direction-artistique.md` (tout en tenons), `00-vision.md` §5.1, §11.3, §12.1, `70-donnees-progression-monetisation.md` §6, §8, §9, §13, §15, `60-ui-ux.md`.

Le lobby se pilote par l'UI. Un gros bouton **PLAY** lance une run en deux touches, et une **barre de 8 boutons** en bas de l'écran ouvre les menus. Le village est un **décor** composé par Clément avec le kit d'A01 : un bâtiment par menu, avec son nom en grandes lettres de briques, et entrer dans un bâtiment ouvre le même menu. Une première run démarre en **25 à 35 s**.

---

## 0. Ce qui change le 5 nov.

| Sujet | Avant (4 nov.) | Maintenant (5 nov.) |
| --- | --- | --- |
| Lancer une run | Marcher jusqu'aux 3 pads du portail | Bouton **PLAY** → Solo / Friends / Public → START |
| Ouvrir un menu | Stations du village + colonne de boutons à droite | **Barre de 8 boutons en bas** ; entrer dans le bâtiment ouvre le même menu |
| Le village | Plan à coordonnées, construit par A09 | **Décor composé par Clément** avec le kit d'A01 ; un bâtiment par menu |
| Choisir une classe | Présentoirs de la Hero Row | Menu **Classes** (bouton ou bâtiment CLASSES) |
| Style | Voxel | **Tout en tenons** (piste B, `80-direction-artistique.md`) |

Ce qui ne change pas : 8 joueurs par serveur de lobby, Solo mis en avant pour la 1re run, file publique entre joueurs du même serveur, enclos privé, classes verrouillées au cadenas seul, boutique et pass 100 % cosmétiques.

Le plan du 4 nov. ([img/65-lobby-plan.svg](img/65-lobby-plan.svg)) est remplacé : il reste une source d'idées (place compacte, portail visible dès l'arrivée, enclos, podium), pas une carte à construire.

---

## 1. Brief

| Champ | Valeur |
| --- | --- |
| Nom (jeu) | **Hubbub Village**, nom de travail validé par Clément en attendant le nom du jeu |
| Fantasme | Un village de briques joyeux et un peu absurde, où les héros se préparent avant d'aller taper la horde |
| Jeu, dans l'ordre | arrivée → **PLAY** → run ; au retour : classes, compagnons, améliorations, quêtes, classements, boutique |
| Cible | mobile d'abord, 9-15 ans ; **8 joueurs max par serveur de lobby** |
| Style | tout en tenons : décor en gros blocs, objets interactifs en briques fines (`80-direction-artistique.md`) |
| Héros (repère) | le portail en tête de gobelin de pierre (32 studs, maquette A01), vu dès l'arrivée |
| Carte | composée à la main par Clément avec le kit d'A01 ; A09 fournit la liste des bâtiments et leurs règles (§3) |
| Pas ça | pas de panneaux qui expliquent ; pas de cercles « reste ici » au sol ; pas de pop-up d'achat ; pas de compte à rebours d'achat |

### Les jobs du hub, par priorité

1. **Amener un nouveau joueur à sa première run** : ≤ 60 s après la prise de contrôle (cible 25-35 s).
2. **Renvoyer un joueur qui revient en run** : 2 touches (PLAY, START).
3. **Montrer la progression** : classements KO, quêtes, classes à débloquer, améliorations.
4. **Montrer la collection** : compagnons capturés, cosmétiques portés.
5. **Former un groupe** : amis ou public, jusqu'à 4.
6. **Proposer la boutique et le pass**, toujours accessibles, jamais poussés.

---

## 2. Le HUD du hub : PLAY et la barre du bas

Maquette de structure : écran 0 du [Figma](https://www.figma.com/design/cdIWE7AH9ScXZ0uzzLyv4b), capture [img/65-hud-play.png](img/65-hud-play.png). Le style final viendra des composants `Lobby/PlayButton`, `Lobby/BarButton` et `Lobby/Currency` de A08 (v3 « briques », pas encore publiés). Positions sur la référence téléphone 844 × 390 (pixels logiques, `60-ui-ux.md`).

| Élément | Place | Taille | Règle |
| --- | --- | --- | --- |
| **PLAY** | bas, centré, au-dessus de la barre | 220 × 58 | La seule action verte de l'écran (bouton Go de A08, taille L) |
| **Barre du bas** | bas, centrée, entre le joystick et le bouton Saut de Roblox | 8 boutons de 66 × 60, écart 4 (556 px) | Icône + mot ; pas de cadre autour de la barre, le village reste visible |
| Monnaies | haut gauche, après la zone des boutons Roblox | pastilles de 32 px | Étoiles d'argent et jetons de quête. Les Robux n'apparaissent que sur les boutons de prix |
| Réglages | haut droite | 44 × 44 | Bouton engrenage de A08 |
| Joystick, Saut | bas gauche, bas droite | Roblox | Rien de notre UI dessous |

**Couleurs** : un bouton de la barre, l'en-tête de son menu et son bâtiment partagent la même couleur (variables `zone/*` de A08). Les couleurs de la barre v3 de A08 diffèrent encore des `zone/*` (par exemple Class violet contre `zone/classes` turquoise) : à aligner par A08.

**Pastilles de nombre** (rouges, sur l'icône) : seulement pour une chose à voir qui ne coûte rien. Quêtes terminées, nouveau compagnon capturé, amélioration abordable avec l'argent gagné. **Jamais sur Shop ni Pass.**

**Première visite** : une flèche animée pointe PLAY, sans texte. Elle disparaît après la 1re run.

### 2.1 Les 8 boutons de la barre (proposition, liste finale avec A08 et Clément)

Le chef de projet a proposé 7 boutons (repris par A08 dans `Lobby/BarButton`). A09 ajoute **Ranks**, parce que le classement hebdo des KO est le pilier du jeu (décisions v2 §1). Ordre : du plus utilisé au moins utilisé, la boutique au bout. Deux libellés diffèrent entre A08 et A09 (Class / Classes, Companions / Critters) : à trancher avec Clément (§12).

| # | Bouton (EN) | Ouvre | Monnaie | Écran |
| --- | --- | --- | --- | --- |
| 1 | **Classes** (A08 : « Class ») | Choix de classe et ses skins | aucune (déblocage par quête) | n° 2, fait |
| 2 | **Critters** (A08 : « Companions ») | Collection de compagnons + style | Robux pour le style seulement | n° 3, fait |
| 3 | **Upgrades** | Boutique d'argent : armes, Runes et objets dans le pool, emplacements, Bannir / Passer / Relancer (`70-donnees` §6) | étoiles d'argent gagnées en run, **jamais de Robux** | nouveau, §6.9 |
| 4 | **Inventory** | Tout ce qu'on possède : skins, styles de compagnon, effets de KO, traînées, emotes, poses, titres ; équiper par emplacement | aucune | nouveau, §6.10 |
| 5 | **Quests** | Quêtes | aucune (récompense automatique) | n° 6, fait |
| 6 | **Ranks** | Classements KO hebdo et all-time | aucune | n° 5, fait |
| 7 | **Pass** | Pass saisonnier cosmétique : piste gratuite + piste payante | Robux pour la piste payante | nouveau, §6.11 |
| 8 | **Shop** | Boutique cosmétique | Robux et jetons | n° 4, fait |

Réglages : bouton engrenage en haut à droite, pas dans la barre.

### 2.2 Le flux PLAY

1. Toucher **PLAY** ouvre l'écran **Queue & Party** (n° 8). **Solo** est présélectionné pour la 1re run ; ensuite, le dernier mode choisi.
2. **START** :
   - **Solo** : décompte de 3 s, bouton « Cancel ».
   - **Friends** : le chef lance pour tout le groupe, avec un décompte de 5 s.
   - **Public** : les joueurs du serveur qui ont choisi Public sont regroupés jusqu'à 4. Départ 10 s après le 1er joueur, remis à 10 s à chaque arrivée, 20 s au plus.
3. Téléportation (MatchService, modes Solo / Party / Public), puis écran de chargement de run (n° 1b).

Entrer dans le portail du village ouvre aussi l'écran Queue & Party.

---

## 3. Le village (décor)

Clément compose la carte avec le kit d'A01 (tout en tenons). A09 ne pose rien dans COHUE et ne construit rien par script ; A09 donne la liste des bâtiments et leurs règles.

### 3.1 Un bâtiment par menu

**Le mot écrit sur le bâtiment est le même que sur le bouton** : un enfant fait le lien sans lire de panneau. Les lettres sont en grosses briques, en anglais. C'est le nom du bâtiment, pas un panneau explicatif.

| Bâtiment (lettres) | Ouvre | Ce qu'on y voit (idées, à composer par Clément) |
| --- | --- | --- |
| **PLAY** (le portail en tête de gobelin) | Queue & Party | Le repère du village, visible dès l'arrivée ; tourbillon lumineux (A07) |
| **CLASSES** | Classes | 8 mannequins avec l'équipement au palier 3 ; les classes verrouillées sont grises, avec un cadenas |
| **CRITTERS** | Critters | L'enclos : ta collection s'y promène (jusqu'à 12, rendus côté client, chacun voit les siens) |
| **UPGRADES** | Upgrades | Une forge : l'enclume brille quand une amélioration est abordable |
| **INVENTORY** | Inventory | Une garde-robe ou un grenier |
| **QUESTS** | Quests | Un tableau de quêtes avec le Hibou Plongeur perché dessus |
| **RANKS** | Ranks | Deux grands tableaux WEEKLY KO / ALL-TIME KO (top 10) et le podium des 3 meilleurs de la semaine en statues |
| **PASS** | Pass | Les récompenses de la saison exposées comme des statues |
| **SHOP** | Shop | La boutique de Gob, gobelin devenu chapelier ; vitrine sans prix ni compte à rebours |

### 3.2 Entrer dans un bâtiment

- Une **zone de porte** invisible devant chaque bâtiment. Quand le joueur y entre, le client ouvre le menu (vérification de la zone toutes les 0,2 s, pas de `Touched`). Le menu ne se rouvre qu'après être sorti de la zone. Pas de `ProximityPrompt` à enchaîner.
- Ouvrir un menu ne change rien côté serveur : tout achat ou équipement passe par les remotes habituels.
- Les zones de porte sont des Parts posées par Clément (nommées `Door_<Menu>`, invisibles, sans collision) : le code les trouve par leur nom.

### 3.3 Règles de composition (conseils pour Clément)

- Arrivée **face au portail** ; centre de la place dégagé, rien ne cache le portail.
- Village compact : chaque bâtiment visible depuis l'arrivée et à moins de 10 s de marche (160 studs).
- Coins où l'on traîne (podium, enclos, bancs) hors de l'axe arrivée → portail.
- Ton compagnon équipé te suit dans le village, et tout le monde le voit.

---

## 4. Parcours d'un nouveau joueur : première run en moins de 60 s

| t | Ce qui se passe | Ce que voit le joueur |
| --- | --- | --- |
| 0 s | Apparition face au portail. **Classe par défaut déjà équipée : Knight.** | Une flèche animée pointe PLAY |
| ~2 s | Touche PLAY | Écran Queue & Party, **Solo** présélectionné |
| ~4 s | Touche START | Décompte de 3 s, « Cancel » |
| ~7 s | Téléportation (MatchService : libération du profil, `TeleportAsync` vers un serveur réservé) | Écran de chargement de run (n° 1b) |
| **~25-35 s** | La run démarre, chrono 10:00 | HUD de run (A08) |

Pas de marche obligatoire, pas de choix obligatoire, pas de texte à lire. Les classes, les compagnons et la boutique se découvrent au retour.

## 5. Joueurs qui reviennent et groupe

- **Retour** : l'écran de fin (A08) propose « Play again » (même équipe, sans repasser par le village). Au village : PLAY puis START.
- **Groupe de 1 à 4** : depuis Queue & Party, « Invite » (invitation d'amis Roblox, `SocialService:PromptGameInvite`) ou toucher un joueur du serveur. Le chef lance pour tout le groupe. Au retour de run, le groupe est reformé (demande de contrat data, §10).
- **Pass VIP** : bouton « Private village » dans Queue & Party (`MatchService.openVipRoom`).

---

## 6. Les écrans de menu

Maquettes Figma : **[COHUE — Menus & Lobby (A09)](https://www.figma.com/design/cdIWE7AH9ScXZ0uzzLyv4b)**. Pages : `00 · Read me`, `01 · Hub plan` (plan du 4 nov., remplacé), `02 · Screens (phone 844×390)`, `03 · Wireframe kit` (composants propres au lobby, liés aux variables A08). Les écrans utilisent la bibliothèque de A08 (« COHUE — UI Design System & Run Screens ») : boutons, couleurs, styles de texte, ombres, et les en-têtes reliés aux variables `zone/<zone>/face` et `zone/<zone>/lip`.

Planche des 8 écrans habillés (4 nov.) : [img/65-maquettes-v2.png](img/65-maquettes-v2.png).

**Style UI en cours de refonte** : Clément a trouvé l'UI de run « en tenons » encore trop AI slop le 5 nov. A08 repart des briques et montre d'abord 1 ou 2 écrans concept. Les écrans du lobby suivront automatiquement les composants de la bibliothèque A08 ; les 3 nouveaux menus (§6.9 à 6.11) seront maquettés après ce concept, pour ne pas dessiner deux fois.

Règles communes :

- textes en anglais ; lisibles sur un téléphone de 6 pouces ; pixels logiques sur la référence 844 × 390 : texte ≥ 12 px, zones tactiles ≥ 44 px, écarts ≥ 8 px ;
- zones réservées (`skip_safe_area`) : encoche, boutons Roblox en haut à gauche, barre du bas ; rien d'interactif dedans ;
- adaptation : panneau flexible, échelle = clamp(min(L / 844, H / 390), 1, 1,6) ; les listes défilent ; sous 780 px de large, la colonne d'aperçu 3D est cachée et remplacée par « VIEW 3D ». Vérifié en 800 × 360 et 667 × 375 ;
- **une seule action verte** par écran, avec un verbe ; un bouton verrouillé dit pourquoi ; la couleur n'est jamais le seul signal ;
- **peu de texte** : pas de sous-titre d'aide sous les boutons.

| # | Écran | Ouvert par | Contenu | Action principale |
| --- | --- | --- | --- | --- |
| 1 | **Title & Loading** | lancement, téléportations | Logo, barre, astuce ; entre places : monde, membres du groupe qui arrivent | aucune |
| 2 | **Classes** | bouton Classes, bâtiment CLASSES | 8 classes (3 gratuites, 5 par quête), avatar qui tourne, arme, passif, mouvement, paliers | EQUIP |
| 3 | **Critters** | bouton Critters, enclos | Collection, 1 équipé (2 pour le Tamer), onglet Style ; pas de renommage | EQUIP |
| 4 | **Shop** | bouton Shop, bâtiment SHOP | Hero gear / Critter style / Effects / Emotes / Passes, prix sur chaque article | le prix |
| 5 | **Ranks** | bouton Ranks, bâtiment RANKS | Weekly / All-time, Global / Friends, podium, ta ligne fixée en bas | aucune |
| 6 | **Quests** | bouton Quests, bâtiment QUESTS | Classes à débloquer en tête, barres, récompenses visibles | aucune |
| 7 | **Settings** | engrenage | Graphismes, son, contrôles, accessibilité | aucune |
| 8 | **Queue & Party** | PLAY, portail | Solo / Friends / Public, 4 places, inviter, Private village | START |
| 9 | **Upgrades** | bouton Upgrades, bâtiment UPGRADES | Boutique d'argent | le prix en argent |
| 10 | **Inventory** | bouton Inventory, bâtiment INVENTORY | Objets possédés, équipement par emplacement | EQUIP |
| 11 | **Pass** | bouton Pass, bâtiment PASS | Paliers de la saison, piste gratuite et piste payante | CLAIM (gratuit) |

### 6.1 Title & Loading

- **Au lancement** : fond du village vu du ciel, logo (« COHUE » en attendant le nom anglais), barre de progression, une astuce par chargement. On passe au village dès que la zone d'arrivée est chargée (`StreamingEnabled`, rayon minimal 64).
- **Entre places** : carte du monde, vignettes des membres du groupe avec une coche quand ils sont arrivés, astuce. Échec de téléportation : « Couldn't start the run. Try again? » et retour au village (MatchService reprend le profil).

### 6.2 Classes

Liste des 8 classes (cartes 2 × 4 sur téléphone), avatar au centre (`ViewportFrame` qui tourne, arrêté si mouvement réduit), fiche : arme de départ, passif, mouvement, paliers d'équipement. Classe verrouillée : silhouette grise avec cadenas (jamais sur l'avatar du joueur), texte de la quête, barre de progression, « See quest ». Skins de classe dans l'onglet « Style », prix sur chaque article, jamais de stat.

### 6.3 Critters

Grille des créatures capturées ; silhouettes « ??? » pour celles qu'on n'a pas encore, avec l'endroit où les trouver. Fiche : attaque, cartes de technique. Onglet **Style** : chapeaux, couleurs, auras, effets, aperçu gratuit, prix sur le bouton. Aucun champ de nom. La capture est gratuite et sûre à 100 %.

### 6.4 Shop

- **100 % cosmétique** : aucune stat, aucune classe, aucune résurrection, aucun objet aléatoire payant.
- **Prix sur chaque article** (Robux ou jetons gagnés en jouant) ; achat par la fenêtre officielle Roblox.
- **Aperçu gratuit** avant tout achat.
- **Aucune pression** : pas de compte à rebours, pas de « Only 2 left! », pas de rouge d'alerte, pas de « BEST VALUE », pas de prix qui clignote, pas de fenêtre qui s'ouvre seule, pas de pastille de nombre sur le bouton Shop.
- Articles possédés : « Owned » + « Equip ».

### 6.5 Ranks

Weekly / All-time et Global / Friends. Podium des 3 premiers, lignes 4 à 50 : rang, nom d'affichage, KO, classe jouée. **Ta ligne reste fixée en bas.** « Resets Mon 00:00 UTC » en petit, sans alerte. Données : `Leaderboards` (A12), top 50 toutes les 120 s.

### 6.6 Quests

En tête **Unlock a class** (Guardian, Rogue, Cleric, Barbarian, Tamer), puis les catégories. Chaque ligne : nom, barre, récompense visible. Récompense donnée automatiquement par le serveur ; la ligne affiche « Done! ».

### 6.7 Settings

Onglets Graphics, Sound, Controls, Accessibility (Colorblind mode, Reduce flashes, Text size 100/115/130 %, Keep my hat). Toute la ligne est tactile, effet immédiat. Anglais seul au lancement. A08 code `SettingsUI` d'après cette maquette.

### 6.8 Queue & Party

Ouvert par PLAY. Trois cartes de mode : **Solo**, **Friends**, **Public**. Groupe : 4 places (vignette, nom, classe, état). « Invite », « Leave », START (le chef). « Picking… » informe sans bloquer : chacun a toujours une classe. « Private village » avec le pass VIP.

### 6.9 Upgrades (nouveau, maquette après le concept UI de A08)

- Boutique d'**étoiles d'argent** gagnées en run (`70-donnees` §6) : armes, Runes et objets à ajouter au pool ; emplacements de Rune ; +1 Bannir / Passer / Relancer par run.
- **Jamais de Robux, jamais de monnaie achetable** : c'est de la progression gagnée en jouant.
- Une carte par amélioration : niveau actuel → suivant, prix en argent sur le bouton ; grisé avec le prix manquant si on n'a pas assez (« Need 120 more Silver »).

### 6.10 Inventory (nouveau, maquette après le concept UI de A08)

- Tout ce qu'on possède, par onglet : Hero gear, Critter style, Effects (KO, traînées, pas), Emotes et poses, Titles.
- Toucher un objet = aperçu ; EQUIP l'équipe dans son emplacement (`EquipCosmetic`). Les objets non possédés n'y sont pas : l'Inventory ne vend rien et ne renvoie pas vers la boutique.

### 6.11 Pass (nouveau, maquette après le concept UI de A08)

- Pass saisonnier **100 % cosmétique** : une piste gratuite et une piste payante (pass Roblox). Les paliers se gagnent **en jouant** (XP de run et quêtes).
- **Aucun palier vendu en Robux**, aucun objet aléatoire, aucune puissance.
- Fin de saison affichée comme une date neutre (« Season 1 · ends Jan 12 »), jamais en compte à rebours rouge.
- Récompenses gratuites : bouton CLAIM ; piste payante : cadenas tant que le pass n'est pas acheté, avec le prix du pass sur un seul bouton.

---

## 7. Mobile et accessibilité

- Tout se fait depuis le HUD : marcher dans le village est un plaisir, jamais une obligation.
- La barre du bas tient entre le joystick et le bouton Saut ; chaque bouton fait au moins 56 px de haut.
- Réduction des mouvements : pas d'icône qui tourne, la flèche de première visite est fixe, fondus au lieu de pops.
- Daltonisme : chaque bouton = icône + mot ; chaque bâtiment = forme + mot.

## 8. Performance (budget du village, carte de Clément)

| Poste | Budget | Note |
| --- | --- | --- |
| Instances (tout le hub) | ≤ 4 000 | vault : hubs mesurés de 913 à 4 531 ; c'est la 1re chose chargée sur les téléphones faibles |
| Triangles visibles | ≤ 300 k | décor en Parts : surveiller leur nombre plus que les triangles |
| Lumières locales | ≤ 10, dont 2 avec ombre | |
| Émetteurs de particules | ≤ 12, en veille au-delà de 300 studs | |
| Compagnons de l'enclos | ≤ 12, côté client, 10 Hz | en pause à plus de 120 studs |
| Tableaux de classement | 2 × 10 lignes, rafraîchis toutes les 120 s | la liste complète est dans le menu |
| Streaming | `StreamingEnabled`, min 64 | l'arrivée et le portail d'abord |

## 9. Ce qui reste à faire (vague 2, après validation)

- **A09-04** : `LobbyController` côté client (HUD du hub : PLAY, barre, zones de porte `Door_<Menu>`), sur la carte de Clément. Plus de blockout du village par A09.
- **A09-05** : Queue & Party, file et téléportation (avec MatchService).
- **A09-06** : tableaux 3D du bâtiment RANKS.
- **A09-07** : Critters, Shop, Upgrades, Inventory, Pass.
- Maquettes des 3 nouveaux menus (§6.9 à 6.11), après le concept UI en briques de A08.

## 10. Demandes de contrat (pour la vague 2)

| Domaine | Demande |
| --- | --- |
| lead (ARCHITECTURE) | Périmètre A09 : `client/Controllers/Lobby/*`, `server/Services/LobbyService.luau`, et les modèles d'UI du lobby dans COHUE (rien construit par script) |
| data (A12) | `MatchRequest` : un groupe et un mode `Solo` / `Party` / `Public` ; reformer le groupe au retour ; `getParty(player)` ; données du pass saisonnier (paliers, piste gratuite et payante, XP gagnée en jouant) ; texte de la quête de déblocage de chaque classe |
| classes (A04) | `applyClass(player, classId)` utilisable dans le lobby (palier 1) |
| companion (A05) | Mode lobby de `CompanionRenderer` : le compagnon équipé suit son joueur ; la collection se promène dans l'enclos (client seul) |
| ui (A08) | Style du bouton PLAY et des boutons de la barre (icône + mot, pastille de nombre) ; **8 icônes de barre** (Classes, Critters, Upgrades, Inventory, Quests, Ranks, Pass, Shop) ; icônes des classes et de Solo / Friends / Public ; `SettingsUI` d'après la maquette n° 7 ; variables `zone/*` : faites et reliées |
| art (A01) | Dans le kit : lettres en briques pour les noms de bâtiments (CLASSES, CRITTERS, UPGRADES, INVENTORY, QUESTS, RANKS, PASS, SHOP) et une façade par menu |
| VFX (A07) | Tourbillon du portail, pop d'équipement, éclat de l'enclume quand une amélioration est abordable |

## 11. Auto-contrôle

| # | Point | État |
| --- | --- | --- |
| 1 | Guide de style | Le village suit `80-direction-artistique.md` (carte de Clément) ; l'UI suit la bibliothèque A08, en refonte |
| 2 | Lisible sur téléphone | Barre et PLAY entre le joystick et le Saut ; 3 tailles de téléphone vérifiées pour les menus |
| 4 | Aucune sortie brute | Composants A08 ; pas de texte d'aide sous les boutons |
| 5 | Humour | Gob le chapelier, le Hibou Plongeur des quêtes, l'enclume qui brille, le podium |
| 6 | quality-score | Auto-évaluation 7,9 / 10 (mouvement des menus non spécifié) : brouillon |
| 7 | Vérifié en jeu | Non : rien n'est construit |

## 12. Décisions de Clément

**4 nov.** : plan, structure des 8 écrans et habillage validés.

| # | Question | Décision |
| --- | --- | --- |
| 1 | Nom du village | **Hubbub Village** |
| 2 | Solo mis en avant pour la 1re run | Oui (présélectionné dans Queue & Party) |
| 3 | Joueurs par serveur de lobby | **8** |
| 4 | File publique dans le même serveur d'abord | Oui |
| 5 | Essai des classes verrouillées | **Non : cadenas seul** |
| 6 | Enclos : chacun voit sa collection | Oui |

**5 nov.** : bouton Play + barre de menus, village en décor (« oui a tous »).

Questions ouvertes (5 nov.) :

1. **8e bouton Ranks** dans la barre (le classement KO est le pilier du jeu) : d'accord ?
2. **Même mot sur le bâtiment et sur le bouton** (« UPGRADES » plutôt que « FORGE ») : d'accord ?
3. **Pass** : aucun palier vendu en Robux, seulement la piste payante : d'accord ?
4. **Libellés** : « Classes » ou « Class » ; « Critters » ou « Companions » ?

## Sources vault

- 33 Level Design / **Lobby and Hub Design** : jobs du hub classés, budgets de temps, place compacte, pas de cercles au sol, budget d'instances.
- 05 UI and UX / **Onboarding and FTUE** et 10 / **First-Time User Experience and Onboarding** : contrôle en ~10 s, 1re action en 10-20 s, pas de mur de texte.
- 05 UI and UX / **Designing Roblox UI in Figma - Frames, Safe Areas and Tokens** : zones réservées, cibles tactiles.
- 21 / **fwjelaa UI Design System** : une seule action verte par écran, dire pourquoi un bouton est verrouillé.
- 41 Multiplayer Services / **Matchmaking Queues with MemoryStore** : le groupe est un seul ticket.
