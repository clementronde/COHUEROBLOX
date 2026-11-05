# Équilibrage du monde 1 (A04-12)

A04, 5 nov. 2026, branche `claude/a04-equilibrage-v4`. Objectif : un joueur moyen bat le monde 1 dans **70 à 80 %** des runs, avec un début de run nerveux (premier niveau en moins de 20 s, une arme en plus avant 1:30).

**Ce rapport vient d'un modèle sur papier, pas d'une partie jouée.** Les chiffres disent dans quel sens et de combien chaque réglage pousse. Ils ne remplacent pas le test en Play (A13-04, section 5).

## 0. En bref

| Classe | Victoires avant | Victoires après (3 graines) | PV restants à la victoire (après) |
| --- | --- | --- | --- |
| Knight | 28 % | 86 à 89 % | 80 % |
| Archer | 9 % | 76 à 79 % | 77 % |
| Mage | 3 % | 66 à 71 % | 80 % |
| **Moyenne** | **13 %** | **≈ 77 %** | |

- Le début de run était déjà nerveux et le reste : niveau 2 à 0:07-0:09, une 2e arme à 0:07-0:09 dans 100 % des runs.
- **Ce qui tuait** : aucun soin régulier dans le jeu (régénération de base 0, pas de PV au sol). Chaque coup s'additionnait pendant 10 min. La plupart des morts tombaient entre 3:00 et 4:00, avec le premier mini-boss.
- **À transmettre à A03** : le mini-boss du monde 1 apparaît avec `elite = true` (`RunManager.spawnMiniBoss`). Ses PV sont donc 900 × `Run.EliteHpMult` 6 = **5 400**, plus que le boss du monde (5 000). Il vit environ 50 s et fait encore 20 à 27 % des dégâts reçus après réglages. Sans mini-boss, le modèle donne 89 à 98 % de victoires.
- Le Knight reste la classe la plus facile (parade). C'est la classe par défaut ; l'écart est passé de 25 à environ 15 points.

## 1. Le modèle et le joueur moyen

`bash tools/tests/a04-balance.sh [runs] [graine] ["variante"]` (luau CLI, hors Studio, environ 2 s pour 600 runs). Le script charge **les vraies configs du dépôt** (`Weapons`, `Grimoires`, `Cards`, `Run`, `Balance`, `Enemies`, `Items`, `Bosses`, `Worlds`, `Rarities`, `Loot`) : un réglage changé dans `shared/Config` change le résultat sans rien recopier. Le 3e argument sert à essayer un réglage ou un autre joueur sans toucher aux fichiers (`"Run.MiniBossAt = {}"`, `"AVG.exposure = 0.05"`).

Pas de 0,5 s, 10 min puis le boss. Ce qui vient du code :

- **Densité** : `Balance.DensityCurve`, vagues de `Run.Waves` (taille et boost), `PhaseDensity` pendant le boss, Overtime après 10:00.
- **Mélange** : `SwarmShare` 0,8, `FamilyUnlock`, roster et variantes de `Worlds.BoisGrognon`. PV, XP et dégâts moyens de la population à chaque instant.
- **Élites** (1re à 1:30 puis toutes les 75 s, PV × 6, XP × 5) et **mini-boss** à 3:00 et 7:00 (PV × `EliteHpMult`, comme le code).
- **XP** : `Enemies[].xp`, `Cards.xpToNext`, `XpGain`.
- **Cartes** : tirage de `CardService` (pool pondéré, rareté par `Rarities.roll` avec la Chance, 25 % de cartes de compagnon, garantie Rare du Mage toutes les 5 offres). Le jeu se fige pendant le choix, donc le choix ne coûte pas de temps.
- **Stats** : base + Runes + objets + passif par niveau, plafonds de `Grimoires.StatCaps`.
- **Armes** : dégâts × (1 + Damage + bonus de carte + Valor) × dmgMult ; recharge × (1 − Cooldown) / (1 + AttackSpeed) ; Size, Amount, Duration ; crits tirés au sort ; brûlure. Coups par déclenchement selon la forme de l'arme et la densité de la foule (cône, onde, tir perçant, orbite, chaîne, frappe, tourelle). Un coup ne retire jamais plus que les PV d'un ennemi.
- **Dégâts reçus** : comme `RunManager.damagePlayer`, dans l'ordre parade du Knight, esquive, armure K / (K + armure). Contact cumulé, un coup toutes les `ContactCooldown` s.
- **Boss** : `Bosses.List.GrandCheneRonchon`, attaques de phase 1 seulement (`PhaseEnabled = false`).

**Le joueur moyen** (table `AVG` en tête du `.luau`, ce sont des hypothèses) :

