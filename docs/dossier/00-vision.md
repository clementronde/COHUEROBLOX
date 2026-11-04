# COHUE — Dossier de conception Roblox (survivors-like coop)

Nov 4, 2026 · @Clément RONDEPIERRE

## 1. Vision en une phrase

**COHUE** (nom de travail) est un jeu original de survie en horde 3D, coop 1 à 4 joueurs sur Roblox, inspiré du genre popularisé par Megabonk et PokeBonk : tu joues avec TON avatar Roblox, tu choisis une **classe** qui lui greffe un trait physique visible (cornes, ailes, bras mécanique…), un **compagnon** original combat à tes côtés et évolue pendant la run, et tu dois tuer le boss du stage avant la fin des 10 minutes sous peine de subir la Vague Finale. Ce n'est pas un remaster : on reprend des mécaniques de genre, tout l'univers est neuf.

- **Ce qu'on reprend de Megabonk** : la run chronométrée de 10 min, le boss à trouver, les armes automatiques, les grimoires (tomes) qui scalent tout, les autels sur la carte, la verticalité et le mouvement skillé (glissade, bunny-hop), la méta-progression par quêtes.
- **Ce qu'on reprend de PokeBonk** : un partenaire qui attaque seul et évolue, les cartes d'amélioration « nouvelle attaque / renforcer / vitamine », un mode Survie infini, les clans et classements.
- **Ce qu'on invente pour Roblox** : l'avatar du joueur reste intact, la classe ajoute un trait physique, le coop est natif, tout est jouable au tactile.
- **Règle d'or** : aucun nom, personnage, créature ou visuel repris tel quel de Megabonk ou de Pokémon. On garde les mécaniques (non protégeables), on crée l'univers.

