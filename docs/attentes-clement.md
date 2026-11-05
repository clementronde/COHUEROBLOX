# COHUE — Ce qui attend Clément

Liste unique de ce que le côté technique (Ironix et ses agents) attend du côté créatif (Clément et ses agents). Tenue à jour par Ironix : chaque fois qu'une tâche dev attend un objet, un son ou une décision de Clément, une ligne est ajoutée ici. Les noms exacts sont dans le dossier cité : c'est par ce nom que le code trouve l'objet (règles : `docs/dossier/01-decisions-v2.md` §12 et §13).

**Pour Clément et son Claude** : quand un point est fait, passe sa case à `[x]` et pousse ; Ironix retire la ligne après vérification en jeu. Un objet manquant ne casse rien : le jeu affiche un repli ou rien, et la console l'indique une fois (`template "..." missing`, `Sound "..." introuvable`).

Dernière mise à jour : 5 nov. 2026.

## Objets à poser dans Studio

| Fait | Quoi | Où le poser | Noms exacts et détails | Bloque |
| --- | --- | --- | --- | --- |
| [ ] | Modèles des 16 ennemis v2 | `ReplicatedStorage.Assets` (voir la décision « un seul dossier » plus bas) | `docs/dossier/13-ennemis-boss.md` §11.1 (`Enemy_GoblinGrunt`, `Enemy_ZombieRunner`…) | A03 : ennemis visibles (blocs provisoires sinon) |
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
| [ ] | Porte 2 : planche concept des ennemis, et écarts au guide DA (zombies gris, théière du Shaman, yeux des fantômes, couleur du sauteur) | `13-ennemis-boss.md` §10 | — |
| [ ] | Nom du monde 2 (proposition : *Soggy Graves*) | `13-ennemis-boss.md` §3 | Id `DunesCroustillantes` gardé |
| [ ] | Compagnon de départ, Ultime, capture en coop, vitesse de capture du Tamer | `40-compagnons.md` §11 | Collection vide, pas d'Ultime, une capture par joueur, 1,33 s |
| [ ] | Les points à confirmer du suivi | `COHUE — Suivi de production.md`, section « Points à confirmer » | Propositions appliquées |
