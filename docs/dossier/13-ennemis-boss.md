# 13 — Ennemis et boss : modèles et rendu (A03)

**Statut : porte 1 validée par Clément le 5 nov. 2026 (« Yes, approved », roster et 4 recommandations de la section 8). Étape 2 en cours : planche concept.**

Rédigé le 5 nov. 2026 par l'agent A03 (ennemis et boss). Sources :
- `01-decisions-v2.md`, sections 6, 7 et 12 ;
- `20-run-mondes-boss.md` ;
- `80-direction-artistique.md` (sections 5 à 7, 9 et 12) ;
- `12-armes-modeles-effets.md`, section 7 ;
- le code de `main` au commit `ea106b4` : `Config/Enemies`, `Bosses`, `Worlds`, `Run`, `EnemyCodec`, `EnemyRenderer`, `BossRenderer`, `EnemyAttackFX`, `EnemyMotion`, `EnemyRigMotion`, `EnemyService`, `RunManager`.

---

## 0. En bref

**Pourquoi Clément ne voit pas les bons ennemis.** `EnemyRenderer` cherche une maille nommée `Enemy_<nom de config>`. Or les noms de la config sont ceux de la v1 (`GlandGrincheux`, `Gobelin`, `Golem`…), alors que les gobelins d'A01 s'appellent `Enemy_GoblinGrunt`, `Enemy_GoblinArcher`, etc. Le nom ne correspond jamais, et le renderer retombe sur ses Parts fabriquées par script. `BossRenderer` fait de même avec `Boss_<id>`.

**Ce qui tourne en Play aujourd'hui.**
- `Run.WorldChain` vaut `BoisGrognon` trois fois, donc on ne voit que le monde 1.
- On y croise :
  - des glands, des champignons et des hiboux ;
  - des bogues ;
  - un « Gobelin » et un « Golem » en Parts, ajoutés par Codex le 4 nov. ;
  - la Souche géante ;
  - le Grand Chêne.
- Les 4 gobelins d'A01 n'apparaissent jamais.

**Le décalage avec la v2.** `Config/Enemies`, `Bosses` et `Worlds` contiennent encore les rosters v1 : le monde 2 y est un désert (momies, cactus, pharaon) et le monde 3 une école de craies et de cartables. Les décisions v2 demandent des **gobelins**, des **zombies** dans un cimetière-marais et des **fantômes**.

**Ce que propose ce dossier :**
- un roster v2 complet : **15 ennemis, 3 mini-boss et 3 boss** (section 3) ;
- pour chacun, sa silhouette, sa taille, son rôle, ses attaques et ce qui existe déjà ;
- ce qu'A14 m'a laissé (tirs ennemis et télégraphes des boss) et les objets qui manquent pour les faire (section 5) ;
- les questions pour Clément (section 8).

---

## 1. État des lieux

### 1.1 Modèles qui existent

| Modèle | Où | Style | Utilisé en jeu ? |
| --- | --- | --- | --- |
| `Enemy_GoblinGrunt`, `Archer`, `Shaman`, `Bomber` (A01) | COHUE, `Assets.Creatures` (MeshId dans `80-direction-artistique.md` §14) | voxel v1 lisse, couleurs par sommet, sans yeux ronds ni tenons | **Non** : aucun nom de config ne correspond |
| `Enemy_GlandGrincheux`, `ChampignonSauteur`, `HibouPlongeur`, `BogueBlindee`, `SoucheGeante`, `Boss_GrandCheneRonchon` | dépôt (`assets/creatures/*.model.json`, ids dans `creatures.csv`) ; présence dans COHUE à vérifier au créneau Studio | mailles générées par IA, lisses, texture peinte | Oui si elles sont dans la place, sinon des Parts. **Hors DA** (guide §12) |
| `Enemy_Gobelin`, `Zombie`, `SurveillantFantome`, `Golem` (Codex, 4 nov.) | dépôt (`assets/creatures/*.rbxm`) ; viennent d'une autre place (COHUE-Base-Studio) | mailles riggées (os), texturées | Le code les anime s'il les trouve (`EnemyRigMotion`). **Hors DA** |
| Modèles en Parts | `Config/Enemies[].model` et la table `MODELS` de `BossRenderer` | Parts lisses fabriquées par script | Oui. **Interdit** par la règle §12 |