Public cible : 9-15 ans, sessions de 10-15 min, mobile majoritaire (on conçoit mobile d'abord). Cela vise le palier **Select 9-15** de Roblox : 2-Step Verification, Plus ou frais par jeu, évaluation réussie, contenu classé Moderate maximum. Tant que le jeu n'est pas approuvé, seuls les 16+ le voient : le délai d'évaluation est intégré à la phase 3 (section 14).

## 2. Analyse de Megabonk (vedinad, 2025)

Megabonk mélange la horde à la Vampire Survivors et l'exploration 3D verticale à la Risk of Rain 2 ; son ADN tient en trois choses : une run de 10 minutes contre la montre, un build qui explose en puissance, et un mouvement physique qui récompense le skill. Le jeu revendique 20+ personnages, 70+ objets et environ 240 quêtes.

### 2.1 Boucle d'une run

1. On choisit un personnage (arme de départ + passif unique) puis une carte et un tier.
2. On tue des vagues, on ramasse l'XP ; chaque niveau propose 3 cartes : nouvelle arme, nouveau tome, ou amélioration d'un existant. Les bonus sont tirés au hasard avec une rareté (commun → légendaire), contrairement aux chemins fixes de Vampire Survivors.
3. On explore : coffres, pots, autels, mini-boss.
4. On trouve le téléporteur / portail du boss et on le bat **avant que le chrono de 10 min arrive à zéro**.
5. Sinon la **Vague Finale** démarre : une horde infinie qui étouffe le joueur (mais rapporte argent et XP bonus à qui survit).

| Phase | Minutes | Objectif joueur |
| --- | --- | --- |
| Début | 0-4 | Ramasser XP, casser des pots, choisir l'arme principale |
| Milieu | 4-8 | Trouver les synergies, autels, localiser le boss |
| Fin | 8-10 | Battre le boss, se préparer |
| Après le chrono | 10+ | Survivre à la Vague Finale |

Des vagues intermédiaires plus denses tombent vers 6:00 et 3:00 restantes.

### 2.2 Cartes, tiers et stages

- **Carte** = un biome (Forêt, Désert, puis Cimetière ajouté par mise à jour). **Tier** = difficulté + nombre de stages. **Stage** = une zone avec son boss.
- Tier 1 : 1 stage, boss battu = fin. Tier 2 : 2 stages, le portail emmène au suivant. Tier 3 : 3 stages.
- Déblocage : battre le boss du stage 1 en T1 ouvre le T2, battre celui du stage 2 en T2 ouvre le T3. Le Désert se débloque via un objectif précis en Forêt T2.
- Chaque biome a ses mini-boss (ex. golem de sable et scorpion géant au Désert) et ses aléas (tempête de sable garantie au Désert, lave périodique dans un défi).

### 2.3 Personnages

Chaque personnage = une arme de départ + un passif qui oriente le build. Exemples de passifs observés : chance qui s'empile à chaque niveau, critique qui monte à chaque niveau, poison qui se propage en explosant, blocage de dégâts + étourdissement en zone, bonus de dégâts tant qu'on n'est pas touché, saut haut + escalade de murs, bouclier qui renvoie des ondes de choc. Le passif compte plus que l'arme : c'est lui qui crée l'identité.

### 2.4 Armes, tomes, objets

- **Armes** (\~29) : tir automatique (arc, bâton éclair, revolver, sniper, haches tournoyantes, aura, épée, katana, bouclier Aegis…). Une par personnage, mais toutes équipables par tous.
- **Tomes** (\~23) : bonus passifs qui s'appliquent à tout le kit — dégâts, cooldown, quantité de projectiles, taille, durée, PV, armure, esquive, bouclier, épines, chance, XP, attraction, régénération, plus des tomes spéciaux (Chaos : multiplicateur de dégâts global ; Maudit : risque/récompense).
- **Emplacements limités** d'armes et de tomes, extensibles par la méta-progression. Une fois les slots pleins, les choix non pris sortent du pool.
- **Objets** (70+) trouvés dans les coffres : effets passifs ou à déclenchement (XP aspirée périodiquement, invocation à chaque X mètres parcourus, dégâts bonus contre élites, ralenti sous 50 % PV…).
- **Outils de contrôle du tirage** : bannir, passer, relancer.

### 2.5 Autels (shrines)

| Autel | Effet |
| --- | --- |
| Charge | Rester dans le cercle quelques secondes (sortir = reset) → choisir 1 stat parmi 3 |
| Charge doré | Même principe, 3 choix légendaires |
| Défi | Fait apparaître des ennemis marqués ; tous tués = coffre |
| Sang (malédiction de boss) | Duplique le boss, récompenses doublées |
| Moaï | Bonus gratuit + objets, sans charger |
| Avidité | Plus d'argent contre plus de difficulté |
| Aspiration | Attire toute l'XP au sol |

Environ 15 autels de charge par stage : c'est le cœur de l'exploration.

### 2.6 Mouvement

Saut, glissade (accroupi), bunny-hop qui conserve la vitesse, glissade en pente qui accélère, double saut sur certains persos, dégâts de chute (annulés en glissant en pente ou en frôlant un mur). Chaque personnage a sa hauteur de saut. Le mouvement est un vrai plafond de skill et un argument de streaming.

### 2.7 Méta-progression

- **Argent (silver)** gagné en fin de run, croît avec le tier → achète les déblocages (armes, tomes, objets) et des outils de confort (ex. un « toggler » pour retirer des éléments du pool).
- **Quêtes** (\~240) : tuer X ennemis d'un type, survivre X min à la Vague Finale, charger tous les autels, battre un boss sans dégâts… Chaque quête débloque un personnage, une arme, un objet ou un slot.
- **Défis** par carte/tier avec modificateurs (mourir au premier coup, sol en lave, ne pas bouger…).
- **Classement** et score de kills.

### 2.8 Pourquoi ça marche

Runs courtes et relançables instantanément, montée de puissance absurde et lisible, humour, 3D qui rend la horde spectaculaire, et une liste de quêtes qui donne toujours un « encore une run ». Points faibles relevés par la presse : début de partie lent et peu de biomes au lancement.

## 3. Analyse de PokeBonk (Charcher, oct. 2026)

PokeBonk est un jeu de fans gratuit dans le navigateur, sorti le 14 octobre 2026, qui transpose la boucle de Megabonk dans l'univers Pokémon : son apport réel, c'est le **partenaire qui combat et évolue**, pas le skin.

- **Entrée** : compte invité possible, choix d'un starter parmi trois (plante / feu / eau).
- **Combat** : le partenaire attaque automatiquement dans une arène 3D, le joueur gère le placement.
- **Montée de niveau** : cartes « nouvelle attaque », « renforcer une attaque », « vitamine » (stat).
- **Évolutions** + capacités **Ultimes** + déblocages de **Ligue**.
- **Modes** : Classique (zones, gardiens, un autel) et Survie (hordes infinies, paliers).
- **Social** : clans qui additionnent les meilleures runs des membres, classements individuels, par carte, global et mode infini.
- **Statut** : projet non lucratif, assisté par IA, en bêta d'équilibrage.

**À retenir pour nous** : le lien affectif avec une créature qui grandit pendant la run est un énorme moteur de rétention chez les 9-14 ans, et les clans donnent une raison de jouer ensemble. **À ne surtout pas reprendre** : les créatures et noms Pokémon (voir section 4).

## 4. Garder, adapter, jeter — et le risque juridique

On copie la structure de jeu, jamais l'habillage : les mécaniques ne sont pas protégées, les personnages, noms, créatures et visuels le sont.

| Élément | Décision | Adaptation Roblox |
| --- | --- | --- |
| Run de 10 min + boss + Vague Finale | Garder | Identique, timer partagé par l'équipe en coop |
| Cartes de niveau (3 choix, rareté) | Garder | Choix individuel, pas de pause globale en coop (voir 5) |
| Tomes / slots limités | Garder | Renommés « Grimoires », 4 slots au départ → 6 max |
| Autels de charge | Garder | En coop, charge plus rapide à plusieurs (incite à se grouper) |
| Bunny-hop / glissade | Adapter | Bouton Glisser + saut buffer, compatible tactile |
| Dégâts de chute | Jeter | Frustrant sur mobile, remplacé par un atterrissage lourd sans dégâts |
| Personnages fixes | Remplacer | Avatar du joueur + Classe à trait physique (section 6) |
| Partenaire Pokémon | Remplacer | Compagnons 100 % originaux (section 7) |
| Clans + classements | Garder | Groupes Roblox / « Bandes » in-game, classements hebdo |
| Humour absurde | Garder | Ton propre, noms français/anglais originaux |

**Risque Pokémon** : Roblox retire les jeux qui utilisent la licence (cas historique de Pokémon Brick Bronze). Zéro créature, nom, cri, type ou silhouette Pokémon. Pas de « starter plante/feu/eau » trop calqué : on passe par des **affinités** originales.

**Risque Megabonk** : aucun nom (personnages, objets, boss), logo ni modèle repris, et aucun titre qui fasse écho à « Megabonk » (d'où l'abandon de « BONK FOLK » au profit de COHUE, à vérifier en marque). On ne parle plus de « remaster » : c'est un jeu original du genre. Trois détails trop proches de Megabonk ont été changés pour que le jeu ait sa propre identité :

- Le 2e monde ne se débloque plus via le Tier 2 du premier monde, mais par des autels d'épreuve (section 9).
- Le mini-boss golem du désert est remplacé par un chameau-tirelire (section 9).
- La liste d'autels n'est plus un calque un pour un : statue de bonus gratuit et autel aspirateur remplacés par des autels maison (section 8.4).

*Je ne suis pas juriste : avant lancement, faire valider le nom et la DA par quelqu'un de compétent en propriété intellectuelle.*

## 5. Boucle de jeu Roblox et multijoueur

Une run = 10 minutes par stage, en solo ou à 4, avec un chrono et un boss communs à l'équipe ; tout le reste (XP, cartes, build) est individuel.

### 5.1 Parcours joueur

1. **Lobby** (place séparée) : le joueur arrive avec son avatar, choisit sa Classe sur un présentoir (le trait physique apparaît en direct sur lui), son Compagnon, puis rejoint une file solo / amis / matchmaking public.
2. **Run** (serveur réservé, 1-4 joueurs) : apparition au centre du stage, chrono 10:00.
3. **Exploration + combat** : armes automatiques, XP, coffres, autels, mini-boss.
4. **Boss** : le premier joueur qui trouve l'Arche du boss la révèle à toute l'équipe (flèche HUD). Le combat démarre quand tous les vivants sont dans l'arène ou après 20 s.
5. **Boss vaincu** : portail vers le stage suivant (Tier 2-3) ou fin de run. Une fenêtre de 60 s de « farm bonus » reste ouverte avant le portail.
6. **Chrono à zéro** : la Vague Finale démarre ; chaque 30 s survécues ajoute de la monnaie.
7. **Écran de fin** : kills, dégâts par arme, quêtes avancées, monnaie gagnée, bouton Rejouer (relance immédiate, même équipe).

### 5.2 Règles coop (ce que Megabonk n'a pas)

- **Pas de pause au level-up** : les 3 cartes s'affichent en bas d'écran, le joueur a 8 s, pendant lesquelles il est invulnérable et ralenti à 50 % (sinon choix auto de la carte la plus rare).
- **XP partagée à 50 %** dans un rayon de 40 studs : se grouper paie, mais on peut s'écarter.
- **Mise à terre** au lieu de la mort : 25 s pour être relevé (rester 3 s à côté). Mort définitive si personne ne vient ; le joueur devient fantôme spectateur qui peut encore charger les autels à 25 % de vitesse.
- **Scaling** : PV des ennemis ×(1 + 0,6 par joueur supplémentaire), densité ×(1 + 0,4 par joueur), boss ×(1 + 0,8 par joueur).
- **Coffres** : butin instancié par joueur (pas de vol entre amis).
- **Autels de charge** : vitesse ×1,5 à 2 joueurs, ×2 à 3+, récompense pour chacun dans le cercle.

### 5.3 Modes

| Mode | Contenu | Rôle |
| --- | --- | --- |
| Aventure | Tiers 1-3 par monde | Progression principale, déblocages |
| Survie | Horde infinie, paliers toutes les 2 min | Classement, streaming |
| Défi hebdo | Classe + compagnon + modificateur imposés | Raison de revenir chaque semaine |
| Défis de monde | Modificateurs (sol en lave, un coup = à terre, sans saut…) | Fin de jeu, titres cosmétiques |

## 6. Avatar intact + Classes à trait physique

L'avatar Roblox du joueur n'est jamais remplacé ni recoloré : la Classe **ajoute** un trait physique (accessoire fixé sur ses points d'attache) qui porte le gameplay, et ce trait **grandit** aux niveaux 10, 20 et 30 de la run pour rendre la montée en puissance visible.

### 6.1 Règles d'intégration à l'avatar

- On garde la `HumanoidDescription` du joueur telle quelle (vêtements, layered clothing, accessoires, proportions). Rig forcé en **R15** pour les points d'attache. Spawn et rechargement via `LoadCharacterAsync` / `ApplyDescriptionAsync` (noms de l'API depuis janvier 2026).
- Le trait est un `Accessory` ajouté côté serveur via `Humanoid:AddAccessory()`, attaché sur une `Attachment` standard (HatAttachment, BodyBackAttachment, WaistBackAttachment, Left/RightShoulderAttachment, Left/RightGripAttachment).
- Le trait se **met à l'échelle** selon la taille de l'avatar (lecture de `BodyHeightScale` / `BodyWidthScale`) pour ne pas flotter sur les avatars mini ou géants.
- **Gestion des conflits** : si le joueur porte déjà un accessoire sur le même point (ailes, chapeau), on masque seulement l'accessoire en conflit pendant la run (Transparency), jamais le reste. Option « Garder mon chapeau » dans les réglages pour les classes de tête.
- Les stats de mouvement viennent de la classe (WalkSpeed, JumpHeight), jamais de l'apparence : un avatar fin ou large a exactement la même hitbox de gameplay (capsule fixe).
- **Character Controller Library** (opt-in, avril 2026) : à tester en phase 0 pour le bunny-hop et la glissade avant d'écrire notre propre contrôleur.
- Couleur du trait : 3 teintes gratuites + teintes cosmétiques (monétisation propre, section 11).

### 6.2 Les 10 classes de lancement

| Classe | Trait physique (point d'attache) | Évolution du trait (niv. 10 / 20 / 30) | Arme de départ | Passif | Mouvement |
| --- | --- | --- | --- | --- | --- |
| **Cornu** | Cornes de bélier (tête) | Cornes plus longues / gravures lumineuses / cornes en flammes | Hache-boomerang | *Bélier* : la glissade devient une charge qui renverse ; chaque ennemi percuté = +0,5 % dégâts (cumul run) | Saut normal, glissade +40 % |
| **Plumeline** | Ailes de plumes (dos) | Ailes plus grandes / plumes dorées / ailes de lumière | Plumes-dards | *Vent arrière* : plané en maintenant Saut ; +25 % dégâts en l'air | Double saut + plané |
| **Mécano** | Bras mécanique (épaule droite) | Pistons / 2e bras / bras doré à vapeur | Clé-tourelle (pose des tourelles) | *Bricoleur* : autels chargés 35 % plus vite ; les tourelles héritent des Grimoires de Quantité | Saut bas, +10 % vitesse au sol |
| **Félyne** | Oreilles + queue de chat (tête + taille) | Rayures / queue double / pelage étincelant | Griffes éclair | *Élan* : 5 sauts enchaînés sans toucher un ennemi = griffure éclair en zone | Bunny-hop plus permissif |
| **Rocailleux** | Plaques de pierre (épaules) | Mousse / cristaux / armure de lave | Poing-séisme | *Bouclier vivant* : +3 armure par niveau ; les coups reçus renvoient 30 % des dégâts | Lent, immunisé au recul |
| **Sporelin** | Chapeau-champignon (tête) | Taches / spores flottantes / chapeau géant lumineux | Nuage de spores | *Contagion* : un ennemi empoisonné qui meurt contamine ses voisins | Normal |
| **Écaille** | Petites cornes + queue écailleuse (tête + taille) | Écailles / crête / mini-ailes de dragon | Souffle de braise | *Combustion* : les brûlures s'empilent sans limite mais durent 2 s | Saut haut |
| **Astrel** | Antennes + couronne d'étoiles en orbite (tête) | 2 étoiles / 4 étoiles / anneau galactique | Météorite | *Bonne étoile* : +1 Chance par niveau, garantie d'un choix rare toutes les 5 cartes | Gravité basse |
| **Cristallin** | Cristaux sur les épaules | Cristaux qui poussent à chaque palier | Éclats de prisme | *Croissance* : +2 % Taille de toutes les armes par niveau | Normal |
| **Tentaculos** | 4 tentacules dans le dos | 6 tentacules / ventouses lumineuses / 8 tentacules | Fouet-tentacule | *Multitâche* : +1 emplacement d'arme, mais −10 % dégâts par arme | Escalade de murs courte |

### 6.3 Déblocage des classes

- Gratuites dès le départ : Cornu, Plumeline, Mécano.
- Les 7 autres via **quêtes** (ex. Rocailleux : encaisser 50 000 dégâts au total ; Astrel : ouvrir 100 coffres ; Tentaculos : finir un stage avec 5 armes). Jamais vendues en Robux, pour garder le jeu équitable et éviter l'effet pay-to-win.
- Chaque classe a un **niveau de maîtrise** (1-20) qui débloque des teintes, des poses de victoire et un titre, pas de stats.

### 6.4 Équilibrage de départ

Objectif : chaque classe finit un Tier 1 en 70-80 % des runs d'un joueur moyen. Mesurer par classe : taux de victoire T1/T2/T3, temps moyen au boss, taux de choix. Une classe hors de ±8 points de la moyenne est retouchée à la mise à jour suivante.

## 7. Compagnons originaux (l'apport PokeBonk, sans la licence)

Chaque joueur emmène un Compagnon de son cru qui attaque seul, gagne ses propres techniques via les cartes de niveau et évolue deux fois pendant la run (niveaux 8 et 20) : c'est l'attachement de PokeBonk, dans un univers 100 % maison.

### 7.1 Six affinités (pas de « types » calqués)

Braise (brûlure), Ronce (poison, ralentit), Marée (recul, soin d'équipe), Volt (chaîne entre ennemis), Givre (gel, fragilise), Écho (son : étourdit, révèle les coffres).

### 7.2 Lignées de lancement (3 stades chacune)

| Affinité | Stade 1 | Stade 2 (niv. 8) | Stade 3 (niv. 20) | Rôle | Ultime (jauge pleine) |
| --- | --- | --- | --- | --- | --- |
| Braise | Tisonnet (lézard-allumette) | Fournaïde | Volcarapace | Dégâts de zone | Pluie de cendres 6 s |
| Ronce | Pousseron (gland qui marche) | Ronciflore | Sylvogarde | Contrôle, poison | Racines qui immobilisent tout l'écran 3 s |
| Marée | Gouttelot (têtard bulle) | Ondelin | Abyssale | Soutien, recul | Vague qui soigne l'équipe de 40 % |
| Volt | Grésillon (souris-pile) | Ampérat | Fulgurex | Dégâts en chaîne | Orage qui frappe 30 cibles |
| Givre | Flocon (pingouin boule) | Stalagmo | Glaciarque | Gel, défense | Blizzard : ennemis gelés 4 s |
| Écho | Pipistrou (chauve-souris enceinte) | Résonar | Tonnerlune | Utilitaire | Cri qui étourdit et révèle le boss |

Les noms sont des propositions originales : vérifier avant publication qu'aucun n'est déjà déposé.

### 7.3 Fonctionnement

- Le Compagnon suit le joueur, attaque la cible la plus proche et ne peut pas mourir (il est « sonné » 5 s si le joueur est à terre).
- Cartes de niveau dédiées : **Nouvelle technique** (max 3), **Renforcer une technique**, **Friandise** (+stat du Compagnon). Environ 1 carte sur 4 concerne le Compagnon.
- **Lien** (méta-progression) : chaque run augmente le niveau de Lien (1-30) du Compagnon utilisé, qui débloque des techniques de départ alternatives, des teintes et une pose — pas de stats brutes au-delà de +10 %.
- **Synergies Classe × Compagnon** : bonus léger (+10 %) quand l'affinité colle à la classe (Écaille + Braise, Sporelin + Ronce, Mécano + Volt…). Ça pousse à essayer des combinaisons sans les rendre obligatoires.
- Collection : 3 Compagnons au départ, les autres gagnés par quêtes ou œufs **gratuits** obtenus en jeu (taux affichés). Pas d'œufs payants au lancement. Règle stricte : aucune monnaie achetable en Robux (gemmes ou autre) ne doit jamais pouvoir acheter un œuf, sinon il devient un objet aléatoire payant.

## 8. Armes, Grimoires, Objets, Autels

Le build repose sur trois couches qui se multiplient entre elles : 4 armes max (5 pour Tentaculos), 4 Grimoires au départ (6 débloquables), et des objets illimités trouvés dans les coffres.

### 8.1 Armes de lancement (16)

| Arme | Comportement | Stat qui la fait briller |
| --- | --- | --- |
| Hache-boomerang | Aller-retour qui transperce | Taille, Quantité |
| Plumes-dards | Rafale vers l'ennemi le plus proche | Quantité, Vitesse d'attaque |
| Clé-tourelle | Pose une tourelle fixe 8 s | Durée, Quantité |
| Griffes éclair | Coup en cône devant soi | Critique |
| Poing-séisme | Onde circulaire au sol | Taille, Armure (convertit) |
| Nuage de spores | Nappe de poison qui suit | Durée, Taille |
| Souffle de braise | Lance-flamme court | Vitesse d'attaque |
| Météorite | Chute aléatoire à grande zone | Chance, Taille |
| Éclats de prisme | Rebondit entre ennemis | Rebonds, Critique |
| Fouet-tentacule | Balayage à 360° | Taille |
| Toupie à scie | Orbite autour du joueur | Quantité, Vitesse |
| Boule de bowling | Roule et rebondit sur le relief | Taille, Dégâts |
| Cerf-volant laser | Rayon qui suit le joueur | Durée |
| Parapluie-bouclier | Bloque un coup, renvoie une onde | Cooldown |
| Bombe à paillettes | Explosion qui aveugle | Taille, Quantité |
| Pistolet à bulles | Bulles qui emprisonnent 1 s | Quantité |

Chaque arme monte jusqu'au niveau 8 ; au niveau 8 avec un Grimoire précis au niveau 5+, elle peut **fusionner** en version ultime (ex. Toupie à scie + Grimoire de Vitesse → Tornade d'acier).

### 8.2 Grimoires (14)

Dégâts, Vitesse d'attaque, Quantité, Taille, Durée, Cooldown, Critique, Chance, Savoir (XP), Aimant (rayon de ramassage), Vitalité (PV max), Rempart (armure), Agilité (vitesse + esquive), et le **Grimoire Interdit** (déblocage tardif : +difficulté et +butin à chaque niveau).

### 8.3 Objets (40 au lancement, 4 raretés)

Exemples : *Lacet magique* (+8 % XP), *Chaussette porte-bonheur* (+3 Chance), *Gomme collante* (ralentit les ennemis touchés), *Trousse renforcée* (+bouclier qui se recharge), *Sifflet de récré* (toutes les 20 s, repousse les ennemis proches), *Clé à molette* (autels +5 % vitesse et +8 % récompense), *Fantôme de doudou* (chaque 15 m parcourus invoque un mini-fantôme), *Aimant de frigo* (aspire toute l'XP toutes les 45 s), *Pile usée* (−10 % PV, +15 % dégâts), *Lunettes de chasseur* (+15 % dégâts aux élites et boss).

Raretés : Commun (gris), Rare (bleu), Épique (violet), Légendaire (or). Contrôle du tirage : 3 Bannir, 3 Passer, 3 Relancer par run, augmentables en méta.

### 8.4 Autels

| Autel | Effet | Spécificité coop |
| --- | --- | --- |
| Autel de charge | Rester dans le cercle → 1 stat parmi 3 | Plus rapide à plusieurs |
| Autel doré | Idem, choix légendaires (rare) | Tout le cercle reçoit |
| Autel d'épreuve | Ennemis marqués ; tous tués = coffre | Coffre par joueur |
| Autel du défi du boss | Ajoute un 2e boss, récompenses ×2 | Vote à la majorité |
| Distributeur farceur | Contre des pièces, donne un objet + un gag temporaire (tête géante, voix aiguë 20 s) | Le gag touche toute l'équipe |
| Tirelire avide | +argent, +difficulté | Visible par tous (malus partagé) |
| Cloche de récré | Regroupe tous les ennemis proches en un point pendant 5 s, +XP sur ceux tués | Idéal pour les combos de zone à plusieurs |
| **Totem d'équipe** | 2 joueurs minimum : buff d'équipe 60 s | Exclusif coop |

15 autels de charge par stage, positionnés en hauteur et en recoins pour récompenser le mouvement.

## 9. Mondes, ennemis, boss

Trois mondes au lancement (Megabonk en avait deux, c'était sa critique principale), chacun en 3 tiers, avec un aléa propre et des cartes semi-procédurales assemblées à partir de tuiles faites main.

| Monde | Ambiance | Aléa | Ennemis de base | Mini-boss | Boss de stage | Déblocage |
| --- | --- | --- | --- | --- | --- | --- |
| Bois Grognon | Forêt de collines et falaises | Brouillard qui réduit la vue 30 s | Glands grincheux, champignons sauteurs, hiboux plongeurs | Souche géante | Le Grand Chêne Ronchon | Dès le départ |
| Dunes Croustillantes | Désert ouvert, ruines | Tempête de sable (pousse les joueurs) | Momies en papier toilette, cactus coureurs, scarabées blindés | Chameau-Tirelire (lâche des pièces à chaque coup) | Pharaon-Grille-Pain | Réussir 10 autels d'épreuve au total (tous mondes, tous tiers) |
| Récré Fantôme | École abandonnée la nuit, toits et préaux | Coupure de courant (ennemis invisibles hors lumière) | Craies vivantes, cartables mordeurs, fantômes de surveillants | Le Pion Spectral | La Directrice Éternelle | Finir un Tier 2 de Dunes |

### 9.1 Familles d'ennemis (communes aux mondes)

- **Essaim** : faibles, nombreux, vont droit sur le joueur (80 % des spawns).
- **Sauteurs** : bondissent pour punir l'immobilité.
- **Tireurs** : projectiles lents et lisibles, forcent à bouger.
- **Blindés** : lents, lourds, bloquent les couloirs.
- **Élites** (contour doré) : ×6 PV, lâchent un coffre.

### 9.2 Boss

Chaque boss a 3 phases (100-66-33 %), une attaque signature télégraphiée 1 s à l'avance (cercle rouge au sol, essentiel sur mobile), et une faiblesse exploitable par le terrain (ex. le Grand Chêne s'enracine : monter sur ses branches pour frapper le cœur). En Tier 3, un **Boss final** de monde arrive au stage 3.

### 9.3 Courbe de spawn

Densité cible (solo) : 40 ennemis vivants à 1:00, 120 à 5:00, 200 à 9:00, plafond technique 300 par serveur (section 12). Vagues renforcées à 6:00 et 3:00 restantes, annoncées par un son et un bandeau.

## 10. Mouvement et contrôles

Le mouvement doit garder le plafond de skill de Megabonk (bunny-hop, glissade en pente) tout en restant jouable au pouce : on garde la physique, on simplifie les entrées.

| Action | PC | Mobile | Manette |
| --- | --- | --- | --- |
| Se déplacer | ZQSD / WASD | Joystick gauche | Stick gauche |
| Caméra | Souris (verrou épaule optionnel) | Glisser à droite | Stick droit |
| Sauter | Espace | Bouton Saut | A |
| Glisser | Ctrl / Shift | Bouton Glisser | B |
| Ultime du compagnon | E | Bouton Ultime | Y |
| Choisir une carte | 1 / 2 / 3 | Toucher la carte | Croix + A |
| Ping (« boss ici », « autel ») | Molette | Appui long sur la mini-carte | Croix haut |

Les contrôles sont construits dès le premier jour sur l'**Input Action System** (InputContext / InputAction / InputBinding) : chaque action du tableau a déjà une liaison clavier, tactile et manette, exactement ce que ce système attend.

Les **pings** deviennent le moyen principal de communiquer en équipe : le chat exige désormais une vérification d'âge et les moins de 16 ans ne peuvent pas discuter avec des adultes. Prévoir 6 pings contextuels (boss ici, autel, aide, coffre, regroupement, merci).

### 10.1 Physique

- **Bunny-hop** : un saut relancé dans les 0,15 s après l'atterrissage conserve la vitesse horizontale ; +3 % de vitesse par hop réussi en tournant la caméra, plafonné à +60 %.
- **Saut tampon** : un appui Saut 0,12 s avant l'atterrissage compte comme réussi (rend le bunny-hop accessible au tactile).
- **Glissade** : perd de la vitesse au plat, en gagne en pente ; sauter en bas de pente convertit l'élan.
- **Pas de dégâts de chute** ; un atterrissage de haut fait une petite onde (jolie, inoffensive).
- **Tremplins, cordes à tyrolienne et geysers** placés dans chaque stage pour la verticalité.
- Le mouvement est **calculé côté client** (réactivité) et contrôlé côté serveur (vitesse max plausible, voir 12). Modèle à confirmer, voir 10.2.

### 10.2 Décision à prendre : Server Authority

Recommandation : **mode classique** (mouvement client + contrôles de vitesse serveur) pour le prototype et probablement le lancement.

| Option | Pour | Contre |
| --- | --- | --- |
| Classique (recommandé) | Bunny-hop et glissade sur mesure faciles à coder, réactif sur mobile, modèle éprouvé | Triche de mouvement possible, limitée par les contrôles serveur |
| `AuthorityMode = Server` (juillet 2026) | Mouvement autoritaire serveur avec prédiction client, bien plus robuste contre la triche | Impose simulation fixe, signaux différés, nouveau système de réplication et Input Action System ; physique de bunny-hop maison nettement plus dure |

Le choix doit être fait avant la phase 0 : passer en Server Authority plus tard signifie réécrire le mouvement et une partie du réseau.

## 11. Méta-progression, économie, monétisation

Tout ce qui donne de la puissance se gagne en jouant ; les Robux achètent du style, du confort et du soutien, jamais une victoire.

### 11.1 Monnaies

| Monnaie | Gain | Usage |
| --- | --- | --- |
| Pièces (pendant la run) | Ennemis, coffres, pots | Coffres payants et marchand ambulant de la run ; perdues à la fin |
| Étoiles d'argent (méta) | Fin de run : ≈ 10 en T1, 25 en T2, 60 en T3, +bonus Vague Finale | Débloquer armes, Grimoires, objets dans le pool ; slots ; Bannir/Passer/Relancer en plus |
| Jetons de quête | Quêtes et défis | Cosmétiques gratuits, teintes de trait |

### 11.2 Quêtes (≈ 150 au lancement)

Réparties en catégories : tuer (X ennemis d'une famille), survivre (X min en Vague Finale), explorer (charger tous les autels d'un stage), maîtriser (battre un boss sans dégât, en moins de 30 s), classe (niveau 30 avec une classe), compagnon (évoluer au stade 3), coop (relever 10 coéquipiers). Chaque quête débloque un élément précis : on voit toujours ce qu'on va gagner.

### 11.3 Monétisation (conforme aux règles Roblox)

- **Pass de jeu** : Teintes Premium de traits, Emotes de victoire, Pass VIP (serveur privé gratuit + titre doré). Pas de relance de cartes en plus dans le pass : ce serait un avantage de jeu payant, et peut-être un objet aléatoire payant.
- **Produits développeur** : packs de teintes, effets de pas, auras de Compagnon purement visuelles.
- **Pas de produits aléatoires payants** au lancement (pas d'œufs ou caisses en Robux, ni en monnaie achetable en Robux). Si on en ajoute plus tard : probabilités affichées avant achat et vérification des règles Roblox en vigueur à ce moment.
- **Pas de résurrection payante** en coop : c'est perçu comme injuste et crée de la pression sur les plus jeunes.
- **Abonnement Roblox** (si éligible) : bonus cosmétique mensuel.
- **ProcessReceipt** : le marqueur `PurchaseId` est stocké **dans le même profil** que l'objet accordé, jamais dans un magasin de reçus séparé (un effacement de données casserait tout). Ordre : accorder l'objet, `SaveNowAsync`, puis renvoyer `PurchaseGranted`. Renvoyer `NotProcessedYet` si le joueur n'est pas là, si le produit est inconnu ou si la sauvegarde échoue.

*Les règles de monétisation Roblox évoluent : relire la politique officielle avant chaque nouveau type d'achat.*

## 12. Architecture technique Roblox

Le défi n°1 est d'afficher 200-300 ennemis fluides sur mobile : les ennemis ne sont donc **pas** des Humanoids mais des données côté serveur, rendues par des modèles légers côté client.

### 12.1 Places et flux

- **Lobby** (place principale) : choix classe/compagnon, boutique, quêtes, files d'attente.
- **Run** (place séparée) : `TeleportAsync` d'un groupe de 1-4 joueurs avec `TeleportOptions.ReservedServerId` (un GUID). L'ancien `ReserveServer` est déprécié.
- **Configuration de la run** (classe, compagnon, monde, tier) : le lobby l'écrit dans une **MemoryStore** indexée par l'identifiant du serveur réservé ; le serveur de run la lit là. On n'utilise plus `TeleportData`, que le joueur peut falsifier.
- **Passage de relais des données** : le lobby **libère le profil** du joueur avant la téléportation. Sans ça, le serveur de run attend l'expiration du verrou (30 à 90 s) : c'est le principal risque de données d'un jeu à deux places.
- Retour au lobby en fin de run avec les gains déjà sauvegardés côté run, même règle de libération dans l'autre sens.

### 12.2 Ennemis

- Le serveur stocke chaque ennemi dans des tableaux (position, PV, type, cible) et les fait avancer à 15 Hz avec un déplacement simple vers la cible + séparation via **grille spatiale** (cellules de 8 studs) : pas de PathfindingService pour l'essaim.
- **Réplication par zone d'intérêt** : chaque client ne reçoit que les ennemis dans un rayon autour de lui (≈ 120 studs), calculé avec la grille spatiale existante.
- **Paquets découpés** : un `UnreliableRemoteEvent` jette silencieusement toute charge de plus de 1 000 octets. Un ennemi pèse ≈ 7 octets (id u16, x et z en i16, état u8), donc 300 ennemis ≈ 2,1 Ko ne passeraient jamais. Chaque tick est découpé en morceaux de **900 octets maximum** (≈ 125 ennemis par paquet).
- **Ordre** : les paquets non fiables arrivent dans le désordre ; chaque paquet porte un numéro de tick en en-tête et le client ignore tout paquet plus ancien que le dernier reçu.
- Le client interpole et place des modèles depuis un **pool** avec `workspace:BulkMoveTo()`.
- Le relief : hauteur lue sur une heightmap précalculée par stage (pas de raycast par ennemi par tick).
- Niveaux de détail : au-delà de 80 studs, modèle simplifié ; au-delà de 150, billboard.
- Plafond : 300 ennemis par serveur, 75 par joueur en coop à 4.

### 12.3 Combat

- Les armes tirent côté serveur (cadence, cibles, dégâts, critique), le client ne joue que les effets visuels à partir d'événements « tir » compacts.
- Le client n'envoie que ses entrées (choix de carte, ultime, ping) via des RemoteEvents validés : rate limit, type, valeur dans la liste des cartes proposées par le serveur.
- Projectiles visuels poolés, particules limitées selon un réglage qualité automatique (détection mobile bas de gamme).

### 12.4 Anti-triche

- Toute l'économie (XP, pièces, étoiles, quêtes) est calculée par le serveur.
- Contrôle de vitesse : distance parcourue entre deux contrôles comparée au maximum théorique (vitesse de classe + bonus + bunny-hop plafonné) ; dépassement répété = recalage.
- Aucune RemoteFunction qui donne une récompense sur demande du client.

### 12.5 Données

- Profil joueur avec **verrou de session**, sauvegarde automatique toutes les 60 s, `BindToClose`, numéro de version de schéma et migrations (une bibliothèque type ProfileStore fait gagner du temps). Libération explicite du profil avant chaque téléportation (12.1).
- Classements via `OrderedDataStore` (hebdo + all-time) ; clans via Communautés Roblox ou un DataStore « Bandes ».

### 12.6 Travail à plusieurs sans Rojo : Team Create + Script Sync + Git

Le CLI officiel de Roblox (la ligne de commande de Studio) sert à lancer Studio sur une place, une version ou un script précis et à exporter l'API ; il ne synchronise pas de code. L'outil officiel pour coder à plusieurs avec des fichiers est **Script Sync**, intégré à Studio et compatible Team Create — contrairement à Rojo.

**Répartition des rôles**

| Couche | Outil | Qui |
| --- | --- | --- |
| Cartes, modèles, UI, effets | Team Create (édition en direct dans Studio) | Builders, UI, VFX |
| Scripts | Script Sync → fichiers `.luau` sur disque, éditeur externe (VS Code, Cursor) | Développeurs |
| Historique et relecture du code | Dépôt Git des dossiers synchronisés (une branche par fonctionnalité) | Développeurs |
| Code commun lobby + run | **Packages** Roblox à mise à jour auto, synchronisés eux aussi | Lead dev |
| Ouvrir vite la bonne place / version | CLI de Studio (`--placeId`, `--universeId`, `--task EditPlace`) | Tout le monde |

**Arborescence dans Studio** (seuls ces trois dossiers sont synchronisés, ils ne contiennent que des scripts et des dossiers) :

```
ReplicatedStorage/Shared              -> shared/
  Config/ (Classes, Weapons, Grimoires, Items, Companions, Balance)
  Types.luau, Net.luau
ServerScriptService/Server            -> server/
  Main.server.luau
  Services/ RunManager, EnemyService, WeaponService, LootService, ShrineService,
            CompanionService, ProgressionService, DataService, MatchService
StarterPlayer/StarterPlayerScripts/Client -> client/
  Main.client.luau
  Controllers/ EnemyRenderer, WeaponFX, CardUI, HUD, MovementController, TraitController
```

Convention de noms sur disque : `nom.luau` = ModuleScript, `nom.server.luau` = Script serveur, `nom.client.luau` = Script client, `init.*.luau` = script avec enfants.

**Règles d'équipe**

- Un script = un seul éditeur à la fois (Script Sync prévient si un collègue synchronise le même arbre, mais deux personnes sur le même fichier s'écrasent).
- Pas d'attributs ni de tags sur les scripts (Script Sync les ignore, risque de perte) ; les modèles, sons et UI restent hors des dossiers synchronisés.
- Paramètre « Resume conflicted sync » laissé sur « Do not resume » : chaque conflit est tranché à la main.
- Extensions recommandées : Luau Language Server + plugin compagnon, selene (lint), StyLua (format).
- Toutes les valeurs d'équilibrage vivent dans `Shared/Config` : on rééquilibre sans toucher à la logique.

## 13. UI / UX

L'écran doit rester lisible au milieu de 200 ennemis sur un téléphone de 6 pouces : HUD réduit aux coins, cartes de niveau en bas, et des couleurs de rareté reconnaissables sans lire.

- **Haut gauche** : PV, bouclier, niveau + barre d'XP.
- **Haut centre** : chrono, gros et rouge sous 1:00 ; flèche vers le boss une fois révélé.
- **Haut droite** : mini-carte (autels en bleu, coffres en jaune, boss en rouge, coéquipiers en vert).
- **Bas gauche** : armes et Grimoires avec leur niveau.
- **Bas droite** (mobile) : Saut, Glisser, Ultime (jauge circulaire).
- **Cartes de niveau** : 3 cartes en bas, icône + 1 ligne de texte + bordure de rareté, choix au toucher sans pause en coop.
- **Écran de sélection** : le personnage du joueur tourne sur un socle ; changer de classe fait « pousser » le trait avec une petite animation.
- **Accessibilité** : mode daltonien pour les raretés, réduction des flashs, taille de texte réglable, sous-titres des annonces de vague.
- **Fin de run** : graphique des dégâts par arme, quêtes avancées en barres, bouton Rejouer mis en avant.

## 14. Roadmap et KPI

On sort un prototype jouable en 4 semaines pour valider le plaisir de la horde sur mobile, puis on élargit ; aucune phase ne démarre tant que la précédente n'a pas passé sa porte.

| Phase | Durée | Contenu | Porte de sortie |
| --- | --- | --- | --- |
| 0. Prototype | 4 sem. | Décision Server Authority (10.2) ; place Team Create + Script Sync + dépôt Git (12.6) ; Bois Grognon T1, 3 classes, 6 armes, 6 Grimoires, 1 compagnon, solo ; EnemyService + EnemyRenderer avec paquets découpés | 150 ennemis à 60 i/s sur un mobile milieu de gamme ; 5 testeurs sur 7 relancent une run d'eux-mêmes ; mesure du temps avant que la première run « accroche » |
| 1. Alpha coop | 4 sem. | Coop 1-4, mise à terre, autels, boss en 3 phases, sauvegarde, téléportation lobby → run avec libération de profil | 0 perte de données sur 200 sessions ; aucune attente de verrou à la téléportation ; run coop sans désynchro visible |
| 2. Bêta fermée | 4 sem. | 2e monde, 6 classes, 12 armes, 3 lignées de compagnons, 60 quêtes, lobby, pings | Rétention J1 ≥ 30 % sur 300 testeurs ; rebond à la première partie sous la cible |
| 3. Lancement | 3 sem. + délai d'évaluation | 3 mondes, 10 classes, 16 armes, 6 lignées, 150 quêtes, Survie, classements, boutique cosmétique ; dossier Select 9-15 (2-Step Verification, Plus ou frais par jeu, évaluation, classement Moderate max) ; miniature 16:9 personnalisée 1920×1080 | Approbation Select 9-15 obtenue avant l'ouverture ; checklist monétisation ; test de charge 50 serveurs |
| 4. Live ops | continu | Défi hebdo, 1 classe ou 1 monde par mois, événements saisonniers, clans | Voir KPI |

### 14.1 KPI à suivre

| KPI | Cible lancement |
| --- | --- |
| Rebond à la première partie (quitte pendant la 1re session) | À fixer après la bêta ; le plus bas possible (critère de recommandation depuis juin 2026) |
| Retour entre J8 et J28 | À fixer après la bêta (critère de recommandation depuis juin 2026, qui ne regarde plus le qPTR) |
| Rétention J1 / J7 / J30 | 30 % / 10 % / 4 % |
| Durée moyenne de session | ≥ 18 min |
| Runs par session | ≥ 2,5 |
| Part de runs en coop | ≥ 35 % |
| Taux de victoire T1 (tous joueurs) | 55-65 % |
| Conversion payeurs | 2-4 % |
| Crashs mémoire mobile | < 1 % des sessions |

### 14.2 Questions ouvertes

- Nom définitif et vérification de marque.
- Direction artistique : low-poly cartoon (recommandé pour la perf mobile) ou style plus détaillé ?
- Équipe : qui modélise les 10 traits × 4 stades (40 accessoires) et les 18 compagnons ?
- Lancement en français + anglais, ou anglais d'abord pour le volume ?

## 15. Sources

- [Megabonk — page Steam](https://store.steampowered.com/app/3405340/)
- [Dexerto — PokeBonk transforme Kanto en Megabonk](https://www.dexerto.com/pokemon/pokemon-fan-game-turns-kanto-into-megabonk-in-your-browser-3419791/)
- [Dexerto FR — PokeBonk, jeu gratuit navigateur](https://www.dexerto.fr/pokemon/jeu-gratuit-navigateur-transforme-pokemon-en-megabonk-1661797/)
- [Megabonk Wiki — World (cartes, tiers, mini-boss)](https://megabonk.wiki/wiki/World)
- [Destructoid — passer au stage suivant](https://www.destructoid.com/how-to-go-to-the-next-stage-in-megabonk/)
- [Selphie1999 Gaming — les autels](https://selphie1999gaming.com/game-guides/megabonk/megabonk-shrines-what-they-are-and-how-they-work/)
- [DTGRE — guide débutant (run de 10 min, Vague Finale)](https://www.dtgre.com/2025/10/megabonk-beginners-guide-survive-first-10-minute-run.html)
- [DTGRE — mouvement avancé](https://www.dtgre.com/2025/10/megabonk-advanced-movement-bunny-hop-sliding-guide.html)
- [Twinfinite — tier list des personnages](https://twinfinite.net/guides/megabonk-characters-tier-list/)
- [Twinfinite — tier list des tomes](https://twinfinite.net/guides/megabonk-tomes-tier-list/)
- [Lords of Gaming — test de Megabonk](https://lordsofgaming.net/2025/10/megabonk-review-a-bonk-tastic-3d-bullet-heaven)
- [Selphie1999 Gaming — 15 autels par stage, vagues à 6:00 et 3:00](https://selphie1999gaming.com/game-guides/megabonk/best-way-to-unlock-the-chaos-tome-in-megabonk/)
- [Roblox Creator Hub — Script Sync](https://create.roblox.com/docs/scripting/sync)
- [Roblox Creator Hub — Studio command-line interface](https://create.roblox.com/docs/studio/command-line-interface)
- Revue technique de Clément (4 nov. 2026) : réseau, reçus, téléportation, Select 9-15, KPI, Input Action System, Server Authority
