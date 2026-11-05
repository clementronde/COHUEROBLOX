# 21 — Tuiles et assemblage semi-procédural (A02-01, A02-08)

Domaine **run**, partie mondes. Agent A02 (code : Cantin ; tuiles, props, lumière, gabarits de portail : Clément).
Sources : `01-decisions-v2.md` §2, §6 et §12 ; `20-run-mondes-boss.md` §1, §3 et §5 ; `80-direction-artistique.md` §3 bis et « Signature des mondes ».
Code : `shared/Config/Tiles.luau` (réglages), `shared/TileLayout.luau` (lecture des tuiles, sol de la horde), `server/Services/WorldBuilder.luau` (tirage et pose), `server/Services/WorldPortals.luau` (portails, transition), `client/Controllers/WorldTransition.luau` (fondu).

## 1. Principe

Chaque monde est une **grille de tuiles faites main** (gros blocs à tenons, posés dans Studio par Clément). À chaque monde de la run, le serveur tire une nouvelle disposition avec une graine : il choisit une tuile et une rotation par case, en respectant les connecteurs des bords. Deux cases ne bougent jamais d'une run à l'autre :

- la **tuile d'apparition** (`Spawn`), toujours au centre de la carte ;
- la **tuile d'arène** (`Arena`, 2 × 2 cases), toujours la même pour un boss donné. Sa place change seulement entre les 4 coins de la carte, tirés par la graine (au moins 180 studs du centre, `20-run-mondes-boss.md` §3).

Le code **clone et place** les tuiles. Il ne fabrique aucun objet visible (règle `01-decisions-v2.md` §12).

## 2. Format d'une tuile

| Règle | Valeur |
| --- | --- |
| Taille d'une case | **80 × 80 studs** (`Tiles.CellSize`). Une tuile normale couvre 1 case ; l'arène couvre 2 × 2 cases (160 × 160) |
| Grille | **7 × 7 cases** par monde (`Tiles.Worlds[id].grid`), soit une carte de 560 × 560, plus un anneau de bordure tout autour |
| Pivot | Le pivot du modèle (`Model.WorldPivot`) est **au centre de l'emprise, à la hauteur du sol (Y = 0)**, sans rotation. Le sol plat d'une tuile a son dessus à Y = 0 |
| Rotation | Le code tourne les tuiles par quarts de tour (0°, 90°, 180°, 270°). Une tuile qui ne doit pas tourner porte `Rotate = false` |
| Où les ranger | `ReplicatedStorage.Assets.Worlds.<WorldId>` (un dossier par monde : `BoisGrognon`, `DunesCroustillantes`, `RecreFantome`). Les clients doivent les lire pour reconstruire le sol de la horde, d'où `ReplicatedStorage` et pas `ServerStorage` |
| Nom | Unique dans le dossier du monde, sans `|`, `;` ni `,` (exemple : `F_Clairiere01`) |

### 2.1 Contenu d'un modèle de tuile

```
F_Clairiere01            (Model, attributs ci-dessous)
├── Ground               (Folder) les surfaces où l'on marche : dalles, terrasses, plateaux, rampes
├── Decor                (Folder, nom libre) arbres, rochers, props : ignorés par le sol de la horde
└── Markers              (Folder) petits Parts invisibles qui marquent des points (section 2.3)
```

- **`Ground`** : des Parts (blocs) et des WedgePart (rampes), visibles et à tenons comme le reste. Le code lit leur emprise et leur dessus pour calculer la hauteur du sol (section 4). Un bloc de `Ground` qui ne doit pas compter porte `Ground = false`.
- **Tout le reste** (décor) n'entre pas dans le sol de la horde : les ennemis passent à travers les troncs. Les cimes restent `CanCollide = false` au-dessus de 3 studs (`20-run-mondes-boss.md` §3).
- **`Markers`** : le serveur les supprime du clone ; ils ne sont jamais visibles en jeu. Mettre `Transparency = 1`, `CanCollide`, `CanQuery` et `CanTouch` à `false`.

### 2.2 Attributs posés par Clément sur chaque tuile

