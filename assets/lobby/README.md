# Lobby « Hubbub Village » (A01)

## État au 5 nov. 2026

| Version | Où | État |
| --- | --- | --- |
| v1, Parts posées par un script d'édition | `Workspace.HubbubVillage` dans la place `COHUE` (1 368 objets, 0 script), `HubbubVillage_build.luau` | **Refusée par Clément** (« beaucoup trop AI slop »). À retirer de COHUE quand la v2 sera posée |
| v2, maquette compacte | `assets/voxel/lobby.py` (plan, stations sur grille, terrain), `brick.py` (stations en briques), `nature.py` (décor naturel), planche `assets/style/06-lobby-nature-briques.png` | **Maquette Blender à valider.** Rien n'est encore construit dans Studio |

Le 5 nov., Clément a trouvé la composition de la maquette voxel « très cool », mais il a écarté le voxel. D'après ses deux retours, la **carte est naturelle** (herbe lisse, chemins de terre, forêt, rochers) et **tout ce qui est interactif est en briques à tenons**. Dans Studio, les tenons seront posés par son plugin. Le guide de style est `docs/dossier/80-direction-artistique.md`.

## La maquette v2

Une île flottante naturelle de 112 × 100 studs : collines douces vers les bords, forêt dense en lisière, falaise de rochers derrière le portail, flanc rocheux sous l'île. Arrivée au sud, portail au nord. Coordonnées en studs, centre de la place en (0, 2), nord = −Y dans Blender (−Z dans Roblox).

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
- valider la maquette avec Clément ;
- tester le plugin de tenons sur une maille en briques, et la technique des briques en texture (A01-02 bis, section 9 du guide) ;
- obtenir l'accord de Clément pour téléverser les nouvelles mailles ;
- obtenir un créneau dans COHUE auprès de la session principale.

Découpage prévu (section 9 du guide) :
- **le sol** : Terrain de Roblox ou maille lisse (à trancher avec A02), avec des chemins de terre et des clairières ;
- **les arbres, les rochers et la falaise** : mailles lisses à couleurs par sommet ;
- **la tête et les stations** : briques en géométrie, découpées en mailles de moins de 20 000 triangles, puis tenons posés par le plugin de Clément ;
- **les avatars d'exposition et les petits objets** : briques en texture.

Les points d'accroche pour A09 gardent les mêmes noms qu'en v1 : attributs `LobbyRole` (`Arrival`, `Pad` + `Mode`, `PadZone`, `PortalSwirl`, `Leaderboard`, `StatueSlot`, `QuestBoard`, `CritterPen`), `ProximityPrompt` `ClassPrompt`, `CrittersPrompt`, `ShopPrompt`, `LeaderboardsPrompt`, `QuestsPrompt`, et un `BoardGui` vide sur la stèle et le tableau des quêtes.

## Rendus

```bash
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python assets/voxel/lobby.py -- assets/voxel/review/lobby_nature
python assets/style/compose.py lobby
```
