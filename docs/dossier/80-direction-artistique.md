# COHUE — Direction artistique (A01)

**Statut : à valider par Clément (porte 1).** Rédigé le 4 nov. 2026 par l'agent A01 (DA et modeling). Ce guide s'applique à tout ce qui est modélisé ou coloré dans le jeu. Il complète `01-decisions-v2.md` section 7.

COHUE est **un diorama voxel bien éclairé**. Les éléments sont faits de cubes de 0,25 stud, avec une palette de 16 couleurs vives. Les personnages sont saturés, le décor plus calme, la lumière basse et chaude. Les références de Clément (Megabonk, Octopath Traveler, Steal an Egg) donnent l'ambiance : silhouettes trapues, horde lisible, effet maquette, ton joyeux. On ne copie aucun de leurs visuels.

Planches de référence (dossier `assets/style/`) :

| Planche | Contenu |
| --- | --- |
| [01-palette-grain.png](../../assets/style/01-palette-grain.png) | Palette COHUE 16 avec ses tons, échelle avatar / gobelins, hiérarchie de saturation |
| [02-silhouettes-familles.png](../../assets/style/02-silhouettes-familles.png) | Gobelins livrés, zombies et fantômes en ébauche, silhouettes à 64 px, code couleur des rôles |
| [03-diorama-lumiere.png](../../assets/style/03-diorama-lumiere.png) | Cible d'ambiance (Blender), avant / après du décor en jeu (Studio), recette de lumière |
| [04-equipement-paliers.png](../../assets/style/04-equipement-paliers.png) | Knight, Archer, Mage aux niveaux 10, 20, 30, de face et de dos |

Captures en jeu : `assets/style/captures/` (place de test `COHUE-A01`, lumière Studio par défaut).

## 1. Les 10 règles

1. **Un seul grain par modèle.** Personnages, créatures, équipement, armes et petits props : 0,25 stud. Grands props et boss : 0,5 stud. Tuiles de terrain : 1 stud.
2. **Rien de lisse.** Pas de sphère, de cylindre ni de mesh généré laissé tel quel : tout est voxelisé.
3. **Seulement la palette COHUE 16**, avec 4 tons par couleur : `.l` (clair), base, `.d` (ombre), `.dd` (ombre profonde). Aucune autre couleur.
4. **Aucune texture.** La couleur est stockée par sommet. On garde `MeshPart.Color` blanc pour la couleur exacte, toute autre valeur la teinte (gel, dégâts…).
5. **Le décor est plus calme que les personnages.** Le décor utilise les tons `.d` et `.dd`. Les tons de base vifs et les tons `.l` sont réservés aux personnages et aux objets à ramasser.
6. **La famille se lit à la silhouette, le rôle à la couleur.** Le dessus de la tête porte la couleur du rôle, car la caméra est haute et voit surtout le dessus des ennemis.
7. **Les yeux sont les pixels les plus clairs** d'un ennemi (Cream), avec des pupilles Ink.
8. **Pas de Neon sur les ennemis ordinaires.** Le Neon est réservé à la capture, aux élites, aux annonces de boss et aux effets du joueur. Avec 100 ennemis, le bloom deviendrait une bouillie.
9. **Chaque élément a un gag** : cocotte en casque, carotte dans le carquois, canard couronné sur la cape…
10. **Vérifié en jeu** : capture Studio à 20 studs au milieu de la horde, silhouette noire reconnaissable à 64 px.

## 2. Le grain voxel

| Classe d'objet | Grain | Pourquoi |
| --- | --- | --- |
| Personnages, créatures, équipement, armes, petits props (< 5 studs) | **0,25 stud** (4 voxels par stud) | Une tête de gobelin fait 8 voxels de large : yeux 2 × 2 lisibles |
| Grands props (arbres, rochers), mini-boss, boss | 0,5 stud (×2) | Garde les budgets bas sur les grandes surfaces |
| Tuiles de terrain, falaises | 1 stud (×4) | Les tuiles s'emboîtent sur la grille des studs |

Les trois grains sont des multiples entiers, donc ils restent cohérents côte à côte. Pour un arbre au grain 0,5, on modélise au grain 0,25 puis on agrandit ×2.

**Pas de clous (studs) en surface.** Le look diorama vient de la lumière et des ombres, pas d'une texture de brique. C'est aussi zéro mémoire de texture sur téléphone.

**Ombrage cuit, sans casser la fusion des faces** : chaque face reçoit un ton selon sa direction, le même sur toute la face.

