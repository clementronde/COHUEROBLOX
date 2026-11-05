# COHUE — Direction artistique (A01)

**Statut : style choisi par Clément le 5 nov. 2026 (piste B : tout en tenons, formes naturelles), à valider en jeu (porte 1).** Guide rédigé le 4 nov. 2026 par l'agent A01 (DA et modeling), réécrit le 5 nov. après les retours de Clément. Il s'applique à tout ce qui est modélisé ou coloré dans le jeu et complète `01-decisions-v2.md` section 7.

COHUE est **un monde tout en plastique à tenons, en plein soleil**. Une seule matière pour tout le jeu (décor, objets, personnages), et c'est la forme qui donne le naturel :
- **le décor est en gros blocs à tenons**, posés de façon irrégulière : herbe en terrasses, chemins de terre, falaises en blocs décalés, sapins en plaques inclinées, feuillus en cubes, eau, pierres de gué ;
- **tout ce avec quoi on interagit est en petites briques fines** et chanfreinées : portail, pads, stations, caisses, coffres, personnages, ennemis, équipement.

On repère ce qui sert à son **échelle** (petites briques), à sa **couleur** (saturée sur un décor calme) et à un peu de **Neon**, pas à sa matière. Dans le jeu, les tenons sont posés par le plugin Studio **Resurface** (section 9). Le ciel est peint, bleu franc, avec de gros cumulus. La palette reste celle de COHUE (16 couleurs vives), et le ton reste joyeux et absurde.

