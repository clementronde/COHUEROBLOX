# 60 — UI / UX (domaine ui)

Domaine : `client/Controllers/UI/*` (sauf `LoadoutUI.luau`, qui passe à A09), `server/Services/PingService.luau`, `shared/Config/UI.luau`.
Contrat : `docs/ARCHITECTURE.md` (sections 2, 6, 7). Vision : `01-decisions-v2.md` d'abord, puis `00-vision.md` sections 1, 5.2, 10, 11.3, 13.

Objectif : un écran lisible au milieu de 200 ennemis sur un téléphone de 6 pouces, pour des joueurs de 9 à 15 ans, conçu mobile d'abord. HUD réduit aux coins, cartes en bas, couleurs de rareté reconnaissables sans lire **et** sans voir les couleurs (toujours un 2e canal).

> **v2 (4 nov. 2026)** : la section 0 ci-dessous remplace les sections 1 à 15 partout où elles se contredisent (style, polices, couleurs, positions, boutons). Les règles techniques des sections 1 à 15 (ScreenInsets, `UIScale`, pools, fréquences, localisation, câblage des entrées) restent valables.

---

## 0. v2 — Design system « Toy-block gloss » et maquettes (A08)

**Fichier Figma** : [COHUE — UI Design System & Run Screens](https://www.figma.com/design/0Yq5m1skq5dzgOQXZ9bG6D). Pages : Cover, Foundations, Icons, Components, Run — Phone landscape (L01-L11), Run — Phone portrait (P01-P11), Run — PC (C01-C11). Statut : **à valider par Clément** (A08-03). Rien n'est intégré dans Roblox avant son accord.

### 0.0 Virage « studs » et UI en dur (5 nov. 2026)

Clément a demandé deux changements après la v1 vernie :

1. **DA en studs.** Tout bloc coloré porte une texture de tenons, dans l'esprit des packs d'UI Roblox « stud ». La texture vient de `kek_stud.png` (pack KekUIEssentials fourni par Clément). Le pack ne contient pas de fichier de licence : Clément confirme le droit d'usage.
2. **UI en dur.** Les `ScreenGui` seront montés comme instances dans le place COHUE, pas générés par le code au lancement. Les scripts de `client/Controllers/UI/*` se brancheront sur des instances nommées et ne feront que cloner ou mettre à jour.

Ordre retenu par Clément : d'abord Figma en studs, il valide, puis montage dans Studio.

Règles du style studs (elles remplacent la brillance et les reflets de 0.1) :

| Élément | Règle |
| --- | --- |
| Texture | Tuile transparente de 128 px (2 × 2 studs) tirée de `kek_stud.png` : clair → blanc translucide, sombre → noir translucide. Affichée à 12 px par stud. Fichier versionné : `docs/dossier/ui-assets/stud_tile_128.png`, refait par `make_stud_tile.py` (Python, PIL). |
| Styles Figma | `Studs/On color` (60 %) sur les faces colorées ; `Studs/On dark` (28 %) sur les plaques sombres désactivées. |
| Où | Boutons, barres de titre, badges de niveau, barres de vie, bouclier, capture, relève et boss, bandeaux de rareté des cartes, annonces, marqueurs et roue de ping. **Jamais** sur les corps de texte sombres, ni sur les touches clavier (`KeyHint`). La barre d'XP (10 px) reste sans studs. |
| Forme | Bloc à contour encre 3 px, lèvre 6 px, biseau clair de 3 px en haut (`Bevel/Stud top`). Plus de bande brillante ni de reflets carrés. Rayons : 8 (boutons L), 7 (M), 12 (fenêtres), 7 (pastilles, qui ne sont plus en pilule). |
| Boutons tactiles | Jump, Slide, Ping, Capture deviennent des **carrés arrondis** à studs, libellé dessous. Anneau doré « Ready » conservé. |
| Fenêtres | Nouveau composant `WindowHeader` (6 tons : Play, Go, Premium, Danger, Info, Neutral) : barre colorée à studs, titre blanc en Luckiest Guy contour encre, croix rouge carrée `CloseButton` de 44 px en option. Il se pose sur un corps sombre, chevauchement de 10 px. Utilisé par Victory (Premium, titre centré), À terre (Danger « DOWNED! », Neutral « GHOST MODE ») et Fin de run (Play « RUN OVER »). Aucune de ces trois fenêtres n'a de croix : elles ne se ferment pas. |

Côté Roblox (montage en dur, après validation) : la tuile est envoyée sur le compte de Clément (accord donné : « Je crée et j'upload »), puis posée comme `ImageLabel` `ScaleType = Tile`, `TileSize = 24 × 24`, `ImageTransparency = 0.4` au-dessus de la face. Les coins passent par `UICorner`, le contour par `UIStroke` de 3 px encre.

Captures v2 studs : planches L01-L11, P01-P11, C01-C11 et règles, envoyées à Clément le 5 nov. 2026.

### 0.0 bis Concept v3.1 « vraies briques » (5 nov. 2026, après le refus de la v2)

Clément a jugé la v2 studs « encore trop AI slop » : c'était la v1 repeinte, avec une texture collée partout. Le concept v3.1 repart de ses 9 références et du monde en tenons d'A01. Il ne couvre pour l'instant que le HUD et Victory en téléphone paysage, page Figma **Concept v3 — briques**.

| Élément | Règle v3.1 |
| --- | --- |
| Police | **Fredoka One** partout (titres, chiffres, libellés), blanc, contour Ink épais (≈ 13 % de la taille) et ombre portée dure de 2 px. 15 px au minimum. |
| Chiffres du HUD | Posés **directement sur le monde**, sans pastille : chrono, KO, record, Silver. |
| Briques | Contour Ink 3 px, rayon 6 (8 pour les grands blocs), lèvre basse en ton `.dd`, biseau haut en ton `.l`. Tenons seulement sur les boutons principaux, les barres de titre, la barre de vie et la mini-carte, en tenons entiers (pas de 12 px), opacité 0,22 à 0,45. |
| Icônes | **Montées en vraies briques** avec les outils d'A01, rendues dans Blender, contour Ink : `docs/dossier/ui-assets/icons/`. Elles débordent du cadre (trophée, coffre, flamme). |
| Fenêtres | Barre de titre dorée à tenons et reflets en biais, titre centré de 40 px. Corps brun foncé (`Bark.dd`) cerclé d'or. Choix présentés en **cartes de couleur** qui disent l'enjeu (« End the run, keep all loot », « Loot is safe. More KO! »). La pastille rouge de compte à rebours prend la place d'une croix. |
| Cases d'inventaire | Claires (Cream), contour Ink, étiquette de niveau dorée « Lv4 ». |
| Boutons tactiles | Tuiles carrées à tenons, grosse icône claire, libellé à cheval sur le bord bas. Capture en Bubblegum avec une cage crème. |
| Marges | 44 px de chaque côté en paysage (encoche des deux côtés selon le sens du téléphone). |
| Animations | « Clic de brique » : la brique s'enfonce de sa lèvre et remonte avec un rebond, les fenêtres tombent et s'écrasent de 4 % en se posant, les tampons claquent avec des tenons qui jaillissent. Recettes TweenService et aperçu jouable : `docs/dossier/ui-assets/concept/preview/` (page « Clic de brique »). Réglage « animations réduites » : fondu de 0,12 s, sans secousse, sans particules, sans pulsation. |

Fond des maquettes : `docs/dossier/ui-assets/concept/run_scene.py`, une arène en tenons avec une horde de gobelins d'A01, rendue dans Blender. Ce n'est pas un décor du jeu.

**v3.2 (même jour)** : corrections de la relecture à l'aveugle (3 relecteurs sur la v3.1 : médiane 6,7/10, plafonnée à 5,0 par 3 px de marge manquants à droite ; « encore du modèle ? » 1/2 pour les trois) et nouvel écran de passage de niveau demandé par Clément. Captures : `docs/dossier/ui-assets/concept/captures/`.

| Écran | v3.2 |
| --- | --- |
| HUD | Marges de 44 px des deux côtés, libellés au-dessus de la barre du bas de l'écran. Une seule plaque de vitals (niveau, vie, XP, Silver). Équipiers en portraits (en jeu : vignette Roblox du joueur dans un cadre à sa couleur), sous la plaque, loin du joystick. Barre d'armes en bas au centre, case verrouillée avec un cadenas. KO (34 px) plus gros que le chrono (28 px). Réglages en brique grise à tenons. Cage de capture avec un gobelin dedans. |
| Victory | L'enjeu est écrit : « Your loot is safe. Pick one: », « Leave now with your loot », « Overtime: more KO! ». Plus de pastille dans le coin (elle ressemblait à une croix) : une barre « AUTO CASH OUT IN 12s » se vide en bas, Cash out par défaut à 0 (proposition, à valider). Le joueur peut changer d'avis tant que la barre n'est pas vide. Portraits des équipiers sur la carte choisie. |
| **Niveau gagné** (nouveau) | Le jeu se fige et pâlit, des rayons tournent derrière. Fenêtre au centre « LEVEL 13! » : 3 offres en cartes de rareté (icône, nom, effet, étiquette NEW! ou Lv 2 → 4, rareté écrite), Reroll / Skip / Banish avec leurs compteurs. Inventaire à gauche (armes, Runes, objets, avec leur niveau), stats à droite : la stat que l'offre sélectionnée change s'allume en vert avec sa future valeur. Choisir une offre fait voler son icône dans la case d'inventaire, puis le jeu reprend. |

**Contract request (A04, serveur)** : le passage de niveau doit mettre le jeu en pause (décision de Clément du 5 nov. 2026). En solo, c'est une pause complète. En coop, la règle reste à choisir (question posée à Clément) : tout le monde figé pendant le choix d'un joueur, ou seulement le joueur qui choisit, figé et invulnérable. Cela remplace « cartes sans pause, 8 s » de la section 4.

### 0.1 Le style (v1 vernie, remplacé par 0.0 pour la brillance et les reflets)

Chaque élément pressable ou important ressemble à un **bloc de jouet verni** :

| Élément | Règle | Pourquoi |
| --- | --- | --- |
| Face | Couleur plate du rôle | Lisible, pas d'effet « plastique flou » |
| Brillance | Bande plus claire **nette** sur le haut (≈ 42 % de la face), deux tons, **aucun dégradé** | Le vault (Glossy Icon Style) : des aplats nets lisent comme du verni, un dégradé lisse lit comme du générique |
| Lèvre | Bande plus sombre de 5 à 7 px sous la face ; « Pressed » = la face s'enfonce de lèvre − 2 | « S'il a une lèvre, on peut appuyer » |
| Contour | Encre marine `#0E1424`, 3 px sur les blocs, 2 à 2,5 sur les petits | Sépare tout du décor coloré ; jamais du noir pur |
| Reflets | Deux petits carrés blancs en haut à gauche | Clin d'œil voxel, signature COHUE (fwjelaa utilise des reflets ronds) |
| Ombre | Ombre dure encre, y 3-4, flou 0 | Effet bloc posé ; ombre douce seulement sous les popups |
| Corps des panneaux | Bleu nuit `#1F2B49` (92-97 % opaque) | Texte blanc à plus de 12:1, même au-dessus d'une horde très saturée |

Inspiré du design system fwjelaa (encre, slabs à lèvre) sans le copier : base bleu nuit au lieu de violet, reflets carrés, couleurs par rôle de jeu et non par menu.

### 0.2 Jetons (variables Figma = futur `UITheme`)

Trois collections : **Primitives** (66 couleurs, cachées), **Color** (rôles, modes `Default` et `Colorblind`), **Layout** (espacements 2/4/8/12/16/24/32, rayons 4/8/12/16/22/pill, contours 1,5/2/3/4, lèvres 3/5/7, tailles tactiles 44/52/68/84).

| Rôle | Default | Colorblind (Okabe-Ito) | 2e canal |
| --- | --- | --- | --- |
| PV | rouge `#FF4757` | idem | cœur + « 72 / 100 » |
| Bouclier | argent `#DDEBFA` | idem | extension après les PV + bouclier + nombre |
| XP | aqua `#2EDDF5` (= gemme d'XP dans le monde) | idem | badge LV |
| Pièces | or `#FFC22E` | idem | pièce + nombre |
| KO | orange `#FF8A1F` | idem | tête-cube aux yeux en croix + nombre |
| Overtime | rouge `#FF4757` | vermillon `#D55E00` | chrono qui monte (+), pastille OVERTIME |
| Common | gris `#BCC5D6` | blanc cassé `#E6E6E6` | mot, 1 losange, cadre 3 px |
| Rare | bleu `#3B87FF` | bleu ciel `#56B4E9` | mot, 2 losanges, cadre 4 px |
| Epic | violet `#A75CFF` | vermillon `#D55E00` | mot, 3 losanges, cadre 5 px |
| Legendary | or `#FFC22E` | jaune `#F0E442` | mot, 4 losanges, cadre 6 px, halo or fixe + rayons |
| Allié / autel / coffre / boss / capturable | turquoise / bleu / or / rouge / rose | vert-bleu / bleu / jaune / vermillon / pourpre | chevron / losange / carré / gros « ! » / étoile |
| Boutons | Go vert, Neutral bleu nuit, Danger rouge, Premium or, Info bleu, Slide turquoise, Capture rose | Slide et Capture suivent Okabe-Ito | libellé toujours écrit |

Le mode daltonien **change de palette** (mode de la collection), jamais de filtre ; les formes et les mots ne changent pas.

### 0.3 Typographie

Trois polices, toutes livrées avec Roblox (`rbxasset://fonts/families/…`) **et** présentes dans Figma, pour un rendu identique :

| Style | Police | Taille (échelle 1) | Usage |
| --- | --- | --- | --- |
| Display/Hero, XL, L, M | Luckiest Guy | 56 / 40 / 30 / 22 | Victory, KO, chrono, niveau : la voix « jouet », chiffres très lisibles avec contour |
| Title/L, Title/M, Label/M, Label/S | Fredoka One | 22 / 16 / 15 / 14 | Titres, boutons, pastilles |
| Body/M, Body/S | Nunito ExtraBold / Bold | 14 / 14 | Descriptions, aides |

Plancher technique 12 px après échelle ; le plus petit style est à **14 px** sur téléphone (relecture : 13 px restait juste pour des 9 ans sur 6 pouces). Contour encre du texte ≤ 8 % de la taille (min 1 px) : au-delà, le contour mange la lettre voisine (vu en relecture). Taille réglable 100 / 115 / 130 % (`textScale`). Builder Sans reste la police de secours des menus longs (A09).

**Échelle** : téléphone 1 ; PC et tablette `clamp(petit côté / 420, 1, 1,6)` (le plafond passe de 1,4 à 1,6 : à 1,4 le HUD était trop petit sur un écran 1080p).

**Manette et clavier** : composant `FocusRing` (anneau or 4 px + halo encre, 6 px autour du bouton ; c'est le `SelectionImageObject`), focus par défaut sur la carte 1, Cash out et Play again. Glyphes `PadGlyph` (A, B, X, Y, croix haut) pour les maquettes ; en jeu, glyphes de la plateforme via `UserInputService:GetImageForKeyCode`. Touches : 1/2/3 cartes, R / X / B Relancer / Passer / Bannir (pas S : le joueur marche encore en ZQSD/WASD pendant l'offre), C / K Victory, Entrée / L écran de fin (Échap est réservé au menu Roblox), Espace / Maj / F / G en run (les touches affichées sont lues dans `InputController.getHint` : la Capture est sur F chez A06).

### 0.4 Composants (page Components)

Base : `Button` (5 rôles × Default/Pressed/Disabled × L 58 / M 46), `ActionButton` (Jump 84, Action 68, Small 52 × Default/Pressed/Ready/Disabled), `Bar` (HP, Shield, XP, Capture, Revive, Boss), `Slot` (Weapon 44, Rune 34, plein ou vide en pointillés), `LevelBadge`, `Pill` (7 tons), `KeyHint`, `RarityPips`, `CountBadge`, `TimerRing`, `Panel` (Default, Sunken, Chip), `SettingsButton`.
Cartes : `Card` (4 raretés × Default/Banish, 150×188) et `CardRow` (portrait, 366×98).
HUD : `Vitals`, `TimerChip` (Normal/Warning/Overtime), `KOCounter` (Normal/NewBest), `Minimap`, `BuildBar`, `TeamRow` (Alive/Downed/Ghost), `BossArrow`, `EdgeArrow`.
Overlays : `CardTray`, `CapturePrompt` (Capturing/Interrupted/Captured), `AnnounceBanner`, `ReviveMarker`, `DownedPanel` (Downed/Ghost), `VictoryBanner` (Landscape/Portrait), `EndScreen` (Landscape/Portrait), `PingMarker` (6), `PingWheel`, `PingFeed`.
Icônes : 24 icônes 48 px (stats, actions, 4 armes, 4 Runes, coffre, autel…) dessinées selon la recette « Glossy Icon Style » (deux tons nets, encre marine, lumière en haut à gauche). A08-07 complétera les 16 armes, 14 Runes et 40 objets.

### 0.5 Les 11 écrans de run

| # | Écran | Changements par rapport aux sections 3 à 10 |
| --- | --- | --- |
| 01 | HUD | KO + record en haut à droite à côté de la mini-carte ; Réglages à gauche de la mini-carte ; armes et **Runes** ; plus de bouton Ultime |
| 02 | Chrono → Overtime | « Vague Finale » remplacée par l'**Overtime** : chronomètre rouge qui monte, pastilles OVERTIME + DANGER n (un cran / 30 s), annonce unique |
| 03 | Compteur de KO | Nouveau : gros chiffre, record perso, NEW BEST! en or quand il est battu |
| 04 | Cartes | 150×188 (lignes 366×98 en portrait) sur une plaque sombre ; Relancer / Passer / Bannir en 100×48 ; pendant le choix on masque build, équipe et boutons ; cartes inertes 0,4 s |
| 05 | Mini-carte | + marque **capturable** (étoile rose) ; flèche du boss en pastille avec distance |
| 06 | Boutons mobiles | **Saut 84, Glisser 68, Ping 52, Capture 68** (contextuel, anneau or) ; Ultime retiré |
| 07 | Barre de capture | Nouveau : panneau près de la cage, barre 2 s avec les secondes écrites à côté, « OUCH! CAPTURE RESET » si touché, nom de la créature si réussi |
| 08 | Victory | Nouveau : ruban or, **Keep going** = le seul bouton Go vert (Overtime infini, record de KO), **Cash out** en or (fin de run, gains sauvés) ; focus manette sur Keep going |
| 09 | Écran de fin | + rang hebdo et record ; dégâts par arme ; gains (Silver, capture, quêtes) |
| 10 | À terre / relève | 25 s ; vignette orange fixe ; marqueur HELP au-dessus d'un coéquipier |
| 11 | Pings | Inchangés sur le fond ; roue à 6 cibles de 48 px ; sur tactile, Saut / Glisser / Ping masqués tant que la roue est ouverte |

Positions de référence (pixels logiques, échelle 1) :

| Élément | Téléphone paysage 844×390 | Téléphone portrait 390×844 | PC 1920×1080 (×1,4) |
| --- | --- | --- | --- |
| Barre Roblox | haut gauche, réservée | rangée sous l'encoche, à gauche | haut gauche |
| Vitaux | haut gauche, sous la barre Roblox | sous le chrono, à gauche | haut gauche |
| Build | sous les vitaux | sous les vitaux | bas gauche |
| Chrono | haut centre (zone libre de la barre) | sous la barre Roblox, centre | haut centre |
| KO | haut droite, à gauche de la mini-carte | rangée de la barre Roblox, à droite | haut droite |
| Mini-carte | haut droite, 120 | à droite sous le KO, 120 | haut droite, 168 |
| Boutons | bas droite | bas droite, au-dessus de la barre d'accueil (34) | légende des touches bas droite |
| Joystick Roblox | bas gauche, libre | bas gauche, libre | — |

### 0.6 États, mouvement et son

Planche « États, mouvement et son » de la page Foundations. Cinq états par bouton : Default, Hover (PC : `UIScale` 1,04, 0,10 s), Pressed (face qui s'enfonce, 0,05 s), Disabled (neutre, sans reflets, texte atténué), Focus (`FocusRing`). Popups : ouverture 0,9 → 1 en 0,18 s Back Out, fermeture 1 → 0,92 en 0,12 s Quad In ; cartes distribuées une par une, la carte choisie vole vers sa case du build. Chaque interaction a un emplacement de son (`ui_press`, `ui_open`, `card_deal`, `card_pick`, `timer_warn`, `overtime_horn`, `record_fanfare`, `capture_tick/ok/fail`) que A10 remplit avec la bibliothèque sous licence du Creator Store. Vibration courte à la manette (capture, record), désactivable. « Réduire les flashs » : fondus seuls, pas de pop, pas de secousse, halos fixes.

### 0.7 Note qualité des maquettes (skill quality-score, 3 relecteurs à l'aveugle)

Premier jet 5,0 (plafonné : boutons du plateau jugés < 44 px, chevauchements, pas de manette), 2e tour 7,1 (médiane), corrections : boutons 100×48, roue de pings qui masque les boutons, bannières dans un couloir central, texte 14 px, contours ≤ 8 %, PC à 1,6, focus et glyphes manette, Keep going en vert, planche d'états et de sons. Note finale : **7,9 / 10** (médiane du 3e tour), critères bloquants OK ; il manquait la lisibilité des petits libellés sur la horde et la densité du HUD. Clément a validé les maquettes le 4 nov. 2026.

### 0.8 Intégration Roblox (A08-04 à A08-06, 4 nov. 2026)

| Module | Ce qu'il fait | Données |
| --- | --- | --- |
| `shared/Config/UI.luau` | Jetons Figma (modes Default / Colorblind), polices, tailles, textes anglais, réglages des écrans | — |
| `UITheme` | Builders glossy (`glossy` : bloc ou bouton avec Pressed, survol 1,04, Disabled, anneau de focus or), `chip`, `popup`, `glossBar`, `pill`, `keycap`, icônes dessinées en code (KO, cœur, horloge), drapeaux partagés (`cardsOpen`, `captureAvailable`...), anglais forcé, forçage d'appareil en Studio (`UIDebugDevice`) | — |
| `HUD` | Vitaux, build, équipe, fil de pings, chrono → Overtime, compteur de KO + record, flèche et barre du boss, annonces, écran à terre / fantôme | `RunState` v2 (A04), `PlayerProgress.kills`, attribut `RunKills`, `PlayerVitals`, `Build`, `Coins`, `Profile.bestKills` |
| `VictoryBanner` (nouveau, démarré par HUD) | Bannière Victory. Keep going ferme ; Cash out ferme et guide vers le portail doré (flèche, distance, barre de maintien d'équipe) | `RunState.victory`, `cashOutPosition`, `cashOutProgress` |
| `CaptureUI` (nouveau, démarré par HUD) | Panneau de capture 2 s, reset si touché, nom de la créature | remote optionnel `CaptureState` ou `CaptureUI.set(payload)` |
| `CardUI` | Cartes glossy, lignes en portrait, plaque, Relancer / Passer / Bannir 100×48, anneau 8 s, touches 1/2/3 et R/X/B, 0,4 s inertes | `CardOffer` |
| `MobileButtons` | Saut, Glisser, Ping, Capture (anneau or) ; légende clavier sur PC | drapeaux UI, `InputController.bindButton` |
| `EndScreen` | Résultat, KO, record, rang hebdo, dégâts par arme, gains, Play again, Lobby si le remote existe | `RunSummary` |
| `Minimap`, `SettingsUI` | Positions des maquettes (rangée de la barre Roblox, engrenage à gauche de la mini-carte en paysage) | — |

**Écarts assumés par rapport aux maquettes**

- Victory : A04 a codé le Cash out comme un portail doré (toute l'équipe 2 s dedans). Les deux boutons restent, mais « Cash out » guide vers le portail au lieu d'envoyer un remote ; la ligne d'équipe de la maquette n'est pas affichée (aucune donnée serveur).
- Raccourcis PC : Passer = X (S sert à marcher pendant l'offre), Lobby = L (Échap est réservé à Roblox).
- Carte venant du compagnon : pastille « PET » (« Companion » ne tient pas à côté de LEGENDARY dans 150 px).
- Icônes : formes dessinées en code et initiales en attendant A08-07, qui demande de téléverser des images (permission de Clément).

**Test** : place `COHUE-A08.rbxlx` construite avec rojo depuis la branche (`tools/test.project.json`). Run réelle (cartes, fin de run, dégâts par arme) + script de test serveur propre à la place (Overtime, record battu, Victory, capture, à terre). Profil téléphone vérifié avec l'attribut joueur `UIDebugDevice = "phone"` (Studio seulement).

**Contract requests**

| Domaine | Demande |
| --- | --- |
| data | `Profile.bestKills` (record perso de KO en une run) ; `RunSummary.weeklyRank` ; remote `ReturnToLobby` (bouton Lobby) |
| companion (A05) | Remote `CaptureState { state = "Idle" \| "Available" \| "Capturing" \| "Interrupted" \| "Captured", progress, holdSeconds, name }` dans `shared/NetDefs/Companion.luau`, et `RunSummary.captured` |
| avatar (A06) | Fait : l'action `Capture` (touche F, X à la manette) est dans main depuis la fusion A06 |
| combat (A04) | Renommer `Build.grimoires` / `grimoireSlots` en `runes` / `runeSlots` quand le contenu v2 arrive (le HUD lit les deux) |
| lead | Ajouter `VictoryBanner` et `CaptureUI` à la liste des modules UI (modules simples démarrés par HUD, pas de nom de boot) |

### 0.9 Questions ouvertes pour Clément

1. **Victory en coop** : chacun choisit Cash out ou Keep going pour lui-même (proposition des maquettes), ou un vote d'équipe ?
2. **Fantôme** : que devient un joueur fantôme (retour au monde suivant ? au prochain autel ? spectateur jusqu'à la fin) ? Les maquettes écrivent « BACK AT THE NEXT WORLD » en attendant.
3. **Raccourcis PC** : R / S / B pour Relancer / Passer / Bannir et C / K pour Cash out / Keep going, à valider.
4. **Monnaie de fin** : le mot « Silver » est repris du code existant ; à remplacer si A09/A12 choisissent un autre nom.

---

## 1. Principes

| Règle | Valeur | Source |
| --- | --- | --- |
| Texte affiché minimum | 12 px (après échelle) | Responsive UI, AI Pitfalls - UI and Input |
| Cible tactile minimum | 44 px (boutons de combat 64–84 px) | Responsive UI, Mobile Button Layout Editor |
| Écart minimum entre cibles | 8 px | Responsive UI |
| Chevauchements | 0, vérifiés aux 5 vues (844×390, 667×375, 1024×768, 1920×1080, téléphone à encoche) | HUD Design |
| Zones sûres | chaque `ScreenGui` règle `ScreenInsets` explicitement ; HUD interactif en `CoreUISafeInsets`, fonds plein écran en `None` | Safe Areas and Insets |
| `SafeAreaCompatibility` | `None` sur toutes nos guis | Safe Areas and Insets |
| `ResetOnSpawn` | `false` partout | ScreenGui Fundamentals (SYMPTOMS) |
| `DisplayOrder` | explicite et unique par gui (tableau §2) | SYMPTOMS : popup sous le HUD |
| Polices | `FontFace` uniquement : Builder Sans (corps), Fredoka One (titres/chiffres). Jamais Gotham (retiré, rend Montserrat) | Text Fonts and Rich Text |
| Taille du texte | `TextSize` fixe + `AutomaticSize` ; jamais `TextScaled` (ignore `PreferredTextSize`) | Accessibility |
| Contour du texte | `UIStroke` ≤ 7 % de la taille (sinon « 10 » devient « 1 » + tache) | SYMPTOMS / UIStroke on Text |
| Animation « pop » | on anime un `UIScale`, jamais `Size` ni `UIStroke.Thickness` | SYMPTOMS / UI Motion |
| Boutons | `Activated` pour les clics ; `InputBegan/InputEnded` seulement pour les boutons maintenus (Saut = plané) | Input - UIS and CAS |

### 1.1 Profil d'appareil et échelle

Classement par capacité, pas par devinette (Responsive UI, section 1) :

- **téléphone** = `TouchEnabled` et petit côté de la vue < 520 px ;
- **tablette** = `TouchEnabled` et petit côté ≥ 520 px ;
- **PC / console** = le reste (`PreferredInput` choisit les indications de touches).

Les tailles de ce document sont en **pixels logiques à l'échelle 1** (référence : téléphone 844×390). Chaque zone d'écran a son propre `UIScale` (jamais imbriqué : double réduction, AI Pitfalls) : échelle = clamp(petit côté / 420, 1, 1,4). Téléphone = 1 (plancher : pas de texte à 6 px), tablette 768 → 1,4 plafonné (1024 px de large = 731 px logiques, assez pour les zones du haut : 220 + 300 + 140), PC 1080 → 1,4. Recalculé quand `ViewportSize` change.

### 1.2 Thème : module de code plutôt que `StyleSheet`

Le vault (UI Design Systems §4) décrit le style moteur (`StyleSheet` / `StyleRule` / `StyleLink`, jetons `$Nom`, `StyleQuery`) mais note que l'éditeur est en bêta (oct. 2026) et que la syntaxe des sélecteurs est « la partie la plus sensible aux versions ». Toute notre UI est **construite par code** : un module de thème (`UITheme`) est la source unique des jetons (couleurs par rôle, typo, espacements, rayons, contours, mouvement). Aucun écran ne code une couleur en dur. Migration possible vers `StyleSheet` plus tard : les jetons ont déjà des noms de rôle.

---

## 2. Écrans et `ScreenGui`

| Gui | Module | DisplayOrder | ScreenInsets | Visible quand |
| --- | --- | --- | --- | --- |
| `COHUE_HUD` | HUD | 10 | CoreUISafeInsets | phase Running / Boss / BossDefeated / FinalWave |
| `COHUE_Minimap` | Minimap | 11 | CoreUISafeInsets | idem (gui séparée : elle bouge à 10 Hz) |
| `COHUE_PingWorld` | PingUI | 12 | None (non interactif, espace de la vue) | toujours en run (flèches de bord) |
| `COHUE_SettingsGear` | SettingsUI | 13 | CoreUISafeInsets | en run (sous la mini-carte) |
| `COHUE_Mobile` | MobileButtons | 15 | CoreUISafeInsets | en run |
| `COHUE_Vignette` | HUD | 24 | None (décor) | à terre |
| `COHUE_Downed` | HUD | 25 | CoreUISafeInsets | à terre / fantôme |
| `COHUE_Cards` | CardUI | 20 | CoreUISafeInsets | offre ouverte |
| `COHUE_Shrine` | ShrineUI | 21 | CoreUISafeInsets | offre d'autel ouverte |
| `COHUE_Announce` | HUD | 30 | CoreUISafeInsets | annonce en cours |
| `COHUE_PingWheel` | PingUI | 35 | CoreUISafeInsets | roue ouverte |
| `COHUE_Loadout` | LoadoutUI | 40 | DeviceSafeInsets (+ fond `None`) | phase Loadout |
| `COHUE_End` | EndScreen | 50 | DeviceSafeInsets | `RunSummary` reçu |
| `COHUE_Settings` | SettingsUI | 60 | CoreUISafeInsets | bouton engrenage |

Sur téléphone, un panneau plein écran (Loadout, Fin, Réglages) **masque le HUD** au lieu de le recouvrir (Responsive UI §6 : « hide, do not shrink »).

---

## 3. HUD en run

### 3.1 Positions par appareil (pixels logiques, avant `UIScale`)

| Élément | Téléphone | Tablette | PC |
| --- | --- | --- | --- |
| Vitaux (PV, bouclier, niveau, XP, pièces) | haut gauche, 210×60 | haut gauche | haut gauche |
| Armes + Grimoires | haut gauche sous les vitaux (icônes 28 / 22 px) — le bas gauche est le joystick | bas gauche (36 / 28 px) | bas gauche (36 / 28 px) |
| Équipe (≤ 3 coéquipiers) | gauche, sous le build, lignes 150×22 | sous les vitaux | sous les vitaux |
| Chrono + monde/stage | haut centre, 120×36 | haut centre | haut centre |
| Flèche du boss | sous le chrono, 36 px + distance | idem | idem |
| Barre de boss | sous le chrono, 280×14 + nom | 280 | 280 |
| Annonces (sous-titres) | haut centre, y = 96, largeur ≤ 520 | idem | idem |
| Mini-carte | haut droite, 112 px | 140 px | 160 px |
| Engrenage Réglages | sous la mini-carte, 44×44 | idem | idem |
| Boutons tactiles | bas droite (§8) | bas droite | — |
| Jauge d'Ultime | sur le bouton Ultime | sur le bouton | bas droite, 140×36, indication « E » / « Y » |
| Cartes | bas centre (§4) | bas centre | bas centre |
| Fil des pings | gauche, sous l'équipe, 3 lignes max | idem | idem |

Toutes les zones du haut commencent sous la barre Roblox grâce à `CoreUISafeInsets` (jamais de hauteur de barre codée en dur : Safe Areas §5).

### 3.2 Vitaux (haut gauche)

- **Barre de PV** 200×16, rouge corail `#F0564A`, texte « 85 / 100 » dessus (2e canal : le nombre). Fond sombre `#1C2230` à 25 % de transparence × `PreferredTransparency`.
- **Bouclier** : barre cyan `#5AD2FF` superposée sur le haut de la barre de PV (6 px), largeur = bouclier / PV max.
- **Niveau** : pastille ronde 32 px « 12 » (Fredoka One 18), libellé « Nv » / « Lv ».
- **XP** : barre 200×6 violet clair `#B68CFF` sous la barre de PV.
- **Pièces** : « ● 1 240 » jaune `#FFD447`, 14 px.
- Données : `PlayerVitals` (forme perso), `PlayerProgress`, `Coins`. Écriture seulement si la valeur change.

### 3.3 Chrono (haut centre)

- « 9:42 » Fredoka One 28, blanc. Sous 1:00 : **rouge `#FF4A3D` et 40 px** ; pas de clignotement (réduction des flashs) — un seul « pop » à 1:00 si le mouvement n'est pas réduit.
- Ligne 12 px dessous : « Bois Grognon · Tier 1 · Stage 2 » (noms du monde via Config.Worlds si présent, sinon id).
- Vague Finale : le chrono devient « VAGUE FINALE 1:23 » (secondes survécues, `finalWaveSeconds`), orange.
- Interpolation locale entre deux `RunState` (envoyé chaque seconde) ; texte réécrit seulement quand la seconde affichée change, boucle à 4 Hz (Race HUD : pas de texte par image).

### 3.4 Flèche du boss et barre de boss

- **Flèche** : dès `RunState.bossRevealed` et `bossPosition`. Triangle rouge 36 px sous le chrono, tourné vers le boss par rapport à la caméra (cap horizontal), + « 120 m ». Mise à jour à chaque image **seulement** tant que la flèche est visible (connexion créée/coupée).
- **Barre de boss** : quand `BossState` arrive (et pendant 3 s après la dernière trame). Nom localisé (`name`), barre 280×14 rouge sombre `#C8323C` + texte « 64 % », pastilles de phase (1 par phase). Masquée à la victoire (`BossDefeated`).

### 3.5 Équipe, mise à terre et relève

- **Liste d'équipe** (forme `{ team = … }` de `PlayerVitals`) : nom d'affichage (`AutoLocalize = false`), mini barre 90×6, et un état écrit : « À TERRE » orange avec icône « + », « FANTÔME » gris. Jamais seulement une couleur.
- **Moi à terre** : vignette de bord rouge (gui `None`, 60 % transparente, fixe si flashs réduits, respiration lente sinon), panneau central « À TERRE — 18 s » / « DOWNED — 18 s », barre de relève (`reviveProgress`) verte-bleue, et « Un coéquipier doit rester 3 s près de toi ».
- **Fantôme** : « FANTÔME — tu peux encore charger les autels (25 %) ». Pas de vignette.
- Coéquipier à terre : sa marque sur la mini-carte devient une croix « + » et le fil de pings affiche « Alex est à terre ! ».

### 3.6 Build (armes et Grimoires)

- Ligne d'armes : `weaponSlots` cases (vides = contour pointillé, 40 % opaques). Icône = carré arrondi coloré + 2 lettres (pas d'id d'asset), badge de niveau en bas à droite.
- Ligne de Grimoires : `grimoireSlots` cases plus petites.
- Données : `Build`. Noms via Config.Weapons / Config.Grimoires (si absents : id).

### 3.7 Compagnon

Nom du stade (`CompanionState.name`) + « Nv 5 » au-dessus du build ; « sonné » en gris si `stunned`. Jauge d'Ultime : §8.

### 3.8 Annonces avec sous-titres

`Announce { kind, text, duration }` → bannière haut centre, Fredoka One 22, fond sombre arrondi. File d'attente, **une à la fois** (HUD Design §3). Les annonces sont les sous-titres des annonces sonores (vagues, boss, Vague Finale) : elles restent `duration` s (min 2 s, max 6 s).

| kind (run) | Accent | Icône |
| --- | --- | --- |
| `Boss`, `BossRevealed`, `FinalWave` | rouge | « ! » |
| `Stage`, `Portal` | bleu | « » » |
| autre | blanc | aucune |

Entrée : pop d'échelle 0,9 → 1 en 0,15 s ; mouvement réduit : fondu seul.

---

## 4. Cartes de niveau (sans pause, 8 s)

`CardOffer { offerId, cards, expiresIn, banish, skip, reroll }` ; `{ offerId, closed = true }` ferme.

### 4.1 Disposition

- 3 cartes en bas centre. Téléphone : 132×112, écart 8, marge basse 8 (entre le joystick et les boutons d'action) ; tablette / PC : même taille × échelle.
- Chaque carte : bordure de rareté (contour 2 / 3 / 4 / 4 px selon la rareté), **losanges de rareté** (1 à 4) en haut à gauche, icône ronde 36 px (2 lettres), titre 1 ligne (14 px gras), description 1 ligne (12 px), « NOUVEAU » / « NEW » ou « Nv 3 », étiquette « Compagnon » si la carte vient du compagnon, indication de touche « 1 / 2 / 3 » sur clavier.
- Au-dessus, rangée de 3 boutons 44 px : **Relancer (n)**, **Passer (n)**, **Bannir (n)** (grisés à 0), puis **l'anneau de 8 s** (40 px).

### 4.2 Anneau de 8 s

Disque qui se vide dans le sens horaire depuis midi (2 demi-disques découpés + `UIGradient` à marche nette, rotation mise à jour à chaque image pendant l'offre seulement), chiffre des secondes restantes au centre (réécrit 1 fois par seconde). Sous 3 s : anneau orange. À 0 le serveur choisit (la plus rare) et envoie `closed`.

### 4.3 Actions

| Action | Geste | Remote |
| --- | --- | --- |
| Choisir | toucher la carte / touche 1–3 (actions `Card1`–`Card3`) / clic | `CardChoice(offerId, "pick", i)` |
| Relancer | bouton | `CardChoice(offerId, "reroll")` |
| Passer | bouton | `CardChoice(offerId, "skip")` |
| Bannir | bouton → mode bannir (cartes barrées d'un « × », bandeau « Touchez une carte à bannir ») → toucher la carte | `CardChoice(offerId, "ban", i)` |

Après un envoi, les cartes sont verrouillées jusqu'à la réponse du serveur (nouvelle offre ou `closed`) : pas de double envoi. Une nouvelle offre remplace l'ancienne.

### 4.4 Couleurs de rareté

| Rareté | Défaut | Daltonien (Okabe-Ito, échelle de luminosité) | 2e canal |
| --- | --- | --- | --- |
| Common / Commun | gris `#AAB0BA` | blanc cassé `#E6E6E6` | 1 losange, contour 2 px |
| Rare / Rare | bleu `#3C96FF` | bleu ciel `#56B4E9` | 2 losanges, contour 3 px |
| Epic / Épique | violet `#B45AFF` | vermillon `#D55E00` | 3 losanges, contour 4 px |
| Legendary / Légendaire | or `#FFBE28` | jaune `#F0E442` | 4 losanges, contour 4 px + fond doré léger |

Le mode daltonien **change de palette**, pas de filtre (`ColorCorrectionEffect` ne peut pas déplacer les teintes : Colour-Blind Safe Design §4.1). Les formes ne changent jamais d'un mode à l'autre.

---

## 5. Autels

- `ShrineOffer { offerId, choices = {{ stat, value, rarity }} }` → panneau au-dessus des cartes (ou à leur place s'il n'y a pas d'offre de carte) : 3 boutons 120×64, « +12 % Dégâts » / « +12% Damage », bordure + losanges de rareté. `ShrineChoice(offerId, i)`. Pas de minuterie côté client : le serveur ferme.
- Charge : depuis `ShrineState`, pastille « Autel 45 % · 2 joueurs » au-dessus du centre bas quand un autel `Charging` est à moins de 14 studs.

---

## 6. Mini-carte

- Radar rond, **nord en haut** (monde −Z vers le haut, Minimap note §1), centré sur le joueur, rayon couvert 120 studs. Pas d'image de carte (aucun id d'asset) : fond sombre rond + anneau.
- Mise à jour à 10 Hz (pas par image), marques en pool.
- Les marques hors du rayon sont collées au bord (sauf autels).

| Marque | Couleur défaut | Daltonien | Forme (2e canal) | Source |
| --- | --- | --- | --- | --- |
| Moi | blanc | blanc | flèche orientée | personnage local |
| Coéquipier | vert `#4CD964` | vert-bleu `#009E73` | chevron orienté ; croix « + » si à terre | personnages + `PlayerVitals.team` |
| Autel | bleu `#3C8CFF` | bleu `#0072B2` | losange (plein si prêt, creux si utilisé) | `ShrineState` |
| Coffre | jaune `#FFD447` | jaune `#F0E442` | carré | `LootRenderer.getChests()` (demande de contrat) |
| Boss | rouge `#FF3B30` | vermillon `#D55E00` | grand rond « ! » | `RunState.bossPosition` / `BossState.position` |
| Ping | couleur du ping | idem | anneau 1 s puis point | `PingBroadcast` |

Légende : petit bouton « ? » dans Réglages → ce tableau en texte.

Appui long 0,5 s sur la mini-carte (tactile) → roue de pings à l'endroit touché (§7).

---

## 7. Pings (6)

| id | FR | EN | Couleur | Glyphe | Durée |
| --- | --- | --- | --- | --- | --- |
| `Boss` | Boss ici ! | Boss here! | rouge | `!` | 8 s |
| `Shrine` | Autel | Shrine | bleu | `*` | 6 s |
| `Help` | À l'aide ! | Help! | orange | `+` | 6 s |
| `Chest` | Coffre | Chest | jaune | `#` | 6 s |
| `Regroup` | On se regroupe | Regroup | vert | `o` | 6 s |
| `Thanks` | Merci ! | Thanks! | rose | `<3` | 3 s (au-dessus du joueur) |

### 7.1 Déclenchement

| Appareil | Ping rapide (contextuel) | Roue des 6 |
| --- | --- | --- |
| PC | clic molette ou G (action `Ping`) au point visé par la souris | maintenir l'action `Ping` 0,3 s, puis cliquer une option |
| Téléphone / tablette | bouton Ping (48 px) : point au centre de l'écran | appui long sur la mini-carte (point touché) ou appui long sur le bouton Ping |
| Manette | croix haut (action `Ping`) au centre de l'écran | maintenir 0,3 s ; sélection manette sur la roue (`SelectedObject`), B ferme |

Ping contextuel : près de la position du boss (< 40 studs) → `Boss` ; autel < 15 → `Shrine` ; coffre < 10 → `Chest` ; sinon `Regroup`.

### 7.2 Affichage

Marqueur monde (`BillboardGui` toujours devant, 8 en pool) : glyphe dans un rond coloré + texte + nom du joueur ; flèche de bord d'écran quand hors champ ; point sur la mini-carte ; ligne dans le fil (« Alex : Autel »). Aucun son (pas d'id d'asset) — TODO quand les sons existent.

### 7.3 Serveur (PingService)

- `Net.onServerEvent("Ping", 3, …)` (seau de 3 par seconde) + plafond 6 pings / 10 s par joueur.
- Vérifie : `kind` est une chaîne parmi les 6 ; `position` est un `Vector3` fini (pas NaN / inf, |x|,|y|,|z| < 100 000) et à ≤ 300 studs de la racine du personnage de l'émetteur (les fantômes peuvent pinger s'ils ont un personnage).
- Diffuse `PingBroadcast { userId, kind, position }` aux joueurs de la run (`RunManager.getRunPlayers()` si l'émetteur en fait partie, sinon tous les joueurs du serveur — mode test).

---

## 8. Boutons tactiles (bas droite)

| Bouton | Taille | Position (depuis le coin bas droit, échelle 1) | Action |
| --- | --- | --- | --- |
| Saut | 84 | (−20, −24) | `Jump` (maintenu = plané) |
| Glisser | 64 | à gauche du Saut, écart 12 | `Slide` |
| Ultime | 64 | au-dessus du Saut, écart 12 | `Ultimate` ; jauge circulaire (`ultimateCharge` 0..1), brille quand pleine (statique si flashs réduits) |
| Ping | 48 | au-dessus du Glisser | `Ping` (tap = rapide, appui long = roue) |

Passe finale : on lit les rectangles réels et on écarte les boutons qui se chevauchent (Responsive UI §6). Masqués hors tactile, sauf la jauge d'Ultime qui reste en affichage (non cliquable) avec l'indication de touche.

---

## 9. Écran de sélection (LoadoutUI)

Visible en phase `Loadout` (et au premier lancement avant le premier `RunState`).

- **Gauche (40 %)** : aperçu du personnage du joueur dans un `ViewportFrame` qui tourne lentement sur un socle (arrêté si mouvement réduit). Le trait de classe est ajouté par le domaine avatar (pas de faux trait ici).
- **Droite** : onglets **Classe** / **Compagnon**.
  - Grille de 10 classes (cartes 120×80 ; 2 colonnes téléphone, 3 tablette, 5 PC) : nom, arme de départ, maîtrise « M 4 » si connue. Verrouillée : cadenas dessiné + grisé + **indice de déblocage** (« Quête : encaisser 50 000 dégâts », texte de la quête si Config.Quests le fournit, sinon l'id de la quête).
  - Grille de 6 compagnons : nom du stade 1, affinité, Lien « L 3 ». Même règle de verrou.
- **Bas** : bouton **JOUER / PLAY** 220×56 → `SelectLoadout(classId, companionId)`. Après l'envoi : « En attente des autres joueurs… ».
- Données : `Profile` (unlocks, mastery, bond, loadout). Avant le profil : classes gratuites Cornu, Plumeline, Mecano ; compagnons marqués `free` dans Config.Companions, sinon Braise, Ronce, Maree.
- Les cosmétiques ne sont que du style (11.3) : aucune stat affichée sur un cosmétique.

---

## 10. Écran de fin (EndScreen)

`RunSummary` → panneau centré (90 % largeur, ≤ 720) défilant :

1. Titre « VICTOIRE ! » / « VICTORY! » ou « FIN DE LA RUN » / « RUN OVER », monde · tier · stage atteint.
2. Ligne de chiffres : ennemis vaincus, niveau, pièces, autels, coffres, relèves, Vague Finale (s).
3. **Dégâts par arme** : barres horizontales triées, nom de l'arme + valeur abrégée (12,4 k), barre = part du maximum.
4. **Quêtes avancées** : barre de progression par quête (`progress / goal`), « TERMINÉE » + coche dessinée si `completed`.
5. Étoiles d'argent gagnées (`silverEarned`).
6. Bouton **REJOUER / PLAY AGAIN** 240×64 mis en avant (couleur primaire) → `Replay()`. Désactivé 1 s après envoi.

Masqué quand la phase repasse à `Loadout` ou `Running`.

---

## 11. Réglages (SettingsUI)

Bouton engrenage 44 px (sous la mini-carte en run, en haut à droite sur l'écran de sélection). Panneau 340 px :

| Réglage | FR / EN | Effet | Envoi |
| --- | --- | --- | --- |
| Mode daltonien | Mode daltonien / Colorblind mode | palette alternative (raretés, mini-carte, pings) | `UpdateSettings{colorblind}` |
| Réduire les flashs | Réduire les flashs / Reduce flashes | pas de clignotements, pas de pulsations, fondus seulement ; activé par défaut si `GuiService.ReducedMotionEnabled` | `{reduceFlashes}` |
| Taille du texte | Taille du texte / Text size : 100 % · 115 % · 130 % | multiplie nos `TextSize` (en plus de `PreferredTextSize` du moteur) | `{textScale}` |
| Garder mon chapeau | Garder mon chapeau / Keep my hat | lu par le domaine avatar | `{keepHat}` |
| Langue | Auto · Français · English | local seulement (pas de champ dans le contrat) | — |
| Légende de la mini-carte | — | affiche le tableau §6 | — |

Les réglages arrivent de `Profile.settings` ; envoi limité à 1 par 0,5 s (regroupé).

---

## 12. Accessibilité

- Les trois préférences `GuiService` respectées et écoutées : `PreferredTextSize` (texte fixe, jamais `TextScaled`), `PreferredTransparency` (transparence des fonds × valeur), `ReducedMotionEnabled` (fondus au lieu de pops, rien qui tourne).
- Daltonisme : palettes par jetons sémantiques + 2e canal partout (losanges, formes, texte).
- Contraste ≥ 4,5:1 pour le texte (texte blanc sur fonds `#1C2230`, contour noir 1 px sur les nombres au-dessus du jeu).
- Aucun clignotement > 3 Hz, aucun flash plein écran, même hors mode réduit.
- Sous-titres : toutes les annonces sont du texte.
- Gros boutons (≥ 44 px), pas d'action critique en appui long seulement (la roue a toujours un équivalent).

## 13. Localisation

- Tout texte visible est `{ fr, en }` (Config.UI.Strings, ou `LocalizedText` reçu du serveur). Anglais par défaut.
- Langue : réglage local, sinon `Translator.LocaleId` du joueur (`GetTranslatorForPlayerAsync` dans un `pcall`, écoute de `LocaleId`), sinon `LocalizationService.RobloxLocaleId`. « fr » si l'id commence par `fr`.
- **`AutoLocalize = false` sur toutes nos guis** : le texte est déjà traduit par nos soins, et les noms inventés (classes, compagnons, armes, boss) ne doivent pas être capturés par la traduction automatique ; les nombres et noms de joueurs non plus (Localization §2).
- Phrases complètes avec paramètres nommés (`"{name} est à terre !"`), jamais de concaténation de fragments ; pas de logique de pluriel anglaise.
- Changement de langue en jeu : tous les textes enregistrés auprès du thème sont réécrits.

## 14. Performance

- Zéro code par image au repos. Boucles par image uniquement pendant : anneau de 8 s, flèche du boss visible, flèches de bord des pings, aperçu tournant de l'écran de sélection. Chaque boucle est connectée/déconnectée.
- Chrono 4 Hz, mini-carte 10 Hz, textes réécrits seulement si la valeur change.
- Pools : marques de mini-carte, marqueurs de pings, lignes du fil, barres de l'écran de fin.
- Aucune création d'instance dans les mises à jour fréquentes ; pas de table allouée par image.
- La partie animée (mini-carte, flèches) est dans ses propres petites guis.

## 15. Câblage des entrées

`InputController` (domaine avatar) possède le système d'actions. Côté UI (module d'aide `UIInput`) :

- écoute : `InputController.onAction(name, fn(pressed))` pour `Card1`–`Card3` (CardUI) et `Ping` (PingUI) ;
- boutons tactiles : `InputController.bindButton(name, button)` s'il existe (liaison `UIButton` du moteur), sinon `InputController.trigger(name, pressed)` sur appui/relâche, sinon repli direct : `Ultimate` → remote `CompanionUltimate`, `Jump` → `Humanoid.Jump`, `Ping` → ping rapide ;
- sans InputController : touches 1/2/3 et clic molette lus par `UserInputService` (en vérifiant `gameProcessedEvent`).

---

## Sources vault

- 05 UI and UX / **Responsive UI for Phone Tablet Console and PC** — profil d'appareil (petit côté < 520), 12 px / 44 px / 8 px, plancher d'échelle, règles du HUD téléphone, passe anti-chevauchement.
- **Safe Areas and Insets** — `ScreenInsets` explicite, `SafeAreaCompatibility = None`, `TopbarInset` jamais en dur (Roblox docs).
- **Mobile Button Layout Editor** — boutons dans le conteneur sûr, positions en échelle, liaison `UIButton`.
- **UI Design Systems** §3–4 — module de thème vs `StyleSheet` (style moteur, éditeur bêta oct. 2026).
- **AI Pitfalls - UI and Input** — `UIScale` jamais imbriqué, vues de test.
- **HUD Design** — zones, file d'annonces, budgets de mouvement et de performance (« write only on change »).
- **Accessibility** — `PreferredTextSize`, `PreferredTransparency`, `ReducedMotionEnabled` (Roblox docs).
- **Colour-Blind Safe Design** — jetons sémantiques, palettes par mode, 2e canal, pas de filtre `ColorCorrectionEffect`.
- **Motion Sensitivity and Camera Comfort** — mouvement réduit = fondu.
- **Text Fonts and Rich Text** — `FontFace`, piège Gotham, échelle typographique.
- **Localization** — `AutoLocalize = false` pour noms inventés, nombres et textes de script ; `GetTranslatorForPlayerAsync` en `pcall` et écoute de `LocaleId` (Roblox docs).
- **Input - UserInputService and ContextActionService** §5 — Input Action System (`InputContext`, `InputAction`, `InputBinding.UIButton`, `Fire()`), `Activated`, `gameProcessedEvent`.
- **Minimap and World Map UI** — nord = monde −Z, projection unique, pas de rotation sans `CanvasGroup`.
- **Race HUD** — chrono calculé localement, pas de texte envoyé par image.
- **Notification and Toast Systems** — le serveur envoie un type + paramètres, le client formate.
- **SYMPTOMS.md** — `DisplayOrder` explicite, `ResetOnSpawn = false`, contour ≤ 7 %, pop via `UIScale`, plancher d'échelle.