### 1.2 Effets d'attaque qui existent (A14)

`Assets.FX.Enemies` est posé dans COHUE et cloné par `EnemyAttackFX` :

| Modèle | Sert à | Mode |
| --- | --- | --- |
| `Sweep` | coup au contact (style « sweep ») | contact |
| `Burst` | coup au contact (style « burst ») | contact |
| `Shot` | bouffée au départ d'un tir | shot |
| `Land` | anneau de poussière à l'atterrissage d'un sauteur | land |
| `Boss` | impact d'une attaque de boss | boss |

Ces effets sont mats et prennent la couleur du profil de l'ennemi (`EnemyMotion`).

**Ce qui reste fabriqué par script** (dans mes fichiers) :
- les **projectiles ennemis**, des boules Neon dans `EnemyRenderer` ;
- les **télégraphes des boss**, des disques et des boîtes Neon dans `BossRenderer` ;
- l'anneau et la couronne des **élites** ;
- le **pilier de l'Arche** révélée ;
- les **marqueurs de point faible** (cloche, gongs) ;
- les **imposteurs** de LOD lointain.

---

## 2. Rôles et familles

Le guide DA donne quatre rôles par famille, lisibles à la couleur du dessus de la tête (§6). Le code n'a que quatre comportements : Swarm, Jumper, Shooter et Armored. Deux rôles v2 n'ont donc **pas de comportement** : le soutien et le kamikaze (A14 l'avait déjà noté, dossier 12 §7.1).

| Rôle | Couleur | Comportement serveur | Existe ? |
| --- | --- | --- | --- |
| Mêlée / essaim | Tomato | `Swarm` : fonce droit sur le joueur | Oui |
| Sauteur | Tomato (il frappe au contact, comme la mêlée ; relecture du 5 nov.) | `Jumper` : prépare 0,4 s, bondit 0,8 s vers la position verrouillée | Oui |
| Tireur | Leaf.d / Leather | `Shooter` : reste à 26 studs, vise 0,6 s, tir lent toutes les 3,2 s | Oui |
| Blindé | Steel / Ember | `Armored` : lent, armure 30 à 40 %, pousse les autres | Oui |
| Soutien | Grape | **`Support`** (proposé) : toutes les 6 s, protège ou accélère ses voisins à moins de 12 studs ; anneau violet au sol | **Non** |
| Kamikaze | Ember + Ink | **`Kamikaze`** (proposé) : court vers le joueur ; à 6 studs, allume sa mèche (1 s, cercle rouge de rayon 5) puis explose et meurt | **Non** |

En attendant les deux nouveaux comportements, le Shaman et la Banshee peuvent tourner en `Shooter`, et le Bomber et le Bloater en `Jumper`. Le jeu marche, seul le comportement est provisoire. Les nouveaux comportements touchent `EnemyService` : c'est une contract request pour A04 (section 9).

---

## 3. Le roster v2

**Tailles** (guide DA §5) :
- avatar : 5,5 studs ;
- ennemi d'essaim : 3,5 à 4,25 studs dessinés ;
- ennemi moyen : 4 à 5 studs ;
- mini-boss : 8 à 10 studs ;
- boss : 16 à 20 studs.

La « taille » des tableaux est la hauteur dessinée. La hauteur de gameplay (`Config/Enemies.height`) vaut cette hauteur ÷ 1,3, car `EnemyRenderer` dessine les mailles 1,3 fois plus grandes (`ART_SCALE`).

**Briques** : 0,25 stud pour les ennemis de horde, 0,5 stud pour les mini-boss et les boss. Tous portent de gros yeux ronds blancs à pupille Ink.

**Élite** : la même maille à ×1,3, avec l'anneau et la couronne or en Neon.

### 3.1 Monde 1 — Bois Grognon / Grumpy Woods (forêt)

Peau des gobelins : **Lime**. Silhouette en **T** : grandes oreilles horizontales, grosse tête (42 % de la hauteur), petites jambes.

| Ennemi | Rôle · comportement | Silhouette et gag | Taille | Attaque | Existe |
| --- | --- | --- | --- | --- | --- |
| **Goblin Grunt** | Mêlée · Swarm | T ; cocotte rouge en casque ; louche brandie hors de la silhouette | 3,75 | Coup de louche au contact | Maille A01 v1 (voxel) ; Parts « Gobelin » ; maille riggée Codex |
| **Goblin Archer** | Tireur · Shooter | T ; capuche vert sombre ; grand arc plus haut que lui | 3,5 | Flèche lente (18 studs/s), visée 0,6 s, toutes les 3,2 s | Maille A01 v1. **Pas de flèche** : boule Neon par script |
| **Goblin Shaman** | Soutien · Support (provisoire : Shooter) | T ; chapeau-champignon violet ; long bâton noueux | 4,25 | Protège les gobelins proches (anneau violet) ; contact faible | Maille A01 v1 ; **comportement absent** |
| **Goblin Bomber** | Kamikaze · Kamikaze (provisoire : Jumper) | T ; bonnet d'aviateur orange, lunettes ; grosse bombe Ink tenue sur le côté | 3,5 | Mèche (1 s, cercle rouge de rayon 5), puis explosion | Maille A01 v1 ; **comportement absent** |
| **Grumpy Acorn** (faune) | Mêlée · Swarm, variante | Gland rond, chapeau en écailles, gros sourcils froncés | 3,1 | Contact | Maille IA lisse (hors DA) ; Parts |
| **Hopshroom** (faune) | Sauteur · Jumper | Champignon rouge à pois crème, pied court, yeux sous le chapeau | 3,6 | Bond sur la position verrouillée, puis anneau d'atterrissage | Maille IA lisse ; Parts |
| **Diving Owl** (faune) | Tireur · Shooter, variante | Boule de plumes, grandes ailes en plaques, flotte un peu | 3,4 | Plume lente | Maille IA lisse ; Parts. **Pas de plume** |
| **Mini-boss : Goblin Chief** (recommandé) | Mini-boss | Gros gobelin ventru ; couronne en capsules ; couvercle de marmite en bouclier ; louche géante | 9 | Contact, plus « Big Ladle » : cercle rouge de rayon 6 devant lui, 1 s (proposé) | **Rien** |
| *ou Giant Stump* | Mini-boss | Souche à racines-pattes | 9 | Contact | Maille IA lisse ; Parts. Doublon visuel du Grand Chêne |
| **Boss : The Grumpy Great Oak** | Boss | Souche-chêne grognon, sourcils de mousse, branches-bras, couronne de feuilles en cubes | 18 | Quake Roots, Acorn Rain, Bark Wave (section 4) | Maille IA lisse 16 × 17,4 × 13,4 (hors DA) ; Parts |

Retirés du monde 1 : la **Bogue blindée** (déjà retirée par le guide DA §12) et le **Golem de mousse** de Codex. Le monde 1 n'a alors pas de blindé : le Bomber tient le rôle du « gros » (guide DA §6).

### 3.2 Monde 2 — Cimetière et marais (nouveau)

Nom de travail à donner par A02 et Clément. Je propose **Soggy Graves** (« Tombes trempées »).

Peau des zombies : **Sky.dd** (bleu-vert mat, plus sombre que le Sky.d du guide : en Sky.d, le zombie de la planche concept passait pour un monstre bleu mignon). Silhouette en **Γ** : bras tendus devant, dos voûté, tête basse en avant. Haillons Plum.

| Ennemi | Rôle · comportement | Silhouette et gag | Taille | Attaque | Existe |
| --- | --- | --- | --- | --- | --- |
| **Shambler** | Mêlée · Swarm | Γ ; chemise Tomato en lambeaux ; une chaussette sur deux | 3,75 | Contact | Ébauche voxel (planche 2) ; maille riggée Codex « Zombie » (hors DA) |
| **Runner** | Sauteur · Jumper | Γ maigre ; **tutu Grape.l** de danseuse, chaussons, noeud Tomato sur le chignon ; un oeil grand ouvert, l'autre mi-clos ; il bondit en grand jeté | 4,25 | Grand jeté sur la position verrouillée | Ébauche voxel (planche 2) |
| **Gravedigger** | Tireur · Shooter | Γ ; haut-de-forme ; pelle plus grande que lui | 4,25 | Motte de terre lancée en cloche, lente | Ébauche voxel (planche 2) |
| **Bloater** | Kamikaze lourd · Kamikaze (provisoire : Jumper) | Gros ventre rond orange citrouille ; toute petite tête | 4,5 | Lent, beaucoup de PV ; au contact ou à sa mort, il éclate (cercle rouge de rayon 5, 0,8 s) | Ébauche voxel (planche 2) |
| **Mini-boss : Zombie Ogre** | Mini-boss | Ogre zombie énorme ; traîne une pierre tombale comme un doudou | 9,5 | Contact, plus « Tombstone Slam » : cercle rouge de rayon 7, 1 s (proposé) | **Rien** |
| **Boss : The Hungry Coffin** (à créer, proposé) | Boss | Cercueil géant debout sur quatre mains de zombie ; le couvercle est une mâchoire à dents carrées ; une langue sort | 17 | « Lid Chomp » : cercle de rayon 8 sous un joueur, 1 s · « Bone Spit » : éventail de 7 os, 18 studs/s · « Grasping Hands » : anneau de 10 à 28 studs, 1,5 s, se saute | **Rien**. Les trois attaques utilisent des types qui existent déjà dans `BossService` (TargetCircle, Fan, Ring) : pas de nouveau code serveur |

### 3.3 Monde 3 — Récré Fantôme / Haunted Recess (école hantée)

Corps des fantômes : **Cream** (jamais cyan : c'est la couleur de l'XP). Silhouette : **dôme et bas ondulé**, sans pieds, flottant à 1 stud du sol.

| Ennemi | Rôle · comportement | Silhouette et gag | Taille | Attaque | Existe |
| --- | --- | --- | --- | --- | --- |
| **Wisp** | Mêlée · Swarm | Petit dôme ; casquette d'écolier Tomato | 3,5 | Contact | Ébauche voxel (planche 2) |
| **Poltergeist** | Tireur · Shooter | Dôme plein, corps en cloche, bas ondulé ; yeux ovales Ink ; pile de livres de classe levée d'une main | 3,75 + 1 de vol | Lance un livre, lent | Ébauche voxel (planche 2) |
| **Banshee** | Soutien · Support (provisoire : Shooter) | Dôme sous un long voile Plum à capuche ; bouche ronde ouverte | 4,25 | Cri : les fantômes à moins de 12 studs vont 1,3 fois plus vite pendant 3 s (onde violette) | Ébauche voxel (planche 2) ; **comportement absent** |
| **Haunted Armor** | Blindé · Armored | Armure Steel vide ; deux yeux qui flottent dans le heaume ; pointeur de tableau en guise de lance | 5 | Contact ; armure 40 % ; pousse les autres | Ébauche voxel (planche 2) |
| **Mini-boss : The Spectral Proctor** | Mini-boss | Surveillant fantôme géant ; sifflet ; brassard jaune de surveillant | 9 | Contact, plus « Whistle Blast » : anneau de 4 à 14 studs, 1 s (proposé) | Parts (kind 15) ; maille riggée Codex « SurveillantFantome » (hors DA) |
| **Boss : The Eternal Headmistress** | Boss | Directrice fantôme en chignon, lunettes en demi-lune, règle géante, robe en cloche qui flotte | 18 | Ruler Smack, Paper Planes ; point faible : la cloche (section 4) | Parts |

### 3.4 Hors run v2

| Entrée v1 | Décision proposée |
| --- | --- |
| Désert v1 : Momie PQ, Cactus coureur, Vautour, Scarabée blindé, Chameau-tirelire, Pharaon grille-pain | Retirés : le monde 2 devient le cimetière |
| Récré v1 : Craie vivante, Cartable mordeur, Fantôme de surveillant, Casier-armoire | Remplacés par les fantômes |
| Bogue blindée, Golem de mousse, « Zombie » et « Gobelin » génériques (kinds 20 à 22) | Retirés (remplacés par le roster ci-dessus) |
| The Great Hubbub (boss final v1) | Pas utilisé par la run v2 (`RunManager` ne lit que `Worlds[].boss`). Gardé en réserve dans la config, **sans modèle** |

**Total à modéliser : 21 modèles.**
- 15 ennemis : 7 dans le monde 1, 4 dans le monde 2, 4 dans le monde 3.
- 3 mini-boss.
- 3 boss.

Les ids d'ennemis tiennent sur 5 bits (1 à 31) : 22 ids avec la réserve, il reste de la marge.

---

## 4. Boss : attaques et télégraphes

Règles v2 :
- 2 à 3 attaques ;
- annoncées au moins 1 s avant (`Bosses.MinTelegraph = 1,0`) ;
- `PhaseEnabled = false` : seules les attaques de phase 1 servent.

Couleurs des télégraphes (`Bosses.Colors`) :
- Tomato pour un danger ;
- Grape pour une invocation ;
- Gold pour un point faible.

| Boss | Attaque | Type | Télégraphe | Objet propre à l'attaque | Existe |
| --- | --- | --- | --- | --- | --- |
| Great Oak | Quake Roots | TargetCircle | cercle de rayon 8 sous un joueur, 1,0 s, verrouillé à 0,5 s | racines qui jaillissent | Disque Neon par script ; impact `FX.Enemies.Boss` |
| Great Oak | Acorn Rain | MultiCircle | 5 cercles de rayon 5, 1,2 s | glands qui tombent | Idem ; **pas de gland** |
| Great Oak | Bark Wave | Ring | anneau de 10 à 30 studs, 1,5 s, se saute | onde d'écorce | Disque et zone sûre verte par script |
| Hungry Coffin | Lid Chomp | TargetCircle | cercle de rayon 8, 1,0 s | morsure du couvercle | **Rien** |
| Hungry Coffin | Bone Spit | Fan | marqueur de rayon 5 sur le boss, puis 7 os | os (projectile) | **Rien** |
| Hungry Coffin | Grasping Hands | Ring | anneau de 10 à 28 studs, 1,5 s, se saute | mains qui sortent du sol | **Rien** |
| Headmistress | Ruler Smack | TargetCircle | cercle de rayon 9, 1,0 s, verrouillé à 0,5 s | règle qui tape | Disque par script |
| Headmistress | Paper Planes | Fan | marqueur de rayon 5, puis 5 avions en papier | avion en papier (projectile) | Boules Neon par script ; **pas d'avion** |
| Headmistress | Point faible : la cloche | Platform | marqueur doré | — | Disque doré par script |

Attaques inactives tant que `PhaseEnabled = false` : Saplings (Oak), Detention for All et Line Up! (Headmistress). Leurs télégraphes utilisent les mêmes objets que les autres.

---

## 5. Ce qu'A14 m'a laissé, et ce qui manque

A14 a converti `EnemyAttackFX` (dossier 12 §14). Il reste dans mes fichiers :

1. **Tirs ennemis** (`EnemyRenderer.onProjectiles`). Aujourd'hui, ce sont des boules Neon de la couleur `Worlds[].projectile` : orange, rose ou vert. Cela contredit le guide DA §6 : « tirs ennemis Tomato, lents, sans Neon ».
2. **Télégraphes des boss** (`BossRenderer.setTelegraphs`), en trois formes : cercle (TargetCircle, MultiCircle, SelfCircle, Summon), anneau avec zone sûre (Ring) et ligne (Line, Charge).
3. Hors du lot d'A14, mais visibles et fabriqués par script :
   - l'anneau et la couronne des élites ;
   - les marqueurs de point faible ;
   - le pilier de l'Arche ;
   - les imposteurs de LOD.

**`Assets.FX.Enemies` ne contient aucun de ces objets.** A14 n'a posé que les éclats d'impact (`Sweep`, `Burst`, `Shot`, `Land`, `Boss`). `Assets.FX.Shared.Telegraph` existe, mais c'est le télégraphe **du joueur**, en Gold : il ne peut pas servir aux ennemis, car le rouge est réservé aux dangers ennemis.

Objets à poser (proposition, en suivant le contrat d'attributs d'A14 : `S`, `Base`, `Fade0`, `Fade1`, `Grow`…) :

| Objet | Où | Forme |
| --- | --- | --- |
| Télégraphes ennemis : `TelegraphCircle`, `TelegraphRing` (avec zone sûre), `TelegraphLine` | `Assets.FX.Enemies.Telegraphs` | Lumière lisse : bord Tomato, remplissage qui grandit jusqu'à l'impact. Variantes de couleur posées par le code (Grape pour une invocation, Gold pour un point faible) |
| Projectile générique | `Assets.FX.Enemies.Projectiles.Default` | Boule Tomato mate à contour Ink, sans Neon |
| Projectiles d'ennemis | `Assets.FX.Enemies.Projectiles.<Nom>` | Objets en briques (« des blocs pour ce qui existe ») : Arrow (flèche de l'Archer), Feather (plume du Hibou), DirtClod (motte du Gravedigger), Book (livre du Poltergeist) |
| Projectiles et chutes de boss | `Assets.FX.Bosses.<Boss>.<Attaque>` | Acorn (gland qui tombe), Bone (os), PaperPlane (avion en papier) |
| Élite | `Assets.FX.Enemies.EliteRing`, `EliteCrown` | Neon or, comme aujourd'hui |
| Point faible et Arche | `Assets.FX.Bosses.WeakPoint`, `ArcheBeam` | Neon or, Neon violet |

