# COHUE — Décisions v2 (4 nov. 2026)

Ce fichier **remplace** `00-vision.md` partout où les deux se contredisent. Il vient des réponses de Clément au questionnaire du 4 novembre. Suivi de production : [doc de suivi](https://claude.ai/artifact/TeTgv75umKcz4qGmxowwws).

## 1. Le cœur du jeu

Le pilier, c'est la boucle survie + XP : tuer → ramasser l'XP → choisir une carte (nouvelle arme, compétence, vitesse d'attaque…) → tuer plus vite → grimper dans le **classement hebdo du plus grand nombre de KO en une run**. Tout le reste sert cette boucle.

- Public 9-15 ans, **mobile d'abord**, solo + coop jusqu'à 4.
- **Anglais seul au lancement** : tout texte visible par le joueur est en anglais. Le dossier et les commentaires restent en français.
- Le jeu doit **rapporter des Robux**, avec une monétisation **100 % cosmétique**.
- COHUE reste un **nom de travail** : il faut un nom anglais avant le lancement.
- On reprend des **mécaniques** de Megabonk et PokeBonk, jamais leurs noms, créatures, visuels ou sons.

## 2. Structure d'une run

| Étape | Règle |
| --- | --- |
| Lobby | Hub 3D voxel : présentoirs de classes, enclos des compagnons capturés, boutique, tableaux de classement, file solo / amis / public |
| Monde 1 → 2 → 3 | **À confirmer** : une run enchaîne les 3 mondes. Chrono de 10:00 par monde. Le boss tué ouvre le portail du monde suivant |
| Overtime | À 0:00, le compte à rebours devient un **chronomètre qui monte** (+00:01, +00:02…). La difficulté monte sans plafond : toutes les 30 s, vitesse de spawn +15 %, PV ennemis +20 %, dégâts +10 %, part d'élites +3 points. Le boss reste tuable pour avancer |
| Après le boss du monde 3 | Bannière Victory, puis choix : **Cash out** (fin de run, gains sauvés) ou **Keep going** (Overtime infini pour farmer des KO) |
| Fin | Tous les joueurs morts, ou Cash out. Écran de fin : KO, dégâts par arme, gains, Play again |

**« Aucun ennemi max »** : côté joueur, la horde ne plafonne jamais. Côté technique, le serveur garde une limite d'ennemis vivants simultanés (≈ 300, à mesurer par l'agent Perf). Une fois la limite atteinte, l'escalade passe par des ennemis plus forts (PV, dégâts, élites) au lieu d'ennemis en plus. Le joueur ne voit pas la différence, le téléphone ne crashe pas.

**KO** : comptés par le serveur uniquement, par joueur. Classement hebdo (reset lundi 00:00 UTC) + all-time, visibles dans le lobby et sur l'écran de fin. Disponibles **dès le lancement**.

## 3. Classes classiques sur l'avatar du joueur

L'avatar Roblox du joueur reste intact. La classe ajoute un **équipement voxel** visible (casque, cape, carquois…) qui grandit aux niveaux 10, 20 et 30 de la run. Les stats viennent de la classe, jamais de l'apparence.

| Classe (EN) | Arme de départ | Passif | Mouvement | Déblocage |
| --- | --- | --- | --- | --- |
| Knight | Broadsword (arc de taille devant soi) | Valor : +1 % dégâts par ennemi à moins de 10 studs (max 30 %) ; parade d'un coup toutes les 8 s | Normal | Gratuit |
| Archer | Longbow (flèches auto qui transpercent) | Eagle Eye : +critique sur les cibles à plus de 20 studs | Saut haut | Gratuit |
| Mage | Fire Staff (boule de feu à zone) | Arcane Surge : +2 % zone par niveau ; une carte rare garantie toutes les 5 | Plané court | Gratuit |
| Guardian | Quake Hammer (onde de choc au sol) | Bulwark : +3 armure par niveau, renvoie 30 % des dégâts de mêlée, immunisé au recul | Lent, atterrissage lourd | Quête |
| Rogue | Throwing Daggers (éventail) | Shadowstep : la glissade donne 0,5 s d'invulnérabilité ; +esquive | Double saut | Quête |
| Cleric | Holy Aura (aura de dégâts) | Blessing : l'aura soigne les alliés ; relève 2× plus vite | Normal | Quête |
| Barbarian | Spinning Axes (orbite) | Rage : jusqu'à +50 % dégâts quand les PV baissent | Charge en glissade | Quête |
| Tamer | Beast Whip (balayage 360°) | Pack Leader : 2 compagnons à la fois, capture 50 % plus rapide, compagnons +20 % dégâts | Normal | Quête |

Les classes ne sont **jamais vendues** en Robux. Les chiffres sont des points de départ pour l'agent Gameplay.

## 4. Armes, Runes, objets, cartes

- **16 armes** : les 8 de départ ci-dessus + 8 du pool commun (Lightning Chain, Frost Nova, Boomerang, Bomb Bag, Spear Throw, Meteor Rain, Orbiting Blades, Crossbow Turret). Toutes équipables par toutes les classes. 4 emplacements.
- **14 Runes** (les « grimoires » de la v1, renommés) : Damage, Attack Speed, Projectiles, Area, Duration, Cooldown, Crit, Luck, Wisdom (XP), Magnet, Vitality, Armor, Agility, Cursed (plus de difficulté contre plus de butin). 4 emplacements, jusqu'à 6 en méta.
- **40 objets** en 4 raretés (Common, Rare, Epic, Legendary), trouvés dans les coffres.
- **Fusion** (proposée, à confirmer) : une arme au niveau 8 + une Rune précise au niveau 5 se transforme en version ultime. Exemple : Longbow + Rune Attack Speed → Storm Bow.
- **Cartes de niveau** : 3 choix, rareté visible. En coop, pas de pause : 8 s pour choisir, joueur ralenti et invulnérable. Bannir / Passer / Relancer limités par run.
- **Autels** : on garde ceux de `00-vision.md` section 8.4.

## 5. Compagnons : on les bat, on les capture

Pas d'évolution. Un compagnon se gagne en le **battant puis en le capturant** pendant une run.

1. Certains ennemis sont **Capturables** : variante marquée (aura + icône), plus résistante. Toutes les espèces de base, les élites et les mini-boss peuvent avoir une variante capturable. Les boss ne le sont pas au lancement.
2. Battu, il laisse une **cage de capture** au sol pendant 10 s.
3. Le joueur reste dedans 2 s sans être touché → capture réussie à 100 %. Pas de hasard, pas d'objet payant.
4. La créature rejoint la **collection** (sauvée en méta). Avant une run, le joueur équipe 1 compagnon (2 pour le Tamer). Il attaque seul et suit le joueur.
5. Chaque espèce a son attaque et ses cartes de technique. Pas de renommage.
6. **Personnalisation en Robux** : chapeaux, couleurs, auras, effets. Purement visuel.

## 6. Mondes, ennemis, boss

| Monde (nom de travail) | Ennemis | Mini-boss | Boss |
| --- | --- | --- | --- |
| 1. Bois Grognon (forêt) | Gobelins (grunt, archer, shaman, bomber) + faune de la forêt (on peut garder Gland Grincheux, Champignon Sauteur, Hibou Plongeur) | Chef gobelin ou Souche géante | Grand Chêne Ronchon (modèle existant) |
| 2. Cimetière / marais (nouveau) | Zombies (shambler, runner, bloater, gravedigger) | Ogre zombie | À créer |
| 3. Récré Fantôme (école hantée) | Fantômes (wisp, poltergeist qui lance des objets, banshee, armure hantée) | Le Pion Spectral | La Directrice Éternelle |

- Ton : **humour absurde** (zombie en tutu, gobelin qui vole ton XP, fantôme de surveillant).
- **Boss simples** : gros PV, 2 à 3 attaques lisibles annoncées 1 s avant (cercle au sol), tués avec ses attaques. Pas de phase d'escalade sur le boss.
- **Cartes semi-procédurales** (proposé) : chaque monde est fait de tuiles voxel faites main, assemblées différemment à chaque run, avec l'arène du boss et le point d'apparition fixes.

## 7. Direction artistique

- **Voxel**, **palette vive et saturée**, humour absurde.
- Références de Clément : Megabonk (silhouettes trapues, lisibilité de la horde), Octopath Traveler (effet diorama, profondeur de champ, bloom, lumière chaude), Steal an Egg (Roblox, ton joyeux). Synthèse : **un diorama voxel bien éclairé**. On s'inspire de l'ambiance, on ne copie aucun visuel.
- Caméra **3e personne** derrière le joueur (remplace la vue de dessus actuelle), dézoomée pour lire la horde, jouable au pouce.
- **UI glossy cartoon** : maquettes Figma validées par Clément avant toute intégration.
- Outils : Blender (accès donné par Clément), Meshy (**budget de crédits illimité accordé par Clément le 4 nov.**), LihFolk Asset Pack, skills fwjelaa (`make-model`, `make-map`, `make-anim`).

## 8. Son

Clément n'a ni musique ni voix. Musiques et sons viennent de la **bibliothèque audio sous licence du Creator Store** (gratuite, utilisable dans les jeux). Chaque id est noté avec sa source. Les cris des créatures sont des sons de la bibliothèque, retravaillés (pitch, couches).

## 9. Monétisation (100 % cosmétique)

Skins d'équipement de classe, personnalisation des compagnons, effets de KO, traînées, emotes, poses de victoire, pass VIP (cosmétique + serveur privé), pass saisonnier cosmétique. Interdit : stats payantes, résurrection payante, produits aléatoires payants, classes payantes. Règles de reçus : `00-vision.md` section 11.3.

## 10. Technique et anti-triche

- Mouvement **calculé par le client, vérifié par le serveur** (mode classique, MovementGuard).
- Mouvement **essentiel** : bunny-hop, glissade, glissade en pente, saut tampon, compatibles tactile.
- Tout ce qui compte (dégâts, XP, KO, pièces, captures, déblocages, classements) est calculé par le serveur.

## 11. Code existant : ce qu'on garde

| Module | Décision | Raison |
| --- | --- | --- |
| `shared/Net`, `Registry`, `Signal`, `Types`, `server/Bus`, les deux `Main` | Garder | Socle propre (rate limit, registre, bus) |
| `EnemyService`, `EnemyCodec`, `EnemyRenderer`, `Heightmap` | Garder, adapter | Réplication binaire de la horde : c'est la partie la plus dure, elle est faite. À adapter à l'Overtime et aux capturables |
| `StatsService`, `CardService`, `WeaponService`, `PassiveService`, `WeaponFX` | Garder, adapter | Le moteur de build marche ; on change le contenu (armes, Runes, passifs) |
| `RunManager`, `StageService` | Adapter | Ajouter les 3 mondes enchaînés, l'Overtime, le Cash out, le compteur de KO |
| `LootService`, `ShrineService`, `LootRenderer`, `ShrineFX` | Garder | Inchangés par les nouvelles décisions |
| `DataService`, `ProgressionService`, `MonetizationService`, `MatchService` | Garder, adapter | Ajouter la collection de compagnons, les classements hebdo, la boutique cosmétique |
| `MovementController`, `MovementGuard`, `InputController` | Garder | Le mouvement reste client + vérif serveur |
| `CameraController` | Remplacer | Vue de dessus → 3e personne |
| `TraitService`, `Config/Classes` | Remplacer | Traits physiques → équipement voxel des 8 classes classiques |
| `CompanionService`, `Config/Companions`, `CompanionRenderer` | Refaire | Évolution → capture et collection |
| `Config/Weapons`, `Grimoires`, `Enemies`, `Worlds`, `Bosses`, `Cosmetics`, `Products` | Réécrire le contenu | Nouveaux thèmes, textes en anglais |
| `client/Controllers/UI/*` | Garder la logique, refaire le look | Style glossy cartoon d'après les maquettes Figma |
| `assets/creatures/*` | Garder au cas par cas | Grand Chêne et faune de la forêt réutilisables ; les anciens compagnons Braise / Marée / Ronce sortent du jeu, sauf si l'agent DA les juge bons comme capturables de la forêt |

## 12. Rien n'est construit par script (4 et 5 nov. 2026)

Le 4 nov., Clément a posé la règle pour la 3D. Le 5 nov., il l'a étendue à l'UI et aux effets (« Oui, tout »). Tout ce que le joueur voit existe comme objet dans la place COHUE, visible et modifiable dans Studio. Les scripts clonent ces modèles et les pilotent ; ils n'en fabriquent plus.

**Le code peut :**
- cloner un modèle, le parenter, le détruire ;
- changer ses propriétés : texte, couleur, position, taille, transparence, visibilité, CFrame ;
- l'animer avec des tweens.

Une liste répétée (cartes, lignes du classement, emplacements) se fait avec un modèle de ligne posé une fois et cloné N fois.

**Le code crée encore les objets invisibles :**
- les RemoteEvent et dossiers de `Net` ;
- les BindableEvent et BindableFunction ;
- les Attachment et contraintes physiques du mouvement ;
- InputContext, InputAction et InputBinding ;
- TeleportOptions ;
- les dossiers de rangement vides et la Camera d'un ViewportFrame.

**Où vivent les modèles :**

| Quoi | Où |
| --- | --- |
| Écrans (HUD, menus, fin de run) | `StarterGui` : un ScreenGui par écran, `ResetOnSpawn = false`, désactivé sauf le HUD |
| Pièces d'UI réutilisées (carte, bouton, ligne, pastille) | `ReplicatedStorage.Assets.UI` |
| Effets (armes, autels, attaques ennemies, pop d'équipement, onde d'atterrissage) | `ReplicatedStorage.Assets.FX` |
| Créatures, boss, compagnons | `ReplicatedStorage.Assets.Creatures` (mailles A01) |
| Équipement de classe | `ReplicatedStorage.Assets.Equipment` |
| Butin, autels, marqueurs de ping | `ReplicatedStorage.Assets.Props` |
| Sons | `ReplicatedStorage.Assets.Sounds` |
| Mondes de run | modèles posés dans COHUE (Workspace ou ServerStorage, choix de A02) |
| Lobby | `Workspace.HubbubVillage` (fait par A01) |

**À convertir** (relevé du 5 nov. dans `main` : les `Instance.new` qui fabriquent du visible) :

| Module | Ce qu'il fabrique aujourd'hui | Agent |
| --- | --- | --- |
| `UI/UITheme` et les écrans qui l'appellent : HUD, CardUI, CaptureUI, EndScreen, LoadoutUI, Minimap, MobileButtons, PingUI, SettingsUI, ShrineUI, VictoryBanner | toute l'UI (ScreenGui, cadres, textes, boutons) | A08 (A09 pour les menus) |
| `EnemyRenderer`, `BossRenderer` | ennemis et boss en Parts | A03, avec les mailles A01 |
| `CompanionRenderer` | compagnons en Parts | A05, avec les mailles A01 |
| `server/Services/TraitService` | équipement de classe (Accessory, Part, Fire, Smoke, Sparkles, lumière, particules) | A04, avec les modèles A01 |
| `server/Services/StageService` | le monde de run (sol, rampes, lumières, panneaux) | A02 |
| `WeaponFX` | effets des armes | A14 |
| `EnemyAttackFX`, `ShrineFX`, onde d'atterrissage de `MovementController` | effets | A07 |
| `LootRenderer` | butin (Part, ProximityPrompt) et sa fenêtre (BillboardGui) | A04 pour le butin, A08 pour la fenêtre |
| `DebugHud` | texte de debug | A08, en dernier |

Chaque agent convertit ses modules à son tour, un seul agent à la fois. Un module pas encore converti continue de marcher tel quel. Une fois converti, il ne fabrique plus rien : si un modèle manque, il le signale dans la sortie au lieu de le recréer.
