# 50 — Classes, avatar et mouvement

Ce dossier détaille les sections 3, 7 et 10 de `01-decisions-v2.md` (qui prime sur `00-vision.md`). Ids en anglais, texte joueur en anglais.

**Deux propriétaires.** Les sections 2 et 3 (classes, équipement, trait) appartiennent à A04 (gameplay) et datent de la v1 : A04 les réécrit pour les 8 classes v2. Les sections 1, 4 à 9 (mouvement, caméra, contrôles, anti-triche) appartiennent à A06 et sont à jour au 4 nov. 2026.
Fichiers A06 : `shared/Config/Movement.luau`, `shared/NetDefs/Avatar.luau`, `server/Services/MovementGuard.luau`, `client/Controllers/{CameraController,InputController,MovementController,PlayerAnimator}.luau`.

## 1. Décisions (mouvement et caméra)

| Sujet | Décision | Pourquoi |
| --- | --- | --- |
| Modèle de mouvement | **Classique** : le client simule son personnage, le serveur vérifie (MovementGuard) | Décisions v2 §10 ; bunny-hop et glissade réactifs au pouce |
| Contrôleur | **Humanoid classique** + `LinearVelocity` (Plane) pour la glissade, `VectorForce` pour la gravité de classe. Pas de Character Controller Library | Les API Humanoid ne sont pas dépréciées ; la CCL ne gère pas encore les capacités maison |
| Saut | **Piloté par le code** : `Humanoid.JumpHeight` tenu à 0, l'action Jump lance la vitesse √(2 g h) | Contrôle exact du tampon, du coyote time et du bunny-hop ; maintenir Saut ne relance pas (sinon le bunny-hop n'a plus de skill) ; le bouton Saut Roblox par défaut se masque tout seul (JumpHeight 0) |
| Caméra | **3e personne Scriptable** haute et dézoomée, remplace la vue de dessus | Décisions v2 §7 ; lire la horde au pouce |
| Visée | Aucune : les armes tirent seules, la caméra sert à voir et à se déplacer | Décisions v2 §7 |
| Déplacement | Relatif à la caméra (contrôles Roblox par défaut, `CurrentCamera`) | Pas de fork du PlayerModule |
| Entrées | **Input Action System**, un contexte `Gameplay`, `Sink = false` | Une action pour clavier, manette et bouton tactile (`InputBinding.UIButton`) |
| Stats de mouvement | Viennent de la **classe** (`Config.Movement.Classes[classId]`, attribut serveur `ClassId`), jamais de l'apparence | Décisions v2 §3 ; même hitbox pour tous |
| Vitesse | Un seul écrivain de `WalkSpeed` : marche(classe) × stat MoveSpeed × bunny-hop × ralenti × contrecoup | Évite les buffs collés |

## 2. Les 10 classes (v1 — domaine A04, à réécrire pour les 8 classes v2)

Valeurs de base : `WalkSpeed` 16 studs/s, `JumpHeight` 7,2 studs (`UseJumpPower = false`). Arme de départ = ordre d'ARCHITECTURE 3. Passif = id de classe (implémenté par le domaine combat).

