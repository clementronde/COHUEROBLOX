# 40 — Compagnons (domaine companion)

Chaque joueur emmène un Compagnon original qui le suit, attaque seul la cible la plus proche, apprend des techniques via les cartes de niveau, évolue deux fois pendant la run et déclenche un Ultime quand sa jauge est pleine. Tous les nombres ci-dessous vivent dans `shared/Config/Companions.luau` ; ce document en est la référence de conception.

Fichiers du domaine : `server/Services/CompanionService.luau`, `shared/Config/Companions.luau`, `client/Controllers/CompanionRenderer.luau`, ce dossier. (`shared/NetDefs/Companion.luau` n'est pas utilisé : les trois remotes du contrat suffisent.)

## 1. Ce qu'on prend à PokeBonk (et ce qu'on ne prend pas)

- **Pris** : un partenaire qui attaque tout seul, des cartes « nouvelle technique / renforcer / friandise », deux évolutions dans la run, un Ultime sur jauge. Ce sont des mécaniques, non protégeables.
- **Pas pris** : aucune créature, aucun nom, cri, type ou silhouette Pokémon. Pas de trio plante/feu/eau : six **affinités** maison, des silhouettes en blocs low-poly construites en code (aucun asset importé), des noms français/anglais inventés. Les silhouettes ci-dessous évitent volontairement les archétypes connus (pas de souris jaune à joues rouges, pas de tortue-volcan, pas de lézard à flamme au bout de la queue).

## 2. Les 6 affinités et leurs effets

L'attaque de base de chaque Compagnon applique l'effet de son affinité. Les effets passent par `EnemyService.applyStatus(id, status, params)` ; les paramètres envoyés sont listés dans la colonne « params ».

| Affinité (id) | FR / EN | Effet (attaque de base) | Stade 1 / 2 / 3 | params `applyStatus` |
| --- | --- | --- | --- | --- |
| `Braise` | Braise / Ember | **Brûlure** | 2 / 4 / 7 dégâts/s pendant 3 s | `Burn { dps, duration, source }` |
| `Ronce` | Ronce / Bramble | **Poison** + **Ralenti** | poison 1,5 / 3 / 5 dps 4 s ; ralenti ×0,75 2 s | `Poison { dps, duration, source }`, `Slow { mult, duration, source }` |
| `Maree` | Marée / Tide | **Recul** (+ soin d'équipe via techniques/Ultime) | recul 4 / 5 / 6 studs | `Knockback { fromX, fromZ, distance, source }` |
| `Volt` | Volt / Volt | **Chaîne** : le coup rebondit | 1 / 2 / 3 rebonds à 60 % des dégâts, portée 10 studs | (dégâts directs, pas de statut) |
| `Givre` | Givre / Frost | **Ralenti**, puis **Gel** au 4e coup sur la même cible ; **Fragile** : +30 % de dégâts du Compagnon sur une cible gelée | ralenti ×0,7 2 s ; gel 1 / 1,25 / 1,5 s | `Slow`, `Freeze { duration, source }` |
| `Echo` | Écho / Echo | **Étourdit** (chance par coup) ; révèle les coffres (voir 13, demande de contrat) | 15 % / 20 % / 25 % d'étourdir 0,8 s | `Stun { duration, source }` |

`Fragile` (Givre) est calculé côté CompanionService (il garde l'heure de fin de gel de chaque cible qu'il a gelée), pour ne pas dépendre d'un statut que l'EnemyService n'a pas.

## 3. Les 6 lignées × 3 stades

Noms FR du dossier de vision, noms EN proposés ici (à vérifier en marque). Taille = hauteur approximative du modèle en studs.

| Lignée | Stade 1 | Stade 2 | Stade 3 |
| --- | --- | --- | --- |
| `Braise` | **Tisonnet** / Tinderling — lézard-allumette : corps orange trapu, tête ronde avec une « tête d'allumette » rouge vif sur le crâne, petite queue ; 2 studs | **Fournaïde** / Furnacid — lézard debout, ventre en porte de four qui rougeoie, deux cheminées sur les épaules ; 3 studs | **Volcarapace** / Volcashell — gros lézard à quatre pattes, dos couvert de plaques sombres d'où sortent trois évents rougeoyants ; 4,5 studs |
| `Ronce` | **Pousseron** / Sproutlet — gland qui marche : corps ovale brun, chapeau de gland, deux pieds et une pousse verte ; 2 studs | **Ronciflore** / Bramblebloom — gland fendu d'où sort une couronne de ronces fleuries, bras-lianes ; 3 studs | **Sylvogarde** / Sylvaward — souche-gardienne trapue, bras de ronces épais, couronne de fleurs roses ; 4,5 studs |
| `Maree` | **Gouttelot** / Dropple — têtard dans une bulle d'eau transparente, petite queue qui dépasse ; 2 studs (flotte) | **Ondelin** / Wavelin — amphibien rond à crête en forme de vague, nageoires-mains ; 3 studs | **Abyssale** / Abyssa — raie flottante bleu nuit, ailes larges, petite lanterne turquoise ; 4,5 studs (flotte) |
| `Volt` | **Grésillon** / Fizzlet — souris-pile : corps cylindrique sarcelle à bandes cuivre, borne sur la tête, queue-câble ; 2 studs | **Ampérat** / Amperat — rat plus long, queue en bobine de cuivre, oreilles-condensateurs ; 3 studs | **Fulgurex** / Fulgurex — furet long sur quatre pattes, deux antennes-paratonnerres, dos à arcs lumineux ; 4,5 studs |
| `Givre` | **Flocon** / Flurry — boule de neige à pattes de pingouin, bec orange, écharpe bleue ; 2 studs | **Stalagmo** / Stalagmo — pingouin trapu, dos hérissé de stalactites ; 3 studs | **Glaciarque** / Glaciarch — pingouin-chevalier massif, couronne et épaulières de glace ; 4,5 studs |
| `Echo` | **Pipistrou** / Pipistrill — chauve-souris ronde dont le ventre est un haut-parleur (cône), grandes oreilles ; 2 studs (vole) | **Résonar** / Resonar — chauve-souris à ailes-pavillons, deux haut-parleurs ; 3 studs (vole) | **Tonnerlune** / Thundermoon — grande chauve-souris à croissant de lune sur le front, ailes-caissons de basse ; 4,5 studs (vole) |

### 3.1 Stats de base par stade (attaque de base)

Dégâts finaux = base × (1 + 0,5 × Dégâts du propriétaire) × (1 + Friandise Puissance) × (1 + bonus Lien) × (1 + synergie). La moitié du stat `Damage` du joueur est héritée pour que le Compagnon reste utile en fin de run sans voler la vedette aux armes.

| Lignée | Stade 1 dégâts / intervalle / portée | Stade 2 | Stade 3 | Rôle |
| --- | --- | --- | --- | --- |
| Braise | 7 / 1,0 s / 22 | 16 / 0,9 s / 24 | 34 / 0,8 s / 26 | Zone (éclaboussure 3 / 4 / 5 studs) |
| Ronce | 5 / 1,0 s / 22 | 12 / 0,9 s / 24 | 26 / 0,8 s / 26 | Contrôle, poison |
| Maree | 5 / 1,1 s / 24 | 12 / 1,0 s / 26 | 25 / 0,9 s / 28 | Soutien, recul |
| Volt | 6 / 0,9 s / 22 | 13 / 0,8 s / 24 | 27 / 0,7 s / 26 | Chaîne |
| Givre | 6 / 1,2 s / 22 | 14 / 1,1 s / 24 | 30 / 1,0 s / 26 | Gel, défense |
| Echo | 5 / 0,9 s / 26 | 11 / 0,8 s / 28 | 24 / 0,7 s / 30 | Utilitaire (portée longue) |

Vitesse de suivi : 1,5 × la vitesse de marche de base (16) = 24 studs/s, téléportation derrière le joueur au-delà de 60 studs. Distance de suivi : 5 studs derrière, 2 studs sur le côté.

## 4. Évolutions : niveau du joueur (décision)

**Décision : le Compagnon n'a pas d'XP propre ; son niveau = niveau de run du propriétaire** (`StatsService.getLevel`, mis à jour par `Bus.PlayerLeveledUp`). Évolution au **niveau 8** (stade 2) et au **niveau 20** (stade 3).

Pourquoi : une seule barre d'XP à lire sur mobile ; l'évolution tombe sur un moment déjà fort (le level-up) ; en coop, le Compagnon ne peut pas prendre de retard parce qu'il a moins tué ; la courbe d'XP est déjà équilibrée par le domaine combat (10 min ≈ niveau 25-30). Les Friandises compensent le manque de progression propre.

Moment d'évolution (fiche vault « Reward Moments and Celebrations » : anticipation puis révélation, sans bloquer le jeu) : flash blanc 0,5 s qui gonfle, anneau de couleur d'affinité, le nouveau modèle apparaît avec un « pop » d'échelle (0,6 → 1,1 → 1) ; pendant 1,5 s le Compagnon est invulnérable de toute façon (il ne peut pas mourir) et continue d'attaquer. `Bus.CompanionEvolved(player, stage)` est tiré à chaque évolution.

## 5. Techniques (max 3 par Compagnon)

- Chaque lignée a **4 techniques**. Le Compagnon en connaît **1 au départ** (technique de départ, choisie via le Lien, voir 9) et peut en apprendre **2 de plus** par cartes : 3 au maximum.
- Niveau 1 à 5. Formes : `Target` (cible la plus proche, éclaboussure optionnelle), `Nova` (zone autour du Compagnon), `Aura` (zone autour du propriétaire), `Chain` (rebonds), `Heal` (soin d'équipe dans un rayon).
- Les dégâts des techniques suivent la même formule que l'attaque de base.

Valeurs par niveau (1 → 5). « dmg » = dégâts, « cd » = recharge (s), « r » = rayon (studs).

### Braise
| id | FR / EN | Forme | dmg | cd | r | Effet |
| --- | --- | --- | --- | --- | --- | --- |
| `EmberSpit` | Crachat de braise / Ember Spit | Target | 12 / 16 / 21 / 27 / 35 | 3,0 / 2,8 / 2,6 / 2,4 / 2,2 | éclab. 5 | Brûlure 4 / 5 / 6 / 8 / 10 dps 3 s |
| `FlameRing` | Cercle de flammes / Flame Ring | Nova | 10 / 14 / 18 / 23 / 30 | 6 / 5,5 / 5 / 4,5 / 4 | 8 / 9 / 10 / 11 / 12 | Brûlure 3 / 4 / 5 / 6 / 8 dps 3 s |
| `CinderTrail` | Cendres chaudes / Cinder Trail | Aura (joueur) | 4 / 5 / 7 / 9 / 12 | 1,0 | 6 / 6,5 / 7 / 7,5 / 8 | dégâts par tic autour du joueur |
| `FireComet` | Comète de feu / Fire Comet | Target | 40 / 55 / 70 / 90 / 120 | 9 / 8,5 / 8 / 7,5 / 7 | éclab. 8 | Brûlure 6 / 8 / 10 / 12 / 15 dps 3 s |

### Ronce
| id | FR / EN | Forme | dmg | cd | r | Effet |
| --- | --- | --- | --- | --- | --- | --- |
| `ThornShot` | Tir d'épines / Thorn Shot | Target | 8 / 11 / 14 / 18 / 23 | 2,5 / 2,4 / 2,3 / 2,2 / 2,0 | — | Poison 3 / 4 / 5 / 6 / 8 dps 4 s |
| `BrambleField` | Champ de ronces / Bramble Field | Nova | 6 / 8 / 10 / 13 / 16 | 7 / 6,5 / 6 / 5,5 / 5 | 9 / 10 / 11 / 12 / 13 | Ralenti ×0,6 3 s + poison 2 / 3 / 4 / 5 / 6 dps |
| `SporePuff` | Bouffée de spores / Spore Puff | Aura (joueur) | 3 / 4 / 5 / 6 / 8 | 1,5 | 6 / 6,5 / 7 / 7,5 / 8 | Poison 2 / 2,5 / 3 / 4 / 5 dps 3 s |
| `RootSnare` | Piège racine / Root Snare | Target | 15 / 20 / 26 / 33 / 42 | 8 / 7,5 / 7 / 6,5 / 6 | éclab. 6 | Étourdit 1,0 / 1,2 / 1,4 / 1,6 / 2,0 s |

### Marée
| id | FR / EN | Forme | dmg | cd | r | Effet |
| --- | --- | --- | --- | --- | --- | --- |
| `BubbleShot` | Tir de bulle / Bubble Shot | Target | 9 / 12 / 16 / 20 / 26 | 2,5 / 2,4 / 2,3 / 2,2 / 2,0 | — | Recul 6 studs |
| `TideRing` | Anneau de marée / Tide Ring | Nova | 8 / 11 / 14 / 18 / 23 | 6 / 5,5 / 5 / 4,5 / 4 | 9 / 10 / 11 / 12 / 13 | Recul 8 studs |
| `Spring` | Source fraîche / Spring | Heal | — | 12 / 11 / 10 / 9 / 8 | 30 | Soigne chaque coéquipier actif dans le rayon de 4 / 5 / 6 / 7 / 8 % PV max |
| `Geyser` | Geyser / Geyser | Target | 30 / 40 / 52 / 66 / 85 | 9 / 8,5 / 8 / 7,5 / 7 | éclab. 7 | Recul 10 studs |

### Volt
| id | FR / EN | Forme | dmg | cd | r | Effet |
| --- | --- | --- | --- | --- | --- | --- |
| `Spark` | Étincelle / Spark | Chain | 8 / 10 / 13 / 17 / 22 | 2,5 / 2,4 / 2,3 / 2,2 / 2,0 | saut 10 | 3 / 3 / 4 / 4 / 5 cibles |
| `StaticField` | Champ statique / Static Field | Aura (joueur) | 4 / 5 / 7 / 9 / 12 | 1,0 | 6 / 6,5 / 7 / 7,5 / 8 | dégâts par tic |
| `ThunderPounce` | Bond tonnerre / Thunder Pounce | Target | 25 / 34 / 44 / 56 / 72 | 7 / 6,5 / 6 / 5,5 / 5 | éclab. 5 | Étourdit 0,6 / 0,7 / 0,8 / 0,9 / 1,0 s |
| `BallLightning` | Boule d'éclair / Ball Lightning | Chain | 18 / 24 / 31 / 40 / 52 | 8 / 7,5 / 7 / 6,5 / 6 | saut 12 | 6 / 7 / 8 / 9 / 10 cibles |

### Givre
| id | FR / EN | Forme | dmg | cd | r | Effet |
| --- | --- | --- | --- | --- | --- | --- |
| `FrostShard` | Éclat de givre / Frost Shard | Target | 10 / 13 / 17 / 22 / 28 | 2,5 / 2,4 / 2,3 / 2,2 / 2,0 | — | Ralenti ×0,6 2 s |
| `IceRing` | Anneau de glace / Ice Ring | Nova | 8 / 11 / 14 / 18 / 23 | 8 / 7,5 / 7 / 6,5 / 6 | 8 / 9 / 10 / 11 / 12 | Gel 1,0 / 1,2 / 1,4 / 1,6 / 2,0 s |
| `HailVeil` | Voile de grêle / Hail Veil | Aura (joueur) | 3 / 4 / 5 / 7 / 9 | 1,0 | 6 / 6,5 / 7 / 7,5 / 8 | Ralenti ×0,7 1,5 s |
| `GlacierSpike` | Pic glaciaire / Glacier Spike | Target | 35 / 48 / 62 / 80 / 100 | 9 / 8,5 / 8 / 7,5 / 7 | éclab. 6 | Gel 1,5 / 1,7 / 1,9 / 2,1 / 2,5 s |

### Écho
| id | FR / EN | Forme | dmg | cd | r | Effet |
| --- | --- | --- | --- | --- | --- | --- |
| `SonicPing` | Ping sonique / Sonic Ping | Target | 8 / 11 / 14 / 18 / 23 | 2,0 / 1,9 / 1,8 / 1,7 / 1,5 | — | Étourdit 0,5 s |
| `Screech` | Cri perçant / Screech | Nova | 8 / 11 / 14 / 18 / 23 | 7 / 6,5 / 6 / 5,5 / 5 | 10 / 11 / 12 / 13 / 14 | Étourdit 1,0 / 1,1 / 1,2 / 1,4 / 1,6 s |
| `Ricochet` | Ricochet / Ricochet | Chain | 10 / 13 / 17 / 22 / 28 | 3 / 2,9 / 2,8 / 2,7 / 2,5 | saut 12 | 3 / 4 / 4 / 5 / 6 cibles |
| `Resonance` | Résonance / Resonance | Aura (joueur) | 4 / 5 / 7 / 9 / 12 | 1,0 | 7 / 7,5 / 8 / 8,5 / 9 | dégâts par tic |

## 6. Friandises (cartes `CompanionTreat`)

Bonus additifs pour la run, cumulables jusqu'à 10 fois chacune. Rareté tirée : Commune 60 %, Rare 30 %, Épique 10 %.

| id | FR / EN | Commune / Rare / Épique |
| --- | --- | --- |
| `TreatPower` | Biscuit costaud / Hearty Biscuit | +8 % / +12 % / +18 % dégâts du Compagnon |
| `TreatHaste` | Bonbon pétillant / Fizzy Candy | +6 % / +9 % / +14 % vitesse d'attaque (intervalle et recharges ÷) |
| `TreatReach` | Baie longue-vue / Spyglass Berry | +8 % / +12 % / +18 % portée et rayons |
| `TreatSpirit` | Miel d'étoile / Star Honey | +8 % / +12 % / +18 % gain de jauge d'Ultime |

## 7. Ultimes

Jauge de 0 à 100. Gains (multipliés par Miel d'étoile et la synergie) :

| Source | Gain |
| --- | --- |
| Passif | 0,5 / s (Compagnon non sonné, run en cours) |
| Ennemi tué par le propriétaire | 0,25 |
| Ennemi tué par le Compagnon | 1 |
| Élite tuée (propriétaire ou Compagnon) | +5 |
| Dégâts encaissés par le propriétaire | 0,2 par PV perdu |
| Level-up du propriétaire | +5 |
| `CompanionService.chargeUltimate(player, n)` | n (objets, autels…) |

Objectif : un Ultime toutes les 60-90 s en milieu de run. Utilisation refusée si : jauge < 100, Compagnon sonné, propriétaire à terre ou fantôme (`RunManager.isActive` faux), phase hors `Running`/`Boss`/`BossDefeated`/`FinalWave`, ou moins de 1 s depuis le dernier.

| Lignée | Ultime FR / EN | Effet (dégâts × formule de 3.1) |
| --- | --- | --- |
| Braise | Pluie de cendres / Ash Rain | 6 s, zone de 18 studs qui suit le propriétaire : 4 tics/s de 10 dégâts + Brûlure 8 dps 3 s |
| Ronce | Racines géantes / Giant Roots | Tous les ennemis à 60 studs (« l'écran ») étourdis (immobilisés) 3 s + poison 6 dps 4 s |
| Maree | Grande vague / Great Wave | Soigne chaque coéquipier actif de 40 % de ses PV max (toute l'équipe) ; recul 12 studs + 30 dégâts à 20 studs |
| Volt | Orage / Thunderstorm | Jusqu'à 30 cibles à 60 studs frappées en 1,5 s, 80 dégâts chacune |
| Givre | Blizzard / Blizzard | Ennemis à 50 studs gelés 4 s + 20 dégâts |
| Echo | Cri lunaire / Moon Howl | Ennemis à 45 studs étourdis 2,5 s + 25 dégâts ; révèle le boss (demande de contrat, section 13) |

Contrôle (dossier vision 10) : **E** au clavier, bouton **Ultime** sur mobile (jauge circulaire dessinée par l'UI), **Y** à la manette. Le domaine avatar déclare l'`InputAction` `"Ultimate"` ; le Compagnon l'écoute (section 12).

## 8. Synergies Classe × affinité (+10 %)

Quand l'affinité du Compagnon correspond à la classe : **+10 % dégâts du Compagnon et +10 % de gain de jauge**. Jamais obligatoire.

| Classe | Affinité en synergie | Raison |
| --- | --- | --- |
| `Cornu` | Braise | cornes en flammes au niveau 30 |
| `Plumeline` | Maree | oiseau marin, vent et embruns |
| `Mecano` | Volt | bras mécanique (dossier vision) |
| `Felyne` | Volt | griffes éclair |
| `Rocailleux` | Ronce | plaques couvertes de mousse |
| `Sporelin` | Ronce | spores et poison (dossier vision) |
| `Ecaille` | Braise | souffle de braise (dossier vision) |
| `Astrel` | Echo | lune et étoiles (Tonnerlune) |
| `Cristallin` | Givre | cristaux de glace |
| `Tentaculos` | Maree | créature des profondeurs |

## 9. Lien (méta-progression 1-30)

Stocké par le domaine data (`profile.bond[line]`, défaut 1). Gain proposé au domaine data : +1 par run terminée avec ce Compagnon, +1 si stade 3 atteint (`RunSummary.companionStage == 3`), +1 si victoire, plafond 30.

| Niveau | Récompense |
| --- | --- |
| 3, 6, 9 … 30 | +1 % dégâts du Compagnon par palier → **+10 % maximum** au niveau 30 (règle : jamais plus de +10 % de stats brutes) |
| 1 | Technique de départ n° 1 |
| 5 | Technique de départ alternative n° 2 |
| 15 | Technique de départ alternative n° 3 |
| 25 | Technique de départ alternative n° 4 |
| 4 / 10 / 20 / 28 | Teintes 1 / 2 / 3 / 4 (cosmétique pur) |
| 12 | Pose de victoire du Compagnon |
| 30 | Titre « Inséparable » / "Inseparable" |

La technique de départ est lue dans `profile.companionStartTech[line]` si elle existe et si le Lien la débloque, sinon technique n° 1 (demande de contrat au domaine data).

## 10. Coop et règle « sonné »

- Le Compagnon **ne peut pas mourir**. Quand son propriétaire est mis à terre (`Bus.PlayerDowned`), il est **sonné 5 s** (n'attaque pas, ne charge pas, reste près du joueur, étoiles au-dessus de la tête), puis il **garde** son propriétaire à terre en attaquant autour de lui. Relevé (`Bus.PlayerRevived`) : sonné annulé. Mort définitive (`Bus.PlayerDied`) : le Compagnon reste sonné jusqu'à la fin de la run.
- Les kills du Compagnon sont crédités au propriétaire (`EnemyService.damage(id, n, owner)`), donc XP, butin et quêtes lui reviennent.
- À plusieurs, les Compagnons se répartissent les cibles : à chaque tic, une cible déjà prise par un autre Compagnon est évitée s'il existe une autre cible à portée.
- Grande vague (Marée) soigne **toute l'équipe** ; Spring soigne les coéquipiers dans 30 studs : la lignée soutien a de la valeur en coop.

## 11. Collection et œufs gratuits

- Départ : **Braise, Ronce, Maree** débloqués. **Volt, Givre, Echo** par quêtes ou œufs.
- **Œuf de Compagnon** : gagné uniquement en jouant (1 par quête compagnon terminée, 1 au premier boss de chaque monde, 1 tous les 10 niveaux de maîtrise cumulés). Jamais vendu en Robux, jamais achetable avec une monnaie achetable en Robux (ni Étoiles d'argent si un jour elles deviennent achetables) : sinon c'est un **objet aléatoire payant** (règle Roblox citée par le vault : un résultat aléatoire acheté directement ou indirectement en Robux, y compris via une monnaie payante ; les récompenses gagnées sans Robux ni monnaie payante en sont exemptées).
- **Taux affichés** quand même (bonne pratique, et prêts si la règle change) : sur les Compagnons non encore possédés, chance égale : 3 restants → 33,33 % chacun, 2 → 50 %, 1 → 100 %. Si tous sont possédés : l'œuf donne +3 niveaux de Lien au Compagnon choisi (pas de doublon inutile). La table affichée et la table tirée sont **la même** (`Companions.Eggs`). Le tirage est fait par le domaine data.
- Pas de « luck boost » payant, pas de pitié payante.

## 12. Réseau, rendu et contrôle de l'Ultime

- **Serveur** : simulation à 10 Hz (`Companions.SimHz`), positions en données (aucune Instance serveur par Compagnon). Cibles via `EnemyService.queryRadius` + `getPosition`.
- **CompanionSnapshot (non fiable)** : 10 Hz, à tous les clients. Format maison : en-tête 5 octets (`tick u32`, `count u8`) + 23 octets par Compagnon (`userId f64`, `x/y/z i16` au 1/4 de stud, `yaw u8`, `flags u8` = lignée 3 bits | stade 2 bits | sonné | ultime actif, `evSeq u8`, `evKind u8`, `evX/evZ i16`, `evRadius u8`). 38 Compagnons par paquet ≤ 900 octets (limite vault : au-delà de 1 000 octets un paquet non fiable est perdu). Encodage dans le service, décodage dans le renderer, constantes partagées dans la config.
- **CompanionState (fiable)** : au propriétaire, à chaque changement (jauge arrondie à l'entier, max 4/s).
- **Client** : modèles low-poly en Parts ancrées sans collision ni requête, construits par stade, interpolés entre deux échantillons (fiche « Snapshot Interpolation »), un seul `BulkMoveTo` par frame. Sautillement procédural, VFX de projectiles / anneaux / flash d'évolution / Ultime en pools bornés.
- **Déclencher l'Ultime** :
  - Clavier / manette : le domaine avatar expose `InputController.onAction("Ultimate", fn)` ; `CompanionRenderer.start()` s'y abonne.
  - Bouton UI : le domaine ui appelle `Registry.get("CompanionRenderer").requestUltimate()` (client). L'état pour la jauge : `CompanionRenderer.getState()` et `CompanionRenderer.onStateChanged(fn)` (payload `CompanionState`).
  - Les deux chemins font `Net.event("CompanionUltimate"):FireServer()` ; le serveur valide (limite 2/s).

## 13. Clés de quêtes rapportées

`ProgressionService.recordStat(player, key, n)` : `CompanionEvolved` (1 par évolution), `CompanionStage3` (1 au stade 3), `UltimatesUsed` (1), `CompanionKills` (n), `CompanionTechsLearned` (1 par nouvelle technique), `CompanionTreats` (1).

## 14. Sources vault

- *Pet Hatching and Following End to End* — modèles de suivi côté client uniquement, pas de modèles serveur avec `AlignPosition`, parts ancrées `CanQuery=false`, téléportation au-delà d'une distance.
- *Snapshot Interpolation for Custom Replication* — interpolation entre échantillons, non fiable pour l'état, fiable pour les événements.
- *RemoteEvent - Engine Reference Card* et *RemoteEvents RemoteFunctions and Unreliable Remotes* — 1 000 octets max par paquet non fiable (Roblox docs), ~500 appels/s par client et par type, validation + limite de débit sur chaque remote C→S.
- *NPC AI and Behaviour* / *Luau Performance and Native Codegen* — cerveaux à 10 Hz, une boucle partagée, aucune allocation par frame.
- *VFX Performance Budgets and Culling*, *Juice on a Budget*, *Particle Emitters In Depth* — pools bornés, effets créés côté client, pas de création/destruction par coup.
- *Reward Moments and Celebrations* — anticipation puis révélation pour l'évolution, sans bloquer.
- *Roblox Policies Ratings and Compliance* et *Paid Random Items and Odds Disclosure in Practice* (Roblox docs, oct. 2026) — définition d'objet aléatoire payant, exemption des récompenses gagnées sans Robux, une seule table pour l'affichage et le tirage.
- *Rebinding Controls with the Input Action System*, *Input - UserInputService and ContextActionService* — une `InputAction` par mécanique, nom stable, `Pressed` ; un bouton tactile se lie à l'action.
- *Case Study - Adopt Me* — la progression visible sur la créature elle-même (stade, lueur) fidélise.