Références :
- **Pour le style retenu** : les captures « canyon en tenons » envoyées par Clément le 5 nov. (falaises, sapins et dalles à tenons, eau, pont de bois), et ses premiers exemples de briques (devlogs Roblox d'octobre 2026, « Making a good Roblox game » de devZippy, zombies de GreenCapYT).
- **Pour le ton** : Megabonk, Octopath Traveler et Steal an Egg, qui restent valables.

Les captures restent chez Clément et ne sont pas copiées dans le dépôt. On s'en inspire sans copier aucun de leurs modèles, aucune de leurs cartes ni aucun de leurs visuels.

Planches de référence (dossier `assets/style/`) :

| Planche | Contenu | État |
| --- | --- | --- |
| [06-lobby-tenons.png](../../assets/style/06-lobby-tenons.png) | Le lobby compact tout en tenons (maquette Blender) : décor en gros blocs, interactions en briques fines | **Style retenu (5 nov.)** |
| [07-pistes-melange-ou-tenons.png](../../assets/style/07-pistes-melange-ou-tenons.png) | La comparaison qui a servi au choix : piste A (décor naturel lisse + briques) contre piste B (tout en tenons) | Décision du 5 nov. |
| [01-palette-grain.png](../../assets/style/01-palette-grain.png) | Palette COHUE 16 avec ses tons, échelle avatar / gobelins, hiérarchie de saturation | v1 voxel : palette et échelle valables, rendu à refaire |
| [02-silhouettes-familles.png](../../assets/style/02-silhouettes-familles.png) | Gobelins, zombies et fantômes en ébauche, silhouettes à 64 px, code couleur des rôles | v1 voxel : silhouettes et rôles valables, rendu à refaire |
| [03-diorama-lumiere.png](../../assets/style/03-diorama-lumiere.png) | Ancienne cible d'ambiance (lumière basse, ombres violettes) | **Remplacée** par la section 10 |
| [04-equipement-paliers.png](../../assets/style/04-equipement-paliers.png) | Knight, Archer, Mage aux niveaux 10, 20, 30 | v1 voxel : pièces et gags valables, rendu à refaire |
| [05-armes-depart.png](../../assets/style/05-armes-depart.png) | Les 8 armes de départ | v1 voxel : formes et gags valables, rendu à refaire |

Captures en jeu : `assets/style/captures/`. Elles montrent toutes la v1 voxel ou le lobby en Parts refusé.

## 0. Pourquoi ce changement

- **4 nov.** Le guide v1 est voxel : cubes de 0,25 stud lisses, ombrage cuit par face, décor en tons d'ombre. Les 23 premiers meshes (gobelins, équipement, armes, capture) sont téléversés dans ce style.
- **5 nov., matin.** Clément refuse le premier lobby, posé en Parts dans COHUE : « beaucoup trop AI slop ».
- **5 nov.** Il trouve la maquette voxel du lobby compact « très cool », mais ne veut pas du voxel comme style. Ses 20 exemples montrent tous la même famille : celle que le vault appelle « Classic brick / stud », remise au goût du jour (briques modélisées, lumière franche, ciel peint).
- **5 nov., deuxième retour.** Devant la maquette tout en briques, il précise : « j'aime que la map soit plus naturelle et que les éléments interactifs soient en briques ». Les tenons, eux, peuvent être posés avec un plugin (Resurface).
- **5 nov., choix final.** Ses nouvelles références montrent des cartes tout en tenons aux formes naturelles (canyon, falaises, rivière). Deux pistes sont rendues sur le même lobby (planche 7) : A, un décor naturel lisse avec des interactions en briques ; B, tout en tenons. **Clément choisit B.**

| Ce qui reste | Ce qui change |
| --- | --- |
| Palette COHUE 16 et ses tons | Une seule matière, le plastique à tenons, pour le décor comme pour les objets |
| La modélisation sur grille (`models.py`, `lobby.py`) : une cellule = une brique | Deux échelles : décor en gros blocs, interactions en petites briques chanfreinées |
| Proportions, silhouettes, code couleur des rôles, gags | Plus d'ombrage cuit par face : tenons, chanfreins et vraie lumière font le relief |
| Équipement et paliers, attaches R15, `ArtLibrary` | Personnages et ennemis : gros yeux ronds blancs |
| Le plan du lobby compact (tête de gobelin, stations) | Lumière : plein jour, ciel peint bleu franc, cumulus (fin de l'ambiance violette) |
| | Les tenons ne sont plus modélisés : Resurface les pose dans Studio |

## 1. Ce que montrent les exemples

| Élément | Dans les exemples | Règle COHUE |
| --- | --- | --- |
| Construction | Tout est fait de blocs et de briques à tenons, y compris les falaises, les arbres et les dalles | Une seule matière, le plastique à tenons |
| Sol | Grande plaque à tenons : herbe vert vif, terre et dalles de couleur unie | Herbe en terrasses à tenons, chemins de terre (section 3 bis) |
| Relief | Falaises en gros blocs décalés de tailles différentes, herbe qui déborde sur la roche | Falaises en blocs décalés, couleurs sable et rose qui alternent |
| Arbres | Sapins en plaques empilées et inclinées, feuillus en cubes | Arbres en plaques et en cubes tournés ; jamais d'arbre réaliste ni d'arbre par défaut de Roblox |
| Eau | Eau claire et brillante, pierres de gué à tenons | Eau du Terrain de Roblox, dalles à tenons |
| Personnages | Briques fines, gros yeux ronds blancs à pupille noire, bouche à dents carrées, accessoires en briques (couronne, chaîne, épaulettes) | Ennemis en briques de 0,25 avec yeux ronds |
| Ciel | Peint : bleu franc en haut, horizon clair, gros cumulus crème | Skybox peinte maison (A02) |
| Accents | Neon cyan ou or sur les objets précieux (cristaux, lampadaires, machine) | Neon réservé au portail, à la capture, au butin, aux élites |
| Ce qui est montré comme raté (« Before ») | Rochers et arbres réalistes au milieu des briques, glace aux textures bruitées, sol gris | À éviter : un seul style à l'écran |

## 2. Les 10 règles

1. **Tout est en plastique à tenons** : décor, objets, personnages, ennemis. Une seule matière à l'écran.
2. **Le naturel vient des formes** : blocs décalés, plaques inclinées, terrasses, herbe qui déborde, eau. Jamais de forme lisse, de rocher réaliste ni d'arbre par défaut de Roblox.
3. **Deux échelles** :
   - le décor en gros blocs de 1 à 8 studs (des Parts dans Studio) ;
   - ce avec quoi on interagit en petites briques chanfreinées de 0,25 ou 0,5 stud (section 3).

   L'échelle, la couleur saturée et un peu de Neon disent « ça sert ».
4. **Les tenons sont posés dans Studio par le plugin Resurface**, sur les Parts comme sur les mailles. On ne les modélise pas : les maquettes les dessinent en texture pour juger le rendu. Les seules surfaces lisses sont les yeux, le Neon, l'eau et le ciel.
5. **Seulement la palette COHUE 16** et ses tons `.l`, base, `.d`, `.dd`. Un bloc ou une brique a une seule couleur (±4 % de clarté d'une pièce à l'autre). Pas de dégradé, pas de mouchetis, pas de texture bruitée : les grandes surfaces sont des aplats, et les tenons leur donnent leur grain.
6. **La famille se lit à la silhouette, le rôle à la couleur.** Le dessus de la tête porte la couleur du rôle, car la caméra est haute et voit surtout le dessus des ennemis.
7. **Gros yeux ronds blancs** à pupille Ink : ce sont les pixels les plus clairs d'un personnage. On y lit l'humeur (colère, panique, sommeil).
8. **Pas de Neon sur les ennemis ordinaires.** Le Neon est réservé à la capture, aux élites, aux boss et aux effets du joueur. Avec 100 ennemis, le bloom deviendrait une bouillie.
9. **Chaque élément a un gag, montré par un objet**, jamais écrit sur un panneau : cocotte en casque, carotte dans le carquois, jambes qui dépassent de la meule de foin.
10. **Vérifié en jeu** : capture Studio à 20 studs au milieu de la horde, silhouette noire reconnaissable à 64 px.

## 3. La brique

Les petites briques fines sont réservées aux éléments interactifs (règle 3). On les modélise toujours sur une grille de cellules (code Python, voir section 13). Une cellule correspond à une brique de 1 × 1 et à un tenon. `assets/voxel/brick.py` transforme la grille en briques pour les maquettes.

| Classe d'objet | Taille de brique | Pourquoi |
| --- | --- | --- |
| Personnages, créatures, équipement, armes, butin, stations et caisses (< 15 studs) | **0,25 stud** | Une tête de gobelin fait 8 briques de large : yeux lisibles |
| Grandes pièces interactives (portail, grandes machines), mini-boss, boss | 0,5 stud | Garde le nombre de briques bas sur les grandes formes |

**Anatomie d'une brique** (valeurs de `brick.py`) :

| Élément | Valeur | Rôle |
| --- | --- | --- |
| Longueur | 1 à 3 cellules (sol : 6), largeur 1 | Assez court pour qu'on lise les briques, assez long pour ne pas faire de grille |
| Pose | En X sur les couches paires, en Y sur les impaires ; joints décalés d'une rangée à l'autre | Appareil de maçonnerie : ça a l'air construit, pas quadrillé |
| Chanfrein | 7 % de la cellule, 1 segment | Dessine le joint et accroche la lumière |
| Tenon | Un par cellule, en texture (`assets/voxel/tex/`) | Signature du style. En jeu, posé par Resurface : on ne le modélise pas |
| Couleur | Une par brique, ±4 % de clarté | Les briques se distinguent sans bruit |
| Matière | Plastique de jouet (rugosité 0,42 dans Blender) | Un léger reflet sur les chanfreins |

**Où les tenons s'arrêtent** : dalles où l'on marche (pads, planchers des stations), yeux, Neon, verre.

Les tons de matière se posent toujours à la main : une rangée `.d` au pied, une bande `.l` en haut d'un chapeau. Il n'y a plus d'ombrage cuit par face : le chanfrein et la lumière du jeu font ce travail.

## 3 bis. Le décor en gros blocs

Tout ce qui n'est pas interactif est fait de gros blocs à tenons, comme des Parts posées à la main. Les formes viennent de `assets/voxel/studs.py`, et l'île du lobby de `studs_island` et `studs_cliff` dans `lobby.py`.

| Élément | Forme | Couleurs |
| --- | --- | --- |
| Herbe | Blocs d'un stud en terrasses : collines douces vers les bords, plat là où l'on marche | Leaf et Leaf.l en grandes plaques (8 studs ou plus) |
| Chemins | Terre en aplat, bords en escalier d'un stud | Leather.l |
| Clairières (place, parvis, sols de stations) | Terre plus sombre, dalles à tenons posées un peu de travers | Leather, dalles Stone.l |
| Falaises | Gros blocs de 3 à 8 studs, de hauteurs différentes, avec des blocs qui débordent de la paroi ; herbe sur une partie des sommets | Leather.l, Cream.d et Stone.l qui alternent d'un bloc à l'autre (sable et rose) |
| Flanc de l'île | Blocs de roche de 3 × 3 × 2 qui se resserrent sous l'île | Mêmes tons de roche, en alternance |
| Sapins | Tronc d'un stud, 4 plaques carrées empilées, chacune tournée et inclinée de quelques degrés | Leaf.d et Leaf en alternance |
| Feuillus | Tronc, deux branches inclinées, 5 cubes de feuillage tournés | Leaf.d, Leaf, Leaf.l ; automne Ember.d, Ember, Gold.d (un arbre sur cinq environ) |
| Buissons, rochers | 2 ou 3 cubes ; un bloc incliné | Leaf / Leaf.d ; tons de roche |
| Champignons | Pied et chapeau en blocs | Cream et Tomato (petit gag de décor) |
| Eau | Plan d'eau dans un creux de deux studs, dalles de gué | Eau du Terrain de Roblox ; fond Leather.d |
| Forêt en lisière | Dense sur les bords, rien sur les passages ni devant les stations | Surtout des sapins, quelques feuillus et buissons |

**En jeu.** Le décor se construit dans Studio avec des Parts (blocs et coins) aux couleurs de la palette, en `SmoothPlastic`, puis Resurface pose les tenons. Aucune maille ni téléversement n'est nécessaire. Pour l'île du lobby, deux voies sont possibles :
- des Parts fusionnés en grands rectangles, comme le fait déjà le maillage glouton (`studs_island`) ;
- une maille unique avec des UV à l'échelle du stud, qui reçoit la MaterialVariant de Resurface.

L'eau vient du Terrain. Les arbres sont des groupes de 6 à 10 Parts, à cloner en `Model` (« rien n'est construit par script » : ils sont posés dans la place).

## 4. Palette COHUE 16

Les tons dérivés se calculent : `.l` = base mélangée à 35 % avec `#FFF4D8` ; `.d` = 35 % avec `#2A1C3D` ; `.dd` = 60 % avec `#2A1C3D`. Le code est dans `assets/voxel/cohue_voxel.py` (`PALETTE`, `tone()`).

| Nom | Hex | Usage | Réserve |
| --- | --- | --- | --- |
| Ink | `#1C1726` | Pupilles, coutures, bombe | |
| Plum | `#4B3866` | Ombres froides, tissu sombre, cape du Mage, bâches | |
| Bark | `#6E4227` | Bois sombre, troncs, chaussures | |
| Leather | `#B5713A` | Cuir, bois clair, cordes ; terre des chemins (`.l`), roche claire (`.l`) | |
| Cream | `#FFE8B8` | Blanc des yeux, dents, papier, fantômes ; roche rose (`.d`) | |
| Stone | `#9C9488` | Pierre, os ; roche et dalles (`.l`) | |
| Steel | `#8EA6C2` | Métal, armure du Knight | |
| Gold | `#FFC21A` | Rivets, liserés, couronne d'élite, pièces ; paille en `.d` | Accents seulement : 5 % au plus d'une pièce |
| Ember | `#FF7A1A` | Rôle kamikaze, feu, orbe du Mage | |
| Tomato | `#E63946` | Rôle mêlée, danger, tirs ennemis | |
| **Bubblegum** | `#FF5FB0` | **Capture** (anneau, cage, interface de capture) | **Réservé à la capture, nulle part ailleurs** |
| Grape | `#8C52E0` | Rôle soutien, magie, Mage | |
| Royal | `#2D6BE6` | Knight | |
| Sky | `#3FD0F5` | XP, magie froide, eau | Sur un ennemi, seulement en `.d` / `.dd` (peau des zombies) ou comme XP volée (Bomber) |
| Leaf | `#3DBE4A` | Archer ; herbe et feuillage | |
| Lime | `#8FD13F` | Peau des gobelins | Réservé aux gobelins |

**Hiérarchie de saturation**, du plus vif au plus calme :

1. Les objets à ramasser (XP cyan, pièces or) brillent en Neon : ce sont les seuls objets lisses et lumineux au sol.
2. Le joueur et la capture : couleur de classe et rose Bubblegum.
3. Les ennemis : peau de famille, couleur de rôle aux tons de base, yeux blancs.
4. Le décor : grands aplats aux tons calmes (herbe Leaf / Leaf.l, terre Leather, roche sable et rose). Les arbres d'automne sont la seule touche chaude.

**À vérifier en jeu dès le premier monde.** En v1, un sol vif noyait la horde (planche 3). Avec une seule matière, rien ne sépare l'ennemi du sol, sinon sa taille de brique, ses yeux blancs et sa couleur de rôle. C'est le principal risque de la piste B : cent ennemis à tenons sur un sol à tenons. Les parades :
- un sol des arènes aux tons calmes et en grands aplats ;
- des ennemis saturés ;
- une capture de horde à 20 studs dès le premier test.

Si les gobelins Lime se fondent dans l'herbe, on assombrit l'herbe des arènes vers Leaf.d, ou on retire les tenons du sol des arènes. Le lobby, lui, n'a pas de horde.

## 5. Proportions

Repère : l'avatar R15 par défaut mesure **5,46 studs** (tête 1,16 × 1,18 × 1,16, torse 1,94 × 1,70 × 1,00), mesuré dans Studio.

| Élément | Hauteur | Règle |
| --- | --- | --- |
| Avatar du joueur | 5,5 studs | Jamais modifié ; seuls les accessoires s'ajoutent |
| Ennemi d'essaim (gobelin, zombie, fantôme) | 3,5 à 4,25 studs dessinés | Environ 65 % de l'avatar ; tête = 40 à 45 % de la hauteur ; largeur ≥ 3 studs avec les oreilles ou les bras |
| Élite | même maille ×1,25 | Couronne et anneau or en Neon (déjà dans EnemyRenderer) |
| Ennemi moyen (bloater, armure hantée) | 4 à 5 studs | |
| Mini-boss | 8 à 10 studs | Briques de 0,5 |
| Boss | 16 à 20 studs | Briques de 0,5, plusieurs mailles de moins de 20 000 triangles |
| Héros de décor (portail du lobby) | ≥ 1,5 × tout ce qui l'entoure | La tête de gobelin fait 32 studs |
| Pièce d'équipement | ≈ 1,4 × la partie du corps couverte | Un casque fait 2 studs de large pour une tête de 1,16 |
| Arme tenue | 3 à 4 studs de long | Lame ou manche épais d'au moins 2 briques |

**Taille en jeu.** `EnemyRenderer` redimensionne la maille à `height × 1,3` (ART_SCALE). Pour garder des briques de 0,25 stud, les hauteurs de `Config/Enemies` doivent valoir hauteur de la maille ÷ 1,3. Pour les gobelins : Grunt 2,9 · Archer 2,7 · Shaman 3,25 · Bomber 2,7 (voir Contract requests).

## 6. Lisibilité dans la horde, sur téléphone

Calcul de référence : écran paysage de 1080 px de haut, FieldOfView vertical de 70°. À 30 studs, on voit 42 studs de haut, soit environ 26 px par stud : un gobelin de 3,5 studs fait 90 px. À 60 studs, il fait 45 px, une brique de 0,25 ne fait plus que 3 px et ses tenons disparaissent. Un détail qui compte doit donc faire **au moins 2 × 2 briques** (0,5 stud). Les yeux ronds font au moins 0,5 stud de diamètre.

**Code couleur des rôles, commun à toutes les familles.** Il est porté par le dessus de la tête et par les vêtements.

| Rôle | Couleur | Gobelin | Zombie (prévu) | Fantôme (prévu) |
| --- | --- | --- | --- | --- |
| Mêlée / essaim | Tomato | Grunt : cocotte rouge en casque, louche brandie qui sort de la silhouette | Shambler | Wisp |
| Tireur | Leaf.d / Leather | Archer : capuche vert sombre, grand arc | Gravedigger (lance de la terre) | Poltergeist |
| Soutien | Grape | Shaman : champignon magique violet | (à définir) | Banshee |
| Kamikaze / gros | Ember + bombe Ink | Bomber : bonnet orange, grosse bombe à bout de bras sur le côté (silhouette ronde à lui) | Bloater | Armure hantée (blindé) |

**Règles de lecture :**

- La famille se lit à la silhouette remplie en noir (planche 2, silhouettes de face) :
  - **gobelins** : forme en T, avec de grandes oreilles horizontales ;
  - **zombies** : forme en Γ, bras tendus devant et dos voûté ;
  - **fantômes** : dôme et bas ondulé, sans pieds, à 1 stud du sol.
- Chaque ennemi a au plus 4 couleurs principales, plus Ink et Cream (les yeux).
- Les tirs ennemis sont Tomato, lents, sans Neon. Ceux du joueur sont aux couleurs de la classe et brillent. On distingue un tir ennemi d'un tir ami d'un coup d'œil.
- **Capturable** : anneau carré au sol et cage flottante au-dessus de la tête, tous deux en Neon Bubblegum. Aucun autre objet du jeu n'est rose, donc on le repère au milieu de 100 ennemis.
- **Élite** : anneau et couronne or en Neon (existant).
- Le joueur se repère à son équipement de classe. Une pastille au sol sous le joueur est recommandée à l'agent UI ou VFX.

## 7. Silhouettes par famille

| Famille | Monde | Peau | Silhouette | Ton | Statut |
| --- | --- | --- | --- | --- | --- |
| Gobelins | 1 · Bois Grognon | Lime | T : grosses oreilles horizontales, petites jambes, grosse tête | Bricoleurs ridicules (cocotte, louche, bonnet d'aviateur) | Livrés en v1 voxel (A01-04) ; **à repasser en briques, avec des yeux ronds** |
| Zombies | 2 · cimetière / marais | Sky.d (bleu-vert mat) | Γ : bras tendus, tête basse en avant ; haillons Plum | Maladroits (zombie en tutu Grape.l, pas en rose) | Ébauches (A01-08) |
| Fantômes | 3 · Récré Fantôme | Cream | Dôme + bas ondulé, flottent ; objets d'école | Surveillants de cantine | Ébauches (A01-08) |

## 8. Équipement des classes

L'avatar reste intact : la classe ajoute des **Accessories** en briques sur les attaches R15 standard. Les pièces se **cumulent** : niveau 10 = tête, niveau 20 = épaules ou bras, niveau 30 = grande pièce de dos, celle que voit la caméra placée derrière le joueur. Avant le niveau 10, l'arme de départ suffit à reconnaître la classe. Les pièces de tête laissent le visage visible.

Les 9 pièces livrées le 4 nov. sont en v1 voxel. Leurs formes, leurs attaches et leurs gags restent ; seul leur rendu passe en briques.

| Classe | Couleurs | Niveau 10 (tête) | Niveau 20 | Niveau 30 (dos) |
| --- | --- | --- | --- | --- |
| Knight | Steel + Royal, rivets Gold | Bassinet ouvert, plumet ridiculement court · `HatAttachment` | Épaulières bleu roi (elles se détachent du casque en acier), la même maille pour les deux (demi-tour à gauche) · `RightShoulderAttachment` + `LeftShoulderAttachment` | Cape bleu roi au canard couronné · `BodyBackAttachment` |
| Archer | Leaf + Leather | Capuche à pointe, broche en gland · `HatAttachment` | Brassard en cuir, cible rouge et crème sur le dos de l'avant-bras (visible de la caméra) · `LeftGripAttachment` (tourné de −90° sur X) | Carquois droit, une flèche est une carotte · `BodyBackAttachment` |
| Mage | Grape + Plum, étoiles Gold | Chapeau pointu à grelot · `HatAttachment` | Orbe de feu dans une cage, 1 stud au-dessus et 1,25 stud à l'extérieur de l'épaule gauche, cœur en cube Neon Ember · `LeftShoulderAttachment` | Cape étoilée à haut col, arrêtée au genou (les jambes ne la traversent pas) · `BodyBackAttachment` |

Couleurs réservées pour les 5 autres classes (A01-07) : Guardian Stone + Ember · Rogue Plum + Ink + Tomato · Cleric Cream + Gold + Sky · Barbarian Bark + Tomato + fourrure Cream · Tamer Leather + Leaf + Ember.

**Échelle de l'avatar.** Chaque accessoire porte la taille de la partie du corps de référence (attribut `RefPartSize`). `ArtLibrary.equipAccessory(character, name)` met la pièce à l'échelle de l'avatar réel (Rthro, corps fins…) avant `Humanoid:AddAccessory`.

**Chapeaux et cheveux du joueur.** Ils traversent les pièces de tête. Je recommande de masquer les accessoires `Hat` et `Hair` de l'avatar pendant la run, avec le réglage `keepHat` déjà prévu (Contract request).

## 9. Budgets

Le décor en gros blocs ne coûte presque rien en triangles : ce sont des Parts, et c'est leur nombre qu'il faut surveiller. Les petites briques fines coûtent plus cher, car le chanfrein multiplie environ par trois les faces d'une brique. La maquette du lobby ne sert qu'à juger le style : ses mailles ne sont pas optimisées. Roblox limite chaque maille à 20 000 triangles.

**Les tenons en jeu : le plugin Resurface.** C'est le plugin qu'utilise Clément. Il est gratuit, publié sous licence MIT par cxmeel (anciennement « Surface Tool »), et disponible sur le Creator Store. Il remet les surfaces classiques de Roblox, dont les tenons, sur les Parts, les modèles, les mailles et les unions. Sur les mailles et les unions, il passe par des **MaterialVariants** ([fil DevForum](https://devforum.roblox.com/t/1226536), [code source](https://github.com/cxmeel/resurface-plugin)).

Ce que ça change pour nous :
- **les mailles ne portent pas de tenons**, Resurface les ajoute ;
- **il faut de vraies UV.** Une MaterialVariant se répète selon les UV de la maille. Or notre export v1 pose des UV neutres (tout en 0,5), et les tenons n'apparaîtraient pas. Il faut des UV à l'échelle de la cellule : une cellule = un tenon ;
- **un matériau couvre toute la MeshPart.** Les parties sans tenons (yeux, Neon, dalles où l'on marche) doivent donc être des MeshParts séparées ;
- **les tenons d'une MaterialVariant couvrent toutes les faces**, pas seulement le dessus. Si on ne les veut que sur le dessus, il faut séparer les faces du dessus.

Pour les briques elles-mêmes, on combine deux techniques :

| Technique | Comment | Pour quoi |
| --- | --- | --- |
| **A. Briques en géométrie** | Briques chanfreinées modélisées, sans tenons (Resurface les pose) | Ce qu'on voit de près et en un seul exemplaire : portail, stations du lobby, boss. Chaque maille reste sous 20 000 triangles |
| **B. Maille fusionnée** | Maille fusionnée comme en v1, avec des UV à l'échelle de la cellule ; les tenons de Resurface suffisent à dire « brique » | Tout ce qui est répété : ennemis de horde, équipement, armes, butin |
| **Décor en blocs** | Parts posées dans Studio (blocs, coins), tenons par Resurface, sans maille | Toute la carte (section 3 bis) |

**À tester dans Studio avant de convertir les 23 meshes** (A01-02 bis) :

- Resurface sur une de nos MeshParts (un gobelin, une station) exportée avec des UV à l'échelle de la cellule : les tenons tombent-ils un par cellule ?
- la couleur par sommet survit-elle sous la MaterialVariant de Resurface, ou faut-il une MeshPart par couleur ?
- le coût : une MaterialVariant est partagée par toutes les pièces, donc a priori peu de mémoire, à mesurer sur téléphone ;
- la lisibilité des briques et des tenons à 20 studs sur téléphone.

| Classe | Technique | Triangles visés / plafond |
| --- | --- | --- |
| Ennemi d'essaim | B | 800 / 1 000 (v1 mesurée : 656 à 792) |
| Ennemi moyen | B | 1 200 / 2 000 |
| Mini-boss | A ou B | 6 000 / 12 000 |
| Boss | A | 15 000 par maille, plusieurs mailles |
| Pièce d'équipement, arme | B | 300 / 800 (limite Roblox des accessoires : 4 000) |
| Marqueur de capture | lisse (Neon) | 300 / 500 |
| Arbre (décor) | 6 à 10 Parts | Compter les Parts, pas les triangles |
| Station du lobby | A | 20 000 par maille au plus |
| Portail du lobby | A, en plusieurs mailles | 20 000 par maille |

Le plafond d'ennemis à l'écran reste à mesurer par A13, une fois la technique B en place.

## 9 bis. Armes de départ (A01-05)

Planche : [05-armes-depart.png](../../assets/style/05-armes-depart.png) (v1 voxel, rendu à refaire en briques). L'origine est le centre de la prise, et l'arme pointe vers +Y dans Roblox. L'attribut `GripOffset` donne la prise depuis le centre de la maille.

| Arme | Classe | Gag |
| --- | --- | --- |
| Broadsword | Knight | Pommeau en canard (rappel de la cape) |
| Longbow | Archer | Une feuille pousse au bout de la branche |
| Fire Staff | Mage | Une guimauve grille sous la flamme ; cristal doublé d'un cube Neon |
| Quake Hammer | Guardian | Pansement en croix sur la tête du marteau |
| Throwing Daggers | Rogue | Ruban rouge noué au pommeau (projectile) |
| Holy Aura | Cleric | Clochette de cantine en porcelaine qui « sonne » l'aura |
| Spinning Axes | Barbarian | Smiley gravé sur le fer |
| Beast Whip | Tamer | Fouet enroulé à pompon de cirque |

## 10. Lumière et ciel (proposition pour A02-05)

On abandonne l'ambiance de la v1 (soleil bas, ombres violettes, flou de maquette). Le nouveau style demande :

- **plein jour** et un soleil haut et chaud ;
- des **ombres franches et bleutées** ;
- un **ciel peint** : bleu franc au zénith, horizon presque blanc, gros cumulus crème ;
- peu de lumière ambiante, pour que les couleurs restent franches ;
- un léger reflet plastique sur les chanfreins.

Valeurs de départ, à régler monde par monde :

| Réglage | Valeur |
| --- | --- |
| `Lighting.ClockTime` / `GeographicLatitude` | 13 / 30 |
| `Brightness` | 3 |
| `Ambient` / `OutdoorAmbient` | `#4E5A70` / `#7F96B8` |
| `ColorShift_Top` | `#FFE6C4` |
| `EnvironmentDiffuseScale` / `SpecularScale` | 0,5 / 0,4 |
| `Atmosphere` | Density 0,22 · Offset 0,1 · Color `#D6ECFF` · Decay `#5F98E0` · Glare 0 · Haze 0,8 |
| `Sky` | Skybox peinte maison (6 faces) : dégradé `#1F63D8` → `#7FC2F7` → `#DDF1FF` à l'horizon, cumulus crème. À peindre par A02, sans reprendre de ciel existant |
| `ColorCorrectionEffect` | Saturation +0,15 · Contrast +0,08 |
| `BloomEffect` | Intensity 0,5 · Size 24 · Threshold 0,95 (seul le Neon fleurit) |
| `DepthOfFieldEffect` | Léger : FarIntensity 0,15, au-delà de 120 studs |

La maquette du lobby (`assets/voxel/lobby.py`, fonction `painted_sky`) utilise ce dégradé. Le ciel y est affiché à pleine force, mais n'éclaire le décor qu'à 45 %. Le `ColorGradingEffect` en mode `Retro` de la place de test désature la palette : il faut l'enlever ou le tester (A02). Les captures MCP de Studio n'affichent pas le post-traitement : la lumière se valide en Play, sur téléphone.

**Signature des mondes** (pour A02) : chaque arène est une île flottante en blocs à tenons, bordée d'une forêt de sapins en plaques. Le flanc est en blocs de roche qui se resserrent sous l'île, et de l'eau coule entre les terrasses. Les éléments interactifs, en briques fines, s'y détachent.

## 11. Anti-AI-slop

- Aucune sortie de Meshy, Cube ou d'un autre générateur n'est livrée telle quelle. Crédits Meshy dépensés : 0.
- **Une seule matière à l'écran** : le plastique à tenons. Pas de rocher réaliste, d'arbre par défaut de Roblox, de forme lisse, de texture photo ni de Part grise sans tenons : les exemples de Clément montrent ces mélanges comme « avant ».
- Pas de panneau qui explique : une station se reconnaît à ses objets. Le texte est réservé à l'interface (classements, compte à rebours).
- Pas de motif bruité : on préfère de grandes surfaces unies, dont le relief vient des tenons.
- Composition d'abord, détail ensuite : un seul héros par vue, des chemins qui y mènent, de la densité vers les bords (note du vault « World Composition and Set Dressing »).
- Maquette rendue et relue avant toute construction dans Studio.
- Silhouettes testées en noir à 64 px ; couleurs vérifiées en jeu sur le sol du monde.

## 11 bis. Relectures quality-score (historique v1 voxel)

Le 4 nov., trois relecteurs ont noté les lots v1 à l'aveugle (grille modèle adaptée au voxel) :

| Lot | Tour 1 (médiane) | Tour 2 (médiane) |
| --- | --- | --- |
| Gobelins | 7,0 | 8,7 |
| Équipement | 7,0 | 7,7 |

Les corrections du tour 1 restent acquises dans les formes, quel que soit le rendu :

- la louche du Grunt brandie hors de la silhouette ;
- la bombe du Bomber portée sur le côté ;
- une peau Lime moins jaune ;
- l'orbe du Mage écartée du chapeau ;
- la cape du Mage arrêtée au genou.

Il restait trois défauts sur l'équipement :

- les capes rigides descendent sur les jambes ;
- le carquois touche la capuche ;
- Mage_Hat dépasse 300 triangles.

Ils seront corrigés au passage en briques. Le lobby en briques n'a pas encore été relu à l'aveugle.

## 12. Créatures existantes (`assets/creatures/`)

Les 15 mailles existantes ont été générées par IA. Elles sont lisses, avec des textures peintes et des dégradés : elles **ne passent pas ce guide** (règles 1, 2 et 5).

| Modèle | Décision |
| --- | --- |
| Grand Chêne Ronchon (boss monde 1) | À refaire en briques de 0,5 (A01-09) en gardant l'idée : souche grognon à sourcils de mousse |
| Gland Grincheux, Champignon Sauteur, Hibou Plongeur (faune monde 1) | À refaire en briques (faune d'essaim, peau de famille « forêt » à définir sans Lime ni Bubblegum) |
| Souche Géante | Doublon possible du mini-boss : à trancher avec A03 |
| Bogue Blindée | Hors liste v2 : retirée |
| Braise, Marée, Ronce (anciens compagnons) | Sortent du jeu (décision v2) |

Les mailles actuelles restent en place tant que les remplaçantes ne sont pas livrées : le jeu continue de tourner.

## 13. Pipeline Blender → Roblox (A01-02)

Le source de chaque modèle est du code Python, qui modélise sur grille : `assets/voxel/models.py` pour les personnages et les objets, `assets/voxel/lobby.py` pour le lobby. Les modèles restent ainsi relisibles, versionnés, réglables et reproductibles.

```
models.py / lobby.py (grille) → brick.py (briques fines chanfreinées, tenons en texture) ┐
lobby.py / studs.py (île en blocs, falaises, arbres en blocs, eau)                        ┴→ rendu Blender
models.py (grille) → cohue_voxel.py (maille fusionnée) → build.py (GLB) → Studio : Import 3D → MeshPart
  → ReplicatedStorage.Assets → ArtLibrary
```

### 13.1 Maquettes en briques

```bash
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python assets/voxel/lobby.py -- assets/voxel/review/lobby_studs
```

`brick.to_blender` a la même signature que `cohue_voxel.to_blender` : la scène du lobby la branche à sa place, et tous les modèles interactifs, avatars compris, passent en briques. Avec `brick.STUD_TEXTURE`, les tenons sont une texture projetée (`studs.stud_material`), comme Resurface en jeu. Le décor en blocs est construit à part par `studs_island`, `studs_cliff` et `studs_dressing`. L'option `--nature` rend la piste A pour comparer. Les planches se montent avec `python assets/style/compose.py lobby` (planche 6) et `compare` (planche 7).

### 13.2 Export pour Roblox (v1, à adapter à la technique B)

```bash
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python assets/voxel/build.py -- export
```

- **Échelle** : 1 unité Blender = 1 stud. Z en haut dans Blender, le modèle regarde vers −Y. L'export glTF +Y up suivi de l'import Roblox donne : avant −Z, main droite en +X, soit la conversion (x, y, z) → (−x, z, y).
- **Maille fusionnée et étanche** : une face par rectangle de même couleur, avec insertion des coins voisins dans les arêtes longues (0 arête de bord, environ +35 % de triangles).
- **Couleurs** : couleur par coin de face (`BYTE_COLOR`, sRGB), un jeu d'UV neutre, un seul matériau.
- **À faire pour le style briques (A01-02 bis)** :
  - UV à l'échelle de la cellule (une cellule = un tenon de Resurface), en projection par face ;
  - séparer en MeshParts ce qui ne doit pas porter de tenons (yeux, Neon, dalles) ;
  - appliquer Resurface dans Studio, puis faire les tests de la section 9.
- **Toujours exporter en ligne de commande.** Forcer le contexte d'une autre scène dans un Blender ouvert l'a fait planter.

### 13.3 Importer dans Studio

`AssetService:CreateAssetAsync` n'est pas encore ouvert (« not available yet », testé le 4 nov.). Le téléversement passe par **Import 3D**, un fichier à la fois. Réglages :
- Scale Unit = **Studs** ;
- Upload to Roblox activé ;
- Merge Meshes désactivé ;
- Use Imported Pivot activé ;
- Ignore Vertex Colors **désactivé**.

Ensuite, `assets/install/A01_finalize.luau` (généré par `python assets/install/make_finalize.py`) range les MeshParts dans `ReplicatedStorage.Assets`, construit les Accessories et affiche la liste `nom;MeshId;taille`. `python assets/install/make_records.py` écrit les fiches CSV et `.model.json`.

**Rien n'est construit par script en jeu** (décision de Clément du 4 nov.) : décor, ennemis et lobby existent comme objets posés dans la place COHUE, et les scripts ne font que cloner.

## 14. Livrables et ids Roblox (v1 voxel)

**Import fait le 4 nov. (soir)** dans la place `COHUE` (placeId 132257920785923), par la file d'importation de Studio : unité studs, facteur 1, couleurs par sommet conservées, téléversement sur le compte de Clément. Capture : `assets/style/captures/studio_COHUE_meshes_televerses.jpg`. Les tailles en jeu sont identiques au manifeste, l'avant de chaque mesh est en −Z, et `A01_finalize.luau` a créé `ReplicatedStorage.Assets` : Creatures (4), Equipment (10 Accessories), Weapons (8), FX (2).

**Ces 23 meshes sont dans le style v1 voxel.** Ils font tourner le jeu en attendant leurs versions en briques. Les nouvelles versions demanderont un nouveau téléversement, donc l'accord de Clément.

Fiches dans le dépôt : `assets/a01-meshes.csv`, les lignes gobelins de `assets/creatures.csv`, les `.model.json` (format Rojo) de `assets/creatures/`, `assets/equipment/`, `assets/weapons/` et `assets/fx/`.

| Mesh | MeshId | Taille (studs) |
| --- | --- | --- |
| Enemy_GoblinGrunt | `102615059367724` | 4.500 × 4.000 × 2.000 |
| Enemy_GoblinArcher | `132629528679784` | 3.500 × 3.500 × 2.500 |
| Enemy_GoblinShaman | `85524445528373` | 3.500 × 4.250 × 2.000 |
| Enemy_GoblinBomber | `85411290248554` | 4.500 × 3.500 × 1.750 |
| FX_CaptureRing | `127618518100828` | 3.500 × 0.500 × 3.500 |
| FX_CaptureIcon | `120961194899196` | 1.000 × 2.000 × 1.000 |
| Knight_Helm | `132240907256271` | 2.000 × 2.000 × 2.250 |
| Knight_Pauldron | `72447148865331` | 1.750 × 1.500 × 1.500 |
| Knight_Cape | `99009188505054` | 2.500 × 3.500 × 1.000 |
| Archer_Hood | `75942870774271` | 2.250 × 2.750 × 2.500 |
| Archer_Bracer | `120950419069141` | 1.750 × 1.250 × 1.750 |
| Archer_Quiver | `75868637250392` | 2.000 × 3.500 × 0.750 |
| Mage_Hat | `92427299567407` | 3.000 × 2.750 × 3.000 |
| Mage_Orb | `121605107426611` | 2.000 × 2.500 × 2.000 |
| Mage_Cape | `96432733334599` | 3.000 × 4.250 × 1.000 |
| Weapon_Broadsword | `135800784718280` | 2.000 × 5.000 × 1.000 |
| Weapon_Longbow | `125338053789307` | 0.500 × 5.250 × 1.000 |
| Weapon_FireStaff | `135835703924289` | 1.250 × 5.750 × 1.000 |
| Weapon_QuakeHammer | `125437062108252` | 2.500 × 5.250 × 1.250 |
| Weapon_ThrowingDagger | `91444651706594` | 1.000 × 2.500 × 0.750 |
| Weapon_HolyBell | `83647104694033` | 2.000 × 3.500 × 2.000 |
| Weapon_SpinningAxe | `102028773090465` | 2.250 × 3.250 × 0.750 |
| Weapon_BeastWhip | `98868436713221` | 2.000 × 4.750 × 2.000 |

## Notes du vault utilisées

`Environment Art Styles` (famille « Classic brick / stud ») · `Voxel and Blocky Modeling` et `Voxel Art - Studs Outlines and Style Kits` (kit « toy-box », tenons en texture, paramètres des tenons) · `World Composition and Set Dressing - Designed, Not Scattered` · `Lobby and Hub Design` · `Art-Direction Nitpicks - The Principles Behind Them` · `Meshing Voxels for Roblox - Greedy Meshing and Export` · `Trim Sheets Atlases and Vertex Colors` · skills `fwjelaa-blender-modeling` et `fwjelaa-asset-import` · limite Roblox de 20 000 triangles par maille (docs Roblox, octobre 2026, citées par le vault).
