# COHUE — Mesure du plafond d'ennemis (A13-01, procédure)

Agent A13, 5 nov. 2026. A13 a écrit les scripts. **Le chef de projet lance la mesure dans Studio, et Cantin fait la mesure sur téléphone.** Le résultat fixe `Balance.MaxEnemies`, aujourd'hui à 300 (`shared/Config/Balance.luau:8`, `01-decisions-v2.md` §2).

## 1. Ce que font les scripts

| Fichier | Où le mettre | Ce qu'il fait |
| --- | --- | --- |
| `tools/perf/HordeStress.server.luau` | un **Script** dans `ServerScriptService` | Attend une run avec des ennemis, puis monte la horde par paliers : 100, 150, 200, 250, 300, 400. À chaque palier : 8 s de remplissage, 20 s de mesure. Relève les ennemis vivants, le Heartbeat serveur, la mémoire serveur, `Stats.DataSendKbps` et une estimation du débit EnemySnapshot du joueur le plus chargé. Remet les réglages comme avant à la fin |
| `tools/perf/HordeStressClient.client.luau` | un **LocalScript** dans `StarterPlayer.StarterPlayerScripts` | Pendant chaque mesure : FPS moyen, 1 % low, image la plus lente, mémoire (totale, textures, mailles, Lua), `Stats.DataReceiveKbps`, triangles, appels de rendu, ennemis dessinés |

Les deux écrivent une ligne par palier dans la sortie (préfixe `[A13]`), puis un tableau Markdown à coller dans le rapport.

Les scripts sont dans `tools/`, hors des dossiers chargés par `tools/studio-load.luau` : ils n'entrent jamais dans le jeu par accident. Ils ne modifient aucun fichier du jeu. Pendant le test seulement, ils changent en mémoire `Balance.Debug.ForceAlive` et `Balance.MaxEnemies` (le palier de 400 a besoin d'un plafond plus haut, voir QA-01), et soignent les joueurs 5 fois par seconde pour qu'ils restent en vie.

Pourquoi un Script et pas la barre de commande : un module requis depuis la barre de commande peut être une autre copie que celle du jeu. Un Script dans `ServerScriptService` tourne dans la même machine Luau que les services, donc `Balance` et `Registry` sont les mêmes tables.

## 2. Mesure dans Studio (chef de projet)

