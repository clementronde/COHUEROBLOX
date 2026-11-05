# Kit d'assets « tout en tenons » (A01)

Demande de Clément le 5 nov. 2026 : « Fais-moi juste les modèles, je vais faire la map. » Il place lui-même les assets ; A01 les fabrique.

**Dans COHUE :** `Workspace.A01_AssetKit`, une vitrine posée sur la dalle grise vers (220 à 390, 8, 720 à 830), à l'est du village v1. Chaque asset est un `Model` de Parts :
- pivot au centre de sa base : il se pose directement au sol ;
- surfaces `Studs` sur toutes les faces (on peut repasser Resurface) ;
- couleurs de la palette COHUE 16, `SmoothPlastic` ;
- ancré, sans aucun script.

Pour s'en servir, on déplace l'asset de la vitrine vers la map, ou on le copie (Ctrl+D) pour le garder en modèle.

| Rayon | Assets |
| --- | --- |
| Arbres | Pine_Small, Pine_Medium, Pine_Large, Pine_Tall (long tronc, pour l'arrière-plan), Pine_Wide (bas et touffu), Tree_Round, Tree_Autumn, Bush_Small, Bush_Large |
| Roche | Rock_Small, Rock_Medium, Rock_Large, Cliff_Wall_Long (20 × 14), Cliff_Wall_Short (12 × 9), Cliff_Pillar (6 × 18), Slab_Square, Slab_Long, Slab_Small (pierres de gué ou de chemin) |
| Objets | Mushroom_Red, Mushroom_Group, Bridge_Wood (16 × 5), Fence_Wood (8 de long), Lamp_Post (lanterne Neon et PointLight), Crate, Barrel, Log_Pile, Flower_Patch |
| Muraille | Wall_Stone (12 de long, créneaux), Wall_Pillar (fenêtre Neon) |

Total : 29 assets, 237 Parts.

**Reconstruire :** `A01_AssetKit_build.luau`. On envoie la section `@header` par le MCP de Studio (`execute_luau`, mode Edit), puis `@nature` et `@props`. Les tirages sont fixés (`Random.new(seed)`) : on retrouve exactement le même kit. Le fichier n'est jamais chargé par le jeu.

**Contrôle :** les Parts sont exportées de Studio et rendues dans Blender (`scratchpad/kit/render_kit.py`), parce que les captures de Studio sortaient blanches pendant la session.
