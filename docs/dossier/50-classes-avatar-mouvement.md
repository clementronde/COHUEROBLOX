# 50 — Classes, avatar et mouvement (domaine avatar)

Ce dossier détaille les sections 6, 10, 10.2 et 12.4 de `00-vision.md`. Les ids sont en anglais (ou les ids de `ARCHITECTURE.md` section 3), le texte joueur en `{ fr, en }`.
Fichiers du domaine : `shared/Config/{Classes,Movement}.luau`, `shared/NetDefs/Avatar.luau`, `server/Services/{TraitService,MovementGuard}.luau`, `client/Controllers/{InputController,MovementController}.luau`.

## 1. Décisions

| Sujet | Décision | Pourquoi |
| --- | --- | --- |
| Modèle de mouvement | **Classique** : le client simule son personnage, le serveur contrôle la plausibilité (MovementGuard) | ARCHITECTURE 1 ; bunny-hop et glissade maison faciles ; réactif sur mobile |
| Contrôleur | **Humanoid classique** + petites forces (`LinearVelocity` en mode Plane pour la glissade, `VectorForce` pour la gravité basse). **Pas** de Character Controller Library | La CCL (opt-in, 11 avril 2026) ne supportait pas les capacités personnalisées à sa sortie, et dans une place CCL `WalkSpeed` / `Jump` / `ChangeState` peuvent ne plus piloter le mouvement. Les API Humanoid ne sont pas dépréciées. À réévaluer quand la CCL supportera les capacités maison |
| Entrées | **Input Action System** (InputContext / InputAction / InputBinding), sortie complète juin 2026 | Une liaison clavier + manette + tactile par action ; `InputBinding.UIButton` relie un bouton UI à l'action |
| Scripts joueur par défaut | On garde les scripts par défaut (pas de fork). Notre contexte a `Sink = false` pour ne pas voler Espace / A au saut par défaut | Fork = casse à chaque mise à jour ; bascule IAS par défaut prévue début 2027 |
| Vitesse | Pile de multiplicateurs nommés côté client (Classe × Stat × Bunny-hop × Ralenti), un seul écrivain de `WalkSpeed` | Évite les buffs « collés » |
| Avatar | Jamais remplacé ni recoloré, pas de `ApplyDescriptionAsync`. Le trait = `Accessory` construit en code, ajouté par `Humanoid:AddAccessory()` côté serveur, après `CharacterAppearanceLoaded` | Garder l'identité du joueur ; appliquer sur un personnage complètement chargé |

## 2. Les 10 classes

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

Tous les nombres sont dans `shared/Config/Movement.luau`.

| Mécanique | Valeur | Détail |
| --- | --- | --- |
| Bunny-hop : fenêtre | **0,15 s** (Félyne 0,25 s) | Saut lancé dans la fenêtre après l'atterrissage = hop réussi, la vitesse est conservée |
| Bunny-hop : gain | **+3 % par hop**, plafond **+60 %** | Gain seulement si la caméra a tourné d'au moins **8°** pendant le saut précédent (Félyne : pas de condition) |
| Bunny-hop : perte | Bonus remis à 0 si au sol plus de la fenêtre, ou sans entrée de déplacement | |
| Saut tampon | **0,12 s** | Saut pressé en l'air (sans charge de double saut) puis atterrissage dans 0,12 s → saut immédiat |
| Coyote time | **0,10 s** | Après avoir quitté un rebord sans sauter |
| Glissade : départ | Au sol, vitesse horizontale ≥ **8** studs/s | Vitesse initiale = max(vitesse actuelle, WalkSpeed) × `slideBoost` (défaut **1,15**, Cornu **1,4**) |
| Glissade : frottement | **14** studs/s² au plat | Fin si vitesse < 0,6 × WalkSpeed, relâchement, ou 1,6 s sans pente |
| Glissade : pente | Gain = **g × 0,6 × sin(pente)** vers le bas de la pente | Plafond **2,2 ×** WalkSpeed de base |
| Glissade → saut | Le bonus de bunny-hop prend `vitesse/base − 1` (borné à +60 %) | « Sauter en bas de pente convertit l'élan » |
| Double saut | Vitesse verticale = √(2 g h) | Recharge sur atterrissage vérifié (rayon, normale Y ≥ 0,55) |
| Plané | Chute max **8** studs/s | En maintenant Saut, en descente |
| Escalade courte | **1,2 s** à **14** studs/s | Mur détecté devant à 2 studs (normale |Y| < 0,3), en maintenant Saut |
| Gravité basse | **×0,6** | `VectorForce` vers le haut = masse × g × 0,4 |
| Ralenti (choix de carte) | `SlowMult` tant que `workspace:GetServerTimeNow() < SlowUntil` | Attributs du Player posés par RunManager (domaine run). Base de temps choisie : **`GetServerTimeNow`** |
| Bonus MoveSpeed | × (1 + `stats.MoveSpeed`) | Remote `Build` (domaine combat) |
| Dégâts de chute | **Aucun** | Roblox n'en a pas par défaut ; `FallingDown` et `Ragdoll` désactivés côté client |
| Onde d'atterrissage | Chute ≥ **18** studs | Anneau Neon local qui s'élargit (0 → 12 studs en 0,35 s) et s'efface ; inoffensif ; 2 anneaux en pool |