| id | FR / EN | Trait (point d'attache) | Arme de départ | WalkSpeed | JumpHeight | Mouvement spécial | Déblocage |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `Cornu` | Cornu / Horned | Cornes de bélier (`HatAttachment`) | `HacheBoomerang` | 16 | 7,2 | Glissade +40 % (`slideBoost` 1,4) | Free |
| `Plumeline` | Plumeline / Featherling | Ailes de plumes (`BodyBackAttachment`) | `PlumesDards` | 16 | 7,2 | Double saut (1 charge) + plané (chute max 8 studs/s en maintenant Saut) | Free |
| `Mecano` | Mécano / Tinker | Bras mécanique (`RightShoulderAttachment`) | `CleTourelle` | 17,6 (+10 %) | 5,5 (bas) | — | Free |
| `Felyne` | Félyne / Felyne | Oreilles (`HatAttachment`) + queue (`WaistBackAttachment`) | `GriffesEclair` | 16 | 7,2 | Bunny-hop permissif : fenêtre 0,25 s, gain sans rotation de caméra | `Q_Felyne` |
| `Rocailleux` | Rocailleux / Stoneback | Plaques de pierre (`LeftShoulderAttachment` + `RightShoulderAttachment`) | `PoingSeisme` | 14 | 6,5 | Immunisé au recul (attribut `KnockbackImmune`) | `Q_Rocailleux` |
| `Sporelin` | Sporelin / Sporeling | Chapeau-champignon (`HatAttachment`) | `NuageSpores` | 16 | 7,2 | — | `Q_Sporelin` |
| `Ecaille` | Écaille / Scaleling | Petites cornes (`HatAttachment`) + queue (`WaistBackAttachment`) ; mini-ailes (`BodyBackAttachment`) au stade 4 | `SouffleBraise` | 16 | 9,5 (haut) | — | `Q_Ecaille` |
| `Astrel` | Astrel / Starling | Antennes + couronne d'étoiles (`HatAttachment`) | `Meteorite` | 16 | 7,2 (apex réel ≈ 12 avec la gravité ×0,6) | Gravité basse ×0,6 (`VectorForce` client) | `Q_Astrel` |
| `Cristallin` | Cristallin / Crystalline | Cristaux (`LeftShoulderAttachment` + `RightShoulderAttachment`) | `EclatsPrisme` | 16 | 7,2 | — | `Q_Cristallin` |
| `Tentaculos` | Tentaculos / Tentaclos | 4 tentacules (`BodyBackAttachment`) | `FouetTentacule` | 16 | 7,2 | Escalade courte : 1,2 s à 14 studs/s en maintenant Saut face à un mur | `Q_Tentaculos` |

### 2.1 Stades du trait (niveaux de run 1 / 10 / 20 / 30)

Échelle de stade : **1,00 / 1,15 / 1,30 / 1,45** (`Config.Classes.StageScale`). Tailles données au stade 1, pour un avatar d'échelle 1.

| Classe | Stade 1 (niv. 1) | Stade 2 (niv. 10) | Stade 3 (niv. 20) | Stade 4 (niv. 30) |
| --- | --- | --- | --- | --- |
| Cornu | 2 cornes enroulées, 3 segments Ø 0,35, envergure ≈ 1,8 | Cornes plus longues (4ᵉ segment) | Anneaux lumineux (Neon) sur les cornes | Cornes en flammes (`Fire` aux pointes) |
| Plumeline | 2 ailes de 4 plumes, envergure ≈ 3,2, hauteur 1,6 | 5 plumes par aile | Plumes dorées | Ailes de lumière (Neon + `PointLight`) |
| Mecano | Épaulière + avant-bras + pince, longueur ≈ 1,6 | Pistons (2 cylindres) | 2ᵉ bras au-dessus | Bras doré à vapeur (`Smoke`) |
| Felyne | 2 oreilles 0,5 ; queue 4 segments ≈ 1,6 | Rayures sombres | Queue double | Pelage étincelant (`Sparkles`) |
| Rocailleux | 1 plaque d'ardoise 1,1 × 0,4 × 1,0 par épaule | Mousse (Grass) | Cristaux (Neon) | Armure de lave (CrackedLava + `PointLight`) |
| Sporelin | Chapeau Ø 1,6, hauteur 0,6 | Taches blanches | Spores flottantes (`ParticleEmitter` sans texture) | Chapeau géant (×1,3 en plus) lumineux |
| Ecaille | 2 petites cornes 0,5 ; queue 4 segments | Écailles (5ᵉ segment, Slate) | Crête (5 pointes) | Mini-ailes de dragon (dos) |
| Astrel | 2 antennes 0,8 + 1 étoile | 2 étoiles | 4 étoiles | Anneau galactique (Neon) + 4 étoiles |
| Cristallin | 1 cristal 0,4 × 0,9 par épaule | 2 cristaux | 3 cristaux | 4 cristaux + `PointLight` |
| Tentaculos | 4 tentacules de 3 boules (≈ 1,8) | 6 tentacules | Ventouses lumineuses | 8 tentacules |

Teintes : 3 teintes gratuites par classe (`tints`), index lu dans `profile.equipped.TraitTint` s'il vaut un nombre (domaine data, défaut 1). Échelles de stade et seuils de niveau : `Config.Movement.Trait` (Classes reste une table `{ [classId]: ClassDef }`, triable par `order`).

### 2.2 Déblocage (à coordonner avec le domaine data)

Gratuites : Cornu, Plumeline, Mecano (`unlock = "Free"`). Les autres : `unlock = "Q_<ClassId>"`. Les objectifs sont fixés par le domaine data (`70-donnees-progression-monetisation.md`, section Classes) ; rappel :

| Quête | Objectif (domaine data) |
| --- | --- |
| `Q_Felyne` | `Kills` ≥ 5 000 |
| `Q_Rocailleux` | `DamageTaken` ≥ 50 000 |
| `Q_Sporelin` | `ShrinesCompleted` ≥ 25 |
| `Q_Ecaille` | `BossesDefeated` ≥ 5 |
| `Q_Astrel` | `ChestsOpened` ≥ 100 |
| `Q_Cristallin` | `BestRunLevel` ≥ 30 |
| `Q_Tentaculos` | `FullBuildStageClears` ≥ 1 |

Le domaine avatar envoie en plus la clé `Hops` (`ProgressionService.recordStat(player, "Hops", 1)` par hop validé) pour de futures quêtes de mouvement.

Le serveur vérifie le déblocage (`ProgressionService.isUnlocked(player, "Class", id)`) ; jamais vendu en Robux.

## 3. Intégration du trait à l'avatar

- **Rig R15 forcé** dans les Avatar Settings (voir 7). Si le rig n'est pas R15, TraitService avertit et soude le trait à la main sur `Head` / `UpperTorso` / `Torso`.
- **Construction** : `Accessory` nommé `CohueTrait_<Classe>_<n>`, `Handle` invisible (0,2 stud, Massless, sans collision/requête/contact), une `Attachment` au nom du point d'attache dans le Handle, et des pièces `Part` soudées au Handle par des `Weld` (C0 explicite). Toutes les pièces : `Massless`, `CanCollide/CanQuery/CanTouch = false`, `CastShadow = false`. Aucun id d'asset ; effets via `Fire`, `Smoke`, `Sparkles`, `PointLight`, `ParticleEmitter` sans texture.
- **Ajout** : côté serveur, `Humanoid:AddAccessory()` après `CharacterAppearanceLoaded` (timeout 6 s). On ne touche à aucun joint, aucune valeur d'échelle, aucune propriété d'apparence.
- **Échelle** : `s = StageScale[stade] × sAvatar`, avec `sAvatar` lu dans les `NumberValue` du Humanoid :
  - tête (`HatAttachment`) : `HeadScale`
  - épaules : `BodyWidthScale`
  - dos / taille : `(BodyHeightScale + BodyWidthScale) / 2`
  - borné à **[0,6 ; 1,6]**, 1 si la valeur manque. Les positions des attaches suivent déjà l'échelle du corps ; on n'échelonne que nos pièces.
- **Conflits** : pour chaque point d'attache du trait, les accessoires **rigides** du joueur (sans `WrapLayer`) qui ont une `Attachment` du même nom dans leur Handle sont masqués (Transparency = 1, valeurs d'origine mémorisées et restaurées). Rien d'autre n'est masqué. Les vêtements à couches ne sont jamais touchés.
- **Garder mon chapeau** : si `DataService.getProfile(player).settings.keepHat == true`, les accessoires en conflit sur `HatAttachment` restent visibles (le trait se superpose). Défaut : `false`.
- **Cycle de vie** : `applyClass` (stade 1) → `PlayerLeveledUp` (niv. 10/20/30) → `setTraitStage` reconstruit le trait (jamais de régression de stade) → `clear` à `RunEnded` et au départ du joueur. À la réapparition (`CharacterAdded`), le trait de la classe active est ré-appliqué au stade courant.
- **Attributs serveur** posés sur le `Player` : `ClassId` (string), `TraitStage` (1-4), `KnockbackImmune` (bool). Le client lit `ClassId` pour ses réglages de mouvement.
- **Hitbox** : identique pour tous (Avatar Settings → Collision : Single Collider). Les stats de mouvement viennent de la classe, jamais de l'apparence.

