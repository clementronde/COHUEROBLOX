# Fiches Claude Design : ennemis et boss (A03)

Clément fait les modèles lui-même avec Claude Design. A03 écrit une fiche prête à coller par modèle, puis, au signal du coordinateur, les emballe dans COHUE : nom, échelle et attributs.

**Style retenu par Clément le 5 nov. 2026 : celui de son fantôme** (« On va refaire tous les models dans le style de ce ghost »). Il remplace les tenons de la planche concept d'A03 ; la planche ne sert plus que de référence pour les formes et les gags.

## Où Clément range les modèles

Dans `C:\Users\Charment\COHUE\assets\claude-design\<NomDeContrat>\`, un dossier par modèle, avec tout ce que Claude Design donne :
- le `.glb` ;
- le `README.md` de handoff ;
- le script `*Controller.server.lua`.

A03 y lit les fichiers directement : plus besoin de les envoyer. Les versions corrigées pour COHUE restent dans `assets/a03/<modèle>/`.

## Zone des mobs dans COHUE

`Workspace.A03_ZoneMobs` (x 398 à 464, z 762 à 788, à côté du kit d'A01) aligne les modèles de Clément déjà installés, chacun sur un socle avec son nom :
- Gobelin ;
- Zombie ;
- Chauve-souris ;
- Squelette ;
- Fantôme.

Ils regardent vers −Z, c'est-à-dire vers le côté libre du sol. Les socles sont espacés de 12 studs. Pour un nouveau modèle, ajouter un socle 12 studs plus loin en x (466) et allonger le sol.

Dans la zone, `Damage` vaut 0 sur chaque mob, pour pouvoir les regarder de près en Play. Remettre la valeur de la fiche pour tester les dégâts.

## Conventions communes (celles du fantôme)

| Règle | Détail |
| --- | --- |
| Style | Voxels lisses en SmoothPlastic, sans tenons. Deux tons par matière, une couleur de base et une ombre (comme le blanc `F3F1FF` et le lilas `C9C0F4` du fantôme). Yeux noirs avec un reflet blanc en Neon. Petites joues roses pastel permises |
| Noms | Une MeshPart par couleur, le code hexadécimal à la fin du nom : `body_skin_8FD13F`, `arm_R_steel_8EA6C2` |
| Pièces | Les parties qui bougent sont séparées (`arm_R`, `arm_L`, `leg_L`, `leg_R`, `tail_1..n`, `hat`…) ; tout le reste va dans `body_*` |
| Script | Un script contrôleur, comme `GhostController` : animations, attaque et attributs (`Walking` ou `Flying`, `AutoAttack`, `AttackEvery`, `Attack`, `Dead`) |
| Face | Vers −Z, comme le fantôme. Pieds au sol |
| Taille | La hauteur finale en studs est donnée dans chaque fiche. Si l'export arrive à une autre échelle, A03 la corrige à l'emballage (le fantôme est arrivé à 2 studs et a été agrandi ×2) |
| Budget de horde | Ennemi ordinaire : 800 triangles et 8 mailles au plus. Mini-boss : 6 000 triangles. Boss : 15 000 triangles |
| Couleurs réservées | Pas de cyan ni de bleu clair (l'XP), pas de rose vif `FF5FB0` (la capture), pas de Neon sur le corps (hors reflet des yeux). Le rouge sert aux ennemis de mêlée et aux dangers |
| À éviter | Toute ressemblance avec un personnage connu (Mario, Toad, Goomba, Blue de Rainbow Friends, Cookie Monster, Yoshi, lutin de Noël…) ; aucun texte ni logo |

## Les modèles à créer

**21 ennemis et boss** (roster du dossier 13 §3), plus 8 petits objets d'attaque optionnels.

### Monde 1 : Bois Grognon (forêt, gobelins et faune)

| # | Nom de contrat | Rôle | Description et gag | Taille (studs) | Fiche |
| --- | --- | --- | --- | --- | --- |
| 1 | `Enemy_GoblinGrunt` | Mêlée, le plus courant | Gobelin vert, cocotte rouge sur la tête, louche brandie | 4,5 | [prête](Enemy_GoblinGrunt.md) |
| 2 | `Enemy_GoblinArcher` | Tireur | Gobelin, capuche vert sombre à pointe et plume crème, grand arc ; flèches à ventouse | 5 | à écrire |
| 3 | `Enemy_GoblinShaman` | Soutien | Gobelin en robe violette, théière violette sur la tête, bâton de berger | 4,75 | à écrire |
| 4 | `Enemy_GoblinBomber` | Kamikaze | Gobelin, bonnet d'aviateur orange et lunettes, grosse bombe noire à mèche | 3,75 | à écrire |
| 5 | `Enemy_GrumpyAcorn` | Essaim (faune) | Gland grognon à gros sourcils, chapeau en écailles | 3,1 | à écrire |
| 6 | `Enemy_Hopshroom` | Sauteur (faune) | Champignon qui bondit ; chapeau brun-orange à taches crème irrégulières (pas de pois blancs sur rouge : trop proche d'un champignon connu) | 3,6 | à écrire |
| 7 | `Enemy_DivingOwl` | Tireur (faune) | Hibou tout rond, grandes ailes, lance des plumes | 3,4 | à écrire |
| 8 | `MiniBoss_GoblinChief` | Mini-boss | Gros gobelin ventru, couronne en capsules, couvercle de marmite en bouclier, louche géante | 9 | à écrire |
| 9 | `Boss_GrumpyGreatOak` | Boss | Chêne-souche grognon, sourcils de mousse, bras-branches, couronne de feuilles | 18 | à écrire |

### Monde 2 : cimetière et marais (zombies)

| # | Nom de contrat | Rôle | Description et gag | Taille (studs) | Fiche |
| --- | --- | --- | --- | --- | --- |
| 10 | `Enemy_ZombieShambler` | Mêlée | Zombie gris voûté, bras tendus devant, chemise rouge en lambeaux | 4 | à écrire |
| 11 | `Enemy_ZombieRunner` | Sauteur | Zombie ballerine : tutu violet clair, chaussons, bandeau rouge ; il bondit en grand jeté | 4,25 | à écrire |
| 12 | `Enemy_ZombieGravedigger` | Tireur | Zombie en haut-de-forme avec une pelle ; lance des mottes de terre | 4,25 | à écrire |
| 13 | `Enemy_ZombieBloater` | Kamikaze | Gros ventre orange citrouille, toute petite tête ; il éclate | 4,5 | à écrire |
| 14 | `MiniBoss_ZombieOgre` | Mini-boss | Ogre zombie énorme qui traîne une pierre tombale comme un doudou | 9,5 | à écrire |
| 15 | `Boss_HungryCoffin` | Boss | Cercueil affamé debout sur quatre mains de zombie ; le couvercle s'ouvre en bouche ; serviette, fourchette et couteau | 16 | à écrire |

### Monde 3 : Récré Fantôme (école hantée, fantômes)

| # | Nom de contrat | Rôle | Description et gag | Taille (studs) | Fiche |
| --- | --- | --- | --- | --- | --- |
| 16 | `Enemy_GhostWisp` | Mêlée | Petit fantôme avec une casquette rouge d'écolier | 3,5 | à écrire |
| 17 | `Enemy_GhostPoltergeist` | Tireur | **Le fantôme de Clément (`Ghostenemy`)** : il lance son orbe | 4,16 (fait) | proposé : déjà fait |
| 18 | `Enemy_GhostBanshee` | Soutien | Fantôme sous un voile violet à capuche, bouche ronde qui crie | 4,25 | à écrire |
| 19 | `Enemy_HauntedArmor` | Blindé | Armure vide en acier, deux yeux qui flottent dans le heaume, pointeur de tableau en guise de lance | 5 | à écrire |
| 20 | `MiniBoss_SpectralProctor` | Mini-boss | Surveillant fantôme géant, sifflet, brassard jaune | 9 | à écrire |
| 21 | `Boss_EternalHeadmistress` | Boss | Directrice fantôme : chignon, lunettes en demi-lune, règle géante, robe en cloche | 18 | à écrire |

### Objets d'attaque (petits, optionnels)

Ce sont des objets lancés, en voxels comme le reste (règle « des blocs pour ce qui existe »). Les lueurs et les traînées restent des effets.

| Nom | Lancé par |
| --- | --- |
| `Projectile_Arrow` | Goblin Archer (flèche à ventouse rouge) |
| `Projectile_Feather` | Diving Owl |
| `Projectile_DirtClod` | Zombie Gravedigger |
| `Projectile_Book` | Poltergeist, si on garde les livres en plus de son orbe |
| `Boss_Acorn` | Grumpy Great Oak (pluie de glands) |
| `Boss_Bone` | Hungry Coffin (éventail d'os) |
| `Boss_PaperPlane` | Eternal Headmistress (avions en papier) |
| `Boss_Ruler` | Eternal Headmistress (coup de règle) |

## Ordre conseillé

Commencer par les ennemis ordinaires du monde 1 : c'est lui qui tourne aujourd'hui en jeu. Il faut donc :
- les 4 gobelins (1 à 4) ;
- la faune (5 à 7) ;
- le Goblin Chief, puis le Grumpy Great Oak.

Viennent ensuite le monde 2, puis le monde 3.