| Attribut | Type | Valeurs | Défaut |
| --- | --- | --- | --- |
| `Kind` | string | `Field` (tuile de jeu), `Spawn`, `Arena`, `Border`, `BorderCorner`. Un modèle sans `Kind` n'est pas une tuile (le code l'ignore) | obligatoire |
| `EdgeN`, `EdgeE`, `EdgeS`, `EdgeW` | string | Connecteur de chaque bord (section 3). Pour l'arène (2 cases par bord) : deux valeurs séparées par une virgule, dans le sens des aiguilles d'une montre vu du dessus (N : d'ouest en est ; E : du nord au sud ; S : d'est en ouest ; W : du sud au nord) | `Open` |
| `Weight` | number | Chance relative d'être tirée | 1 |
| `MaxCount` | number | Nombre maximal d'exemplaires sur une carte | illimité |
| `Rotate` | boolean | Autoriser les quarts de tour | `true` |
| `Boss` | string | Arène seulement : id du boss (`GrandCheneRonchon`…). Sans arène pour ce boss, le code prend n'importe quelle arène du monde | — |
| `Radius` | number | Arène seulement : rayon de l'arène en studs | `Run.ArenaRadius` (60) |

Orientation : **N = −Z**, E = +X, S = +Z, W = −X, la tuile vue dans Studio sans rotation.

### 2.3 Marqueurs (Parts dans `Markers`, le nom du Part donne le type)

| Nom | Où | Rôle |
| --- | --- | --- |
| `Player` | `Spawn` (4) | Points d'apparition des joueurs |
| `Chest`, `Pot`, `Shrine`, `Merchant` | `Field` | Candidats pour le butin. Le code en garde au plus 18 / 40 / 8 / 2 sur la carte, espacés de 22 / 10 / 50 / 40 studs (`Tiles.SpawnPoints`). En mettre plus que nécessaire : 2 à 4 coffres et 3 à 6 pots par tuile, un autel toutes les 2 tuiles, en hauteur et dans les recoins (A02-03) |
| `Arche` | `Arena` (1) | Centre de l'arène : l'Arche du boss, le point qui révèle le boss |
| `Portal` | `Arena` (1) | Où s'ouvre le portail après le boss (sinon : 26 studs au sud de l'Arche, `Run.PortalOffset`) |
| `WeakPoint` | `Arena` | Faiblesse de terrain du boss (sommet des branches-rampes du Grand Chêne, cloche, gongs) : poser le Part **sur** la plateforme |
| `Pillar` | `Arena` | Pilier de ruine qui arrête la charge (Pharaon) : rayon = moitié de `Size.X`, hauteur = `Size.Y` |
| `JumpPad` | partout | Tremplin : le Part regarde (`LookVector`) vers où il propulse ; attribut `Height` = hauteur du plateau à atteindre. Le tremplin visible est un prop de `Decor` |
| `Lamp` | partout | Lampadaire qui éclaire pendant la coupure de courant (Récré Fantôme). Le lampadaire visible est un prop de `Decor` |

## 3. Connecteurs et règles de voisinage

Chaque bord de case a un connecteur. Deux cases voisines doivent avoir des connecteurs compatibles (`Tiles.Compat`) :

| | `Open` | `Path` | `Wall` |
| --- | --- | --- | --- |
| **`Open`** (herbe ou sol plat à Y = 0 sur tout le bord) | oui | oui | oui |
| **`Path`** (chemin de terre centré sur le bord, 16 studs de large) | oui | oui | non |
| **`Wall`** (falaise, eau, bord infranchissable) | oui | non | oui |

- **Passage** : on traverse un bord si aucun des deux côtés n'est `Wall`.
- **Bord de carte** : tout connecteur est accepté ; la bordure ferme la carte.
- **Connexité** : après le tirage, un parcours part de la tuile d'apparition. L'arène doit être atteignable et au moins **85 %** des cases aussi (`Tiles.MinReachable`). Sinon le code recommence avec la suite de la graine, jusqu'à 40 essais (`Tiles.MaxAttempts`).
- **Hauteur au bord** : au droit d'un bord `Open` ou `Path`, le sol est à Y = 0 sur les 4 derniers studs, pour que deux tuiles se raccordent sans marche. Les plateaux restent à l'intérieur d'une case.
- **Pas de passage dessous** : le sol de la horde prend la surface la plus haute. Un pont ou une arche praticable par-dessous n'est pas compris : les ennemis marcheraient dessus.

**Bordure** : un anneau de tuiles `Border` (forêt de sapins, falaises en blocs) entoure la grille, avec une `BorderCorner` à chaque coin. Convention : le bord **N** d'une `Border` regarde la carte ; les bords **N et E** d'une `BorderCorner` regardent la carte. La bordure ne compte pas dans le sol de la horde (la horde reste dans les 560 × 560).