## 4. Mouvement (client, `MovementController`)

Tous les nombres sont dans `shared/Config/Movement.luau`. Base : marche **16** studs/s, saut **7,2** studs.

### 4.1 Saut, bunny-hop, saut tampon

| Mécanique | Valeur | Détail |
| --- | --- | --- |
| Saut | √(2 g h) vers le haut | `ChangeState(Jumping)` + vitesse ; g tient compte de la gravité de classe |
| Saut tampon | **0,12 s** | Saut pressé en l'air juste avant l'atterrissage → saut à l'atterrissage. Pour le Rogue, un appui à moins de 0,12 s du sol est un tampon, pas le double saut |
| Coyote time | **0,10 s** | Saut encore permis après avoir quitté un rebord sans sauter |
| Bunny-hop : fenêtre | **0,15 s** | Relance dans les 0,15 s après l'atterrissage = hop réussi |
| Bunny-hop : gain | **+3 % par hop**, plafond **+60 %** | 20 hops parfaits pour le plafond (≈ 11 s de chaîne). Le hop ne compte que sur un **appui neuf** (maintenir Saut ne relance pas) et si la vitesse au sol est ≥ **70 %** de la marche (pas de gain contre un mur) |
| Bunny-hop : perte | Bonus à 0 | Au sol plus de 0,15 s (hors glissade), ou sans entrée de déplacement |
| Vitesse au plafond | **25,6** studs/s | Marche 16 × 1,6. Mesuré en jeu : 22 hops, 275 studs parcourus |