Tremplins, tyroliennes et geysers : placés par le domaine run, qui doit appeler `MovementGuard.exempt` (voir 6).

**Signaux au serveur** (remote `MoveEvent`, C→S, 8/s) : `("SlideStart")`, `("SlideEnd")`, `("Hop")`, `("HopReset")`. Le serveur les valide (types, au sol, cadence) et pose des attributs **serveur** sur le Player, en lecture seule pour les autres domaines :
`Sliding` (bool, expire seul après 2,5 s), `HopChain` (hops enchaînés, recompté par le serveur, 1 hop max / 0,2 s), `Airborne` (bool, rayon serveur à 4 Hz). Le domaine combat s'en sert pour Bélier (Cornu), Vent arrière (Plumeline) et Élan (Félyne) ; Élan mémorise `HopChain` au moment d'un contact ennemi. MovementGuard compte aussi `ProgressionService.recordStat(player, "Hops", 1)`.

## 5. Contrôles et Input Action System

`InputController` crée un `InputContext` « Gameplay » (Priority 1000, `Sink = false`) dans un dossier local `ReplicatedStorage/CohueInput` (créé par le client, non répliqué). Une `InputAction` de type `Bool` par action :

| Action | Clavier / souris | Manette | Tactile |
| --- | --- | --- | --- |
| `Jump` | Espace | ButtonA | Bouton Saut (UI) |
| `Slide` | LeftControl, LeftShift | ButtonB | Bouton Glisser (UI) |
| `Ultimate` | E | ButtonY | Bouton Ultime (UI) |
| `Card1` / `Card2` / `Card3` | 1 / 2 / 3 | DPadLeft / DPadDown / DPadRight | Toucher la carte (CardUI) |
| `Ping` | Clic molette (`MouseButton3`, via UserInputService) + G | DPadUp | Appui long mini-carte (PingUI) |

Déplacement et caméra : contrôles Roblox par défaut (ZQSD/WASD, stick gauche, joystick tactile).

API pour les autres contrôleurs (client) :
- `InputController.onAction(name, fn: (pressed: boolean) -> ()) -> Connection` (`Connection.disconnect()`)
- `InputController.getContext() -> InputContext`
- `InputController.bindButton(name, button: GuiButton) -> InputBinding` : **méthode recommandée pour l'UI**. Crée une `InputBinding` avec `UIButton = button` sous l'action : appuyer sur le bouton déclenche l'action comme la touche (appui = `pressed true`, relâché = `false`). À appeler une fois par bouton (MobileButtons : Jump, Slide, Ultimate).
- `InputController.trigger(name, pressed)` : repli pour du code (compagnon, tests, gestes). Appelle directement les écouteurs.
- `InputController.setEnabled(enabled)` : coupe les actions de gameplay quand un menu plein écran est ouvert.

Règle tactile : l'action part à l'**appui**, pas au relâchement.

## 6. Anti-triche mouvement (`MovementGuard`, serveur)

Échantillon toutes les **0,25 s** (Heartbeat), déplacement **horizontal** uniquement.

