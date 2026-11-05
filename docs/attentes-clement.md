# COHUE — Ce qui attend Clément

Liste unique de ce que le côté technique (Ironix et ses agents) attend du côté créatif (Clément et ses agents). Tenue à jour par Ironix : chaque fois qu'une tâche dev attend un objet, un son ou une décision de Clément, une ligne est ajoutée ici. Les noms exacts sont dans le dossier cité : c'est par ce nom que le code trouve l'objet (règles : `docs/dossier/01-decisions-v2.md` §12 et §13).

**Pour Clément et son Claude** : quand un point est fait, passe sa case à `[x]` et pousse ; Ironix retire la ligne après vérification en jeu. Un objet manquant ne casse rien : le jeu affiche un repli ou rien, et la console l'indique une fois (`template "..." missing`, `Sound "..." introuvable`).

Dernière mise à jour : 5 nov. 2026 (soir), après la vague 3 (A00, A03, A04, A05, A12).

## Objets à poser dans Studio

| Fait | Quoi | Où le poser | Noms exacts et détails | Bloque |
| --- | --- | --- | --- | --- |
| [ ] | **Urgent** : télégraphes et tir par défaut des ennemis | `ReplicatedStorage.Assets.FX.Enemies` | `Telegraphs.Circle`, `Telegraphs.Ring`, `Telegraphs.Line`, `Projectiles.Default` (`13-ennemis-boss.md` §11.4) | A03 : sans eux, les attaques arrivent sans annonce et les tirs sont invisibles |
| [ ] | Autres tirs, marques d'élite, imposteur lointain | `ReplicatedStorage.Assets.FX.Enemies` | `Projectiles.Arrow`, `Projectiles.Feather`, `Projectiles.DirtClod`, `Projectiles.Book`, `EliteRing`, `EliteCrown`, `Impostor` (§11.4) | A03 : rien n'est dessiné sinon |
| [ ] | Effets des boss | `ReplicatedStorage.Assets.FX.Bosses` | `HungryCoffin.Bone`, `EternalHeadmistress.PaperPlane`, `WeakPoint`, `ArcheBeam` (§9.2 et §11.4) | A03 : attaques de boss invisibles |
| [ ] | Modèles des 21 ennemis, mini-boss et boss v2, plus un modèle de remplacement | `ReplicatedStorage.Assets.Creatures` | `13-ennemis-boss.md` §9.1 et §11.1 (`Enemy_GoblinGrunt`, `Enemy_ZombieRunner`…) et `Enemy_Placeholder` | A03 : aujourd'hui seuls les 4 gobelins existent ; la faune, les zombies et les fantômes utilisent les anciens modèles (`legacyAsset` dans `Config/Enemies`), un ennemi sans modèle ni placeholder n'est pas dessiné |
| [ ] | Effets des comportements ennemis (préparation, aura, explosion, nappe, atterrissage) | `ReplicatedStorage.Assets.FX` | `13-ennemis-boss.md` §11.3 | A03 : rendus provisoires sinon |
| [ ] | Aura et icône des capturables | `ReplicatedStorage.Assets.FX` | `FX_CaptureRing`, `FX_CaptureIcon` (`13-ennemis-boss.md` §11.2) | A03-03 |
| [ ] | Cage de capture, éclat de réussite, étoiles, impact de compagnon | `ReplicatedStorage.Assets.FX` | `FX_CaptureCage` (12 studs de large), `FX_CaptureSuccess`, `FX_CompanionStun`, `FX_CompanionHit` (`40-compagnons.md` §8) | A05 : capture invisible |
| [ ] | Modèles des compagnons | `ReplicatedStorage.Assets.Creatures` | `Companion_<espèce>` (`40-compagnons.md` §8) ; sinon le modèle `Enemy_<espèce>` sert de repli | A05 |
| [ ] | Tous les sons et musiques | `ReplicatedStorage.Assets.Sounds` (sous-dossiers libres) | Liste complète : `docs/dossier/90-son.md` §4 (`Music_BoisGrognon`, `SFX_XpPickup`, `UI_CardOffer`…) | A10 : jeu muet |
| [ ] | Tuiles des mondes (avec leurs attributs) | `ReplicatedStorage.Assets.Worlds.<monde>` | `docs/dossier/21-tuiles-assemblage.md` §2.2 et §8 | A02 : ancienne carte en Parts sinon |
| [ ] | Gabarits de portail | `ReplicatedStorage.Assets` | `PortalNextWorld`, `PortalCashOut`, disque d'environ 8 à 10 studs de rayon (`21-tuiles-assemblage.md` §7.1) | A02-08 |
| [ ] | Écran de transition entre mondes | `StarterGui` | ScreenGui `WorldTransition` > Frame `Fade` > TextLabel `Title` (`21-tuiles-assemblage.md` §7) | A02-08 : pas de fondu sinon |
| [ ] | Tremplins, geysers, tyroliennes posés dans la map | Map des mondes | Fiche : `docs/dossier/50-classes-avatar-mouvement.md` §11 | A06-07 |
| [ ] | Animations : 5 gestes d'attaque et geste de capture (A06-06) | Publiées sur Roblox, ids notés dans le dossier | `50-classes-avatar-mouvement.md` §4 (« Pas encore faits ») | Attaques sans geste |
| [ ] | UI de fin de run et de Victory : « Cash out » envoie `VictoryChoice("CashOut")`, « Keep going » `VictoryChoice("KeepGoing")`, barre de progression par joueur ; bouton Lobby de l'écran de fin envoie `ReturnToLobby` | `VictoryBanner`, `EndScreen` | Rapport A04 v3 ; remotes dans `shared/Net.luau` | A04 : boutons sans effet |
| [ ] | HUD et thème : lire l'attribut joueur `InRun` (au lieu de la phase globale) ; vue d'attente coop du passage de niveau (L04c) avec `LevelUpPause` | `HUD`, `UITheme.inRun()`, `CardUI` | `60-ui-ux.md` (contrat `LevelUpPause`) | A04 : HUD de run affiché au lobby |
| [ ] | UI des données : ids de classe v2 (`Knight`…) dans `Config.UI` (`ClassOrder`, `FreeClasses`), `LoadoutUI`, `LobbyController` ; afficher `Profile.bestKills` (HUD), `RunSummary.weeklyRank` (écran de fin, « — » si vide), `Profile.classes` (menu Classes) | `client/Controllers/UI/*`, `client/Controllers/Lobby/*` | `70-donnees-progression-monetisation.md` §1, §13, §16 | Marche encore avec les ids v1 ; record et rang non affichés |
| [ ] | (Option) Part `CritterRoam` dans l'enclos du lobby pour délimiter la promenade des compagnons | Map du lobby, enclos `LobbyRole = "CritterPen"` | `40-compagnons.md` | Sinon la Part `Meadow` sert de zone |
| [ ] | UI de capture : états `Refused` (« Collection full for this run », « Can't save right now ») et « NEW! » ; cages sur la minimap | `StarterGui` (CaptureUI, Minimap) | `40-compagnons.md` §10 (demandes à A08) | A05 : messages absents |

## Sur Roblox (Creator Dashboard, propriétaire du jeu)

| Fait | Quoi | Détails | Bloque |
| --- | --- | --- | --- |
| [ ] | Créer les game passes et produits de la boutique | Liste et prix : `docs/dossier/70-donnees-progression-monetisation.md` §9 ; ids à reporter dans `shared/Config/Products.luau` (aujourd'hui `0`) | A12-04 : boutique inactive |
| [ ] | Activer « Studio access to API services » | Paramètres du jeu > Sécurité | Classements et sauvegarde testables en Studio |

## Décisions attendues

| Fait | Question | Où | Défaut appliqué en attendant |
| --- | --- | --- | --- |
| [ ] | Un seul dossier de modèles (`Assets.Creatures`) ou garder `EnemyVisualRigs` / `EnemyVisualMeshes` ? | `13-ennemis-boss.md` §6 et §9 (point 7) | Le code cherche dans `Assets` puis `EnemyVisualRigs` |
| [ ] | Cash out automatique au bout d'un délai après la Victory, ou seulement par le bouton et le portail ? | Rapport A04 v3, `20-run-mondes-boss.md` | Pas de minuterie : chacun part par le bouton ou le portail, le dernier termine la run |
| [ ] | Porte 2 : planche concept des ennemis, et écarts au guide DA (zombies gris, théière du Shaman, yeux des fantômes, couleur du sauteur) | `13-ennemis-boss.md` §10 | — |
| [ ] | Nom du monde 2 (proposition : *Soggy Graves*) | `13-ennemis-boss.md` §3 | Id `DunesCroustillantes` gardé |
| [ ] | Compagnon de départ, Ultime, capture en coop, vitesse de capture du Tamer | `40-compagnons.md` §11 | Collection vide, pas d'Ultime, une capture par joueur, 1,33 s |
| [ ] | Les points à confirmer du suivi | `COHUE — Suivi de production.md`, section « Points à confirmer » | Propositions appliquées |
