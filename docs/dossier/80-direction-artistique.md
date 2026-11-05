# COHUE — Direction artistique (A01)

**Statut : style changé le 5 nov. 2026 (briques à tenons), à valider par Clément (porte 1).** Guide rédigé le 4 nov. 2026 par l'agent A01 (DA et modeling) et réécrit le 5 nov. après le choix de Clément. Il s'applique à tout ce qui est modélisé ou coloré dans le jeu et complète `01-decisions-v2.md` section 7.

COHUE est **un monde de briques à tenons, en plein soleil**. Tout est monté en briques de jouet chanfreinées, posées en quinconce, avec un tenon sur chaque dessus libre. Le sol est une grande plaque à tenons, d'une couleur par zone. Les personnages sont en briques fines, avec de gros yeux ronds. Le ciel est peint, bleu franc, avec de gros cumulus. La palette reste celle de COHUE (16 couleurs vives), et le ton reste joyeux et absurde.

Références :
- **Pour le style** : les exemples envoyés par Clément le 5 nov., des devlogs Roblox d'octobre 2026 (« Making a good Roblox game » de devZippy, zombies de GreenCapYT). Les captures restent chez Clément et ne sont pas copiées dans le dépôt.
- **Pour le ton** : Megabonk, Octopath Traveler et Steal an Egg, qui restent valables.

On s'en inspire sans copier aucun de leurs modèles, aucune de leurs cartes ni aucun de leurs visuels.

Planches de référence (dossier `assets/style/`) :

| Planche | Contenu | État |
| --- | --- | --- |
| [06-lobby-briques.png](../../assets/style/06-lobby-briques.png) | Le lobby compact en briques à tenons (maquette Blender), ce qu'on garde des exemples | **Nouveau style (5 nov.)** |
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