| Face | Ton cuit |
| --- | --- |
| Dessus | 12 % vers la lumière chaude `#FFF4D8` |
| Dessous | 40 % vers l'ombre violette `#2A1C3D` |
| Dos (+Y Blender) | 8 % d'ombre |
| Côté droit du modèle | 4 % d'ombre |

Les tons de matière se posent à la main : une rangée `.d` au pied, une bande `.l` en haut d'un chapeau. Les lignes sombres ne vont qu'aux jointures entre deux matières (ceinture, bord de capuche), jamais sur chaque marche.

## 3. Palette COHUE 16

Les tons dérivés se calculent : `.l` = base mélangée à 35 % avec `#FFF4D8` ; `.d` = 35 % avec `#2A1C3D` ; `.dd` = 60 % avec `#2A1C3D`. Le code est dans `assets/voxel/cohue_voxel.py` (`PALETTE`, `tone()`).

| Nom | Hex | Usage | Réserve |
| --- | --- | --- | --- |
| Ink | `#1C1726` | Contours, pupilles, coutures, bombe | |
| Plum | `#4B3866` | Ombres froides, tissu sombre, cape du Mage | |
| Bark | `#6E4227` | Bois sombre, chaussures, bordures | |
| Leather | `#B5713A` | Cuir, bois clair, cordes | |
| Cream | `#FFE8B8` | Blanc des yeux, dents, émail, fantômes | |
| Stone | `#9C9488` | Pierre, os, gris neutre chaud | |
| Steel | `#8EA6C2` | Métal, armure du Knight | |
| Gold | `#FFC21A` | Rivets, liserés, couronne d'élite, pièces | Accents seulement : 5 % au plus d'une pièce |
| Ember | `#FF7A1A` | Rôle kamikaze, feu, orbe du Mage | |
| Tomato | `#E63946` | Rôle mêlée, danger, tirs ennemis | |
| **Bubblegum** | `#FF5FB0` | **Capture** (anneau, cage, interface de capture) | **Réservé à la capture, nulle part ailleurs** |
| Grape | `#8C52E0` | Rôle soutien, magie, Mage | |
| Royal | `#2D6BE6` | Knight | |
| Sky | `#3FD0F5` | XP, magie froide | Sur un ennemi, seulement en `.d` / `.dd` (peau des zombies) ou comme XP volée (Bomber) |
| Leaf | `#3DBE4A` | Archer ; décor en `.d` / `.dd` | |
| Lime | `#8FD13F` | Peau des gobelins | Réservé aux gobelins. `#A6E03A` virait au jaune pur sous le soleil de Roblox (relecture du 4 nov.) |

**Hiérarchie de saturation**, du plus vif au plus calme :

1. Les objets à ramasser (XP cyan, pièces or) sont les plus vifs et brillent en Neon (LootRenderer).
2. Le joueur et la capture : couleur de classe et rose Bubblegum.
3. Les ennemis : peau de famille et couleur de rôle, en tons de base.
4. Le décor : uniquement des tons `.d` et `.dd` sur les grandes surfaces (herbe Leaf.d / Leaf.dd, chemin Leather.d, pierre Stone.d).

La planche 3 montre la règle en jeu. Sur un sol au ton de base, la horde se fond dans l'herbe ; sur un sol en `.dd`, elle ressort.

## 4. Proportions

Repère : l'avatar R15 par défaut mesure **5,46 studs** (tête 1,16 × 1,18 × 1,16, torse 1,94 × 1,70 × 1,00), mesuré dans Studio.

| Élément | Hauteur | Règle |
| --- | --- | --- |
| Avatar du joueur | 5,5 studs | Jamais modifié ; seuls les accessoires s'ajoutent |
| Ennemi d'essaim (gobelin, zombie, fantôme) | 3,5 à 4,25 studs dessinés | Environ 65 % de l'avatar ; tête = 40 à 45 % de la hauteur ; largeur ≥ 3 studs avec les oreilles ou les bras |
| Élite | même maille ×1,25 | Couronne et anneau or en Neon (déjà dans EnemyRenderer) |
| Ennemi moyen (bloater, armure hantée) | 4 à 5 studs | |
| Mini-boss | 8 à 10 studs | Grain 0,5 |
| Boss | 16 à 20 studs | Grain 0,5, plusieurs mailles sous 10 000 triangles |
| Pièce d'équipement | ≈ 1,4 × la partie du corps couverte | Un casque fait 2 studs de large pour une tête de 1,16 |
| Arme tenue | 3 à 4 studs de long | Lame ou manche épais d'au moins 2 voxels |