| Hypothèse | Valeur | Ce que ça veut dire en jeu |
| --- | --- | --- |
| Contact subi | 4 % du maximum (3 ennemis collés en permanence) | environ 1 contact toutes les 15 s à 1:00, toutes les 5 s à 9:00 |
| Tirs ennemis qui touchent | 12 % (tireurs assez près : 25 %) | les plumes et flèches sont lentes et lisibles |
| Sauts de Jumper qui touchent | 25 % | |
| Bombers qui explosent sur lui | 30 % de ceux qui arrivent | |
| Attaques de boss esquivées | 60 % (anneaux sautés : 70 %) | annonce de 1 s |
| Collé à une grosse cible lente | 3 % du temps (moitié moins avec une arme de départ à distance) | élite, mini-boss, boss |
| À portée de la frappe du mini-boss | 20 % du temps | |
| XP ramassée | 90 % | |
| Choix de carte | 20 % au hasard, sinon : nouvelle arme tant qu'il en a moins de 3, puis amélioration d'arme, puis Runes (Damage, Attack Speed, Vitality, Area, Projectiles…) | |
| Coffres | 3 (2:30, 5:00, 7:30), un objet à stats chacun | les objets à effet ne sont pas modélisés |
| Marchand | 1 soin (35 %) à 5:30 si PV < 70 % | |
| Boss | combat lancé à 9:30, perdu s'il dure plus de 5 min | |
| Compagnon | Braise, 7 dps mono-cible, +15 % par carte de compagnon | |

**Limites** : pas de déplacement réel ni de carte ; les objets à effet, les autels, les dangers (brouillard), le recul et les statuts de contrôle ne comptent pas ; le contact est une moyenne. Le modèle est fait pour comparer des réglages entre eux, pas pour prédire un pourcentage exact.

## 2. Résultats avant / après (200 runs par classe, graine 12)

Sorties complètes : [`equilibrage-monde1-avant.txt`](equilibrage-monde1-avant.txt), [`equilibrage-monde1-apres.txt`](equilibrage-monde1-apres.txt).

### Paliers de niveau (médiane, identiques à quelques secondes près pour les 3 classes)

| Niveau | 2 | 5 | 10 | 15 | 20 | 25 | 30 | Niveau final |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Avant | 0:08 | 0:33 | 1:21 | 2:20 | 3:31 | 4:42* | — | 20-25 (morts) |
| Après | 0:08 | 0:35 | 1:31 | 2:43 | 4:03 | 5:34 | 7:21 | 35 |

\* Knight seulement : les autres classes étaient déjà mortes.

### Par classe

| | Knight avant | Knight après | Archer avant | Archer après | Mage avant | Mage après |
| --- | --- | --- | --- | --- | --- | --- |
| Victoires | 28 % | 89 % | 9 % | 76 % | 3 % | 68 % |
| Mort (médiane) | 4:07 | 8:12 | 3:38 | 8:39 | 3:36 | 8:27 |
| PV restants à la victoire | 55 % | 80 % | 60 % | 77 % | 25 % | 80 % |
| 2e arme | 0:09 | 0:09 | 0:08 | 0:08 | 0:07 | 0:07 |
| Boss tué en | 0:09 | 0:10 | 0:08 | 0:07 | 0:08 | 0:10 |

Dégâts reçus après réglages, par source : contact 30-36 %, tirs 31-39 %, mini-boss 17-27 %, boss 7-11 %, le reste moins de 2 %.

### Sensibilité (après réglages, graine 12)

| Variante du joueur | Knight | Archer | Mage |
| --- | --- | --- | --- |
| Référence | 89 % | 76 % | 68 % |
| Plus habile (contact 3 %) | 92 % | 84 % | 81 % |
| Moins habile (contact 5 %) | 79 % | 69 % | 64 % |
| Esquive mal les tirs (18 %) | 71 % | 54 % | 59 % |
| Esquive mal le boss (40 %) | 85 % | 70 % | 63 % |
| Choisit ses cartes à moitié au hasard | 74 % | 67 % | 56 % |
| Sans mini-boss | 98 % | 96 % | 89 % |

Les tirs ennemis et le mini-boss sont les deux points où l'habileté du joueur pèse le plus.

## 3. Réglages (avec leur raison)