La règle « la caméra doit tourner de 8° pendant le saut » de la v1 est supprimée : au pouce, le pouce droit tape Saut, il ne peut pas tourner la caméra en même temps. Le plafond de skill vient de la fenêtre de 0,15 s, de l'appui neuf et des combos glissade.

### 4.2 Glissade et glissade en pente

| Mécanique | Valeur | Détail |
| --- | --- | --- |
| Départ | Au sol, vitesse ≥ **6** studs/s ou direction au stick | Vitesse = max(vitesse actuelle, marche actuelle) × **1,2**, plafonnée |
| Frottement | **12** studs/s² au plat | Glissade au plat : 19,2 → 8,8 studs/s en 0,87 s (mesuré) |
| Pente | + g × **0,6** × sin(pente) vers le bas | Pente de 24° : 19 → 35 studs/s en 0,8 s (mesuré) |
| Plafond | **2,2 ×** la marche de base | 35,2 studs/s |
| Fin | Vitesse < 0,55 × marche, 1,6 s sans pente, 0,3 s en l'air, ou relâchement | Tactile : un appui lance toute la glissade (relâcher ne l'arrête pas), un 2ᵉ appui l'arrête |
| Braquage | 2,5 /s vers le stick | Relatif à la caméra |
| Recharge | **0,35 s** entre deux glissades | |
| Glissade tampon | **0,15 s** | Glisser pressé ou maintenu à l'atterrissage → glissade à l'atterrissage (enchaînement hop → glissade) |
| Glissade → saut | Bonus = bonus d'entrée + (vitesse − vitesse de départ) / marche, + 3 % si l'élan est gardé | Au plat, ça conserve le bonus (le boost de départ ne compte pas, sinon glisser-sauter remplacerait le timing). En bas de pente, ça convertit l'élan : 35 studs/s → +60 % d'un coup (mesuré). Grâce de **0,2 s** après la fin de la glissade |

### 4.3 Mouvement par classe (ids de `01-decisions-v2.md` §3)

`Config.Movement.profile(classId)`, lu par le client et par MovementGuard. Les nombres de base et les drapeaux viennent de `Config/Classes` (A04 : `walkSpeed`, `jumpHeight`, `airJumps`, `glide` + `glideSeconds`, `heavyLanding`, `slideBoost`) ; `Config.Movement.Classes` n'ajoute que les réglages fins (vitesse de plané, contrecoup, gravité, frottement de glissade). Une classe inconnue reçoit le profil normal. Les valeurs ci-dessous sont celles d'A04 au 4 nov.