**Taille en jeu.** `EnemyRenderer` redimensionne la maille à `height × 1,3` (ART_SCALE). Pour garder des voxels de 0,25 stud, les hauteurs de `Config/Enemies` doivent valoir hauteur de la maille ÷ 1,3. Pour les gobelins : Grunt 2,9 · Archer 2,7 · Shaman 3,25 · Bomber 2,7 (voir Contract requests).

## 5. Lisibilité dans la horde, sur téléphone

Calcul de référence : écran paysage de 1080 px de haut, FieldOfView vertical de 70°. À 30 studs, on voit 42 studs de haut, soit environ 26 px par stud : un gobelin de 3,5 studs fait 90 px. À 60 studs, il fait 45 px et un voxel ne fait plus que 3 px. Un détail qui compte doit donc faire **au moins 2 × 2 voxels** (0,5 stud).

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
- Chaque ennemi a au plus 4 couleurs principales, plus Ink et Cream.
- Les tirs ennemis sont Tomato, lents, sans Neon. Ceux du joueur sont aux couleurs de la classe et brillent. On distingue un tir ennemi d'un tir ami d'un coup d'œil.
- **Capturable** : anneau carré au sol et cage flottante au-dessus de la tête, tous deux en Neon Bubblegum. Aucun autre objet du jeu n'est rose, donc on le repère au milieu de 100 ennemis (captures Studio).
- **Élite** : anneau et couronne or en Neon (existant).
- Le joueur se repère à son équipement de classe. Une pastille au sol sous le joueur est recommandée à l'agent UI ou VFX.

## 6. Silhouettes par famille