**Il manque une donnée au client.** Le paquet des projectiles (`EnemyCodec.encodeProjectiles`) envoie une couleur, mais pas le tireur. Le client ne peut donc pas choisir entre une flèche et une plume. Il faut ajouter un octet `kind` à chaque projectile : `EnemyCodec` est partagé, et l'encodage se fait côté serveur dans `EnemyService` (contract request A04, section 9).

---

## 6. Rendu : ce qui doit changer (étape 4)

- `EnemyRenderer` et `BossRenderer` **clonent** `Assets.Creatures.<Modèle>` et ne fabriquent plus rien : je supprime les branches Parts, la table `MODELS` et les champs `model` de la config. Si un modèle manque, le renderer le signale une fois dans la sortie, sans repli (décisions v2 §12).
- La correspondance entre un ennemi et son modèle passe par un champ `asset` de `Config/Enemies` (par exemple `asset = "Enemy_GoblinGrunt"`), et non plus par le nom.
- On garde la réplication binaire (`EnemyCodec`, 7 octets par ennemi), le pooling par (kind, LOD, élite), le `BulkMoveTo` unique par frame, les LOD avec hystérésis et `EnemyMotion` (le corps entier se balance et sautille).
- **LOD** :
  - moins de 80 studs : maille complète ;
  - 80 à 150 studs : **maille simplifiée** du même modèle (aujourd'hui, c'est la même maille) ;
  - plus de 150 studs : imposteur.