| Classe | Profil | Mesuré en jeu |
| --- | --- | --- |
| `Knight`, `Cleric`, `Tamer` | Normal | Saut 7,1 studs, glissade 0,87 s / 12 studs |
| `Archer` | Saut haut : **10** studs | (11 mesuré avec l'ancien réglage) |
| `Rogue` | Marche **17**, double saut : 1 saut en l'air à 90 % de la hauteur, rechargé au sol | 13,4 studs au total |
| `Mage` | Plané court : Saut maintenu en descente, chute max **6** studs/s pendant **1,2 s** par saut | Vol de 1,17 s au lieu de 0,54 s |
| `Guardian` | Lent : marche **14**, saut **6,5**, gravité **×1,2**. Atterrissage lourd après **8** studs de chute : marche ×0,6 pendant 0,25 s, onde au sol, secousse de caméra | Saut 6,4 studs, vol 0,43 s ; chute de 13 studs → atterrissage lourd côté client et `HeavyLandAt` côté serveur |
| `Barbarian` | Glissade qui charge : boost **1,6**, frottement **6**, fin à 0,5 × marche, 2,2 s au plat, plafond 2,4 ×, braquage 4. Attribut serveur `SlideCharge` | 2,2 s / 36,6 studs (boost 1,45) |

Les passifs liés au mouvement (Shadowstep du Rogue : 0,5 s d'invulnérabilité en glissade ; dégâts de charge du Barbarian ; onde de choc du Guardian) sont du gameplay, donc chez A04 : ils lisent les attributs serveur `Sliding`, `SlideCharge` et `HeavyLandAt`.

### 4.4 Autres règles

| Mécanique | Valeur | Détail |
| --- | --- | --- |
| Ralenti (choix de carte) | `SlowMult` tant que `GetServerTimeNow() < SlowUntil` | Attributs posés par RunManager |
| Stat MoveSpeed | × (1 + `stats.MoveSpeed`) | Remote `Build` |
| Dégâts de chute | Aucun | `FallingDown` et `Ragdoll` désactivés côté client |
| Onde d'atterrissage | Chute ≥ **18** studs | Anneau Neon local (0 → 12 studs en 0,35 s), secousse légère ; 3 anneaux en pool |

### 4.5 Poses du joueur (`PlayerAnimator`, A06-06 partiel)

Poses procédurales posées par-dessus l'Animator (Transform des articulations en PreSimulation, Motor6D ou AnimationConstraint), visibles par tous les joueurs, sans asset à publier :

| Pose | Déclencheur | Forme |
| --- | --- | --- |
| Glissade | `isSliding()` en local, attribut serveur `Sliding` pour les autres | Buste penché de 62° en arrière, bassin abaissé de 1,35 stud, jambes devant, bras écartés |
| Charge (Barbarian) | `Sliding` + `SlideCharge` | Penché de 24° vers l'avant, accroupi |
| Atterrissage lourd | Local à l'atterrissage, `HeavyLandAt` pour les autres | Accroupi bref (0,32 s) |

Pas encore faits : les 5 gestes d'attaque (taille, tir à l'arc, sort, lancer, frappe au sol) et le geste de capture. Ils demandent des clips keyframés (skill `make-anim`, à publier par Clément) et un signal client « telle arme tire pour tel joueur » côté A04.

**Signaux au serveur** (remote `MoveEvent`, C→S, 10/s) : `SlideStart`, `SlideEnd`, `Hop`, `HopReset`. Le serveur les valide et pose des attributs **serveur** sur le Player (lecture seule ailleurs) : `Sliding` (expire seul après 2,5 s), `SlideCharge`, `HopChain`, `Airborne` (rayon serveur à 4 Hz), `HeavyLandAt` (`GetServerTimeNow` du dernier atterrissage lourd). MovementGuard compte aussi `ProgressionService.recordStat(player, "Hops", 1)`.

## 5. Caméra 3e personne (client, `CameraController`)

| Réglage | Valeur | Détail |
| --- | --- | --- |
| Type | Scriptable, RenderStep Camera + 1 | Le module caméra Roblox ne fait plus rien ; le déplacement reste relatif à `CurrentCamera` |
| Distance | **32** studs (zoom 14 à 48) | Testé avec 217 ennemis : la horde se lit jusqu'au fond, l'anneau autour du joueur reste visible |
| Angle | **42°** sous l'horizon (8° à 70°) | 30° montre plus loin mais les ennemis du premier plan cachent le joueur ; 46° tend vers la vue de dessus |
| Visée | 2,5 studs au-dessus du HumanoidRootPart, caméra avancée de 5 studs | Le joueur est un peu sous le centre : plus d'espace devant |
| Suivi | Horizontal 20, vertical 8 (lissage exponentiel avec dt) | Les sauts ne secouent pas l'image |
| FOV | **70**, +8 avec la vitesse | Un seul propriétaire du FOV |
| Tactile | Glissé d'un doigt sur la **moitié droite** : 260° par hauteur d'écran (vertical × 0,6). Pincement à deux doigts = zoom | Doigt posé sur un bouton ou le joystick ignoré (`gameProcessed`) ; moitié gauche = déplacement |
| Souris | Clic droit maintenu : 0,3°/pixel, curseur verrouillé. Molette = zoom | Delta d'événement, repli sur l'écart de position |
| Manette | Stick droit (action `Look`) : 220°/s, 120°/s en vertical, zone morte 0,15, courbe ², gâchettes hautes = zoom | |
| Clavier | Flèches gauche / droite : 150°/s ; I / O = zoom | |
| Recentrage | Tactile et manette : après 1 s sans toucher la caméra, en courant vers l'avant (< 75°), à 1,2 /s | Pas de spirale en courant de côté |
| Sensibilité | `CameraController.setSensitivity(0,25 à 3)` | Sensibilité du jeu ; celle de Roblox n'est pas lue (elle valait 0,2 sur le compte de test et rendait la caméra 5 × trop lente) |
| Murs | Spherecast rayon 0,6 depuis la tête, marge 0,3, minimum 2 studs ; entrée immédiate, sortie lente (4 /s) | Mur de test à 10 studs derrière : 28,5 → 12,4 studs, reste du bon côté, ressort en 1,5 s |
| Obstacles fins | Ignorés si leur 2ᵉ plus grande dimension ≤ **3** studs (troncs, poteaux) | Un tronc qui passe ne fait pas sauter le zoom |
| Estompage | Personnage local transparent sous **5** studs de caméra | |
| Secousse | `CameraController.shake(force, durée)` : 1,6° max, recalculée chaque image | Ne dérive jamais |

API : `getYaw()`, `setEnabled(on)` (off = caméra Roblox `Custom`, pour une cinématique), `setSensitivity(mult)`, `setDistance(studs)` / `getDistance()`, `setPitch(deg)` / `getPitch()`, `shake(force, durée?)`.

## 6. Contrôles et Input Action System (`InputController`)

Contexte `Gameplay` (Priority 1000, `Sink = false`) dans `ReplicatedStorage/CohueInput`, créé par le client. Une `InputAction` par action.

| Action | Clavier / souris | Manette | Tactile |
| --- | --- | --- | --- |
| `Jump` | Espace | A | Bouton Saut (MobileButtons, A08) |
| `Slide` | Maj gauche, Ctrl gauche, C | B, R2 | Bouton Glisser (A08) |
| `Capture` | F | X | Bouton Capture (A08, vague 2) — action prête, personne ne l'écoute encore |
| `Ultimate` | E | Y | Bouton Ultime (A08) |
| `Card1` à `Card3` | 1 / 2 / 3 (pavé aussi) | Croix gauche / bas / droite | Toucher la carte (CardUI) |
| `Ping` | G, clic molette | Croix haut | Appui long mini-carte (PingUI) |
| `CameraLeft` / `CameraRight` | Flèches gauche / droite | — | — |
| `ZoomIn` / `ZoomOut` | I / O | R1 / L1 | Pincement |
| `Look` (Direction2D) | — | Stick droit | Glissé moitié droite (UserInputService) |

API : `onAction(name, fn)`, `isDown(name)`, `bindButton(name, button)` (méthode pour l'UI), `trigger(name, pressed)`, `getHint(name)` (texte de la touche pour l'appareil courant), `getVector(name)`, `getContext()`, `setEnabled(on)`. Règle tactile : l'action part à l'appui.

## 7. Anti-triche mouvement (`MovementGuard`, serveur)

Échantillon toutes les **0,25 s**, déplacement **horizontal** seulement. Le serveur ne lit jamais `Humanoid.WalkSpeed` : il suit lui-même la vitesse plausible.

| Contrôle | Règle |
| --- | --- |
| Marche | marche(classe) × (1 + MoveSpeed serveur) |
| Bunny-hop | +3 % par `Hop` reçu si le serveur a vu le joueur en l'air (≤ 1,2 s) puis au sol (≤ 0,3 s, ou rayon au moment du Hop), au plus un hop par **0,4 s** ; perdu après 0,7 s au sol ou sur `HopReset`. `HopChain` et la stat `Hops` ne comptent que ces hops validés |
| Glissade | Vitesse suivie : départ = vitesse permise × boost de classe × 1,1 ; gain de pente seulement si le rayon serveur voit une pente (gain × 1,5) ; frottement × 0,5 au plat ; plafond de classe. Fin de glissade : crédite le bonus d'entrée + la part gagnée en pente (le hop du saut arrive par `Hop`). `SlideStart` toujours mis en attente (0,5 s) puis accepté dès que le serveur voit : sol, vitesse mesurée ≥ 4,8 studs/s, 0,35 s depuis la fin de la précédente, 0,4 s depuis le début de la précédente. `SlidePose` et `SlideCharge` à chaque glissade acceptée ; l'attribut de gameplay `Sliding` (Shadowstep) une fois par 1,5 s (S-08). Un saut de glissade n'est crédité, et son élan permis, que si le serveur voit le joueur décoller dans les 0,5 s. Gain de pente seulement en descendant (× cos avec la pente), frottement toujours appliqué, gain plafonné. Après la fin, la vitesse de glissade ne reste permise que si un `Hop` suit dans les 0,35 s. Une glissade ne garde la chaîne de hops que si elle part juste après un saut, et au plus `maxFlatTime` + 0,3 s : enchaîner des glissades au sol ne la prolonge pas |
| Seau percé | permis = vitesse × **1,06** × temps + **0,6** stud ; excès cumulé − **1,5** stud/s ; au-delà de **20** studs + vitesse × ping → recalage (le ping agrandit le seau une fois, pas chaque pas). A11 proposait marge 1,2 et fuite 8 : un hack ×1,5 passerait, d'où ces valeurs plus serrées, à revalider sur téléphone |
| Ralentis | `SlowMult` tant que `SlowUntil` n'est pas passé : appliqué aussi à la vitesse permise (S-14) |
| Vertical (S-01) | Montée par échantillon ≤ vitesse de saut de la classe × 1,2 × temps + 1 stud ; plus de **12** studs au-dessus de `Heightmap.getY` pendant plus de **2 s** sans appui (sphère sous le joueur, coéquipiers compris) → recalage |
| Gel réseau | Si le serveur ne voit plus bouger le joueur (< 0,2 stud) alors que sa vitesse répliquée dépasse 2 studs/s, le rattrapage suivant est permis à hauteur de cette vitesse × temps gelé (≤ 0,75 s), seulement dans sa direction ; au-delà de 5 studs d'excès, strike immédiat |
| Seau à crédit | Un pas plus court que permis laisse un crédit d'au plus 0,5 s de course : les positions répliquées arrivent par paquets (mesuré sous 150 ms de latence simulée) |
| Tremplins | 2,5 s de vitesse relevée à 30 studs/s près d'un tremplin du plan ; pas une exemption : téléport et seau restent contrôlés |
| Téléport | Un pas > max(**45**, vitesse max possible × (temps + ping) × 2,5) → recalage immédiat |
| Vol stationnaire | 3,5 s en l'air avec moins de 2 studs d'amplitude et sans appui, ou monté de plus que les sauts de la classe + 8 studs → recalage (`HoverEnforce = true`) |
| Recalage | `PivotTo` de la dernière position valide au sol, vitesse annulée, 0,6 s + ping de grâce. Jamais de kick |
| Exemptions et grâces | `MovementGuard.exempt(player, s, raison?)` ou attribut `MoveExemptUntil` : le déplacement que le serveur impose juste après est accepté une fois et devient l'ancre ; pendant 0,5 s + ping, les positions du client encore en vol sont acceptées seulement près de l'ancienne position. Ensuite, distance à l'ancre ≤ vitesse max × temps × 1,2 + 12 studs. Grâces d'apparition (3 s) et de recalage (0,6 s + ping) : distance à l'ancre ≤ vitesse normale × 1,06 × temps + 0,6 stud, sans portée de lancement (S-02, suivi A11) |
| Temps en l'air | Plus de 4 s sans sol ni appui (hors tremplin, hors trajet imposé par le serveur) → recalage |
| Strikes par run | `MovementGuard.getRunStrikes(player)`, par UserId, remis à 0 sur `Bus.RunStarted`, survit aux réapparitions et aux reconnexions. `MovementGuard.getLastValidPosition(player)` donne la dernière position valide (reset de A04) |
| Remote | `MoveEvent` à 5/s (regles-v2 §0.3) ; un saut de glissade n'envoie pas `SlideEnd` ; `SlideStart` et `Hop` ignorés pour un joueur à terre |

**Mesures en jeu (Studio, 4 nov.)**

| Scénario | Résultat |
| --- | --- |
| 22 hops légitimes jusqu'à +60 % (25,6 studs/s) | 0 recalage, pic du seau 1,1 / 20 |
| Glissade en pente (35 studs/s) → saut → 10 hops à +60 % | 0 recalage, pic du seau 0 |
| Tests de classe (double saut, plané, atterrissage lourd, charge) | 0 recalage, aucun log « vol » |
| Hack CFrame à 40 studs/s (×2,5) | Recalé en ~1,6 s, à répétition |
| Hack +10 studs/s pendant un bunny-hop | Recalé (2 fois en 9 s) |
| `SlideStart` envoyé en boucle + hack +15 au plat | Recalé (2 fois en 7 s) |
| Hack ×1,5 au sol (24 studs/s) | Recalé en ~6 s |
| Téléport de 70 studs | Recalé immédiatement |
| `SlideEnd` + `SlideStart` toutes les 0,5 s + hack +15 au plat (après correctifs) | Recalé 2 fois en 10 s |
| Immobile 2 s puis clignement de 30 studs (après correctifs) | Recalé (seau 24,7 / 20) |
| 22 hops légitimes après correctifs | 0 recalage, seau 0 |
| Pente 24° (35 studs/s) → saut → hops, après correctifs | 0 recalage, pic du seau 6,1 / 20 (le serveur voit la pente à 4 Hz et prend un peu de retard pendant l'accélération) |

Limite connue : un tricheur qui reste sous ≈ +25 % de la vitesse permise n'est pas recalé (c'est la marge qui protège les joueurs légitimes sur réseau mobile). Mesuré en Studio sans latence : à revalider sur téléphone en 4G (A11-06).

## 8. Réglages de place à faire à la main (chef de projet)

1. `StarterPlayer.EnableMouseLockOption = false` : Maj sert à glisser ; sinon Maj bascule aussi le verrouillage de la souris.
2. Avatar Settings : R15, Collision **Single Collider** (même hitbox pour tous), Abilities **Legacy Humanoid** (pas de CCL).
3. `StarterPlayer.CharacterUseJumpPower = false` (déjà le cas). `CharacterJumpHeight` peut rester à 7,2 : MovementController le remet à 0 côté client.
4. `Workspace.PlayerScriptsUseInputActionSystem` : laisser par défaut ; ne pas forker le PlayerModule.

## 9. Sources vault

fwjelaa : *Camera Systems* §4 (caméra d'épaule Scriptable, Spherecast depuis le pivot), §7 (tactile, manette, zoom), §8 (lissage exponentiel avec dt, un seul propriétaire du FOV) ; *Camera Obstruction Handling - Occlusion Modes, Fades and Collision* (Spherecast rayon 0,5 à 1, entrée immédiate / sortie lente, petits obstacles exclus) ; *Touch Gestures - Pinch, Pan, Swipe and Long Press* (ratio de pincement depuis le début, seuils à l'échelle de l'écran) ; *Input - UserInputService and ContextActionService* §5 (InputContext / InputAction / InputBinding, `UIButton`, `GetState()` pour l'analogique) ; *Server Authority and Input Migration 2026* (bascule IAS des scripts joueur début 2027, ne pas forker sans désactiver le PlayerModule).
LihFolk (v1, toujours valables) : *Custom Character Controllers*, *Input Responsiveness Buffering and Coyote Time*, *Mover Constraints and Physics Controllers*, *Exploits and Anti-Cheat*, *Detecting Movement Exploits - Speed Fly Noclip Teleport*.