| Famille | Monde | Peau | Silhouette | Ton | Statut |
| --- | --- | --- | --- | --- | --- |
| Gobelins | 1 · Bois Grognon | Lime | T : grosses oreilles horizontales, petites jambes, grosse tête | Bricoleurs ridicules (cocotte, louche, bonnet d'aviateur) | **Livrés** (A01-04) |
| Zombies | 2 · cimetière / marais | Sky.d (bleu-vert mat) | Γ : bras tendus, tête basse en avant ; haillons Plum | Maladroits (zombie en tutu Grape.l, pas en rose) | Ébauches (A01-08) |
| Fantômes | 3 · Récré Fantôme | Cream | Dôme + bas ondulé, flottent ; objets d'école | Surveillants de cantine | Ébauches (A01-08) |

## 7. Équipement des classes

L'avatar reste intact : la classe ajoute des **Accessories** voxel sur les attaches R15 standard. Les pièces se **cumulent** : niveau 10 = tête, niveau 20 = épaules ou bras, niveau 30 = grande pièce de dos, celle que voit la caméra placée derrière le joueur. Avant le niveau 10, l'arme de départ suffit à reconnaître la classe. Les pièces de tête laissent le visage visible.

| Classe | Couleurs | Niveau 10 (tête) | Niveau 20 | Niveau 30 (dos) |
| --- | --- | --- | --- | --- |
| Knight | Steel + Royal, rivets Gold | Bassinet ouvert, plumet ridiculement court · `HatAttachment` | Épaulières bleu roi (elles se détachent du casque en acier), la même maille pour les deux (demi-tour à gauche) · `RightShoulderAttachment` + `LeftShoulderAttachment` | Cape bleu roi au canard couronné · `BodyBackAttachment` |
| Archer | Leaf + Leather | Capuche à pointe, broche en gland · `HatAttachment` | Brassard en cuir, cible rouge et crème sur le dos de l'avant-bras (visible de la caméra) · `LeftGripAttachment` (tourné de −90° sur X) | Carquois droit, une flèche est une carotte de 4 voxels · `BodyBackAttachment` |
| Mage | Grape + Plum, étoiles Gold | Chapeau pointu à grelot · `HatAttachment` | Orbe de feu dans une cage, 1 stud au-dessus et 1,25 stud à l'extérieur de l'épaule gauche (hors du bord du chapeau), cœur en cube Neon Ember · `LeftShoulderAttachment` | Cape étoilée à haut col, arrêtée au genou (les jambes ne la traversent pas) · `BodyBackAttachment` |

Couleurs réservées pour les 5 autres classes (A01-07) : Guardian Stone + Ember · Rogue Plum + Ink + Tomato · Cleric Cream + Gold + Sky · Barbarian Bark + Tomato + fourrure Cream · Tamer Leather + Leaf + Ember.

**Échelle de l'avatar.** Chaque accessoire porte la taille de la partie du corps de référence (attribut `RefPartSize`). `ArtLibrary.equipAccessory(character, name)` met la pièce à l'échelle de l'avatar réel (Rthro, corps fins…) avant `Humanoid:AddAccessory`.

**Chapeaux et cheveux du joueur.** Ils traversent les pièces de tête. Je recommande de masquer les accessoires `Hat` et `Hair` de l'avatar pendant la run, avec le réglage `keepHat` déjà prévu (Contract request).

## 8. Budgets

Mesurés sur les livrables : maillage glouton, une seule maille, aucune texture.

| Classe | Triangles visés / plafond | Mesuré (mailles étanches) |
| --- | --- | --- |
| Ennemi d'essaim | 800 / 1 000 | Grunt 656 · Archer 684 · Shaman 716 · Bomber 792 |
| Ennemi moyen | 1 200 / 2 000 | — |
| Mini-boss | 3 000 / 6 000 | — |
| Boss | 8 000 / 15 000 (mailles < 10 000) | — |
| Pièce d'équipement | 300 / 800 (limite Roblox des accessoires : 4 000) | 80 à 348 |
| Arme | 300 / 800 | 94 à 232 |
| Marqueur de capture (anneau + cage) | 300 / 500 | 158 + 130 |
| Petit prop | 300 / 600 | — |
| Arbre | 600 / 1 500 | — |
| Tuile de terrain | 1 500 / 4 000 | — |

Textures : **0 octet** (couleurs par sommet). Une horde de 300 gobelins à 700 triangles en moyenne fait environ 210 000 triangles, sur 4 mailles partagées. Le plafond d'ennemis réel reste à mesurer par A13.

## 8 bis. Armes de départ (A01-05)

Planche : [05-armes-depart.png](../../assets/style/05-armes-depart.png). L'origine est le centre de la prise, et l'arme pointe vers +Y dans Roblox. L'attribut `GripOffset` donne la prise depuis le centre de la maille.

| Arme | Classe | Gag |
| --- | --- | --- |
| Broadsword | Knight | Pommeau en canard (rappel de la cape) |
| Longbow | Archer | Une feuille pousse au bout de la branche |
| Fire Staff | Mage | Une guimauve grille sous la flamme ; cristal doublé d'un cube Neon |
| Quake Hammer | Guardian | Pansement en croix sur la tête du marteau |
| Throwing Daggers | Rogue | Ruban rouge noué au pommeau (projectile) |
| Holy Aura | Cleric | Clochette de cantine en porcelaine qui « sonne » l'aura |
| Spinning Axes | Barbarian | Smiley gravé sur le fer |
| Beast Whip | Tamer | Fouet enroulé à pompon de cirque (les anneaux carrés sont à revoir s'ils gênent) |

## 9. Lumière diorama (proposition pour A02-05)

Lumière basse et chaude, ombres violettes, flou de profondeur doux (effet maquette), bloom seulement sur le Neon. Valeurs de départ, à régler monde par monde :

| Réglage | Valeur |
| --- | --- |
| `Lighting.ClockTime` / `GeographicLatitude` | 15,6 / 35 |
| `Brightness` | 2,6 |
| `Ambient` / `OutdoorAmbient` | `#60526F` / `#9680A0` |
| `ColorShift_Top` | `#FFD6A0` |
| `EnvironmentDiffuseScale` / `SpecularScale` | 0,5 / 0,2 |
| `Atmosphere` | Density 0,32 · Offset 0,15 · Color `#FFE4C4` · Decay `#96A0E6` · Glare 0,2 · Haze 1,4 |
| `ColorCorrectionEffect` | Saturation +0,12 · Contrast +0,06 · Tint `#FFF6E8` |
| `BloomEffect` | Intensity 0,6 · Size 24 · Threshold 0,9 |
| `DepthOfFieldEffect` | FarIntensity 0,35 · FocusDistance ≈ distance caméra-joueur (30) · InFocusRadius 24 · NearIntensity 0,4 |

La place de test contient un `ColorGradingEffect` réglé sur le tonemapper `Retro`. Il désature la palette : à retirer ou à tester par A02. Les captures MCP de Studio n'affichent pas les effets de post-traitement : la lumière se valide en Play sur téléphone.

**Signature diorama des mondes** (pour A02) : les tuiles flottent et montrent leur coupe de terrain (herbe, terre Bark, Leather.d, roche Stone.d) au bord de l'arène.

## 10. Anti-AI-slop, appliqué au modeling

- Aucune sortie Meshy, Cube ou générateur n'est livrée telle quelle. Toute forme organique est revoxelisée et repeinte avec la palette. Crédits Meshy dépensés pour ce lot : 0.
- Pas de motif bruité : le damier du chapeau du Shaman et le mouchetis de l'herbe ont été retirés. On préfère de grandes bandes ou des plaques.
- Silhouettes testées en noir à 64 px. Couleurs vérifiées en jeu sur un sol au ton du monde.
- Chaque modèle a son gag, listé dans `assets/voxel/manifest.json` (champ `gag` pour les ennemis).

## 10 bis. Relecture quality-score

Trois relecteurs à l'aveugle ont noté les lots le 4 nov. avec la grille modèle du skill, adaptée au voxel (critère V4 = grain unique et arêtes nettes).

| Lot | Relecteur 1 | Relecteur 2 | Relecteur 3 | Médiane |
| --- | --- | --- | --- | --- |
| Gobelins | 7,0 | 7,0 | 7,7 | **7,0** |
| Équipement | 7,0 | 8,0 | 6,7 | **7,0** |

Corrections appliquées (tour 1) :

- **Silhouettes** : Grunt et Bomber faisaient la même tache à 64 px. La louche du Grunt est maintenant brandie hors de la silhouette, et la bombe du Bomber est portée sur le côté.
- **Peau des gobelins** : Lime moins jaune (`#8FD13F`), et la cocotte remontée d'un voxel pour dégager les yeux.
- **Intersections de l'équipement** : l'orbe est écartée du chapeau, la queue de capuche raccourcie (elle traversait le carquois), la cape du Mage arrêtée au genou.
- **Lecture de l'équipement** :
  - le brassard est d'une seule couleur, avec la cible au dos ;
  - le carquois est droit, avec une carotte de 4 voxels ;
  - les épaulières sont bleu roi et posées sur l'épaule ;
  - la capuche a une vraie pointe.

Un relecteur voyait le casque du Knight tourné d'un quart de tour. La vue de profil dans Studio le contredit : rivets sur le côté, nasal vers −Z, crête d'avant en arrière. Rien n'a été changé sur ce point.

**Tour 2 (nouvelle note par 3 relecteurs) : pas encore fait.** Il faut d'abord refaire les captures Studio de la horde et des gobelins à 20 studs avec les modèles corrigés. Les captures `studio_horde_*` et `studio_gobelins_*` montrent encore l'ancienne version.

## 11. Créatures existantes (`assets/creatures/`)

Les 15 mailles existantes ont été générées par IA. Elles sont lisses, avec des textures peintes et des dégradés : elles **ne passent pas ce guide** (règles 1, 2 et 4). La capture `assets/style/captures/studio_grunt_vs_anciennes-creatures.jpg` montre l'écart avec un gobelin voxel. Proposition :

| Modèle | Décision |
| --- | --- |
| Grand Chêne Ronchon (boss monde 1) | À refaire en voxel au grain 0,5 (A01-09) en gardant l'idée : souche grognon à sourcils de mousse |
| Gland Grincheux, Champignon Sauteur, Hibou Plongeur (faune monde 1) | À refaire en voxel (faune d'essaim, peau de famille « forêt » à définir sans Lime ni Bubblegum) |
| Souche Géante | Doublon possible du mini-boss : à trancher avec A03 |
| Bogue Blindée | Hors liste v2 : retirée |
| Braise, Marée, Ronce (anciens compagnons) | Sortent du jeu (décision v2) |

Les mailles actuelles restent en place tant que les remplaçantes ne sont pas livrées : le jeu continue de tourner.

## 12. Pipeline Blender → Roblox (A01-02)

Le source de chaque modèle est du code Python (`assets/voxel/models.py`). Cela rend les modèles relisibles, versionnés, réglables et reproductibles.

```
models.py (voxels) → cohue_voxel.py (maillage glouton, tons) → Blender 5.2 en ligne de commande (build.py)
  → assets/voxel/glb/*.glb + manifest.json → Studio : Import 3D → MeshPart (ids Roblox)
  → ReplicatedStorage.Assets → ArtLibrary
```

### 12.1 Construire et exporter

```bash
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python assets/voxel/build.py -- export
```

- **Échelle** : 1 unité Blender = 1 stud, un voxel = 0,25. Z en haut dans Blender, le modèle regarde vers −Y. L'export glTF +Y up suivi de l'import Roblox donne : avant −Z, main droite en +X, soit la conversion (x, y, z) → (−x, z, y).
- **Triangles** : maillage glouton, une face par rectangle de même couleur. Les sommets sont séparés par direction de face, d'où un ombrage parfaitement plat.
- **Mode étanche** : la fusion crée des jonctions en T, sources de fentes topologiques et de pixels qui scintillent. Les coins voisins sont donc insérés dans les arêtes longues. Chaque face est triangulée en éventail depuis un coin libre, sinon depuis un point seul sur son arête, sinon depuis son centre. Résultat : 0 arête de bord, 0 triangle plat, pour environ +35 % de triangles. Il reste quelques arêtes non-manifold, là où deux voxels ne se touchent que par une arête (marches en diagonale) : c'est normal en voxel et sans effet sur le rendu.
- **UV et couleurs** : couleur par coin de face (`BYTE_COLOR`, sRGB), un jeu d'UV neutre (Roblox en attend un), un seul matériau `COHUE_Voxel`.
- **Export** : GLB, `export_apply`, normales, `export_vertex_color = ACTIVE`, une maille par fichier. `manifest.json` donne pour chaque modèle : triangles, taille en studs (axes Roblox), décalage de l'attache depuis le centre de la maille, rotation d'attache, couleurs.
- **Toujours exporter en ligne de commande.** Forcer le contexte d'une autre scène dans un Blender ouvert l'a fait planter pendant ce lot.
- **Aperçu sans téléversement** : `assets/voxel/luau/*.json` (même maille, axes Roblox), chargé dans Studio par EditableMesh (module `A01_VoxelPreview` de la place COHUE-A01). Un MeshPart créé par EditableMesh garde l'origine des sommets comme centre ; l'aperçu recentre donc la maille sur sa boîte, comme le fait Import 3D.

### 12.2 Importer dans Studio

`AssetService:CreateAssetAsync` n'est pas encore ouvert (« not available yet », testé le 4 nov.) : le téléversement passe par **Import 3D**.

1. Accueil → Import 3D → sélectionner tous les `assets/voxel/glb/*.glb` (import groupé).
2. Réglages : Scale Unit = **Studs** · Upload to Roblox = **activé** (import final seulement) · Creator = le propriétaire de l'expérience · Merge Meshes désactivé · Use Imported Pivot activé · Ignore Vertex Colors **désactivé**.
3. Lire le panneau d'avertissements, puis importer.
4. Lancer `assets/install/A01_finalize.luau` (généré par `python assets/install/make_finalize.py` depuis le manifeste). Le script :
   - range les MeshParts dans `ReplicatedStorage.Assets` (Creatures, Equipment, Weapons, FX) et règle leurs propriétés : Color blanc, collisions coupées, pas d'ombre, `PivotOffset` nul ;
   - construit les 10 Accessories : Handle, attache R15 avec sa rotation, attributs `RefPartName` et `RefPartSize`, cœur Neon soudé pour l'orbe ;
   - affiche la liste `nom;MeshId;taille`.
5. Reporter cette liste dans `assets/creatures.csv` et `assets/equipment.csv`, puis écrire les `.model.json`.

**Test à blanc fait le 4 nov.** Des maillages d'aperçu portant les 23 noms ont remplacé les imports. La finalisation a produit 10 Accessories, 8 armes et 2 effets. `ArtLibrary.equipClassTier` a posé 4, 3 et 3 pièces, placées par `AddAccessory` exactement comme prévu, y compris sur un avatar agrandi 1,3 fois (capture `studio_equipClassTier_dos.jpg`). Il reste à faire le vrai Import 3D pour obtenir les ids : voir section 13.

## 13. Livrables et ids Roblox

Voir `assets/equipment.csv`, `assets/creatures.csv` et `assets/voxel/manifest.json`. Les ids sont remplis après l'import groupé dans Studio.

## Notes du vault utilisées

`Voxel Art - Studs Outlines and Style Kits` · `Meshing Voxels for Roblox - Greedy Meshing and Export` · `Trim Sheets Atlases and Vertex Colors` (les couleurs par sommet se multiplient avec `Color`) · skills `fwjelaa-blender-modeling` (budgets, règle d'export GLB) et `fwjelaa-asset-import` (réglages de l'Import 3D) · `Engine and API Changes 2025-2026` (CreateAssetAsync).