1. Ouvrir une **copie** de travail de la place, ou la place COHUE en Play seulement : les deux scripts ne doivent **jamais** être publiés. Les retirer avant toute sauvegarde dans Team Create.
2. Coller `HordeStress.server.luau` dans un Script `ServerScriptService.A13HordeStress`, et `HordeStressClient.client.luau` dans un LocalScript `StarterPlayer.StarterPlayerScripts.A13HordeStressClient`.
3. Onglet Test > Device : choisir un téléphone (paysage). Ce n'est pas la perf d'un vrai téléphone, mais ça donne la taille d'écran et le palier de qualité Low de WeaponFX.
4. Play, choisir une classe, lancer une run **solo**. Le script démarre dès que des ennemis existent (3 min max pour lancer la run).
5. Pendant la mesure, **ne pas bouger** (les ennemis se massent autour du joueur : c'est le pire cas réseau). Choisir les cartes de niveau tout de suite : en solo, le jeu attend le choix.
6. À la fin (environ 3 min), copier les deux tableaux de la sortie (`[A13] fin.` et `[A13 client] fin.`) dans le rapport A13-01.
7. Recommencer à 4 joueurs : Test > Clients and Servers > 4 joueurs. Le tableau serveur donne alors le coût d'un serveur plein.
8. Stop. Supprimer les deux scripts.

Pendant le palier de 300, ouvrir aussi le MicroProfiler (Ctrl+Alt+F6) et faire une capture : elle montre ce qui coûte dans `PreRender` (EnemyRenderer, WeaponFX) ([MicroProfiler](https://create.roblox.com/docs/studio/microprofiler)).

## 3. Mesure sur un vrai téléphone (Cantin)

Le vrai chiffre vient d'ici. Studio sur PC ne dit rien de la perf d'un téléphone.

**Téléphone cible** : un Android milieu de gamme de 2 à 3 ans (ex. Samsung Galaxy A-series, 4 Go de RAM). En plus si possible : un iPhone de 4 à 5 ans (iPhone 11 ou SE 2e génération).

1. Faire une **copie privée** de la place (Fichier > Save to Roblox As…, une nouvelle expérience privée). Ne jamais mettre les scripts dans la place COHUE partagée.
2. Dans la copie, coller les deux scripts comme en section 2. Dans `HordeStress.server.luau`, passer `ALLOW_LIVE = true` (sans ça, le script ne fait rien hors Studio).
3. Publier la copie. Sur le téléphone : batterie > 50 %, mode économie d'énergie coupé, Wi-Fi, appli Roblox à jour, aucune autre appli ouverte. Graphismes de Roblox en **automatique** (c'est ce qu'ont les joueurs).
4. Rejoindre la copie depuis le téléphone, lancer une run solo, ne pas bouger, choisir les cartes vite.
5. Lire les résultats :
   - en haut à gauche, le petit texte du script client donne le dernier palier ;
   - la console (ouvrir le chat et taper `/console`) montre les lignes `[A13 client]` dans l'onglet Log côté client, et `[A13]` côté serveur ;
   - photographier ou recopier les deux tableaux de fin.
6. Refaire la mesure une 2e fois après 10 min de jeu (téléphone chaud) : les FPS d'un téléphone chaud baissent souvent.
7. Si possible, une 3e fois en 4G.
8. Supprimer la copie privée ou retirer les scripts.

Pour aller plus loin sur le téléphone : Paramètres de Roblox > MicroProfiler On, puis ouvrir dans un navigateur du PC l'adresse IP et le port affichés ([MicroProfiler](https://create.roblox.com/docs/studio/microprofiler)).

## 4. Lire le résultat

Le plafond retenu est le **plus haut palier** qui passe toutes les lignes ci-dessous **sur le téléphone cible, téléphone chaud** :

| Mesure | Seuil | Budget |
| --- | --- | --- |
| FPS moyen | ≥ 45 | `budgets-perf.md` §2 |
| 1 % low | ≥ 30 | idem |
| Mémoire client | ≤ 1 200 Mo | §5 |
| Débit reçu (DataReceiveKbps) | ≤ 50 en moyenne | §3.2 |
| Heartbeat serveur (4 joueurs, Studio) | ≥ 55 Hz | §4 |
| Vivants | ≥ 90 % du palier (sinon le palier n'a pas été atteint) | — |

Ensuite :
- palier retenu ≥ 300 : `MaxEnemies` reste à 300 ;
- palier retenu entre 200 et 250 : `MaxEnemies` descend à ce palier (contract request au propriétaire de `Balance.luau`) et l'Overtime convertit le reste en PV (`EnemyService.luau:337-349`, déjà prêt) ;
- sous 200 : on corrige d'abord PERF-01 à PERF-06 (`plan-de-test.md` §3), puis on remesure.

Le rapport A13-01 donne : le téléphone, la version de Roblox, le commit testé, les tableaux bruts, le palier retenu, et le poste le plus cher vu dans le MicroProfiler.

## 5. Si le compte ne monte pas

Le script prévient quand un palier n'atteint pas 90 % de sa cible. Causes possibles :

- **La run n'est plus active** (joueur mort, boss tué, retour au lobby) : la horde n'apparaît que pendant une run (`EnemyService.luau:590`). Relancer.
- **Le jeu attend un choix de carte** : choisir la carte.
- **Les armes tuent plus vite que la horde n'apparaît** (10 par tick, `Balance.luau:9`) : au palier de 400, un Mage avec beaucoup de zones peut garder le compte bas. Refaire avec une classe de départ sans montée de niveau (choisir « Skip » aux cartes).