## 4. Sol de la horde (Heightmap, A02-04)

Le serveur publie la disposition dans la clé de stage (`Workspace.CohueStageKey`) : `monde|stage|graine|boss|<disposition>`. La disposition liste chaque tuile posée : `7;3,3,0,Spawn01;5,5,1,ArenaChene;0,0,2,F_Clairiere01;…` (taille de grille, puis `i,j,rotation,nom` par tuile). Chaque client relit les mêmes modèles dans `ReplicatedStorage.Assets.Worlds` et reconstruit la même grille de hauteurs, sans dépendre des Parts streamées.

Pour chaque Part de `Ground` (position dans la tuile, puis rotation de la case) :
- **bloc** (Part, MeshPart, Union) → plateau : son emprise au sol (boîte englobante) et son dessus ;
- **WedgePart** → rampe : elle monte vers le +Z local de la pièce, du bas au haut de la pièce, sur sa longueur (Z) et sa largeur (X). Garder les rampes alignées sur les axes de la tuile.

Le reste ne change pas : cellules de 2 studs, interpolation bilinéaire, aucune requête physique par ennemi (`shared/Heightmap.luau`).

## 5. Tirage (graine par run)

La graine est tirée par `RunManager` à chaque monde (`math.random(1, 2^30)`), donc chaque monde de chaque run a sa carte. Un `Random` par usage, d'après « Procedural World Generation » :

| Usage | Graine |
| --- | --- |
| Coin de l'arène | `graine + 11` |
| Tuiles et rotations | `graine + 12` (puis `+ 100 × essai`) |
| Points de butin | `graine + 13` |

Ordre de pose : apparition au centre, arène dans un coin, puis les autres cases ligne par ligne. Pour chaque case, le code liste les couples (tuile, rotation) compatibles avec les voisins déjà posés et sous leur `MaxCount`, et en tire un au poids. Une case sans candidat fait recommencer l'essai. Si les 40 essais échouent, ou si le monde n'a pas encore de tuiles, `StageService` reconstruit l'ancienne carte en Parts (`Tiles.LegacyFallback = true`) et le signale dans la sortie. Le chef de projet met `LegacyFallback = false` une fois les tuiles posées : le code n'aura plus le droit de fabriquer le monde.

Budget : avertissement au-delà de **6 000 Parts** posées par monde (`Tiles.PartBudget`, vault « Art Budgets » : 3k-10k instances pour une zone habillée, on vise le bas de la fourchette pour le mobile).

## 6. Jeu de tuiles de test minimal (à poser par le chef de projet)

Dans `ReplicatedStorage.Assets.Worlds.BoisGrognon`, avec des Parts unies en attendant les vraies tuiles de Clément. Toutes ont un pivot au centre, à Y = 0, et une plaque de sol `Ground/Floor` de 80 × 1 × 80 (dessus à Y = 0, centre à Y = −0,5).

| Nom | `Kind` | Bords N, E, S, W | Autres attributs | Contenu |
| --- | --- | --- | --- | --- |
| `T_Spawn` | `Spawn` | Open, Open, Open, Open | `Rotate = false` | Sol ; `Markers` : 4 `Player` à 6 studs du centre (en croix) |
| `T_Arena` | `Arena` | `Open,Open` sur les 4 bords | `Rotate = false`, `Boss = GrandCheneRonchon` | Sol 160 × 1 × 160 ; `Markers` : `Arche` au centre, `Portal` à 26 studs au sud ; 4 plateformes 8 × 8 × 8 à 17 studs en diagonale du centre dans `Ground`, chacune avec une WedgePart 6 × 8 × 18 qui monte vers elle, et un `WeakPoint` posé sur chaque plateforme |
| `T_Open` | `Field` | Open ×4 | `Weight = 3` | Sol ; `Markers` : 3 `Chest`, 6 `Pot` dispersés |
| `T_Plateau` | `Field` | Open ×4 | `Weight = 2` | Sol ; plateau 30 × 10 × 30 au centre (`Ground/Top`), WedgePart 12 × 10 × 22 contre son bord ouest qui monte vers l'est (face haute contre le plateau) ; `Markers` : `Shrine` sur le plateau, 2 `Chest` |
| `T_PathEW` | `Field` | Wall, Path, Wall, Path | `Weight = 1` | Sol ; bandes de falaise 80 × 12 × 8 au nord et au sud **dans `Decor`** (elles bloquent les joueurs mais pas la horde, test volontaire de la règle) ; `Markers` : 4 `Pot`, 1 `Merchant` |
| `T_Cliff` | `Field` | Open ×4 | `Weight = 1`, `MaxCount = 4` | Sol ; plateau 24 × 14 × 24 sans rampe ; `Markers` : `JumpPad` 5 studs à l'ouest, regardant l'est, `Height = 14` ; `Shrine` sur le plateau |
| `T_Border` | `Border` | — | | Rangée de blocs 80 × 30 × 20 (falaise) |
| `T_Corner` | `BorderCorner` | — | | Bloc 80 × 30 × 80 |

