# COHUE — Checklist de lancement (A13-06)

Agent A13, 5 nov. 2026. On coche chaque ligne avant de rendre le jeu public. Sources Roblox lues le 5 nov. 2026.

## 1. Public 9-15 ans (Roblox Select)

- [ ] Questionnaire de maturité **rempli en entier** (obligatoire pour Kids et Select) : Publish settings > Content rating ([Content maturity](https://create.roblox.com/docs/production/promotion/content-maturity)).
- [ ] Label obtenu Minimal ou Mild (Select 9-15 et Kids 5-8), ou Moderate (Select 9-15 et 16+). Sans label, Roblox restreint le jeu (idem).
- [ ] Exigences de publication en plus pour Kids et Select relues sur la page liée « kids-and-select » (pas encore lue par A13).
- [ ] Violence cartoon seulement : pas de sang, KO en briques (`01-decisions-v2.md` §6-7).
- [ ] Chat et pings : seulement le chat Roblox filtré ; aucun texte libre affiché sans `TextService` (PingService n'envoie que des kinds, à vérifier).
- [ ] Aucun lien externe, aucune demande d'info personnelle.

## 2. Monétisation (100 % cosmétique)

- [ ] Aucun produit ne donne de stat, de résurrection, de classe ou de monnaie (`01-decisions-v2.md` §9 ; `shared/Config/Products.luau:2-3`).
- [ ] **Aucun objet aléatoire payant**. S'il en apparaît un un jour : le déclarer dans le questionnaire et le bloquer avec `PolicyService` (`ArePaidRandomItemsRestricted`) ([Content maturity](https://create.roblox.com/docs/production/promotion/content-maturity)).
- [ ] Pas de message pressant ni de compte à rebours d'achat visant les enfants ([Monetization](https://create.roblox.com/docs/production/monetization)).
- [ ] Ids de produits et pass réels à la place des `0` (`ARCHITECTURE.md` §1), prix affichés depuis `MarketplaceService`.
- [ ] Un seul `ProcessReceipt` (`server/Services/MonetizationService.luau:6`), testé : achat, déconnexion pendant l'achat, reçu rejoué → pas de double don, pas de perte.
- [ ] Le pass VIP serveur privé marche ; le pass saisonnier ne donne que du cosmétique.

## 3. Textes en anglais

- [ ] Tout texte visible est en anglais (`01-decisions-v2.md` §1). Relevé du 5 nov. : `shared/Config/UI.luau:459` a encore un `fr` en français (le champ `en` existe ; vérifier que l'UI lit `en`).
- [ ] Nom anglais définitif choisi (COHUE est un nom de travail) ; aucun nom de Megabonk ou PokeBonk.
- [ ] Description du jeu, nom des badges, produits et pass en anglais, sans faute.

## 4. Page du jeu

- [ ] Icône 512×512, lisible en petit sur téléphone.
- [ ] 3 à 5 miniatures 1920×1080 : horde à l'écran, coop à 4, boss, choix de carte, lobby. Aucune image qui imite un autre jeu.
- [ ] Vidéo courte de gameplay (optionnelle).
- [ ] Genre, appareils (téléphone, tablette, PC, console si manette OK), nombre max de joueurs par serveur.

## 5. Technique

- [ ] Plafond d'ennemis mesuré sur téléphone (A13-01, `docs/qa/mesure-horde.md`) et `Balance.MaxEnemies` réglé.
- [ ] `Balance.Debug.ForceAlive = nil`, `Debug.ShowStats` faux hors Studio, `Run.Debug.StudioCommands` sans effet hors Studio.
- [ ] Scripts `tools/perf/*` absents de la place.
- [ ] Bugs B et M de `plan-de-test.md` §3 fermés.
- [ ] Campagne complète du plan de test (P1 à P6) sur Android et iPhone, au commit publié.
- [ ] DataStore : sauvegarde testée en ligne, à la fermeture du serveur (`BindToClose`) et au départ d'un joueur.
- [ ] Classements hebdo : reset lundi 00:00 UTC vérifié.
- [ ] Revue sécurité A11 passée.
