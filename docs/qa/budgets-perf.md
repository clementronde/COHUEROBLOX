# COHUE — Budgets de perf (A13-02)

Agent A13, 5 nov. 2026. Base : `main` au commit `851322e`.

Ce fichier fixe un budget par domaine pour un **téléphone milieu de gamme** (cible de la porte de la phase 0 : 150 ennemis à 60 FPS, `README.md`). Chaque chiffre a l'une de trois origines :

- **[code]** : la valeur vient du code actuel, avec le fichier et la ligne ;
- **[doc Roblox]** : la valeur vient de la doc officielle, avec l'URL (lue le 5 nov. 2026) ;
- **[hypothèse]** : un chiffre de travail sans source officielle. La mesure A13-01 le confirme ou le corrige.

Un domaine qui dépasse son budget le signale dans son rapport. Il ne prend pas la marge d'un autre domaine sans accord du chef de projet.

## 0. Ce que Roblox publie, et ce qu'il ne publie pas

| Sujet | Ce que dit la doc | Source |
| --- | --- | --- |
| Paquet non fiable | Roblox peut jeter sans renvoi un message dont la charge dépasse 1 000 octets | [Remote events](https://create.roblox.com/docs/scripting/events/remote) |
| Débit par client | **Aucun plafond publié** (ni sur Remote events, ni sur Improve performance) | idem, [Improve](https://create.roblox.com/docs/performance-optimization/improve) |
| Événements en trop | Fiables : traités plus tard. Non fiables : jetés | [Remote events](https://create.roblox.com/docs/scripting/events/remote) |
| Image | 60 FPS = 16,67 ms par image ; 30 FPS = 33,33 ms | [Identify](https://create.roblox.com/docs/performance-optimization/identify) |
| Plafond client | 60 FPS par défaut | idem |
| Serveur | Heartbeat plafonné à 60 Hz ; garder la mémoire serveur sous 50 % de `6,25 Gio + 100 Mio × joueurs max` | idem |
| Textures | 512×512 au plus pour une texture ordinaire, moins de 256×256 pour les petites images | [Improve](https://create.roblox.com/docs/performance-optimization/improve) |
| Mémoire mobile | **Aucun chiffre publié** | idem |

Conséquence : pour le débit et la mémoire du téléphone, les plafonds ci-dessous sont des **hypothèses**, à confirmer par A13-01.

## 1. Image client (16,67 ms à 60 FPS)

Répartition **[hypothèse]** du temps CPU d'une image sur le téléphone cible. Le rendu GPU est mesuré à part.

| Poste | Budget | Code concerné |
| --- | --- | --- |
| Horde (EnemyRenderer + EnemyMotion + EnemyRigMotion + BulkMoveTo) | 4,0 ms à 300 ennemis | `client/Controllers/EnemyRenderer.luau:403` (`render`) |
| Effets d'armes (WeaponFX) | 2,0 ms | `client/Controllers/WeaponFX.luau:955` |
| Butin (LootRenderer) | 1,0 ms à 450 objets visibles | `client/Controllers/LootRenderer.luau:24` (`VISIBLE_CAP = 450`) |
| Compagnons, boss, autels, effets ennemis | 1,5 ms à eux quatre | `CompanionRenderer`, `BossRenderer`, `ShrineFX`, `EnemyAttackFX` |
| UI (HUD, cartes, minimap, pings) | 1,5 ms | `client/Controllers/UI/*` |
| Mouvement, caméra, entrées | 1,0 ms | `MovementController`, `CameraController` |
| Moteur (physique du personnage, réplication, GC) | 5,6 ms restants | — |

Mesure : MicroProfiler (Ctrl+Alt+F6 sur PC ; sur mobile, menu Paramètres > MicroProfiler On, puis le navigateur sur l'IP affichée), étiquettes `PreRender` et `RenderStepped`. Source : [MicroProfiler](https://create.roblox.com/docs/studio/microprofiler).

## 2. Horde : plafond d'ennemis

| Valeur | Chiffre | Origine |
| --- | --- | --- |
| Plafond technique serveur | 300 vivants | **[code]** `shared/Config/Balance.luau:8` (`MaxEnemies`), décision « aucun ennemi max » de `01-decisions-v2.md` §2 |
| Apparitions par tick | 10, soit 150 par seconde | **[code]** `Balance.luau:9` |
| Courbe de densité solo | 10 → 200 en 9 min | **[code]** `Balance.luau:19-25` |
| Coop | +40 % de densité par joueur en plus | **[code]** `Balance.luau:26` |
| Porte de la phase 0 | 150 ennemis à 60 FPS | **[code]** `README.md` |
| Cible du lancement | **300 à 30 FPS minimum, 45 FPS en moyenne** sur le téléphone cible | **[hypothèse]**, à mesurer (A13-01) |

En coop à 4, la courbe donne 200 × (1 + 0,4 × 3) = 440 ennemis voulus à 9 min : le plafond de 300 est atteint en jeu normal, avant même l'Overtime. Le palier de 400 du script de mesure sert à voir la marge au-dessus.

## 3. Réseau

### 3.1 Paquets non fiables

Règle du contrat : moins de 900 octets par paquet (`docs/ARCHITECTURE.md` §6), soit 100 octets de marge sous la limite de 1 000 de Roblox. Tous les codecs binaires actuels la respectent :

| Remote | Format | Plus gros paquet | Origine |
| --- | --- | --- | --- |
| EnemySnapshot | en-tête 7 + 7 par ennemi, 127 ennemis par paquet | 896 octets | **[code]** `shared/EnemyCodec.luau:11-13` |
| WeaponFx | en-tête 6 + 14 par effet, 63 effets par paquet | 888 octets | **[code]** `shared/WeaponFxCodec.luau:25-28` |
| LootSnapshot | en-tête 8 + 7 par objet, 127 objets par paquet | 897 octets | **[code]** `shared/LootCodec.luau:11-14` |
| CompanionSnapshot | en-tête 5 + 23 par compagnon, 38 par paquet | 879 octets | **[code]** `shared/Config/Companions.luau:90-93` |
| EnemyAttackVisual | arguments Luau (id, 2 textes, 2 Vector3, nombre) | ~60 octets **[hypothèse]** | `server/Services/EnemyService.luau:406` |

Tout nouveau remote non fiable passe par un codec du même type, avec un `assert` sur la taille au chargement (comme `EnemyCodec.luau:17`).

### 3.2 Débit descendant par client

**[hypothèse]** : budget total de **50 Ko/s en moyenne par client**, pics à 80 Ko/s. Roblox ne publie pas de plafond (section 0) ; 50 Ko/s est le chiffre de travail courant chez les développeurs Roblox. Il est à confirmer par A13-01 : au palier où le ping monte ou les ennemis saccadent, on est au-dessus.

| Remote | Fréquence | Pire cas actuel | Budget | Calcul |
| --- | --- | --- | --- | --- |
| EnemySnapshot | 15 Hz | **31,8 Ko/s** à 300 ennemis à moins de 80 studs | 25 Ko/s | 3 paquets × 7 + 300 × 7 = 2 121 octets × 15. Rayons : `Balance.luau:30-32` |
| WeaponFx | 15 Hz | **26,6 Ko/s** | 10 Ko/s | 2 paquets pleins (126 effets, `WeaponService.luau:30`) × 888 × 15 |
| LootSnapshot | 10 Hz, complet toutes les 10 ticks | ~4 Ko/s (complet) + deltas | 6 Ko/s | 400 gemmes + 160 pièces (`Config/Loot.luau:17,30`) = 5 paquets par seconde |
| EnemyProjectiles (fiable) | 15 Hz | 41 octets par tir | 2 Ko/s | `EnemyCodec.luau:126`, 150 projectiles max (`EnemyService.luau:33`) |
| CompanionSnapshot | 10 Hz | 8 compagnons × 23 octets × 10 = 1,9 Ko/s | 2 Ko/s | `Companions.luau:88,91` |
| EnemyAttackVisual | à chaque attaque | ~2 Ko/s **[hypothèse]** | 2 Ko/s | envoyé à **tous** les clients (`EnemyService.luau:406`) |
| RunState, PlayerVitals, Build, Coins, etc. | ≤ 10 Hz | < 2 Ko/s | 3 Ko/s | `Config/Run.luau:105` (`VitalsMaxHz = 10`) |
| **Total** | | **~70 Ko/s** au pire | **50 Ko/s** | |

Le pire cas dépasse le budget : voir les bugs PERF-01 et PERF-02 du plan de test.

### 3.3 Client → serveur

| Remote | Plafond | Origine |
| --- | --- | --- |
| Mouvement (glissade, saut) | 5 par seconde et par joueur | **[code]** `shared/Config/Movement.luau:91` |
| CardChoice | 5 par seconde | **[code]** `shared/Config/Cards.luau:35` |
| Tous les autres | seau de jetons de `Net.onServerEvent` | **[code]** `shared/Net.luau:108` |

Budget **[hypothèse]** : < 2 Ko/s montant par client. Roblox limite aussi le débit montant par type de remote, sans publier le chiffre ([Remote events](https://create.roblox.com/docs/scripting/events/remote)).

## 4. Serveur

| Poste | Budget par tick à 15 Hz (66 ms) | Origine |
| --- | --- | --- |
| EnemyService (`step` + `send`) à 300 ennemis, 4 joueurs | 6 ms | **[hypothèse]** |
| WeaponService (400 projectiles, 96 zones) | 6 ms | plafonds **[code]** `shared/Config/Weapons.luau:92-94` |
| Loot, compagnons, autels, passifs (10 à 15 Hz) | 4 ms à eux tous | **[hypothèse]** |
| RunManager (contacts à 15 Hz) | 1 ms | **[code]** `Config/Run.luau:78-80` |
| **Total** | **≤ 17 ms par tick**, Heartbeat serveur stable à 60 Hz | Heartbeat plafonné à 60 Hz ([Identify](https://create.roblox.com/docs/performance-optimization/identify)) |

Mémoire serveur : un serveur de 4 joueurs a droit à 6,25 Gio + 400 Mio. Roblox conseille de rester sous 50 %, soit environ 3,3 Gio ([Identify](https://create.roblox.com/docs/performance-optimization/identify)). COHUE garde les ennemis en tableaux, sans Instance serveur : budget **[hypothèse]** de 600 Mo, très loin de la limite.

Règle du contrat : aucune allocation par image dans les boucles chaudes (`ARCHITECTURE.md` §1). Voir PERF-04 pour les écarts actuels.

## 5. Mémoire client

Roblox ne publie pas de plafond mobile. Budget **[hypothèse]** pour un téléphone de 3 à 4 Go de RAM, où le système et l'appli Roblox prennent déjà une bonne part :

| Catégorie (onglet Memory de la console) | Budget | Remarque |
| --- | --- | --- |
| Total (`Stats:GetTotalMemoryUsageMb()`) | **≤ 1 200 Mo** en run, ≤ 900 Mo au lobby | relevé par le script A13-01 |
| GraphicsTexture | ≤ 250 Mo | textures ≤ 512×512, icônes ≤ 256×256 ([Improve](https://create.roblox.com/docs/performance-optimization/improve)) |
| GraphicsMeshParts | ≤ 150 Mo | mailles A01, une maille par espèce réutilisée en pool |
| LuaHeap | ≤ 150 Mo | |
| Sounds | ≤ 50 Mo | voir section 8 |
| Instances | ≤ 60 000 dans `Stats.InstanceCount` | pools compris (les pièces cachées comptent) |

Les pools du client ne rendent jamais leurs pièces (`EnemyRenderer.luau:197-213`, `WeaponFX.luau:344`) : la mémoire suit le pic de la run, pas la moyenne. C'est voulu (pas d'à-coups), mais le pic doit tenir dans le budget. Voir PERF-05.

## 6. Triangles et appels de rendu

Roblox ne donne pas de chiffre ; il conseille seulement le moins d'appels de rendu possible ([Improve](https://create.roblox.com/docs/performance-optimization/improve)). Budget **[hypothèse]**, lu dans `Stats.SceneTriangleCount` et `Stats.SceneDrawcallCount`, ou en Shift+F2 (Render Stats) :

| Élément | Triangles par modèle | Nombre à l'écran | Total |
| --- | --- | --- | --- |
| Ennemi de la nuée, LOD 1 (< 80 studs) | ≤ 500 | ~150 | 75 000 |
| Ennemi, LOD 2 (80 à 150 studs) | ≤ 150 (une pièce) | ~100 | 15 000 |
| Ennemi, LOD 3 (> 150 studs) | 12 (une plaque) | ~50 | 600 |
| Élite (anneau + couronne en plus) | ≤ 800 | ≤ 4 (`Config/Run.luau:113`) hors Overtime | 3 200 |
| Mini-boss | ≤ 3 000 | 1 | 3 000 |
| Boss | ≤ 8 000 | 1 | 8 000 |
| Compagnon | ≤ 1 500 | ≤ 8 | 12 000 |
| Avatar joueur + équipement de classe | ≤ 4 000 | 4 | 16 000 |
| Objet de butin (gemme, pièce) | ≤ 50 | ≤ 450 | 22 500 |
| Arme en pixel extrudé (24 à 32 px) | ≤ 1 500 après fusion des faces | 4 joueurs × 4 | 24 000 |
| Décor de la tuile visible | — | — | 120 000 |
| **Total à l'écran** | | | **≤ 300 000 triangles, ≤ 400 appels de rendu** |

Distances de LOD : **[code]** `EnemyRenderer.luau:34-36` (80 et 150 studs, hystérésis de 6). Les seuils de la DA (A01) et ceux du code doivent rester les mêmes.

Règles pour A01 et Clément :
- une espèce = une maille, avec un seul matériau et une seule texture (au plus 512×512) ;
- pas de `Highlight` par ennemi (déjà écarté, `EnemyRenderer.luau:5-7`) ;
- `CastShadow = false` sur tout ce qui est en pool (déjà fait, `EnemyRenderer.luau:114`).

## 7. Particules et effets

| Valeur | Chiffre | Origine |
| --- | --- | --- |
| Paliers de qualité des armes | Low / Medium / High : 60 / 150 / 300 projectiles visibles, 12 / 28 / 56 zones, particules × 0,5 / 0,8 / 1 | **[code]** `WeaponFX.luau:46-48` |
| Choix du palier | tactile sans clavier : Low si le petit côté de l'écran < 500, sinon Medium | **[code]** `WeaponFX.luau:166-171` |
| Effets d'attaque ennemie simultanés | 18 | **[code]** `EnemyAttackFX.luau:29` |
| Effets de compagnons simultanés | 48 | **[code]** `CompanionRenderer.luau:31` |
| **Budget de particules vivantes à l'écran** (palier Low) | **≤ 600**, dont ≤ 300 pour les armes, ≤ 150 pour les KO, ≤ 150 pour le reste | **[hypothèse]**, compté avec Shift+Ctrl+F1 à F5 (Debug Stats) |
| Rafale par KO | ≤ 6 particules, pas de lumière | **[hypothèse]** (à 20 KO par seconde : 120 particules) |
| `PointLight` dynamiques | 0 en Low, ≤ 8 en High | **[code]** `WeaponFX.luau:46-48` (`lights`) |
| Traînées (`Trail`) | 0 en Low | **[code]** idem |

A07 (VFX) cale ses modèles d'effets dans `Assets.FX` sur ces chiffres. Le mode « réduction des flashs » (`SettingsUI`) doit aussi baisser le nombre de particules.

## 8. Sons simultanés

Aucun son n'est encore joué dans le code (`grep` sur `Sound` dans `client/`, 5 nov.). A10 suit ces budgets **[hypothèse]** :

| Valeur | Chiffre |
| --- | --- |
| Sons joués en même temps (tous types) | ≤ 24 |
| Coups et KO de la horde | ≤ 8 voix, une instance `Sound` en pool par variante, au plus 1 nouveau départ par variante toutes les 50 ms |
| Musique | 1 piste (2 pendant un fondu de 2 s) |
| Ennemis spéciaux, boss, UI | ≤ 12 voix |
| Mémoire des sons chargés | ≤ 50 Mo (étiquette Sounds de l'onglet Memory, [Identify](https://create.roblox.com/docs/performance-optimization/identify)) |
| Durée d'un son court | ≤ 2 s ; boucles d'ambiance en streaming |

## 9. Comment on mesure

| Quoi | Outil | Source |
| --- | --- | --- |
| FPS client | Shift+F5, ou le script A13-01 (`tools/perf/HordeStressClient.client.luau`) | [Identify](https://create.roblox.com/docs/performance-optimization/identify) |
| Temps par image, par script | MicroProfiler | [MicroProfiler](https://create.roblox.com/docs/studio/microprofiler) |
| Mémoire par catégorie | Console (F9), onglet Memory | [Identify](https://create.roblox.com/docs/performance-optimization/identify) |
| Mémoire, CPU, GPU, réseau | Performance Stats (Ctrl+Alt+F7) | idem |
| Ping | Shift+F3 ; Server Stats dans la console | idem |
| Débit par remote | estimation du script A13-01 (comptage des ennemis dans les rayons d'intérêt) + `Stats.DataSendKbps` côté serveur | [Stats](https://create.roblox.com/docs/reference/engine/classes/Stats) |
| Triangles, appels de rendu | Shift+F2, `Stats.SceneTriangleCount`, `Stats.SceneDrawcallCount` | idem |