- Les clés de `EnemyMotion.profiles` et du remote `EnemyAttackVisual` (le nom de l'ennemi) suivent les nouveaux noms.

**Ce que Codex a changé dans `main` (commit `aa4ce33`, 5 nov.), et dont je pars à l'étape 4 :**
- `ArtLibrary.find` cherche un modèle dans cet ordre :
  1. `ReplicatedStorage.EnemyVisualRigs.Enemy_<nom>` ;
  2. `ReplicatedStorage.Assets` ;
  3. `ReplicatedStorage.EnemyVisualMeshes.<nom>`.
- `EnemyRenderer` utilise un modèle riggé (avec des os) à toutes les distances, et fige une pose de repos à mi-distance.

Je garde ce comportement pour les modèles riggés. Les nouveaux ennemis sont des mailles fusionnées rigides : `EnemyMotion` les anime en entier, sans os.

**Proposition pour Clément** (via le coordinateur) : un seul endroit pour les modèles, `ReplicatedStorage.Assets.Creatures`, comme le prévoit la section 12 des décisions v2.
- Les modèles de `EnemyVisualRigs` et `EnemyVisualMeshes` qu'on garde y seraient déplacés.
- Les deux dossiers seraient retirés, puis `ArtLibrary.find` simplifié.
- Tant que Clément n'a pas tranché, je ne touche ni à ces dossiers ni à l'ordre de recherche. Les nouveaux modèles portent des noms qui n'existent pas encore (champ `asset`), donc aucun conflit.

---

## 7. Budget (horde de 300 sur téléphone)

| Classe | Triangles visés / plafond (guide DA §9) | Pièces par modèle |
| --- | --- | --- |
| Ennemi de horde | 800 / 1 000 (v1 mesurée : 656 à 792) | 1 MeshPart (maille fusionnée, couleurs par sommet) ; les yeux dans la même maille |
| LOD moyen | ≤ 200 | 1 |
| Ennemi moyen (Bloater, Haunted Armor) | 1 200 / 2 000 | 1 |
| Mini-boss | 6 000 / 12 000 | 1 ou 2 |
| Boss | 15 000 par maille | 2 à 4 (parties qui bougent) |

Pire cas, 300 ennemis à moins de 80 studs : 300 × 800 = 240 000 triangles. En pratique, le LOD en garde environ 80 en maille complète, soit à peu près 100 000 triangles. Le même MeshId, avec le même matériau et une couleur blanche, permet l'instanciation automatique de Roblox : un appel de dessin par modèle. **Ces chiffres sont à mesurer en Play à l'étape 4** et seront notés ici.

---

## 8. Questions pour Clément (porte 1)

1. **Le roster de la section 3** te va-t-il ? 15 ennemis, 3 mini-boss et 3 boss.
2. **Mini-boss du monde 1** : *Goblin Chief* (recommandé : la famille reste lisible, et la Souche géante ressemble trop au Grand Chêne) ou *Giant Stump* ?
3. **Boss du monde 2** : *The Hungry Coffin* (cercueil sur des mains de zombie, 3 attaques) te plaît-il, ou veux-tu une autre idée ?
4. **Faune de la forêt** (gland, champignon, hibou) : la garder à côté des gobelins (recommandé : 10 minutes de monde 1 avec 4 gobelins seulement, ce serait monotone) ?
5. **Objets d'attaque manquants** (section 5) : je les pose moi-même en suivant le contrat d'A14 (recommandé : A14 a fini, et ce sont mes fichiers qui les clonent) ?

La question des gobelins v1 (les refaire dans la DA actuelle ou les garder) viendra à la porte 2, avec la planche concept.

---

## 9. Contract requests

| Pour | Demande | Pourquoi |
| --- | --- | --- |
| A04 (`EnemyService`) | Deux comportements : `Support` (protection ou accélération des voisins, toutes les 6 s, 12 studs) et `Kamikaze` (mèche de 1 s à 6 studs, explosion de rayon 5, mort). Ajouter les clés `Support` et `Kamikaze` aux rosters de `Worlds` (chaque clé optionnelle) | Shaman, Banshee, Bomber, Bloater (section 2) |
| A04 (`EnemyService`) + A03 (`EnemyCodec`) | Ajouter un octet `kind` du tireur à chaque projectile ennemi ; passer la couleur à Tomato | Choisir l'objet projectile (flèche, plume, motte, gomme) |
| A04 (`RunManager`, `BossService`) | Optionnel : une attaque pour les mini-boss (Big Ladle, Tombstone Slam, Whistle Blast) | Aujourd'hui, les mini-boss ne font que du contact |
| A02 (`Worlds`, `StageService`) | Créer le monde 2 cimetière-marais (id et nom) et retirer `DunesCroustillantes` ; `Run.WorldChain` = Bois → cimetière → Récré quand les cartes existent | Les zombies et le Hungry Coffin n'apparaîtront qu'avec ce monde |
| A05 (capture) | Le marqueur de capture d'A01 (`ArtLibrary.cloneCaptureMarker`) s'accroche au modèle cloné de l'ennemi capturable | Contrat d'A01 avec A03 (note A01) |

Je modifie moi-même, dans mon domaine :
- `Config/Enemies` et `Config/Bosses` (contenu, noms, champ `asset`) ;
- `EnemyRenderer`, `BossRenderer` et `EnemyMotion` ;
- le décodage des projectiles dans `EnemyCodec`.

Les ids d'ennemis utilisés par le serveur (`Worlds.roster`, `Bosses.kind`, `summonKind`, `Worlds.miniBoss`) changent avec le roster : je le coordonne avec A04 et A02 au moment de la bascule, sans casser la run du monde 1.

---

## 10. Étape 2 : planche concept (porte 2 présentée à Clément)

Planche : `assets/a03/01-ennemis-boss-concept.jpg`. Sources :
- `assets/a03/creatures.py` : les modèles sur grille ;
- `assets/a03/concept.py` : les rendus Blender 5.2 en ligne de commande ;
- `assets/a03/board.py` : le montage.

Modélisés : Goblin Grunt, Archer, Shaman et Bomber (v2), Zombie Runner, Poltergeist et The Hungry Coffin. La horde est rendue en maille fusionnée du jeu (technique B) : environ 700 triangles par ennemi, plus les yeux. En briques chanfreinées, un ennemi en coûterait 3 500 à 4 900.

**Relectures à l'aveugle** (2 relecteurs par tour, seuil 8,5) :

| Tour | Notes | Moyenne | Ce qui a changé ensuite |
| --- | --- | --- | --- |
| 1 | 7,2 et 6 | 6,6 | cocotte sans bord crème, 3 gobelins v2 de plus, test de horde du monde 1 avec les 4 rôles |
| 2 | 7,1 et 7,0 | 7,05 | ressemblances retirées (chapeau-champignon, tête brune à sourcils, zombie bleu), Grunt sans moustache, sol calme |
| 3 | 7,6 et 7,5 | 7,55 | zombie gris, yeux blancs cerclés pour le fantôme, cercueil à bouche noire, capturable et tirs visibles, test des mondes 2 et 3 |
| 4 | 8,4 et 7,6 | 8,0 | corrections légères : plume crème de l'Archer, livres verts, théière redessinée, légendes corrigées |

Le coordinateur a demandé de présenter la planche après ce tour, même sous 8,5.

**Points encore ouverts** (relecteur le plus sévère du tour 4) :
- le zombie se lit encore mal comme zombie (« un rat ou un pigeon en tutu ») ;
- le cercueil se lit comme un coffre piégé ;
- la louche et la théière restent difficiles à lire.

Ces trois points se règlent à l'étape 3, modèle par modèle, avec un contrôle qualité à 8,5 (étape 5).

**Écarts au guide DA, à valider par Clément** :
- peau des zombies grise (Stone.d) au lieu de Sky.d : en bleu, le zombie rappelait un monstre bleu connu, et en vert, un dinosaure connu ;
- théière violette pour le Shaman au lieu du champignon : le chapeau-champignon à pois rappelait un personnage connu ;
- yeux blancs cerclés d'Ink sur les fantômes, au lieu d'yeux Ink : deux yeux noirs faisaient une tache sombre, et de loin le fantôme passait pour un mouton ;
- couleur du sauteur : Tomato, comme la mêlée.