Ce jeu suffit à tester le tirage (rotations, chemins entre falaises), la connexité, la horde sur les plateaux et les rampes, le tremplin, la faiblesse du Grand Chêne et le portail.

## 7. Portails entre mondes (A02-08)

Flux déjà en place dans `RunManager` (A04-02, `20-run-mondes-boss.md` §1) : le boss tué ouvre le portail **NEXT WORLD** (ou **CASH OUT** après le dernier boss) ; tous les joueurs actifs dedans, ou 60 s, et on passe au monde suivant. A02-08 y ajoute :

1. **Gabarits** : le portail visible est un modèle de Clément, cloné par `WorldPortals`. Il n'est plus construit en Parts par `StageService` (sauf `LegacyFallback`).
2. **Position** : le marqueur `Portal` de l'arène, s'il existe ; sinon la règle actuelle (26 studs au sud de l'Arche).
3. **Transition** : quand l'équipe part, le serveur annonce une transition de **1,5 s** (`Tiles.TransitionSeconds`), rend les joueurs invulnérables, puis construit le monde suivant. Le client fait un fondu au noir avec le nom du monde suivant, puis rouvre l'image quand le nouveau monde est publié.

### 7.1 Gabarits de portail (Clément)

| Nom | Où | Contenu attendu |
| --- | --- | --- |
| `PortalNextWorld` | `ReplicatedStorage.Assets.Props` (ou `Assets.Worlds.<WorldId>` pour une version propre au monde, prioritaire) | Model, pivot au centre du disque au sol, regard (−Z) vers l'arène. Briques de 0,5 stud (DA §3), anneau en Neon. Optionnel : un `TextLabel` nommé `Title` (le code y écrit le nom du monde suivant, en anglais), des `ParticleEmitter` avec l'attribut `Burst` (nombre) : le code les fait éclater quand l'équipe part |
| `PortalCashOut` | idem | Même format, doré (Gold de la palette). `Title` reçoit « CASH OUT » |
| `WorldTransition` | `StarterGui` (ScreenGui, `ResetOnSpawn = false`, `Enabled = false`, `IgnoreGuiInset = true`, `DisplayOrder` haut) | Un `Frame` plein écran nommé `Fade` (fond sombre de la palette) et, dedans, un `TextLabel` nommé `Title` |

Le rayon d'entrée reste celui de `Run.PortalRadius` (8 studs) et `Run.CashOut.Radius` (10 studs) : le disque du gabarit doit faire environ ce diamètre.

### 7.2 Attributs publiés (protocole client)

| Attribut de `Workspace` | Valeur |
| --- | --- |
| `CohueTransition` | `""` hors transition ; `"NextWorld"` pendant le fondu |
| `CohueTransitionWorld` | id du monde suivant |
| `CohueTransitionEnd` | heure serveur (`GetServerTimeNow`) de fin prévue du fondu |

## 8. Ce que Clément fournit

1. Pour chaque monde : 1 tuile `Spawn`, 1 tuile `Arena` (avec la faiblesse de son boss), **12 tuiles `Field` au moins** (A02-02, avec des bords variés : il faut assez de `Path` et de `Wall` pour que les cartes diffèrent), 1 `Border` et 1 `BorderCorner`.
2. Les attributs de la section 2.2 et les marqueurs de la section 2.3 sur chaque tuile.
3. Les gabarits `PortalNextWorld`, `PortalCashOut` et l'écran `WorldTransition` (section 7.1).
4. La lumière diorama par monde (A02-05, plus tard).

## 9. Sources vault

- *Procedural World Generation* (un `Random.new(graine)` par usage, tuiles et connecteurs, vérification de connexité)
- *Instance Streaming* (le client reconstruit le sol sans attendre les Parts streamées)
- *Art Budgets - Triangles Draw Calls Memory* (budget d'instances par zone)
- *Combat Arena and Encounter Layout* (arène ouverte et lisible, rayon fixe)
