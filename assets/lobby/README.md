# Lobby « Hubbub Village » : objets posés dans COHUE (A01)

Construit le 4 nov. 2026 dans la place `COHUE` (placeId 132257920785923), à la demande de Clément : **rien n'est fabriqué par script au lancement**. Le village existe comme objets dans `Workspace.HubbubVillage`. Le code d'A09 (LobbyService, interfaces) ne fera que s'y brancher.

- Plan suivi : `docs/dossier/65-lobby.md` (A09, validé par Clément).
- Style : `docs/dossier/80-direction-artistique.md`.
- Captures : `assets/style/captures/lobby_*.jpg`.

**Place non sauvegardée au moment de la construction : la session principale doit la sauvegarder.**

## Ce qui est posé

| Zone (Model) | Contenu |
| --- | --- |
| `Ground` | Plateau de 244 × 232 studs, 8 studs d'épaisseur, avec coupe de terrain visible (herbe, terre, argile, roche). Avenue et chemins, place en mosaïque avec une flèche violette vers le portail, pad d'arrivée, porte « HUBBUB VILLAGE », panneau « PORTAL ▲ », 4 bancs |
| `HeroRow` | 8 présentoirs (`Stand_<Classe>`) : socle, bannière de 12 studs à la couleur de la classe, plaque. Knight, Archer et Mage sont figés avec leur vrai équipement de palier 3 (`Assets.Equipment`). Les 5 autres sont gris, avec un cadenas voxel. Repère : une épée flottante |
| `PortalCourt` | Arche de 44 studs (bandes violettes, couronne), tourbillon Neon violet-bleu, 3 pads `Pad_Solo` / `Pad_Friends` / `Pad_Public` avec leurs panneaux, portier gobelin et son drapeau |
| `CritterPen` | Prairie clôturée de 56 × 48, porte à l'est, kiosque, panneau « Do not feed the critters. They bite. », abreuvoir, foin. Repère : une patte |
| `GlamShop` | Boutique de Gob (38 × 36, toit mandarine), vitrine avec 3 mannequins, comptoir, Gob (le gobelin voleur d'XP), réplique « I used to steal XP. Now I sell hats. ». Repère : un chapeau haut-de-forme |
| `HallOfFame` | Tableaux WEEKLY KO et ALL-TIME KO de 18 × 14, podium 1-2-3, socle vide « Your statue here? », pupitre. Repère : un trophée |
| `QuestBoard` | Tableau de liège de 20 × 12, notes épinglées, hibou facteur et sa sacoche, pupitre. Repère : un parchemin « ! » |
| `Edge` | Ceinture d'arbres voxel, falaises étagées au nord (6 à 18 studs, elles ne cachent pas le portail), 2 maisonnettes |

Total : 1 368 objets (792 Parts, 0 script). Budget du dossier 65 : 4 000 au plus.

## Points d'accroche pour A09 (aucun script n'est posé)

| Objet | Où | Rôle |
| --- | --- | --- |
| Attribut `LobbyRole = "Arrival"` | `Ground.ArrivalPad` | Zone d'apparition. Le `SpawnLocation` de la place n'a pas été touché : le spawn est à décider avec A09 et la session principale |
| `LobbyRole = "Pad"` + attribut `Mode` | `PortalCourt.Pad_*` | Pads Solo / Friends / Public |
| `LobbyRole = "PadZone"` | `Pad_*.Zone` | Boîte invisible à interroger avec `GetPartBoundsInBox` (jamais `Touched`) |
| `LobbyRole = "PortalSwirl"` | `PortalCourt.PortalSwirl` | Surface du tourbillon (VFX animé : A07) |
| `ProximityPrompt` `ClassPrompt` | `HeroRow.Stand_*.Mannequin.UpperTorso` | « Try on » ou « See quest ». Le Model du présentoir porte les attributs `ClassId` et `Locked` |
| `CrittersPrompt`, `ShopPrompt`, `LeaderboardsPrompt`, `QuestsPrompt` | Kiosque, comptoir, pupitres | Ouvrent les menus 3, 4, 5 et 6 |
| `LobbyRole = "Leaderboard"` | `HallOfFame.BoardWeekly`, `BoardAllTime` | `Panel.BoardGui` : `Title`, `Subtitle`, cadre vide `Rows` pour les 10 lignes |
| `LobbyRole = "StatueSlot"` | `HallOfFame.StatueSlot1..3` | Emplacements des statues du top 3 de la semaine |
| `LobbyRole = "QuestBoard"` | `QuestBoard.Board` | `Cork.BoardGui.Notes` : cadre vide pour les quêtes du joueur |
| `LobbyRole = "CritterPen"` | `CritterPen` | Zone où se promène la collection (rendu client, A05) |

## Reste à faire

- **Spawn** : brancher l'apparition sur `ArrivalPad` (A09 et la session principale).
- **A07** : rotation lente des repères flottants (fixes si mouvement réduit), tourbillon animé du portail, anneaux de décompte des pads.
- **A02** : lumière diorama.
- **Autour du village** : la grande dalle grise de la place COHUE entoure le plateau. Pour un vrai effet diorama, mieux vaut un vide ou un fond (ciel, mer de nuages).
- **Poses drôles des mannequins** (casque trop grand du Knight, Archer qui vise un pigeon) : à faire avec des poses figées.
- **Gardien du portail** : le dossier prévoit le Gland Grincheux. Un gobelin le remplace en attendant sa version voxel.

## Reconstruire

`assets/lobby/HubbubVillage_build.luau` : coller l'en-tête puis une section `-- @zone` dans la barre de commande de Studio (ou l'exécuter par le MCP). Relancer une section remplace sa zone. Ce fichier n'est jamais chargé par le jeu.
