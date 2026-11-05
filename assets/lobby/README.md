# Lobby « Hubbub Village » (A01)

## État au 5 nov. 2026

| Version | Où | État |
| --- | --- | --- |
| v1, Parts posées par un script d'édition | `Workspace.HubbubVillage` dans la place `COHUE` (1 368 objets, 0 script), `HubbubVillage_build.luau` | **Refusée par Clément** (« beaucoup trop AI slop »). À retirer de COHUE quand la v2 sera posée |
| v2, maquette compacte | `assets/voxel/lobby.py` (modèles sur grille), `assets/voxel/brick.py` (rendu en briques), planche `assets/style/06-lobby-briques.png` | **Maquette Blender à valider.** Rien n'est encore construit dans Studio |

Le style est passé du voxel aux **briques à tenons** le 5 nov. Le guide de style est `docs/dossier/80-direction-artistique.md`. Clément a trouvé la composition de la maquette « très cool ». Le style voxel a été écarté, la composition est gardée.

## La maquette v2

Une île flottante de 112 × 100 studs, avec sa coupe en strates. Arrivée au sud, portail au nord. Coordonnées en studs, centre de la place en (0, 2), nord = −Y dans Blender (−Z dans Roblox).

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
- tester la technique des briques en texture (A01-02 bis, section 9 du guide) ;
- obtenir l'accord de Clément pour téléverser les nouvelles mailles ;
- obtenir un créneau dans COHUE auprès de la session principale.

Découpage prévu (section 9 du guide) :
- **le sol** : Parts ou mailles plates à la couleur de chaque zone, avec une texture de tenons répétée ; dalles lisses pour les chemins et la place ;
- **la tête et les stations** : briques en géométrie, découpées en mailles de moins de 20 000 triangles ;
- **les arbres, les props et les avatars d'exposition** : briques en texture.

Les points d'accroche pour A09 gardent les mêmes noms qu'en v1 : attributs `LobbyRole` (`Arrival`, `Pad` + `Mode`, `PadZone`, `PortalSwirl`, `Leaderboard`, `StatueSlot`, `QuestBoard`, `CritterPen`), `ProximityPrompt` `ClassPrompt`, `CrittersPrompt`, `ShopPrompt`, `LeaderboardsPrompt`, `QuestsPrompt`, et un `BoardGui` vide sur la stèle et le tableau des quêtes.

## Rendus

```bash
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python assets/voxel/lobby.py -- assets/voxel/review/lobby_brick
python assets/style/compose.py lobby
```
