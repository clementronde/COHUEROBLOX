# Lobby « Hubbub Village » (A01)

## État au 5 nov. 2026

| Version | Où | État |
| --- | --- | --- |
| v1, Parts posées par un script d'édition | `Workspace.HubbubVillage` dans la place `COHUE` (1 368 objets, 0 script), `HubbubVillage_build.luau` | **Refusée par Clément** (« beaucoup trop AI slop »). À retirer de COHUE quand la v2 sera posée |
| v2, maquette compacte | `assets/voxel/lobby.py` (plan, stations sur grille, île), `brick.py` (stations en briques fines), `studs.py` (décor en gros blocs à tenons), planches `assets/style/06-lobby-tenons.png` et `07-pistes-melange-ou-tenons.png` | **Style choisi par Clément (piste B).** Rien n'est encore construit dans Studio |

Le 5 nov., Clément a trouvé la composition de la maquette voxel « très cool », mais il a écarté le voxel. Après comparaison de deux pistes, il a choisi la piste B : **tout en tenons, avec des formes naturelles**. Le décor est en gros blocs à tenons (terrasses, falaises en blocs décalés, sapins en plaques, mare), et ce avec quoi on interagit est en petites briques fines. Dans Studio, les tenons seront posés par son plugin **Resurface**. Le guide de style est `docs/dossier/80-direction-artistique.md`.

## La maquette v2

Une île flottante en blocs à tenons de 112 × 100 studs : herbe en terrasses qui monte vers les bords, forêt de sapins en lisière, falaise en blocs décalés derrière le portail, mare à pierres de gué à l'est, flanc de roche sous l'île. Arrivée au sud, portail au nord. Coordonnées en studs, centre de la place en (0, 2), nord = −Y dans Blender (−Z dans Roblox).

| Zone | Position | Contenu (aucun panneau écrit) |
| --- | --- | --- |
| Portail (héros) | (0, −40), 32 studs de haut | Tête de gobelin géante en pierre, endormie : un œil fermé, l'autre entrouvert qui regarde les joueurs, une défense cassée, un anneau d'or à l'oreille. La bouche (15 × 12,5 studs) est le portail, avec un tourbillon Grape.d / Royal.d. La langue sert de tapis jusqu'au pad Public |
| Pads | Solo (−17, −20) · Public (0, −15) · Friends (17, −20) | Dalles rondes avec 1, 4 ou 2 silhouettes incrustées |
| Arrivée | (0, 40) | Meule de foin d'où dépassent deux jambes : on revient de run en tombant dedans |
| Knight | (−17, 27) | Râtelier d'épées, enclume, mannequin de paille coiffé d'une cocotte, fanion Royal |
| Archer | (18, 22) | Trois cibles, une carotte plantée dans le mille, flèches ratées, fanion Leaf |
| Mage | (−17, 10) | Tour penchée dont le toit est le chapeau du Mage, chaudron, grimoires |
| 5 classes à débloquer | (17, 37) | Charrette de caisses cadenassées ; une bâche cache une pointe, des yeux regardent par une planche cassée |
| Compagnons | (−37, 2) | Enclos avec niche, os, abreuvoir et une lisse mordue ; des gobelins capturés s'y promènent |
| Boutique de Gob | (35, 4) | Étal rayé surmonté d'un haut-de-forme géant, chapeaux en vitrine, miroir, sac d'XP volée qui déborde |
| Classements | (−34, −27) | Stèle d'ardoise à deux colonnes, podium or / acier / cuir, statues des meilleurs joueurs |
| Quêtes | (34, −27) | Tableau sous un petit toit, avis de recherche d'un gobelin, hibou facteur |
| Feu de camp | (16, −8) | Lieu où l'on traîne, hors de l'axe d'arrivée, avec trois bancs en rondins |

Trajet arrivée → pad Public : 55 studs, soit 3,5 s à 16 studs/s.

**Écarts avec le plan validé d'A09** (`docs/dossier/65-lobby.md`), à faire valider (Contract request) :
- les 8 présentoirs alignés sont remplacés par 3 stations de classe et la charrette des 5 classes à débloquer ;
- le gardien du portail est la tête de gobelin elle-même ;
- l'emprise passe d'environ 230 × 215 à 112 × 100 studs.

## Pour construire la v2 dans COHUE

Le lobby est posé comme objets dans la place : rien n'est fabriqué par script au lancement. Avant la pose, il faut :
- tester Resurface sur une de nos mailles exportée avec des UV à l'échelle de la cellule (A01-02 bis, section 9 du guide) ;
- obtenir l'accord de Clément pour téléverser les mailles de la tête et des stations ;
- obtenir un créneau dans COHUE auprès de la session principale.

Découpage prévu (section 9 du guide) :
- **l'île, la falaise, les arbres, les rochers, les dalles** : des Parts (blocs, coins) posées dans Studio aux couleurs de la palette, avec les tenons de Resurface. Il n'y a rien à téléverser. Pour l'île, on peut reprendre les rectangles du maillage glouton de `studs_island`, ou utiliser une seule maille avec des UV au stud ;
- **l'eau** : Terrain de Roblox ;
- **la tête et les stations** : briques fines en géométrie, découpées en mailles de moins de 20 000 triangles, avec les tenons de Resurface par MaterialVariant ;
- **les avatars d'exposition et les petits objets** : mailles fusionnées, avec les tenons de Resurface.

Les points d'accroche pour A09 gardent les mêmes noms qu'en v1 : attributs `LobbyRole` (`Arrival`, `Pad` + `Mode`, `PadZone`, `PortalSwirl`, `Leaderboard`, `StatueSlot`, `QuestBoard`, `CritterPen`), `ProximityPrompt` `ClassPrompt`, `CrittersPrompt`, `ShopPrompt`, `LeaderboardsPrompt`, `QuestsPrompt`, et un `BoardGui` vide sur la stèle et le tableau des quêtes.

## Rendus

```bash
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python assets/voxel/lobby.py -- assets/voxel/review/lobby_studs
python assets/style/compose.py lobby
python assets/style/compose.py compare
```