| Ce qui reste | Ce qui change |
| --- | --- |
| Palette COHUE 16 et ses tons | Le rendu : briques chanfreinées et tenons au lieu de cubes lisses |
| La modélisation sur grille (`models.py`, `lobby.py`) : une cellule = une brique de 1 | Plus d'ombrage cuit par face : les chanfreins et la vraie lumière font le relief |
| Proportions, silhouettes, code couleur des rôles, gags | Le décor n'est plus en tons d'ombre : sols unis aux tons de base, relief par les tenons |
| Équipement et paliers, attaches R15, `ArtLibrary` | Personnages et ennemis : gros yeux ronds blancs |
| Le plan du lobby compact (tête de gobelin, stations) | Lumière : plein jour, ciel peint bleu franc, cumulus (fin de l'ambiance violette) |

## 1. Ce que montrent les exemples

| Élément | Dans les exemples | Règle COHUE |
| --- | --- | --- |
| Construction | Tout est fait de briques et de plaques, avec un chanfrein sur chaque arête et des joints décalés (château, mesas, créatures) | Briques à tenons partout (section 3) |
| Sol | Grande plaque à tenons, une couleur unie par zone (herbe, sable, neige) | Plaque à tenons ; chemins et places en dalles lisses |
| Relief | Falaises et mesas en strates de plaques empilées | Coupe de l'île et falaises en strates |
| Arbres | Troncs en briques, feuillage en plaques empilées (acacias plats, boules) | Arbres en plaques ; jamais d'arbre réaliste |
| Personnages | Briques fines, gros yeux ronds blancs à pupille noire, bouche à dents carrées, accessoires en briques (couronne, chaîne, épaulettes) | Ennemis en briques de 0,25 avec yeux ronds |
| Ciel | Peint : bleu franc en haut, horizon clair, gros cumulus crème, parfois un arc-en-ciel | Skybox peinte maison (A02) |
| Accents | Neon cyan ou or sur les objets précieux (cristaux, lampadaires, machine) | Neon réservé au portail, à la capture, au butin, aux élites |
| Ce qui est montré comme raté (« Before ») | Rochers et arbres réalistes au milieu des briques, glace aux textures bruitées, sol gris | À éviter : un seul style à l'écran |

## 2. Les 10 règles

1. **Tout est monté en briques chanfreinées**, joints décalés d'une rangée sur l'autre, en trois tailles : 0,25, 0,5 et 1 stud (section 3).
2. **Un tenon sur chaque dessus libre**, sauf sur les dalles (chemins, places, planchers), qui restent lisses pour qu'on lise où marcher.
3. **Seulement la palette COHUE 16** et ses tons `.l`, base, `.d`, `.dd`. Une brique a une seule couleur ; on admet ±4 % de clarté d'une brique à l'autre, mais aucun dégradé peint.
4. **Les seules surfaces lisses** sont les yeux ronds des personnages, les effets Neon (portail, capture, butin, élites), le ciel et ses nuages, et l'eau. Tout le reste est en briques.
5. **Les grandes surfaces sont unies** : une couleur par zone, le relief vient des tenons. Pas de mouchetis, pas de damier, pas de texture bruitée.
6. **La famille se lit à la silhouette, le rôle à la couleur.** Le dessus de la tête porte la couleur du rôle, car la caméra est haute et voit surtout le dessus des ennemis.
7. **Gros yeux ronds blancs** à pupille Ink : ce sont les pixels les plus clairs d'un personnage. On y lit l'humeur (colère, panique, sommeil).
8. **Pas de Neon sur les ennemis ordinaires.** Le Neon est réservé à la capture, aux élites, aux boss et aux effets du joueur. Avec 100 ennemis, le bloom deviendrait une bouillie.
9. **Chaque élément a un gag, montré par un objet**, jamais écrit sur un panneau : cocotte en casque, carotte dans le carquois, jambes qui dépassent de la meule de foin.
10. **Vérifié en jeu** : capture Studio à 20 studs au milieu de la horde, silhouette noire reconnaissable à 64 px.

## 3. La brique

On modélise toujours sur une grille de cellules (code Python, voir section 13). Une cellule correspond à une brique de 1 × 1, avec un tenon. `assets/voxel/brick.py` transforme la grille en briques.

| Classe d'objet | Taille de brique | Pourquoi |
| --- | --- | --- |
| Personnages, créatures, équipement, armes, petits props et stations (< 15 studs) | **0,25 stud** | Une tête de gobelin fait 8 briques de large : yeux lisibles |
| Grands props (arbres, rochers), héros de décor (portail), mini-boss, boss | 0,5 stud | Garde le nombre de briques bas sur les grandes formes |
| Sol, falaises, tranches d'île | 1 stud | La grille des tenons du sol tombe sur celle des studs de Roblox |

**Anatomie d'une brique** (valeurs de `brick.py`) :

| Élément | Valeur | Rôle |
| --- | --- | --- |
| Longueur | 1 à 3 cellules (sol : 6), largeur 1 | Assez court pour qu'on lise les briques, assez long pour ne pas faire de grille |
| Pose | En X sur les couches paires, en Y sur les impaires ; joints décalés d'une rangée à l'autre | Appareil de maçonnerie : ça a l'air construit, pas quadrillé |
| Chanfrein | 7 % de la cellule, 1 segment | Dessine le joint et accroche la lumière |
| Tenon | Diamètre 60 % de la cellule, hauteur 18 %, 10 côtés | Signature du style |
| Couleur | Une par brique, ±4 % de clarté | Les briques se distinguent sans bruit |
| Matière | Plastique de jouet (rugosité 0,42 dans Blender) | Un léger reflet sur les chanfreins |

**Où les tenons s'arrêtent** : dalles de chemin et de place, yeux, Neon, eau, verre. Le contraste entre une plaque à tenons et une dalle lisse indique où l'on marche.

Les tons de matière se posent toujours à la main : une rangée `.d` au pied, une bande `.l` en haut d'un chapeau. Il n'y a plus d'ombrage cuit par face : le chanfrein et la lumière du jeu font ce travail.

## 4. Palette COHUE 16

Les tons dérivés se calculent : `.l` = base mélangée à 35 % avec `#FFF4D8` ; `.d` = 35 % avec `#2A1C3D` ; `.dd` = 60 % avec `#2A1C3D`. Le code est dans `assets/voxel/cohue_voxel.py` (`PALETTE`, `tone()`).

| Nom | Hex | Usage | Réserve |
| --- | --- | --- | --- |
| Ink | `#1C1726` | Pupilles, coutures, bombe | |
| Plum | `#4B3866` | Ombres froides, tissu sombre, cape du Mage, bâches | |
| Bark | `#6E4227` | Bois sombre, troncs, chaussures | |
| Leather | `#B5713A` | Cuir, bois clair, cordes ; chemins en `.l` | |
| Cream | `#FFE8B8` | Blanc des yeux, dents, papier, fantômes | |
| Stone | `#9C9488` | Pierre, os ; dalles des places en `.l` | |
| Steel | `#8EA6C2` | Métal, armure du Knight | |
| Gold | `#FFC21A` | Rivets, liserés, couronne d'élite, pièces ; paille en `.d` | Accents seulement : 5 % au plus d'une pièce |
| Ember | `#FF7A1A` | Rôle kamikaze, feu, orbe du Mage | |
| Tomato | `#E63946` | Rôle mêlée, danger, tirs ennemis | |
| **Bubblegum** | `#FF5FB0` | **Capture** (anneau, cage, interface de capture) | **Réservé à la capture, nulle part ailleurs** |
| Grape | `#8C52E0` | Rôle soutien, magie, Mage | |
| Royal | `#2D6BE6` | Knight | |
| Sky | `#3FD0F5` | XP, magie froide, eau | Sur un ennemi, seulement en `.d` / `.dd` (peau des zombies) ou comme XP volée (Bomber) |
| Leaf | `#3DBE4A` | Archer ; herbe (plaque à tenons) | |
| Lime | `#8FD13F` | Peau des gobelins | Réservé aux gobelins |

**Hiérarchie de saturation**, du plus vif au plus calme :

1. Les objets à ramasser (XP cyan, pièces or) brillent en Neon : ce sont les seuls objets lisses et lumineux au sol.
2. Le joueur et la capture : couleur de classe et rose Bubblegum.
3. Les ennemis : peau de famille, couleur de rôle aux tons de base, yeux blancs.
4. Le décor :
   - grands sols aux tons de base, une couleur par zone (herbe Leaf, sable Gold.d, neige Cream) ;
   - chemins et places en `.l` (Leather.l, Stone.l) ;
   - tranches, dessous et strates en `.d` et `.dd`.

**À vérifier en jeu dès le premier monde.** En v1, un sol vif noyait la horde (planche 3). Avec les tenons, le sol a désormais une texture, et les yeux blancs font ressortir les ennemis. Si la capture de horde à 20 studs montre encore des gobelins Lime fondus dans l'herbe Leaf, on repasse l'herbe en Leaf.d pour les mondes de combat. Le lobby, lui, n'a pas de horde.

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

Les briques coûtent beaucoup plus de triangles que les cubes lisses. Un tenon en géométrie fait une trentaine de triangles, et le chanfrein multiplie environ par trois les faces d'une brique. La maquette du lobby compte **1,3 million de triangles** avant chanfreins : elle sert à juger le style, pas à jouer. Roblox limite chaque maille à 20 000 triangles.

En jeu, on combine donc deux techniques :

| Technique | Comment | Pour quoi |
| --- | --- | --- |
| **A. Briques en géométrie** | Briques chanfreinées et tenons modélisés, comme dans la maquette | Ce qu'on voit de près et en un seul exemplaire : portail, stations du lobby, boss. Chaque maille reste sous 20 000 triangles |
| **B. Briques en texture** | Maille fusionnée (comme en v1), avec des UV à l'échelle de la cellule et une texture répétée de joints et de tenons (`SurfaceAppearance`, normal map, ou image de tenons en superposition) | Tout ce qui est répété : ennemis de horde, équipement, armes, arbres, sols |
| **Sol** | Grands Parts ou mailles plates, couleur unie, texture de tenons répétée (comme la plaque de base de Studio) | Plaques à tenons des mondes et du lobby |

**La technique B n'est pas encore testée dans Studio** (A01-02 bis). Il faut vérifier trois choses avant de convertir les 23 meshes :

- la couleur par sommet survit-elle sous une `SurfaceAppearance` ?
- le coût mémoire de la texture sur téléphone ;
- la lisibilité des tenons à 20 studs.

| Classe | Technique | Triangles visés / plafond |
| --- | --- | --- |
| Ennemi d'essaim | B | 800 / 1 000 (v1 mesurée : 656 à 792) |
| Ennemi moyen | B | 1 200 / 2 000 |
| Mini-boss | A ou B | 6 000 / 12 000 |
| Boss | A | 15 000 par maille, plusieurs mailles |
| Pièce d'équipement, arme | B | 300 / 800 (limite Roblox des accessoires : 4 000) |
| Marqueur de capture | lisse (Neon) | 300 / 500 |
| Arbre | B | 600 / 1 500 |
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

**Signature des mondes** (pour A02) : chaque tuile flotte et montre sa coupe en strates (herbe, terre Bark, Leather, plaques de pierre Stone / Stone.d) au bord de l'arène.

## 11. Anti-AI-slop

- Aucune sortie de Meshy, Cube ou d'un autre générateur n'est livrée telle quelle. Crédits Meshy dépensés : 0.
- **Un seul style à l'écran** : pas de rocher réaliste, d'arbre par défaut de Roblox ou de Part grise lisse au milieu des briques. C'est exactement ce que les exemples de Clément montrent comme « avant ».
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

Les 15 mailles existantes ont été générées par IA. Elles sont lisses, avec des textures peintes et des dégradés : elles **ne passent pas ce guide** (règles 1, 3 et 4).

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
models.py / lobby.py (grille) → brick.py (briques chanfreinées, tenons) → rendu Blender (maquettes, planches)
models.py (grille) → cohue_voxel.py (maille fusionnée) → build.py (GLB) → Studio : Import 3D → MeshPart
  → ReplicatedStorage.Assets → ArtLibrary
```

### 13.1 Maquettes en briques

```bash
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python assets/voxel/lobby.py -- assets/voxel/review/lobby_brick
```

`brick.to_blender` a la même signature que `cohue_voxel.to_blender`. La scène du lobby la branche à sa place : tous les modèles, avatars compris, passent en briques sans autre changement. La planche 6 se monte avec `python assets/style/compose.py lobby`.

### 13.2 Export pour Roblox (v1, à adapter à la technique B)

```bash
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python assets/voxel/build.py -- export
```

- **Échelle** : 1 unité Blender = 1 stud. Z en haut dans Blender, le modèle regarde vers −Y. L'export glTF +Y up suivi de l'import Roblox donne : avant −Z, main droite en +X, soit la conversion (x, y, z) → (−x, z, y).
- **Maille fusionnée et étanche** : une face par rectangle de même couleur, avec insertion des coins voisins dans les arêtes longues (0 arête de bord, environ +35 % de triangles).
- **Couleurs** : couleur par coin de face (`BYTE_COLOR`, sRGB), un jeu d'UV neutre, un seul matériau.
- **À faire pour le style briques (A01-02 bis)** :
  - UV à l'échelle de la cellule (une cellule = une tuile de tenon) ;
  - garder un quad par cellule sur les faces qui reçoivent la texture ;
  - fabriquer la texture de joints et de tenons, puis tester dans Studio (section 9).
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