| Fichier | Réglage | Avant → après | Pourquoi |
| --- | --- | --- | --- |
| `Config/Grimoires` | `BaseStats.MaxHp` | 100 → 140 | Marge pour les pics (mini-boss, vagues). Repère d'A03 pour les attaques du boss : ~130 PV à la fin du monde 1 |
| `Config/Grimoires` | `BaseStats.Regen` | 0 → 0,5 PV/s | Aucun soin régulier dans le jeu : sans régénération, tout coup reçu était perdu pour la run. Rend ~300 PV par monde |
| `Config/Grimoires` | Rune Vitality, `Regen` par niveau | 0,1 → 0,2 (texte mis à jour) | 0,1 ne se voyait plus à côté de la base 0,5 |
| `Config/Run` | `Player.ContactCooldown` | 0,5 → 0,75 s | Le contact (foule, mini-boss à 22 par coup) faisait 30 à 45 % des dégâts ; 0,75 s laisse le temps de sortir de la mêlée sans toucher à la horde |
| `Config/Run` | `Player.BaseMaxHp` | 100 → 140 | Repli seulement (les PV viennent de la stat MaxHp) : aligné |
| `Config/Enemies` | Contact de Goblin Grunt et Grumpy Acorn (essaim) | 6 → 5 | Le contact de la foule était la 1re source de dégâts |
| `Config/Enemies` | `shotDamage` de Goblin Archer et Diving Owl | 9 → 6 | Les tireurs restent hors de portée de mêlée et faisaient ~30 % des dégâts |
| `Config/Cards` | `Xp.Quad` | 0,35 → 0,6 | Les KO suivent l'arrivée des ennemis, pas les dégâts du joueur : il montait au niveau ~40, soit 40 pauses de carte par joueur et par monde (lourd en coop, tout le monde se fige). Avec 0,6 : ~35, et les 10 premiers niveaux ne bougent presque pas |
| `Config/Weapons` | Fire Staff | 14 dég / 1,4 s → 13 dég / 1,0 s | Le tir lent laissait la foule au contact : le Mage était la classe gratuite la plus fragile |
| `Config/Weapons` | Knight, `parryEvery` | 8 → 15 s (texte mis à jour) | La parade bloque un coup entier (contact cumulé, mini-boss, boss). À un coup toutes les 5 à 15 s, elle en bloquait 40 à 60 % : le Knight avait 25 points d'avance |

Pas touché : lignes boss et mini-boss d'`Enemies` et `Bosses` (A03), `Config/Loot`, les services. `docs/dossier/10-combat-armes-grimoires-objets.md` suit les nouveaux chiffres.

## 4. Ce que le modèle montre en plus (pour plus tard)

1. **Mini-boss à 5 400 PV** (A03 ou A04 sur `RunManager`) : `spawnMiniBoss` passe `elite = true`, donc PV × 6 et l'aura d'élite. Si c'est voulu, il faut le dire dans le dossier 13. Sinon, `elite = false` ou des PV propres au mini-boss. **Les réglages ci-dessus sont faits avec le mini-boss tel qu'il est** : s'il passe à 900 PV, refaire tourner le modèle (sans lui, on passe à 89-98 %).
2. **Le boss meurt en ~10 s** au niveau ~35 (5 000 PV face à plusieurs centaines de dps mono-cible). Ça ne pèse pas sur le taux de victoire, mais ce n'est pas un combat. À voir avec A03 (PV du boss ou part de ses PV face aux armes de zone).
3. **Les ennemis du monde 1 ne gagnent pas de PV pendant les 10 min** (10 à 14 PV, tués en un coup dès 1:00). Le danger ne vient que du nombre et des coups reçus. Une montée douce des PV avec le temps rendrait les cartes de dégâts utiles au monde 1. Elle demande un réglage dans `EnemyService` (contract request).
4. **Pas de soin au sol** : `Loot.PotTable` n'a pas de résultat « soin ». Un petit soin dans les pots, courant dans le genre, permettrait de redescendre la régénération de base. Domaine butin.

## 5. Les 5 réglages à vérifier en jouant (A13-04)

1. **Le premier mini-boss (3:00)** : combien de PV perd un joueur moyen pendant qu'il est en vie, et combien de temps il vit. Le modèle dit ~50 s et 60 à 90 PV ; c'est le point le plus incertain.
2. **Régénération 0,5 PV/s** : on doit la sentir entre deux vagues, sans rendre le joueur intouchable. Si un enfant reste immobile au milieu de la horde sans mourir, c'est trop.
3. **Contact toutes les 0,75 s** : vérifier qu'un joueur encerclé ne se sent pas « invincible » et que les coups restent lisibles (flash, son).
4. **Tirs des Goblin Archer et Diving Owl à 6** : compter les tirs reçus par minute à 5:00 et 9:00. Le modèle suppose 12 % de tirs qui touchent ; à 18 %, l'Archer tombe à 54 %.
5. **Nombre de niveaux (Quad 0,6)** : niveau atteint à 10:00 (cible ~35) et confort des pauses en coop à 4 joueurs. Premier niveau sous 20 s et 2e arme avant 1:30 à revérifier.

Pour chaque test : classe, durée de vie, cause de la mort, niveau à 5:00 et à 10:00. Avec 10 runs par classe, on peut comparer au tableau de la section 2.
