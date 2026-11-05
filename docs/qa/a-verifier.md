# COHUE — À vérifier en jouant (Cantin)

État au 5 nov. 2026, après la fusion de la vague dev (A02, A03, A05, A06, A10, A11, A12, A13). Les tests automatiques sont déjà passés (résultats : `docs/security/tests-exploits.md`, `docs/qa/mesure-horde.md`). Reste ce qui demande un humain : le ressenti, la coop, le téléphone. Parcours complet : `docs/qa/plan-de-test.md`.

Cocher, et noter tout problème dans la liste de bugs de `plan-de-test.md` §3.

## Ressenti (Studio, Play, solo)

- [ ] **Mouvement** : bunny-hop, glissade, glissade en pente agréables au clavier, à la manette et au tactile ; jamais ramené en arrière en jouant normalement.
- [ ] **Mouvement par classe** : double saut (Rogue), saut haut (Archer), plané (Mage, pas encore testé en automatique), atterrissage lourd (Guardian).
- [ ] **Caméra** : 3e personne assez reculée pour lire la horde, ne traverse pas les murs, sensibilité réglable.
- [ ] **Ennemis v2** : les bonnes espèces dans chaque monde (blocs provisoires tant que les modèles manquent).
- [ ] **Comportements spéciaux** : shaman qui soigne, bomber qui explose et vole de l'XP, banshee qui ralentit, gravedigger qui surgit, bloater qui laisse une nappe, poltergeist qui tire en éventail.
- [ ] **Capture** : ennemi capturable, cage au sol 10 s, 2 s dedans, interrompue si touché ; la créature suit et attaque à la run suivante.
- [ ] **Tamer** : 2 compagnons, capture plus rapide.
- [ ] **Run complète** : 3 mondes enchaînés, Overtime, Victory, Cash out et Keep going, écran de fin.

## Demande un réglage ou un objet avant d'être testable

- [ ] **Classements et sauvegarde v2** : activer « Studio access to API services » (paramètres du jeu), puis quitter et revenir : collection, classes, records conservés.
- [ ] **Boutique et pass** : après création des produits sur Roblox (ids encore à `0`).
- [ ] **Sons et musique d'Overtime** : après les sons de Clément (liste : `docs/dossier/90-son.md`).
- [ ] **Assemblage des mondes et portails** : après les tuiles et portails de Clément (`docs/dossier/21-tuiles-assemblage.md`).
- [ ] **Tremplins, geysers, tyroliennes** : après leur pose dans la map (dossier 50 §11).

## Coop et téléphone

- [ ] **Coop à 2-4** (Studio, onglet Test, plusieurs joueurs) : à terre et relève, choix de carte en coop, et le test T6 de `tests-exploits.md` (se téléporter puis mourir : réapparaître près de la position d'avant).
- [ ] **Téléphone** : procédure de `docs/qa/mesure-horde.md` §3 (FPS et réseau de 100 à 400 ennemis). Point à surveiller : 31 Ko/s par joueur à 300 ennemis (PERF-01).