- **Vitesse max plausible** = `walkSpeed(classe) × (1 + MoveSpeed serveur) × max(1 + 0,6 bunny-hop, 2,2 glissade)`. Valeurs serveur seulement (`StatsService.get`), jamais `Humanoid.WalkSpeed` (le client le change sans que le serveur le voie). Le ralenti n'est pas utilisé pour resserrer la limite (le retard réseau du ralenti ferait des faux positifs).
- **Seau percé** : excès = max(0, distance − vmax × 1,35 × dt − pingSlack) ; seau += excès − 20 × dt ; au-delà de **40** studs → **recalage**.
- **Saut énorme** (téléport) : un pas > max(**45** studs, vmax × (dt + ping + 0,5) × 2) → recalage immédiat.
- **Vol stationnaire** : en l'air plus de **3,5 s** sans redescendre de 0,5 stud sous l'altitude de décollage → signalé ; recalage seulement si `HoverEnforce = true` (désactivé au lancement : mode « ombre », log seul).
- **Recalage** : `PivotTo(dernière position valide)` + vitesse annulée, puis **0,6 s + ping** de grâce. Une position n'est « valide » que si elle est au sol (rayon serveur) et atteinte sans excès.
- **Ne punit jamais un pic de lag seul** : marge de ping (ping borné à 1 s × vmax), échantillon ignoré si dt > 3 × intervalle (à-coup serveur), seau au lieu d'un seuil par échantillon, grâce après recalage, pas de kick (logs + compteur `strikes`).
- **Exemptions** : `MovementGuard.exempt(player, seconds, reason?)` ou attribut serveur `MoveExemptUntil` (temps `GetServerTimeNow`) sur le Player. Automatique : 3 s après apparition, assis (`SeatPart`), ancré, mort.
- **Logs** : `warn` limité à 1 par joueur toutes les 5 s, avec ping, distance, vmax, strikes.

## 7. Réglages Studio à faire à la main

1. **Avatar Settings** (menu Fichier) : Avatar type **R15 only** (points d'attache ; aussi requis pour le taux DevEx 18+ US) ; Collision **Single Collider** (même boîte pour tous) ; Animation **Player Choice** ou Standard R15 ; Body Scale/Build **Player Choice** (identité) ; Accessory Scale **Player Choice** (pour ne pas réduire/supprimer les traits) ; Abilities **Legacy Humanoid** (pas de CCL).
2. `StarterPlayer.CharacterUseJumpPower = false`, `CharacterJumpHeight = 7.2`, `CharacterWalkSpeed = 16`, `CharacterMaxSlopeAngle = 89` (laissé par défaut).
3. `Workspace.PlayerScriptsUseInputActionSystem` : laisser par défaut pour l'instant ; tester l'activation (début 2027 elle deviendra le défaut). Ne pas forker le PlayerModule.
4. `Workspace.Gravity` = 196,2 (défaut ; la gravité basse d'Astrel est une force par joueur).
5. Écrire ces réglages dans le README de la place : ils changent des comportements invisibles depuis les scripts.

## 8. Sources vault (LihFolk Vault V2)

- *Input - UserInputService and ContextActionService* §5 (IAS : InputContext/InputAction/InputBinding, `UIButton`, Sink, Priority) ; *Server Authority and Input Migration 2026* §4 (calendrier de bascule des scripts joueur, `GetControls` casse) ; *InputBinding* (atlas).
- *Engine and API Changes 2025-2026* §7 (Character Controller Library, opt-in, capacités maison non supportées) ; *Avatar Body Types and Scale in Gameplay* §2 (Avatar Settings, Single Collider) ; *AI Pitfalls - Physics and Animation*.
- *Custom Character Controllers* (pile de multiplicateurs, sauts, glissade, validation serveur) ; *Input Responsiveness Buffering and Coyote Time* §2, §4, §6 (tampon 0,12 s, coyote 0,10 s, action à l'appui sur tactile) ; *Mover Constraints and Physics Controllers* §2, §5, §6 (LinearVelocity Plane + `Move(dir)`, VectorForce anti-gravité).
- *Accessories and Armor That Follow Animation* §1-2 (Weld, accessoire = Handle + Attachment du même nom) ; *R15 Rig Anatomy and Attachments* §3-4 (attaches, `BodyHeightScale`…) ; *Character Select and Class Systems with Different Rigs* §2 (appliquer après `CharacterAppearanceLoaded`) ; *HumanoidDescription and Outfit Systems* ; *Characters and Humanoids* §2 (propriétés de mouvement, `SetStateEnabled` côté client).
- *Exploits and Anti-Cheat* (seau percé, horizontal seulement) ; *Detecting Movement Exploits - Speed Fly Noclip Teleport* (tolérances, recalage sur position au sol, Common mistakes, Checklist) ; *DevEx and Cashing Out* (règle R15).
- SYMPTOMS : « slows get stuck » (pile de multiplicateurs), « character slides and cannot stop » (Massless sur les pièces), « I pressed jump on the edge » (coyote).
